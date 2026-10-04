import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { CredentialsService } from '../services/CredentialsService';
import { FileContentInfo, WriteOption } from '../storage';
import { StorageError, StorageErrorCodes } from '../storage/StorageError';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConflictMessage, SuccessMessage } from './WorkerParam';
import { ConflictStrategy, SaveDatabase, SaveDatabaseDbParam, SaveDatabaseMessage } from './DatabaseSaveWorkerParam';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { HashUtils, KdbxUtils, ResourceManager } from '../common/utils';
import { SaveDatabaseCallback } from './callback/SaveDatabaseCallback';

const DOMAIN = 0x0000;
const TAG = 'DatabaseSave';

/**
 * 保存数据库
 * 保存流程：重读远端 -> 双基线判定（版本串 + 内容哈希）-> 未变则条件写入；
 * 已变则按冲突策略处理（AUTO 通知上层选择 / MERGE 合并后条件写入 / OVERWRITE 无条件写入），
 * 条件写入失败（VERSION_CONFLICT）时有界重试，防止覆盖其他设备的修改
 */
export class DatabaseSave {
  /**
   * 冲突合并写入的最大重试次数（防止对端持续写入导致活锁）
   */
  private static readonly MAX_CONFLICT_RETRY: number = 3;

  private callback?: SaveDatabaseCallback = undefined;

  constructor(callback?: SaveDatabaseCallback) {
    this.callback = callback;
  }

