import { gzip, ungzip } from '@ohos/flate2';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Kdbx } from './kdbx';
import { CipherId, CompressionAlgorithm, ErrorCodes } from '../defs/consts';
import { KdbxError } from '../errors/kdbx-error';
import { BinaryStream } from '../utils/binary-stream';
import { KdbxContext } from './kdbx-context';
import { KdbxHeader } from './kdbx-header';
import { AttachmentStore } from '../utils/attachment-store';
import {
    arrayBufferEquals,
    arrayToBuffer,
    bytesToString,
    stringToBytes,
    zeroBuffer
} from '../utils/byte-utils';
import { ProtectSaltGenerator } from '../crypto/protect-salt-generator';
import * as XmlUtils from '../utils/xml-utils';
import * as HmacBlockTransform from '../crypto/hmac-block-transform';
import { ChaCha20 } from '../crypto/chacha20';
import * as HashedBlockTransform from '../crypto/hashed-block-transform';
import * as CryptoEngine from '../crypto/crypto-engine';
import * as KeyEncryptorAes from '../crypto/key-encryptor-aes';
import * as KeyEncryptorKdf from '../crypto/key-encryptor-kdf';
import { Int64 } from '../utils/int64';

export class KdbxFormat {
    readonly kdbx: Kdbx;
    readonly ctx: KdbxContext;

    preserveXml = false;
    /**
     * CP2' 模型守卫上限（字节）：解压后载荷超过该值时中止加载，
     * 防止超大 XML 的 DOM/字符串放大导致 OOM；undefined 表示不检查
     */
    maxDecompressedBytes: number | undefined = undefined;
    /**
     * S4 附件磁盘化阈值（字节）：v4 加载完成后附件池总量达到该值时，
     * 附件字节转入 binaries.store 加密缓存，内存仅保留哈希引用。
     * undefined / 0 表示禁用（纯内存模式）。store 未设置时同样禁用。
     */
    attachmentsDiskThreshold: number | undefined = undefined;

    constructor(kdbx: Kdbx) {
        this.kdbx = kdbx;
        this.ctx = new KdbxContext({ kdbx });
    }

    load(data: ArrayBuffer): Promise<Kdbx> {
        const stm = new BinaryStream(data);
        return this.kdbx.credentials.ready.then(() => {
            this.kdbx.header = KdbxHeader.read(stm, this.ctx);
            if (this.kdbx.header.versionMajor === 3) {
                return this.loadV3(stm);
            } else if (this.kdbx.header.versionMajor === 4) {
                return this.loadV4(stm);
            } else {
                throw new KdbxError(
                    ErrorCodes.InvalidVersion,
                    `bad version: ${this.kdbx.versionMajor}`
                );
            }
        });
    }

    /**
     * 从文件流式加载（S4 流式解密管道 T0→T1）
     * 预读 header 到 BinaryStream，ChaCha20 v4 用 decryptFromFile 流式解密到 t1Path，
     * AES-CBC v4 或 v3 退化为整缓冲（读入内存走 load()）
     * @param filePath KDBX 文件路径
     * @param t1Path 解密后 gz 数据的临时文件路径（由调用方管理生命周期）
     */
    loadFromFile(filePath: string, t1Path: string): Promise<Kdbx> {
        return this.kdbx.credentials.ready.then(() => {
            return fs.open(filePath, fs.OpenMode.READ_ONLY).then((file) => {
                return this.loadFromFileInner(file.fd, t1Path).then((kdbx) => {
                    return fs.close(file.fd).then(() => kdbx);
                });
            });
        });
    }

