import { beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { emitter } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { Kdbx, KdbxCredentials, KdbxEntry, KdbxGroup, ProtectedValue } from 'kdbxweb';

import { AutoOpenCoordinator, AutoOpenFailure } from '../../../../../main/ets/services/autoopen/AutoOpenCoordinator';
import { AutoOpenItem } from '../../../../../main/ets/services/autoopen/AutoOpenItem';
import { AutoOpenService } from '../../../../../main/ets/services/autoopen/AutoOpenService';
import { DeviceIdentity } from '../../../../../main/ets/services/autoopen/DeviceIdentity';
import { AUTO_OPEN_GROUP_NAME, AutoOpenFieldName } from '../../../../../main/ets/services/autoopen/AutoOpenConstants';
import { DatabaseRegistry } from '../../../../../main/ets/services/kdbx/DatabaseRegistry';
import { FileService } from '../../../../../main/ets/services/FileService';
import { EventBus } from '../../../../../main/ets/services/EventBus';
import { DbFileParam, AuthType } from '../../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../../main/ets/storage';
import { KdbxFileManager } from '../../../../../main/ets/services/kdbx/KdbxFileManager';
import { KdbxModeTestHelper } from '../../workers/KdbxModeTestHelper';

const PARENT_PASSWORD = 'Coord-Parent-Pass-1';
const CHILD_PASSWORD = 'Coord-Child-Pass-1';
const EVENT_TIMEOUT: number = 30000;

/**
 * 创建真实加密数据库（独立密码）
 */
function createKdbx(name: string, password: string): Kdbx {
  return Kdbx.create(new KdbxCredentials(ProtectedValue.fromString(password)), name);
}

/**
 * 构造已登记到注册表的父库会话参数（真实文件 + 真实加密库）
 */
async function writeAndRegisterParent(path: string, database: Kdbx): Promise<string> {
  const fileManager: KdbxFileManager = new KdbxFileManager(StorageType.LOCAL);
  await fileManager.write(path, await database.save());
  const parentParam: DbFileParam = {
    filePath: path,
    fileName: path.substring(path.lastIndexOf('/') + 1),
    password: PARENT_PASSWORD,
    database: database,
    authType: AuthType.PASSWORD,
    storageType: StorageType.LOCAL,
    storageConfig: {},
    modifiedTime: 0,
    version: null,
    contentHash: null
  } as DbFileParam;
  FileService.setDbFileParam(parentParam);
  return DatabaseRegistry.buildIocKey(StorageType.LOCAL, path);
}

/**
 * 在父库根组下创建 AutoOpen 组并添加子库条目（真实字段约定）
 */
function addChildEntry(parent: Kdbx, title: string, url: string, password: string): KdbxEntry {
  let autoOpenGroup: KdbxGroup | undefined = undefined;
  for (const group of parent.getDefaultGroup().groups) {
    if ((group.name ?? '').toLowerCase() === AUTO_OPEN_GROUP_NAME.toLowerCase()) {
      autoOpenGroup = group;
      break;
    }
  }
  if (autoOpenGroup === undefined) {
    autoOpenGroup = parent.createGroup(parent.getDefaultGroup(), AUTO_OPEN_GROUP_NAME);
  }
  const entry: KdbxEntry = parent.createEntry(autoOpenGroup);
  entry.fields.set('Title', title);
  entry.fields.set('URL', url);
  entry.fields.set('Password', password);
  return entry;
}

/**
 * 等待 AutoOpenCoordinator 指定事件且数据匹配（带超时防挂死）
 */
function waitCoordinatorEvent(event: string, expected: string, timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const cb: Callback<emitter.EventData> = (data: emitter.EventData) => {
      const raw: Object | undefined = data?.data;
      if (typeof raw === 'string' && raw === expected) {
        EventBus.off(event, cb);
        clearInterval(timer);
        resolve();
      }
    };
    const timer = setInterval(() => {
      clearInterval(timer);
      EventBus.off(event, cb);
      reject(new Error(`wait event ${event} timeout`));
    }, timeoutMs);
    EventBus.on(event, cb);
  });
}

/**
 * 等待子库打开失败事件且 iocKey 匹配（带超时防挂死）。
 * 注意：emitter 会序列化事件数据，类实例载荷到达消费方时已是普通对象，
 * 不能用 instanceof 判别，须直接读取 iocKey 字段比对。
 */
