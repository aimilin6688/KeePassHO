import { beforeAll, describe, expect, it } from '@ohos/hypium';
import {
  Kdbx,
  KdbxCredentials,
  KdbxEntry,
  KdbxGroup,
  ProtectedValue
} from 'kdbxweb';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

/** 测试主密码 */
const TEST_PASSWORD: string = 'Tan-Test-123';

/** 构造空测试库并返回根分组 */
function makeRootGroup(): [Kdbx, KdbxGroup] {
  const db = Kdbx.create(
    new KdbxCredentials(ProtectedValue.fromString(TEST_PASSWORD)),
    'TanDb'
  );
  return [db, db.getDefaultGroup()];
}

/** 构造 TAN 条目（Title 精确 '<TAN>'） */
function makeTanEntry(group: KdbxGroup, tanIndex: string, password: string): KdbxEntry {
  const entry = new KdbxEntry();
  entry.fields.set(KdbxUtils.FIELD_TITLE, KdbxUtils.TAN_TITLE);
  entry.fields.set(KdbxUtils.FIELD_USERNAME, tanIndex);
  entry.fields.set(KdbxUtils.FIELD_PASSWORD, password);
  group.entries.push(entry);
  return entry;
}

/**
 * P2-4 M3：TAN 支持（设计文档 §6.3，测试方案 §8.1 用例 6/7/8/10）。
 *
 * 覆盖：
 * - isTanEntry：对齐 KeePass PwDefs.IsTanEntry（Title 精确等于 '<TAN>'，大小写敏感）
 * - addTanEntries：对齐 TanWizardForm.AddTan（空片段跳过、序号递增、字段赋值）
 * - expireTanEntryOnUse：对齐 EntryUtil.ExpireTanEntryIfOption
 *   （开关关闭不变更；TAN 过期（expires=true、expiryTime≈now、历史+1）；非 TAN 不变）
 * - parseEntryColor：#RRGGBB 校验与归一化（非法/空 → undefined）
 */
