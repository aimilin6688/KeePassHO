import { Kdbx, KdbxCredentials } from 'kdbxweb';
import { CredentialsService } from '../services/CredentialsService';
import { FileInfo } from '../storage';
import { fileIo as fs } from '@kit.CoreFileKit';
import { KdbxLoadServiceCallback } from '../services/kdbx/KdbxLoadService';
import { LoadDatabase } from './DatabaseLoadWorkerParam';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { DatabaseLoadGuard } from '../services/kdbx/DatabaseLoadGuard';
import { CommonUtils, HashUtils, KdbxUtils } from '../common/utils';
import { LoadMessage, SuccessMessage, toErrorMessage, toLoadMessage } from './WorkerParam';

const DOMAIN = 0x0000;
const TAG = 'DatabaseLoad';

export class DatabaseLoad {
  /**
   * 加载数据库
   * S4：readToFile 流式下载到 T0 文件 → Kdbx.loadFromFile 流式解密 T0→T1 → ungzip → parse
   * 全程不持有远端内容整缓冲（修 P5/P9）
   * @param request 请求参数
   * @param callback 回调
   */
  async handleLoadDatabase(request: LoadDatabase, callback?: KdbxLoadServiceCallback): Promise<void> {
    const t0Path: string = CommonUtils.getCacheDir() + '/load_t0_' + Date.now() + '.tmp';
    const t1Path: string = CommonUtils.getCacheDir() + '/load_t1_' + Date.now() + '.tmp';
    try {
      this.postMessage('creating_key', callback?.onLoadMessage);
      // 创建凭证
      let credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
      this.postMessage('loading_key', callback?.onLoadMessage);
      // 读前守卫 + 流式下载到 T0 文件
      let fileInfo: FileInfo = await this.loadKdbxFileToFile(request, t0Path);
      this.postMessage('validating', callback?.onLoadMessage);
      // 流式解密 T0→T1 → ungzip → parse（ChaCha20 v4 流式，AES-CBC/v3 退化整缓冲）
      const maxDecompressedBytes: number = await DatabaseLoadGuard.getMaxDecompressedBytes();
      let logTime = Date.now();
      let kdbx: Kdbx = await Kdbx.loadFromFile(t0Path, credentials,
        { maxDecompressedBytes: maxDecompressedBytes, t1Path: t1Path });
      hilog.debug(DOMAIN, TAG, "Load database (from file) cost time: %{public}d ms", Date.now() - logTime);

      this.postMessage('loading_complete', callback?.onLoadMessage);
      // 流式 sha256 冲突检测基线（T0 文件 = 远端原始内容）
      const contentHash: string = await HashUtils.sha256HexFile(t0Path);
      this.postSuccessMessage(new SuccessMessage(kdbx, fileInfo.modifiedTime, false,
        fileInfo.version ?? null, contentHash), callback?.onSuccessMessage);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Worker error loading database:%{public}s, stack:%{public}s', error.message, error.stack);
      this.postErrorMessage(KdbxUtils.kdbxErrorPayload(error), callback?.onErrorMessage);
    } finally {
      // 清理解密临时文件（T0/T1 用完即删）
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
    }
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
    // 读前守卫（CP1 文件大小 / CP-DISK 磁盘余量）：拒绝时抛资源名
    const rejectReason: string | null = await DatabaseLoadGuard.checkBeforeRead(
      request.storageType, request.storageConfig, request.filePath);
    if (rejectReason !== null) {
      throw new Error(rejectReason);
    }
    const fileInfo: FileInfo = await new KdbxFileManager(request.storageType, request.storageConfig)
      .readToFile(request.filePath, destPath);
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