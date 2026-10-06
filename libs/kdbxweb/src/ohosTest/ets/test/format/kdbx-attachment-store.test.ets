import { describe, expect, it, beforeAll } from '@ohos/hypium';
import * as kdbxweb from '../../../../main/ets/index';
import { ohosArgon2 } from '../../../../main/ets/crypto/argon2-rs';
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

/**
 * 清空目录内全部文件（store 密钥随机化导致文件名跨执行不同，需清理保证用例幂等）
 */
function cleanDir(path: string): void {
    try {
        const names = fs.listFileSync(path);
        for (let i = 0; i < names.length; i++) {
            try {
                fs.unlinkSync(`${path}/${names[i]}`);
            } catch (e) {
                // best effort
            }
        }
    } catch (e) {
        // 目录不存在
    }
}

/**
 * 独立目录 store：先清理再建目录，保证用例间互不污染且可重复执行
 */
function makeStoreAt(dir: string): kdbxweb.AttachmentStore {
    cleanDir(dir);
    try {
        if (!fs.accessSync(dir, fs.AccessModeType.EXIST)) {
            fs.mkdirSync(dir, true);
        }
    } catch (e) {
        // 目录可能已存在
    }
    return new kdbxweb.AttachmentStore(dir, kdbxweb.ByteUtils.randomData(32));
}

/**
 * 构造带单个真实附件的 v4 数据库并加密保存。
 * 注意：demo.kdbx 为 KDBX 3.1，v3 不参与磁盘化，磁盘化用例必须使用 v4 库。
 */
async function createV4DatabaseWithAttachment(
    credentials: kdbxweb.KdbxCredentials,
    data: ArrayBuffer
): Promise<ArrayBuffer> {
    const db = kdbxweb.Kdbx.create(credentials, 'AttachStore');
    const entry = db.createEntry(db.getDefaultGroup());
    entry.fields.set('Title', 'has-attachment');
    const binary = await db.binaries.add(data);
    entry.binaries.set('demo.bin', binary);
    return db.save();
}

