import { hilog } from '@kit.PerformanceAnalysisKit';
import { emitter } from '@kit.BasicServicesKit';
import { ErrorEvent } from '@kit.ArkTS';
import { ByteUtils } from 'kdbxweb';

import { AutoOpenItem } from './AutoOpenItem';
import { AutoOpenService } from './AutoOpenService';
import { AutoOpenPathResolver } from './AutoOpenPathResolver';
import { ChildTarget, SchemeMapper } from './SchemeMapper';
import { AutoOpenConfigRebuilder, ConfigRebuildResult } from './AutoOpenConfigRebuilder';
import { DeviceIdentity } from './DeviceIdentity';
import { IfDeviceParser } from './IfDeviceParser';
import { DatabaseRegistry, PutDatabaseOptions } from '../kdbx/DatabaseRegistry';
import { FileService } from '../FileService';
import { EventBus } from '../EventBus';
import { RecentFilesService } from '../RecentFilesService';
import KdbxLoadService from '../kdbx/KdbxLoadService';
import { KdbxFileManager } from '../kdbx/KdbxFileManager';
import { AuthType, AuthTypeInfo, DbFileParam, RecentFile } from '../TypeDefined';
import { LoadDatabase } from '../../workers/DatabaseLoadWorkerParam';
import { LoadMessage, SuccessMessage } from '../../workers/WorkerParam';
import { FilenameUtils, KdbxUtils, CommonUtils } from '../../common/utils';
import { LocalFileStorageConfig } from '../../storage/local/LocalFileConfig';
import { StorageConfig, StorageType } from '../../storage';
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
 * - 远端子库打开成功后把连接配置（不含子库主密码）回写最近文件记录
 *   （RecentFilesService.upsertChildConfigRecord，M6.9：统一解析链②的数据源，
 *   尾部追加不置顶）；本地子库不回写；主打开链路的 RecentFiles 维持既有逻辑；
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
      const outcome: string = await this.openChild(item, parentParam, false);
      if (outcome === 'queued') {
        queuedCount++;
      }
    }
    if (queuedCount === 0) {
      EventBus.emit(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, parentIocKey);
    }
  }

  /**
   * 由 AutoOpen 条目 URL 计算子库 iocKey（M6：本地/远端统一入口）：
   * 占位符展开 → scheme 解析 → 按目标存储类型构造 iocKey。
   * 管理页 / 切换面板的「已打开」判定与本协调器内部判定保持同一口径。
   * @returns 可识别 scheme 时返回 iocKey；URL 为空或 scheme 不支持返回空串
   */
  static buildChildIocKey(itemUrl: string, parentFilePath: string): string {
    const target: ChildTarget | undefined = SchemeMapper.resolveTarget(itemUrl, parentFilePath);
    if (target === undefined) {
      return '';
    }
    return DatabaseRegistry.buildIocKey(target.storageType, target.filePath);
  }

  /**
   * 子库打开失败统一提示（切换面板 / 子库管理页的 OPEN_FAILED 事件监听调用）。
   * 子库加载为异步入队，「立即打开」发起后仅返回 loading，真正的失败终态经本事件到达——
   * 若不在此提示，用户点击后将无任何反馈。
   * emitter 会序列化事件数据，此处按字段读取 AutoOpenFailure 同构普通对象。
   */
  static showOpenFailedToast(eventData: emitter.EventData): void {
    const raw: Object | undefined = eventData.data;
    if (raw === undefined || raw === null) {
      CommonUtils.showToast($r('app.string.database_switcher_child_failed'), 2000);
      return;
    }
    const failure: AutoOpenFailure = raw as AutoOpenFailure;
    const title: string = failure.title;
    const reason: string = failure.reason;
    if (title.length === 0) {
      CommonUtils.showToast($r('app.string.database_switcher_child_failed'), 2000);
      return;
    }
    if (reason.length > 0) {
      CommonUtils.showToast($r('app.string.child_dbs_open_failed_detail', title, reason), 2000);
      return;
    }
    CommonUtils.showToast($r('app.string.child_dbs_open_failed', title), 2000);
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
    const childUrl: string = AutoOpenPathResolver.resolveUrl(item.url, parentParam.filePath);
    if (childUrl.length === 0) {
      return 'failed';
    }
    const target: ChildTarget | undefined = SchemeMapper.parse(childUrl);
    if (target === undefined) {
      hilog.warn(DOMAIN, TAG, 'unsupported child scheme: %{public}s', childUrl);
      return 'failed';
    }
    const iocKey: string = DatabaseRegistry.buildIocKey(target.storageType, target.filePath);
    if (registry.has(iocKey)) {
      registry.setCurrent(iocKey);
      return 'switched';
    }
    // 允许重试本会话失败的子库（attempted 仅防自动触发循环，不拦手动重试）
    registry.removeAttempted(iocKey);
    const outcome: string = await this.openChild(item, parentParam, true);
    if (outcome === 'queued') {
      return 'loading';
    }
    // 'failedNotified'：失败已由 OPEN_FAILED 事件给出详细提示，调用方无需再吐司
    return outcome === 'failedNotified' ? 'failedNotified' : 'failed';
  }

  /**
   * 发起单个子库打开：解析路径与 scheme → 循环防护标记 → storageConfig 重建（M6）→
   * skip 检查 → 构造加载参数 → 入队。
   * 加载终态由 ChildOpenTask 回调结算（见 handleChildSuccess / handleChildFailed）
   * @returns 'queued' 成功入队；'skipped' 静默跳过（父库/路径缺失、判重、skip 条件命中）；
   *          'failedNotified' storageConfig 重建失败（已发 OPEN_FAILED 详细提示）
   */
  private async openChild(item: AutoOpenItem, parentParam: DbFileParam, makeCurrent: boolean): Promise<string> {
    const registry: DatabaseRegistry = FileService.getRegistry();
    const childUrl: string = AutoOpenPathResolver.resolveUrl(item.url, parentParam.filePath);
    if (childUrl.length === 0) {
      return 'skipped';
    }
    const target: ChildTarget | undefined = SchemeMapper.parse(childUrl);
    if (target === undefined) {
      hilog.warn(DOMAIN, TAG, 'skip child: unsupported scheme: %{public}s', childUrl);
      return 'skipped';
    }
    const childIocKey: string = DatabaseRegistry.buildIocKey(target.storageType, target.filePath);
    if (registry.has(childIocKey) || registry.wasAttempted(childIocKey)) {
      return 'skipped';
    }
    // 发起前标记（失败也计入，防自动触发反复重试同一不可打开子库）
    registry.markAttempted(childIocKey);

    // M6.9：远端子库 storageConfig 统一解析链（①RecentFiles 命中复用 →
    // ②凭据型条目 Ioc 字段重建 → ③精确失败文案）
    const rebuild: ConfigRebuildResult = await AutoOpenConfigRebuilder.build(item, target);
    if (rebuild.config === undefined) {
      hilog.warn(DOMAIN, TAG, 'child storage config rebuild failed: %{public}s, reason: %{public}s',
        childIocKey, rebuild.failReason);
      EventBus.emit(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED,
        new AutoOpenFailure(childIocKey, item.title, rebuild.failReason));
      return 'failedNotified';
    }
    const storageConfig: StorageConfig = rebuild.config;

    // 密钥文件解析（UserName 字段支持 {DB_DIR} 等占位符；密钥文件恒为本地文件）
    const localFileManager: KdbxFileManager =
      new KdbxFileManager(StorageType.LOCAL, new LocalFileStorageConfig());
    let keyLocation: LocationInfo | undefined = undefined;
    if (item.keyFilePath.length > 0) {
      const keyPath: string = AutoOpenPathResolver.resolveUrl(item.keyFilePath, parentParam.filePath);
      if (item.skipIfKeyFileNotExists) {
        const keyInfo = await localFileManager.getInfoOrNull(keyPath);
        if (keyInfo === null) {
          hilog.info(DOMAIN, TAG, 'skip child: key file not exists: %{public}s', keyPath);
          return 'skipped';
        }
      }
      keyLocation = {
        mode: LocationMode.SELECT,
        filePath: keyPath,
        fileName: FilenameUtils.getFileName(keyPath),
        storageType: StorageType.LOCAL,
        storageConfig: new LocalFileStorageConfig()
      };
    }

    // KeyFile.bin 内嵌密钥回退（kp2a KeeAutoExec.cs:339-345）：UserName 密钥路径为空
    // 且条目携带 KeyFile.bin 附件时以附件内容为密钥来源（内容不驻留 item，现取现用，
    // base64 随 JSON 消息传 Worker，otpSecretHex 同机制）
    let keyFileDataBase64: string | undefined = undefined;
    if (keyLocation === undefined && item.hasKeyFileAttachment) {
      try {
        const attachment: ArrayBuffer =
          await AutoOpenService.readKeyFileAttachment(parentParam.database, item.entryUuid);
        keyFileDataBase64 = ByteUtils.bytesToBase64(attachment);
      } catch (error) {
        const reason: string = error instanceof Error ? error.message : `${error}`;
        hilog.warn(DOMAIN, TAG, 'read KeyFile.bin attachment failed: %{public}s', reason);
        EventBus.emit(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED,
          new AutoOpenFailure(childIocKey, item.title, reason));
        return 'failedNotified';
      }
    }

    // 子库文件缺失 + SkipIfNotExists：仅本地检查存在性；远端恒视为存在
    // （对齐 kp2a KeeAutoExec.cs:358-385：远端存在性探测代价高且可能需交互，不作拦截）
    if (item.skipIfNotExists && target.storageType === StorageType.LOCAL) {
      const childInfo = await localFileManager.getInfoOrNull(target.filePath);
      if (childInfo === null) {
        hilog.info(DOMAIN, TAG, 'skip child: file not exists: %{public}s', target.filePath);
        return 'skipped';
      }
    }

    this.beginPending(item.sourceIocKey);
    // 认证方式：路径密钥 → 密码+密钥文件；附件密钥 → 有密码为密码+密钥文件、
    // 无密码为仅密钥文件（kp2a 密码组件仅在 Password 非空时并入复合密钥）
    let authType: AuthTypeInfo = AuthType.PASSWORD;
    if (keyLocation !== undefined) {
      authType = AuthType.PASSWORD_KEYFILE;
    } else if (keyFileDataBase64 !== undefined) {
      authType = item.passwordText.length > 0 ? AuthType.PASSWORD_KEYFILE : AuthType.KEYFILE;
    }
    const loadParam: LoadDatabase = new LoadDatabase(target.filePath, FilenameUtils.getFileName(target.filePath),
      item.passwordText, authType, keyLocation, target.storageType, storageConfig);
    loadParam.keyFileDataBase64 = keyFileDataBase64;
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
    return 'queued';
  }

  /**
   * 子库加载成功：还原模型 → 登记注册表 → 广播 OPENED → 递归扫描孙库 → 结算在飞计数
   */
  private async handleChildSuccess(task: ChildOpenTask, message: SuccessMessage): Promise<void> {
    if (task.finished) {
      return;
    }
    task.finished = true;
    const childIocKey: string = DatabaseRegistry.buildIocKey(
      task.loadParam.storageType, task.loadParam.filePath);
    try {
      const kdbx = await KdbxUtils.successMessageToKdbx(message, task.loadParam);
      const childParam: DbFileParam = {
        filePath: task.loadParam.filePath,
        fileName: task.loadParam.fileName,
        password: task.loadParam.password,
        database: kdbx,
        authType: task.loadParam.authType,
        keyLocation: task.loadParam.keyLocation,
        keyFileDataBase64: task.loadParam.keyFileDataBase64,
        storageType: task.loadParam.storageType,
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
      // M6.9：远端子库回写连接配置到最近文件（统一解析链②的数据源；
      // 不含子库主密码；best-effort 不阻塞打开流程）
      if (task.loadParam.storageType !== StorageType.LOCAL) {
        const record: RecentFile = {
          filePath: task.loadParam.filePath,
          fileName: task.loadParam.fileName,
          storageType: task.loadParam.storageType,
          storageConfig: task.loadParam.storageConfig,
          authType: task.loadParam.authType,
          keyLocation: task.loadParam.keyLocation
        };
        await RecentFilesService.upsertChildConfigRecord(record);
      }
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
    const childIocKey: string = DatabaseRegistry.buildIocKey(
      task.loadParam.storageType, task.loadParam.filePath);
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
