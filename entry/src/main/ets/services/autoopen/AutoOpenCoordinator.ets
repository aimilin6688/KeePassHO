import { hilog } from '@kit.PerformanceAnalysisKit';
import { ErrorEvent } from '@kit.ArkTS';

import { AutoOpenItem } from './AutoOpenItem';
import { AutoOpenService } from './AutoOpenService';
import { AutoOpenPathResolver } from './AutoOpenPathResolver';
import { DeviceIdentity } from './DeviceIdentity';
import { IfDeviceParser } from './IfDeviceParser';
import { DatabaseRegistry, PutDatabaseOptions } from '../database/DatabaseRegistry';
import { FileService } from '../FileService';
import { EventBus } from '../EventBus';
import KdbxLoadService from '../kdbx/KdbxLoadService';
import { KdbxFileManager } from '../kdbx/KdbxFileManager';
import { AuthType, DbFileParam } from '../TypeDefined';
import { LoadDatabase } from '../../workers/DatabaseLoadWorkerParam';
import { LoadMessage, SuccessMessage } from '../../workers/WorkerParam';
import { FilenameUtils, KdbxUtils } from '../../common/utils';
import { LocalFileStorageConfig } from '../../storage/local/LocalFileConfig';
import { StorageType } from '../../storage';
import { LocationInfo, LocationMode } from '../beans/LocationParam';

const DOMAIN = 0x0000;
const TAG = 'AutoOpenCoordinator';

/**
 * 子库打开失败事件数据
 */
export class AutoOpenFailure {
  /** 失败子库的 iocKey */
  readonly iocKey: string;
  /** 子库条目标题（AutoOpen 条目 Title） */
  readonly title: string;
  /** 失败原因（错误消息） */
  readonly reason: string;

  constructor(iocKey: string, title: string, reason: string) {
    this.iocKey = iocKey;
    this.title = title;
    this.reason = reason;
  }
}

/**
 * 单个子库打开任务：终态身份令牌（防 SUCCESS 后 onexit 等重复终态重复结算）
 */
class ChildOpenTask {
  readonly item: AutoOpenItem;
  readonly loadParam: LoadDatabase;
  /** 手动打开（切换面板）时为 true：成功后切换为当前库 */
  readonly makeCurrent: boolean;
  /** 是否已到达终态（成功/失败任一） */
  finished: boolean = false;

  constructor(item: AutoOpenItem, loadParam: LoadDatabase, makeCurrent: boolean) {
    this.item = item;
    this.loadParam = loadParam;
    this.makeCurrent = makeCurrent;
  }
}

/**
 * 子数据库自动打开协调器（M3）
 *
 * 父库解锁成功后扫描其 AutoOpen 条目，后台串行打开子库：
 * - 过滤：enabled=false / IfDevice 本设备禁用 的条目跳过；
 *   已打开（registry.has）或本会话已尝试（wasAttempted）的跳过（循环防护，对齐 kp2a _openAttempts）；
 * - SkipIfNotExists / SkipIfKeyFileNotExists：标记为真且文件缺失时静默跳过；
 * - 后台自动打开不抢当前库（makeCurrent=false，用户解锁父库期待父库内容；
 *   kp2a 的 Focus=Restore 语义依赖其库选择中枢页，本应用无该页面故细化为此行为）；
 *   手动打开（openManually）成功后切换为当前库；
 * - 子库打开成功后递归扫描孙库（attempted 标记天然防环）；
 * - 子库不写入最近文件列表（RecentFiles 由主打开链路维护）；
 * - 全程事件驱动：OPENED / OPEN_FAILED / AUTO_OPEN_DONE（数据见各常量注释）。
 */
export class AutoOpenCoordinator {
  /** 子库打开成功事件（数据：子库 iocKey） */
  static readonly EVENT_DATABASE_OPENED: string = 'database_opened';
  /** 子库打开失败事件（数据：AutoOpenFailure；emitter 会序列化事件数据，消费方收到的是同构普通对象，须按字段读取，不可 instanceof） */
  static readonly EVENT_DATABASE_OPEN_FAILED: string = 'database_open_failed';
  /** 某父库的全部直接子库处理完毕事件（数据：父库 iocKey；无子库条目时立即发射） */
  static readonly EVENT_AUTO_OPEN_DONE: string = 'auto_open_done';

  private static instance: AutoOpenCoordinator | null = null;

  /** 每个父库在飞的直接子库任务数：归零时广播 AUTO_OPEN_DONE */
  private pendingByParent: Map<string, number> = new Map<string, number>();

  static getInstance(): AutoOpenCoordinator {
    if (AutoOpenCoordinator.instance === null) {
      AutoOpenCoordinator.instance = new AutoOpenCoordinator();
    }
    return AutoOpenCoordinator.instance;
  }

