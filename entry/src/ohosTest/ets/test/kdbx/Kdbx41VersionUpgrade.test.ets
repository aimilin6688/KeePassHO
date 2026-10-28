import { beforeAll, describe, expect, it } from '@ohos/hypium';
import {
  Kdbx,
  KdbxCredentials,
  KdbxCustomDataItem,
  KdbxEntry,
  KdbxGroup,
  KdbxUuid,
  ProtectedValue
} from 'kdbxweb';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

/** 测试主密码 */
const TEST_PASSWORD: string = 'Kdbx41-Upgrade-123';

/** 构造测试凭证 */
function makeCredentials(): KdbxCredentials {
  return new KdbxCredentials(ProtectedValue.fromString(TEST_PASSWORD));
}

/** 保存后重载（完整加密往返） */
async function saveAndReload(db: Kdbx): Promise<Kdbx> {
  const data = await db.save();
  return Kdbx.load(data, makeCredentials());
}

/** 按 uuid 查找条目 */
function findEntry(db: Kdbx, uuid: KdbxUuid): KdbxEntry {
  for (const entry of db.getDefaultGroup().allEntries()) {
    if (entry.uuid.equals(uuid)) {
      return entry;
    }
  }
  throw new Error('entry not found: ' + uuid.id);
}

/** 按 uuid 查找分组 */
function findGroup(db: Kdbx, uuid: KdbxUuid): KdbxGroup {
  for (const item of db.getDefaultGroup().allGroupsAndEntries()) {
    if (item instanceof KdbxGroup && item.uuid.equals(uuid)) {
      return item;
    }
  }
  throw new Error('group not found: ' + uuid.id);
}

/** 读取 customData 中某键的值（避免非空断言） */
function customDataValue(
  customData: Map<string, KdbxCustomDataItem> | undefined,
  key: string
): string | undefined {
  const item = customData ? customData.get(key) : undefined;
  return item ? item.value : undefined;
}

/** 取 uuid id（避免非空断言） */
function uuidId(uuid: KdbxUuid | undefined): string {
  return uuid ? uuid.id : '';
}

/**
 * P2-4 M1：保存前 KDBX 版本自动评估测试（4.0 → 4.1）。
 *
 * 对齐 KeePass GetMinKdbxVersion（KdbxFile.cs：保存时按实际使用的特性
 * 计算最低版本）与 KeePassXC kdbxVersionRequired：
 * - 使用了 4.1 特性的 4.0 库，保存时静默升级为 4.1（次版本升级无加密/
 *   头部结构变更，KeePass 2.x 亦如此处理）
 * - 未使用 4.1 特性的 4.0 库保持 4.0（不惊扰文件）
 * - 3.1 库不自动升级（涉及加密结构变更，须用户显式 upgrade()）
 *
 * 触发特性（设计文档 §6）：
 * previousParentGroup / Group tags / QualityCheck / CustomData 项
 * lastModified / 自定义图标 name、lastModified
 */
