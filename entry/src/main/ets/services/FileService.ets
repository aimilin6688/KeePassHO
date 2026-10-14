import { Kdbx } from 'kdbxweb';
import { DbFileParam } from './TypeDefined';


/**
 * 文件服务对象
 */
export class FileService {
  private static instance: FileService = new FileService();
  private dbFileParam: DbFileParam;

  private constructor() {
    this.dbFileParam = {} as DbFileParam;
  }

  public static getInstance(): FileService {
    return FileService.instance;
  }

  public init(): void {
    this.initDbFileParam();
  }

  public static init(): void {
    FileService.instance.init();
  }

  public static close(): void {
    FileService.instance.init();
  }

  public initDbFileParam(): void {
    this.dbFileParam = {} as DbFileParam;
  }

  public setDbFileParam(dbFileParam: DbFileParam): void {
    this.dbFileParam = dbFileParam;
  }

  public static setDbFileParam(dbFileParam: DbFileParam): void {
    FileService.instance.setDbFileParam(dbFileParam);
  }

  public getDbFileParam(): DbFileParam {
    return this.dbFileParam;
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
    const dbFileParam = this.getDbFileParam();
    dbFileParam.newPassword = undefined;
    dbFileParam.newKeyLocation = undefined;
    dbFileParam.notUseKeyFile = false;
  }

  public static clearPendingCredentialChanges(): void {
    FileService.instance.clearPendingCredentialChanges();
  }

  /**
   * 是否存在待应用的改密凭证字段（改密页发起保存前写入、尚未被保存请求消费或清理）
   * 注意 newPassword='' 表示"切换到仅密钥文件模式"的待应用变更，同样视为待应用状态
   * @returns 是否存在待应用改密字段
   */
  public hasPendingCredentialChanges(): boolean {
    const dbFileParam = this.getDbFileParam();
    return dbFileParam.newPassword !== undefined || dbFileParam.newKeyLocation !== undefined
      || dbFileParam.notUseKeyFile === true;
  }

  public static hasPendingCredentialChanges(): boolean {
    return FileService.instance.hasPendingCredentialChanges();
  }
}