import { Kdbx } from 'kdbxweb';
import { DbFileParam } from './TypeDefined';
import { DatabaseRegistry, PutDatabaseOptions } from './database/DatabaseRegistry';


/**
 * 文件服务对象
 *
 * M2 起为多库注册表 facade：所有已打开数据库会话的唯一事实来源是内部 DatabaseRegistry，
 * 本类保留单库时代的静态 API（getDbFileParam / setDbFileParam / resetDbFileParam 等）并使其
 * 作用于「当前库」，存量调用点无需改动；多库管理（子库登记 / 切换 / 尝试标记）通过
 * getRegistry() 访问注册表完成。
 */
export class FileService {
  private static instance: FileService = new FileService();
  /**
   * 多库注册表：主库 + 子库的已打开会话记录，currentKey 指向当前库
   */
  private registry: DatabaseRegistry = new DatabaseRegistry();
  /**
   * 空会话兜底参数：注册表无当前库时 getDbFileParam() 返回此对象（空对象模式，永不返回 undefined，
   * 保证存量调用点 `param.database` / `param.filePath` 等取值不抛错）
   */
  private emptyParam: DbFileParam = {} as DbFileParam;

  public static getInstance(): FileService {
    return FileService.instance;
  }

  /**
   * 获取多库注册表（子库登记 / 切换 / AutoOpen 尝试标记等场景使用；单库 API 一律走当前库 facade）
   */
  public getRegistry(): DatabaseRegistry {
    return this.registry;
  }

  public static getRegistry(): DatabaseRegistry {
    return FileService.instance.getRegistry();
  }

  public init(): void {
    this.registry.clear();
    this.emptyParam = {} as DbFileParam;
  }

  public static init(): void {
    FileService.instance.init();
  }

  public static close(): void {
    FileService.instance.init();
  }

  public initDbFileParam(): void {
    this.init();
  }

  public setDbFileParam(dbFileParam: DbFileParam): void {
    this.registry.put(dbFileParam, new PutDatabaseOptions(true, false));
  }

  public static setDbFileParam(dbFileParam: DbFileParam): void {
    FileService.instance.setDbFileParam(dbFileParam);
  }

  public getDbFileParam(): DbFileParam {
    return this.registry.getCurrent() ?? this.emptyParam;
  }

  public static getDbFileParam(): DbFileParam {
    return FileService.instance.getDbFileParam();
  }

  public static getFilePath() {
    return FileService.getDbFileParam().filePath;
  }

  public static getDatabase() {
    return FileService.getDbFileParam().database;
  }

  public static isDatabaseValid() {
    return FileService.getDbFileParam() && FileService.getDbFileParam().database !== undefined;
  }

  /**
   * 是否存在已打开的数据库会话（注册表中存在当前库记录）
   */
  public static hasOpenDatabase(): boolean {
    return FileService.getRegistry().getCurrentKey() !== null;
  }

  /**
   * 关闭当前库：从注册表移除当前记录并返回其会话参数；
   * 仍有剩余库时自动切换到首个剩余库（注册表 remove 语义），最后一个库关闭后注册表回到空态
   * @returns 被关闭库的会话参数；无打开库时返回 undefined
   */
  public static closeCurrent(): DbFileParam | undefined {
    const instance = FileService.instance;
    const key = instance.registry.getCurrentKey();
    if (key === null) {
      return undefined;
    }
    const removed = instance.registry.remove(key);
    if (instance.registry.getCurrentKey() === null) {
      // 最后一个库已关闭：回到干净空会话
      instance.emptyParam = {} as DbFileParam;
    }
    return removed;
  }

  /**
   * 重置数据库文件参数
   * @param kdbx 数据库
   * @param modifiedTime 修改时间
   * @param version 远端文件版本标识（不透明字符串）
   * @param contentHash 远端文件内容 SHA256
   * @returns 结果
   */
  public static resetDbFileParam(kdbx: Kdbx, modifiedTime: number, version?: string | null, contentHash?: string | null): DbFileParam {
    FileService.getDbFileParam().database = kdbx;
    FileService.getDbFileParam().modifiedTime = modifiedTime;
    FileService.getDbFileParam().version = version ?? null;
    FileService.getDbFileParam().contentHash = contentHash ?? null;
    return FileService.getDbFileParam();
  }

  /**
   * 清理待应用的改密凭证字段（newPassword / newKeyLocation / notUseKeyFile）
   *
   * 这些字段由改密页在发起保存前写入共享 dbFileParam，仅当次保存请求消费；
   * 保存失败或被放弃（保存出错 / 冲突弹框关闭 / RELOAD 重载策略 / Worker 外部终止）后
   * 必须清理，否则残留字段会被后续普通保存静默应用，
   * 造成非预期的密码 / 密钥文件变更（用户被锁在库外）。
   * 会话字段（database / password / filePath 等）不受影响。
   */
  public clearPendingCredentialChanges(): void {
    FileService.clearPendingCredentialChangesOf(this.getDbFileParam());
  }

  public static clearPendingCredentialChanges(): void {
    FileService.instance.clearPendingCredentialChanges();
  }

  /**
   * 清理指定会话参数上待应用的改密凭证字段（多库安全版本：作用于传入的 param，
   * 不依赖当前库指针——保存链路中捕获的参数在回调时可能与当前库不一致）
   */
  public static clearPendingCredentialChangesOf(dbFileParam: DbFileParam): void {
    dbFileParam.newPassword = undefined;
    dbFileParam.newKeyLocation = undefined;
    dbFileParam.notUseKeyFile = false;
  }

  /**
   * 是否存在待应用的改密凭证字段（改密页发起保存前写入、尚未被保存请求消费或清理）
   * 注意 newPassword='' 表示"切换到仅密钥文件模式"的待应用变更，同样视为待应用状态
   * @returns 是否存在待应用改密字段
   */
  public hasPendingCredentialChanges(): boolean {
    return FileService.hasPendingCredentialChangesOf(this.getDbFileParam());
  }

  public static hasPendingCredentialChanges(): boolean {
    return FileService.instance.hasPendingCredentialChanges();
  }

  /**
   * 指定会话参数是否存在待应用的改密凭证字段（多库安全版本）
   */
  public static hasPendingCredentialChangesOf(dbFileParam: DbFileParam): boolean {
    return dbFileParam.newPassword !== undefined || dbFileParam.newKeyLocation !== undefined
      || dbFileParam.notUseKeyFile === true;
  }
}
