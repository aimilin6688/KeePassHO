import { describe, expect, it, beforeAll } from '@ohos/hypium';
import * as kdbxweb from '../../../../main/ets/index';
import { ohosArgon2 } from '../../../../main/ets/crypto/argon2-rs';
import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * S6 保存管道文件版（saveToFile）专项测试。
 *
 * 验证 v4 + ChaCha20 全链路落盘（X1 inner → X2 deflate → X3 kdbx）产物：
 * - 可被 Kdbx.load 加载
 * - 与整缓冲 save() 产物加载后模型等价
 * - 磁盘引用附件经流式回读写出后内容保真
 * - 未压缩库往返
 * - canSaveToFile 判定与参数校验
 */
function writeFile(path: string, data: ArrayBuffer): Promise<void> {
    return fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC)
        .then((file) => fs.write(file.fd, data).then(() => fs.fsync(file.fd).then(() => fs.close(file.fd))));
}

function readFile(path: string): Promise<ArrayBuffer> {
    return fs.open(path, fs.OpenMode.READ_ONLY).then((file) =>
        fs.stat(file.fd).then((stat) => {
            const buf = new ArrayBuffer(stat.size);
            return fs.read(file.fd, buf).then(() => fs.close(file.fd).then(() => buf));
        })
    );
}

function binaryBytes(value: kdbxweb.KdbxBinary): ArrayBuffer {
    if (value instanceof kdbxweb.ProtectedValue) {
        return kdbxweb.ByteUtils.arrayToBuffer(value.getBinary());
    }
    return value as ArrayBuffer;
}

function cleanup(paths: string[]): void {
    for (const p of paths) {
        try { fs.unlinkSync(p); } catch (e) { /* best effort */ }
    }
}

