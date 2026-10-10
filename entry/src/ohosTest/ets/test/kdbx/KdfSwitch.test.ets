import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { ByteUtils, Consts, Int64, Kdbx, KdbxCredentials, ProtectedValue, VarDictionary } from 'kdbxweb';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

/** 测试主密码 */
const TEST_PASSWORD: string = 'Kdf-Switch-Test-123';
/** 快速 Argon2 参数（低迭代/小内存，保证测试速度） */
const ARGON2_ITERATIONS: number = 2;
const ARGON2_MEMORY_MIB: number = 8;
const ARGON2_PARALLELISM: number = 1;
/** AES-KDF 转换轮数 */
const AES_ROUNDS: number = 60000;

/** 构造测试凭证 */
function makeCredentials(): KdbxCredentials {
  return new KdbxCredentials(ProtectedValue.fromString(TEST_PASSWORD));
}

/** 读取 kdfParameters 当前 KDF 类型（base64 $UUID，与页面 saveAlgoParams 判定口径一致） */
function currentKdf(kdf: VarDictionary): string {
  const uuid = kdf.get('$UUID');
  if (!(uuid instanceof ArrayBuffer)) {
    throw new Error('kdf $UUID is missing');
  }
  return ByteUtils.bytesToBase64(uuid);
}

/** 取 kdfParameters（v4 必有，缺失视为测试环境异常） */
function requireKdf(database: Kdbx): VarDictionary {
  const kdf = database.header.kdfParameters;
  if (!kdf) {
    throw new Error('kdfParameters is missing');
  }
  return kdf;
}

/** 读取 UInt64 参数的数值（I/M/R） */
function int64Value(kdf: VarDictionary, key: string): number {
  const value = kdf.get(key);
  if (value instanceof Int64) {
    return value.valueOf();
  }
  throw new Error('not an Int64 value: ' + key);
}

/** 应用用户 Argon2 参数（与页面 saveAlgoParams 修复后逻辑一致） */
function applyArgon2Params(kdf: VarDictionary, iterations: number, memoryMiB: number, parallelism: number): void {
  kdf.set('I', VarDictionary.ValueType.UInt64, Int64.from(iterations));
  kdf.set('M', VarDictionary.ValueType.UInt64, Int64.from(memoryMiB * 1024 * 1024));
  kdf.set('P', VarDictionary.ValueType.UInt32, parallelism);
}

/** 应用用户 AES 转换轮数（与页面 saveAlgoParams 修复后逻辑一致） */
function applyAesParams(kdf: VarDictionary, rounds: number): void {
  kdf.set('R', VarDictionary.ValueType.UInt64, Int64.from(rounds));
}

/**
 * KDF 切换（AES-KDF ↔ Argon2d/Argon2id）单元测试。
 *
 * 回归背景：KDBX4 下页面切换 KDF 曾原地修改 kdfParameters 而未补 Argon2 必需的 V 键，
 * 保存时 encryptArgon2 校验 V（必须为 0x13 或 0x10）失败，抛 FileCorrupt: bad argon2 version。
 * 修复后 KDF 类型变化时通过 header.setKdf 重建参数字典（补齐 V/S、清除旧算法残留键），
 * 再应用用户输入的参数。本套件在 kdbxweb 层镜像页面修复后的完整切换流程。
 */
