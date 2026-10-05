import { Kdbx } from './kdbx';
import { KdbxContext } from './kdbx-context';
import { KdbxCredentials } from './kdbx-credentials';
import { KdbxHeader } from './kdbx-header';
import { KdbxBinary, KdbxBinaryWithHash } from './kdbx-binaries';
import { ProtectedValue } from '../crypto/protected-value';
import { KdbxError } from '../errors/kdbx-error';
import { CrsAlgorithm, ErrorCodes } from '../defs/consts';
import { BinaryStream } from '../utils/binary-stream';
import {
    arrayToBuffer,
    bytesToHex,
    bytesToString,
    hexToBytes,
    stringToBytes
} from '../utils/byte-utils';
import * as XmlUtils from '../utils/xml-utils';

const SNAPSHOT_MAGIC_0 = 0x4b; // 'K'
const SNAPSHOT_MAGIC_1 = 0x50; // 'P'
const SNAPSHOT_MAGIC_2 = 0x53; // 'S'
const SNAPSHOT_MAGIC_3 = 0x4e; // 'N'
const SNAPSHOT_VERSION = 1;
const FIXED_HEADER_LENGTH = 18;
const HASH_LENGTH = 32;
const POOL_ENTRY_HEADER_LENGTH = 4 + 1 + HASH_LENGTH;

/**
 * KPSN binary snapshot: in-memory transfer format for passing a database
 * model across thread boundaries without XML/base64 attachment inflation.
 *
 * Layout (all integers little-endian):
 *   [0..4)    magic 'KPSN'
 *   [4..6)    format version (uint16)
 *   [6..10)   header length (uint32)
 *   [10..14)  xml length (uint32)
 *   [14..18)  pool count (uint32)
 *   header blob: KdbxHeader.write output (version, kdf, cipher, salts)
 *   xml blob: entry tree, attachments as refs only, protected values
 *             as ProtectedInMemPlainXml plaintext (same as saveXml)
 *   pool entries (ordered, index = binary ref):
 *     uint32 dataLength, uint8 flags (bit0 = protected), 32B sha256, data
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
            const xml = XmlUtils.serialize(kdbx.xml);
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
            const payloads: ArrayBuffer[] = [];
            let totalLength = FIXED_HEADER_LENGTH + headerData.byteLength + xmlData.byteLength;
            for (const item of pool) {
                const payload = KdbxSnapshot.getPoolPayload(item.value);
                payloads.push(payload);
                totalLength += POOL_ENTRY_HEADER_LENGTH + payload.byteLength;
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
                const payload = payloads[i];
                view.setUint32(pos, payload.byteLength, true);
                pos += 4;
                view.setUint8(pos, pool[i].value instanceof ProtectedValue ? 1 : 0);
                pos += 1;
                bytes.set(hashBytes, pos);
                pos += HASH_LENGTH;
                bytes.set(new Uint8Array(payload), pos);
                pos += payload.byteLength;
            }
            return out;
        });
    }

    static load(data: ArrayBuffer, credentials: KdbxCredentials,
        maxDecompressedBytes?: number): Promise<Kdbx> {
        if (!KdbxSnapshot.isSnapshot(data)) {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidArg, 'data'));
        }
        if (!(credentials instanceof KdbxCredentials)) {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidArg, 'credentials'));
        }
        const kdbx = new Kdbx();
        kdbx.credentials = credentials;
        const ctx = new KdbxContext({ kdbx });
        return kdbx.credentials.ready.then(() => {
            try {
                const stm = new BinaryStream(data);
                stm.readBytes(4);
                const version = stm.getUint16(true);
                if (version !== SNAPSHOT_VERSION) {
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
                    const payload = stm.readBytes(dataLength);
                    const value: KdbxBinary =
                        (flags & 1) === 1 ? ProtectedValue.fromBinary(payload) : payload;
                    pool.push({ hash: bytesToHex(hashBytes), value });
                }
                kdbx.binaries.importPool(pool);

                kdbx.xml = XmlUtils.parse(bytesToString(xmlData));
                XmlUtils.protectPlainValues(kdbx.xml.documentElement);
                return kdbx.loadFromXml(ctx).then(() => {
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

    private static getPoolPayload(value: KdbxBinary): ArrayBuffer {
        if (value instanceof ProtectedValue) {
            return arrayToBuffer(value.getBinary());
        }
        return value.slice(0);
    }
}