export default function KdbxSaveToFileTest() {
    describe('KdbxSaveToFile', () => {
        let testDir: string;

        beforeAll(() => {
            kdbxweb.CryptoEngine.setArgon2Impl(ohosArgon2);
            testDir = '/data/storage/el2/base/haps/entry/files/save-to-file-test';
            try {
                if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
                    fs.mkdirSync(testDir, true);
                }
            } catch (e) {
                // 目录可能已存在
            }
        });

        /**
         * canSaveToFile 仅对 v4 + ChaCha20 为 true；默认 AES / v3 为 false（调用方回退 save）
         */
        it('canSaveToFile is true only for v4 + ChaCha20', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const aesDb = kdbxweb.Kdbx.create(cred, 'AesDb');
            expect(aesDb.canSaveToFile()).assertFalse();

            const db = kdbxweb.Kdbx.create(cred, 'ChaChaDb');
            db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
            expect(db.canSaveToFile()).assertTrue();

            db.header.setVersion(3);
            expect(db.canSaveToFile()).assertFalse();
        });

        /**
         * saveToFile 产物可被 Kdbx.load 加载，meta/条目与原库一致
         */
        it('saveToFile product can be loaded by Kdbx.load', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const db = kdbxweb.Kdbx.create(cred, 'SaveToFileDb');
            db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'save-to-file-entry');

            const outPath = testDir + '/stf-basic.kdbx';
            const x1 = testDir + '/stf-basic-x1.tmp';
            const x2 = testDir + '/stf-basic-x2.tmp';
            await db.saveToFile(outPath, { x1Path: x1, x2Path: x2 });
            const loaded = await kdbxweb.Kdbx.load(await readFile(outPath), cred);

            expect(loaded.meta.name).assertEqual('SaveToFileDb');
            expect(loaded.getDefaultGroup().entries[0].fields.get('Title')).assertEqual('save-to-file-entry');
            cleanup([outPath, x1, x2]);
        });

        /**
         * saveToFile 与 save 产物加载后模型等价（meta/条目/附件池）
         */
        it('saveToFile and save products load to equal models', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const db = kdbxweb.Kdbx.create(cred, 'EquivDb');
            db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'equiv-entry');
            const attach = kdbxweb.ByteUtils.stringToBuffer('equiv-attachment-payload');
            const binary = await db.binaries.add(attach);
            entry.binaries.set('a.bin', binary);

            const outPath = testDir + '/stf-equiv.kdbx';
            const x1 = testDir + '/stf-equiv-x1.tmp';
            const x2 = testDir + '/stf-equiv-x2.tmp';
            await db.saveToFile(outPath, { x1Path: x1, x2Path: x2 });
            const fromFile = await kdbxweb.Kdbx.load(await readFile(outPath), cred);

            const buf = await db.save();
            const fromBuffer = await kdbxweb.Kdbx.load(buf, cred);

            expect(fromFile.meta.name).assertEqual(fromBuffer.meta.name);
            expect(fromFile.getDefaultGroup().entries.length)
                .assertEqual(fromBuffer.getDefaultGroup().entries.length);
            const ft = fromFile.getDefaultGroup().entries[0].fields.get('Title');
            const bt = fromBuffer.getDefaultGroup().entries[0].fields.get('Title');
            expect(ft).assertEqual(bt);

            const fp = fromFile.binaries.getAllWithHashes();
            const bp = fromBuffer.binaries.getAllWithHashes();
            expect(fp.length).assertEqual(bp.length);
            expect(fp[0].hash).assertEqual(bp[0].hash);
            expect(kdbxweb.ByteUtils.arrayBufferEquals(
                binaryBytes(fp[0].value), binaryBytes(bp[0].value))).assertTrue();
            cleanup([outPath, x1, x2]);
        });

        /**
         * 未压缩库 saveToFile 往返（X2 不使用，载荷=X1）
         */
        it('saveToFile round-trips with compression None', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const db = kdbxweb.Kdbx.create(cred, 'NoCompressionDb');
            db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
            db.header.compression = kdbxweb.Consts.CompressionAlgorithm.None;
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'no-gzip-entry');

            const outPath = testDir + '/stf-none.kdbx';
            const x1 = testDir + '/stf-none-x1.tmp';
            const x2 = testDir + '/stf-none-x2.tmp';
            await db.saveToFile(outPath, { x1Path: x1, x2Path: x2 });
            const loaded = await kdbxweb.Kdbx.load(await readFile(outPath), cred);

            expect(loaded.meta.name).assertEqual('NoCompressionDb');
            expect(loaded.getDefaultGroup().entries[0].fields.get('Title')).assertEqual('no-gzip-entry');
            cleanup([outPath, x1, x2]);
        });

        /**
         * 磁盘引用附件库 saveToFile 往返：writeBinaryToFile 流式回读加密缓存写出，
         * 加载侧附件内容与原始字节一致（验证 S6 保存管道对 disk ref 的正确处理）
         */
        it('saveToFile round-trips disk-ref attachments via store', 0, async () => {
            const storeDir = testDir + '-store-diskref';
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const db = kdbxweb.Kdbx.create(cred, 'DiskRefSaveDb');
            db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'disk-ref-save');
            const big = kdbxweb.ByteUtils.stringToBuffer('x'.repeat(5 * 1024 * 1024));
            const binary = await db.binaries.add(big);
            entry.binaries.set('big.bin', binary);

            const store = new kdbxweb.AttachmentStore(storeDir, kdbxweb.ByteUtils.randomData(32));
            db.binaries.store = store;
            await db.binaries.maybeConvertToDiskRefs(1);
            expect(db.binaries.hasDiskRefs()).assertTrue();

            const outPath = testDir + '/stf-diskref.kdbx';
            const x1 = testDir + '/stf-diskref-x1.tmp';
            const x2 = testDir + '/stf-diskref-x2.tmp';
            await db.saveToFile(outPath, { x1Path: x1, x2Path: x2 });
            const loaded = await kdbxweb.Kdbx.load(await readFile(outPath), cred);

            const pool = loaded.binaries.getAllWithHashes();
            expect(pool.length).assertEqual(1);
            expect(kdbxweb.ByteUtils.arrayBufferEquals(binaryBytes(pool[0].value), big)).assertTrue();
            cleanup([outPath, x1, x2]);
        });

        /**
         * saveToFile 缺少路径参数抛 InvalidArg
         */
        it('saveToFile rejects missing path args', 0, () => {
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const db = kdbxweb.Kdbx.create(cred, 'ArgDb');
            db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
            return db.saveToFile('', { x1Path: 'a', x2Path: 'b' }).then(
                () => { expect(false).assertTrue(); },
                (e: kdbxweb.KdbxError) => {
                    expect(e.code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidArg);
                }
            );
        });

        /**
         * S6-f：serializeToFile 产出的 XML 与 serialize 语义等价（Kdbx.load 可解析、模型一致）。
         * 验证 DOM→文件分块序列化器正确性（转义、自闭合、属性、ProtectedValue base64 文本）。
         */
        it('serializeToFile output is parseable and model-equivalent', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const db = kdbxweb.Kdbx.create(cred, 'SerializeFileDb');
            db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'serialize-file-entry');
            entry.fields.set('Password', kdbxweb.ProtectedValue.fromString('secret-pass-123'));
            const attach = kdbxweb.ByteUtils.stringToBuffer('serialize-file-attachment');
            const binary = await db.binaries.add(attach);
            entry.binaries.set('s.bin', binary);

            // 用 saveToFile（内部走 serializeToFile）产出文件，再 Kdbx.load 读回
            const outPath = testDir + '/stf-serialize.kdbx';
            const x1 = testDir + '/stf-serialize-x1.tmp';
            const x2 = testDir + '/stf-serialize-x2.tmp';
            await db.saveToFile(outPath, { x1Path: x1, x2Path: x2 });
            const loaded = await kdbxweb.Kdbx.load(await readFile(outPath), cred);

            // 验证条目、ProtectedValue、附件
            const loadedEntry = loaded.getDefaultGroup().entries[0];
            expect(loadedEntry.fields.get('Title')).assertEqual('serialize-file-entry');
            const pwd = loadedEntry.fields.get('Password');
            expect(pwd instanceof kdbxweb.ProtectedValue).assertTrue();
            const pwdVal = pwd as kdbxweb.ProtectedValue;
            expect(kdbxweb.ByteUtils.bytesToString(pwdVal.getBinary())).assertEqual('secret-pass-123');
            const pool = loaded.binaries.getAllWithHashes();
            expect(pool.length).assertEqual(1);
            expect(kdbxweb.ByteUtils.arrayBufferEquals(binaryBytes(pool[0].value), attach)).assertTrue();
            cleanup([outPath, x1, x2]);
        });

        /**
         * S6-f：serializeToFile 处理特殊字符（<, >, &, "）不损坏 XML
         */
        it('serializeToFile escapes special characters correctly', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const db = kdbxweb.Kdbx.create(cred, 'EscapeDb');
            db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'a<b>&c"d\'e>f');
            entry.fields.set('Notes', 'x&y<z>w"q');

            const outPath = testDir + '/stf-escape.kdbx';
            const x1 = testDir + '/stf-escape-x1.tmp';
            const x2 = testDir + '/stf-escape-x2.tmp';
            await db.saveToFile(outPath, { x1Path: x1, x2Path: x2 });
            const loaded = await kdbxweb.Kdbx.load(await readFile(outPath), cred);
            const loadedEntry = loaded.getDefaultGroup().entries[0];
            expect(loadedEntry.fields.get('Title')).assertEqual('a<b>&c"d\'e>f');
            expect(loadedEntry.fields.get('Notes')).assertEqual('x&y<z>w"q');
            cleanup([outPath, x1, x2]);
        });
    });
}
