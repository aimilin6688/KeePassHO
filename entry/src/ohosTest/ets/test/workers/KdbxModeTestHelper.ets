import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { ErrorEvent, MessageEvents, worker } from '@kit.ArkTS';
import { Kdbx, KdbxCredentials, KdbxGroup, ProtectedValue } from 'kdbxweb';
import { DatabaseLoad } from '../../../../main/ets/workers/DatabaseLoad';
import { DatabaseSave } from '../../../../main/ets/workers/DatabaseSave';
import { KdbxLoadServiceCallback } from '../../../../main/ets/services/kdbx/KdbxLoadService';
import { LoadDatabase } from '../../../../main/ets/workers/DatabaseLoadWorkerParam';
import { SaveDatabaseMessage } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { DbFileParam, AuthType } from '../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../main/ets/storage';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { HashUtils } from '../../../../main/ets/common/utils/HashUtils';
import { ConflictMessage, LoadMessage, MessageType, SuccessMessage, WorkerMessage } from '../../../../main/ets/workers/WorkerParam';
import { DatabaseWorkerFactory } from '../../../../main/ets/workers/DatabaseWorkerFactory';
import { LoadDispatchCache } from '../../../../main/ets/services/kdbx/LoadDispatchCache';
import { Constants } from '../../../../main/ets/common/constants/Constants';
// 副作用引入 worker 壳：ohosTest 构建仅编译被引用文件，必须 import 才能将壳文件编入 entry_test abc。
// 主线程加载时壳内 workerPort 为空，顶层注册自动跳过（不影响 worker 线程行为）。
import '../../../../main/ets/workers/DatabaseLoadWorker.ets';
import '../../../../main/ets/workers/DatabaseSaveWorker.ets';

/**
 * 数据库加载/保存双模式（同步模式 / Worker 异步模式）测试共享基建。
 *
 * 使用运行时真实加密构造的 KDBX 数据库（Kdbx.create + save），配合本地沙箱真实文件，
 * 不使用任何 mock 数据。通过 Kdbx.load 当前文件内容的方式模拟"另一设备"的并发修改。
 */
export class KdbxModeTestHelper {
  /** 测试数据库主密码 */
  public static readonly DB_PASSWORD: string = 'Mode-Test-Pass-123';
  /** Worker 消息等待超时（毫秒） */
  public static readonly WORKER_TIMEOUT: number = 30000;

  /**
   * 注入 ApplicationContext（ResourceManager / 临时目录等依赖）
   */
  public static initContext(): common.Context {
    const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
    CommonUtils.init(appContext as common.UIAbilityContext);
    return appContext;
  }

  /**
   * 创建真实加密数据库（KDBX4），并写入首个条目
   */
  public static async createDatabase(name: string, firstEntryTitle: string): Promise<Kdbx> {
    const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
    const database = Kdbx.create(credentials, name);
    KdbxModeTestHelper.addEntry(database, firstEntryTitle);
    return database;
  }

  /**
   * 向数据库默认分组添加一个真实条目
   */
  public static addEntry(database: Kdbx, title: string): void {
    const entry = database.createEntry(database.getDefaultGroup());
    entry.fields.set('Title', title);
  }

  /**
   * 模拟"另一设备"修改：从文件当前内容加载副本、添加条目、加密保存并写回存储。
   * @returns 写入的新文件内容
   */
  public static async writeRemoteModification(fileManager: KdbxFileManager, path: string, title: string):
    Promise<ArrayBuffer> {
    const fileContent = await fileManager.read(path);
    const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
    const remoteDatabase = await Kdbx.load(fileContent.content, credentials);
    KdbxModeTestHelper.addEntry(remoteDatabase, title);
    const saved = await remoteDatabase.save();
    await fileManager.write(path, saved);
    return saved;
  }

  /**
   * 收集数据库全部条目标题（递归遍历所有分组）
   */
  public static collectEntryTitles(database: Kdbx): string[] {
    const titles: string[] = [];
    KdbxModeTestHelper.collectGroupTitles(database.getDefaultGroup(), titles);
    return titles;
  }

  private static collectGroupTitles(group: KdbxGroup, titles: string[]): void {
    for (let i = 0; i < group.entries.length; i++) {
      const title = group.entries[i].fields.get('Title');
      if (typeof title === 'string') {
        titles.push(title);
      }
    }
    for (let i = 0; i < group.groups.length; i++) {
      KdbxModeTestHelper.collectGroupTitles(group.groups[i], titles);
    }
  }

  /**
   * 分级加载调度下强制指定文件走 Worker 路径（Worker 专测用例适配）：
   * 向调度缓存种入超阈值大小——resolveSize 命中缓存优先级①，
   * 守卫以 precheckSize 复用该值跳过 getInfo，不影响真实文件读取
   */
  public static forceWorkerDispatch(filePath: string): void {
    LoadDispatchCache.put(filePath, Constants.SYNC_LOAD_MAX_BYTES + 1);
  }

