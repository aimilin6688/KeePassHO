import { describe, expect, it, beforeAll } from '@ohos/hypium';
import * as kdbxweb from '../../../../main/ets/index';
import { ohosArgon2 } from '../../../../main/ets/crypto/argon2-rs';
import * as ZlibFile from '../../../../main/ets/utils/zlib-file';
import { fileIo as fs } from '@kit.CoreFileKit';

/** S5 大附件流式落盘阈值，须与 KdbxFormat.LARGE_BINARY_STREAM_THRESHOLD 一致 */
const LARGE_BINARY_THRESHOLD = 4 * 1024 * 1024;
const BIG_ATTACHMENT_SIZE = LARGE_BINARY_THRESHOLD + 256 * 1024;

/**
 * 确定性伪随机填充（xorshift32），保证大附件可压缩性与哈希跨执行稳定
 */
function makePatternBuffer(size: number): ArrayBuffer {
    const buf = new ArrayBuffer(size);
    const bytes = new Uint8Array(buf);
    let seed = 0x12345678;
    for (let i = 0; i < size; i++) {
        seed ^= seed << 13;
        seed ^= seed >>> 17;
        seed ^= seed << 5;
        bytes[i] = seed & 0xff;
    }
    return buf;
}

/**
 * 构造 ChaCha20 v4 库（loadFromFile 仅 ChaCha20 走流式路径）
 */
function createChaChaDb(credentials: kdbxweb.KdbxCredentials, name: string): kdbxweb.Kdbx {
    const db = kdbxweb.Kdbx.create(credentials, name);
    db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
    return db;
}

