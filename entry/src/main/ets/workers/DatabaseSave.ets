import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { CredentialsService } from '../services/CredentialsService';
import { FileContentInfo, WriteOption } from '../storage';
import { FileTransfer } from '../storage/FileTransfer';
import { fileIo as fs } from '@kit.CoreFileKit';
import { StorageError, StorageErrorCodes } from '../storage/StorageError';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConflictMessage, SuccessMessage } from './WorkerParam';
import { ConflictStrategy, SaveDatabase, SaveDatabaseDbParam, SaveDatabaseMessage } from './DatabaseSaveWorkerParam';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { DatabaseLoadGuard } from '../services/kdbx/DatabaseLoadGuard';
import { CommonUtils, HashUtils, KdbxUtils, ResourceManager } from '../common/utils';
import { SaveDatabaseCallback } from './callback/SaveDatabaseCallback';
import { FileInfo } from '../storage';

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
   * S3：远端读取改为流式 readToFile 到临时文件 + 增量 sha256 冲突检测，
   * 远端未变时整条链路不持有远端内容（修 P9 内存峰值）
   * @param requestMessage 请求
   */
  public async handleSaveDatabase(requestMessage: SaveDatabaseMessage) {
    // 远端临时文件（ciphertext，可放 cacheDir；finally 清理）
    const tempPath: string = CommonUtils.getCacheDir() + '/save_remote_' + Date.now() + '.tmp';
    try {
      const request = new SaveDatabase(JSON.parse(requestMessage.dbFileParam) as SaveDatabaseDbParam, requestMessage);
      this.postMessage('loading_key');
      // 创建凭证
      const credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
      const strategy: string = request.conflictStrategy ?? ConflictStrategy.AUTO;
      let retryCount = 0;
      while (true) {
        // 读前守卫（CP1 文件大小 / CP-DISK 磁盘余量）：拒绝时抛资源名
        const rejectReason: string | null = await DatabaseLoadGuard.checkBeforeRead(
          request.storageType, request.storageConfig, request.filePath);
        if (rejectReason !== null) {
          throw new Error(rejectReason);
        }
        // 流式下载到临时文件（不驻留整缓冲，修 P9）
        const fileInfo: FileInfo = await new KdbxFileManager(request.storageType, request.storageConfig)
          .readToFile(request.filePath, tempPath);
        this.postMessage('load_file_success');
        // 流式增量 sha256（分块喂入，不驻留整缓冲）
        const remoteHash: string = await HashUtils.sha256HexFile(tempPath);
        const remoteChanged: boolean = DatabaseSave.isRemoteChanged(request, fileInfo, remoteHash);
        if (!remoteChanged) {
          // 远端未变：直接保存，远端内容不入内存
          const savedDb: ArrayBuffer = await this.buildSavedContent(request, credentials);
          await this.writeContent(request, savedDb, fileInfo.version ?? null);
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
          this.postConflictMessage(new ConflictMessage(fileInfo.modifiedTime, fileInfo.version ?? null));
          return;
        }
        // MERGE：从临时文件读入内存（S4 前仍整缓冲）→ Kdbx.load → 合并 → 写入
        const remoteContent: ArrayBuffer = await FileTransfer.readFileToBuffer(tempPath);
        const mergedModel: Kdbx = await this.mergeDatabase(request, remoteContent, credentials);
        const mergedDb: ArrayBuffer = await this.buildSavedContent(request, credentials, mergedModel);
        try {
          await this.writeContent(request, mergedDb, fileInfo.version ?? null);
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
        await this.postSuccess(request, mergedDb, true, mergedModel);
        return;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Worker error saving database:%{public}s, stack:%{public}s', error.message, error.stack);
      if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT) {
        // 重试耗尽仍冲突：远端正被持续写入，提示用户稍后重试，本地修改保留在内存中
        this.postErrorMessage('save_conflict_retry_exhausted');
      } else {
        this.postErrorMessage(KdbxUtils.kdbxErrorPayload(error));
      }
    } finally {
      // 清理远端临时文件（ciphertext，用完即删）
      try {
        await fs.unlink(tempPath);
      } catch {
        // 文件不存在或清理失败：忽略
      }
    }
  }

  /**
   * 判定远端文件是否已被修改（双基线）
   * 基线A：存储原生版本串（快速路径，可能为 null）
   * 基线B：内容 SHA256（最终裁判，永远执行；S3 起由调用方流式计算后传入）
   * @param request 请求
   * @param fileInfo 远端文件信息（含 version）
   * @param remoteHash 远端内容 SHA256（已由调用方流式计算）
   */
  private static isRemoteChanged(request: SaveDatabase, fileInfo: FileInfo, remoteHash: string): boolean {
    const baseHash: string | null = request.baseContentHash ?? null;
    if (baseHash !== null && remoteHash !== baseHash) {
      hilog.info(DOMAIN, TAG, 'Remote content changed: hash mismatch');
      return true;
    }
    const expectedVersion: string | null = request.expectedVersion ?? null;
    const remoteVersion: string | null = fileInfo.version ?? null;
    if (expectedVersion !== null && remoteVersion !== null && expectedVersion !== remoteVersion) {
      hilog.info(DOMAIN, TAG, 'Remote version changed: %{public}s -> %{public}s', expectedVersion, remoteVersion);
      return true;
    }
    return false;
  }

  /**
   * 构建待写入的数据库内容（凭证变更处理 + 加密保存）
   * @param request 请求
   * @param credentials 凭证
   * @param kdbx 已有数据库对象（合并场景传入），不传则从请求数据反序列化
   * @throws Error 保存失败
   */
  private async buildSavedContent(request: SaveDatabase, credentials: KdbxCredentials, kdbx?: Kdbx): Promise<ArrayBuffer> {
    this.postMessage('save_saving');
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
   * 合并数据库：远端修改合并进本地后返回合并模型（由调用方加密保存）
   * @param request 请求
   * @param fileContent 远端文件内容
   * @param credentials 凭证
  /**
   * 合并数据库：远端修改合并进本地后返回合并模型（由调用方加密保存）
   * S3 起远端内容由调用方从临时文件读入后传入（S4 流式解密前仍整缓冲）
   * @param request 请求
   * @param remoteContent 远端文件内容（ArrayBuffer）
   * @param credentials 凭证
   * @throws Error 合并失败（远端凭证变更时 Kdbx.load 抛出 InvalidKey）
   */
  private async mergeDatabase(request: SaveDatabase, remoteContent: ArrayBuffer,
    credentials: KdbxCredentials): Promise<Kdbx> {
    this.postMessage('validating');
    // 尝试加载远端数据库（远端凭证已变更时抛出 InvalidKey，由上层统一转为用户提示）
    const maxDecompressedBytes: number = await DatabaseLoadGuard.getMaxDecompressedBytes();
    const remoteKdbx: Kdbx = await Kdbx.load(remoteContent, credentials,
      { maxDecompressedBytes: maxDecompressedBytes });
    this.postMessage('merging_database');
    // 合并数据库
    const localKdbx: Kdbx = await KdbxUtils.arrayBufferToKdbx(request.data, request, credentials);
    localKdbx.merge(remoteKdbx);
    return localKdbx;
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
      this.postMessage('save_success');
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
   * @param database 合并场景下的合并后模型（随消息以 KPSN 快照回传，主线程免解密重解析）
   */
  private async postSuccess(request: SaveDatabase, content: ArrayBuffer, isMerge: boolean,
    database?: Kdbx): Promise<void> {
    const kdbxFileManager = new KdbxFileManager(request.storageType, request.storageConfig);
    try {
      const fileInfo = await kdbxFileManager.getInfo(request.filePath);
      const contentHash: string = await HashUtils.sha256Hex(content);
      const message = new SuccessMessage(content, fileInfo.modifiedTime, isMerge,
        fileInfo.version ?? null, contentHash);
      if (isMerge && database) {
        message.snapshot = await database.saveSnapshot();
      }
      this.postSuccessMessage(message);
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
   * @param message 资源名（如 'save_saving'），由消费方按名本地化
   */
  postMessage(message: string) {
    const msgText = ResourceManager.getMessage(message);
    hilog.info(DOMAIN, TAG, 'Save database message:  %{public}s', msgText);
    if (this.callback && this.callback.onMessage) {
      this.callback.onMessage(msgText);
    }
  }

  /**
   * 发送失败消息
   * @param message 消息（资源名或原始文本，由消费方按名本地化、原文透传）
   */
  postErrorMessage(message: string | number) {
    const msgText = ResourceManager.getMessage(message);
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
