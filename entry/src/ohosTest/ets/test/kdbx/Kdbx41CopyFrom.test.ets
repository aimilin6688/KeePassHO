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
const TEST_PASSWORD: string = 'Kdbx41-CopyFrom-123';

/** 构造测试凭证 */
function makeCredentials(): KdbxCredentials {
  return new KdbxCredentials(ProtectedValue.fromString(TEST_PASSWORD));
}

/** 读取 customData 中某键的值（避免非空断言） */
function customDataValue(
  customData: Map<string, KdbxCustomDataItem> | undefined,
  key: string
): string | undefined {
  const item = customData ? customData.get(key) : undefined;
  return item ? item.value : undefined;
}

/**
 * P2-4 M1：copyFrom 4.1 字段补全测试。
 *
 * 背景：copyFrom 同时服务于 merge 内容胜出路径（Entry/Group.merge）与
 * pushHistory 历史快照，缺失字段会导致合并/回滚丢失 4.1 元数据：
 * - Entry：customData、qualityCheck
 * - Group：tags、customData
 *
 * 设计约束（docs/entry-color-prevparent-tan-design.md §6）：
 * previousParentGroup 刻意不进 copyFrom —— 位置元数据由 merge 专用逻辑
 * 处理（KeePass MergeInLocationChanged 语义），内容回滚不得改变当前位置。
 */
export default function Kdbx41CopyFromTest() {
  describe('Kdbx41CopyFromTest', () => {
    beforeAll(() => {
      KdbxModeTestHelper.initContext();
    });

    it('entry copyFrom copies customData and qualityCheck as independent clone', 0, () => {
      const db = Kdbx.create(makeCredentials(), 'CopyFrom41Db');
      const group = db.getDefaultGroup();
      const source = db.createEntry(group);

      const customData = new Map<string, KdbxCustomDataItem>();
      customData.set('k1', { value: 'v1', lastModified: new Date(2026, 0, 1) });
      source.customData = customData;
      source.qualityCheck = false;
      source.previousParentGroup = KdbxUuid.random();
      source.tags = ['t1'];
      source.times.lastModTime = new Date(2026, 0, 2);

      const target = new KdbxEntry();
      target.copyFrom(source);

      // customData / qualityCheck 被复制
      expect(target.qualityCheck).assertEqual(false);
      expect(customDataValue(target.customData, 'k1')).assertEqual('v1');
      // 克隆独立性：修改源不影响副本
      if (source.customData) {
        source.customData.set('k1', { value: 'changed' });
      }
      expect(customDataValue(target.customData, 'k1')).assertEqual('v1');
      source.qualityCheck = true;
      expect(target.qualityCheck).assertEqual(false);

      // previousParentGroup 刻意不复制（位置元数据由 merge 专用逻辑处理）
      expect(target.previousParentGroup === undefined).assertTrue();
    });

    it('group copyFrom copies tags and customData as independent clones', 0, () => {
      const db = Kdbx.create(makeCredentials(), 'CopyFrom41Db');
      const root = db.getDefaultGroup();
      const source = db.createGroup(root, 'SourceGroup');

      source.tags = ['g-tag1', 'g-tag2'];
      const customData = new Map<string, KdbxCustomDataItem>();
      customData.set('cd-key', { value: 'cd-val', lastModified: new Date(2026, 0, 3) });
      source.customData = customData;
      source.previousParentGroup = KdbxUuid.random();
      source.fgColor = '#FF0000';
      source.bgColor = '#00FF00';

      const target = new KdbxGroup();
      target.copyFrom(source);

      // tags 被复制且为独立副本
      expect(target.tags.length).assertEqual(2);
      expect(target.tags[0]).assertEqual('g-tag1');
      expect(target.tags[1]).assertEqual('g-tag2');
      source.tags.push('mutated');
      expect(target.tags.length).assertEqual(2);

      // customData 被复制且为独立副本
      expect(customDataValue(target.customData, 'cd-key')).assertEqual('cd-val');
      if (source.customData) {
        source.customData.delete('cd-key');
      }
      expect(customDataValue(target.customData, 'cd-key')).assertEqual('cd-val');

      // 颜色（模型一等字段）同步
      expect(target.fgColor).assertEqual('#FF0000');
      expect(target.bgColor).assertEqual('#00FF00');

      // previousParentGroup 刻意不复制
      expect(target.previousParentGroup === undefined).assertTrue();
    });
  });
}
