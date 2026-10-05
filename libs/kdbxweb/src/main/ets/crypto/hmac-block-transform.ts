import { Int64 } from '../utils/int64';
import { arrayBufferEquals, arrayToBuffer, zeroBuffer } from '../utils/byte-utils';
import * as CryptoEngine from './crypto-engine';
import { BinaryStream } from '../utils/binary-stream';
import { KdbxError } from '../errors/kdbx-error';
import { ErrorCodes } from '../defs/consts';
import { fileIo as fs } from '@kit.CoreFileKit';

const BlockSize = 1024 * 1024;

export function getHmacKey(key: ArrayBuffer, blockIndex: Int64): Promise<ArrayBuffer> {
    const shaSrc = new Uint8Array(8 + key.byteLength);
    shaSrc.set(new Uint8Array(key), 8);
    const view = new DataView(shaSrc.buffer);
    view.setUint32(0, blockIndex.lo, true);
    view.setUint32(4, blockIndex.hi, true);
    return CryptoEngine.sha512(arrayToBuffer(shaSrc)).then((sha) => {
        zeroBuffer(shaSrc);
        return sha;
    });
}

function getBlockHmac(
    key: ArrayBuffer,
    blockIndex: number,
    blockLength: number,
    blockData: ArrayBuffer
): Promise<ArrayBuffer> {
    return getHmacKey(key, new Int64(blockIndex)).then((blockKey) => {
        const blockDataForHash = new Uint8Array(blockData.byteLength + 4 + 8);
        const blockDataForHashView = new DataView(blockDataForHash.buffer);
        blockDataForHash.set(new Uint8Array(blockData), 4 + 8);
        blockDataForHashView.setInt32(0, blockIndex, true);
        blockDataForHashView.setInt32(8, blockLength, true);
        return CryptoEngine.hmacSha256(blockKey, blockDataForHash.buffer);
    });
}

export function decrypt(data: ArrayBuffer, key: ArrayBuffer): Promise<ArrayBuffer> {
    const stm = new BinaryStream(data);
    return Promise.resolve().then(() => {
        const buffers: ArrayBuffer[] = [];
        let blockIndex = 0,
            blockLength = 0,
            blockHash: ArrayBuffer,
            totalLength = 0;

        const next = (): Promise<ArrayBuffer> => {
            blockHash = stm.readBytes(32);
            blockLength = stm.getUint32(true);
            if (blockLength > 0) {
                totalLength += blockLength;
                const blockData = stm.readBytes(blockLength);
                return getBlockHmac(key, blockIndex, blockLength, blockData).then(
                    (calculatedBlockHash) => {
                        if (!arrayBufferEquals(calculatedBlockHash, blockHash)) {
                            throw new KdbxError(ErrorCodes.FileCorrupt, 'invalid hash block');
                        } else {
                            buffers.push(blockData);
                            blockIndex++;
                            return next();
                        }
                    }
                );
            } else {
                const ret = new Uint8Array(totalLength);
                let offset = 0;
                for (let i = 0; i < buffers.length; i++) {
                    ret.set(new Uint8Array(buffers[i]), offset);
                    offset += buffers[i].byteLength;
                }
                return Promise.resolve(ret.buffer);
            }
        };
        return next();
    });
}

export function encrypt(data: ArrayBuffer, key: ArrayBuffer): Promise<ArrayBuffer> {
    return Promise.resolve().then(() => {
        let bytesLeft = data.byteLength;
        let currentOffset = 0,
            blockIndex = 0,
            totalLength = 0;
        const buffers: ArrayBuffer[] = [];

        const next = (): Promise<ArrayBuffer> => {
            const blockLength = Math.min(BlockSize, bytesLeft);
            bytesLeft -= blockLength;

            const blockData = data.slice(currentOffset, currentOffset + blockLength);
            return getBlockHmac(key, blockIndex, blockLength, blockData).then((blockHash) => {
                const blockBuffer = new ArrayBuffer(32 + 4);
                const stm = new BinaryStream(blockBuffer);
                stm.writeBytes(blockHash);
                stm.setUint32(blockLength, true);

                buffers.push(blockBuffer);
                totalLength += blockBuffer.byteLength;

                if (blockData.byteLength > 0) {
                    buffers.push(blockData);
                    totalLength += blockData.byteLength;
                    blockIndex++;
                    currentOffset += blockLength;
                    return next();
                } else {
                    const ret = new Uint8Array(totalLength);
                    let offset = 0;
                    for (let i = 0; i < buffers.length; i++) {
                        ret.set(new Uint8Array(buffers[i]), offset);
                        offset += buffers[i].byteLength;
                    }
                    return ret.buffer;
                }
            });
        };
        return next();
    });
}

/**
 * 流式文件版解密：从已定位到加密数据起始处的 fileFd 逐块读 → HMAC 验证 →
 * 调用方提供的 decryptBlock 就地解密 → 写到 outPath。
 * 不累积整缓冲到内存，窗口 = 1 个块（1MB）+ 包裹缓冲（修 P5）
 */
