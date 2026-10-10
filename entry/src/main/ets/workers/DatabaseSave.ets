import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { CredentialsService } from '../services/CredentialsService';
import { FileContentInfo, TransferProgressCallback, WriteOption } from '../storage';
import { fileIo as fs } from '@kit.CoreFileKit';
import { StorageError, StorageErrorCodes } from '../storage/StorageError';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ConflictMessage, ProgressMessage, SuccessMessage } from './WorkerParam';
import { ProgressThrottler } from './ProgressThrottler';
import { ConflictStrategy, SaveDatabase, SaveDatabaseDbParam, SaveDatabaseMessage } from './DatabaseSaveWorkerParam';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { DatabaseLoadGuard, GuardCheckResult } from '../services/kdbx/DatabaseLoadGuard';
import { AttachmentCacheService } from '../services/kdbx/AttachmentCacheService';
import { SessionFileService } from '../services/kdbx/SessionFileService';
import { Constants } from '../common/constants/Constants';
import { CommonUtils, HashUtils, KdbxUtils, ResourceManager } from '../common/utils';
import { SaveDatabaseCallback } from './callback/SaveDatabaseCallback';
import { FileInfo } from '../storage';

const DOMAIN = 0x0000;
const TAG = 'DatabaseSave';

/**
 * 保存产物（S6 保存管道）：
 * - 流式路径（v4 + ChaCha20）：filePath 为 X3 落盘路径，buffer 为 null
 * - 回退路径（v3 / AES-CBC）：buffer 为整缓冲产物，filePath 为 null
 */
export class SavedContent {
  /** 落盘的 KDBX 文件路径（流式路径）；null 表示回退整缓冲 */
  readonly filePath: string | null;
  /** 整缓冲产物（回退路径）；null 表示流式路径 */
  readonly buffer: ArrayBuffer | null;