  /**
   * 复位内部计数（单测用）
   */
  reset(): void {
    this.pendingByParent.clear();
  }

  /**
   * 父库解锁成功后触发：扫描并后台串行打开其未尝试的子库。
   * 不阻塞调用方（内部异步逐条排队，加载经 KdbxLoadService.enqueueLoad 串行执行）
   * @param parentIocKey 父库 iocKey（须已在注册表登记）
   */
  async onParentUnlocked(parentIocKey: string): Promise<void> {
    const registry: DatabaseRegistry = FileService.getRegistry();
    const parentParam: DbFileParam | undefined = registry.get(parentIocKey);
    if (parentParam === undefined || !parentParam.database) {
      return;
    }
    const items: AutoOpenItem[] = AutoOpenService.scan(parentParam.database, parentIocKey);
    if (items.length === 0) {
      EventBus.emit(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, parentIocKey);
      return;
    }
    const deviceId: string = DeviceIdentity.getDeviceId();
    let queuedCount: number = 0;
    for (const item of items) {
      if (!item.enabled) {
        continue;
      }
      if (!IfDeviceParser.isEnabled(item.ifDeviceRaw, deviceId).enabled) {
        continue;
      }
      const started: boolean = await this.openChild(item, parentParam, false);
      if (started) {
        queuedCount++;
      }
    }
    if (queuedCount === 0) {
      EventBus.emit(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, parentIocKey);
    }
  }

