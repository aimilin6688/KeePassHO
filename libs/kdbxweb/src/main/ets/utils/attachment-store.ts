import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { ChaCha20 } from '../crypto/chacha20';
import * as CryptoEngine from '../crypto/crypto-engine';
import { ErrorCodes } from '../defs/consts';
import { KdbxError } from '../errors/kdbx-error';
import {
    arrayBufferEquals,
    arrayToBuffer,
    bytesToHex,
    hexToBytes,
    zeroBuffer
} from './byte-utils';

const KEY_LENGTH = 32;
const NONCE_LENGTH = 12;
const HASH_LENGTH = 32;
const FILE_SUFFIX = '.bin';
const TMP_SUFFIX = '.tmp';
const FILENAME_PATTERN = /^[0-9a-f]{64}\.bin$/;
/** S5 流式搬运分块：附件从源文件区域转储到缓存的窗口大小 */
const REGION_CHUNK_SIZE = 4 * 1024 * 1024;

/**
 * 计算文件指定区域的 sha256（S5 流式加载路径）：
 * 4MB 分块增量喂入 cryptoFramework Md，全程不整读区域内容。
 * @returns 十六进制哈希
 */
export function sha256FileRegion(fileFd: number, offset: number, length: number): Promise<string> {
    if (length <= 0) {
        return Promise.resolve(
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        );
    }
    const md = cryptoFramework.createMd('SHA256');
    let chain: Promise<void> = Promise.resolve();
    let position = offset;
    let remaining = length;
    while (remaining > 0) {
        const readLen = Math.min(remaining, REGION_CHUNK_SIZE);
        const readAt = position;
        const buf = new ArrayBuffer(readLen);
        chain = chain.then(() => {
            return fs.read(fileFd, buf, { offset: readAt }).then((read) => {
                if (read !== readLen) {
                    throw new KdbxError(ErrorCodes.FileCorrupt, 'file region short read');
                }
                md.updateSync({ data: new Uint8Array(buf, 0, read) });
            });
        });
        position += readLen;
        remaining -= readLen;
    }
    return chain.then(() => bytesToHex(new Uint8Array(md.digestSync().data)));
}

/**
 * 内容寻址的附件加密磁盘缓存（S4 附件磁盘化）。
 *
 * 文件名 = HMAC-SHA256(storeKey, contentHash)，与内容哈希单向绑定：
 * 换库/换密钥后旧缓存不可复用；文件内容为 [12B nonce][ChaCha20 密文]，
 * 明文不落盘（§2.1 明文落盘必加密）。
 *
 * put() 在缓存命中（磁盘已存在同哈希文件）时直接复用，不重复序列化/加密/写盘。
 * get() 解密后校验 sha256 与请求哈希一致，防止磁盘损坏静默返回错数据。
 */
export class AttachmentStore {
    private readonly dir: string;
    private readonly key: Uint8Array;

    constructor(dir: string, key: Uint8Array) {
        if (!dir) {
            throw new KdbxError(ErrorCodes.InvalidArg, 'attachment store dir');
        }
        if (!(key instanceof Uint8Array) || key.length !== KEY_LENGTH) {
            throw new KdbxError(ErrorCodes.InvalidArg, 'attachment store key');
        }
        this.dir = dir;
        // 拷贝一份，调用方可以随时清零自己的 key 缓冲
        this.key = new Uint8Array(key);
        try {
            fs.mkdirSync(this.dir, true);
        } catch (e) {
            // 已存在则忽略，其余错误在首次读写时暴露
        }
    }

