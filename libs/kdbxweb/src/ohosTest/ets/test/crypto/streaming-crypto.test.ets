import { describe, expect, it, beforeAll, afterAll } from '@ohos/hypium';
import { ByteUtils, ChaCha20, Consts, HmacBlockTransform, KdbxError } from '../../../../main/ets/index';
import { fileIo as fs } from '@kit.CoreFileKit';

export default function StreamingCryptoTest() {
    describe('StreamingCrypto', () => {
        const key = ByteUtils.arrayToBuffer(
            ByteUtils.hexToBytes('1f5c3ef76d43e72ee2c5216c36187c799b153cab3d0cb63a6f3ecccc2627f535')
        );
        let testDir: string;

        beforeAll(() => {
            testDir = '/data/storage/el2/base/haps/entry/files/streaming-crypto-test';
            try {
                if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
                    fs.mkdirSync(testDir, true);
                }
            } catch (e) {
                // 目录可能已存在
            }
        });

        /**
         * xorInPlace 与 getBytes 结果一致（小数据）
         */
        it('xorInPlace matches getBytes for small data', 0, () => {
            const keyBytes = new Uint8Array(32);
            const nonce = new Uint8Array(32);
            for (let i = 0; i < 32; i++) {
                keyBytes[i] = i;
                nonce[i] = i * 2;
            }

            const chacha1 = new ChaCha20(keyBytes, nonce);
            const stream = chacha1.getBytes(64);

            const chacha2 = new ChaCha20(keyBytes, nonce);
            const data = new Uint8Array(64);
            for (let i = 0; i < 64; i++) {
                data[i] = i;
            }
            const original = new Uint8Array(data);
            chacha2.xorInPlace(data);

            // data = original XOR stream
            for (let i = 0; i < 64; i++) {
                expect(data[i]).assertEqual(original[i] ^ stream[i]);
            }
        });

        /**
         * xorInPlace 状态跨块保持（多块连续 XOR = 单次大块 XOR）
         */
        it('xorInPlace state persists across blocks', 0, () => {
            const keyBytes = new Uint8Array(32);
            const nonce = new Uint8Array(32);

            // 单次 XOR 1000 字节
            const chacha1 = new ChaCha20(keyBytes, nonce);
            const bigData = new Uint8Array(1000);
            for (let i = 0; i < 1000; i++) {
                bigData[i] = i % 256;
            }
            const original = new Uint8Array(bigData);
            chacha1.xorInPlace(bigData);

            // 分 3 块 XOR（300 + 400 + 300）
            const chacha2 = new ChaCha20(keyBytes, nonce);
            const chunkData = new Uint8Array(original);
            chacha2.xorInPlace(chunkData.subarray(0, 300));
            chacha2.xorInPlace(chunkData.subarray(300, 700));
            chacha2.xorInPlace(chunkData.subarray(700, 1000));

            // 两种方式结果一致
            expect(ByteUtils.bytesToHex(bigData)).assertEqual(ByteUtils.bytesToHex(chunkData));
        });

        /**
         * xorInPlace 解密 = 加密（对称性）
         */
        it('xorInPlace is symmetric (encrypt then decrypt)', 0, () => {
            const keyBytes = new Uint8Array(32);
            const nonce = new Uint8Array(32);
            const original = new Uint8Array(500);
            for (let i = 0; i < 500; i++) {
                original[i] = (i * 7) % 256;
            }

            // 加密
            const enc = new Uint8Array(original);
            const chacha1 = new ChaCha20(keyBytes, nonce);
            chacha1.xorInPlace(enc);

            // 解密（同一 key+nonce）
            const dec = new Uint8Array(enc);
            const chacha2 = new ChaCha20(keyBytes, nonce);
            chacha2.xorInPlace(dec);

            expect(ByteUtils.bytesToHex(dec)).assertEqual(ByteUtils.bytesToHex(original));
        });

        /**
         * decryptFromFile 与 decrypt 结果一致（多块）
         */
        it('decryptFromFile matches decrypt for multi-block', 0, () => {
            const src = new Uint8Array(1024 * 1024 * 2 + 2);
            for (let i = 0; i < src.length; i++) {
                src[i] = i % 256;
            }
            return HmacBlockTransform.encrypt(src.buffer, key).then((enc) => {
                // 整缓冲解密（基准）
                return HmacBlockTransform.decrypt(enc, key).then((expectedDec) => {
                    // 写加密数据到文件
                    const encPath = testDir + '/enc-multi.bin';
                    return writeFile(encPath, enc).then(() => {
                        return fs.open(encPath, fs.OpenMode.READ_ONLY).then((file) => {
                            const outPath = testDir + '/dec-multi.bin';
                            const decryptBlock = (data: Uint8Array): void => {
                                // 无加密：纯 HMAC 验证 + 直写
                            };
                            return HmacBlockTransform.decryptFromFile(
                                file.fd, outPath, key, decryptBlock
                            ).then(() => {
                                return fs.close(file.fd).then(() => {
                                    return readFile(outPath).then((fileDec) => {
                                        expect(ByteUtils.bytesToHex(new Uint8Array(fileDec)))
                                            .assertEqual(ByteUtils.bytesToHex(new Uint8Array(expectedDec)));
                                    });
                                });
                            });
                        });
                    });
                });
            });
        });

        /**
         * decryptFromFile 与 decrypt 一致（小数据 < 1 块）
         */
        it('decryptFromFile matches decrypt for small data', 0, () => {
            const src = new Uint8Array([1, 2, 3, 4, 5]);
            return HmacBlockTransform.encrypt(src.buffer, key).then((enc) => {
                return HmacBlockTransform.decrypt(enc, key).then((expectedDec) => {
                    const encPath = testDir + '/enc-small.bin';
                    return writeFile(encPath, enc).then(() => {
                        return fs.open(encPath, fs.OpenMode.READ_ONLY).then((file) => {
                            const outPath = testDir + '/dec-small.bin';
                            const decryptBlock = (data: Uint8Array): void => {};
                            return HmacBlockTransform.decryptFromFile(
                                file.fd, outPath, key, decryptBlock
                            ).then(() => {
                                return fs.close(file.fd).then(() => {
                                    return readFile(outPath).then((fileDec) => {
                                        expect(new Uint8Array(fileDec)).assertEqual(new Uint8Array(expectedDec));
                                    });
                                });
                            });
                        });
                    });
                });
            });
        });

        /**
         * encryptFromFile 与 encrypt 结果一致
         */
        it('encryptFromFile matches encrypt', 0, () => {
            const src = new Uint8Array(1024 * 1024 + 100);
            for (let i = 0; i < src.length; i++) {
                src[i] = (i * 3) % 256;
            }
            // 整缓冲加密（基准）
            return HmacBlockTransform.encrypt(src.buffer, key).then((expectedEnc) => {
                // 写明文到文件
                const inPath = testDir + '/plain-enc.bin';
                return writeFile(inPath, src.buffer).then(() => {
                    const outPath = testDir + '/enc-from-file.bin';
                    return fs.open(outPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
                        .then((outFile) => {
                            const encryptBlock = (data: Uint8Array): void => {};
                            return HmacBlockTransform.encryptFromFile(
                                inPath, outFile.fd, key, encryptBlock
                            ).then(() => {
                                return fs.close(outFile.fd).then(() => {
                                    return readFile(outPath).then((fileEnc) => {
                                        expect(ByteUtils.bytesToHex(new Uint8Array(fileEnc)))
                                            .assertEqual(ByteUtils.bytesToHex(new Uint8Array(expectedEnc)));
                                    });
                                });
                            });
                        });
                });
            });
        });

        /**
         * encryptFromFile → decryptFromFile 往返一致
         */
        it('encryptFromFile then decryptFromFile roundtrip', 0, () => {
            const src = new Uint8Array(2 * 1024 * 1024 + 50);
            for (let i = 0; i < src.length; i++) {
                src[i] = i % 256;
            }
            const inPath = testDir + '/roundtrip-plain.bin';
            const encPath = testDir + '/roundtrip-enc.bin';
            const decPath = testDir + '/roundtrip-dec.bin';

            return writeFile(inPath, src.buffer).then(() => {
                return fs.open(encPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
                    .then((encFile) => {
                        const noop = (data: Uint8Array): void => {};
                        return HmacBlockTransform.encryptFromFile(inPath, encFile.fd, key, noop)
                            .then(() => {
                                return fs.close(encFile.fd).then(() => {
                                    return fs.open(encPath, fs.OpenMode.READ_ONLY).then((readFile1) => {
                                        return HmacBlockTransform.decryptFromFile(
                                            readFile1.fd, decPath, key, noop
                                        ).then(() => {
                                            return fs.close(readFile1.fd).then(() => {
                                                return readFile(decPath).then((decBuf) => {
                                                    expect(ByteUtils.bytesToHex(new Uint8Array(decBuf)))
                                                        .assertEqual(ByteUtils.bytesToHex(src));
                                                });
                                            });
                                        });
                                    });
                                });
                            });
                    });
            });
        });

        /**
         * decryptFromFile 对损坏的 HMAC 抛 FileCorrupt
         */
        it('decryptFromFile throws FileCorrupt for tampered data', 0, () => {
            const src = new Uint8Array([1, 2, 3, 4, 5]);
            return HmacBlockTransform.encrypt(src.buffer, key).then((enc) => {
                // 篡改第一个字节（HMAC 值）
                const tampered = new Uint8Array(enc);
                tampered[0] = tampered[0] ^ 0xff;
                const encPath = testDir + '/tampered.bin';
                return writeFile(encPath, tampered.buffer).then(() => {
                    return fs.open(encPath, fs.OpenMode.READ_ONLY).then((file) => {
                        const outPath = testDir + '/tampered-out.bin';
                        const noop = (data: Uint8Array): void => {};
                        return HmacBlockTransform.decryptFromFile(file.fd, outPath, key, noop)
                            .then(() => {
                                return fs.close(file.fd).then(() => {
                                    throw new Error('should have thrown FileCorrupt');
                                });
                            })
                            .catch((e: Error) => {
                                return fs.close(file.fd).then(() => {
                                    expect(e instanceof KdbxError).assertTrue();
                                    expect((e as KdbxError).code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                                });
                            });
                    });
                });
            });
        });
    });
}

function writeFile(path: string, data: ArrayBuffer): Promise<void> {
    return fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC).then((file) => {
        return fs.write(file.fd, data).then(() => {
            return fs.fsync(file.fd).then(() => {
                return fs.close(file.fd);
            });
        });
    });
}

function readFile(path: string): Promise<ArrayBuffer> {
    return fs.open(path, fs.OpenMode.READ_ONLY).then((file) => {
        return fs.stat(file.fd).then((stat) => {
            const buf = new ArrayBuffer(stat.size);
            return fs.read(file.fd, buf).then(() => {
                return fs.close(file.fd).then(() => buf);
            });
        });
    });
}