  /**
   * 手动打开一个子库（切换面板区块 2 / 子库管理页「立即打开」）：
   * 清除尝试标记以允许重试失败子库；已打开时直接切换为当前库；
   * 成功后成为当前库（区别于后台自动打开的不抢当前库）
   * @returns 已打开直接切换返回 'switched'；发起加载返回 'loading'；
   *          父库不在注册表 / 路径为空返回 'failed'
   */
  async openManually(item: AutoOpenItem): Promise<string> {
    const registry: DatabaseRegistry = FileService.getRegistry();
    const parentParam: DbFileParam | undefined = registry.get(item.sourceIocKey);
    if (parentParam === undefined || !parentParam.database) {
      return 'failed';
    }
    const childPath: string = AutoOpenPathResolver.resolveUrl(item.url, parentParam.filePath);
    if (childPath.length === 0) {
      return 'failed';
    }
    const iocKey: string = DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPath);
    if (registry.has(iocKey)) {
      registry.setCurrent(iocKey);
      return 'switched';
    }
    // 允许重试本会话失败的子库（attempted 仅防自动触发循环，不拦手动重试）
    registry.removeAttempted(iocKey);
    const started: boolean = await this.openChild(item, parentParam, true);
    return started ? 'loading' : 'failed';
  }

  /**
   * 发起单个子库打开：解析路径 → 循环防护标记 → skip 检查 → 构造加载参数 → 入队。
   * 加载终态由 ChildOpenTask 回调结算（见 handleChildSuccess / handleChildFailed）
   * @returns 是否成功入队（false = 静默跳过或父库缺失）
   */
  private async openChild(item: AutoOpenItem, parentParam: DbFileParam, makeCurrent: boolean): Promise<boolean> {
    const registry: DatabaseRegistry = FileService.getRegistry();
    const childPath: string = AutoOpenPathResolver.resolveUrl(item.url, parentParam.filePath);
    if (childPath.length === 0) {
      return false;
    }
    const childIocKey: string = DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPath);
    if (registry.has(childIocKey) || registry.wasAttempted(childIocKey)) {
      return false;
    }
    // 发起前标记（失败也计入，防自动触发反复重试同一不可打开子库）
    registry.markAttempted(childIocKey);

    const localConfig: LocalFileStorageConfig = new LocalFileStorageConfig();
    const fileManager: KdbxFileManager = new KdbxFileManager(StorageType.LOCAL, localConfig);

    // 密钥文件解析（UserName 字段支持 {DB_DIR} 等占位符）
    let keyLocation: LocationInfo | undefined = undefined;
    if (item.keyFilePath.length > 0) {
      const keyPath: string = AutoOpenPathResolver.resolveUrl(item.keyFilePath, parentParam.filePath);
      if (item.skipIfKeyFileNotExists) {
        const keyInfo = await fileManager.getInfoOrNull(keyPath);
        if (keyInfo === null) {
          hilog.info(DOMAIN, TAG, 'skip child: key file not exists: %{public}s', keyPath);
          return false;
        }
      }
      keyLocation = {
        mode: LocationMode.SELECT,
        filePath: keyPath,
        fileName: FilenameUtils.getFileName(keyPath),
        storageType: StorageType.LOCAL,
        storageConfig: localConfig
      };
    }

    // 子库文件缺失 + SkipIfNotExists：静默跳过（对齐 KeePass 桌面语义）
    if (item.skipIfNotExists) {
      const childInfo = await fileManager.getInfoOrNull(childPath);
      if (childInfo === null) {
        hilog.info(DOMAIN, TAG, 'skip child: file not exists: %{public}s', childPath);
        return false;
      }
    }

    this.beginPending(item.sourceIocKey);
    const authType = keyLocation !== undefined ? AuthType.PASSWORD_KEYFILE : AuthType.PASSWORD;
    const loadParam: LoadDatabase = new LoadDatabase(childPath, FilenameUtils.getFileName(childPath),
      item.passwordText, authType, keyLocation, StorageType.LOCAL, localConfig);
    const task: ChildOpenTask = new ChildOpenTask(item, loadParam, makeCurrent);
    KdbxLoadService.enqueueLoad(loadParam, {
      onSuccessMessage: (message: SuccessMessage) => {
        this.handleChildSuccess(task, message);
      },
      onErrorMessage: (message: LoadMessage) => {
        this.handleChildFailed(task, String(message.message));
      },
      onAllErrors: (err: ErrorEvent) => {
        this.handleChildFailed(task, err.message);
      },
      onexit: (e: number) => {
        hilog.debug(DOMAIN, TAG, 'child load worker exit: %{public}d', e);
      }
    });
    return true;
  }

  /**
   * 子库加载成功：还原模型 → 登记注册表 → 广播 OPENED → 递归扫描孙库 → 结算在飞计数
   */
  private async handleChildSuccess(task: ChildOpenTask, message: SuccessMessage): Promise<void> {
    if (task.finished) {
      return;
    }
    task.finished = true;
    const childIocKey: string = DatabaseRegistry.buildIocKey(StorageType.LOCAL, task.loadParam.filePath);
    try {
      const kdbx = await KdbxUtils.successMessageToKdbx(message, task.loadParam);
      const childParam: DbFileParam = {
        filePath: task.loadParam.filePath,
        fileName: task.loadParam.fileName,
        password: task.loadParam.password,
        database: kdbx,
        authType: task.loadParam.authType,
        keyLocation: task.loadParam.keyLocation,
        storageType: StorageType.LOCAL,
        storageConfig: task.loadParam.storageConfig,
        modifiedTime: message.modifiedTime,
        version: message.version ?? null,
        contentHash: message.contentHash ?? null
      };
      const registry: DatabaseRegistry = FileService.getRegistry();
      registry.put(childParam, new PutDatabaseOptions(task.makeCurrent, true));
      EventBus.emit(AutoOpenCoordinator.EVENT_DATABASE_OPENED, childIocKey);
      hilog.info(DOMAIN, TAG, 'child database opened: %{public}s (makeCurrent=%{public}s)',
        childIocKey, `${task.makeCurrent}`);
      // 递归扫描孙库（attempted/has 标记防环）
      await this.onParentUnlocked(childIocKey);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'child database restore failed: %{public}s', error.message);
      EventBus.emit(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED,
        new AutoOpenFailure(childIocKey, task.item.title, error.message));
    } finally {
      this.endPending(task.item.sourceIocKey);
    }
  }

  /**
   * 子库加载失败：标记终态并广播 OPEN_FAILED
   */
  private handleChildFailed(task: ChildOpenTask, reason: string): void {
    if (task.finished) {
      return;
    }
    task.finished = true;
    const childIocKey: string = DatabaseRegistry.buildIocKey(StorageType.LOCAL, task.loadParam.filePath);
    hilog.warn(DOMAIN, TAG, 'child database open failed: %{public}s, reason=%{public}s', childIocKey, reason);
    EventBus.emit(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED,
      new AutoOpenFailure(childIocKey, task.item.title, reason));
    this.endPending(task.item.sourceIocKey);
  }

  /**
   * 登记某父库的一个在飞子库任务
   */
  private beginPending(parentIocKey: string): void {
    const current: number = this.pendingByParent.get(parentIocKey) ?? 0;
    this.pendingByParent.set(parentIocKey, current + 1);
  }

  /**
   * 结算某父库的一个在飞子库任务：归零时广播 AUTO_OPEN_DONE
   */
  private endPending(parentIocKey: string): void {
    const current: number = this.pendingByParent.get(parentIocKey) ?? 0;
    if (current <= 1) {
      this.pendingByParent.delete(parentIocKey);
      EventBus.emit(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, parentIocKey);
      return;
    }
    this.pendingByParent.set(parentIocKey, current - 1);
  }
}