    private loadFromFileInner(fileFd: number, t1Path: string): Promise<Kdbx> {
        // 预读 header（256KB 足够任何 KDBX outer header + sha + hmac）
        const headerBuf = new ArrayBuffer(256 * 1024);
        return fs.read(fileFd, headerBuf).then((totalRead) => {
            const stm = new BinaryStream(headerBuf.slice(0, totalRead));
            this.kdbx.header = KdbxHeader.read(stm, this.ctx);
            if (this.kdbx.header.versionMajor === 3) {
                // v3 退化为整缓冲
                return this.loadFromFileFallbackV3(fileFd, stm, totalRead);
            } else if (this.kdbx.header.versionMajor === 4) {
                return this.loadV4FromFile(stm, fileFd, t1Path);
            } else {
                throw new KdbxError(
                    ErrorCodes.InvalidVersion,
                    `bad version: ${this.kdbx.versionMajor}`
                );
            }
        });
    }

    /**
     * v4 流式加载：header 验证 → decryptFromFile 流式解密到 T1 → ungzip → parse
     * 仅 ChaCha20 支持流式；AES-CBC 退化为整缓冲
     */
    private loadV4FromFile(stm: BinaryStream, fileFd: number, t1Path: string): Promise<Kdbx> {
        return this.getHeaderHash(stm).then((headerSha) => {
            const expectedHeaderSha = stm.readBytes(headerSha.byteLength);
            if (!arrayBufferEquals(expectedHeaderSha, headerSha)) {
                throw new KdbxError(ErrorCodes.FileCorrupt, 'header hash mismatch');
            }
            return this.computeKeysV4().then((keys) => {
                return this.getHeaderHmac(stm, keys.hmacKey).then((headerHmac) => {
                    const expectedHeaderHmac = stm.readBytes(headerHmac.byteLength);
                    if (!arrayBufferEquals(expectedHeaderHmac, headerHmac)) {
                        throw new KdbxError(ErrorCodes.InvalidKey);
                    }

                    // stm 现在在 header + sha + hmac 后 = 加密数据起始偏移
                    const dataOffset = stm.pos;

                    // 检查 cipher：仅 ChaCha20 支持流式就地解密
                    const cipherId = this.kdbx.header.dataCipherUuid;
                    if (!cipherId || cipherId.toString() !== CipherId.ChaCha20) {
                        // AES-CBC 或未知：退化为整缓冲
                        return this.loadV4FromFileFallback(fileFd, dataOffset, keys, stm);
                    }

                    // ChaCha20 流式解密到 T1 文件
                    const iv = this.kdbx.header.encryptionIV;
                    if (!iv) {
                        throw new KdbxError(ErrorCodes.FileCorrupt, 'no encryption IV');
                    }
                    const chaCha = new ChaCha20(new Uint8Array(keys.cipherKey), new Uint8Array(iv));
                    const decryptBlock = (data: Uint8Array): void => {
                        chaCha.xorInPlace(data);
                    };

                    // lseek 到加密数据起始处
                    fs.lseek(fileFd, dataOffset, 0 /* SEEK_SET */);
                    return HmacBlockTransform.decryptFromFile(
                        fileFd, t1Path, keys.hmacKey, decryptBlock
                    ).then(() => {
                        zeroBuffer(keys.hmacKey);
                        zeroBuffer(keys.cipherKey);
                        // 读 T1 → ungzip → parse
                        return this.parseDecryptedFile(t1Path);
                    });
                });
            });
        });
    }

