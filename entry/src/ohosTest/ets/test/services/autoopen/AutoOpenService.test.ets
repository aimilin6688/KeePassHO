import { describe, expect, it } from '@ohos/hypium';
import { Kdbx, KdbxGroup, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { AutoOpenService } from '../../../../../main/ets/services/autoopen/AutoOpenService';
import { AutoOpenItem } from '../../../../../main/ets/services/autoopen/AutoOpenItem';
import { TestUtils } from '../../importExport/TestUtils';

/** 测试库 + AutoOpen 组持有者（避免元组解构） */
class AutoOpenTestDb {
  public readonly db: Kdbx;
  public readonly autoOpen: KdbxGroup;

  constructor(db: Kdbx, autoOpen: KdbxGroup) {
    this.db = db;
    this.autoOpen = autoOpen;
  }
}

/** 创建带 AutoOpen 组的测试库 */
async function createDbWithAutoOpen(groupName: string = 'AutoOpen'): Promise<AutoOpenTestDb> {
  const db = await TestUtils.createTestDatabase('AutoOpen Scan Test');
  const root = db.getDefaultGroup();
  const autoOpen = TestUtils.createTestGroup(db, root, groupName);
  return new AutoOpenTestDb(db, autoOpen);
}

/**
 * AutoOpen 组扫描与条目解析服务单元测试
 * 兼容语义对齐 KeePass 桌面 / KeeAutoExec / keepass2android：
 * 组名大小写不敏感、URL 为空忽略、过期默认禁用、Enabled/Visible/Priority 覆盖
 */
export default function AutoOpenServiceTest() {
  describe('AutoOpenService', () => {
    const IOC_KEY = 'ioc://parent';

    it('scan: returns empty when no AutoOpen group exists', 0, async () => {
      const db = await TestUtils.createTestDatabase('No AutoOpen');
      TestUtils.createTestEntry(db, db.getDefaultGroup(), 'normal', 'u', 'p', 'child.kdbx');
      expect(AutoOpenService.scan(db, IOC_KEY).length).assertEqual(0);
    });

    it('scan: collects entries from AutoOpen group (case-insensitive)', 0, async () => {
      const holder = await createDbWithAutoOpen('autoOPEN');
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'child', 'u', 'p', 'child.kdbx');
      expect(AutoOpenService.scan(holder.db, IOC_KEY).length).assertEqual(1);
    });

    it('scan: skips entries without URL', 0, async () => {
      const holder = await createDbWithAutoOpen();
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'with-url', 'u', 'p', 'child.kdbx');
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'no-url', 'u', 'p');
      expect(AutoOpenService.scan(holder.db, IOC_KEY).length).assertEqual(1);
    });

    it('scan: collects entries from nested subgroups of AutoOpen group', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const sub = TestUtils.createTestGroup(holder.db, holder.autoOpen, 'sub');
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'direct', 'u', 'p', 'a.kdbx');
      TestUtils.createTestEntry(holder.db, sub, 'nested', 'u', 'p', 'b.kdbx');
      expect(AutoOpenService.scan(holder.db, IOC_KEY).length).assertEqual(2);
    });

    it('scan: finds AutoOpen group nested under a regular group', 0, async () => {
      const db = await TestUtils.createTestDatabase('Nested AutoOpen');
      const regular = TestUtils.createTestGroup(db, db.getDefaultGroup(), 'regular');
      const autoOpen = TestUtils.createTestGroup(db, regular, 'AutoOpen');
      TestUtils.createTestEntry(db, autoOpen, 'child', 'u', 'p', 'child.kdbx');
      expect(AutoOpenService.scan(db, IOC_KEY).length).assertEqual(1);
    });

    it('scan: matches when root group itself is named AutoOpen', 0, async () => {
      const db = await TestUtils.createTestDatabase('Root AutoOpen Test');
      db.getDefaultGroup().name = 'AutoOpen';
      TestUtils.createTestEntry(db, db.getDefaultGroup(), 'child', 'u', 'p', 'child.kdbx');
      expect(AutoOpenService.scan(db, IOC_KEY).length).assertEqual(1);
    });

    it('scan: maps standard fields to item', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const entry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'Title X', 'key.kdbx', 'child-pass', '/path/child.kdbx');
      entry.icon = 42;
      entry.customIcon = new KdbxUuid();
      const items = AutoOpenService.scan(holder.db, IOC_KEY);
      expect(items.length).assertEqual(1);
      const item = items[0];
      expect(item.title).assertEqual('Title X');
      expect(item.url).assertEqual('/path/child.kdbx');
      expect(item.keyFilePath).assertEqual('key.kdbx');
      expect(item.passwordText).assertEqual('child-pass');
      expect(item.sourceIocKey).assertEqual(IOC_KEY);
      expect(item.entryUuid).assertEqual(entry.uuid.id);
      expect(item.parentGroupId).assertEqual(holder.autoOpen.uuid.id);
      expect(item.iconId).assertEqual(42);
      expect(item.customIconId).assertEqual(entry.customIcon!.id);
    });

    it('scan: password read from ProtectedValue', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const entry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 't', undefined, undefined, 'child.kdbx');
      entry.fields.set('Password', ProtectedValue.fromString('secret-pass'));
      const items = AutoOpenService.scan(holder.db, IOC_KEY);
      expect(items[0].passwordText).assertEqual('secret-pass');
    });

    it('scan: expired entry disabled by default', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const entry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'expired', 'u', 'p', 'child.kdbx');
      entry.times.expires = true;
      entry.times.expiryTime = new Date(Date.now() - 86_400_000);
      const items = AutoOpenService.scan(holder.db, IOC_KEY);
      expect(items[0].enabled).assertFalse();
    });

    it('scan: Enabled=True overrides expiry', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const entry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'expired-enabled', 'u', 'p', 'child.kdbx');
      entry.times.expires = true;
      entry.times.expiryTime = new Date(Date.now() - 86_400_000);
      entry.fields.set('Enabled', 'True');
      const items = AutoOpenService.scan(holder.db, IOC_KEY);
      expect(items[0].enabled).assertTrue();
    });

    it('scan: Enabled=False disables active entry', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const entry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'active-disabled', 'u', 'p', 'child.kdbx');
      entry.fields.set('Enabled', 'False');
      const items = AutoOpenService.scan(holder.db, IOC_KEY);
      expect(items[0].enabled).assertFalse();
    });

    it('scan: default enabled/visible, Visible=False overrides', 0, async () => {
      const holder = await createDbWithAutoOpen();
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'v1', 'u', 'p', 'a.kdbx');
      const hiddenEntry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'v2', 'u', 'p', 'b.kdbx');
      hiddenEntry.fields.set('Visible', 'False');
      const items = AutoOpenService.scan(holder.db, IOC_KEY);
      const byTitle = new Map<string, AutoOpenItem>();
      items.forEach((item: AutoOpenItem) => {
        byTitle.set(item.title, item);
      });
      expect(byTitle.get('v1')!.enabled).assertTrue();
      expect(byTitle.get('v1')!.visible).assertTrue();
      expect(byTitle.get('v2')!.visible).assertFalse();
    });

    it('scan: IfDevice raw passthrough', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const entry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'if-device', 'u', 'p', 'child.kdbx');
      entry.fields.set('IfDevice', 'HUAWEI P60 (id1)');
      const items = AutoOpenService.scan(holder.db, IOC_KEY);
      expect(items[0].ifDeviceRaw).assertEqual('HUAWEI P60 (id1)');
    });

    it('scan: SkipIfNotExists new and legacy field names', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const e1 = TestUtils.createTestEntry(holder.db, holder.autoOpen, 's1', 'u', 'p', 'a.kdbx');
      e1.fields.set('SkipIfNotExists', 'True');
      const e2 = TestUtils.createTestEntry(holder.db, holder.autoOpen, 's2', 'u', 'p', 'b.kdbx');
      e2.fields.set('Skip if not exists', 'True');
      const items = AutoOpenService.scan(holder.db, IOC_KEY);
      const byTitle = new Map<string, AutoOpenItem>();
      items.forEach((item: AutoOpenItem) => {
        byTitle.set(item.title, item);
      });
      expect(byTitle.get('s1')!.skipIfNotExists).assertTrue();
      expect(byTitle.get('s2')!.skipIfNotExists).assertTrue();
    });

    it('scan: SkipIfKeyFileNotExists mapping', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const e1 = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'k1', 'u', 'p', 'a.kdbx');
      e1.fields.set('SkipIfKeyFileNotExists', 'True');
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'k2', 'u', 'p', 'b.kdbx');
      const items = AutoOpenService.scan(holder.db, IOC_KEY);
      const byTitle = new Map<string, AutoOpenItem>();
      items.forEach((item: AutoOpenItem) => {
        byTitle.set(item.title, item);
      });
      expect(byTitle.get('k1')!.skipIfKeyFileNotExists).assertTrue();
      expect(byTitle.get('k2')!.skipIfKeyFileNotExists).assertFalse();
    });

    it('scan: Priority sorts items with scan-order stability', 0, async () => {
      const holder = await createDbWithAutoOpen();
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'A', 'u', 'p', 'a.kdbx'); // 默认优先级 0
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'B', 'u', 'p', 'b.kdbx'); // 默认优先级 1
      const c = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'C', 'u', 'p', 'c.kdbx');
      c.fields.set('Priority', '10');
      const d = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'D', 'u', 'p', 'd.kdbx');
      d.fields.set('Priority', '-5');
      const e = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'E', 'u', 'p', 'e.kdbx');
      e.fields.set('Priority', ' 0 '); // 等于 A 的默认优先级，稳定排序应保持 A 在前
      const titles: string[] = [];
      AutoOpenService.scan(holder.db, IOC_KEY).forEach((item: AutoOpenItem) => {
        titles.push(item.title);
      });
      // 优先级：D(-5) < A(0) < E(0) < B(1) < C(10)，同优先级按扫描顺序
      expect(titles.join(',')).assertEqual('D,A,E,B,C');
    });

    it('scan: invalid Priority falls back to scan order', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const a = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'A', 'u', 'p', 'a.kdbx');
      a.fields.set('Priority', 'abc');
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'B', 'u', 'p', 'b.kdbx');
      const items = AutoOpenService.scan(holder.db, IOC_KEY);
      expect(items[0].title).assertEqual('A');
      expect(items[0].priority).assertEqual(0);
      expect(items[1].title).assertEqual('B');
    });

    it('findOrCreateAutoOpenGroup: finds existing group case-insensitively', 0, async () => {
      const holder = await createDbWithAutoOpen('AUTOOPEN');
      const found = AutoOpenService.findOrCreateAutoOpenGroup(holder.db, false);
      expect(found !== undefined).assertTrue();
      expect(found!.uuid.id).assertEqual(holder.autoOpen.uuid.id);
    });

    it('findOrCreateAutoOpenGroup: returns undefined when missing and create=false', 0, async () => {
      const db = await TestUtils.createTestDatabase('No AutoOpen');
      expect(AutoOpenService.findOrCreateAutoOpenGroup(db, false)).assertUndefined();
    });

    it('findOrCreateAutoOpenGroup: creates group under root when missing', 0, async () => {
      const db = await TestUtils.createTestDatabase('Create AutoOpen');
      const root = db.getDefaultGroup();
      const created = AutoOpenService.findOrCreateAutoOpenGroup(db, true);
      expect(created !== undefined).assertTrue();
      expect(created!.name).assertEqual('AutoOpen');
      expect(created!.parentGroup!.uuid.id).assertEqual(root.uuid.id);
      // 再次查找命中已创建的组
      const again = AutoOpenService.findOrCreateAutoOpenGroup(db, false);
      expect(again!.uuid.id).assertEqual(created!.uuid.id);
    });

    it('collectAutoOpenEntries: returns raw KdbxEntry list', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const entry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'raw', 'u', 'p', 'child.kdbx');
      const entries = AutoOpenService.collectAutoOpenEntries(holder.db);
      expect(entries.length).assertEqual(1);
      expect(entries[0].uuid.id).assertEqual(entry.uuid.id);
    });

    // ---------------- hasUnconfiguredForDevice（M5 提示条判定） ----------------

    it('hasUnconfiguredForDevice: false when no AutoOpen group exists', 0, async () => {
      const db = await TestUtils.createTestDatabase('No AutoOpen');
      expect(AutoOpenService.hasUnconfiguredForDevice(db, IOC_KEY, 'DEV_A')).assertFalse();
    });

    it('hasUnconfiguredForDevice: true when entry has no IfDevice field', 0, async () => {
      const holder = await createDbWithAutoOpen();
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'child', 'u', 'p', 'child.kdbx');
      // 无 IfDevice 字段 = 未显式配置本设备
      expect(AutoOpenService.hasUnconfiguredForDevice(holder.db, IOC_KEY, 'DEV_A')).assertTrue();
    });

    it('hasUnconfiguredForDevice: false when device explicitly whitelisted', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const entry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'child', 'u', 'p', 'child.kdbx');
      entry.fields.set('IfDevice', 'DEV_A');
      expect(AutoOpenService.hasUnconfiguredForDevice(holder.db, IOC_KEY, 'DEV_A')).assertFalse();
    });

    it('hasUnconfiguredForDevice: false when device explicitly excluded', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const entry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'child', 'u', 'p', 'child.kdbx');
      entry.fields.set('IfDevice', '!DEV_A');
      expect(AutoOpenService.hasUnconfiguredForDevice(holder.db, IOC_KEY, 'DEV_A')).assertFalse();
    });

    it('hasUnconfiguredForDevice: true when whitelist names only another device', 0, async () => {
      const holder = await createDbWithAutoOpen();
      const entry = TestUtils.createTestEntry(holder.db, holder.autoOpen, 'child', 'u', 'p', 'child.kdbx');
      // 白名单仅 DEV_B：DEV_A 未显式命中 → 提示
      entry.fields.set('IfDevice', 'DEV_B');
      expect(AutoOpenService.hasUnconfiguredForDevice(holder.db, IOC_KEY, 'DEV_A')).assertTrue();
    });

    it('hasUnconfiguredForDevice: skips entries without URL', 0, async () => {
      const holder = await createDbWithAutoOpen();
      TestUtils.createTestEntry(holder.db, holder.autoOpen, 'no-url', 'u', 'p');
      expect(AutoOpenService.hasUnconfiguredForDevice(holder.db, IOC_KEY, 'DEV_A')).assertFalse();
    });
  });
}