export default function KdbxAttachmentStoreTest() {
    describe('KdbxAttachmentStore', () => {
        let testDir: string;
        let store: kdbxweb.AttachmentStore;

        beforeAll(() => {
            kdbxweb.CryptoEngine.setArgon2Impl(ohosArgon2);
            testDir = '/data/storage/el2/base/haps/entry/files/attach-store-test';
            // 上次执行的缓存文件（密钥不同、无法复用）先清空，保证用例幂等
            cleanDir(testDir);
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

        it('get with tampered file throws FileCorrupt', 0, async () => {
            // 独立目录：目录内唯一 .bin 即篡改目标，避免共享目录下 listFileSync 顺序不定选错文件
            const tamperDir = testDir + '-tamper';
            const store2 = makeStoreAt(tamperDir);
            const tamperData = kdbxweb.ByteUtils.stringToBuffer('tamper-target-content');
            const realHash = await sha256Hex(tamperData);
            await store2.put(realHash, tamperData);
            // 篡改唯一缓存文件的一个密文字节
            const names = fs.listFileSync(tamperDir)
                .filter((name: string) => name.endsWith('.bin'));
            expect(names.length).assertEqual(1);
            const path = tamperDir + '/' + names[0];
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
            let threw = false;
            try {
                await store2.get(realHash);
            } catch (e) {
                threw = true;
                expect(e instanceof kdbxweb.KdbxError).assertTrue();
                expect((e as kdbxweb.KdbxError).code)
                    .assertEqual(kdbxweb.Consts.ErrorCodes.FileCorrupt);
            }
            expect(threw).assertTrue();
        });

        it('get missing hash rejects', 0, () => {
            return store.get('ff'.repeat(32)).then(() => {
                throw new Error('should have rejected');
            }).catch((e: kdbxweb.KdbxError) => {
                expect(e instanceof kdbxweb.KdbxError).assertTrue();
                expect(e.code).assertEqual(kdbxweb.Consts.ErrorCodes.AttachmentStoreError);
            });
        });

        /**
         * getToFile 流式回读（S6 保存管道）：与 get 字节输出完全一致
         */
        it('getToFile returns same bytes as get', 0, async () => {
            const realHash = await sha256Hex(DATA);
            await store.put(realHash, DATA);
            const expected = await store.get(realHash);
            // 写到临时文件再读回比较
            const tmpPath = testDir + '/getToFile-eq.tmp';
            const file = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
            try {
                await store.getToFile(realHash, file.fd);
            } finally {
                fs.closeSync(file);
            }
            const stat = fs.statSync(tmpPath);
            const buf = new ArrayBuffer(stat.size);
            const rf = fs.openSync(tmpPath, fs.OpenMode.READ_ONLY);
            try {
                fs.readSync(rf.fd, buf);
            } finally {
                fs.closeSync(rf);
            }
            expect(buf.byteLength).assertEqual(expected.byteLength);
            expect(kdbxweb.ByteUtils.arrayBufferEquals(buf, expected)).assertTrue();
            try { fs.unlinkSync(tmpPath); } catch (e) { /* best effort */ }
        });

        /**
         * getToFile 大附件（5MB）流式回读保真
         */
        it('getToFile streams large attachment preserving bytes', 0, async () => {
            const big = kdbxweb.ByteUtils.stringToBuffer('y'.repeat(5 * 1024 * 1024));
            const realHash = await sha256Hex(big);
            await store.put(realHash, big);
            const tmpPath = testDir + '/getToFile-big.tmp';
            const file = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
            try {
                await store.getToFile(realHash, file.fd);
            } finally {
                fs.closeSync(file);
            }
            const stat = fs.statSync(tmpPath);
            const buf = new ArrayBuffer(stat.size);
            const rf = fs.openSync(tmpPath, fs.OpenMode.READ_ONLY);
            try {
                fs.readSync(rf.fd, buf);
            } finally {
                fs.closeSync(rf);
            }
            expect(buf.byteLength).assertEqual(big.byteLength);
            expect(kdbxweb.ByteUtils.arrayBufferEquals(buf, big)).assertTrue();
            try { fs.unlinkSync(tmpPath); } catch (e) { /* best effort */ }
        });

        /**
         * getToFile 篡改密文 → FileCorrupt（哈希校验失败）
         */
        it('getToFile with tampered file throws FileCorrupt', 0, async () => {
            const tamperDir = testDir + '-tamper-gettofile';
            const store2 = makeStoreAt(tamperDir);
            const tamperData = kdbxweb.ByteUtils.stringToBuffer('gettofile-tamper-target');
            const realHash = await sha256Hex(tamperData);
            await store2.put(realHash, tamperData);
            // 篡改唯一缓存文件的密文字节
            const names = fs.listFileSync(tamperDir)
                .filter((name: string) => name.endsWith('.bin'));
            expect(names.length).assertEqual(1);
            const path = tamperDir + '/' + names[0];
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
            const tmpPath = testDir + '/getToFile-tamper.tmp';
            const out = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
            let threw = false;
            try {
                await store2.getToFile(realHash, out.fd);
            } catch (e) {
                threw = true;
                expect(e instanceof kdbxweb.KdbxError).assertTrue();
                expect((e as kdbxweb.KdbxError).code)
                    .assertEqual(kdbxweb.Consts.ErrorCodes.FileCorrupt);
            } finally {
                fs.closeSync(out);
            }
            expect(threw).assertTrue();
            try { fs.unlinkSync(tmpPath); } catch (e) { /* best effort */ }
        });

        /**
         * getToFile 缺失哈希 → AttachmentStoreError
         */
        it('getToFile missing hash rejects', 0, () => {
            const tmpPath = testDir + '/getToFile-missing.tmp';
            const file = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
            fs.closeSync(file);
            const reopen = fs.openSync(tmpPath, fs.OpenMode.READ_WRITE);
            return store.getToFile('ff'.repeat(32), reopen.fd).then(() => {
                fs.closeSync(reopen.fd);
                throw new Error('should have rejected');
            }).catch((e: kdbxweb.KdbxError) => {
                fs.closeSync(reopen.fd);
                expect(e instanceof kdbxweb.KdbxError).assertTrue();
                expect(e.code).assertEqual(kdbxweb.Consts.ErrorCodes.AttachmentStoreError);
            }).then(() => {
                try { fs.unlinkSync(tmpPath); } catch (e) { /* best effort */ }
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

        it('load with threshold converts attachments to disk refs', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo')
            );
            const dbBuf = await createV4DatabaseWithAttachment(cred, DATA);
            const db = await kdbxweb.Kdbx.load(dbBuf, cred, {
                attachmentStore: store,
                attachmentsDiskThreshold: 1
            });
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

        it('save with disk refs round-trips attachment content', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo')
            );
            const dbBuf = await createV4DatabaseWithAttachment(cred, DATA);
            // 基线：纯内存加载
            const baseline = await kdbxweb.Kdbx.load(dbBuf, cred);
            const baselinePool = baseline.binaries.getAllWithHashes();
            const baselineHash = baselinePool[0].hash;
            const baselineBytes = binaryBytes(baselinePool[0].value);
            // 磁盘化加载 → 保存
            const db = await kdbxweb.Kdbx.load(dbBuf, cred, {
                attachmentStore: store,
                attachmentsDiskThreshold: 1
            });
            const saved = await db.save();
            // 重新加载（纯内存）验证附件内容保真
            const reloaded = await kdbxweb.Kdbx.load(saved, cred);
            const pool = reloaded.binaries.getAllWithHashes();
            expect(pool.length).assertEqual(1);
            expect(pool[0].hash).assertEqual(baselineHash);
            const bytes = binaryBytes(pool[0].value);
            expect(bytes.byteLength).assertEqual(baselineBytes.byteLength);
            expect(kdbxweb.ByteUtils.arrayBufferEquals(bytes, baselineBytes)).assertTrue();
        });

        it('snapshot v2 carries disk refs without attachment bytes', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo')
            );
            const dbBuf = await createV4DatabaseWithAttachment(cred, DATA);
            const db = await kdbxweb.Kdbx.load(dbBuf, cred, {
                attachmentStore: store,
                attachmentsDiskThreshold: 1
            });
            const snap = await db.saveSnapshot();
            expect(kdbxweb.KdbxSnapshot.isSnapshot(snap)).assertTrue();
            // 带 store 恢复：附件为磁盘引用
            const restored = await kdbxweb.Kdbx.loadSnapshot(snap, cred, {
                attachmentStore: store
            });
            const pool = restored.binaries.getAllWithHashes();
            expect(pool.length).assertEqual(1);
            expect(pool[0].value instanceof kdbxweb.KdbxBinaryDiskRef).assertTrue();
            // 无 store 恢复：明确报错而非静默损坏
            let threw = false;
            try {
                await kdbxweb.Kdbx.loadSnapshot(snap, cred);
            } catch (e) {
                threw = true;
                expect(e instanceof kdbxweb.KdbxError).assertTrue();
                expect((e as kdbxweb.KdbxError).code)
                    .assertEqual(kdbxweb.Consts.ErrorCodes.InvalidState);
            }
            expect(threw).assertTrue();
        });

        it('saveXml materializes disk refs for export', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo')
            );
            const dbBuf = await createV4DatabaseWithAttachment(cred, DATA);
            const db = await kdbxweb.Kdbx.load(dbBuf, cred, {
                attachmentStore: store,
                attachmentsDiskThreshold: 1
            });
            const xml = await db.saveXml(true, true);
            expect(xml.length > 0).assertTrue();
            expect(xml.includes('KeePassFile')).assertTrue();
        });
    });
}