    /**
     * 读解密后的 T1 文件 → ungzip（S5 前整缓冲）→ CP2' → inner header + XML parse
     */
    private parseDecryptedFile(t1Path: string): Promise<Kdbx> {
        return fs.open(t1Path, fs.OpenMode.READ_ONLY).then((file) => {
            return fs.stat(file.fd).then((stat) => {
                const buf = new ArrayBuffer(stat.size);
                return fs.read(file.fd, buf).then(() => {
                    return fs.close(file.fd).then(() => {
                        let data: ArrayBuffer = buf;
                        if (this.kdbx.header.compression === CompressionAlgorithm.GZip) {
                            const date = new Date().getTime();
                            data = arrayToBuffer(ungzip(new Uint8Array(data)));
                            console.log("kdbx gunzip (from file) time: " + (new Date().getTime() - date) + "ms");
                        }
                        KdbxFormat.assertDecompressedLimit(
                            data.byteLength, this.maxDecompressedBytes);
                        const stm = new BinaryStream(arrayToBuffer(data));
                        this.kdbx.header.readInnerHeader(stm, this.ctx);
                        data = stm.readBytesToEnd();
                        const xmlStr = bytesToString(data);
                        this.kdbx.xml = XmlUtils.parse(xmlStr);
                        return this.setProtectedValues().then(() => {
                            return this.kdbx.loadFromXml(this.ctx).then(() =>
                                this.postLoadBinaries()
                            ).then(() => {
                                this.cleanXml();
                                return this.kdbx;
                            });
                        });
                    });
                });
            });
        });
    }

    /**
     * AES-CBC v4 退化：lseek 到 dataOffset 读剩余 → 走整缓冲 loadV4
     */
    private loadV4FromFileFallback(fileFd: number, dataOffset: number,
        keys: { hmacKey: ArrayBuffer; cipherKey: ArrayBuffer }, stm: BinaryStream): Promise<Kdbx> {
        // 读剩余文件到 ArrayBuffer
        fs.lseek(fileFd, 0, 0);
        const allBuf = new ArrayBuffer(256 * 1024);
        return fs.read(fileFd, allBuf).then((n) => {
            // 重新构造完整 buffer（header 已在 stm 中，需要从文件读全部）
            // 简化：直接从 dataOffset 读剩余
            fs.lseek(fileFd, dataOffset, 0);
            // 估算剩余大小：先 stat
            return fs.stat(fileFd).then((stat) => {
                const remainingSize = stat.size - dataOffset;
                const remainingBuf = new ArrayBuffer(remainingSize);
                return fs.read(fileFd, remainingBuf).then(() => {
                    return HmacBlockTransform.decrypt(remainingBuf, keys.hmacKey).then((data) => {
                        zeroBuffer(keys.hmacKey);
                        return this.decryptData(data, keys.cipherKey).then((data) => {
                            zeroBuffer(keys.cipherKey);
                            if (this.kdbx.header.compression === CompressionAlgorithm.GZip) {
                                data = arrayToBuffer(ungzip(new Uint8Array(data)));
                            }
                            KdbxFormat.assertDecompressedLimit(
                                (data as ArrayBuffer).byteLength, this.maxDecompressedBytes);
                            const innerStm = new BinaryStream(arrayToBuffer(data));
                            this.kdbx.header.readInnerHeader(innerStm, this.ctx);
                            data = innerStm.readBytesToEnd();
                            const xmlStr = bytesToString(data);
                            this.kdbx.xml = XmlUtils.parse(xmlStr);
                            return this.setProtectedValues().then(() => {
                                return this.kdbx.loadFromXml(this.ctx).then(() =>
                                    this.postLoadBinaries()
                                ).then(() => {
                                    this.cleanXml();
                                    return this.kdbx;
                                });
                            });
                        });
                    });
                });
            });
        });
    }

    /**
     * v3 退化：读入整缓冲走 load()
     */
    private loadFromFileFallbackV3(fileFd: number, stm: BinaryStream, headerRead: number): Promise<Kdbx> {
        return fs.stat(fileFd).then((stat) => {
            const fullBuf = new ArrayBuffer(stat.size);
            fs.lseek(fileFd, 0, 0);
            return fs.read(fileFd, fullBuf).then(() => {
                return this.load(fullBuf);
            });
        });
    }

    private loadV3(stm: BinaryStream): Promise<Kdbx> {
        return this.decryptXmlV3(stm).then((xmlStr) => {
            KdbxFormat.assertDecompressedLimit(xmlStr.length * 2, this.maxDecompressedBytes);
            this.kdbx.xml = XmlUtils.parse(xmlStr);
            return this.setProtectedValues().then(() => {
                return this.kdbx.loadFromXml(this.ctx).then(() => {
                    return this.checkHeaderHashV3(stm).then(() => {
                        this.cleanXml();
                        return this.kdbx;
                    });
                });
            });
        });
    }

