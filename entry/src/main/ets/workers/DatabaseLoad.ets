import { Kdbx, KdbxCredentials, ErrorCodes, KdbxError } from 'kdbxweb';
import { CredentialsService } from '../services/CredentialsService';
import { FileInfo } from '../storage';
import { fileIo as fs } from '@kit.CoreFileKit';
import { KdbxLoadServiceCallback } from '../services/kdbx/KdbxLoadService';
import { AttachmentCacheService } from '../services/kdbx/AttachmentCacheService';
import { SessionFileService, SessionWrapWriter } from '../services/kdbx/SessionFileService';
import { LoadDatabase } from './DatabaseLoadWorkerParam';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { DatabaseLoadGuard, GuardCheckResult } from '../services/kdbx/DatabaseLoadGuard';
import { CommonUtils, HashUtils, KdbxUtils } from '../common/utils';
import { LoadMessage, SuccessMessage, toErrorMessage, toLoadMessage } from './WorkerParam';

const DOMAIN = 0x0000;
const TAG = 'DatabaseLoad';

export class DatabaseLoad {
  /**
    * 加载数据库
    * S4：readToFile 流式下载到 T0 文件 → Kdbx.loadFromFile 流式解密 T0→T1
    * S5：T1 native zlib 流式解压到 T2 → inner header 按文件解析，大附件分块落盘
    * 全程不持有远端内容/解压后载荷整缓冲（修 P5/P9）
    * @param request 请求参数
    * @param callback 回调
    */
  async handleLoadDatabase(request: LoadDatabase, callback?: KdbxLoadServiceCallback): Promise<void> {
    const t0Path: string = CommonUtils.getCacheDir() + '/load_t0_' + Date.now() + '.tmp';
    const t1Path: string = CommonUtils.getCacheDir() + '/load_t1_' + Date.now() + '.tmp';
    const t2Path: string = CommonUtils.getCacheDir() + '/load_t2_' + Date.now() + '.tmp';
    const tStart: number = Date.now();
    try {
      this.postMessage('creating_key', callback?.onLoadMessage);
      // 创建凭证
      let credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
      this.postMessage('loading_key', callback?.onLoadMessage);
      // 读前守卫 + 流式下载到 T0 文件（precheckSize 由调度层解析时跳过重复 getInfo）
      const tDownload: number = Date.now();
      let fileInfo: FileInfo = await this.loadKdbxFileToFile(request, t0Path);
      hilog.info(DOMAIN, TAG, 'load stage download: %{public}d ms, bytes=%{public}d',
        Date.now() - tDownload, fileInfo.size ?? 0);
      this.postMessage('validating', callback?.onLoadMessage);
      // 流式解密 T0→T1 → 流式解压 T1→T2 → parse（ChaCha20 v4 流式，AES-CBC/v3 退化整缓冲）
      const maxDecompressedBytes: number = await DatabaseLoadGuard.getMaxDecompressedBytes();
      // S4 附件磁盘化：大附件池转入加密缓存，内存仅保留哈希引用（store 不可用时纯内存模式）
      const attachmentStore = AttachmentCacheService.getStore();
      const attachmentsDiskThreshold = AttachmentCacheService.getAttachmentsDiskThreshold();

      // M0 v3 直传快路径（仅 Worker 运输模式启用）：解密解压后不建模型，
      // 原始 XML + 头部 + 池引用直传容器（SFW1 流式包裹），主线程只解析一次。
      // 非 v4+ChaCha20 抛 Unsupported → 回退全模型 KPSN 路径；其余错误原样上抛
      if (this.useContainerTransport()) {
        const wrapWriter: SessionWrapWriter = await SessionFileService.openWrapStream('m0_load_');
        try {
          const tContainer: number = Date.now();
          await Kdbx.loadToContainerFile(t0Path, credentials, {
            t1Path: t1Path,
            t2Path: t2Path,
            containerWriter: wrapWriter,
            maxDecompressedBytes: maxDecompressedBytes,
            attachmentStore: attachmentStore,
            attachmentsDiskThreshold: attachmentsDiskThreshold
          });
          const m0Path: string = await wrapWriter.close();
          hilog.info(DOMAIN, TAG, 'load stage container(v3 direct): %{public}d ms', Date.now() - tContainer);
          this.postMessage('loading_complete', callback?.onLoadMessage);
          // 流式 sha256 冲突检测基线（T0 文件 = 远端原始内容）
          const tHash: number = Date.now();
          const contentHash: string = await HashUtils.sha256HexFile(t0Path);
          hilog.info(DOMAIN, TAG, 'load stage sha256: %{public}d ms, bytes=%{public}d',
            Date.now() - tHash, fileInfo.size ?? 0);
          hilog.info(DOMAIN, TAG, 'load total: %{public}d ms', Date.now() - tStart);
          const containerMessage: SuccessMessage = new SuccessMessage(new ArrayBuffer(0),
            fileInfo.modifiedTime, false, fileInfo.version ?? null, contentHash);
          containerMessage.m0Path = m0Path;
          if (fileInfo.size > 0) {
            containerMessage.fileSize = fileInfo.size;
          }
          this.postSuccessMessage(containerMessage, callback?.onSuccessMessage);
          return;
        } catch (error) {
          // 释放半途包裹文件（残缺不可解包，清扫兜底；Worker 常驻防 fd 泄漏）
          await wrapWriter.abort();
          if (error instanceof KdbxError && error.code === ErrorCodes.Unsupported) {
            hilog.warn(DOMAIN, TAG, 'container fast-path fallback to model path: %{public}s', error.message);
          } else {
            throw error as Error;
          }
        }
      }

      const tParse: number = Date.now();
      let kdbx: Kdbx = await Kdbx.loadFromFile(t0Path, credentials,
        {
          maxDecompressedBytes: maxDecompressedBytes,
          t1Path: t1Path,
          t2Path: t2Path,
          attachmentStore: attachmentStore,
          attachmentsDiskThreshold: attachmentsDiskThreshold
        });
      hilog.info(DOMAIN, TAG, 'load stage parse(decrypt+inflate+xml): %{public}d ms', Date.now() - tParse);

      this.postMessage('loading_complete', callback?.onLoadMessage);
      // 流式 sha256 冲突检测基线（T0 文件 = 远端原始内容）
      const tHash: number = Date.now();
      const contentHash: string = await HashUtils.sha256HexFile(t0Path);
      hilog.info(DOMAIN, TAG, 'load stage sha256: %{public}d ms, bytes=%{public}d',
        Date.now() - tHash, fileInfo.size ?? 0);
      hilog.info(DOMAIN, TAG, 'load total: %{public}d ms', Date.now() - tStart);
      const successMessage: SuccessMessage = new SuccessMessage(kdbx, fileInfo.modifiedTime, false,
        fileInfo.version ?? null, contentHash);
      // 分级加载调度：压缩后大小随消息回传，主线程回填调度缓存与最近文件记录
      if (fileInfo.size > 0) {
        successMessage.fileSize = fileInfo.size;
      }
      this.postSuccessMessage(successMessage, callback?.onSuccessMessage);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Worker error loading database:%{public}s, stack:%{public}s', error.message, error.stack);
      this.postErrorMessage(KdbxUtils.kdbxErrorPayload(error), callback?.onErrorMessage);
    } finally {
      // 清理解密/解压临时文件（T0/T1/T2 用完即删）
      try {
        await fs.unlink(t0Path);
      } catch {
        // 文件不存在或清理失败：忽略
      }
      try {
        await fs.unlink(t1Path);
      } catch {
        // 文件不存在或清理失败：忽略
      }
      try {
        await fs.unlink(t2Path);
      } catch {
        // 文件不存在或清理失败：忽略
      }
    }
  }

