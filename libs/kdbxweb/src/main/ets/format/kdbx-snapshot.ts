import { Kdbx } from './kdbx';
import { KdbxContext } from './kdbx-context';
import { KdbxCredentials } from './kdbx-credentials';
import { KdbxHeader } from './kdbx-header';
import {
    KdbxBinary,
    KdbxBinaryDiskRef,
    KdbxBinaryWithHash
} from './kdbx-binaries';
import { ProtectedValue } from '../crypto/protected-value';
import { KdbxError } from '../errors/kdbx-error';
import { CrsAlgorithm, ErrorCodes } from '../defs/consts';
import { AttachmentStore } from '../utils/attachment-store';
import { BinaryStream } from '../utils/binary-stream';
import {
    arrayToBuffer,
    bytesToHex,
    hexToBytes,
    stringToBytes
} from '../utils/byte-utils';
import * as XmlUtils from '../utils/xml-utils';
import { MemoryChunkReader, KdbxStreamingXmlLoader, SequentialByteReader, SequentialReaderChunkReader } from '../utils/xml-pull-parser';

const SNAPSHOT_MAGIC_0 = 0x4b; // 'K'
const SNAPSHOT_MAGIC_1 = 0x50; // 'P'
const SNAPSHOT_MAGIC_2 = 0x53; // 'S'
const SNAPSHOT_MAGIC_3 = 0x4e; // 'N'
const SNAPSHOT_VERSION_1 = 1;
const SNAPSHOT_VERSION_2 = 2;
const SNAPSHOT_VERSION_3 = 3;
const SNAPSHOT_VERSION = SNAPSHOT_VERSION_2;
const FIXED_HEADER_LENGTH = 18;
/** v3 固定头长度：magic4 + version2 + flags4 + headerLen4 + innerInfoLen4 + poolCount4 + xmlLen4 */
const V3_FIXED_HEADER_LENGTH = 26;
const HASH_LENGTH = 32;
const POOL_ENTRY_HEADER_LENGTH = 4 + 1 + HASH_LENGTH;
const FLAG_PROTECTED = 1;
/** v2：池条目为磁盘引用，只携带 hash+长度，不携带附件字节（P7 治理） */
const FLAG_STORE_REF = 2;
/** v3 容器 flags bit0：xml 区为原始 inner XML（Protected 值为内层流密文，需 innerInfo 解密）；
 * 0 = 明文快照 XML（KPSN v1/v2 buildXml 语义，供合并产物复用） */
const FLAG_V3_RAW_XML = 1;

/**
 * KPSN binary snapshot: in-memory transfer format for passing a database
 * model across thread boundaries without XML/base64 attachment inflation.
 *
 * Layout (all integers little-endian):
 *   [0..4)    magic 'KPSN'
 *   [4..6)    format version (uint16, 1 or 2)
 *   [6..10)   header length (uint32)
 *   [10..14)  xml length (uint32)
 *   [14..18)  pool count (uint32)
 *   header blob: KdbxHeader.write output (version, kdf, cipher, salts)
 *   xml blob: entry tree, attachments as refs only, protected values
 *             as ProtectedInMemPlainXml plaintext (same as saveXml)
 *   pool entries (ordered, index = binary ref):
 *     uint32 dataLength, uint8 flags, 32B sha256, data
 *     flags bit0 = protected
 *     flags bit1 = storeRef (v2): 附件字节留在加密缓存中，
 *       dataLength 为附件字节长度，条目不携带 data
 */
export class KdbxSnapshot {
    static isSnapshot(data: ArrayBuffer): boolean {
        if (!(data instanceof ArrayBuffer) || data.byteLength < FIXED_HEADER_LENGTH) {
            return false;
        }
        const bytes = new Uint8Array(data, 0, 4);
        return (
            bytes[0] === SNAPSHOT_MAGIC_0 &&
            bytes[1] === SNAPSHOT_MAGIC_1 &&
            bytes[2] === SNAPSHOT_MAGIC_2 &&
            bytes[3] === SNAPSHOT_MAGIC_3
        );
    }

