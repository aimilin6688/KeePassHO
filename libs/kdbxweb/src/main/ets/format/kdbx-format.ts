import { gzip, ungzip } from '@ohos/flate2';
import { fileIo as fs, statfs } from '@kit.CoreFileKit';
import { Document } from '@xmldom/xmldom';
import { Kdbx } from './kdbx';
import { CipherId, CompressionAlgorithm, ErrorCodes } from '../defs/consts';
import { KdbxError } from '../errors/kdbx-error';
import { BinaryStream } from '../utils/binary-stream';
import { KdbxContext } from './kdbx-context';
import { KdbxHeader, readFileRegion } from './kdbx-header';
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
import { ValueType } from '../utils/var-dictionary';
import * as ZlibFile from '../utils/zlib-file';
import {
    FileChunkReader,
    KdbxStreamingXmlLoader
} from '../utils/xml-pull-parser';
import { KdbxSnapshot } from './kdbx-snapshot';

/**
 * 容器分块写出器：v3 直传容器产出侧的宿主注入接口
 * （Worker 侧为会话密钥分块包裹流，测试可为内存收集器）
 */
export interface ContainerChunkWriter {
    writeChunk(data: Uint8Array): Promise<void>;
}

/**
 * 保存选项（XC 挑战-应答两阶段保存，方案 §9.3）：
 * kdfSalt 由调用方在保存入口预生成并完成 NFC 挑战后注入——
 * generateSalts() 之后覆盖 KDF seed 'S'，使写出的 seed 与
 * 已取得的挑战应答严格配对（KeePassXC 为保存内嵌挑战，本项目
 * Worker 架构下等价实现）。不传时行为与现状完全一致。
 */
export interface SaveOptions {
    kdfSalt?: ArrayBuffer;
}

export class KdbxFormat {
    /** S5：inner Binary 字段超过该值时流式落盘附件缓存，不整读入内存 */
    private static readonly LARGE_BINARY_STREAM_THRESHOLD = 4 * 1024 * 1024;
    /** S5：流式 inflate 前要求的磁盘余量安全垫（T2 写入 + 解析期临时占用） */
    private static readonly STREAM_DISK_MARGIN = 64 * 1024 * 1024;
    /**
     * §7.2 流式拉取解析器开关：true 时 parseInnerFileStreaming 走手写状态机
     * 解析器（不建 DOM），false 时走既有 xmldom DOM 路径（差分测试对照）。
     * 差分测试全绿后 DOM 路径退役。
     */
    static streamingXmlParse: boolean = true;

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
     * 从文件流式加载（S4 流式解密管道 T0→T1，S5 流式解压 T1→T2）
     * 预读 header 到 BinaryStream，ChaCha20 v4 用 decryptFromFile 流式解密到 t1Path，
     * t2Path 提供时走 S5 流式解压 + inner header 文件解析 + 附件落盘；
     * AES-CBC v4 或 v3 退化为整缓冲（读入内存走 load()）
     * @param filePath KDBX 文件路径
     * @param t1Path 解密后 gz 数据的临时文件路径（由调用方管理生命周期）
     * @param t2Path 解压后 inner 明文的临时文件路径（可选；不提供则整缓冲 ungzip）
     */
    loadFromFile(filePath: string, t1Path: string, t2Path?: string): Promise<Kdbx> {
        return this.kdbx.credentials.ready.then(() => {
            return fs.open(filePath, fs.OpenMode.READ_ONLY).then((file) => {
                return this.loadFromFileInner(file.fd, t1Path, t2Path).then((kdbx) => {
                    return fs.close(file.fd).then(() => kdbx);
                });
            });
        });
    }

