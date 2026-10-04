import { Kdbx, KdbxCredentials } from 'kdbxweb';
import { CredentialsService } from '../services/CredentialsService';
import { FileContentInfo } from '../storage';
import { KdbxLoadServiceCallback } from '../services/kdbx/KdbxLoadService';
import { LoadDatabase } from './DatabaseLoadWorkerParam';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { LoadMessage, SuccessMessage, toErrorMessage, toLoadMessage } from './WorkerParam';
import { KdbxUtils, HashUtils } from '../common/utils';

const DOMAIN = 0x0000;
const TAG = 'DatabaseLoad';

export class DatabaseLoad {
  /**
   * 加载数据库
   * @param request 请求参数
   * @param callback 回调
   */
  async handleLoadDatabase(request: LoadDatabase, callback?: KdbxLoadServiceCallback): Promise<void> {
    try {
      this.postMessage('creating_key', callback?.onLoadMessage);
      // 创建凭证
      let credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
      this.postMessage('loading_key', callback?.onLoadMessage);
      // 加载文件内容
      let fileContent: FileContentInfo = await this.loadKdbxFileContent(request);
      this.postMessage('validating', callback?.onLoadMessage);
      // 加载数据库
      let logTime = Date.now();
      let kdbx: Kdbx = await Kdbx.load(fileContent.content, credentials);
      hilog.debug(DOMAIN, TAG, "Load database cost time: %{public}d ms", Date.now() - logTime);

      this.postMessage('loading_complete', callback?.onLoadMessage);
      // 记录远端内容哈希与版本，作为后续保存的冲突检测基线
      const contentHash: string = await HashUtils.sha256Hex(fileContent.content);
      this.postSuccessMessage(new SuccessMessage(kdbx, fileContent.modifiedTime, false,
        fileContent.version ?? null, contentHash), callback?.onSuccessMessage);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Worker error loading database:%{public}s, stack:%{public}s', error.message, error.stack);
      this.postErrorMessage(KdbxUtils.kdbxErrorPayload(error), callback?.onErrorMessage);
    }
  }

  /**
   * 加载文件内容
   * @param request 请求
   * @return Promise<ArrayBuffer> 文件内容
   * @throws Error 加载失败
   */
  async loadKdbxFileContent(request: LoadDatabase): Promise<FileContentInfo> {
    if (!request.filePath) {
      hilog.error(DOMAIN, TAG, 'Worker error loading database: file path is empty');
      throw new Error();
    }
    let result = await new KdbxFileManager(request.storageType, request.storageConfig).read(request.filePath);
    this.postMessage('load_file_success');
    return result;
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