    static save(kdbx: Kdbx): Promise<ArrayBuffer> {
        return kdbx.credentials.ready.then(() => {
            const ctx = new KdbxContext({ kdbx });
            ctx.exportXml = false;
            ctx.snapshot = true;
            try {
                kdbx.buildXml(ctx);
            } finally {
                ctx.snapshot = false;
            }
            if (!kdbx.xml) {
                throw new KdbxError(ErrorCodes.InvalidState, 'no xml');
            }
            XmlUtils.unprotectValues(kdbx.xml.documentElement);
            const xml = XmlUtils.serializeToStringFast(kdbx.xml);
            XmlUtils.protectUnprotectedValues(kdbx.xml.documentElement);
            kdbx.xml = undefined;

            const headerStm = new BinaryStream();
            // header.write 校验要求 salts 存在（新建未落盘的模型没有），
            // 与 KdbxFormat.save/saveXml 保持同一语义；下次加密保存会重新生成，无保真影响
            kdbx.header.generateSalts();
            kdbx.header.write(headerStm);
            const headerData = headerStm.getWrittenBytes();
            const xmlData = arrayToBuffer(stringToBytes(xml));

            const pool = kdbx.binaries.getAllWithHashes();
            const payloads: Array<ArrayBuffer | undefined> = [];
            let totalLength = FIXED_HEADER_LENGTH + headerData.byteLength + xmlData.byteLength;
            for (const item of pool) {
                const payload = KdbxSnapshot.getPoolPayload(item.value, kdbx.binaries.store);
                payloads.push(payload);
                totalLength += POOL_ENTRY_HEADER_LENGTH + (payload ? payload.byteLength : 0);
            }

            const out = new ArrayBuffer(totalLength);
            const view = new DataView(out);
            const bytes = new Uint8Array(out);
            bytes[0] = SNAPSHOT_MAGIC_0;
            bytes[1] = SNAPSHOT_MAGIC_1;
            bytes[2] = SNAPSHOT_MAGIC_2;
            bytes[3] = SNAPSHOT_MAGIC_3;
            let pos = 4;
            view.setUint16(pos, SNAPSHOT_VERSION, true);
            pos += 2;
            view.setUint32(pos, headerData.byteLength, true);
            pos += 4;
            view.setUint32(pos, xmlData.byteLength, true);
            pos += 4;
            view.setUint32(pos, pool.length, true);
            pos += 4;
            bytes.set(new Uint8Array(headerData), pos);
            pos += headerData.byteLength;
            bytes.set(new Uint8Array(xmlData), pos);
            pos += xmlData.byteLength;
            for (let i = 0; i < pool.length; i++) {
                const hashBytes = hexToBytes(pool[i].hash);
                if (hashBytes.length !== HASH_LENGTH) {
                    throw new KdbxError(ErrorCodes.FileCorrupt, 'bad binary hash');
                }
                const value = pool[i].value;
                const payload = payloads[i];
                let flags = 0;
                let dataLength: number;
                if (payload === undefined) {
                    // 磁盘引用条目（v2）：不携带附件字节
                    flags |= FLAG_STORE_REF;
                    dataLength = (value as KdbxBinaryDiskRef).byteLength;
                } else {
                    dataLength = payload.byteLength;
                }
                if (value instanceof ProtectedValue) {
                    flags |= FLAG_PROTECTED;
                } else if (value instanceof KdbxBinaryDiskRef && value.isProtected) {
                    flags |= FLAG_PROTECTED;
                }
                view.setUint32(pos, dataLength, true);
                pos += 4;
                view.setUint8(pos, flags);
                pos += 1;
                bytes.set(hashBytes, pos);
                pos += HASH_LENGTH;
                if (payload !== undefined) {
                    bytes.set(new Uint8Array(payload), pos);
                    pos += payload.byteLength;
                }
            }
            return out;
        });
    }