  /**
   * 构造保存参数（内存数据库对象 + 版本/内容哈希冲突检测基线）
   */
  public static makeDbFileParam(database: Kdbx, filePath: string, fileName: string,
    version: string | null, contentHash: string | null): DbFileParam {
    const dbFileParam: DbFileParam = {
      filePath: filePath,
      fileName: fileName,
      password: KdbxModeTestHelper.DB_PASSWORD,
      database: database,
      authType: AuthType.PASSWORD,
      storageType: StorageType.LOCAL,
      storageConfig: {},
      modifiedTime: 0,
      version: version,
      contentHash: contentHash
    };
    return dbFileParam;
  }

  /**
   * 构造加载参数
   */
  public static makeLoadParam(filePath: string, fileName: string, password: string): LoadDatabase {
    return new LoadDatabase(filePath, fileName, password, AuthType.PASSWORD,
      undefined, StorageType.LOCAL, {});
  }

  /**
   * 构造保存消息
   */
  public static makeSaveMessage(database: Kdbx, filePath: string, fileName: string,
    version: string | null, contentHash: string | null, strategy: string): SaveDatabaseMessage {
    const dbFileParam = KdbxModeTestHelper.makeDbFileParam(database, filePath, fileName, version, contentHash);
    return new SaveDatabaseMessage(database, dbFileParam, strategy);
  }

  /**
   * 计算内容 SHA256（十六进制小写），与产品冲突检测基线口径一致
   */
  public static async sha256Hex(content: ArrayBuffer): Promise<string> {
    return HashUtils.sha256Hex(content);
  }

  /**
   * 以同步模式执行一次加载（主线程直接调用，回调式 API 转 Promise）
   */
  public static loadSync(loadParam: LoadDatabase): Promise<SuccessMessage> {
    return new Promise<SuccessMessage>((resolve, reject) => {
      const callback: KdbxLoadServiceCallback = {
        onSuccessMessage: (message: SuccessMessage) => {
          resolve(message);
        },
        onErrorMessage: (message: LoadMessage) => {
          reject(new Error(String(message.message)));
        }
      };
      new DatabaseLoad().handleLoadDatabase(loadParam, callback);
    });
  }

  /**
   * 以同步模式执行一次保存（主线程直接调用），回调式 API 转多终态结果
   */
  public static saveSync(saveMessage: SaveDatabaseMessage): Promise<SyncSaveResult> {
    return new Promise<SyncSaveResult>((resolve, reject) => {
      new DatabaseSave({
        onSuccess: (success: SuccessMessage) => {
          const result = new SyncSaveResult();
          result.success = success;
          resolve(result);
        },
        onConflict: (conflict: ConflictMessage) => {
          const result = new SyncSaveResult();
          result.conflict = conflict;
          resolve(result);
        },
        onError: (errorMessage: string) => {
          reject(new Error(errorMessage));
        }
      }).handleSaveDatabase(saveMessage);
    });
  }

  /**
   * 创建数据库加载 Worker。
   *
   * useNormalizedOHMUrl 开启时仅支持同包相对路径加载，统一走产品同款工厂；
   * worker 壳文件已通过副作用 import 编入 entry_test abc。
   */
  public static createLoadWorker(): worker.ThreadWorker {
    return DatabaseWorkerFactory.createLoadWorker();
  }

  /**
   * 创建数据库保存 Worker（同 createLoadWorker 说明）
   */
  public static createSaveWorker(): worker.ThreadWorker {
    return DatabaseWorkerFactory.createSaveWorker();
  }

  /**
   * 等待 Worker 发回的终态消息（SUCCESS / CONFLICT / ERROR），超时或 Worker 异常时拒绝
   */
  public static waitWorkerResult(w: worker.ThreadWorker, timeoutMs: number): Promise<WorkerMessage> {
    return new Promise<WorkerMessage>((resolve, reject) => {
      const timerId = setTimeout(() => {
        reject(new Error('worker message timeout after ' + timeoutMs + 'ms'));
      }, timeoutMs);
      w.onmessage = (event: MessageEvents) => {
        const message = event.data as WorkerMessage;
        if (message.type === MessageType.SUCCESS || message.type === MessageType.CONFLICT
          || message.type === MessageType.ERROR) {
          clearTimeout(timerId);
          resolve(message);
        }
      };
      w.onAllErrors = (error: ErrorEvent) => {
        clearTimeout(timerId);
        reject(new Error(error.message));
      };
    });
  }
}

/**
 * 同步保存的多终态结果
 */
export class SyncSaveResult {
  success: SuccessMessage | null = null;
  conflict: ConflictMessage | null = null;
}
