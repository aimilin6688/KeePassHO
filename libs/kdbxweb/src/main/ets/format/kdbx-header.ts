/* Docs for the KDBX header schema:
 * https://keepass.info/help/kb/kdbx_4.html#innerhdr
 */

import {
    CipherId,
    CompressionAlgorithm,
    CrsAlgorithm,
    Defaults,
    ErrorCodes,
    KdfId,
    Signatures
} from '../defs/consts';
import { KdbxUuid } from './kdbx-uuid';
import { ValueType, VarDictionary } from '../utils/var-dictionary';
import { BinaryStream } from '../utils/binary-stream';
import { KdbxError } from '../errors/kdbx-error';
import { base64ToBytes, zeroBuffer } from '../utils/byte-utils';
import * as CryptoEngine from '../crypto/crypto-engine';
import { Int64 } from '../utils/int64';
import { KdbxContext } from './kdbx-context';
import { KdbxBinaryDiskRef } from './kdbx-binaries';
import { ProtectedValue } from '../crypto/protected-value';
import { sha256FileRegion } from '../utils/attachment-store';
import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * 读取文件指定区域到新分配的 ArrayBuffer（S5 流式解析辅助）。
 */
export function readFileRegion(
    fileFd: number,
    offset: number,
    length: number
): Promise<ArrayBuffer> {
    const buf = new ArrayBuffer(length);
    return fs.read(fileFd, buf, { offset }).then((read) => {
        if (read !== length) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'file region short read');
        }
        return buf;
    });
}

interface HeaderField {
    name: string;
    ver?: number[];
    skipHeader?: boolean;
}

const HeaderFields: HeaderField[] = [
    { name: 'EndOfHeader' },

    { name: 'Comment' },
    { name: 'CipherID' },
    { name: 'CompressionFlags' },
    { name: 'MasterSeed' },
    { name: 'TransformSeed', ver: [3] },
    { name: 'TransformRounds', ver: [3] },
    { name: 'EncryptionIV' },
    { name: 'ProtectedStreamKey', ver: [3] },
    { name: 'StreamStartBytes', ver: [3] },
    { name: 'InnerRandomStreamID', ver: [3] },

    { name: 'KdfParameters', ver: [4] },
    { name: 'PublicCustomData', ver: [4] }
];

const InnerHeaderFields: HeaderField[] = [
    { name: 'EndOfHeader' },

    { name: 'InnerRandomStreamID' },
    { name: 'InnerRandomStreamKey' },
    { name: 'Binary', skipHeader: true }
];

export const HeaderConst = {
    DefaultFileVersionMajor: 4,
    MinSupportedVersion: 3,
    MaxSupportedVersion: 4,
    FlagBinaryProtected: 0x01,
    InnerHeaderBinaryFieldId: 0x03,

    DefaultKdfAlgo: KdfId.Argon2d,
    DefaultKdfSaltLength: 32,
    DefaultKdfParallelism: 2,
    DefaultKdfIterations: 2,
    DefaultKdfMemory: 6 * 1024 * 1024,
    DefaultKdfVersion: 0x13,

    EndOfHeader: 0x0d0a0d0a
} as const;

const DefaultMinorVersions = {
    3: 1,
    4: 1
} as const;

const LastMinorVersions: { [major: number]: number } = {
    3: 1,
    4: 1
} as const;

export class KdbxHeader {
    static readonly MaxFileVersion = HeaderConst.MaxSupportedVersion;

    versionMajor = 0;
    versionMinor = 0;
    dataCipherUuid: KdbxUuid | undefined;
    compression: number | undefined;
    masterSeed: ArrayBuffer | undefined;
    transformSeed: ArrayBuffer | undefined;
    keyEncryptionRounds: number | undefined;
    encryptionIV: ArrayBuffer | undefined;
    protectedStreamKey: ArrayBuffer | undefined;
    streamStartBytes: ArrayBuffer | undefined;
    crsAlgorithm: number | undefined;
    endPos: number | undefined;
    kdfParameters: VarDictionary | undefined;
    publicCustomData: VarDictionary | undefined;