function waitOpenFailedEvent(expectedIocKey: string, timeoutMs: number): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    const cb: Callback<emitter.EventData> = (data: emitter.EventData) => {
      const raw: Object | undefined = data?.data;
      if (raw !== undefined && (raw as AutoOpenFailure).iocKey === expectedIocKey) {
        EventBus.off(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED, cb);
        clearInterval(timer);
        resolve();
      }
    };
    const timer = setInterval(() => {
      clearInterval(timer);
      EventBus.off(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED, cb);
      reject(new Error(`wait event ${AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED} timeout`));
    }, timeoutMs);
    EventBus.on(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED, cb);
  });
}

/**
 * AutoOpenCoordinator（M3 子数据库协调器）单元测试。
 *
 * 使用沙箱真实加密库文件 + 真实多库注册表（FileService 单例）端到端验证：
 * - 后台自动打开：成功登记为子库、不抢当前库、递归孙库
 * - 过滤：Enabled=False / IfDevice 本设备排除 / SkipIfNotExists 缺失文件静默跳过
 * - 手动打开：失败子库可重试（removeAttempted）、成功后切换当前库、已打开子库直接切换
 */
export default function AutoOpenCoordinatorTest() {
  describe('AutoOpenCoordinatorTest', () => {
    let appContext: common.Context;
    let fileManager: KdbxFileManager;
    let filesDir: string;
    let registry: DatabaseRegistry;

    beforeAll(() => {
      appContext = KdbxModeTestHelper.initContext();
      fileManager = new KdbxFileManager(StorageType.LOCAL);
      filesDir = appContext.filesDir;
    });

    beforeEach(() => {
      // 复位多库注册表与协调器内部计数（FileService 单例跨用例共享）
      FileService.init();
      AutoOpenCoordinator.getInstance().reset();
      registry = FileService.getRegistry();
    });

    it('onParentUnlocked opens child in background without stealing current', 0, async () => {
      const childPath = `${filesDir}/coord-child-basic.kdbx`;
      const childDb = createKdbx('ChildDb', CHILD_PASSWORD);
      await fileManager.write(childPath, await childDb.save());

      const parentPath = `${filesDir}/coord-parent-basic.kdbx`;
      const parentDb = createKdbx('ParentDb', PARENT_PASSWORD);
      addChildEntry(parentDb, 'ChildDb', childPath, CHILD_PASSWORD);
      const parentIocKey = await writeAndRegisterParent(parentPath, parentDb);

      // 订阅先于触发：DONE 可能在 onParentUnlocked 返回前同步发射
      const donePromise = waitCoordinatorEvent(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, parentIocKey, EVENT_TIMEOUT);
      await AutoOpenCoordinator.getInstance().onParentUnlocked(parentIocKey);
      await donePromise;

      const childIocKey = DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPath);
      expect(registry.has(childIocKey)).assertTrue();
      expect(registry.isChild(childIocKey)).assertTrue();
      expect(registry.wasAttempted(childIocKey)).assertTrue();
      // 后台打开不抢当前库：当前库仍为父库
      expect(registry.getCurrentKey()).assertEqual(parentIocKey);
      // 子库会话可用（模型成功还原）
      const childParam = registry.get(childIocKey);
      expect(childParam !== undefined).assertTrue();
      expect(childParam?.database !== undefined).assertTrue();
    });

    it('onParentUnlocked skips entry disabled by Enabled=False', 0, async () => {
      const childPath = `${filesDir}/coord-child-disabled.kdbx`;
      const childDb = createKdbx('ChildDb', CHILD_PASSWORD);
      await fileManager.write(childPath, await childDb.save());

      const parentPath = `${filesDir}/coord-parent-disabled.kdbx`;
      const parentDb = createKdbx('ParentDb', PARENT_PASSWORD);
      const entry = addChildEntry(parentDb, 'ChildDb', childPath, CHILD_PASSWORD);
      entry.fields.set(AutoOpenFieldName.ENABLED, 'False');
      const parentIocKey = await writeAndRegisterParent(parentPath, parentDb);

      const donePromise = waitCoordinatorEvent(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, parentIocKey, EVENT_TIMEOUT);
      await AutoOpenCoordinator.getInstance().onParentUnlocked(parentIocKey);
      // Enabled=False：无加载发起（AUTO_OPEN_DONE 立即发射，无子库事件）
      await donePromise;

      const childIocKey = DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPath);
      expect(registry.has(childIocKey)).assertFalse();
      expect(registry.wasAttempted(childIocKey)).assertFalse();
    });

    it('onParentUnlocked skips child excluded by IfDevice on this device', 0, async () => {
      const childPath = `${filesDir}/coord-child-ifdevice.kdbx`;
      const childDb = createKdbx('ChildDb', CHILD_PASSWORD);
      await fileManager.write(childPath, await childDb.save());

      const parentPath = `${filesDir}/coord-parent-ifdevice.kdbx`;
      const parentDb = createKdbx('ParentDb', PARENT_PASSWORD);
      const entry = addChildEntry(parentDb, 'ChildDb', childPath, CHILD_PASSWORD);
      entry.fields.set(AutoOpenFieldName.IF_DEVICE, `!${DeviceIdentity.getDeviceId()}`);
      const parentIocKey = await writeAndRegisterParent(parentPath, parentDb);

      const donePromise = waitCoordinatorEvent(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, parentIocKey, EVENT_TIMEOUT);
      await AutoOpenCoordinator.getInstance().onParentUnlocked(parentIocKey);
      await donePromise;

      const childIocKey = DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPath);
      expect(registry.has(childIocKey)).assertFalse();
    });

    it('onParentUnlocked silently skips missing file when SkipIfNotExists=True', 0, async () => {
      const missingPath = `${filesDir}/coord-child-missing.kdbx`;

      const parentPath = `${filesDir}/coord-parent-missing.kdbx`;
      const parentDb = createKdbx('ParentDb', PARENT_PASSWORD);
      const entry = addChildEntry(parentDb, 'MissingChild', missingPath, CHILD_PASSWORD);
      entry.fields.set(AutoOpenFieldName.SKIP_IF_NOT_EXISTS, 'True');
      const parentIocKey = await writeAndRegisterParent(parentPath, parentDb);

      const donePromise = waitCoordinatorEvent(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, parentIocKey, EVENT_TIMEOUT);
      await AutoOpenCoordinator.getInstance().onParentUnlocked(parentIocKey);
      // SkipIfNotExists + 文件缺失：静默跳过（无失败事件），DONE 正常发射
      await donePromise;

      const childIocKey = DatabaseRegistry.buildIocKey(StorageType.LOCAL, missingPath);
      expect(registry.has(childIocKey)).assertFalse();
      // 静默跳过已在本会话处理过（attempted 已标记，不重复探测）
      expect(registry.wasAttempted(childIocKey)).assertTrue();
    });

    it('onParentUnlocked opens multiple children serially keeping parent current', 0, async () => {
      const childPathA = `${filesDir}/coord-multi-a.kdbx`;
      const childPathB = `${filesDir}/coord-multi-b.kdbx`;
      await fileManager.write(childPathA, await createKdbx('ChildA', CHILD_PASSWORD).save());
      await fileManager.write(childPathB, await createKdbx('ChildB', CHILD_PASSWORD).save());

      const parentPath = `${filesDir}/coord-parent-multi.kdbx`;
      const parentDb = createKdbx('ParentDb', PARENT_PASSWORD);
      addChildEntry(parentDb, 'ChildA', childPathA, CHILD_PASSWORD);
      addChildEntry(parentDb, 'ChildB', childPathB, CHILD_PASSWORD);
      const parentIocKey = await writeAndRegisterParent(parentPath, parentDb);

      const donePromise = waitCoordinatorEvent(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, parentIocKey, EVENT_TIMEOUT);
      await AutoOpenCoordinator.getInstance().onParentUnlocked(parentIocKey);
      await donePromise;

      expect(registry.has(DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPathA))).assertTrue();
      expect(registry.has(DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPathB))).assertTrue();
      expect(registry.isChild(DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPathA))).assertTrue();
      expect(registry.isChild(DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPathB))).assertTrue();
      expect(registry.getCurrentKey()).assertEqual(parentIocKey);
      expect(registry.size()).assertEqual(3);
    });

    it('onParentUnlocked recursively opens grandchild via child database', 0, async () => {
      const grandPath = `${filesDir}/coord-grand.kdbx`;
      await fileManager.write(grandPath, await createKdbx('GrandDb', CHILD_PASSWORD).save());

      // 子库自身含 AutoOpen 条目指向孙库
      const childPath = `${filesDir}/coord-child-grand.kdbx`;
      const childDb = createKdbx('ChildDb', CHILD_PASSWORD);
      addChildEntry(childDb, 'GrandDb', grandPath, CHILD_PASSWORD);
      await fileManager.write(childPath, await childDb.save());

      const parentPath = `${filesDir}/coord-parent-grand.kdbx`;
      const parentDb = createKdbx('ParentDb', PARENT_PASSWORD);
      addChildEntry(parentDb, 'ChildDb', childPath, CHILD_PASSWORD);
      const parentIocKey = await writeAndRegisterParent(parentPath, parentDb);

      const childIocKey = DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPath);
      // 等父库 DONE（子库已登记 + 孙库已排队）后再等子库 DONE（孙库登记完成）
      const parentDonePromise = waitCoordinatorEvent(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE,
        parentIocKey, EVENT_TIMEOUT);
      const childDonePromise = waitCoordinatorEvent(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE,
        childIocKey, EVENT_TIMEOUT);
      await AutoOpenCoordinator.getInstance().onParentUnlocked(parentIocKey);
      await parentDonePromise;
      await childDonePromise;

      const grandIocKey = DatabaseRegistry.buildIocKey(StorageType.LOCAL, grandPath);
      expect(registry.has(grandIocKey)).assertTrue();
      expect(registry.isChild(grandIocKey)).assertTrue();
      expect(registry.getCurrentKey()).assertEqual(parentIocKey);
    });

    it('openManually retries failed child and switches current after success', 0, async () => {
      const childPath = `${filesDir}/coord-child-retry.kdbx`;
      // 清理上一轮运行第二阶段写入的残留文件（保证首轮"文件不存在→失败"语义可复现）
      if (fs.accessSync(childPath, fs.AccessModeType.EXIST)) {
        fs.unlinkSync(childPath);
      }

      const parentPath = `${filesDir}/coord-parent-retry.kdbx`;
      const parentDb = createKdbx('ParentDb', PARENT_PASSWORD);
      addChildEntry(parentDb, 'RetryChild', childPath, CHILD_PASSWORD);
      const parentIocKey = await writeAndRegisterParent(parentPath, parentDb);

      const childIocKey = DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPath);
      // 第一次：文件不存在（无 SkipIfNotExists）→ 失败事件（订阅先于触发）
      const failedPromise = waitOpenFailedEvent(childIocKey, EVENT_TIMEOUT);
      await AutoOpenCoordinator.getInstance().onParentUnlocked(parentIocKey);
      await failedPromise;
      expect(registry.has(childIocKey)).assertFalse();

      // 补写子库文件后手动打开：removeAttempted 允许重试
      await fileManager.write(childPath, await createKdbx('RetryDb', CHILD_PASSWORD).save());
      const items: AutoOpenItem[] = AutoOpenService.scan(parentDb, parentIocKey);
      expect(items.length).assertEqual(1);
      const openedPromise = waitCoordinatorEvent(AutoOpenCoordinator.EVENT_DATABASE_OPENED, childIocKey, EVENT_TIMEOUT);
      const result = await AutoOpenCoordinator.getInstance().openManually(items[0]);
      expect(result).assertEqual('loading');
      await openedPromise;

      expect(registry.has(childIocKey)).assertTrue();
      expect(registry.isChild(childIocKey)).assertTrue();
      // 手动打开成功后切换为当前库
      expect(registry.getCurrentKey()).assertEqual(childIocKey);
    });

    it('openManually switches directly to already opened child', 0, async () => {
      const childPath = `${filesDir}/coord-child-switch.kdbx`;
      await fileManager.write(childPath, await createKdbx('ChildDb', CHILD_PASSWORD).save());

      const parentPath = `${filesDir}/coord-parent-switch.kdbx`;
      const parentDb = createKdbx('ParentDb', PARENT_PASSWORD);
      addChildEntry(parentDb, 'ChildDb', childPath, CHILD_PASSWORD);
      const parentIocKey = await writeAndRegisterParent(parentPath, parentDb);

      const donePromise = waitCoordinatorEvent(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, parentIocKey, EVENT_TIMEOUT);
      await AutoOpenCoordinator.getInstance().onParentUnlocked(parentIocKey);
      await donePromise;
      expect(registry.getCurrentKey()).assertEqual(parentIocKey);

      const items: AutoOpenItem[] = AutoOpenService.scan(parentDb, parentIocKey);
      const result = await AutoOpenCoordinator.getInstance().openManually(items[0]);
      expect(result).assertEqual('switched');
      const childIocKey = DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPath);
      expect(registry.getCurrentKey()).assertEqual(childIocKey);
    });
  });
}
