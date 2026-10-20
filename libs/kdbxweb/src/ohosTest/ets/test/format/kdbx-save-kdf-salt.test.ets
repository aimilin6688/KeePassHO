import { describe, expect, it, beforeAll } from '@ohos/hypium';
import * as kdbxweb from '../../../../main/ets/index';
import { ohosArgon2 } from '../../../../main/ets/crypto/argon2-rs';
import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * XC 两阶段保存 §9.3：save/saveToFile 预挑战 KDF salt 注入专项测试。
 *
 * 验证 SaveOptions.kdfSalt（applyKdfSaltOverride）：
 * - 注入 salt 写入 kdfParameters 'S'（重读文件头校验）
 * - 无 opts 行为不变（每次保存随机 salt，两次不同）
 * - 挑战-应答复合凭证 + 注入 salt 往返（模拟 XC 保存链路：固定应答解锁回开）
 * - saveToFile 文件版注入
 * - 参数校验：v3 库注入 Unsupported、非 32 字节 InvalidArg（均经 Promise 拒绝）
 */
function saltOf(db: kdbxweb.Kdbx): ArrayBuffer {
    const kdfParameters = db.header.kdfParameters;
    if (!kdfParameters) {
        throw new Error('no kdf parameters');
    }
    const salt = kdfParameters.get('S');
    if (!(salt instanceof ArrayBuffer)) {
        throw new Error('no kdf salt');
    }
    return salt;
}

export default function KdbxSaveKdfSaltTest() {
    describe('KdbxSaveKdfSalt', () => {
        beforeAll(() => {
            kdbxweb.CryptoEngine.setArgon2Impl(ohosArgon2);
        });

        /**
         * save({ kdfSalt }) 注入：产物可加载，且文件头 kdfParameters 'S' == 注入值
         */
        it('save injects kdfSalt into header S', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const db = kdbxweb.Kdbx.create(cred, 'SaltInjectDb');
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'salt-injected-entry');

            const kdfSalt = kdbxweb.ByteUtils.arrayToBuffer(kdbxweb.ByteUtils.randomData(32));
            const ab = await db.save({ kdfSalt });
            const loaded = await kdbxweb.Kdbx.load(ab, cred);

            expect(loaded.getDefaultGroup().entries[0].fields.get('Title')).assertEqual('salt-injected-entry');
            expect(kdbxweb.ByteUtils.arrayBufferEquals(saltOf(loaded), kdfSalt)).assertTrue();
        });

        /**
         * 无 opts 行为不变：两次保存 salt 均为 32 字节随机值且互不相同（generateSalts 语义保持）
         */
        it('save without opts keeps random salt behavior', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const db = kdbxweb.Kdbx.create(cred, 'RandomSaltDb');

            const ab1 = await db.save();
            const loaded1 = await kdbxweb.Kdbx.load(ab1, cred);
            const salt1 = saltOf(loaded1);

            const ab2 = await db.save();
            const loaded2 = await kdbxweb.Kdbx.load(ab2, cred);
            const salt2 = saltOf(loaded2);

            expect(salt1.byteLength).assertEqual(32);
            expect(salt2.byteLength).assertEqual(32);
            expect(kdbxweb.ByteUtils.arrayBufferEquals(salt1, salt2)).assertFalse();
        });

        /**
         * XC 链路模拟：挑战-应答复合凭证 + 注入预挑战 salt 保存 →
         * 以同一固定应答重新加载成功（M1+M2 组合的 kdbxweb 层验证）
         */
        it('save with injected salt round-trips challenge-response credentials', 0, async () => {
            const fixedResponse = kdbxweb.ByteUtils.arrayToBuffer(kdbxweb.ByteUtils.randomData(20));
            const challengeResponse: kdbxweb.KdbxChallengeResponseFn = (challenge) =>
                Promise.resolve(new Uint8Array(fixedResponse));
            const cred = new kdbxweb.KdbxCredentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                null,
                challengeResponse
            );
            const db = kdbxweb.Kdbx.create(cred, 'XcSaltDb');
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'xc-salt-entry');

            const kdfSalt = kdbxweb.ByteUtils.arrayToBuffer(kdbxweb.ByteUtils.randomData(32));
            const ab = await db.save({ kdfSalt });

            const reloaded = await kdbxweb.Kdbx.load(ab, cred);
            expect(reloaded.getDefaultGroup().entries[0].fields.get('Title')).assertEqual('xc-salt-entry');
            expect(kdbxweb.ByteUtils.arrayBufferEquals(saltOf(reloaded), kdfSalt)).assertTrue();
        });

        /**
         * saveToFile({ kdfSalt }) 文件版注入：产物头 'S' == 注入值
         */
        it('saveToFile injects kdfSalt into header S', 0, async () => {
            const testDir = '/data/storage/el2/base/haps/entry/files/save-kdf-salt-test';
            try {
                if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
                    fs.mkdirSync(testDir, true);
                }
            } catch (e) {
                // 目录可能已存在
            }
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));
            const db = kdbxweb.Kdbx.create(cred, 'SaltFileDb');
            db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
            const entry = db.createEntry(db.getDefaultGroup());
            entry.fields.set('Title', 'salt-file-entry');

            const outPath = testDir + '/salt.kdbx';
            const x1 = testDir + '/salt-x1.tmp';
            const x2 = testDir + '/salt-x2.tmp';
            const kdfSalt = kdbxweb.ByteUtils.arrayToBuffer(kdbxweb.ByteUtils.randomData(32));
            await db.saveToFile(outPath, { x1Path: x1, x2Path: x2, kdfSalt });

            const buf = await fs.open(outPath, fs.OpenMode.READ_ONLY).then((file) =>
                fs.stat(file.fd).then((stat) => {
                    const data = new ArrayBuffer(stat.size);
                    return fs.read(file.fd, data).then(() => fs.close(file.fd).then(() => data));
                })
            );
            const loaded = await kdbxweb.Kdbx.load(buf, cred);
            expect(loaded.getDefaultGroup().entries[0].fields.get('Title')).assertEqual('salt-file-entry');
            expect(kdbxweb.ByteUtils.arrayBufferEquals(saltOf(loaded), kdfSalt)).assertTrue();

            for (const p of [outPath, x1, x2]) {
                try { fs.unlinkSync(p); } catch (e) { /* best effort */ }
            }
        });

        /**
         * 参数校验：v3 库注入拒绝（Unsupported）、非 32 字节拒绝（InvalidArg）
         */
        it('save rejects kdfSalt for v3 and wrong length', 0, async () => {
            const cred = new kdbxweb.KdbxCredentials(kdbxweb.ProtectedValue.fromString('demo'));

            const v3Db = kdbxweb.Kdbx.create(cred, 'V3SaltDb');
            v3Db.header.setVersion(3);
            const salt32 = kdbxweb.ByteUtils.arrayToBuffer(kdbxweb.ByteUtils.randomData(32));
            try {
                await v3Db.save({ kdfSalt: salt32 });
                expect(false).assertTrue();
            } catch (e) {
                const err = e as kdbxweb.KdbxError;
                expect(err.code).assertEqual(kdbxweb.Consts.ErrorCodes.Unsupported);
            }

            const v4Db = kdbxweb.Kdbx.create(cred, 'BadLenSaltDb');
            const salt31 = kdbxweb.ByteUtils.arrayToBuffer(kdbxweb.ByteUtils.randomData(31));
            try {
                await v4Db.save({ kdfSalt: salt31 });
                expect(false).assertTrue();
            } catch (e) {
                const err = e as kdbxweb.KdbxError;
                expect(err.code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidArg);
            }
        });
    });
}