    private loadV4(stm: BinaryStream): Promise<Kdbx> {
        return this.getHeaderHash(stm).then((headerSha) => {
            const expectedHeaderSha = stm.readBytes(headerSha.byteLength);
            if (!arrayBufferEquals(expectedHeaderSha, headerSha)) {
                throw new KdbxError(ErrorCodes.FileCorrupt, 'header hash mismatch');
            }
            return this.computeKeysV4().then((keys) => {
                return this.getHeaderHmac(stm, keys.hmacKey).then((headerHmac) => {
                    const expectedHeaderHmac = stm.readBytes(headerHmac.byteLength);
                    if (!arrayBufferEquals(expectedHeaderHmac, headerHmac)) {
                        throw new KdbxError(ErrorCodes.InvalidKey);
                    }
                    return HmacBlockTransform.decrypt(stm.readBytesToEnd(), keys.hmacKey).then(
                        (data) => {
                            zeroBuffer(keys.hmacKey);
                            return this.decryptData(data, keys.cipherKey).then((data) => {
                                zeroBuffer(keys.cipherKey);
                                if (this.kdbx.header.compression === CompressionAlgorithm.GZip) {
                                    const date = new Date().getTime();
                                    data = arrayToBuffer(ungzip(new Uint8Array(data)));
                                    console.log("kdbx gunzip time: " + (new Date().getTime() - date) + "ms");
                                }
                                KdbxFormat.assertDecompressedLimit(
                                    (data as ArrayBuffer).byteLength, this.maxDecompressedBytes);
                                stm = new BinaryStream(arrayToBuffer(data));
                                this.kdbx.header.readInnerHeader(stm, this.ctx);
                                data = stm.readBytesToEnd();
                                const xmlStr = bytesToString(data);
                                this.kdbx.xml = XmlUtils.parse(xmlStr);
                                return this.setProtectedValues().then(() => {
                                    return this.kdbx.loadFromXml(this.ctx).then(() =>
                                        this.postLoadBinaries()
                                    ).then(() => {
                                        this.cleanXml();
                                        return this.kdbx;
                                    });
                                });
                            });
                        }
                    );
                });
            });
        });
    }

    /**
     * CP2' 模型守卫：解压后载荷超过上限时抛错中止，避免进入 DOM/字符串放大阶段
     */
    private static assertDecompressedLimit(payloadBytes: number, maxDecompressedBytes: number | undefined): void {
        if (maxDecompressedBytes !== undefined && payloadBytes > maxDecompressedBytes) {
            throw new KdbxError(
                ErrorCodes.DecompressedTooLarge,
                `decompressed payload ${payloadBytes} exceeds limit ${maxDecompressedBytes}`
            );
        }
    }

    /**
     * S4 附件磁盘化：v4 加载完成后按阈值把附件池转入加密缓存。
     * store 未设置 / 阈值未配置 / v3 时为 no-op（小库零行为差异）。
     * 磁盘已存在同哈希附件时直接复用缓存，不重复加密写盘。
     */
    private postLoadBinaries(): Promise<void> {
        const threshold = this.attachmentsDiskThreshold;
        if (!this.kdbx.binaries.store || !threshold || this.kdbx.versionMajor < 4) {
            return Promise.resolve();
        }
        return this.kdbx.binaries.maybeConvertToDiskRefs(threshold).then((converted) => {
            if (converted) {
                // entry.binaries 仍持有旧共享值，替换为磁盘引用后内存附件才可被 GC
                this.kdbx.rebindEntryBinaries();
            }
        });
    }