    private readSignature(stm: BinaryStream): void {
        if (stm.byteLength < 8) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'not enough data');
        }
        const sig1 = stm.getUint32(true),
            sig2 = stm.getUint32(true);
        // 官方 KeePass 同时接受正式与预发布签名（KdbxFile.Read.cs）。
        if (
            !(
                sig1 === Signatures.FileMagic &&
                (sig2 === Signatures.Sig2Kdbx || sig2 === Signatures.Sig2KdbxPreRelease)
            )
        ) {
            throw new KdbxError(ErrorCodes.BadSignature);
        }
    }

    private writeSignature(stm: BinaryStream): void {
        stm.setUint32(Signatures.FileMagic, true);
        stm.setUint32(Signatures.Sig2Kdbx, true);
    }

    private readVersion(stm: BinaryStream): void {
        const versionMinor = stm.getUint16(true);
        const versionMajor = stm.getUint16(true);
        if (
            versionMajor > HeaderConst.MaxSupportedVersion ||
            versionMajor < HeaderConst.MinSupportedVersion
        ) {
            throw new KdbxError(ErrorCodes.InvalidVersion);
        }
        // 官方 KeePass 仅限制最新支持 major 的 minor 版本（KdbxFile.Read.cs）：
        // 旧 major（KDBX 3.x）的任意 minor 无条件打开；4.x minor 超限时提示确认。
        if (
            versionMajor === HeaderConst.MaxSupportedVersion &&
            versionMinor > LastMinorVersions[versionMajor]
        ) {
            throw new KdbxError(ErrorCodes.InvalidVersion);
        }
        this.versionMinor = versionMinor;
        this.versionMajor = versionMajor;
    }

    private writeVersion(stm: BinaryStream): void {
        if (!this.versionMajor) {
            throw new KdbxError(ErrorCodes.InvalidState, 'version is not set');
        }
        stm.setUint16(this.versionMinor, true);
        stm.setUint16(this.versionMajor, true);
    }

    private readCipherID(bytes: ArrayBuffer): void {
        if (bytes.byteLength !== 16) {
            throw new KdbxError(ErrorCodes.Unsupported, 'cipher');
        }
        this.dataCipherUuid = new KdbxUuid(bytes);
    }

    private writeCipherID(stm: BinaryStream): void {
        if (!this.dataCipherUuid) {
            throw new KdbxError(ErrorCodes.InvalidState, 'cipher id is not set');
        }
        this.writeFieldSize(stm, 16);
        stm.writeBytes(this.dataCipherUuid.bytes);
    }

    private readCompressionFlags(bytes: ArrayBuffer): void {
        const id = new DataView(bytes).getUint32(0, true);
        if (id < 0 || id >= Object.keys(CompressionAlgorithm).length) {
            throw new KdbxError(ErrorCodes.Unsupported, 'compression');
        }
        this.compression = id;
    }

    private writeCompressionFlags(stm: BinaryStream): void {
        if (typeof this.compression !== 'number') {
            throw new KdbxError(ErrorCodes.InvalidState, 'compression is not set');
        }
        this.writeFieldSize(stm, 4);
        stm.setUint32(this.compression, true);
    }

    private readMasterSeed(bytes: ArrayBuffer): void {
        this.masterSeed = bytes;
    }

    private writeMasterSeed(stm: BinaryStream): void {
        if (!this.masterSeed) {
            throw new KdbxError(ErrorCodes.InvalidState, 'master seed is not set');
        }
        this.writeFieldBytes(stm, this.masterSeed);
    }

    private readTransformSeed(bytes: ArrayBuffer): void {
        this.transformSeed = bytes;
    }

    private writeTransformSeed(stm: BinaryStream): void {
        if (!this.transformSeed) {
            throw new KdbxError(ErrorCodes.InvalidState, 'transform seed is not set');
        }
        this.writeFieldBytes(stm, this.transformSeed);
    }

    private readTransformRounds(bytes: ArrayBuffer): void {
        this.keyEncryptionRounds = new BinaryStream(bytes).getUint64(true);
    }

    private writeTransformRounds(stm: BinaryStream): void {
        // rounds = 0 是合法值（官方 AesKdf 允许 0 轮），仅未设置时报错。
        if (this.keyEncryptionRounds === undefined) {
            throw new KdbxError(ErrorCodes.InvalidState, 'key encryption rounds is not set');
        }
        this.writeFieldSize(stm, 8);
        stm.setUint64(this.keyEncryptionRounds, true);
    }

    private readEncryptionIV(bytes: ArrayBuffer): void {
        this.encryptionIV = bytes;
    }

    private writeEncryptionIV(stm: BinaryStream): void {
        if (!this.encryptionIV) {
            throw new KdbxError(ErrorCodes.InvalidState, 'encryption IV is not set');
        }
        this.writeFieldBytes(stm, this.encryptionIV);
    }

    private readProtectedStreamKey(bytes: ArrayBuffer): void {
        this.protectedStreamKey = bytes;
    }

    private writeProtectedStreamKey(stm: BinaryStream): void {
        if (!this.protectedStreamKey) {
            throw new KdbxError(ErrorCodes.InvalidState, 'protected stream key is not set');
        }
        this.writeFieldBytes(stm, this.protectedStreamKey);
    }

    private readStreamStartBytes(bytes: ArrayBuffer): void {
        this.streamStartBytes = bytes;
    }

    private writeStreamStartBytes(stm: BinaryStream): void {
        if (!this.streamStartBytes) {
            throw new KdbxError(ErrorCodes.InvalidState, 'stream start bytes is not set');
        }
        this.writeFieldBytes(stm, this.streamStartBytes);
    }

    private readInnerRandomStreamID(bytes: ArrayBuffer): void {
        this.crsAlgorithm = new DataView(bytes).getUint32(0, true);
    }

    private writeInnerRandomStreamID(stm: BinaryStream): void {
        if (!this.crsAlgorithm) {
            throw new KdbxError(ErrorCodes.InvalidState, 'CRSAlgorithm is not set');
        }
        this.writeFieldSize(stm, 4);
        stm.setUint32(this.crsAlgorithm, true);
    }

    private readInnerRandomStreamKey(bytes: ArrayBuffer): void {
        this.protectedStreamKey = bytes;
    }

    private writeInnerRandomStreamKey(stm: BinaryStream): void {
        if (!this.protectedStreamKey) {
            throw new KdbxError(ErrorCodes.InvalidState, 'protected stream key is not set');
        }
        this.writeFieldBytes(stm, this.protectedStreamKey);
    }

    private readKdfParameters(bytes: ArrayBuffer): void {
        this.kdfParameters = VarDictionary.read(new BinaryStream(bytes));
    }

    private writeKdfParameters(stm: BinaryStream): void {
        if (!this.kdfParameters) {
            throw new KdbxError(ErrorCodes.InvalidState, 'KDF parameters are not set');
        }
        const innerStream = new BinaryStream();
        this.kdfParameters.write(innerStream);
        this.writeFieldBytes(stm, innerStream.getWrittenBytes());
    }

    private readPublicCustomData(bytes: ArrayBuffer): void {
        this.publicCustomData = VarDictionary.read(new BinaryStream(bytes));
    }

    private hasPublicCustomData(): boolean {
        return !!this.publicCustomData;
    }

    private writePublicCustomData(stm: BinaryStream): void {
        if (this.publicCustomData) {
            const innerStream = new BinaryStream();
            this.publicCustomData.write(innerStream);
            this.writeFieldBytes(stm, innerStream.getWrittenBytes());
        }
    }

    private readBinary(bytes: ArrayBuffer, ctx: KdbxContext): void {
        const view = new DataView(bytes);
        const flags = view.getUint8(0);
        const isProtected = flags & HeaderConst.FlagBinaryProtected;
        const binaryData = bytes.slice(1); // Actual data comes after the flag byte

        const binary = isProtected ? ProtectedValue.fromBinary(binaryData) : binaryData;

        ctx.kdbx.binaries.addWithNextId(binary);
    }

    private writeBinary(stm: BinaryStream, ctx: KdbxContext): Promise<void> {
        if (this.versionMajor < 4) {
            return Promise.resolve();
        }
        const binaries = ctx.kdbx.binaries.getAll();
        let chain: Promise<void> = Promise.resolve();
        for (const binary of binaries) {
            const value = binary.value;
            if (value instanceof KdbxBinaryDiskRef) {
                // 磁盘引用：从加密缓存按需读回后写出（S4 附件磁盘化）
                chain = chain.then(() =>
                    ctx.kdbx.binaries.readDiskRef(value).then((binaryData) => {
                        stm.setUint8(HeaderConst.InnerHeaderBinaryFieldId);
                        this.writeFieldSize(stm, binaryData.byteLength + 1);
                        stm.setUint8(value.isProtected ? HeaderConst.FlagBinaryProtected : 0);
                        stm.writeBytes(binaryData);
                        zeroBuffer(binaryData);
                    })
                );
            } else if (value instanceof ProtectedValue) {
                chain = chain.then(() => {
                    const binaryData = value.getBinary();
                    stm.setUint8(HeaderConst.InnerHeaderBinaryFieldId);
                    this.writeFieldSize(stm, binaryData.byteLength + 1);
                    stm.setUint8(HeaderConst.FlagBinaryProtected);
                    stm.writeBytes(binaryData);
                    zeroBuffer(binaryData);
                });
            } else {
                chain = chain.then(() => {
                    stm.setUint8(HeaderConst.InnerHeaderBinaryFieldId);
                    this.writeFieldSize(stm, value.byteLength + 1);
                    stm.setUint8(0);
                    stm.writeBytes(value);
                });
            }
        }
        return chain;
    }

    private writeEndOfHeader(stm: BinaryStream): void {
        this.writeFieldSize(stm, 4);
        stm.setUint32(HeaderConst.EndOfHeader, false);
    }

    private readField(stm: BinaryStream, fields: HeaderField[], ctx: KdbxContext) {
        const headerId = stm.getUint8();
        const size = this.readFieldSize(stm);
        const bytes = size > 0 ? stm.readBytes(size) : new ArrayBuffer(0);
        return this.applyField(headerId, bytes, fields, ctx);
    }

    /**
     * 处理一个已读出的头部字段。S5：整缓冲 readField 与文件流式
     * readInnerHeaderFromFile 共用同一套字段解释逻辑。
     * @returns 是否继续读下一字段（EndOfHeader 返回 false）
     */
    private applyField(
        headerId: number,
        bytes: ArrayBuffer,
        fields: HeaderField[],
        ctx: KdbxContext
    ): boolean {
        const headerField = fields[headerId];
        if (!headerField) {
            // 官方 KeePass 对未知头字段仅 Debug.Assert 后跳过继续读
            // （KdbxFile.Read.cs ReadHeaderField default 分支），不使加载失败。
            return true;
        }
        switch (headerField.name) {
            case 'EndOfHeader':
            case 'Comment':
                break;
            case 'CipherID':
                this.readCipherID(bytes);
                break;
            case 'CompressionFlags':
                this.readCompressionFlags(bytes);
                break;
            case 'MasterSeed':
                this.readMasterSeed(bytes);
                break;
            case 'TransformSeed':
                this.readTransformSeed(bytes);
                break;
            case 'TransformRounds':
                this.readTransformRounds(bytes);
                break;
            case 'EncryptionIV':
                this.readEncryptionIV(bytes);
                break;
            case 'ProtectedStreamKey':
                this.readProtectedStreamKey(bytes);
                break;
            case 'StreamStartBytes':
                this.readStreamStartBytes(bytes);
                break;
            case 'InnerRandomStreamID':
                this.readInnerRandomStreamID(bytes);
                break;
            case 'KdfParameters':
                this.readKdfParameters(bytes);
                break;
            case 'PublicCustomData':
                this.readPublicCustomData(bytes);
                break;
            case 'InnerRandomStreamKey':
                this.readInnerRandomStreamKey(bytes);
                break;
            case 'Binary':
                this.readBinary(bytes, ctx);
                break;
            default:
                throw new KdbxError(ErrorCodes.InvalidArg, `bad header field: ${headerField.name}`);
        }
        return headerId !== 0;
    }

    /**
     * S5 流式读取 v4 inner header：直接从解压后的 inner 明文文件逐字段解析，
     * 大 Binary 字段（≥ largeBinaryThreshold 字节且附件缓存可用）不整读入内存：
     * 先对文件区域算 sha256，再分块搬运进附件加密缓存，模型仅保留
     * KdbxBinaryDiskRef（设计文档 §2.2 加载管道 / §6 附件落盘）。
     * @param fileFd inner 明文文件 fd（gzip 解压后的 T2 或未压缩的 T1）
     * @param ctx KDBX 上下文（附件池挂载点）
     * @param largeBinaryThreshold Binary 字段流式落盘的最小字节数
     * @returns XML 区起始偏移
     */
    async readInnerHeaderFromFile(
        fileFd: number,
        ctx: KdbxContext,
        largeBinaryThreshold: number
    ): Promise<number> {
        let pos = 0;
        for (;;) {
            const head = new ArrayBuffer(5);
            const headRead = await fs.read(fileFd, head, { offset: pos });
            if (headRead !== 5) {
                throw new KdbxError(ErrorCodes.FileCorrupt, 'inner header truncated');
            }
            const view = new DataView(head);
            const fieldId = view.getUint8(0);
            const size = view.getUint32(1, true);
            pos += 5;
            if (fieldId === HeaderConst.InnerHeaderBinaryFieldId) {
                pos = await this.readBinaryFromFile(fileFd, pos, size, ctx, largeBinaryThreshold);
                continue;
            }
            const bytes = size > 0 ? await readFileRegion(fileFd, pos, size) : new ArrayBuffer(0);
            pos += size;
            if (!this.applyField(fieldId, bytes, InnerHeaderFields, ctx)) {
                break;
            }
        }
        this.validateInner();
        return pos;
    }

    /**
     * 流式处理 inner header 的 Binary 字段：data = [flags:1][bytes]。
     * 大字段分块落盘为 KdbxBinaryDiskRef，小字段保持内存模式（与整缓冲路径一致）。
     * @returns 消费后的文件偏移
     */
    private async readBinaryFromFile(
        fileFd: number,
        pos: number,
        size: number,
        ctx: KdbxContext,
        largeBinaryThreshold: number
    ): Promise<number> {
        if (size < 1) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'bad inner binary size');
        }
        const flagsBuf = new ArrayBuffer(1);
        const flagRead = await fs.read(fileFd, flagsBuf, { offset: pos });
        if (flagRead !== 1) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'inner binary flag truncated');
        }
        const isProtected =
            (new DataView(flagsBuf).getUint8(0) & HeaderConst.FlagBinaryProtected) !== 0;
        const dataOffset = pos + 1;
        const dataLength = size - 1;
        const store = ctx.kdbx.binaries.store;
        if (store && dataLength >= largeBinaryThreshold) {
            const hash = await sha256FileRegion(fileFd, dataOffset, dataLength);
            await store.putFromFileRegion(hash, fileFd, dataOffset, dataLength);
            ctx.kdbx.binaries.addWithNextId(
                new KdbxBinaryDiskRef(hash, dataLength, isProtected)
            );
        } else {
            const binaryData =
                dataLength > 0
                    ? await readFileRegion(fileFd, dataOffset, dataLength)
                    : new ArrayBuffer(0);
            const binary = isProtected ? ProtectedValue.fromBinary(binaryData) : binaryData;
            ctx.kdbx.binaries.addWithNextId(binary);
        }
        return dataOffset + dataLength;
    }

    private writeField(
        stm: BinaryStream,
        headerId: number,
        fields: HeaderField[],
        ctx?: KdbxContext
    ) {
        const headerField = fields[headerId];
        if (headerField) {
            if (headerField.ver && !headerField.ver.includes(this.versionMajor)) {
                return;
            }

            switch (headerField.name) {
                case 'PublicCustomData':
                    if (!this.hasPublicCustomData()) {
                        return;
                    }
                    break;
                case 'Comment':
                    return;
            }

            if (!headerField.skipHeader) {
                stm.setUint8(headerId);
            }
            switch (headerField.name) {
                case 'EndOfHeader':
                    this.writeEndOfHeader(stm);
                    break;
                case 'CipherID':
                    this.writeCipherID(stm);
                    break;
                case 'CompressionFlags':
                    this.writeCompressionFlags(stm);
                    break;
                case 'MasterSeed':
                    this.writeMasterSeed(stm);
                    break;
                case 'TransformSeed':
                    this.writeTransformSeed(stm);
                    break;
                case 'TransformRounds':
                    this.writeTransformRounds(stm);
                    break;
                case 'EncryptionIV':
                    this.writeEncryptionIV(stm);
                    break;
                case 'ProtectedStreamKey':
                    this.writeProtectedStreamKey(stm);
                    break;
                case 'StreamStartBytes':
                    this.writeStreamStartBytes(stm);
                    break;
                case 'InnerRandomStreamID':
                    this.writeInnerRandomStreamID(stm);
                    break;
                case 'KdfParameters':
                    this.writeKdfParameters(stm);
                    break;
                case 'PublicCustomData':
                    this.writePublicCustomData(stm);
                    break;
                case 'InnerRandomStreamKey':
                    this.writeInnerRandomStreamKey(stm);
                    break;
                case 'Binary':
                    if (!ctx) {
                        throw new KdbxError(ErrorCodes.InvalidArg, 'context is not set');
                    }
                    // writeBinary 可能需要异步读回磁盘引用附件
                    return this.writeBinary(stm, ctx);
                default:
                    throw new KdbxError(
                        ErrorCodes.InvalidArg,
                        `Bad header field: ${headerField.name}`
                    );
            }
        }
    }

    private readFieldSize(stm: BinaryStream): number {
        return (this.versionMajor | 0) >= 4 ? stm.getUint32(true) : stm.getUint16(true);
    }

    private writeFieldSize(stm: BinaryStream, size: number) {
        if ((this.versionMajor | 0) >= 4) {
            stm.setUint32(size, true);
        } else {
            stm.setUint16(size, true);
        }
    }

    private writeFieldBytes(stm: BinaryStream, bytes: ArrayBuffer): void {
        this.writeFieldSize(stm, bytes.byteLength);
        stm.writeBytes(bytes);
    }

    private validate(): void {
        if (!this.versionMajor || this.versionMinor === undefined) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no version in header');
        }
        if (this.dataCipherUuid === undefined) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no cipher in header');
        }
        if (this.compression === undefined) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no compression in header');
        }
        if (!this.masterSeed) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no master seed in header');
        }
        if (this.versionMajor < 4 && !this.transformSeed) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no transform seed in header');
        }
        // 官方允许 TransformRounds = 0（AesKdf 0 轮 = 仅最终 SHA256），
        // 因此只校验字段缺失，不能把 rounds=0 误判为文件损坏。
        if (this.versionMajor < 4 && this.keyEncryptionRounds === undefined) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no key encryption rounds in header');
        }
        if (!this.encryptionIV) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no encryption iv in header');
        }
        if (this.versionMajor < 4 && !this.protectedStreamKey) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no protected stream key in header');
        }
        if (this.versionMajor < 4 && !this.streamStartBytes) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no stream start bytes in header');
        }
        // CrsAlgorithm = 0（ArcFourVariant）是合法值，缺失才报错；
        // ArcFour 后续由内流创建处以 Unsupported 报"不支持的算法"。
        if (this.versionMajor < 4 && this.crsAlgorithm === undefined) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no crs algorithm in header');
        }
        if (this.versionMajor >= 4 && !this.kdfParameters) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no kdf parameters in header');
        }
    }

    private validateInner(): void {
        if (!this.protectedStreamKey) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no protected stream key in header');
        }
        if (!this.crsAlgorithm) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no crs algorithm in header');
        }
    }

    private createKdfParameters(algo?: string): void {
        if (!algo) {
            algo = HeaderConst.DefaultKdfAlgo;
        }
        switch (algo) {
            case KdfId.Argon2d:
            case KdfId.Argon2id:
                this.kdfParameters = new VarDictionary();
                this.kdfParameters.set('$UUID', ValueType.Bytes, base64ToBytes(algo));
                this.kdfParameters.set(
                    'S',
                    ValueType.Bytes,
                    CryptoEngine.random(HeaderConst.DefaultKdfSaltLength)
                );
                this.kdfParameters.set('P', ValueType.UInt32, HeaderConst.DefaultKdfParallelism);
                this.kdfParameters.set(
                    'I',
                    ValueType.UInt64,
                    new Int64(HeaderConst.DefaultKdfIterations)
                );
                this.kdfParameters.set(
                    'M',
                    ValueType.UInt64,
                    new Int64(HeaderConst.DefaultKdfMemory)
                );
                this.kdfParameters.set('V', ValueType.UInt32, HeaderConst.DefaultKdfVersion);
                break;
            case KdfId.Aes:
                this.kdfParameters = new VarDictionary();
                this.kdfParameters.set('$UUID', ValueType.Bytes, base64ToBytes(KdfId.Aes));
                this.kdfParameters.set(
                    'S',
                    ValueType.Bytes,
                    CryptoEngine.random(HeaderConst.DefaultKdfSaltLength)
                );
                this.kdfParameters.set(
                    'R',
                    ValueType.UInt64,
                    new Int64(Defaults.KeyEncryptionRounds)
                );
                break;
            default:
                throw new KdbxError(ErrorCodes.InvalidArg, 'bad KDF algo');
        }
    }

    write(stm: BinaryStream): void {
        this.validate();
        this.writeSignature(stm);
        this.writeVersion(stm);
        for (let id = 1; id < HeaderFields.length; id++) {
            this.writeField(stm, id, HeaderFields);
        }
        this.writeField(stm, 0, HeaderFields);
        this.endPos = stm.pos;
    }

    /**
     * 写内层头（v4）。Binary 字段可能携带磁盘引用，需异步从加密缓存读回，
     * 因此整体为异步链式写出。
     */
    writeInnerHeader(stm: BinaryStream, ctx: KdbxContext): Promise<void> {
        this.validateInner();
        let chain: Promise<void> = Promise.resolve();
        for (let id = 1; id < InnerHeaderFields.length; id++) {
            const fieldId = id;
            chain = chain.then(() => this.writeField(stm, fieldId, InnerHeaderFields, ctx));
        }
        return chain.then(() => this.writeField(stm, 0, InnerHeaderFields, ctx));
    }

    /**
     * 写内层头到文件 fd（S6 保存管道）：字段顺序与 writeInnerHeader 完全一致；
     * 磁盘引用附件分块流式回读直写，不再整读入内存。
     */
    writeInnerHeaderToFile(outFd: number, ctx: KdbxContext): Promise<void> {
        this.validateInner();
        let chain: Promise<void> = Promise.resolve();
        // InnerRandomStreamID(1) + InnerRandomStreamKey(2)：小同步字段，复用 writeField 到内存 stm 再 flush
        for (let id = 1; id < InnerHeaderFields.length - 1; id++) {
            const fieldId = id;
            chain = chain.then(() => this.writeSmallFieldToFile(outFd, fieldId, InnerHeaderFields));
        }
        // Binary(3)：附件字段，磁盘引用流式回读直写
        chain = chain.then(() => this.writeBinaryToFile(outFd, ctx));
        // EndOfHeader(0)
        return chain.then(() => this.writeSmallFieldToFile(outFd, 0, InnerHeaderFields));
    }

    private writeSmallFieldToFile(outFd: number, id: number, fields: HeaderField[]): Promise<void> {
        const stm = new BinaryStream();
        this.writeField(stm, id, fields);
        return fs.write(outFd, stm.getWrittenBytes()).then(() => undefined);
    }

    private writeBinaryToFile(outFd: number, ctx: KdbxContext): Promise<void> {
        if (this.versionMajor < 4) {
            return Promise.resolve();
        }
        const binaries = ctx.kdbx.binaries.getAll();
        let chain: Promise<void> = Promise.resolve();
        for (const binary of binaries) {
            const value = binary.value;
            if (value instanceof KdbxBinaryDiskRef) {
                chain = chain.then(() => {
                    const frame = new ArrayBuffer(1 + 4 + 1);
                    const stm = new BinaryStream(frame);
                    stm.setUint8(HeaderConst.InnerHeaderBinaryFieldId);
                    stm.setUint32(value.byteLength + 1, true);
                    stm.setUint8(value.isProtected ? HeaderConst.FlagBinaryProtected : 0);
                    return fs.write(outFd, frame).then(() =>
                        ctx.kdbx.binaries.readDiskRefToFile(value, outFd).then(() => undefined)
                    );
                });
            } else if (value instanceof ProtectedValue) {
                chain = chain.then(() => {
                    const binaryData = value.getBinary();
                    const frame = new ArrayBuffer(1 + 4 + 1);
                    const stm = new BinaryStream(frame);
                    stm.setUint8(HeaderConst.InnerHeaderBinaryFieldId);
                    stm.setUint32(binaryData.byteLength + 1, true);
                    stm.setUint8(HeaderConst.FlagBinaryProtected);
                    return fs.write(outFd, frame).then(() =>
                        fs.write(outFd, binaryData).then(() => {
                            zeroBuffer(binaryData);
                        })
                    );
                });
            } else {
                chain = chain.then(() => {
                    const frame = new ArrayBuffer(1 + 4 + 1);
                    const stm = new BinaryStream(frame);
                    stm.setUint8(HeaderConst.InnerHeaderBinaryFieldId);
                    stm.setUint32(value.byteLength + 1, true);
                    stm.setUint8(0);
                    return fs.write(outFd, frame).then(() =>
                        fs.write(outFd, value).then(() => undefined)
                    );
                });
            }
        }
        return chain;
    }

    generateSalts(): void {
        this.masterSeed = CryptoEngine.random(32);
        if (this.versionMajor < 4) {
            this.transformSeed = CryptoEngine.random(32);
            this.streamStartBytes = CryptoEngine.random(32);
            this.protectedStreamKey = CryptoEngine.random(32);
            this.encryptionIV = CryptoEngine.random(16);
        } else {
            this.protectedStreamKey = CryptoEngine.random(64);
            if (!this.kdfParameters || !this.dataCipherUuid) {
                throw new KdbxError(ErrorCodes.InvalidState, 'no kdf params');
            }
            this.kdfParameters.set('S', ValueType.Bytes, CryptoEngine.random(32));
            const ivLength = this.dataCipherUuid.toString() === CipherId.ChaCha20 ? 12 : 16;
            this.encryptionIV = CryptoEngine.random(ivLength);
        }
    }

    setVersion(version: number): void {
        if (version !== 3 && version !== 4) {
            throw new KdbxError(ErrorCodes.InvalidArg, 'bad file version');
        }
        this.versionMajor = version;
        this.versionMinor = DefaultMinorVersions[version];
        if (this.versionMajor === 4) {
            if (!this.kdfParameters) {
                this.createKdfParameters();
            }
            this.crsAlgorithm = CrsAlgorithm.ChaCha20;
            this.keyEncryptionRounds = undefined;
        } else {
            this.kdfParameters = undefined;
            this.crsAlgorithm = CrsAlgorithm.Salsa20;
            this.keyEncryptionRounds = Defaults.KeyEncryptionRounds;
        }
    }

    setKdf(kdf: string): void {
        this.createKdfParameters(kdf);
    }

    static read(stm: BinaryStream, ctx: KdbxContext): KdbxHeader {
        const header = new KdbxHeader();
        header.readSignature(stm);
        header.readVersion(stm);
        while (header.readField(stm, HeaderFields, ctx)) {}
        header.endPos = stm.pos;
        header.validate();
        return header;
    }

    readInnerHeader(stm: BinaryStream, ctx: KdbxContext): void {
        while (this.readField(stm, InnerHeaderFields, ctx)) {}
        this.validateInner();
    }

    static create(): KdbxHeader {
        const header = new KdbxHeader();
        header.versionMajor = HeaderConst.DefaultFileVersionMajor;
        header.versionMinor = DefaultMinorVersions[HeaderConst.DefaultFileVersionMajor];
        header.dataCipherUuid = new KdbxUuid(CipherId.Aes);
        header.compression = CompressionAlgorithm.GZip;
        header.crsAlgorithm = CrsAlgorithm.ChaCha20;
        header.createKdfParameters();
        return header;
    }
}