function writeFile(path: string, data: ArrayBuffer): Promise<void> {
    return fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
        .then((file) => {
            return fs.write(file.fd, data).then(() => {
                return fs.fsync(file.fd).then(() => fs.close(file.fd));
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

/**
 * 附件值规范化为 ArrayBuffer
 */
function binaryBytes(value: kdbxweb.KdbxBinary): ArrayBuffer {
    if (value instanceof kdbxweb.ProtectedValue) {
        return kdbxweb.ByteUtils.arrayToBuffer(value.getBinary());
    }
    return value as ArrayBuffer;
}

export default function KdbxStreamingLoadTest() {
    describe('KdbxStreamingLoad', () => {
        let testDir: string;

        beforeAll(() => {
            kdbxweb.CryptoEngine.setArgon2Impl(ohosArgon2);
            testDir = '/data/storage/el2/base/haps/entry/files/streaming-load-test';
            try {
                if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
                    fs.mkdirSync(testDir, true);
                }
            } catch (e) {
                // 目录可能已存在
            }
        });

        /**
         * native zlib 模块：deflateFile → readGzipIsize → inflateFile 往返保真
         */
        it('zlib file round-trip keeps content and ISIZE', 0, () => {
            const src = testDir + '/zlib-src.tmp';
            const gz = testDir + '/zlib-out.gz';
            const back = testDir + '/zlib-back.tmp';
            const data = makePatternBuffer(1024 * 1024 + 12345);
            return writeFile(src, data).then(() => {
                return ZlibFile.deflateFile(src, gz).then((written) => {
                    expect(written > 0).assertTrue();
                    return ZlibFile.readGzipIsize(gz).then((isize) => {
                        expect(isize).assertEqual(data.byteLength);
                        return ZlibFile.inflateFile(gz, back).then((inflated) => {
                            expect(inflated).assertEqual(data.byteLength);
                            return readFile(back).then((read) => {
                                expect(kdbxweb.ByteUtils.arrayBufferEquals(read, data))
                                    .assertTrue();
                                try { fs.unlinkSync(src); } catch { /* ignore */ }
                                try { fs.unlinkSync(gz); } catch { /* ignore */ }
                                try { fs.unlinkSync(back); } catch { /* ignore */ }
                            });
                        });
                    });
                });
            });
        });

        /**
         * S5 流式路径（t2Path）与整缓冲 Kdbx.load 等价：
         * meta / 条目 / 附件内容一致
         */
        it('loadFromFile with t2Path matches Kdbx.load', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo')
            );
            const db = createChaChaDb(cred, 'StreamDb');
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'stream-entry');
            const attach = kdbxweb.ByteUtils.stringToBuffer('stream-attachment-payload');
            const binary = await db.binaries.add(attach);
            entry.binaries.set('a.bin', binary);
            const dbBuf = await db.save();

            const dbPath = testDir + '/stream-eq.kdbx';
            const t1Path = testDir + '/stream-eq-t1.tmp';
            const t2Path = testDir + '/stream-eq-t2.tmp';
            await writeFile(dbPath, dbBuf);
            const fromFile = await kdbxweb.Kdbx.loadFromFile(dbPath, cred, {
                t1Path: t1Path,
                t2Path: t2Path
            });
            const fromBuffer = await kdbxweb.Kdbx.load(dbBuf, cred);
            expect(fromFile.meta.name).assertEqual('StreamDb');
            expect(fromFile.meta.name).assertEqual(fromBuffer.meta.name);
            // 条目标题一致
            const fileTitle = fromFile.getDefaultGroup().entries[0].fields.get('Title');
            const bufTitle = fromBuffer.getDefaultGroup().entries[0].fields.get('Title');
            expect(fileTitle).assertEqual('stream-entry');
            expect(fileTitle).assertEqual(bufTitle);
            // 附件内容一致
            const filePool = fromFile.binaries.getAllWithHashes();
            const bufPool = fromBuffer.binaries.getAllWithHashes();
            expect(filePool.length).assertEqual(bufPool.length);
            expect(filePool[0].hash).assertEqual(bufPool[0].hash);
            expect(kdbxweb.ByteUtils.arrayBufferEquals(
                binaryBytes(filePool[0].value), binaryBytes(bufPool[0].value))).assertTrue();
            try { fs.unlinkSync(dbPath); } catch { /* ignore */ }
            try { fs.unlinkSync(t1Path); } catch { /* ignore */ }
            try { fs.unlinkSync(t2Path); } catch { /* ignore */ }
        });

        /**
         * 流式落盘：≥4MB 附件在 inner header 解析时直接进加密缓存，
         * 不设 attachmentsDiskThreshold（排除 postLoad 转换路径），
         * 磁盘引用只能来自 S5 流式路径；内容可经 store 读回且哈希一致
         */
        it('streaming load places large attachment as disk ref', 0, async () => {
            const storeDir = testDir + '-store-big';
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo')
            );
            const db = createChaChaDb(cred, 'BigAttachDb');
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'big-attachment');
            const big = makePatternBuffer(BIG_ATTACHMENT_SIZE);
            const expectedHash = kdbxweb.ByteUtils.bytesToHex(
                new Uint8Array(await kdbxweb.CryptoEngine.sha256(big)));
            const binary = await db.binaries.add(big);
            entry.binaries.set('big.bin', binary);
            const dbBuf = await db.save();

            const store = new kdbxweb.AttachmentStore(
                storeDir,
                kdbxweb.ByteUtils.randomData(32)
            );
            const dbPath = testDir + '/stream-big.kdbx';
            const t1Path = testDir + '/stream-big-t1.tmp';
            const t2Path = testDir + '/stream-big-t2.tmp';
            await writeFile(dbPath, dbBuf);
            const loaded = await kdbxweb.Kdbx.loadFromFile(dbPath, cred, {
                t1Path: t1Path,
                t2Path: t2Path,
                attachmentStore: store
            });
            const pool = loaded.binaries.getAllWithHashes();
            expect(pool.length).assertEqual(1);
            expect(pool[0].value instanceof kdbxweb.KdbxBinaryDiskRef).assertTrue();
            const ref = pool[0].value as kdbxweb.KdbxBinaryDiskRef;
            expect(ref.hash).assertEqual(expectedHash);
            expect(ref.byteLength).assertEqual(BIG_ATTACHMENT_SIZE);
            // 内容经加密缓存读回保真
            const read = await loaded.binaries.readDiskRef(ref);
            expect(read.byteLength).assertEqual(BIG_ATTACHMENT_SIZE);
            expect(kdbxweb.ByteUtils.arrayBufferEquals(read, big)).assertTrue();
            try { fs.unlinkSync(dbPath); } catch { /* ignore */ }
            try { fs.unlinkSync(t1Path); } catch { /* ignore */ }
            try { fs.unlinkSync(t2Path); } catch { /* ignore */ }
        });

        /**
         * 阈值边界：<4MB 附件在流式路径下仍保持内存模式（行为与整缓冲一致）
         */
        it('streaming load keeps small attachment in memory', 0, async () => {
            const storeDir = testDir + '-store-small';
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo')
            );
            const db = createChaChaDb(cred, 'SmallAttachDb');
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'small-attachment');
            const small = kdbxweb.ByteUtils.stringToBuffer('small-attachment-bytes');
            const binary = await db.binaries.add(small);
            entry.binaries.set('s.bin', binary);
            const dbBuf = await db.save();

            const store = new kdbxweb.AttachmentStore(
                storeDir,
                kdbxweb.ByteUtils.randomData(32)
            );
            const dbPath = testDir + '/stream-small.kdbx';
            const t1Path = testDir + '/stream-small-t1.tmp';
            const t2Path = testDir + '/stream-small-t2.tmp';
            await writeFile(dbPath, dbBuf);
            const loaded = await kdbxweb.Kdbx.loadFromFile(dbPath, cred, {
                t1Path: t1Path,
                t2Path: t2Path,
                attachmentStore: store
            });
            const pool = loaded.binaries.getAllWithHashes();
            expect(pool.length).assertEqual(1);
            expect(pool[0].value instanceof kdbxweb.KdbxBinaryDiskRef).assertFalse();
            expect(kdbxweb.ByteUtils.arrayBufferEquals(binaryBytes(pool[0].value), small))
                .assertTrue();
            try { fs.unlinkSync(dbPath); } catch { /* ignore */ }
            try { fs.unlinkSync(t1Path); } catch { /* ignore */ }
            try { fs.unlinkSync(t2Path); } catch { /* ignore */ }
        });

        /**
         * 未压缩库：T1 即 inner 明文，流式路径直接从 T1 解析（不经 inflate）
         */
        it('loadFromFile with t2Path handles uncompressed db', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo')
            );
            const db = createChaChaDb(cred, 'NoGzipDb');
            db.header.compression = kdbxweb.Consts.CompressionAlgorithm.None;
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'nogzip-entry');
            const dbBuf = await db.save();

            const dbPath = testDir + '/stream-nogzip.kdbx';
            const t1Path = testDir + '/stream-nogzip-t1.tmp';
            const t2Path = testDir + '/stream-nogzip-t2.tmp';
            await writeFile(dbPath, dbBuf);
            const loaded = await kdbxweb.Kdbx.loadFromFile(dbPath, cred, {
                t1Path: t1Path,
                t2Path: t2Path
            });
            expect(loaded.meta.name).assertEqual('NoGzipDb');
            const title = loaded.getDefaultGroup().entries[0].fields.get('Title');
            expect(title).assertEqual('nogzip-entry');
            try { fs.unlinkSync(dbPath); } catch { /* ignore */ }
            try { fs.unlinkSync(t1Path); } catch { /* ignore */ }
            try { fs.unlinkSync(t2Path); } catch { /* ignore */ }
        });

        /**
         * CP2'：流式路径按 XML 区大小判定，极小上限触发 DecompressedTooLarge
         */
        it('streaming load respects maxDecompressedBytes limit', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo')
            );
            const db = createChaChaDb(cred, 'LimitDb');
            const dbBuf = await db.save();
            const dbPath = testDir + '/stream-limit.kdbx';
            const t1Path = testDir + '/stream-limit-t1.tmp';
            const t2Path = testDir + '/stream-limit-t2.tmp';
            await writeFile(dbPath, dbBuf);
            let threw = false;
            try {
                await kdbxweb.Kdbx.loadFromFile(dbPath, cred, {
                    t1Path: t1Path,
                    t2Path: t2Path,
                    maxDecompressedBytes: 1
                });
            } catch (e) {
                threw = true;
                expect(e instanceof kdbxweb.KdbxError).assertTrue();
                expect((e as kdbxweb.KdbxError).code)
                    .assertEqual(kdbxweb.Consts.ErrorCodes.DecompressedTooLarge);
            }
            expect(threw).assertTrue();
            try { fs.unlinkSync(dbPath); } catch { /* ignore */ }
            try { fs.unlinkSync(t1Path); } catch { /* ignore */ }
            try { fs.unlinkSync(t2Path); } catch { /* ignore */ }
        });
    });
}
