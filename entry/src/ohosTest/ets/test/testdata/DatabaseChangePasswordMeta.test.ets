import { describe, expect, it } from '@ohos/hypium';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { TestDataGenerator } from './TestDataGenerator';

const DOMAIN = 0x0000;
const TAG = 'DatabaseChangePasswordMetaTest';
/** 修改主密码用例的新密码 */
const NEW_PASSWORD = 'E2e-Test-456@New!';

/**
 * 数据库操作单元测试（仅测试目录，不进入主应用），作为生成套件的姊妹用例：
 *
 * 1. change_master_password_roundtrip —— 修改主密码往返：
 *    生成→原密码可解锁→修改主密码（镜像 workers/DatabaseSave.ets 的
 *    credentials.setPassword + save 机制）→旧密码被拒绝→新密码可解锁且数据完整。
 * 2. set_metadata_and_persist —— 元数据设置持久化：
 *    修改 name/desc/defaultUser/historyMaxItems/historyMaxSize/recycleBinEnabled→
 *    保存→重载→逐项校验（镜像 pages/setting/SettingDatabaseMeta.ets 可编辑字段）。
 */
export default function DatabaseChangePasswordMetaTest() {
  describe('DatabaseChangePasswordMetaTest', () => {

    it('change_master_password_roundtrip', 0, async () => {
      const db = await TestDataGenerator.generate();
      const originalEntryCount = TestDataGenerator.countEntries(db.getDefaultGroup());
      const saved = await db.save();

      // 原密码可解锁
      const reloaded = await Kdbx.load(saved,
        new KdbxCredentials(ProtectedValue.fromString(TestDataGenerator.DB_PASSWORD)));
      expect(reloaded.meta.name).assertEqual(TestDataGenerator.DB_NAME);

      // 修改主密码（与 workers/DatabaseSave.ets 实际机制一致）
      await reloaded.credentials.setPassword(ProtectedValue.fromString(NEW_PASSWORD));
      const resaved = await reloaded.save();
      hilog.info(DOMAIN, TAG, 'password changed, resaved: %{public}d bytes', resaved.byteLength);

      // 旧密码被拒绝
      let oldRejected = false;
      try {
        await Kdbx.load(resaved,
          new KdbxCredentials(ProtectedValue.fromString(TestDataGenerator.DB_PASSWORD)));
      } catch (e) {
        oldRejected = true;
      }
      expect(oldRejected).assertTrue();

      // 新密码可解锁且数据完整
      const final = await Kdbx.load(resaved,
        new KdbxCredentials(ProtectedValue.fromString(NEW_PASSWORD)));
      expect(final.meta.name).assertEqual(TestDataGenerator.DB_NAME);
      expect(TestDataGenerator.countEntries(final.getDefaultGroup()))
        .assertEqual(originalEntryCount);
    });

    it('set_metadata_and_persist', 0, async () => {
      const db = await TestDataGenerator.generate();
      db.meta.name = 'E2E-重命名数据库';
      db.meta.desc = '新描述：验证元数据持久化';
      db.meta.defaultUser = 'new-default-user@example.com';
      db.meta.historyMaxItems = 20;
      db.meta.historyMaxSize = 20 * 1024 * 1024;
      db.meta.recycleBinEnabled = true;
      const saved = await db.save();

      const reloaded = await Kdbx.load(saved,
        new KdbxCredentials(ProtectedValue.fromString(TestDataGenerator.DB_PASSWORD)));
      expect(reloaded.meta.name).assertEqual('E2E-重命名数据库');
      expect(reloaded.meta.desc).assertEqual('新描述：验证元数据持久化');
      expect(reloaded.meta.defaultUser).assertEqual('new-default-user@example.com');
      expect(reloaded.meta.historyMaxItems).assertEqual(20);
      expect(reloaded.meta.historyMaxSize).assertEqual(20 * 1024 * 1024);
      expect(reloaded.meta.recycleBinEnabled).assertTrue();
    });
  });
}