    loadXml(xmlStr: string): Promise<Kdbx> {
        return this.kdbx.credentials.ready.then(() => {
            this.kdbx.header = KdbxHeader.create();
            this.kdbx.xml = XmlUtils.parse(xmlStr);
            XmlUtils.protectPlainValues(this.kdbx.xml.documentElement);
            return this.kdbx.loadFromXml(this.ctx).then(() => {
                this.cleanXml();
                return this.kdbx;
            });
        });
    }

    save(): Promise<ArrayBuffer> {
        return this.kdbx.credentials.ready.then(() => {
            const stm = new BinaryStream();
            this.kdbx.header.generateSalts();
            this.kdbx.header.write(stm);
            if (this.kdbx.versionMajor === 3) {
                // v3 附件池内联写入 Meta，磁盘引用必须先物化回内存
                return this.kdbx.binaries.materializeDiskRefs().then(() => {
                    this.kdbx.rebindEntryBinaries();
                    return this.saveV3(stm);
                });
            } else if (this.kdbx.versionMajor === 4) {
                return this.saveV4(stm);
            } else {
                throw new KdbxError(
                    ErrorCodes.InvalidVersion,
                    `bad version: ${this.kdbx.versionMajor}`
                );
            }
        });
    }

    private saveV3(stm: BinaryStream): Promise<ArrayBuffer> {
        return this.getHeaderHash(stm).then((headerHash) => {
            this.kdbx.meta.headerHash = headerHash;
            this.kdbx.buildXml(this.ctx);
            return this.getProtectSaltGenerator().then((gen) => {
                if (!this.kdbx.xml) {
                    throw new KdbxError(ErrorCodes.InvalidState, 'no xml');
                }
                XmlUtils.updateProtectedValuesSalt(this.kdbx.xml.documentElement, gen);
                return this.encryptXmlV3().then((data) => {
                    this.cleanXml();
                    stm.writeBytes(data);
                    return stm.getWrittenBytes();
                });
            });
        });
    }

    private saveV4(stm: BinaryStream): Promise<ArrayBuffer> {
        this.kdbx.buildXml(this.ctx);
        return this.getHeaderHash(stm).then((headerSha) => {
            stm.writeBytes(headerSha);
            return this.computeKeysV4().then((keys) => {
                return this.getHeaderHmac(stm, keys.hmacKey).then((headerHmac) => {
                    stm.writeBytes(headerHmac);
                    return this.getProtectSaltGenerator().then((gen) => {
                        if (!this.kdbx.xml) {
                            throw new KdbxError(ErrorCodes.InvalidState, 'no xml');
                        }
                        XmlUtils.updateProtectedValuesSalt(this.kdbx.xml.documentElement, gen);
                        const xml = XmlUtils.serialize(this.kdbx.xml);
                        const innerHeaderStm = new BinaryStream();
                        // 磁盘引用附件在此从加密缓存按需读回后写出
                        return this.kdbx.header.writeInnerHeader(innerHeaderStm, this.ctx).then(
                            () => {
                                const innerHeaderData = innerHeaderStm.getWrittenBytes();
                                const xmlData = arrayToBuffer(stringToBytes(xml));
                                let data = new ArrayBuffer(innerHeaderData.byteLength + xmlData.byteLength);
                                const dataArr = new Uint8Array(data);
                                dataArr.set(new Uint8Array(innerHeaderData));
                                dataArr.set(new Uint8Array(xmlData), innerHeaderData.byteLength);
                                zeroBuffer(xmlData);
                                zeroBuffer(innerHeaderData);
                                if (this.kdbx.header.compression === CompressionAlgorithm.GZip) {
                                    const date = new Date().getTime();
                                    data = arrayToBuffer(gzip(new Uint8Array(data)));
                                    console.log("kdbx gzip time: " + (new Date().getTime() - date) + "ms");
                                }
                                return this.encryptData(arrayToBuffer(data), keys.cipherKey).then(
                                    (data) => {
                                        zeroBuffer(keys.cipherKey);
                                        return HmacBlockTransform.encrypt(data, keys.hmacKey).then(
                                            (data) => {
                                                this.cleanXml();
                                                zeroBuffer(keys.hmacKey);
                                                stm.writeBytes(data);
                                                return stm.getWrittenBytes();
                                            }
                                        );
                                    }
                                );
                            }
                        );
                    });
                });
            });
        });
    }