  constructor(filePath: string | null, buffer: ArrayBuffer | null) {
    this.filePath = filePath;
    this.buffer = buffer;
  }
}

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
  public async handleSaveDatabase(requestMessage: SaveDatabaseMessage): Promise<void> {
    const ts: number = Date.now();
    const t0: number = ts;
    // 远端临时文件（ciphertext，可放 cacheDir；finally 清理）
    const tempPath: string = CommonUtils.getCacheDir() + '/save_remote_' + ts + '.tmp';
    // S6 保存管道临时文件（X1 inner / X2 deflate / X3 成品，调用方管理生命周期）
    const savedPath: string = CommonUtils.getCacheDir() + '/save_x3_' + ts + '.tmp';
    const x1Path: string = CommonUtils.getCacheDir() + '/save_x1_' + ts + '.tmp';
    const x2Path: string = CommonUtils.getCacheDir() + '/save_x2_' + ts + '.tmp';
    try {
      const request = new SaveDatabase(JSON.parse(requestMessage.dbFileParam) as SaveDatabaseDbParam, requestMessage);
      this.postMessage('loading_key');
      // 创建凭证
      const credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
      // 单 manager 贯穿守卫/下载/写入/postSuccess：一次 init 存储、令牌刷新结果随 config 原地传递
      const fileManager: KdbxFileManager = new KdbxFileManager(request.storageType, request.storageConfig);
      const strategy: string = request.conflictStrategy ?? ConflictStrategy.AUTO;
      let retryCount = 0;
      // 守卫只跑一次：MERGE 写冲突重试时跳过（文件已在本操作内通过 CP1/CP-DISK，重跑无意义）
      let guardChecked = false;
      while (true) {
        // 读前守卫（CP1 文件大小 / CP-DISK 磁盘余量）：拒绝时抛资源名；
        // 预检 getInfo 结果随 GuardCheckResult 返回（版本预检快速路径复用，不产生额外请求）
        let guardInfo: FileInfo | null = null;
        if (!guardChecked) {
          const guard: GuardCheckResult = await DatabaseLoadGuard.checkBeforeRead(fileManager, request.filePath);
          if (guard.rejectReason !== null) {
            throw new Error(guard.rejectReason);
          }
          guardInfo = guard.fileInfo;
          guardChecked = true;
        }

        // 版本预检快速路径（能力协商，编排层零 provider 分支）：
        // 存储声明 version 可信 且 守卫预检版本与基线一致 → 跳过全量下载 + sha256 校验，
        // 直接条件写入；写前复核（WriteOption 契约）兜底预检与写入之间的远端并发修改
        const expectedVersion: string | null = request.expectedVersion ?? null;
        const fastPathHit: boolean = guardInfo !== null
          && expectedVersion !== null
          && guardInfo.version !== null && guardInfo.version !== undefined
          && guardInfo.version === expectedVersion
          && fileManager.supportsVersionFastPath();

        let fileInfo: FileInfo;
        let remoteChanged: boolean = false;
        if (fastPathHit && guardInfo !== null) {
          fileInfo = guardInfo;
          hilog.info(DOMAIN, TAG, 'save fast-path: hit (version matched, skip download+sha256)');
          this.postMessage('load_file_success');
        } else {
          if (guardInfo !== null) {
            hilog.info(DOMAIN, TAG, 'save fast-path: miss (version=%{public}s, expected=%{public}s)',
              guardInfo.version ?? 'null', expectedVersion ?? 'null');
          }
          // 流式下载到临时文件（不驻留整缓冲，修 P9）
          const tDownload: number = Date.now();
          fileInfo = await fileManager.readToFile(request.filePath, tempPath);
          hilog.info(DOMAIN, TAG, 'save stage download: %{public}d ms, bytes=%{public}d',
            Date.now() - tDownload, fileInfo.size ?? 0);
          this.postMessage('load_file_success');
          // 流式增量 sha256（分块喂入，不驻留整缓冲）
          const tHash: number = Date.now();
          const remoteHash: string = await HashUtils.sha256HexFile(tempPath);
          hilog.info(DOMAIN, TAG, 'save stage sha256: %{public}d ms, bytes=%{public}d',
            Date.now() - tHash, fileInfo.size ?? 0);
          remoteChanged = DatabaseSave.isRemoteChanged(request, fileInfo, remoteHash);
        }
        if (!remoteChanged) {
          // 远端未变：直接保存，远端内容不入内存
          const saved: SavedContent = await this.buildSavedContent(request, credentials, undefined,
            savedPath, x1Path, x2Path);
          let writtenInfo: FileInfo | null;
          try {
            writtenInfo = await this.writeSavedContent(request, saved, fileInfo.version ?? null, fileManager);
          } catch (error) {
            // 预检/下载与写入窗口内远端被并发修改（快速路径下窗口略增大）：
            // 重回循环按策略分发（AUTO 弹框 / MERGE 重新合并 / OVERWRITE 无条件写），而非直接报冲突耗尽
            if (error instanceof StorageError && error.code === StorageErrorCodes.VERSION_CONFLICT
              && retryCount < DatabaseSave.MAX_CONFLICT_RETRY) {
              retryCount++;
              hilog.warn(DOMAIN, TAG, 'No-conflict write conflict, re-dispatch by strategy, retry: %{public}d/%{public}d',
                retryCount, DatabaseSave.MAX_CONFLICT_RETRY);
              continue;
            }
            if (error instanceof Error) {
              throw error;
            }
            throw new Error(error.message);
          }
          await this.postSuccess(request, saved, false, fileManager, writtenInfo);
          hilog.info(DOMAIN, TAG, 'save total (no-conflict): %{public}d ms, mode=%{public}s',
            Date.now() - t0, saved.filePath !== null ? 'stream' : 'buffer');
          return;
        }
        if (strategy === ConflictStrategy.OVERWRITE) {
          // 用户已选择覆盖：丢弃远端修改，无条件写入本地内容
          const saved: SavedContent = await this.buildSavedContent(request, credentials, undefined,
            savedPath, x1Path, x2Path);
          const writtenInfo: FileInfo | null = await this.writeSavedContent(request, saved, null, fileManager);
          await this.postSuccess(request, saved, false, fileManager, writtenInfo);
          hilog.info(DOMAIN, TAG, 'save total (overwrite): %{public}d ms, mode=%{public}s',
            Date.now() - t0, saved.filePath !== null ? 'stream' : 'buffer');
          return;
        }
        if (strategy === ConflictStrategy.AUTO) {
          // 检测到冲突：通知上层（弹框让用户选择），本次不保存
          this.postConflictMessage(new ConflictMessage(fileInfo.modifiedTime, fileInfo.version ?? null));
          return;
        }
        // MERGE：流式加载远端（loadFromFile，不整读远端文件）→ 合并 → 写入
        const mergeT1Path: string = CommonUtils.getCacheDir() + '/merge_t1_' + ts + '.tmp';
        const mergeT2Path: string = CommonUtils.getCacheDir() + '/merge_t2_' + ts + '.tmp';
        const tMerge: number = Date.now();
        const mergedModel: Kdbx = await this.mergeDatabase(request, tempPath, credentials,
          mergeT1Path, mergeT2Path);
        hilog.info(DOMAIN, TAG, 'save stage merge-load: %{public}d ms', Date.now() - tMerge);
        const saved: SavedContent = await this.buildSavedContent(request, credentials, mergedModel,
          savedPath, x1Path, x2Path);
        let writtenInfo: FileInfo | null;
        try {
          writtenInfo = await this.writeSavedContent(request, saved, fileInfo.version ?? null, fileManager);
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
        await this.postSuccess(request, saved, true, fileManager, writtenInfo, mergedModel);
        hilog.info(DOMAIN, TAG, 'save total (merge): %{public}d ms, mode=%{public}s',
          Date.now() - t0, saved.filePath !== null ? 'stream' : 'buffer');
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
      // 清理管道临时文件（ciphertext + S6 保存中间态 + MERGE 流式加载中间态，用完即删）
      const tempFiles: string[] = [tempPath, savedPath, x1Path, x2Path,
        CommonUtils.getCacheDir() + '/merge_t1_' + ts + '.tmp',
        CommonUtils.getCacheDir() + '/merge_t2_' + ts + '.tmp'];
      for (const p of tempFiles) {
        try {
          await fs.unlink(p);
        } catch {
          // 文件不存在或清理失败：忽略
        }
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
   * S6 保存管道：v4 + ChaCha20 走 saveToFile 文件流式（deflate + encryptFromFile，内存与库大小解耦）；
   * v3 / AES-CBC 回退 save() 整缓冲。调用方据 SavedContent 选择 writeFromFile / write。
   * @param request 请求
   * @param credentials 凭证
   * @param kdbx 已有数据库对象（合并场景传入），不传则从请求数据反序列化
   * @param savedPath X3 成品路径（流式路径）
   * @param x1Path X1 inner 明文路径（流式路径）
   * @param x2Path X2 inner.gz 路径（流式路径）
   * @throws Error 保存失败
   */
  private async buildSavedContent(request: SaveDatabase, credentials: KdbxCredentials, kdbx?: Kdbx,
    savedPath?: string, x1Path?: string, x2Path?: string): Promise<SavedContent> {
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
    // S6 保存管道：v4 + ChaCha20 走文件流式（deflate + encryptFromFile），内存与库大小解耦；
    // v3 / AES-CBC 回退整缓冲 save()
    if (savedPath && x1Path && x2Path && database.canSaveToFile()) {
      await database.saveToFile(savedPath, { x1Path: x1Path, x2Path: x2Path });
      hilog.info(DOMAIN, TAG, 'save stage build(stream): %{public}d ms', new Date().getTime() - now);
      return new SavedContent(savedPath, null);
    }
    const savedDb: ArrayBuffer = await database.save().then(buf => {
      hilog.info(DOMAIN, TAG, 'save stage build(buffer): %{public}d ms', new Date().getTime() - now);
      return buf;
    });
    return new SavedContent(null, savedDb);
  }

  /**
   * 合并数据库：流式加载远端（loadFromFile，不整读远端文件）→ 合并进本地模型
   * S6 MERGE 流式化：loadFromFile 走 S4/S5 流式解密+解压+附件落盘管道，消除 peak ⑫（远端整缓冲）
   * @param request 请求
   * @param remoteFilePath 远端临时文件路径（已下载到本地）
   * @param credentials 凭证
   * @param t1Path MERGE 流式解密临时文件路径（调用方管理生命周期）
   * @param t2Path MERGE 流式解压临时文件路径（调用方管理生命周期）
   * @throws Error 合并失败（远端凭证变更时 loadFromFile 抛出 InvalidKey）
   */
  private async mergeDatabase(request: SaveDatabase, remoteFilePath: string,
    credentials: KdbxCredentials, t1Path: string, t2Path: string): Promise<Kdbx> {
    this.postMessage('validating');
    // 流式加载远端数据库（远端凭证已变更时抛出 InvalidKey，由上层统一转为用户提示）
    const maxDecompressedBytes: number = await DatabaseLoadGuard.getMaxDecompressedBytes();
    const remoteKdbx: Kdbx = await Kdbx.loadFromFile(remoteFilePath, credentials, {
      maxDecompressedBytes: maxDecompressedBytes,
      t1Path: t1Path,
      t2Path: t2Path,
      attachmentStore: AttachmentCacheService.getStore(),
      attachmentsDiskThreshold: Constants.ATTACH_DISK_THRESHOLD_BYTES
    });
    // 清理 MERGE 流式加载临时文件（T1/T2）
    for (const p of [t1Path, t2Path]) {
      try { await fs.unlink(p); } catch { /* 文件不存在或清理失败：忽略 */ }
    }
    this.postMessage('merging_database');
    // 合并数据库
    const localKdbx: Kdbx = await KdbxUtils.arrayBufferToKdbx(request.data, request, credentials);
    localKdbx.merge(remoteKdbx);
    return localKdbx;
  }

  /**
   * 写入保存产物：流式路径走 writeFromFile（分块上传），回退路径走 write（整缓冲）
   * @param request 请求
   * @param saved 保存产物
   * @param expectedVersion 期望的远端版本（条件写入），null 表示无条件写入
   * @param fileManager 贯穿本次操作的文件管理器
   * @returns 流式路径返回写入后的远端 FileInfo（writeFromFile 契约产物，含新版本基线）；
   *          回退路径 write 契约无返回值，返回 null
   * @throws Error 写入失败，版本冲突时抛出 StorageError(VERSION_CONFLICT)
   */
  private async writeSavedContent(request: SaveDatabase, saved: SavedContent, expectedVersion: string | null,
    fileManager: KdbxFileManager): Promise<FileInfo | null> {
    const tWrite: number = Date.now();
    if (saved.filePath !== null) {
      const option: WriteOption | undefined = expectedVersion !== null ? { expectedVersion: expectedVersion } : undefined;
      // 上传进度：成品尺寸已知 → 限频器转 PROGRESS 消息；存储不支持进度能力时无事件，行为不变
      const uploadTotalBytes: number = DatabaseSave.statFileSize(saved.filePath);
      const uploadThrottler: ProgressThrottler = new ProgressThrottler(uploadTotalBytes);
      const onUploadProgress: TransferProgressCallback = (transferredBytes: number, totalBytes: number): void => {
        const percent: number = uploadThrottler.onProgress(transferredBytes);
        if (percent >= 0) {
          this.postProgressMessage(new ProgressMessage(percent, transferredBytes, totalBytes));
        }
      };
      try {
        const writtenInfo: FileInfo = await fileManager.writeFromFile(request.filePath, saved.filePath, option,
          onUploadProgress);
        // 上传完成：补发末条 100%（S3 末片事件缺失等场景兜底；已发过 100% 或全程无事件时无操作）
        const finalPercent: number = uploadThrottler.finish();
        if (finalPercent >= 0) {
          this.postProgressMessage(new ProgressMessage(finalPercent, uploadTotalBytes, uploadTotalBytes));
        }
        this.postMessage('save_success');
        hilog.info(DOMAIN, TAG, 'save stage upload(stream): %{public}d ms', Date.now() - tWrite);
        return writtenInfo;
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Worker error save database (writeFromFile):%{public}s, stack:%{public}s', error.message, error.stack);
        if (error instanceof Error) {
          throw error;
        }
        throw new Error(error.message);
      }
    }
    const buffer = saved.buffer;
    if (buffer === null) {
      throw new Error('saved content is empty');
    }
    // 上传进度：整缓冲尺寸已知 → 限频器转 PROGRESS 消息；存储不支持进度能力时无事件，行为不变
    const uploadTotalBytes: number = buffer.byteLength;
    const uploadThrottler: ProgressThrottler = new ProgressThrottler(uploadTotalBytes);
    const onUploadProgress: TransferProgressCallback = (transferredBytes: number, totalBytes: number): void => {
      const percent: number = uploadThrottler.onProgress(transferredBytes);
      if (percent >= 0) {
        this.postProgressMessage(new ProgressMessage(percent, transferredBytes, totalBytes));
      }
    };
    await this.writeContent(request, buffer, expectedVersion, fileManager, onUploadProgress);
    // 上传完成：补发末条 100%（分片末片事件缺失等场景兜底；已发过 100% 或全程无事件时无操作）
    const finalPercent: number = uploadThrottler.finish();
    if (finalPercent >= 0) {
      this.postProgressMessage(new ProgressMessage(finalPercent, uploadTotalBytes, uploadTotalBytes));
    }
    hilog.info(DOMAIN, TAG, 'save stage upload(buffer): %{public}d ms, bytes=%{public}d',
      Date.now() - tWrite, buffer.byteLength);
    return null;
  }

  /**
   * 写入文件内容
   * @param request 请求
   * @param content 数据库内容
   * @param expectedVersion 期望的远端版本（条件写入），null 表示无条件写入
   * @param fileManager 贯穿本次操作的文件管理器
   * @param onProgress 上传进度回调（可选），透传给底层存储
   * @throws Error 写入失败，版本冲突时抛出 StorageError(VERSION_CONFLICT)
   */
  private async writeContent(request: SaveDatabase, content: ArrayBuffer, expectedVersion: string | null,
    fileManager: KdbxFileManager, onProgress?: TransferProgressCallback): Promise<void> {
    const option: WriteOption | undefined = expectedVersion !== null ? { expectedVersion: expectedVersion } : undefined;
    try {
      await fileManager.write(request.filePath, content, option, onProgress);
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
   * S6：流式路径分块哈希落盘文件；回退路径整缓冲哈希。
   * data 一律传空缓冲：Worker 消息序列化上限 16MB，大缓冲不随消息跨线程
   * （§7.4；主线程非合并不用 data，合并模型走 m0Path 会话文件还原）
   * @param request 请求
   * @param saved 保存产物
   * @param isMerge 是否发生了合并
   * @param fileManager 贯穿本次操作的文件管理器
   * @param writtenInfo 流式写入已返回的远端 FileInfo（免 getInfo 复用）；null 时回退 getInfo 获取
   * @param database 合并场景下的合并后模型（随消息以 KPSN 快照回传，主线程免解密重解析）
   */
  private async postSuccess(request: SaveDatabase, saved: SavedContent, isMerge: boolean,
    fileManager: KdbxFileManager, writtenInfo?: FileInfo | null, database?: Kdbx): Promise<void> {
    try {
      // 流式路径 writeFromFile 已返回写入后的 FileInfo（含新版本基线），不再重复 getInfo
      let fileInfo: FileInfo;
      if (writtenInfo !== null && writtenInfo !== undefined) {
        fileInfo = writtenInfo;
      } else {
        fileInfo = await fileManager.getInfo(request.filePath);
      }
      let contentHash: string;
      if (saved.filePath !== null) {
        contentHash = await HashUtils.sha256HexFile(saved.filePath);
      } else {
        const buffer = saved.buffer;
        if (buffer === null) {
          throw new Error('saved content is empty');
        }
        contentHash = await HashUtils.sha256Hex(buffer);
      }
      const data = new ArrayBuffer(0);
      const message = new SuccessMessage(data, fileInfo.modifiedTime, isMerge,
        fileInfo.version ?? null, contentHash);
      // 保存后远端尺寸可能剧增（新增附件等）：随消息回传新尺寸，
      // 主线程回填加载调度缓存与最近文件快照，避免下次加载仍按旧尺寸
      // 误判"小库"派发主线程（大库解密+解析阻塞 UI）
      let newSize: number = fileInfo.size ?? 0;
      if (newSize <= 0 && saved.buffer !== null) {
        newSize = saved.buffer.byteLength;
      }
      if (newSize > 0) {
        message.fileSize = newSize;
      }
      // 整缓冲回退路径的缓存回写：write() 写入时新版本未知，仅复制内容不更新元数据；
      // 此处携带写入后的远端事实刷新缓存+元数据，与流式 writeFromFile 的 refreshCache
      // 对齐，使"保存后立刻重载"命中版本快速路径（跳过全量下载）
      if (saved.buffer !== null) {
        await fileManager.refreshCacheFromBuffer(request.filePath, saved.buffer, fileInfo);
      }
      if (isMerge && database) {
        // §7.4：合并模型经会话密钥包裹落盘 M0，仅路径跨线程（KPSN ArrayBuffer 协议退役）
        const snapshotBytes: ArrayBuffer = await database.saveSnapshot();
        message.m0Path = await SessionFileService.wrapToFile(snapshotBytes, 'm0_merge_');
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
   * 读取本地文件尺寸（上传进度分母）；读取失败返回 0（限频器对 0 尺寸永不上报）
   * @param path 本地文件路径
   */
  private static statFileSize(path: string): number {
    try {
      return fs.statSync(path).size;
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'Stat saved file failed, upload progress disabled: %{public}s', error.message);
      return 0;
    }
  }

  /**
   * 发送传输进度消息（上传方向）
   * @param message 进度消息（纯数据，不含文案，由消费方组合展示）
   */
  postProgressMessage(message: ProgressMessage) {
    if (this.callback && this.callback.onProgress) {
      this.callback.onProgress(message);
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
