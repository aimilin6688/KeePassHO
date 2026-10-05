import { describe, expect, it, beforeAll } from '@ohos/hypium';
import * as kdbxweb from '../../../../main/ets/index';
import { ohosArgon2 } from '../../../../main/ets/crypto/argon2-rs';
import { TestResources } from '../test-support/test-resources';
import { fileIo as fs } from '@kit.CoreFileKit';

const DATA = kdbxweb.ByteUtils.stringToBuffer('attachment-content-0123456789');

/**
 * 内容哈希（sha256 hex），用于跨模式比较附件内容
 */
function sha256Hex(data: ArrayBuffer): Promise<string> {
    return kdbxweb.CryptoEngine.sha256(data).then(kdbxweb.ByteUtils.bytesToHex);
}

/**
 * 附件值规范化为 ArrayBuffer（ProtectedValue → 解码字节）
 */
function binaryBytes(value: kdbxweb.KdbxBinary): ArrayBuffer {
    if (value instanceof kdbxweb.ProtectedValue) {
        return kdbxweb.ByteUtils.arrayToBuffer(value.getBinary());
    }
    return value as ArrayBuffer;
}

export default function KdbxAttachmentStoreTest() {
    describe('KdbxAttachmentStore', () => {
        let testDir: string;
        let store: kdbxweb.AttachmentStore;

        beforeAll(() => {
            kdbxweb.CryptoEngine.setArgon2Impl(ohosArgon2);
            testDir = '/data/storage/el2/base/haps/entry/files/attach-store-test';
            try {
                if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
                    fs.mkdirSync(testDir, true);
                }
            } catch (e) {
                // 目录可能已存在
            }
            store = new kdbxweb.AttachmentStore(
                testDir,
                kdbxweb.ByteUtils.randomData(32)
            );
        });

        it('put/get round-trip verifies content hash', 0, () => {
            const hash = 'a1b2c3d4'.padEnd(64, '0');
            // 用真实 sha256 作为 hash（get 校验依赖）
            return sha256Hex(DATA).then((realHash) => {
                return store.put(realHash, DATA).then(() => {
                    return store.has(realHash).then((exists) => {
                        expect(exists).assertTrue();
                        return store.get(realHash).then((read) => {
                            expect(kdbxweb.ByteUtils.arrayBufferEquals(read, DATA)).assertTrue();
                        });
                    });
                });
            });
        });

        it('put twice with same hash reuses disk copy (cache hit)', 0, () => {
            return sha256Hex(DATA).then((realHash) => {
                const data2 = kdbxweb.ByteUtils.stringToBuffer('attachment-content-0123456789');
                return store.put(realHash, data2).then(() => {
                    return store.get(realHash).then((read) => {
                        expect(read.byteLength).assertEqual(DATA.byteLength);
                        expect(kdbxweb.ByteUtils.arrayBufferEquals(read, DATA)).assertTrue();
                    });
                });
            });
        });

        it('get with tampered file throws FileCorrupt', 0, () => {
            const tamperData = kdbxweb.ByteUtils.stringToBuffer('tamper-target-content');
            return sha256Hex(tamperData).then((realHash) => {
                return store.put(realHash, tamperData).then(() => {
                    // 找到缓存文件并篡改一个密文字节
                    const names = fs.listFileSync(testDir)
                        .filter((name: string) => name.endsWith('.bin'));
                    expect(names.length > 0).assertTrue();
                    const path = testDir + '/' + names[names.length - 1];
                    const file = fs.openSync(path, fs.OpenMode.READ_WRITE);
                    try {
                        const size = fs.statSync(file.fd).size;
                        const buf = new ArrayBuffer(1);
                        fs.readSync(file.fd, buf, { offset: Math.floor(size / 2) });
                        const flip = new Uint8Array(buf);
                        flip[0] = flip[0] ^ 0xff;
                        fs.writeSync(file.fd, buf, { offset: Math.floor(size / 2) });
                    } finally {
                        fs.closeSync(file);
                    }
                    return store.get(realHash).then(() => {
                        throw new Error('should have thrown FileCorrupt');
                    }).catch((e: kdbxweb.KdbxError) => {
                        expect(e instanceof kdbxweb.KdbxError).assertTrue();
                        expect(e.code).assertEqual(kdbxweb.Consts.ErrorCodes.FileCorrupt);
                    });
                });
            });
        });

        it('get missing hash rejects', 0, () => {
            return store.get('ff'.repeat(32)).then(() => {
                throw new Error('should have rejected');
            }).catch((e: kdbxweb.KdbxError) => {
                expect(e instanceof kdbxweb.KdbxError).assertTrue();
                expect(e.code).assertEqual(kdbxweb.Consts.ErrorCodes.AttachmentStoreError);
            });
        });

        it('sweep removes files beyond budget', 0, () => {
            const store2 = new kdbxweb.AttachmentStore(
                testDir + '-sweep',
                kdbxweb.ByteUtils.randomData(32)
            );
            const writes: Promise<void>[] = [];
            for (let i = 0; i < 3; i++) {
                const data = kdbxweb.ByteUtils.stringToBuffer('sweep-item-' + i);
                writes.push(sha256Hex(data).then((hash) => store2.put(hash, data)));
            }
            return Promise.all(writes).then(() => {
                return store2.sweep(0).then(() => {
                    const checks: Promise<boolean>[] = [];
                    for (let i = 0; i < 3; i++) {
                        const data = kdbxweb.ByteUtils.stringToBuffer('sweep-item-' + i);
                        checks.push(sha256Hex(data).then((hash) => store2.has(hash)));
                    }
                    return Promise.all(checks).then((exists: boolean[]) => {
                        for (let i = 0; i < exists.length; i++) {
                            expect(exists[i]).assertFalse();
                        }
                    });
                });
            });
        });

        it('load with threshold converts attachments to disk refs', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred, {
                attachmentStore: store,
                attachmentsDiskThreshold: 1
            }).then((db) => {
                const pool = db.binaries.getAllWithHashes();
                expect(pool.length).assertEqual(1);
                expect(pool[0].value instanceof kdbxweb.KdbxBinaryDiskRef).assertTrue();
                const ref = pool[0].value as kdbxweb.KdbxBinaryDiskRef;
                expect(ref.hash).assertEqual(pool[0].hash);
                expect(ref.byteLength > 0).assertTrue();
                // entry.binaries 同步替换为磁盘引用
                let entryRefCount = 0;
                for (const item of db.getDefaultGroup().allGroupsAndEntries()) {
                    if (item instanceof kdbxweb.KdbxEntry) {
                        for (const value of item.binaries.values()) {
                            if (kdbxweb.KdbxBinaries.isKdbxBinaryWithHash(value)) {
                                expect(value.value instanceof kdbxweb.KdbxBinaryDiskRef).assertTrue();
                                entryRefCount++;
                            }
                        }
                    }
                }
                expect(entryRefCount > 0).assertTrue();
            });
        });

        it('save with disk refs round-trips attachment content', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            // 基线：纯内存加载
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((baseline) => {
                const baselinePool = baseline.binaries.getAllWithHashes();
                const baselineHash = baselinePool[0].hash;
                const baselineBytes = binaryBytes(baselinePool[0].value);
                // 磁盘化加载 → 保存
                return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred, {
                    attachmentStore: store,
                    attachmentsDiskThreshold: 1
                }).then((db) => {
                    return db.save().then((saved) => {
                        // 重新加载（纯内存）验证附件内容保真
                        return kdbxweb.Kdbx.load(saved, cred).then((reloaded) => {
                            const pool = reloaded.binaries.getAllWithHashes();
                            expect(pool.length).assertEqual(1);
                            expect(pool[0].hash).assertEqual(baselineHash);
                            const bytes = binaryBytes(pool[0].value);
                            expect(bytes.byteLength).assertEqual(baselineBytes.byteLength);
                            expect(kdbxweb.ByteUtils.arrayBufferEquals(bytes, baselineBytes))
                                .assertTrue();
                        });
                    });
                });
            });
        });

        it('snapshot v2 carries disk refs without attachment bytes', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred, {
                attachmentStore: store,
                attachmentsDiskThreshold: 1
            }).then((db) => {
                return db.saveSnapshot().then((snap) => {
                    expect(kdbxweb.KdbxSnapshot.isSnapshot(snap)).assertTrue();
                    // 带 store 恢复：附件为磁盘引用
                    return kdbxweb.Kdbx.loadSnapshot(snap, cred, { attachmentStore: store })
                        .then((restored) => {
                            const pool = restored.binaries.getAllWithHashes();
                            expect(pool.length).assertEqual(1);
                            expect(pool[0].value instanceof kdbxweb.KdbxBinaryDiskRef)
                                .assertTrue();
                            // 无 store 恢复：明确报错而非静默损坏
                            return kdbxweb.Kdbx.loadSnapshot(snap, cred).then(() => {
                                throw new Error('should have thrown');
                            }).catch((e: kdbxweb.KdbxError) => {
                                expect(e instanceof kdbxweb.KdbxError).assertTrue();
                                expect(e.code)
                                    .assertEqual(kdbxweb.Consts.ErrorCodes.InvalidState);
                            });
                        });
                });
            });
        });

        it('saveXml materializes disk refs for export', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred, {
                attachmentStore: store,
                attachmentsDiskThreshold: 1
            }).then((db) => {
                return db.saveXml(true, true).then((xml) => {
                    expect(xml.length > 0).assertTrue();
                    expect(xml.includes('KeePassFile')).assertTrue();
                });
            });
        });
    });
}
