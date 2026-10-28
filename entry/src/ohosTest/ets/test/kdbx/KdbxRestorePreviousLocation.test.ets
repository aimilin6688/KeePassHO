import { beforeAll, describe, expect, it } from '@ohos/hypium';
import {
  Kdbx,
  KdbxCredentials,
  KdbxEntry,
  KdbxGroup,
  KdbxUuid,
  ProtectedValue
} from 'kdbxweb';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

/** 测试主密码 */
const TEST_PASSWORD: string = 'Restore-Prev-123';

/** 构造带 g1/g2 子分组的测试库（Kdbx.create 自带回收站） */
function makeDb(): [Kdbx, KdbxGroup, KdbxGroup] {
  const db = Kdbx.create(
    new KdbxCredentials(ProtectedValue.fromString(TEST_PASSWORD)),
    'RestoreDb'
  );
  const root = db.getDefaultGroup();
  const g1 = db.createGroup(root, 'G1');
  const g2 = db.createGroup(root, 'G2');
  return [db, g1, g2];
}

/** 取回收站分组 */
function getTrash(db: Kdbx): KdbxGroup {
  const trashUuid = db.meta.recycleBinUuid;
  const trash = trashUuid ? db.getGroup(trashUuid) : undefined;
  expect(trash !== undefined).assertTrue();
  return trash as KdbxGroup;
}

/**
 * P2-4 M2：回收站恢复到原位置（设计文档 §6.2，测试方案 §8.1 用例 9）。
 *
 * 覆盖（对齐 KeePass GetPreviousParentGroupSafeI / MainForm_Functions.cs:6896-6928）：
 * - getPreviousParentGroupSafe：未设置 / 目标已删 / 目标==当前父组 / 目标是自身或子孙 → 拒绝
 * - restoreToPreviousLocation：正常路径 → parentGroup 正确且 previousParentGroup 交换为回收站
 */