    saveXml(prettyPrint = false, writeBinaries=true): Promise<string> {
        return this.kdbx.credentials.ready.then(() => {
            // 导出 XML 时附件池以 base64 内联写入 Meta，磁盘引用必须先物化
            const prepare = writeBinaries
                ? this.kdbx.binaries.materializeDiskRefs().then(() => {
                    this.kdbx.rebindEntryBinaries();
                })
                : Promise.resolve();
            return prepare.then(() => {
                this.kdbx.header.generateSalts();
                this.ctx.exportXml = writeBinaries;
                this.kdbx.buildXml(this.ctx);
                if (!this.kdbx.xml) {
                    throw new KdbxError(ErrorCodes.InvalidState, 'no xml');
                }
                XmlUtils.unprotectValues(this.kdbx.xml.documentElement);
                const xml = XmlUtils.serialize(this.kdbx.xml, prettyPrint);
                XmlUtils.protectUnprotectedValues(this.kdbx.xml.documentElement);
                this.cleanXml();
                return xml;
            });
        });
    }

    private decryptXmlV3(stm: BinaryStream): Promise<string> {
        const data = stm.readBytesToEnd();
        return this.getMasterKeyV3().then((masterKey) => {
            return this.decryptData(data, masterKey).then((data) => {
                zeroBuffer(masterKey);
                data = this.trimStartBytesV3(data);
                return HashedBlockTransform.decrypt(data).then((data) => {
                    if (this.kdbx.header.compression === CompressionAlgorithm.GZip) {
                        data = arrayToBuffer(ungzip(new Uint8Array(data)));
                    }
                    return bytesToString(data);
                });
            });
        });
    }

    private encryptXmlV3(): Promise<ArrayBuffer> {
        if (!this.kdbx.xml) {
            throw new KdbxError(ErrorCodes.InvalidState, 'no xml');
        }
        const xml = XmlUtils.serialize(this.kdbx.xml);
        let data = arrayToBuffer(stringToBytes(xml));
        if (this.kdbx.header.compression === CompressionAlgorithm.GZip) {
            data = arrayToBuffer(gzip(new Uint8Array(data)));
        }
        return HashedBlockTransform.encrypt(arrayToBuffer(data)).then((data) => {
            if (!this.kdbx.header.streamStartBytes) {
                throw new KdbxError(ErrorCodes.InvalidState, 'no header start bytes');
            }
            const ssb = new Uint8Array(this.kdbx.header.streamStartBytes);
            const newData = new Uint8Array(data.byteLength + ssb.length);
            newData.set(ssb);
            newData.set(new Uint8Array(data), ssb.length);
            data = newData;
            return this.getMasterKeyV3().then((masterKey) => {
                return this.encryptData(arrayToBuffer(data), masterKey).then((data) => {
                    zeroBuffer(masterKey);
                    return data;
                });
            });
        });
    }