  /**
   * 处理数据库保存任务
   * @param requestMessage 请求
   */
  public async handleSaveDatabase(requestMessage: SaveDatabaseMessage) {
    try {
      const request = new SaveDatabase(JSON.parse(requestMessage.dbFileParam) as SaveDatabaseDbParam, requestMessage);
      this.postMessage($r('app.string.loading_key'));
      // 创建凭证
      const credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
      const strategy: string = request.conflictStrategy ?? ConflictStrategy.AUTO;
      let retryCount = 0;
      while (true) {
        // 加载远端文件内容（每次重试都重新读取，拿到最新事实）
        const fileContent: FileContentInfo = await this.loadKdbxFileContent(request);
        const remoteChanged = await DatabaseSave.isRemoteChanged(request, fileContent);
        if (!remoteChanged) {
          // 远端未变：直接保存，条件写入防竞态
          const savedDb: ArrayBuffer = await this.buildSavedContent(request, credentials);
          await this.writeContent(request, savedDb, fileContent.version ?? null);
          await this.postSuccess(request, savedDb, false);
          return;
        }
        if (strategy === ConflictStrategy.OVERWRITE) {
          // 用户已选择覆盖：丢弃远端修改，无条件写入本地内容
          const savedDb: ArrayBuffer = await this.buildSavedContent(request, credentials);
          await this.writeContent(request, savedDb, null);
          await this.postSuccess(request, savedDb, false);
          return;
        }
        if (strategy === ConflictStrategy.AUTO) {
          // 检测到冲突：通知上层（弹框让用户选择），本次不保存
          this.postConflictMessage(new ConflictMessage(fileContent.modifiedTime, fileContent.version ?? null));
          return;
        }
        // MERGE：合并远端修改后条件写入，写入时版本再变则有界重试
        const mergedDb: ArrayBuffer = await this.mergeDatabase(request, fileContent, credentials);
        try {
          await this.writeContent(request, mergedDb, fileContent.version ?? null);
        } catch (error) {
          if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT
            && retryCount < DatabaseSave.MAX_CONFLICT_RETRY) {
            retryCount++;
            hilog.warn(DOMAIN, TAG, 'Merge write conflict, retry: %{public}d/%{public}d', retryCount, DatabaseSave.MAX_CONFLICT_RETRY);
            continue;
          }
          if (error instanceof Error) {
            throw error;
          }
          throw new Error(error.message);
        }
        await this.postSuccess(request, mergedDb, true);
        return;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Worker error saving database:%{public}s, stack:%{public}s', error.message, error.stack);
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        // 重试耗尽仍冲突：远端正被持续写入，提示用户稍后重试，本地修改保留在内存中
        this.postErrorMessage($r('app.string.save_conflict_retry_exhausted').id);
      } else {
        this.postErrorMessage(KdbxUtils.kdbxErrorPayload(error));
      }
    }
  }

  /**
   * 判定远端文件是否已被修改（双基线）
   * 基线A：存储原生版本串（快速路径，可能为 null）
   * 基线B：内容 SHA256（最终裁判，永远执行）
   * @param request 请求
   * @param fileContent 当前远端文件内容
   */
  private static async isRemoteChanged(request: SaveDatabase, fileContent: FileContentInfo): Promise<boolean> {
    const remoteHash: string = await HashUtils.sha256Hex(fileContent.content);
    const baseHash: string | null = request.baseContentHash ?? null;
    if (baseHash !== null && remoteHash !== baseHash) {
      hilog.info(DOMAIN, TAG, 'Remote content changed: hash mismatch');
      return true;
    }
    const expectedVersion: string | null = request.expectedVersion ?? null;
    const remoteVersion: string | null = fileContent.version ?? null;
    if (expectedVersion !== null && remoteVersion !== null && expectedVersion !== remoteVersion) {
      hilog.info(DOMAIN, TAG, 'Remote version changed: %{public}s -> %{public}s', expectedVersion, remoteVersion);
      return true;
    }
    return false;
  }

  /**
   * 加载文件内容
   * @param request 请求
   * @return Promise<FileContentInfo> 文件内容
   * @throws Error 加载失败
   */
  private async loadKdbxFileContent(request: SaveDatabase): Promise<FileContentInfo> {
    if (!request.filePath) {
      hilog.error(DOMAIN, TAG, 'Worker error saving database: file path is empty');
      throw new Error();
    }
    const result = await new KdbxFileManager(request.storageType, request.storageConfig).read(request.filePath);
    this.postMessage($r('app.string.load_file_success'));
    return result;
  }

  /**
   * 构建待写入的数据库内容（凭证变更处理 + 加密保存）
   * @param request 请求
   * @param credentials 凭证
   * @param kdbx 已有数据库对象（合并场景传入），不传则从请求数据反序列化
   * @throws Error 保存失败
   */
  private async buildSavedContent(request: SaveDatabase, credentials: KdbxCredentials, kdbx?: Kdbx): Promise<ArrayBuffer> {
    this.postMessage($r('app.string.save_saving'));
    const database: Kdbx = kdbx ? kdbx : await KdbxUtils.arrayBufferToKdbx(request.data, request, credentials);
    if (request.newPassword) {
      database.credentials.setPassword(ProtectedValue.fromString(request.newPassword));
    }
    // 不适用密钥文件
    if (request.notUseKeyFile) {
      database.credentials.setKeyFile(null);
    } else {
      if (request.newKeyLocation) {
        await KdbxFileManager.of(request.newKeyLocation).read(request.newKeyLocation.filePath).then(newKeyFileContent => {
          database.credentials.setKeyFile(newKeyFileContent.content);
        });
      }
    }
    const now = new Date().getTime();
    return await database.save().then(savedDb => {
      hilog.debug(DOMAIN, TAG, 'Worker save database success, time: %{public}d ms', new Date().getTime() - now);
      return savedDb;
    });
  }

  /**
   * 合并数据库：远端修改合并进本地后构建写入内容
   * @param request 请求
   * @param fileContent 远端文件内容
   * @param credentials 凭证
   * @throws Error 合并失败（远端凭证变更时 Kdbx.load 抛出 InvalidKey）
   */
  private async mergeDatabase(request: SaveDatabase, fileContent: FileContentInfo,
    credentials: KdbxCredentials): Promise<ArrayBuffer> {
    this.postMessage($r('app.string.validating'));
    // 尝试加载远端数据库（远端凭证已变更时抛出 InvalidKey，由上层统一转为用户提示）
    const remoteKdbx: Kdbx = await Kdbx.load(fileContent.content, credentials);
    this.postMessage($r('app.string.merging_database'));
    // 合并数据库
    const localKdbx: Kdbx = await KdbxUtils.arrayBufferToKdbx(request.data, request, credentials);
    localKdbx.merge(remoteKdbx);
    // 保存数据库
    return await this.buildSavedContent(request, credentials, localKdbx);
  }

  /**
   * 写入文件内容
   * @param request 请求
   * @param content 数据库内容
   * @param expectedVersion 期望的远端版本（条件写入），null 表示无条件写入
   * @throws Error 写入失败，版本冲突时抛出 StorageError(VERSION_CONFLICT)
   */
  private async writeContent(request: SaveDatabase, content: ArrayBuffer, expectedVersion: string | null): Promise<void> {
    const kdbxFileManager = new KdbxFileManager(request.storageType, request.storageConfig);
    const option: WriteOption | undefined = expectedVersion !== null ? { expectedVersion: expectedVersion } : undefined;
    try {
      await kdbxFileManager.write(request.filePath, content, option);
      this.postMessage($r('app.string.save_success'));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Worker error save database:%{public}s, stack:%{public}s', error.message, error.stack);
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(error.message);
    }
  }

  /**
   * 发送成功消息（附带新的版本基线供下次保存使用）
   * @param request 请求
   * @param content 写入的数据库内容
   * @param isMerge 是否发生了合并
   */
  private async postSuccess(request: SaveDatabase, content: ArrayBuffer, isMerge: boolean): Promise<void> {
    const kdbxFileManager = new KdbxFileManager(request.storageType, request.storageConfig);
    try {
      const fileInfo = await kdbxFileManager.getInfo(request.filePath);
      const contentHash: string = await HashUtils.sha256Hex(content);
      this.postSuccessMessage(new SuccessMessage(content, fileInfo.modifiedTime, isMerge,
        fileInfo.version ?? null, contentHash));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Worker error get file info:%{public}s, stack:%{public}s', error.message, error.stack);
      if (error instanceof Error) {
        throw error;
      }
      throw new Error(error.message);
    }
  }

  /**
   * 发送加载消息
   * @param message 消息
   */
  postMessage(message: string | Resource) {
    const msgText = ResourceManager.getString(message);
    hilog.info(DOMAIN, TAG, 'Save database message:  %{public}s', msgText);
    if (this.callback && this.callback.onMessage) {
      this.callback.onMessage(msgText);
    }
  }

  /**
   * 发送失败消息
   * @param message 消息（原始文本或资源 ID，由消费方在其所在线程本地化）
   */
  postErrorMessage(message: string | number) {
    const msgText = ResourceManager.getString(message);
    if (this.callback && this.callback.onError) {
      this.callback.onError(msgText);
    }
  }

  /**
   * 发送成功消息
   * @param message 消息
   */
  postSuccessMessage(message: SuccessMessage) {
    if (this.callback && this.callback.onSuccess) {
      this.callback.onSuccess(message);
    }
  }

  /**
   * 发送冲突消息
   * @param message 冲突信息
   */
  postConflictMessage(message: ConflictMessage) {
    if (this.callback && this.callback.onConflict) {
      this.callback.onConflict(message);
    }
  }
}