export default function KdbxTanTest() {
  describe('KdbxTanTest', () => {
    beforeAll(() => {
      KdbxModeTestHelper.initContext();
    });

    it('isTanEntry matches exact <TAN> title case-sensitively', 0, () => {
      const tuple = makeRootGroup();
      const root = tuple[1];
      // 精确匹配
      const tanEntry = makeTanEntry(root, '1', 'TANCODE1');
      expect(KdbxUtils.isTanEntry(tanEntry)).assertTrue();
      // 大小写敏感 / 无尖括号 / 普通标题
      const lowerEntry = new KdbxEntry();
      lowerEntry.fields.set(KdbxUtils.FIELD_TITLE, '<tan>');
      expect(KdbxUtils.isTanEntry(lowerEntry)).assertFalse();
      const plainEntry = new KdbxEntry();
      plainEntry.fields.set(KdbxUtils.FIELD_TITLE, 'TAN');
      expect(KdbxUtils.isTanEntry(plainEntry)).assertFalse();
      const normalEntry = new KdbxEntry();
      normalEntry.fields.set(KdbxUtils.FIELD_TITLE, '普通条目');
      expect(KdbxUtils.isTanEntry(normalEntry)).assertFalse();
      // 空标题
      const emptyEntry = new KdbxEntry();
      emptyEntry.fields.set(KdbxUtils.FIELD_TITLE, '');
      expect(KdbxUtils.isTanEntry(emptyEntry)).assertFalse();
    });

    it('getTanIndex reads UserName field', 0, () => {
      const tuple = makeRootGroup();
      const root = tuple[1];
      const tanEntry = makeTanEntry(root, '42', 'TANCODE');
      expect(KdbxUtils.getTanIndex(tanEntry)).assertEqual('42');
    });

    it('addTanEntries creates entries with title/index/password and skips empties', 0, () => {
      const tuple = makeRootGroup();
      const root = tuple[1];
      const before = root.entries.length;
      const created = KdbxUtils.addTanEntries(root, ['A1', '', 'B2'], 5);
      expect(created).assertEqual(2);
      expect(root.entries.length).assertEqual(before + 2);
      const first = root.entries[before];
      expect(KdbxUtils.getFieldValueString(first.fields, KdbxUtils.FIELD_TITLE))
        .assertEqual(KdbxUtils.TAN_TITLE);
      expect(KdbxUtils.getFieldValueString(first.fields, KdbxUtils.FIELD_USERNAME))
        .assertEqual('5');
      expect(KdbxUtils.getFieldValueString(first.fields, KdbxUtils.FIELD_PASSWORD))
        .assertEqual('A1');
      const second = root.entries[before + 1];
      expect(KdbxUtils.getFieldValueString(second.fields, KdbxUtils.FIELD_USERNAME))
        .assertEqual('6');
      expect(KdbxUtils.getFieldValueString(second.fields, KdbxUtils.FIELD_PASSWORD))
        .assertEqual('B2');
      // 起始序号 0 时首条序号为 '1'（index>0 才写序号，0 视为无序号）
      const createdZero = KdbxUtils.addTanEntries(root, ['C3'], 0);
      expect(createdZero).assertEqual(1);
      const third = root.entries[before + 2];
      expect(KdbxUtils.getFieldValueString(third.fields, KdbxUtils.FIELD_USERNAME))
        .assertEqual('');
    });

    it('expireTanEntryOnUse expires TAN entry with history pushed', 0, () => {
      const tuple = makeRootGroup();
      const root = tuple[1];
      const tanEntry = makeTanEntry(root, '7', 'TANCODE7');
      const historyBefore = tanEntry.history.length;
      const before = Date.now();
      // 开关开启 + TAN → 过期
      const changed = KdbxUtils.expireTanEntryOnUse(tanEntry, true);
      expect(changed).assertTrue();
      expect(tanEntry.times.expires === true).assertTrue();
      expect(tanEntry.times.expiryTime !== undefined).assertTrue();
      const expiryDelta = (tanEntry.times.expiryTime as Date).getTime() - before;
      expect(expiryDelta >= 0 && expiryDelta < 60000).assertTrue();
      expect(tanEntry.history.length).assertEqual(historyBefore + 1);
      // 变更前推入历史：历史快照仍是未过期状态
      expect(tanEntry.history[historyBefore].times.expires === true).assertFalse();
      // 幂次保护：已过期的 TAN 再次调用仍会重新过期（保持 KeePass 行为，时间刷新）
      const changedAgain = KdbxUtils.expireTanEntryOnUse(tanEntry, true);
      expect(changedAgain).assertTrue();
    });

    it('expireTanEntryOnUse keeps entry unchanged when disabled or not TAN', 0, () => {
      const tuple = makeRootGroup();
      const root = tuple[1];
      // 开关关闭 → 不变更
      const tanEntry = makeTanEntry(root, '1', 'TANCODE');
      expect(KdbxUtils.expireTanEntryOnUse(tanEntry, false)).assertFalse();
      expect(tanEntry.times.expires === true).assertFalse();
      expect(tanEntry.history.length).assertEqual(0);
      // 非 TAN → 不变更
      const normalEntry = new KdbxEntry();
      normalEntry.fields.set(KdbxUtils.FIELD_TITLE, '普通条目');
      normalEntry.fields.set(KdbxUtils.FIELD_PASSWORD, 'pwd');
      root.entries.push(normalEntry);
      expect(KdbxUtils.expireTanEntryOnUse(normalEntry, true)).assertFalse();
      expect(normalEntry.times.expires === true).assertFalse();
      expect(normalEntry.history.length).assertEqual(0);
    });

    it('parseEntryColor validates and normalizes #RRGGBB colors', 0, () => {
      expect(KdbxUtils.parseEntryColor('#AABBCC')).assertEqual('#AABBCC');
      // 小写归一化为大写（KeePass 写出格式）
      expect(KdbxUtils.parseEntryColor('#a1b2c3')).assertEqual('#A1B2C3');
      // 3 位 hex / 颜色名 / 空 / undefined → undefined（继承默认色）
      expect(KdbxUtils.parseEntryColor('#abc')).assertUndefined();
      expect(KdbxUtils.parseEntryColor('red')).assertUndefined();
      expect(KdbxUtils.parseEntryColor('')).assertUndefined();
      expect(KdbxUtils.parseEntryColor(undefined)).assertUndefined();
      // 7 位但非 hex → undefined
      expect(KdbxUtils.parseEntryColor('#GGHHII')).assertUndefined();
      expect(KdbxUtils.parseEntryColor('AABBCC')).assertUndefined();
    });
  });
}