export default function Kdbx41VersionUpgradeTest() {
  describe('Kdbx41VersionUpgradeTest', () => {
    beforeAll(() => {
      KdbxModeTestHelper.initContext();
    });

    it('saves 4.0 db upgraded to 4.1 when entry has previousParentGroup', 0, async () => {
      const db = Kdbx.create(makeCredentials(), 'Upgrade41Db');
      db.header.versionMinor = 0; // 模拟 KDBX 4.0 库
      const root = db.getDefaultGroup();
      const g1 = db.createGroup(root, 'G1');
      const g2 = db.createGroup(root, 'G2');
      const entry = db.createEntry(g1);
      db.move(entry, g2); // 维护 previousParentGroup = g1.uuid

      const reloaded = await saveAndReload(db);

      expect(reloaded.versionMajor).assertEqual(4);
      expect(reloaded.versionMinor).assertEqual(1);
      const reloadedEntry = findEntry(reloaded, entry.uuid);
      expect(uuidId(reloadedEntry.previousParentGroup)).assertEqual(g1.uuid.id);
      expect(uuidId(reloadedEntry.parentGroup ? reloadedEntry.parentGroup.uuid : undefined))
        .assertEqual(g2.uuid.id);
    });

    it('saves 4.0 db upgraded to 4.1 when group has tags', 0, async () => {
      const db = Kdbx.create(makeCredentials(), 'Upgrade41Db');
      db.header.versionMinor = 0;
      const root = db.getDefaultGroup();
      const g1 = db.createGroup(root, 'G1');
      g1.tags = ['grp-tag'];

      const reloaded = await saveAndReload(db);

      expect(reloaded.versionMinor).assertEqual(1);
      const reloadedGroup = findGroup(reloaded, g1.uuid);
      expect(reloadedGroup.tags.length).assertEqual(1);
      expect(reloadedGroup.tags[0]).assertEqual('grp-tag');
    });

    it('saves 4.0 db upgraded to 4.1 when entry qualityCheck is set', 0, async () => {
      const db = Kdbx.create(makeCredentials(), 'Upgrade41Db');
      db.header.versionMinor = 0;
      const root = db.getDefaultGroup();
      const entry = db.createEntry(root);
      entry.qualityCheck = false;

      const reloaded = await saveAndReload(db);

      expect(reloaded.versionMinor).assertEqual(1);
      const reloadedEntry = findEntry(reloaded, entry.uuid);
      expect(reloadedEntry.qualityCheck).assertEqual(false);
    });

    it('saves 4.0 db upgraded to 4.1 when customData has lastModified', 0, async () => {
      const db = Kdbx.create(makeCredentials(), 'Upgrade41Db');
      db.header.versionMinor = 0;
      const root = db.getDefaultGroup();
      const entry = db.createEntry(root);
      const customData = new Map<string, KdbxCustomDataItem>();
      customData.set('k', { value: 'v', lastModified: new Date(2026, 0, 2) });
      entry.customData = customData;

      const reloaded = await saveAndReload(db);

      expect(reloaded.versionMinor).assertEqual(1);
      const reloadedEntry = findEntry(reloaded, entry.uuid);
      expect(customDataValue(reloadedEntry.customData, 'k')).assertEqual('v');
      const item = reloadedEntry.customData ? reloadedEntry.customData.get('k') : undefined;
      expect(item ? item.lastModified !== undefined : false).assertTrue();
    });

    it('saves 4.0 db upgraded to 4.1 when meta customData has lastModified', 0, async () => {
      const db = Kdbx.create(makeCredentials(), 'Upgrade41Db');
      db.header.versionMinor = 0;
      db.meta.customData.set('mk', { value: 'mv', lastModified: new Date(2026, 0, 2) });

      const reloaded = await saveAndReload(db);

      expect(reloaded.versionMinor).assertEqual(1);
      expect(customDataValue(reloaded.meta.customData, 'mk')).assertEqual('mv');
    });

    it('saves 4.0 db upgraded to 4.1 when custom icon has lastModified', 0, async () => {
      const db = Kdbx.create(makeCredentials(), 'Upgrade41Db');
      db.header.versionMinor = 0;
      db.meta.customIcons.set(new KdbxUuid().id, {
        data: new ArrayBuffer(4),
        lastModified: new Date(2026, 0, 2)
      });

      const reloaded = await saveAndReload(db);

      expect(reloaded.versionMinor).assertEqual(1);
      expect(reloaded.meta.customIcons.size).assertEqual(1);
    });

    it('keeps 4.0 version when no 4.1 features are used', 0, async () => {
      const db = Kdbx.create(makeCredentials(), 'Upgrade41Db');
      db.header.versionMinor = 0;
      const root = db.getDefaultGroup();
      const entry = db.createEntry(root);
      // 4.0 兼容特性：条目 tags、无 lastModified 的 customData
      entry.tags = ['entry-tag-ok-in-40'];
      const customData = new Map<string, KdbxCustomDataItem>();
      customData.set('plain', { value: 'no-lastmod' });
      entry.customData = customData;

      const reloaded = await saveAndReload(db);

      expect(reloaded.versionMajor).assertEqual(4);
      expect(reloaded.versionMinor).assertEqual(0);
      const reloadedEntry = findEntry(reloaded, entry.uuid);
      expect(reloadedEntry.tags.length).assertEqual(1);
      expect(reloadedEntry.tags[0]).assertEqual('entry-tag-ok-in-40');
      expect(customDataValue(reloadedEntry.customData, 'plain')).assertEqual('no-lastmod');
    });

    it('does not auto-upgrade 3.1 db', 0, async () => {
      const db = Kdbx.create(makeCredentials(), 'Upgrade41Db');
      db.setVersion(3);
      const root = db.getDefaultGroup();
      const g1 = db.createGroup(root, 'G1');
      const g2 = db.createGroup(root, 'G2');
      const entry = db.createEntry(g1);
      db.move(entry, g2); // previousParentGroup 被维护，但 3.1 不自动升级

      const reloaded = await saveAndReload(db);

      expect(reloaded.versionMajor).assertEqual(3);
      expect(reloaded.versionMinor).assertEqual(1);
      const reloadedEntry = findEntry(reloaded, entry.uuid);
      // 位置正常持久化，previousParentGroup 在 3.1 中被丢弃（KeePass 3.x 行为）
      expect(uuidId(reloadedEntry.parentGroup ? reloadedEntry.parentGroup.uuid : undefined))
        .assertEqual(g2.uuid.id);
      expect(reloadedEntry.previousParentGroup === undefined).assertTrue();
    });
  });
}