export default function KdfSwitchTest() {
  describe('KdfSwitchTest', () => {
    beforeAll(() => {
      KdbxModeTestHelper.initContext();
    });

    /**
     * 新建库默认为 KDBX4 + Argon2d，且 V=0x13（回归基线）
     */
    it('Kdbx.create defaults to v4 Argon2d with V=0x13', 0, () => {
      const database = Kdbx.create(makeCredentials(), 'KdfSwitchDb');
      expect(database.header.versionMajor).assertEqual(4);
      const kdf = requireKdf(database);
      expect(currentKdf(kdf)).assertEqual(Consts.KdfId.Argon2d);
      expect(kdf.get('V')).assertEqual(0x13);
    });

    /**
     * AES-KDF 库切换 Argon2d：setKdf 重建字典补齐 V/S、清除 R 残留，保存与重载均成功
     * （核心修复回归：旧逻辑原地改字典不补 V，保存即抛 bad argon2 version）
     */
    it('switching AES-KDF to Argon2d recreates dict with V and saves', 0, async () => {
      const database = Kdbx.create(makeCredentials(), 'KdfSwitchDb');
      const header = database.header;
      // 模拟当前使用 AES-KDF 的数据库
      header.setKdf(Consts.KdfId.Aes);
      applyAesParams(requireKdf(database), AES_ROUNDS);
      await database.save();

      // 页面 saveAlgoParams 修复后的切换逻辑：类型变化时 setKdf 重建字典
      if (currentKdf(requireKdf(database)) !== Consts.KdfId.Argon2d) {
        header.setKdf(Consts.KdfId.Argon2d);
      }
      const newParams = requireKdf(database);
      applyArgon2Params(newParams, ARGON2_ITERATIONS, ARGON2_MEMORY_MIB, ARGON2_PARALLELISM);

      // 重建后的字典包含 Argon2 必需键且无 AES 残留键
      expect(newParams.get('V')).assertEqual(0x13);
      expect(newParams.get('S') !== undefined).assertTrue();
      expect(newParams.keys().includes('R')).assertFalse();
      expect(int64Value(newParams, 'I')).assertEqual(ARGON2_ITERATIONS);

      const saved: ArrayBuffer = await database.save();
      const reloaded = await Kdbx.load(saved, makeCredentials());
      const reloadedKdf = requireKdf(reloaded);
      expect(currentKdf(reloadedKdf)).assertEqual(Consts.KdfId.Argon2d);
      expect(reloadedKdf.get('V')).assertEqual(0x13);
      expect(int64Value(reloadedKdf, 'I')).assertEqual(ARGON2_ITERATIONS);
      expect(int64Value(reloadedKdf, 'M')).assertEqual(ARGON2_MEMORY_MIB * 1024 * 1024);
      expect(reloadedKdf.get('P')).assertEqual(ARGON2_PARALLELISM);
    });

    /**
     * Argon2d 库切换 AES-KDF：重建字典清除 Argon2 残留键，保存与重载均成功
     */
    it('switching Argon2d to AES-KDF cleans stale keys and saves', 0, async () => {
      const database = Kdbx.create(makeCredentials(), 'KdfSwitchDb');
      const header = database.header;
      applyArgon2Params(requireKdf(database), ARGON2_ITERATIONS, ARGON2_MEMORY_MIB, ARGON2_PARALLELISM);
      await database.save();

      if (currentKdf(requireKdf(database)) !== Consts.KdfId.Aes) {
        header.setKdf(Consts.KdfId.Aes);
      }
      const newParams = requireKdf(database);
      applyAesParams(newParams, AES_ROUNDS);

      expect(currentKdf(newParams)).assertEqual(Consts.KdfId.Aes);
      expect(newParams.keys().includes('V')).assertFalse();
      expect(newParams.keys().includes('I')).assertFalse();
      expect(newParams.keys().includes('M')).assertFalse();
      expect(newParams.keys().includes('P')).assertFalse();

      const saved: ArrayBuffer = await database.save();
      const reloaded = await Kdbx.load(saved, makeCredentials());
      const reloadedKdf = requireKdf(reloaded);
      expect(currentKdf(reloadedKdf)).assertEqual(Consts.KdfId.Aes);
      expect(int64Value(reloadedKdf, 'R')).assertEqual(AES_ROUNDS);
    });

    /**
     * 切换 Argon2id：同样通过 setKdf 重建并保存成功
     */
    it('switching AES-KDF to Argon2id recreates dict with V and saves', 0, async () => {
      const database = Kdbx.create(makeCredentials(), 'KdfSwitchDb');
      const header = database.header;
      // 模拟当前使用 AES-KDF 的数据库
      header.setKdf(Consts.KdfId.Aes);
      applyAesParams(requireKdf(database), AES_ROUNDS);

      if (currentKdf(requireKdf(database)) !== Consts.KdfId.Argon2id) {
        header.setKdf(Consts.KdfId.Argon2id);
      }
      const newParams = requireKdf(database);
      applyArgon2Params(newParams, ARGON2_ITERATIONS, ARGON2_MEMORY_MIB, ARGON2_PARALLELISM);

      expect(newParams.get('V')).assertEqual(0x13);
      const saved: ArrayBuffer = await database.save();
      const reloaded = await Kdbx.load(saved, makeCredentials());
      expect(currentKdf(requireKdf(reloaded))).assertEqual(Consts.KdfId.Argon2id);
      expect(requireKdf(reloaded).get('V')).assertEqual(0x13);
    });

    /**
     * 同类型仅调参：不重建字典，盐值 S 保持不变
     */
    it('re-applying same KDF keeps existing salt', 0, async () => {
      const database = Kdbx.create(makeCredentials(), 'KdfSwitchDb');
      const kdf = requireKdf(database);
      const saltBefore = kdf.get('S');
      applyArgon2Params(kdf, 4, 16, 2);
      // 同类型调整不触发 setKdf 重建，盐值引用不变
      expect(kdf.get('S')).assertEqual(saltBefore);

      const saved: ArrayBuffer = await database.save();
      const reloaded = await Kdbx.load(saved, makeCredentials());
      expect(int64Value(requireKdf(reloaded), 'I')).assertEqual(4);
    });

    /**
     * 旧缺陷回归守卫：原地改 $UUID/I/M/P 而不补 V，保存以 bad argon2 version 拒绝
     */
    it('in-place mutation without V rejects with bad argon2 version', 0, async () => {
      const database = Kdbx.create(makeCredentials(), 'KdfSwitchDb');
      database.header.setKdf(Consts.KdfId.Aes);
      const kdf = requireKdf(database);
      // 旧缺陷路径：仅原地改写 $UUID 与 I/M/P，不 setKdf 重建、不补 V
      kdf.set('$UUID', VarDictionary.ValueType.Bytes, ByteUtils.base64ToBytes(Consts.KdfId.Argon2d));
      applyArgon2Params(kdf, ARGON2_ITERATIONS, ARGON2_MEMORY_MIB, ARGON2_PARALLELISM);

      let rejected = false;
      try {
        await database.save();
      } catch (e) {
        rejected = true;
        expect(e.message.includes('bad argon2 version')).assertTrue();
      }
      expect(rejected).assertTrue();
    });
  });
}