    /**
     * v3 直传容器产出（M0 直传，Worker 快路径）：T0 → 流式解密 T1 → 流式解压 T2 →
     * inner header 文件解析（附件落盘）→ v3 容器前缀（内存构建）→
     * XML 区从 inner 文件分块流式拷入 containerWriter——全程不构建模型、
     * 不 materialize 整段 XML（消除跨线程双重构建）。
     * 仅 v4 + ChaCha20 支持；其余格式抛 Unsupported（调用方回退全模型 KPSN 路径）。
     * 守卫拒绝（DecompressedTooLarge/NotEnoughDisk）与真实加载错误（InvalidKey/FileCorrupt）
     * 原样上抛；解压阶段非守卫失败映射为 Unsupported 交由调用方回退（保留旧行为可恢复性）
     * @param filePath KDBX 文件路径
     * @param t1Path 解密后 gz 临时文件路径
     * @param t2Path 解压后 inner 明文临时文件路径
     * @param containerWriter 容器分块写出器（宿主注入，如会话密钥分块包裹流）
     */
    loadToContainerFile(
        filePath: string,
        t1Path: string,
        t2Path: string,
        containerWriter: ContainerChunkWriter
    ): Promise<void> {
        return this.kdbx.credentials.ready.then(() => {
            return fs.open(filePath, fs.OpenMode.READ_ONLY).then((file) => {
                return this.loadToContainerFileInner(file.fd, t1Path, t2Path, containerWriter).then(
                    () => fs.close(file.fd),
                    (e) => fs.close(file.fd).then(
                        () => Promise.reject(e),
                        () => Promise.reject(e)
                    )
                );
            });
        });
    }

