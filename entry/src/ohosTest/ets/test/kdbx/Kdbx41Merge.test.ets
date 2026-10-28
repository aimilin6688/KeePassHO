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
const TEST_PASSWORD: string = 'Kdbx41-Merge-123';

// 共享 UUID：local 与 remote 两个库使用同一组对象标识（上游 kdbx.merge.test 模式）
const ROOT_ID: KdbxUuid = KdbxUuid.random();
const TRASH_ID: KdbxUuid = KdbxUuid.random();
const G1_ID: KdbxUuid = KdbxUuid.random();
const G2_ID: KdbxUuid = KdbxUuid.random();
const G11_ID: KdbxUuid = KdbxUuid.random();
const ENTRY_ID: KdbxUuid = KdbxUuid.random();
const NEW_ENTRY_ID: KdbxUuid = KdbxUuid.random();

/** 固定时间基线（避免同毫秒创建导致时间比较失真） */
const T_BASE: number = new Date(2026, 0, 1).getTime();

/** 基线 + N 天 */
function at(dayOffset: number): Date {
  return new Date(T_BASE + dayOffset * 86400000);
}

/** 构造测试凭证 */
function makeCredentials(): KdbxCredentials {
  return new KdbxCredentials(ProtectedValue.fromString(TEST_PASSWORD));
}

/** 测试库结构：local / remote 各持一份同构对象 */
interface Merge41Db {
  db: Kdbx;
  g1: KdbxGroup;
  g2: KdbxGroup;
  g11: KdbxGroup;
  entry: KdbxEntry;
}