    private getMasterKeyV3(): Promise<ArrayBuffer> {
        return this.kdbx.credentials.getHash().then((credHash) => {
            if (
                !this.kdbx.header.transformSeed ||
                !this.kdbx.header.keyEncryptionRounds ||
                !this.kdbx.header.masterSeed
            ) {
                throw new KdbxError(ErrorCodes.FileCorrupt, 'no header transform parameters');
            }
            const transformSeed = this.kdbx.header.transformSeed;
            const transformRounds = this.kdbx.header.keyEncryptionRounds;
            const masterSeed = this.kdbx.header.masterSeed;

            return this.kdbx.credentials.getChallengeResponse(masterSeed).then((chalResp) => {
                return KeyEncryptorAes.encrypt(
                    new Uint8Array(credHash),
                    transformSeed,
                    transformRounds
                ).then((encKey) => {
                    zeroBuffer(credHash);
                    return CryptoEngine.sha256(encKey).then((keyHash) => {
                        zeroBuffer(encKey);

                        const chalRespLength = chalResp ? chalResp.byteLength : 0;
                        const all = new Uint8Array(
                            masterSeed.byteLength + keyHash.byteLength + chalRespLength
                        );
                        all.set(new Uint8Array(masterSeed), 0);
                        if (chalResp) {
                            all.set(new Uint8Array(chalResp), masterSeed.byteLength);
                        }
                        all.set(new Uint8Array(keyHash), masterSeed.byteLength + chalRespLength);

                        zeroBuffer(keyHash);
                        zeroBuffer(masterSeed);
                        if (chalResp) {
                            zeroBuffer(chalResp);
                        }

                        return CryptoEngine.sha256(all.buffer).then((masterKey) => {
                            zeroBuffer(all.buffer);
                            return masterKey;
                        });
                    });
                });
            });
        });
    }

