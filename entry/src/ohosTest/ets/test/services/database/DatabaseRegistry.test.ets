import { beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { DatabaseRegistry, OpenDatabaseRecord, PutDatabaseOptions } from '../../../../../main/ets/services/database/DatabaseRegistry';
import { AuthType, DbFileParam } from '../../../../../main/ets/services/TypeDefined';

/**
 * 构造测试用库会话参数（真实 Kdbx 实例可复用——注册表只关心参数对象身份，不校验库内容）
 */
function makeRegistryParam(filePath: string, storageType: string, database: Kdbx): DbFileParam {
  return {
    password: 'p',
    authType: AuthType.PASSWORD,
    filePath: filePath,
    fileName: 'x.kdbx',
    database: database,
    storageType: storageType,
    storageConfig: {},
    modifiedTime: 0
  } as DbFileParam;
}

/**
 * DatabaseRegistry（M2 多库注册表）单元测试。
 *
 * 覆盖：
 * - iocKey 构造（buildIocKey / iocKeyOf）
 * - put 登记语义：默认切换当前库 / makeCurrent=false 不切换 / 空表兜底 / 同键替换保 isChild
 * - setCurrent 切换与未知键拒绝
 * - remove：删除当前库自动切换首个剩余库（插入序）/ 删空回到空态 / 未知键返回 undefined
 * - all / size / isChild
 * - attempted 尝试标记（AutoOpen 触发循环防护，与记录独立）
 * - clear 全量复位
 */
export default function DatabaseRegistryTest() {
  describe('DatabaseRegistry', () => {
    let registry: DatabaseRegistry;
    let database: Kdbx;

    beforeAll(() => {
      database = Kdbx.create(new KdbxCredentials(ProtectedValue.fromString('registry-test')), 'RegistryTestDb');
    });

    beforeEach(() => {
      registry = new DatabaseRegistry();
    });

    // ==================== iocKey ====================

    it('buildIocKey joins storageType and filePath with ::', 0, () => {
      expect(DatabaseRegistry.buildIocKey('WEBDAV', '/a/b.kdbx')).assertEqual('WEBDAV::/a/b.kdbx');
      expect(DatabaseRegistry.buildIocKey('LOCAL', '/c.kdbx')).assertEqual('LOCAL::/c.kdbx');
    });

    it('buildIocKey tolerates undefined components', 0, () => {
      expect(DatabaseRegistry.buildIocKey(undefined, undefined)).assertEqual('::');
      expect(DatabaseRegistry.buildIocKey('LOCAL', undefined)).assertEqual('LOCAL::');
    });

    it('iocKeyOf builds key from dbFileParam', 0, () => {
      const param = makeRegistryParam('/a.kdbx', 'WEBDAV', database);
      expect(DatabaseRegistry.iocKeyOf(param)).assertEqual('WEBDAV::/a.kdbx');
    });

    // ==================== put / get / current ====================

    it('put registers param and makes it current by default', 0, () => {
      const param = makeRegistryParam('/main.kdbx', 'LOCAL', database);
      const record = registry.put(param);
      expect(record.iocKey).assertEqual('LOCAL::/main.kdbx');
      expect(record.dbFileParam === param).assertTrue();
      expect(record.isChild).assertFalse();
      expect(registry.getCurrentKey()).assertEqual('LOCAL::/main.kdbx');
      expect(registry.getCurrent() === param).assertTrue();
      expect(registry.get('LOCAL::/main.kdbx') === param).assertTrue();
      expect(registry.has('LOCAL::/main.kdbx')).assertTrue();
      expect(registry.size()).assertEqual(1);
    });

    it('put makeCurrent=false does not switch away from existing current', 0, () => {
      const main = makeRegistryParam('/main.kdbx', 'LOCAL', database);
      const child = makeRegistryParam('/child.kdbx', 'LOCAL', database);
      registry.put(main);
      registry.put(child, new PutDatabaseOptions(false, true));
      expect(registry.getCurrent() === main).assertTrue();
      expect(registry.get('LOCAL::/child.kdbx') === child).assertTrue();
      expect(registry.isChild('LOCAL::/child.kdbx')).assertTrue();
      expect(registry.isChild('LOCAL::/main.kdbx')).assertFalse();
    });

    it('put makeCurrent=false falls back to current when registry is empty', 0, () => {
      const child = makeRegistryParam('/child.kdbx', 'LOCAL', database);
      registry.put(child, new PutDatabaseOptions(false, true));
      // 空表兜底：首个入库库自动成为当前库（否则 getCurrent 永远为空）
      expect(registry.getCurrent() === child).assertTrue();
    });

    it('put same key replaces param and keeps isChild flag', 0, () => {
      const child = makeRegistryParam('/child.kdbx', 'LOCAL', database);
      registry.put(child, new PutDatabaseOptions(false, true));
      const childUpdated = makeRegistryParam('/child.kdbx', 'LOCAL', database);
      const record = registry.put(childUpdated, new PutDatabaseOptions(true, false));
      // 同键替换：会话参数对象更新，子库身份保留（options.isChild=false 不得覆盖既有标记）
      expect(record.dbFileParam === childUpdated).assertTrue();
      expect(record.isChild).assertTrue();
      expect(registry.get('LOCAL::/child.kdbx') === childUpdated).assertTrue();
      expect(registry.size()).assertEqual(1);
    });

    it('put different storageType same path registers separate databases', 0, () => {
      const local = makeRegistryParam('/same.kdbx', 'LOCAL', database);
      const webdav = makeRegistryParam('/same.kdbx', 'WEBDAV', database);
      registry.put(local);
      registry.put(webdav);
      expect(registry.size()).assertEqual(2);
      expect(registry.getCurrent() === webdav).assertTrue();
    });

    // ==================== setCurrent / remove ====================

    it('setCurrent switches current and rejects unknown key', 0, () => {
      const a = makeRegistryParam('/a.kdbx', 'LOCAL', database);
      const b = makeRegistryParam('/b.kdbx', 'LOCAL', database);
      registry.put(a);
      registry.put(b);
      expect(registry.setCurrent('LOCAL::/a.kdbx')).assertTrue();
      expect(registry.getCurrent() === a).assertTrue();
      expect(registry.setCurrent('LOCAL::/missing.kdbx')).assertFalse();
      expect(registry.getCurrent() === a).assertTrue();
    });

    it('remove current auto-switches to first remaining (insertion order)', 0, () => {
      const a = makeRegistryParam('/a.kdbx', 'LOCAL', database);
      const b = makeRegistryParam('/b.kdbx', 'LOCAL', database);
      const c = makeRegistryParam('/c.kdbx', 'LOCAL', database);
      registry.put(a);
      registry.put(b);
      registry.put(c);
      expect(registry.getCurrent() === c).assertTrue();
      const removed = registry.remove('LOCAL::/c.kdbx');
      expect(removed === c).assertTrue();
      // 删除当前库：自动切换到首个剩余库（插入序）
      expect(registry.getCurrent() === a).assertTrue();
      expect(registry.size()).assertEqual(2);
    });

    it('remove last database empties registry', 0, () => {
      const a = makeRegistryParam('/a.kdbx', 'LOCAL', database);
      registry.put(a);
      const removed = registry.remove('LOCAL::/a.kdbx');
      expect(removed === a).assertTrue();
      expect(registry.getCurrentKey()).assertNull();
      expect(registry.getCurrent()).assertUndefined();
      expect(registry.size()).assertEqual(0);
    });

    it('remove unknown key returns undefined', 0, () => {
      expect(registry.remove('LOCAL::/none.kdbx')).assertUndefined();
    });

    it('all returns records in insertion order', 0, () => {
      const a = makeRegistryParam('/a.kdbx', 'LOCAL', database);
      const b = makeRegistryParam('/b.kdbx', 'LOCAL', database);
      registry.put(a);
      registry.put(b);
      const records: OpenDatabaseRecord[] = registry.all();
      expect(records.length).assertEqual(2);
      expect(records[0].dbFileParam === a).assertTrue();
      expect(records[1].dbFileParam === b).assertTrue();
    });

    // ==================== attempted（AutoOpen 触发循环防护） ====================

    it('markAttempted / wasAttempted track failed attempts independently of records', 0, () => {
      const key = 'WEBDAV::/child.kdbx';
      // 未登记记录的失败尝试也必须可标记（对齐 kp2a _openAttempts：防止失败后反复重试）
      expect(registry.wasAttempted(key)).assertFalse();
      expect(registry.has(key)).assertFalse();
      registry.markAttempted(key);
      expect(registry.wasAttempted(key)).assertTrue();
      expect(registry.has(key)).assertFalse();
      // 清理尝试标记不影响已登记记录
      registry.put(makeRegistryParam('/child.kdbx', 'WEBDAV', database));
      registry.clearAttempted();
      expect(registry.wasAttempted(key)).assertFalse();
      expect(registry.has(key)).assertTrue();
    });

    it('clear resets records, attempted and currentKey', 0, () => {
      registry.put(makeRegistryParam('/a.kdbx', 'LOCAL', database));
      registry.markAttempted('LOCAL::/x.kdbx');
      registry.clear();
      expect(registry.size()).assertEqual(0);
      expect(registry.getCurrentKey()).assertNull();
      expect(registry.wasAttempted('LOCAL::/x.kdbx')).assertFalse();
    });
  });
}