/** 构造 local/remote 共享结构的数据库（root/trash/g1/g2/g11/entry 全部对齐 uuid 与时间基线） */
function makeDb(): Merge41Db {
  const db = Kdbx.create(makeCredentials(), 'Merge41Db');
  const root = db.getDefaultGroup();
  root.uuid = ROOT_ID;
  root.times.lastModTime = at(0);
  root.times.locationChanged = at(0);

  // 回收站对齐（Kdbx.create 已创建随机 uuid 的回收站，改为共享 TRASH_ID）
  const oldTrashUuid = db.meta.recycleBinUuid;
  const trash = oldTrashUuid ? db.getGroup(oldTrashUuid) : undefined;
  if (trash) {
    trash.uuid = TRASH_ID;
    trash.times.lastModTime = at(0);
    trash.times.locationChanged = at(0);
  }
  db.meta.recycleBinUuid = TRASH_ID;

  const g1 = db.createGroup(root, 'G1');
  g1.uuid = G1_ID;
  g1.times.lastModTime = at(0);
  g1.times.locationChanged = at(0);

  const g2 = db.createGroup(root, 'G2');
  g2.uuid = G2_ID;
  g2.times.lastModTime = at(0);
  g2.times.locationChanged = at(0);

  const g11 = db.createGroup(g1, 'G11');
  g11.uuid = G11_ID;
  g11.times.lastModTime = at(0);
  g11.times.locationChanged = at(0);

  const entry = db.createEntry(g1);
  entry.uuid = ENTRY_ID;
  entry.fields.set('Title', 'E1');
  entry.times.lastModTime = at(0);
  entry.times.locationChanged = at(0);

  return { db: db, g1: g1, g2: g2, g11: g11, entry: entry };
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
 * P2-4 M1：merge 4.1 字段补全测试。
 *
 * 覆盖差距（设计文档 §4 G1/G4，对齐 KeePass PwDatabase.MergeInLocationChanged
 * GetBestPool 语义：LocationChanged 胜出一方的 previousParentGroup 与
 * locationChanged 一起落地）：
 * 1. 远端条目内容较新 → customData / qualityCheck 不丢失（copyFrom 补全）
 * 2. 远端分组较新 → 分组 tags / customData 不丢失（copyFrom 补全）
 * 3. 远端移动胜出（条目/分组）→ previousParentGroup 采用远端值并同步
 *    locationChanged，保证后续 merge 收敛
 * 4. 远端新建对象 → previousParentGroup 随对象落地（回收站恢复原位置的依据）
 */
export default function Kdbx41MergeTest() {
  describe('Kdbx41MergeTest', () => {
    beforeAll(() => {
      KdbxModeTestHelper.initContext();
    });

    it('merge keeps remote entry customData and qualityCheck when remote content is newer', 0, () => {
      const local = makeDb();
      const remote = makeDb();

      remote.entry.times.lastModTime = at(2);
      const remoteCustomData = new Map<string, KdbxCustomDataItem>();
      remoteCustomData.set('rk', { value: 'rv', lastModified: at(1) });
      remote.entry.customData = remoteCustomData;
      remote.entry.qualityCheck = false;

      local.db.merge(remote.db);

      expect(customDataValue(local.entry.customData, 'rk')).assertEqual('rv');
      expect(local.entry.qualityCheck).assertEqual(false);
    });

    it('merge keeps remote group tags and customData when remote group is newer', 0, () => {
      const local = makeDb();
      const remote = makeDb();

      remote.g2.tags = ['remote-tag'];
      const remoteCustomData = new Map<string, KdbxCustomDataItem>();
      remoteCustomData.set('gk', { value: 'gv' });
      remote.g2.customData = remoteCustomData;
      remote.g2.times.lastModTime = at(3);

      local.db.merge(remote.db);

      expect(local.g2.tags.length).assertEqual(1);
      expect(local.g2.tags[0]).assertEqual('remote-tag');
      expect(customDataValue(local.g2.customData, 'gk')).assertEqual('gv');
    });

    it('merge moves entry with remote-won location and syncs previousParentGroup', 0, () => {
      const local = makeDb();
      const remote = makeDb();

      // 本地曾从 root 移入 g1（previousParentGroup = root）
      local.entry.previousParentGroup = ROOT_ID;
      // 远端稍后将 entry 从 g1 移到 g2
      remote.db.move(remote.entry, remote.g2);
      remote.entry.times.locationChanged = at(5);

      local.db.merge(remote.db);

      // 条目落地到本地 g2
      expect(uuidId(local.entry.parentGroup ? local.entry.parentGroup.uuid : undefined))
        .assertEqual(G2_ID.id);
      expect(local.g1.entries.length).assertEqual(0);
      expect(local.g2.entries.length).assertEqual(1);
      // previousParentGroup 采用远端胜出一方（KeePass GetBestPool 语义）
      expect(uuidId(local.entry.previousParentGroup)).assertEqual(G1_ID.id);
      // locationChanged 同步为远端值，保证后续 merge 收敛
      const mergedLocationChanged = local.entry.times.locationChanged;
      expect(mergedLocationChanged ? mergedLocationChanged.getTime() : 0)
        .assertEqual(at(5).getTime());
    });

    it('merge moves group with remote-won location and syncs previousParentGroup', 0, () => {
      const local = makeDb();
      const remote = makeDb();

      remote.db.move(remote.g11, remote.g2);
      remote.g11.times.locationChanged = at(6);

      local.db.merge(remote.db);

      expect(uuidId(local.g11.parentGroup ? local.g11.parentGroup.uuid : undefined))
        .assertEqual(G2_ID.id);
      expect(local.g2.groups.length).assertEqual(1);
      expect(uuidId(local.g11.previousParentGroup)).assertEqual(G1_ID.id);
    });

    it('merge creates remote-new entry with previousParentGroup preserved', 0, () => {
      const local = makeDb();
      const remote = makeDb();

      const newEntry = remote.db.createEntry(remote.g2);
      newEntry.uuid = NEW_ENTRY_ID;
      newEntry.fields.set('Title', 'NewRemote');
      newEntry.previousParentGroup = G1_ID;
      newEntry.times.lastModTime = at(1);
      newEntry.times.locationChanged = at(1);

      local.db.merge(remote.db);

      expect(local.g2.entries.length).assertEqual(1);
      const merged = local.g2.entries[0];
      expect(merged.uuid.id).assertEqual(NEW_ENTRY_ID.id);
      expect(merged.fields.get('Title')).assertEqual('NewRemote');
      expect(uuidId(merged.previousParentGroup)).assertEqual(G1_ID.id);
      expect(uuidId(merged.parentGroup ? merged.parentGroup.uuid : undefined))
        .assertEqual(G2_ID.id);
    });
  });
}