    private loadToContainerFileInner(
        fileFd: number,
        t1Path: string,
        t2Path: string,
        containerWriter: ContainerChunkWriter
    ): Promise<void> {
        // 预读 header（与 loadFromFileInner 同源）
        const headerBuf = new ArrayBuffer(256 * 1024);
        return fs.read(fileFd, headerBuf).then((totalRead) => {
            const stm = new BinaryStream(headerBuf.slice(0, totalRead));
            this.kdbx.header = KdbxHeader.read(stm, this.ctx);
            if (this.kdbx.header.versionMajor !== 4) {
                throw new KdbxError(ErrorCodes.Unsupported, 'container fast-path requires kdbx v4');
            }
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
                        const dataOffset = stm.pos;
                        const cipherId = this.kdbx.header.dataCipherUuid;
                        if (!cipherId || cipherId.toString() !== CipherId.ChaCha20) {
                            throw new KdbxError(
                                ErrorCodes.Unsupported,
                                'container fast-path requires ChaCha20'
                            );
                        }
                        const iv = this.kdbx.header.encryptionIV;
                        if (!iv) {
                            throw new KdbxError(ErrorCodes.FileCorrupt, 'no encryption IV');
                        }
                        const chaCha = new ChaCha20(new Uint8Array(keys.cipherKey), new Uint8Array(iv));
                        const decryptBlock = (data: Uint8Array): void => {
                            chaCha.xorInPlace(data);
                        };
                        fs.lseek(fileFd, dataOffset, 0 /* SEEK_SET */);
                        return HmacBlockTransform.decryptFromFile(
                            fileFd, t1Path, keys.hmacKey, decryptBlock
                        ).then(() => {
                            zeroBuffer(keys.hmacKey);
                            zeroBuffer(keys.cipherKey);
                            // 解压阶段：守卫拒绝直接抛；非守卫失败映射 Unsupported（调用方回退全模型路径）
                            return this.prepareInnerFileStreaming(t1Path, t2Path).then(
                                (innerPath) => this.writeContainerFromInnerFile(innerPath, containerWriter),
                                (e) => {
                                    if (e instanceof KdbxError &&
                                        (e.code === ErrorCodes.DecompressedTooLarge ||
                                            e.code === ErrorCodes.NotEnoughDisk)) {
                                        throw e;
                                    }
                                    throw new KdbxError(
                                        ErrorCodes.Unsupported,
                                        `container fast-path inflate failed: ${e}`
                                    );
                                }
                            );
                        });
                    });
                });
            });
        });
    }

    /**
     * inner 明文文件 → v3 容器：inner header 逐字段（附件落盘/入池）→
     * computeHashes → 容器前缀（内存）→ XML 区 4MB 分块流式拷贝
     */
    private writeContainerFromInnerFile(
        innerPath: string,
        containerWriter: ContainerChunkWriter
    ): Promise<void> {
        return fs.open(innerPath, fs.OpenMode.READ_ONLY).then((file) => {
            const chain = this.kdbx.header
                .readInnerHeaderFromFile(
                    file.fd,
                    this.ctx,
                    KdbxFormat.LARGE_BINARY_STREAM_THRESHOLD
                )
                .then((xmlStart) => fs.stat(file.fd).then((stat) => {
                    const xmlLength = stat.size - xmlStart;
                    if (xmlLength < 0) {
                        throw new KdbxError(ErrorCodes.FileCorrupt, 'inner xml region missing');
                    }
                    KdbxFormat.assertDecompressedLimit(xmlLength, this.maxDecompressedBytes);
                    return this.kdbx.binaries.computeHashes().then(() => {
                        const prefix = KdbxSnapshot.buildV3ContainerPrefix(this.kdbx, true, xmlLength);
                        return containerWriter.writeChunk(prefix).then(() => {
                            const COPY_CHUNK = 4 * 1024 * 1024;
                            let offset = xmlStart;
                            const copyNext = (): Promise<void> => {
                                if (offset >= stat.size) {
                                    return Promise.resolve();
                                }
                                const len = Math.min(COPY_CHUNK, stat.size - offset);
                                const buf = new ArrayBuffer(len);
                                return fs.read(file.fd, buf, { offset }).then((got) => {
                                    const view = got === len
                                        ? new Uint8Array(buf)
                                        : new Uint8Array(buf, 0, got);
                                    offset += got;
                                    return containerWriter.writeChunk(view).then(copyNext);
                                });
                            };
                            return copyNext();
                        });
                    });
                }));
            return chain.then(
                () => fs.close(file.fd),
                (e) => fs.close(file.fd).then(
                    () => Promise.reject(e),
                    () => Promise.reject(e)
                )
            );
        });
    }

    private loadFromFileInner(fileFd: number, t1Path: string, t2Path?: string): Promise<Kdbx> {
        // 预读 header（256KB 足够任何 KDBX outer header + sha + hmac）
        const headerBuf = new ArrayBuffer(256 * 1024);
        return fs.read(fileFd, headerBuf).then((totalRead) => {
            const stm = new BinaryStream(headerBuf.slice(0, totalRead));
            this.kdbx.header = KdbxHeader.read(stm, this.ctx);
            if (this.kdbx.header.versionMajor === 3) {
                // v3 退化为整缓冲
                return this.loadFromFileFallbackV3(fileFd, stm, totalRead);
            } else if (this.kdbx.header.versionMajor === 4) {
                return this.loadV4FromFile(stm, fileFd, t1Path, t2Path);
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
    private loadV4FromFile(
        stm: BinaryStream,
        fileFd: number,
        t1Path: string,
        t2Path?: string
    ): Promise<Kdbx> {
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
                        // 读 T1 → ungzip（S5 流式）/ inner parse
                        return this.parseDecryptedFile(t1Path, t2Path);
                    });
                });
            });
        });
    }

    /**
     * 读解密后的 T1 文件 → 解压 → inner header + XML parse。
     * t2Path 提供时走 S5 流式路径；否则整缓冲 ungzip。
     */
    private parseDecryptedFile(t1Path: string, t2Path?: string): Promise<Kdbx> {
        if (t2Path === undefined) {
            return this.parseDecryptedFileBuffered(t1Path);
        }
        return this.prepareInnerFileStreaming(t1Path, t2Path).then((innerPath) => {
            // inner 明文已就绪。此后失败不再回退整缓冲：
            // inner header 解析会直接向附件池累加、写入 inner 流密钥，
            // 部分应用后重放整缓冲路径会造成状态重复
            return this.parseInnerFileStreaming(innerPath);
        }, (e) => {
            // 解压阶段失败：守卫拒绝直接抛出；其余（native 损坏/IO 异常）
            // 回退整缓冲路径，保留原有错误语义与兼容性
            if (e instanceof KdbxError &&
                (e.code === ErrorCodes.DecompressedTooLarge ||
                    e.code === ErrorCodes.NotEnoughDisk)) {
                throw e;
            }
            return this.parseDecryptedFileBuffered(t1Path);
        });
    }

    /**
     * S5 流式解压：gzip 时 ISIZE 磁盘预检 → native zlib 流式 inflate T1→T2
     * （内存窗口与文件大小解耦）；未压缩时 T1 即 inner 明文。
     * @returns inner 明文文件路径
     */
    private prepareInnerFileStreaming(t1Path: string, t2Path: string): Promise<string> {
        if (this.kdbx.header.compression !== CompressionAlgorithm.GZip) {
            return Promise.resolve(t1Path);
        }
        return ZlibFile.readGzipIsize(t1Path).then((isize) => {
            const inflate = (): Promise<void> => {
                const date = new Date().getTime();
                return ZlibFile.inflateFile(t1Path, t2Path).then(() => {
                    console.log(
                        'kdbx inflate (stream) time: ' + (new Date().getTime() - date) + 'ms'
                    );
                });
            };
            if (isize === undefined || isize <= 0) {
                // ISIZE 不可得（截断/极小文件）：fail-open 直接流式解压
                return inflate().then(() => t2Path);
            }
            return KdbxFormat.checkDiskForStreamInflate(t2Path, isize).then(inflate).then(() => {
                return t2Path;
            });
        });
    }

    /**
     * 流式 inflate 前的磁盘余量守卫（CP-DISK 在加载管道内的延伸，§9）：
     * 剩余空间不足以容纳 T2 + 安全垫时以 NotEnoughDisk 中止，
     * statfs 不可用时 fail-open 交给 inflate 自身的写失败报错。
     */
    private static checkDiskForStreamInflate(t2Path: string, isize: number): Promise<void> {
        const dir = t2Path.substring(0, t2Path.lastIndexOf('/'));
        return statfs.getFreeSize(dir).then((free) => {
            if (free < isize + KdbxFormat.STREAM_DISK_MARGIN) {
                throw new KdbxError(
                    ErrorCodes.NotEnoughDisk,
                    `streaming inflate needs ~${isize} bytes, free ${free}`
                );
            }
        }).catch((e) => {
            if (e instanceof KdbxError) {
                throw e;
            }
            // statfs 失败：fail-open
        });
    }

    /**
     * S5：inner 明文已在文件中（T2 或未压缩 T1）。从文件逐字段解析 inner header，
     * 大附件分块落盘不进内存；仅 XML 区读入内存并做 CP2' 检查后 DOM parse。
     * CP2' 在此按 XML 区大小精确判定——附件型大库的附件池不占内存，
     * 不再受解压总量约束（§10 目标场景）。
     */
    private parseInnerFileStreaming(innerPath: string): Promise<Kdbx> {
        return fs.open(innerPath, fs.OpenMode.READ_ONLY).then((file) => {
            const parseChain = this.kdbx.header
                .readInnerHeaderFromFile(
                    file.fd,
                    this.ctx,
                    KdbxFormat.LARGE_BINARY_STREAM_THRESHOLD
                )
                .then((xmlStart) => {
                    return fs.stat(file.fd).then((stat) => {
                        const xmlLength = stat.size - xmlStart;
                        if (xmlLength < 0) {
                            throw new KdbxError(ErrorCodes.FileCorrupt, 'inner xml region missing');
                        }
                        KdbxFormat.assertDecompressedLimit(xmlLength, this.maxDecompressedBytes);
                        if (KdbxFormat.streamingXmlParse) {
                            return this.parseXmlStreaming(file.fd, xmlStart, xmlLength)
                                .then(() => this.postLoadBinaries())
                                .then(() => {
                                    this.cleanXml();
                                    return this.kdbx;
                                });
                        }
                        return readFileRegion(file.fd, xmlStart, xmlLength).then((xmlBytes) => {
                            const xmlStr = bytesToString(xmlBytes);
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
            return parseChain.then(
                (kdbx) => fs.close(file.fd).then(() => kdbx),
                (e) => fs.close(file.fd).then(
                    () => Promise.reject(e),
                    () => Promise.reject(e)
                )
            );
        });
    }

    /**
     * §7.2 流式拉取解析器：从文件分块读 XML 区（256KB），手写状态机解析，
     * 直接构建模型对象，不建 DOM。ProtectedValue 边解析边用 ProtectSaltGenerator
     * 取 salt（流式 XOR，密钥流状态跨元素保持）。RSS = 模型 + 256KB 窗口。
     * 文档解析结束后 computeHashes + resolve pending entry binary refs。
     */
    private parseXmlStreaming(fd: number, start: number, length: number): Promise<void> {
        const reader = new FileChunkReader(fd, start, length);
        return KdbxStreamingXmlLoader.load(this.kdbx, this.ctx, reader);
    }

    /**
     * 读解密后的 T1 文件 → ungzip（整缓冲）→ CP2' → inner header + XML parse
     */
    private parseDecryptedFileBuffered(t1Path: string): Promise<Kdbx> {
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

    save(opts?: SaveOptions): Promise<ArrayBuffer> {
        return this.kdbx.credentials.ready.then(() => {
            const stm = new BinaryStream();
            // P2-4 M1：保存前评估 4.1 特性，4.0 静默升 4.1（须在 header.write 前）
            this.kdbx.upgradeMinorVersionIfNeeded();
            this.kdbx.header.generateSalts();
            KdbxFormat.applyKdfSaltOverride(this.kdbx, opts);
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

    /**
     * S6 保存管道文件版（设计文档 §2.3）：v4 + ChaCha20 时全链路落盘
     * X1 inner.bin → X2 inner.gz → X3 saved.kdbx，内存窗口与库大小解耦。
     * v3 / AES-CBC 不支持：抛 InvalidVersion / Unsupported，由调用方回退整缓冲 save()。
     * @param outPath X3 成品 KDBX 文件路径（调用方管理生命周期）
     * @param x1Path X1 inner 明文临时文件路径（调用方管理）
     * @param x2Path X2 inner.gz 临时文件路径（调用方管理；未压缩时未使用）
     */
    saveToFile(outPath: string, x1Path: string, x2Path: string, opts?: SaveOptions): Promise<void> {
        return this.kdbx.credentials.ready.then(() => {
            if (this.kdbx.versionMajor !== 4) {
                throw new KdbxError(ErrorCodes.InvalidVersion, 'saveToFile requires kdbx v4');
            }
            const cipherId = this.kdbx.header.dataCipherUuid;
            if (!cipherId || cipherId.toString() !== CipherId.ChaCha20) {
                throw new KdbxError(ErrorCodes.Unsupported, 'saveToFile requires ChaCha20 cipher');
            }
            const stm = new BinaryStream();
            // P2-4 M1：保存前评估 4.1 特性，4.0 静默升 4.1（须在 header.write 前）
            this.kdbx.upgradeMinorVersionIfNeeded();
            this.kdbx.header.generateSalts();
            KdbxFormat.applyKdfSaltOverride(this.kdbx, opts);
            this.kdbx.header.write(stm);
            return this.saveV4ToFile(stm, outPath, x1Path, x2Path);
        });
    }

    private saveV4ToFile(stm: BinaryStream, outPath: string, x1Path: string, x2Path: string): Promise<void> {
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
                        // S6-f：DOM→文件分块序列化，消除 XML 字符串峰值（③b）+ UTF-8 拷贝峰值（③c）
                        // DOM 峰值（③a）仍保留，att-500（3MB XML）DOM ~15MB 在预算内
                        return this.writeInnerToFile(x1Path, this.kdbx.xml).then((x1Bytes) => {
                            // 载荷选择：GZip → deflate 到 X2；None → X1 即载荷
                            let payloadPath = x1Path;
                            let afterDeflate: Promise<void> = Promise.resolve();
                            if (this.kdbx.header.compression === CompressionAlgorithm.GZip) {
                                payloadPath = x2Path;
                                afterDeflate = KdbxFormat.checkDiskForStreamDeflate(x2Path, x1Bytes).then(() => {
                                    const date = new Date().getTime();
                                    return ZlibFile.deflateFile(x1Path, x2Path).then(() => {
                                        console.log('kdbx deflate (stream) time: ' + (new Date().getTime() - date) + 'ms');
                                    });
                                });
                            }
                            return afterDeflate.then(() => {
                                let outFile: fs.File | null = null;
                                const writeAll: Promise<void> = fs.open(
                                    outPath,
                                    fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
                                ).then((out) => {
                                    outFile = out;
                                    return fs.write(out.fd, stm.getWrittenBytes()).then(() => {
                                        const iv = this.kdbx.header.encryptionIV;
                                        if (!iv) {
                                            throw new KdbxError(ErrorCodes.FileCorrupt, 'no encryption IV');
                                        }
                                        const chaCha = new ChaCha20(
                                            new Uint8Array(keys.cipherKey),
                                            new Uint8Array(iv)
                                        );
                                        const encryptBlock = (data: Uint8Array): void => {
                                            chaCha.xorInPlace(data);
                                        };
                                        return HmacBlockTransform.encryptFromFile(
                                            payloadPath, out.fd, keys.hmacKey, encryptBlock
                                        ).then(() => {
                                            this.cleanXml();
                                            zeroBuffer(keys.cipherKey);
                                            zeroBuffer(keys.hmacKey);
                                        });
                                    });
                                }).then(() => undefined);
                                return writeAll.then(
                                    () => {
                                        if (outFile === null) {
                                            return Promise.resolve();
                                        }
                                        return fs.fsync(outFile.fd).then(() => fs.close(outFile.fd));
                                    },
                                    (e: Error) => {
                                        if (outFile !== null) {
                                            try { fs.closeSync(outFile.fd); } catch (ignored) { /* best effort */ }
                                        }
                                        try { fs.unlinkSync(outPath); } catch (ignored) { /* best effort */ }
                                        throw e;
                                    }
                                );
                            });
                        });
                    });
                });
            });
        });
    }

    /**
     * 写 X1 inner 明文文件：inner header 流式分块回读附件 + DOM→文件序列化 XML 追加。
     * @param x1Path X1 文件路径
     * @param xmlDoc 已 updateProtectedValuesSalt 的 DOM 文档
     * @returns X1 文件字节数（供 deflate 磁盘守卫估算）
     */
    private writeInnerToFile(x1Path: string, xmlDoc: Document): Promise<number> {
        let x1File: fs.File | null = null;
        return fs.open(x1Path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC).then((x1) => {
            x1File = x1;
            return this.kdbx.header.writeInnerHeaderToFile(x1.fd, this.ctx).then(() =>
                XmlUtils.serializeToFile(xmlDoc, x1.fd)
            ).then(() => fs.fsync(x1.fd).then(() =>
                fs.stat(x1.fd).then((stat) =>
                    fs.close(x1.fd).then(() => stat.size)
                )
            ));
        }).catch((e: Error) => {
            if (x1File !== null) {
                try { fs.closeSync(x1File.fd); } catch (ignored) { /* best effort */ }
            }
            throw e;
        });
    }

    /**
     * 流式 deflate 前磁盘余量守卫（镜像 checkDiskForStreamInflate）：
     * 剩余空间不足以容纳 X2 + 安全垫时以 NotEnoughDisk 中止，statfs 不可用时 fail-open。
     */
    private static checkDiskForStreamDeflate(x2Path: string, estBytes: number): Promise<void> {
        const dir = x2Path.substring(0, x2Path.lastIndexOf('/'));
        return statfs.getFreeSize(dir).then((free) => {
            if (free < estBytes + KdbxFormat.STREAM_DISK_MARGIN) {
                throw new KdbxError(
                    ErrorCodes.NotEnoughDisk,
                    `streaming deflate needs ~${estBytes} bytes, free ${free}`
                );
            }
        }).catch((e) => {
            if (e instanceof KdbxError) {
                throw e;
            }
            // statfs 失败：fail-open
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
            const transformRounds = this.kdbx.header.keyEncryptionRounds;
            if (
                !this.kdbx.header.transformSeed ||
                transformRounds === undefined ||
                !this.kdbx.header.masterSeed
            ) {
                throw new KdbxError(ErrorCodes.FileCorrupt, 'no header transform parameters');
            }
            const transformSeed = this.kdbx.header.transformSeed;
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

    /**
     * XC 两阶段保存：注入预挑战 KDF salt（§9.3）。
     * generateSalts() 之后用调用方预生成（已完成 NFC 挑战取应答）的 salt
     * 覆盖 kdfParameters 'S'，保证写出的 KDF seed 与挑战应答配对一致。
     * 仅 KDBX4（'S' 仅存在于 v4 KDF 参数）；salt 必须 32 字节。
     * 不传 kdfSalt 时无操作（保存行为与现状一致）。
     */
    private static applyKdfSaltOverride(kdbx: Kdbx, opts?: SaveOptions): void {
        const kdfSalt: ArrayBuffer | undefined = opts?.kdfSalt;
        if (!kdfSalt) {
            return;
        }
        if (kdbx.versionMajor !== 4) {
            throw new KdbxError(ErrorCodes.Unsupported, 'kdfSalt override requires kdbx v4');
        }
        if (kdfSalt.byteLength !== 32) {
            throw new KdbxError(ErrorCodes.InvalidArg, 'kdfSalt must be 32 bytes');
        }
        const kdfParameters = kdbx.header.kdfParameters;
        if (!kdfParameters) {
            throw new KdbxError(ErrorCodes.InvalidState, 'no kdf params');
        }
        kdfParameters.set('S', ValueType.Bytes, kdfSalt);
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