    private trimStartBytesV3(data: ArrayBuffer): ArrayBuffer {
        if (!this.kdbx.header.streamStartBytes) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no stream start bytes');
        }
        const ssb = this.kdbx.header.streamStartBytes;
        if (data.byteLength < ssb.byteLength) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'short start bytes');
        }
        if (!arrayBufferEquals(data.slice(0, this.kdbx.header.streamStartBytes.byteLength), ssb)) {
            throw new KdbxError(ErrorCodes.InvalidKey);
        }
        return data.slice(ssb.byteLength);
    }

    private setProtectedValues(): Promise<void> {
        return this.getProtectSaltGenerator().then((gen) => {
            if (!this.kdbx.xml) {
                throw new KdbxError(ErrorCodes.InvalidState, 'no xml');
            }
            XmlUtils.setProtectedValues(this.kdbx.xml.documentElement, gen);
        });
    }

    private getProtectSaltGenerator(): Promise<ProtectSaltGenerator> {
        if (!this.kdbx.header.protectedStreamKey || !this.kdbx.header.crsAlgorithm) {
            throw new KdbxError(ErrorCodes.InvalidState, 'bad header parameters');
        }
        return ProtectSaltGenerator.create(
            this.kdbx.header.protectedStreamKey,
            this.kdbx.header.crsAlgorithm
        );
    }

    private getHeaderHash(stm: BinaryStream): Promise<ArrayBuffer> {
        if (!this.kdbx.header.endPos) {
            throw new KdbxError(ErrorCodes.InvalidState, 'no end pos');
        }
        const src = stm.readBytesNoAdvance(0, this.kdbx.header.endPos);
        return CryptoEngine.sha256(src);
    }

    private getHeaderHmac(stm: BinaryStream, key: ArrayBuffer): Promise<ArrayBuffer> {
        if (!this.kdbx.header.endPos) {
            throw new KdbxError(ErrorCodes.InvalidState, 'no end pos');
        }
        const src = stm.readBytesNoAdvance(0, this.kdbx.header.endPos);
        return HmacBlockTransform.getHmacKey(key, new Int64(0xffffffff, 0xffffffff)).then(
            (keySha) => {
                return CryptoEngine.hmacSha256(keySha, src);
            }
        );
    }

    private checkHeaderHashV3(stm: BinaryStream) {
        if (this.kdbx.meta.headerHash) {
            const metaHash = this.kdbx.meta.headerHash;
            return this.getHeaderHash(stm).then((actualHash) => {
                if (!arrayBufferEquals(metaHash, actualHash)) {
                    throw new KdbxError(ErrorCodes.FileCorrupt, 'header hash mismatch');
                }
            });
        } else {
            return Promise.resolve();
        }
    }

    private computeKeysV4() {
        const masterSeed = this.kdbx.header.masterSeed;
        if (!masterSeed || masterSeed.byteLength !== 32) {
            return Promise.reject(new KdbxError(ErrorCodes.FileCorrupt, 'bad master seed'));
        }
        const kdfParams = this.kdbx.header.kdfParameters;
        if (!kdfParams) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no kdf params');
        }
        const kdfSalt = kdfParams.get('S');
        if (!(kdfSalt instanceof ArrayBuffer)) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no salt');
        }
        return this.kdbx.credentials.getHash(kdfSalt).then((credHash) => {
            return KeyEncryptorKdf.encrypt(credHash, kdfParams).then((encKey) => {
                zeroBuffer(credHash);
                if (!encKey || encKey.byteLength !== 32) {
                    return Promise.reject(new KdbxError(ErrorCodes.Unsupported, 'bad derived key'));
                }
                const keyWithSeed = new Uint8Array(65);
                keyWithSeed.set(new Uint8Array(masterSeed), 0);
                keyWithSeed.set(new Uint8Array(encKey), masterSeed.byteLength);
                keyWithSeed[64] = 1;
                zeroBuffer(encKey);
                zeroBuffer(masterSeed);
                return Promise.all([
                    CryptoEngine.sha256(keyWithSeed.buffer.slice(0, 64)),
                    CryptoEngine.sha512(keyWithSeed.buffer)
                ]).then((keys) => {
                    zeroBuffer(keyWithSeed);
                    return { cipherKey: keys[0], hmacKey: keys[1] };
                });
            });
        });
    }

    private decryptData(data: ArrayBuffer, cipherKey: ArrayBuffer): Promise<ArrayBuffer> {
        const cipherId = this.kdbx.header.dataCipherUuid;
        if (!cipherId) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no cipher id');
        }
        switch (cipherId.toString()) {
            case CipherId.Aes:
                return this.transformDataV4Aes(data, cipherKey, false);
            case CipherId.ChaCha20:
                return this.transformDataV4ChaCha20(data, cipherKey);
            default:
                return Promise.reject(new KdbxError(ErrorCodes.Unsupported, 'unsupported cipher'));
        }
    }

    private encryptData(data: ArrayBuffer, cipherKey: ArrayBuffer): Promise<ArrayBuffer> {
        const cipherId = this.kdbx.header.dataCipherUuid;
        if (!cipherId) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no cipher id');
        }
        switch (cipherId.toString()) {
            case CipherId.Aes:
                return this.transformDataV4Aes(data, cipherKey, true);
            case CipherId.ChaCha20:
                return this.transformDataV4ChaCha20(data, cipherKey);
            default:
                return Promise.reject(new KdbxError(ErrorCodes.Unsupported, 'unsupported cipher'));
        }
    }

    private transformDataV4Aes(
        data: ArrayBuffer,
        cipherKey: ArrayBuffer,
        encrypt: boolean
    ): Promise<ArrayBuffer> {
        const aesCbc = CryptoEngine.createAesCbc();
        const iv = this.kdbx.header.encryptionIV;
        if (!iv) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no encryption IV');
        }
        return aesCbc.importKey(cipherKey).then(() => {
            return encrypt ? aesCbc.encrypt(data, iv) : aesCbc.decrypt(data, iv);
        });
    }

    private transformDataV4ChaCha20(
        data: ArrayBuffer,
        cipherKey: ArrayBuffer
    ): Promise<ArrayBuffer> {
        const iv = this.kdbx.header.encryptionIV;
        if (!iv) {
            throw new KdbxError(ErrorCodes.FileCorrupt, 'no encryption IV');
        }
        return CryptoEngine.chacha20(data, cipherKey, iv);
    }

    private cleanXml() {
        if (!this.preserveXml) {
            this.kdbx.xml = undefined;
        }
    }
}
