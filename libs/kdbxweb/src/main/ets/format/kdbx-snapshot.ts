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
import { MemoryChunkReader, KdbxStreamingXmlLoader } from '../utils/xml-pull-parser';

const SNAPSHOT_MAGIC_0 = 0x4b; // 'K'
const SNAPSHOT_MAGIC_1 = 0x50; // 'P'
const SNAPSHOT_MAGIC_2 = 0x53; // 'S'
const SNAPSHOT_MAGIC_3 = 0x4e; // 'N'
const SNAPSHOT_VERSION_1 = 1;
const SNAPSHOT_VERSION_2 = 2;
const SNAPSHOT_VERSION = SNAPSHOT_VERSION_2;
const FIXED_HEADER_LENGTH = 18;
const HASH_LENGTH = 32;
const POOL_ENTRY_HEADER_LENGTH = 4 + 1 + HASH_LENGTH;
const FLAG_PROTECTED = 1;
/** v2：池条目为磁盘引用，只携带 hash+长度，不携带附件字节（P7 治理） */
const FLAG_STORE_REF = 2;

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
}