export function decryptFromFile(
    fileFd: number,
    outPath: string,
    hmacKey: ArrayBuffer,
    decryptBlock: (data: Uint8Array) => void
): Promise<void> {
    let outFile: fs.File | null = null;
    let blockIndex = 0;

    const readNextBlock = (): Promise<void> => {
        const hmacBuf = new ArrayBuffer(32);
        return fs.read(fileFd, hmacBuf).then((n1: number) => {
            if (n1 < 32) {
                return Promise.resolve();
            }
            const lenBuf = new ArrayBuffer(4);
            return fs.read(fileFd, lenBuf).then((n2: number) => {
                if (n2 < 4) {
                    throw new KdbxError(ErrorCodes.FileCorrupt, 'truncated hash block header');
                }
                const blockLength = new DataView(lenBuf).getUint32(0, true);
                if (blockLength === 0) {
                    return Promise.resolve();
                }
                const blockData = new ArrayBuffer(blockLength);
                return fs.read(fileFd, blockData).then((n3: number) => {
                    if (n3 < blockLength) {
                        throw new KdbxError(ErrorCodes.FileCorrupt, 'truncated hash block data');
                    }
                    return getBlockHmac(hmacKey, blockIndex, blockLength, blockData).then((calcHash) => {
                        if (!arrayBufferEquals(calcHash, hmacBuf)) {
                            throw new KdbxError(ErrorCodes.FileCorrupt, 'invalid hash block');
                        }
                        decryptBlock(new Uint8Array(blockData));
                        const writeTarget = outFile;
                        if (!writeTarget) {
                            throw new KdbxError(ErrorCodes.InvalidState, 'output file not open');
                        }
                        return fs.write(writeTarget.fd, blockData).then(() => {
                            blockIndex++;
                            return readNextBlock();
                        });
                    });
                });
            });
        });
    };

    return fs.open(outPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC).then((f: fs.File) => {
        outFile = f;
        return readNextBlock().then(() => {
            const target = outFile;
            if (!target) {
                return Promise.resolve();
            }
            return fs.fsync(target.fd).then(() => {
                return fs.close(target.fd);
            });
        });
    }).then(undefined, (error: Error) => {
        if (outFile) {
            try { fs.closeSync(outFile.fd); } catch { /* ignore */ }
        }
        throw error;
    });
}

/**
 * 流式文件版加密：从 inPath 逐块读 → 调用方提供的 encryptBlock 就地加密 →
 * 计算 HMAC → 写到 outFd（HMAC block 格式）。
 */
export function encryptFromFile(
    inPath: string,
    outFd: number,
    hmacKey: ArrayBuffer,
    encryptBlock: (data: Uint8Array) => void
): Promise<void> {
    let inFile: fs.File | null = null;

    const processNext = (remaining: number, blockIndex: number): Promise<void> => {
        if (remaining <= 0) {
            // 终止块
            const src = inFile;
            if (!src) {
                return Promise.resolve();
            }
            return getBlockHmac(hmacKey, blockIndex, 0, new ArrayBuffer(0)).then((endHash) => {
                const endBuf = new ArrayBuffer(32 + 4);
                const endStm = new BinaryStream(endBuf);
                endStm.writeBytes(endHash);
                endStm.setUint32(0, true);
                return fs.write(outFd, endBuf).then(() => { return; });
            });
        }
        const blockLength = Math.min(BlockSize, remaining);
        const blockData = new ArrayBuffer(blockLength);
        const src = inFile;
        if (!src) {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidState, 'input file not open'));
        }
        return fs.read(src.fd, blockData).then((n: number) => {
            if (n < blockLength) {
                throw new KdbxError(ErrorCodes.FileCorrupt, 'truncated input on encrypt');
            }
            encryptBlock(new Uint8Array(blockData));
            return getBlockHmac(hmacKey, blockIndex, blockLength, blockData).then((blockHash) => {
                const headerBuf = new ArrayBuffer(32 + 4);
                const stm = new BinaryStream(headerBuf);
                stm.writeBytes(blockHash);
                stm.setUint32(blockLength, true);
                return fs.write(outFd, headerBuf).then(() => {
                    return fs.write(outFd, blockData).then(() => {
                        return processNext(remaining - blockLength, blockIndex + 1);
                    });
                });
            });
        });
    };

    return fs.open(inPath, fs.OpenMode.READ_ONLY).then((f: fs.File) => {
        inFile = f;
        return fs.stat(f.fd).then((stat) => {
            return processNext(stat.size, 0).then(() => {
                const target = inFile;
                if (!target) {
                    return Promise.resolve();
                }
                return fs.close(target.fd);
            });
        });
    }).then(undefined, (error: Error) => {
        if (inFile) {
            try { fs.closeSync(inFile.fd); } catch { /* ignore */ }
        }
        throw error;
    });
}