    private fileName(hash: string): Promise<string> {
        let hashBytes: Uint8Array;
        try {
            hashBytes = hexToBytes(hash);
        } catch (e) {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidArg, 'bad attachment hash'));
        }
        if (hashBytes.length !== HASH_LENGTH) {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidArg, 'bad attachment hash'));
        }
        return CryptoEngine.hmacSha256(
            arrayToBuffer(this.key),
            arrayToBuffer(hashBytes)
        ).then((mac) => bytesToHex(new Uint8Array(mac)) + FILE_SUFFIX);
    }

    has(hash: string): Promise<boolean> {
        return this.fileName(hash).then((name) =>
            fs.access(this.pathOf(name)).then((exists) => exists).catch(() => false)
        );
    }

    /**
     * 写入附件缓存；磁盘已存在同哈希文件时直接复用（仅刷新 LRU 时间）。
     */
    put(hash: string, data: ArrayBuffer): Promise<void> {
        return this.fileName(hash).then((name) => {
            const path = this.pathOf(name);
            return fs.access(path).then((exists) => {
                if (exists) {
                    this.touch(path);
                    return;
                }
                return this.writeEncrypted(path, name, hash, data);
            }).catch(() => this.writeEncrypted(path, name, hash, data));
        });
    }

    /**
     * 流式写入附件缓存（S5）：附件字节仍在源文件（解压后的 T2）的指定区间内，
     * 4MB 分块读取 → ChaCha20 分块加密 → 临时文件 fsync → rename 到内容寻址路径，
     * 全程不把附件整读入内存（窗口 = 4MB 分块，设计文档 §6）。
     * 磁盘已存在同哈希文件时直接复用（仅刷新 LRU 时间）。
     */
    putFromFileRegion(hash: string, srcFd: number, offset: number, length: number): Promise<void> {
        return this.fileName(hash).then((name) => {
            const path = this.pathOf(name);
            return fs.access(path).then((exists) => {
                if (exists) {
                    this.touch(path);
                    return;
                }
                return this.writeEncryptedRegion(path, name, srcFd, offset, length);
            }).catch(() => this.writeEncryptedRegion(path, name, srcFd, offset, length));
        });
    }

    /**
     * 读取并解密附件，校验内容哈希。
     */
    get(hash: string): Promise<ArrayBuffer> {
        return this.fileName(hash).then((name) => {
            const path = this.pathOf(name);
            let file: fs.File | null = null;
            return fs.open(path, fs.OpenMode.READ_ONLY).then((f) => {
                file = f;
                return fs.stat(f.fd).then((stat) => {
                    if (stat.size < NONCE_LENGTH) {
                        throw new KdbxError(ErrorCodes.FileCorrupt, 'attachment cache truncated');
                    }
                    const raw = new ArrayBuffer(stat.size);
                    return fs.read(f.fd, raw).then((read) => {
                        if (read !== stat.size) {
                            throw new KdbxError(ErrorCodes.FileCorrupt, 'attachment cache short read');
                        }
                        return fs.close(f.fd).then(() => {
                            file = null;
                            const rawBytes = new Uint8Array(raw);
                            const nonce = rawBytes.slice(0, NONCE_LENGTH);
                            const cipher = rawBytes.slice(NONCE_LENGTH);
                            zeroBuffer(raw);
                            new ChaCha20(this.key, nonce).xorInPlace(cipher);
                            const plain = arrayToBuffer(cipher);
                            return CryptoEngine.sha256(plain).then((digest) => {
                                const expected = hexToBytes(hash);
                                if (!arrayBufferEquals(digest, arrayToBuffer(expected))) {
                                    zeroBuffer(plain);
                                    throw new KdbxError(
                                        ErrorCodes.FileCorrupt,
                                        'attachment cache hash mismatch'
                                    );
                                }
                                this.touch(path);
                                return plain;
                            });
                        });
                    });
                });
            }).catch((e) => {
                if (file !== null) {
                    try {
                        fs.closeSync(file.fd);
                    } catch (ignored) {
                        // best effort
                    }
                }
                if (e instanceof KdbxError) {
                    throw e;
                }
                throw new KdbxError(
                    ErrorCodes.AttachmentStoreError,
                    `attachment cache read failed: ${e}`
                );
            });
        });
    }

    /**
     * 删除单个缓存文件（best effort）。
     */
    remove(hash: string): Promise<void> {
        return this.fileName(hash).then((name) =>
            fs.unlink(this.pathOf(name)).catch(() => undefined)
        );
    }

    /**
     * LRU 清理：按 mtime 升序删除最旧文件，直到总占用不超过 maxTotalBytes。
     */
    sweep(maxTotalBytes: number): Promise<void> {
        let names: string[] = [];
        try {
            names = fs.listFileSync(this.dir).filter((name) => FILENAME_PATTERN.test(name));
        } catch (e) {
            return Promise.resolve();
        }
        const entries: Array<{ name: string; size: number; mtime: number }> = [];
        let chain: Promise<void> = Promise.resolve();
        for (const name of names) {
            chain = chain.then(() => {
                const path = this.pathOf(name);
                return fs.stat(path).then((stat) => {
                    entries.push({ name, size: stat.size, mtime: stat.mtime });
                }).catch(() => undefined);
            });
        }
        return chain.then(() => {
            entries.sort((a, b) => a.mtime - b.mtime);
            let total = 0;
            for (const entry of entries) {
                total += entry.size;
            }
            let removed: Promise<void> = Promise.resolve();
            for (const entry of entries) {
                if (total <= maxTotalBytes) {
                    break;
                }
                total -= entry.size;
                const path = this.pathOf(entry.name);
                removed = removed.then(() =>
                    fs.unlink(path).catch(() => undefined)
                );
            }
            return removed;
        });
    }

    private pathOf(name: string): string {
        return `${this.dir}/${name}`;
    }

    private touch(path: string): void {
        try {
            // utimes 为同步接口，mtime 单位秒；失败不影响正确性，仅影响 LRU 精度
            fs.utimes(path, Math.floor(Date.now() / 1000));
        } catch (e) {
            // best effort
        }
    }

    private writeEncrypted(
        path: string,
        name: string,
        hash: string,
        data: ArrayBuffer
    ): Promise<void> {
        const nonce = CryptoEngine.random(NONCE_LENGTH);
        // 拷贝后加密，避免改动调用方缓冲
        const cipher = new Uint8Array(data.slice(0));
        new ChaCha20(this.key, nonce).xorInPlace(cipher);
        const out = new ArrayBuffer(NONCE_LENGTH + cipher.byteLength);
        const outBytes = new Uint8Array(out);
        outBytes.set(nonce, 0);
        outBytes.set(cipher, NONCE_LENGTH);
        zeroBuffer(cipher);

        const tmpPath = `${this.dir}/${name}${TMP_SUFFIX}`;
        let file: fs.File | null = null;
        return fs.open(
            tmpPath,
            fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
        ).then((f) => {
            file = f;
            return fs.write(f.fd, out).then(() => fs.fsync(f.fd)).then(() =>
                fs.close(f.fd).then(() => {
                    file = null;
                    return fs.rename(tmpPath, path);
                })
            );
        }).catch((e) => {
            if (file !== null) {
                try {
                    fs.closeSync(file.fd);
                } catch (ignored) {
                    // best effort
                }
            }
            try {
                fs.unlinkSync(tmpPath);
            } catch (ignored) {
                // best effort
            }
            throw new KdbxError(
                ErrorCodes.AttachmentStoreError,
                `attachment cache write failed: ${e}`
            );
        });
    }

    private writeEncryptedRegion(
        path: string,
        name: string,
        srcFd: number,
        offset: number,
        length: number
    ): Promise<void> {
        const nonce = CryptoEngine.random(NONCE_LENGTH);
        const cipher = new ChaCha20(this.key, nonce);
        const tmpPath = `${this.dir}/${name}${TMP_SUFFIX}`;
        let file: fs.File | null = null;
        return fs.open(
            tmpPath,
            fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC
        ).then((f) => {
            file = f;
            return fs.write(f.fd, arrayToBuffer(nonce)).then(() => {
                return this.copyRegionEncrypted(f.fd, srcFd, offset, length, cipher);
            }).then(() => fs.fsync(f.fd)).then(() =>
                fs.close(f.fd).then(() => {
                    file = null;
                    return fs.rename(tmpPath, path);
                })
            );
        }).catch((e) => {
            if (file !== null) {
                try {
                    fs.closeSync(file.fd);
                } catch (ignored) {
                    // best effort
                }
            }
            try {
                fs.unlinkSync(tmpPath);
            } catch (ignored) {
                // best effort
            }
            throw new KdbxError(
                ErrorCodes.AttachmentStoreError,
                `attachment cache stream write failed: ${e}`
            );
        });
    }

    private copyRegionEncrypted(
        destFd: number,
        srcFd: number,
        offset: number,
        length: number,
        cipher: ChaCha20
    ): Promise<void> {
        let chain: Promise<void> = Promise.resolve();
        let position = offset;
        let remaining = length;
        while (remaining > 0) {
            const readLen = Math.min(remaining, REGION_CHUNK_SIZE);
            const readAt = position;
            const buf = new ArrayBuffer(readLen);
            chain = chain.then(() => {
                return fs.read(srcFd, buf, { offset: readAt }).then((read) => {
                    if (read !== readLen) {
                        throw new KdbxError(ErrorCodes.FileCorrupt, 'attachment region short read');
                    }
                    cipher.xorInPlace(new Uint8Array(buf));
                    return fs.write(destFd, buf);
                }).then(() => undefined);
            });
            position += readLen;
            remaining -= readLen;
        }
        return chain;
    }
}