    static load(data: ArrayBuffer, credentials: KdbxCredentials,
        maxDecompressedBytes?: number, attachmentStore?: AttachmentStore): Promise<Kdbx> {
        if (!KdbxSnapshot.isSnapshot(data)) {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidArg, 'data'));
        }
        if (!(credentials instanceof KdbxCredentials)) {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidArg, 'credentials'));
        }
        const kdbx = new Kdbx();
        kdbx.credentials = credentials;
        kdbx.binaries.store = attachmentStore;
        const ctx = new KdbxContext({ kdbx });
        return kdbx.credentials.ready.then(() => {
            try {
                const stm = new BinaryStream(data);
                stm.readBytes(4);
                const version = stm.getUint16(true);
                if (version !== SNAPSHOT_VERSION_1 && version !== SNAPSHOT_VERSION_2) {
                    throw new KdbxError(ErrorCodes.InvalidVersion, 'bad snapshot version');
                }
                const headerLength = stm.getUint32(true);
                const xmlLength = stm.getUint32(true);
                if (maxDecompressedBytes !== undefined && xmlLength > maxDecompressedBytes) {
                    throw new KdbxError(
                        ErrorCodes.DecompressedTooLarge,
                        `snapshot xml ${xmlLength} exceeds limit ${maxDecompressedBytes}`
                    );
                }
                const poolCount = stm.getUint32(true);
                const minPoolBytes = poolCount * POOL_ENTRY_HEADER_LENGTH;
                if (
                    FIXED_HEADER_LENGTH + headerLength + xmlLength + minPoolBytes >
                    data.byteLength
                ) {
                    throw new KdbxError(ErrorCodes.FileCorrupt, 'bad snapshot layout');
                }
                const headerData = stm.readBytes(headerLength);
                kdbx.header = KdbxHeader.read(new BinaryStream(headerData), ctx);
                // crsAlgorithm 属 v4 内层头字段（InnerRandomStreamID），不在外层头序列化输出中，
                // 快照无法携带；恢复为库默认值，后续 save() 的内层头会原样写入
                if (kdbx.header.versionMajor >= 4 && kdbx.header.crsAlgorithm === undefined) {
                    kdbx.header.crsAlgorithm = CrsAlgorithm.ChaCha20;
                }
                const xmlData = stm.readBytes(xmlLength);

                const pool: KdbxBinaryWithHash[] = [];
                for (let i = 0; i < poolCount; i++) {
                    const dataLength = stm.getUint32(true);
                    const flags = stm.getUint8();
                    const hashBytes = stm.readBytes(HASH_LENGTH);
                    const hash = bytesToHex(hashBytes);
                    let value: KdbxBinary;
                    if ((flags & FLAG_STORE_REF) !== 0) {
                        // v2 磁盘引用：附件字节留在加密缓存，仅在内存保留元信息
                        if (!attachmentStore) {
                            throw new KdbxError(
                                ErrorCodes.InvalidState,
                                'snapshot has disk-ref attachments but no attachment store'
                            );
                        }
                        value = new KdbxBinaryDiskRef(
                            hash, dataLength, (flags & FLAG_PROTECTED) !== 0
                        );
                    } else {
                        const payload = stm.readBytes(dataLength);
                        value = (flags & FLAG_PROTECTED) !== 0
                            ? ProtectedValue.fromBinary(payload)
                            : payload;
                    }
                    pool.push({ hash, value });
                }
                kdbx.binaries.importPool(pool);

                const reader = new MemoryChunkReader(xmlData);
                return KdbxStreamingXmlLoader.load(kdbx, ctx, reader).then(() => {
                    kdbx.xml = undefined;
                    return kdbx;
                });
            } catch (error) {
                if (error instanceof KdbxError) {
                    throw error;
                }
                throw new KdbxError(ErrorCodes.FileCorrupt, `bad snapshot: ${error}`);
            }
        });
    }

    /**
     * 计算池条目载荷：
     * - 磁盘引用且 store 可用 → undefined（条目只携带 hash+长度）
     * - 磁盘引用但 store 缺失 → 拒绝（无法恢复字节）
     * - 其余 → 序列化字节
     */
    private static getPoolPayload(
        value: KdbxBinary,
        store: AttachmentStore | undefined
    ): ArrayBuffer | undefined {
        if (value instanceof KdbxBinaryDiskRef) {
            if (!store) {
                throw new KdbxError(
                    ErrorCodes.InvalidState,
                    'disk-ref attachments require an attachment store'
                );
            }
            return undefined;
        }
        if (value instanceof ProtectedValue) {
            return arrayToBuffer(value.getBinary());
        }
        return value.slice(0);
    }

    // ==================== v3 直传容器（Worker→主线程原始 XML 直传） ====================

    /**
     * 构建 v3 容器前缀（Worker 产容器时调用）：[fixed 26B][header blob][innerInfo][pool entries]。
     * XML 区不在此构建——由调用方从 inner 明文文件流式拷贝追加（内存窗口与文件大小解耦）。
     * 前置条件：kdbx.header 已完成 readInnerHeaderFromFile（含 crsAlgorithm/protectedStreamKey）、
     * binaries 已 computeHashes（池条目 hash 就绪）
     * @param kdbx 已解析外层头 + inner header 的宿主对象
     * @param rawXml true=xml 区为原始 inner XML（需 innerInfo）；false=明文快照 XML
     * @param xmlLength XML 区字节数（CP2' 已由调用方检查）
     */
    static buildV3ContainerPrefix(kdbx: Kdbx, rawXml: boolean, xmlLength: number): Uint8Array {
        const headerStm = new BinaryStream();
        // 不 generateSalts：保留文件真实头（与 v1/v2 快照"新库补盐"语义不同，v3 直传保真）
        kdbx.header.write(headerStm);
        const headerData = headerStm.getWrittenBytes();

        let innerInfoData: ArrayBuffer = new ArrayBuffer(0);
        if (rawXml) {
            const streamKey = kdbx.header.protectedStreamKey;
            const crsAlgorithm = kdbx.header.crsAlgorithm;
            if (!streamKey || crsAlgorithm === undefined) {
                throw new KdbxError(
                    ErrorCodes.FileCorrupt,
                    'missing inner stream info for raw-xml container'
                );
            }
            const keyBytes = new Uint8Array(streamKey);
            const innerStm = new BinaryStream();
            innerStm.setUint8(crsAlgorithm);
            innerStm.setUint32(keyBytes.length, true);
            innerStm.writeBytes(keyBytes);
            innerInfoData = innerStm.getWrittenBytes();
        }

        const pool = kdbx.binaries.getAllWithHashes();
        const store = kdbx.binaries.store;
        const out = new BinaryStream();
        out.setUint8(SNAPSHOT_MAGIC_0);
        out.setUint8(SNAPSHOT_MAGIC_1);
        out.setUint8(SNAPSHOT_MAGIC_2);
        out.setUint8(SNAPSHOT_MAGIC_3);
        out.setUint16(SNAPSHOT_VERSION_3, true);
        out.setUint32(rawXml ? FLAG_V3_RAW_XML : 0, true);
        out.setUint32(headerData.byteLength, true);
        out.setUint32(innerInfoData.byteLength, true);
        out.setUint32(pool.length, true);
        out.setUint32(xmlLength, true);
        out.writeBytes(headerData);
        out.writeBytes(innerInfoData);
        for (let i = 0; i < pool.length; i++) {
            const hashBytes = hexToBytes(pool[i].hash);
            if (hashBytes.length !== HASH_LENGTH) {
                throw new KdbxError(ErrorCodes.FileCorrupt, 'bad binary hash');
            }
            const value = pool[i].value;
            const payload = KdbxSnapshot.getPoolPayload(value, store);
            let flags = 0;
            let dataLength: number;
            if (payload === undefined) {
                flags |= FLAG_STORE_REF;
                dataLength = (value as KdbxBinaryDiskRef).byteLength;
            } else {
                dataLength = payload.byteLength;
            }
            if (value instanceof ProtectedValue) {
                flags |= FLAG_PROTECTED;
            } else if (value instanceof KdbxBinaryDiskRef && value.isProtected) {
                flags |= FLAG_PROTECTED;
            }
            out.setUint32(dataLength, true);
            out.setUint8(flags);
            out.writeBytes(hashBytes);
            if (payload !== undefined) {
                out.writeBytes(payload);
            }
        }
        return new Uint8Array(out.getWrittenBytes());
    }

    /**
     * 从顺序字节流加载 v3 直传容器（主线程消费：会话解包 Reader 边解包边协作解析）。
     * 布局见 buildV3ContainerPrefix；RAW_XML 模式携带 innerInfo（crsAlgorithm +
     * protectedStreamKey），KdbxStreamingXmlLoader 边解析边解密 Protected 值。
     * v1/v2 内存快照仍走 load()
     */
    static loadFromReader(
        reader: SequentialByteReader,
        credentials: KdbxCredentials,
        options?: { maxDecompressedBytes?: number; attachmentStore?: AttachmentStore }
    ): Promise<Kdbx> {
        if (!(credentials instanceof KdbxCredentials)) {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidArg, 'credentials'));
        }
        const kdbx = new Kdbx();
        kdbx.credentials = credentials;
        kdbx.binaries.store = options?.attachmentStore;
        const ctx = new KdbxContext({ kdbx });
        return kdbx.credentials.ready.then(() => {
            return KdbxSnapshot.readExact(reader, V3_FIXED_HEADER_LENGTH).then((fixedBytes) => {
                const fixedView = new DataView(arrayToBuffer(fixedBytes));
                if (
                    fixedBytes[0] !== SNAPSHOT_MAGIC_0 || fixedBytes[1] !== SNAPSHOT_MAGIC_1 ||
                    fixedBytes[2] !== SNAPSHOT_MAGIC_2 || fixedBytes[3] !== SNAPSHOT_MAGIC_3
                ) {
                    throw new KdbxError(ErrorCodes.FileCorrupt, 'bad v3 container magic');
                }
                const version = fixedView.getUint16(4, true);
                if (version !== SNAPSHOT_VERSION_3) {
                    throw new KdbxError(ErrorCodes.InvalidVersion, 'bad container version');
                }
                const rawXml = (fixedView.getUint32(6, true) & FLAG_V3_RAW_XML) !== 0;
                const headerLength = fixedView.getUint32(10, true);
                const innerInfoLength = fixedView.getUint32(14, true);
                const poolCount = fixedView.getUint32(18, true);
                const xmlLength = fixedView.getUint32(22, true);
                if (options?.maxDecompressedBytes !== undefined &&
                    xmlLength > options.maxDecompressedBytes) {
                    throw new KdbxError(
                        ErrorCodes.DecompressedTooLarge,
                        `container xml ${xmlLength} exceeds limit ${options.maxDecompressedBytes}`
                    );
                }
                return KdbxSnapshot.readExact(reader, headerLength).then((headerBytes) => {
                    kdbx.header = KdbxHeader.read(new BinaryStream(arrayToBuffer(headerBytes)), ctx);
                    return KdbxSnapshot.readExact(reader, innerInfoLength).then((innerBytes) => {
                        if (rawXml) {
                            KdbxSnapshot.applyInnerInfo(kdbx, innerBytes);
                        }
                        return KdbxSnapshot.readPoolFromReader(reader, poolCount,
                            options?.attachmentStore).then((pool) => {
                            kdbx.binaries.importPool(pool);
                            const chunkReader = new SequentialReaderChunkReader(reader, xmlLength);
                            return KdbxStreamingXmlLoader.load(kdbx, ctx, chunkReader).then(() => {
                                kdbx.xml = undefined;
                                return kdbx;
                            });
                        });
                    });
                });
            }).catch((error) => {
                if (error instanceof KdbxError) {
                    throw error;
                }
                throw new KdbxError(ErrorCodes.FileCorrupt, `bad v3 container: ${error}`);
            });
        });
    }

    /**
     * 顺序读满 n 字节（流式 Reader 单次 read 可能短读——仅返回当前解密块内
     * 可用字节，循环拉取凑满；EOF/无法凑满视为损坏）
     */
    private static readExact(reader: SequentialByteReader, n: number): Promise<Uint8Array> {
        if (n === 0) {
            return Promise.resolve(new Uint8Array(0));
        }
        const parts: Uint8Array[] = [];
        let received = 0;
        const pull = (): Promise<Uint8Array> => {
            return reader.read(n - received).then((bytes: Uint8Array | null) => {
                if (bytes === null || bytes.length === 0) {
                    throw new KdbxError(ErrorCodes.FileCorrupt, `container short read: ${n}`);
                }
                parts.push(bytes);
                received += bytes.length;
                if (received >= n) {
                    const out = new Uint8Array(n);
                    let offset = 0;
                    for (const part of parts) {
                        out.set(part, offset);
                        offset += part.length;
                    }
                    return out;
                }
                return pull();
            });
        };
        return pull();
    }

    /**
     * 应用 innerInfo blob：[uint8 crsAlgorithm][uint32 keyLen][key bytes]
     * （RAW_XML 模式的 Protected 值解密参数，保真优于 v1/v2 的默认补 ChaCha20）
     */
    private static applyInnerInfo(kdbx: Kdbx, innerBytes: Uint8Array): void {
        if (innerBytes.length < 5) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'bad innerInfo length');
        }
        const view = new DataView(arrayToBuffer(innerBytes));
        const crsAlgorithm = view.getUint8(0);
        const keyLength = view.getUint32(1, true);
        if (5 + keyLength !== innerBytes.length) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'bad innerInfo key length');
        }
        kdbx.header.crsAlgorithm = crsAlgorithm;
        kdbx.header.protectedStreamKey = arrayToBuffer(innerBytes.subarray(5));
    }

    /**
     * 从顺序流读取池条目（编码与 v1/v2 load 完全同构）
     */
    private static readPoolFromReader(
        reader: SequentialByteReader,
        poolCount: number,
        attachmentStore: AttachmentStore | undefined
    ): Promise<KdbxBinaryWithHash[]> {
        const pool: KdbxBinaryWithHash[] = [];
        const next = (index: number): Promise<KdbxBinaryWithHash[]> => {
            if (index >= poolCount) {
                return Promise.resolve(pool);
            }
            return KdbxSnapshot.readExact(reader, POOL_ENTRY_HEADER_LENGTH).then((entryHead) => {
                const headView = new DataView(arrayToBuffer(entryHead));
                const dataLength = headView.getUint32(0, true);
                const flags = headView.getUint8(4);
                const hash = bytesToHex(entryHead.subarray(5));
                let value: KdbxBinary;
                if ((flags & FLAG_STORE_REF) !== 0) {
                    if (!attachmentStore) {
                        throw new KdbxError(
                            ErrorCodes.InvalidState,
                            'container has disk-ref attachments but no attachment store'
                        );
                    }
                    value = new KdbxBinaryDiskRef(hash, dataLength, (flags & FLAG_PROTECTED) !== 0);
                    pool.push({ hash, value });
                    return next(index + 1);
                }
                return KdbxSnapshot.readExact(reader, dataLength).then((payload) => {
                    value = (flags & FLAG_PROTECTED) !== 0
                        ? ProtectedValue.fromBinary(arrayToBuffer(payload))
                        : arrayToBuffer(payload);
                    pool.push({ hash, value });
                    return next(index + 1);
                });
            });
        };
        return next(0);
    }
}