  /**
   * 是否启用 M0 v3 直传容器运输（Worker 模式 true：解密解压后不建模型直传原始 XML；
   * 主线程同步模式 false：Kdbx 实例直接引用传递，零协议税）
   */
  protected useContainerTransport(): boolean {
    return false;
  }

  /**
   * 流式下载到本地文件（S4：readToFile 替代 read 整缓冲）
   * @param request 请求
   * @param destPath 本地目标文件路径
   * @return Promise<FileInfo> 远端文件信息
   * @throws Error 加载失败
   */
  async loadKdbxFileToFile(request: LoadDatabase, destPath: string): Promise<FileInfo> {
    if (!request.filePath) {
      hilog.error(DOMAIN, TAG, 'Worker error loading database: file path is empty');
      throw new Error();
    }
    // 单 manager 贯穿守卫与下载：一次 init 存储、令牌刷新结果随 config 原地传递
    const fileManager: KdbxFileManager = new KdbxFileManager(request.storageType, request.storageConfig);
    // 读前守卫（CP1 文件大小 / CP-DISK 磁盘余量）：拒绝时抛资源名；
    // precheckSize 已知时守卫复用该值，跳过重复 getInfo
    const guard: GuardCheckResult = await DatabaseLoadGuard.checkBeforeRead(fileManager, request.filePath,
      request.precheckSize);
    if (guard.rejectReason !== null) {
      throw new Error(guard.rejectReason);
    }
    const fileInfo: FileInfo = await fileManager.readToFile(request.filePath, destPath);
    this.postMessage('load_file_success');
    return fileInfo;
  }

  /**
   * 发送加载消息
   * @param message 资源名（如 'loading_key'），由消费方按名本地化
   */
  postMessage(message: string, onLoadMessage?: (message: LoadMessage) => void) {
    if (onLoadMessage) {
      onLoadMessage(toLoadMessage(message));
    }
  }

  /**
   * 发送失败消息
   * @param message 消息（原始文本或资源 ID，由消费方在其所在线程本地化）
   */
  postErrorMessage(message: string | number, onErrorMessage?: (message: LoadMessage) => void) {
    if (onErrorMessage) {
      onErrorMessage(toErrorMessage(message));
    }
  }

  /**
   * 发送成功消息
   * @param message 消息
   */
  postSuccessMessage(message: SuccessMessage, onSuccessMessage?: (message: SuccessMessage) => void) {
    if (onSuccessMessage) {
      onSuccessMessage(message);
    }
  }
}