export default function KdbxRestorePreviousLocationTest() {
  describe('KdbxRestorePreviousLocationTest', () => {
    beforeAll(() => {
      KdbxModeTestHelper.initContext();
    });

    it('getPreviousParentGroupSafe rejects when previousParentGroup not set', 0, () => {
      const tuple = makeDb();
      const db = tuple[0];
      const g1 = tuple[1];
      const trash = getTrash(db);
      // 直接在回收站创建（未经 move，previousParentGroup 未设置）
      const entry = db.createEntry(trash);
      entry.fields.set('Title', 'NoPpg');
      expect(KdbxUtils.getPreviousParentGroupSafe(db, entry)).assertUndefined();
      // g1 中普通条目同样未设置
      const normalEntry = db.createEntry(g1);
      normalEntry.fields.set('Title', 'Normal');
      expect(KdbxUtils.getPreviousParentGroupSafe(db, normalEntry)).assertUndefined();
    });

    it('getPreviousParentGroupSafe rejects when target group permanently deleted', 0, () => {
      const tuple = makeDb();
      const db = tuple[0];
      const g1 = tuple[1];
      const trash = getTrash(db);
      const entry = db.createEntry(g1);
      entry.fields.set('Title', 'E1');
      db.remove(entry);
      expect(entry.parentGroup).assertEqual(trash);
      // 永久删除原分组 g1
      const ix = db.getDefaultGroup().groups.indexOf(g1);
      expect(ix >= 0).assertTrue();
      db.getDefaultGroup().groups.splice(ix, 1);
      expect(KdbxUtils.getPreviousParentGroupSafe(db, entry)).assertUndefined();
    });

    it('getPreviousParentGroupSafe rejects when target is current parent', 0, () => {
      const tuple = makeDb();
      const db = tuple[0];
      const g1 = tuple[1];
      const entry = db.createEntry(g1);
      entry.fields.set('Title', 'E1');
      // 构造"已在原位置"状态：previousParentGroup 指向当前父组
      entry.previousParentGroup = g1.uuid;
      expect(KdbxUtils.getPreviousParentGroupSafe(db, entry)).assertUndefined();
    });

    it('getPreviousParentGroupSafe rejects group restore into self or own descendant', 0, () => {
      const tuple = makeDb();
      const db = tuple[0];
      const root = db.getDefaultGroup();
      // 目标是自身
      const gSelf = db.createGroup(root, 'GSelf');
      db.remove(gSelf);
      gSelf.previousParentGroup = gSelf.uuid;
      expect(KdbxUtils.getPreviousParentGroupSafe(db, gSelf)).assertUndefined();
      // 目标是自身子孙：原父组 X 被移入待恢复分组 G 内（恢复会成环）
      const x = db.createGroup(root, 'X');
      const g = db.createGroup(x, 'G');
      db.remove(g);
      expect(g.previousParentGroup !== undefined).assertTrue();
      db.move(x, g);
      expect(x.parentGroup).assertEqual(g);
      expect(KdbxUtils.getPreviousParentGroupSafe(db, g)).assertUndefined();
    });

    it('restoreToPreviousLocation restores entry from trash and swaps previousParentGroup', 0, () => {
      const tuple = makeDb();
      const db = tuple[0];
      const g1 = tuple[1];
      const trash = getTrash(db);
      const entry = db.createEntry(g1);
      entry.fields.set('Title', 'E1');
      db.remove(entry);
      expect(db.isInRecycleBin(entry)).assertTrue();
      const ok = KdbxUtils.restoreToPreviousLocation(db, entry);
      expect(ok).assertTrue();
      expect(entry.parentGroup).assertEqual(g1);
      expect(db.isInRecycleBin(entry)).assertFalse();
      // 交换语义：previousParentGroup 更新为恢复前的父组（回收站）
      expect(entry.previousParentGroup !== undefined).assertTrue();
      const ppg = entry.previousParentGroup as KdbxUuid;
      expect(ppg.equals(trash.uuid)).assertTrue();
      // 再次删除后仍可再恢复（交换语义自洽）
      db.remove(entry);
      expect(KdbxUtils.restoreToPreviousLocation(db, entry)).assertTrue();
      expect(entry.parentGroup).assertEqual(g1);
    });

    it('restoreToPreviousLocation restores group from trash', 0, () => {
      const tuple = makeDb();
      const db = tuple[0];
      const g1 = tuple[1];
      const trash = getTrash(db);
      const sub = db.createGroup(g1, 'Sub');
      const childEntry = db.createEntry(sub);
      childEntry.fields.set('Title', 'Child');
      db.remove(sub);
      expect(db.isInRecycleBin(sub)).assertTrue();
      const ok = KdbxUtils.restoreToPreviousLocation(db, sub);
      expect(ok).assertTrue();
      expect(sub.parentGroup).assertEqual(g1);
      expect(db.isInRecycleBin(sub)).assertFalse();
      // 子条目随分组回到原位置
      expect(childEntry.parentGroup).assertEqual(sub);
      expect(db.isInRecycleBin(childEntry)).assertFalse();
      const ppg = sub.previousParentGroup as KdbxUuid;
      expect(ppg.equals(trash.uuid)).assertTrue();
    });

    it('restoreToPreviousLocation returns false and keeps position when not restorable', 0, () => {
      const tuple = makeDb();
      const db = tuple[0];
      const trash = getTrash(db);
      const entry = db.createEntry(trash);
      entry.fields.set('Title', 'NoPpg');
      const ok = KdbxUtils.restoreToPreviousLocation(db, entry);
      expect(ok).assertFalse();
      expect(entry.parentGroup).assertEqual(trash);
      // 目标已删场景同样保持原位
      const tuple2 = makeDb();
      const db2 = tuple2[0];
      const trash2 = getTrash(db2);
      const entry2 = db2.createEntry(tuple2[1]);
      entry2.fields.set('Title', 'E2');
      db2.remove(entry2);
      const ix = db2.getDefaultGroup().groups.indexOf(tuple2[1]);
      db2.getDefaultGroup().groups.splice(ix, 1);
      const ok2 = KdbxUtils.restoreToPreviousLocation(db2, entry2);
      expect(ok2).assertFalse();
      expect(entry2.parentGroup).assertEqual(trash2);
    });

    it('isDescendantOrSelf detects self, descendant and unrelated groups', 0, () => {
      const tuple = makeDb();
      const db = tuple[0];
      const root = db.getDefaultGroup();
      const g1 = tuple[1];
      const g11 = db.createGroup(g1, 'G11');
      // 自身
      expect(KdbxUtils.isDescendantOrSelf(g1, g1)).assertTrue();
      // 直接子孙
      expect(KdbxUtils.isDescendantOrSelf(g11, g1)).assertTrue();
      // 间接子孙
      const g111 = db.createGroup(g11, 'G111');
      expect(KdbxUtils.isDescendantOrSelf(g111, g1)).assertTrue();
      // 无关分组
      const g2 = tuple[2];
      expect(KdbxUtils.isDescendantOrSelf(g2, g1)).assertFalse();
      // 反方向（祖先对子孙）为 false
      expect(KdbxUtils.isDescendantOrSelf(g1, g11)).assertFalse();
      // 根组遍历到顶不误报
      expect(KdbxUtils.isDescendantOrSelf(root, g11)).assertFalse();
    });
  });
}
