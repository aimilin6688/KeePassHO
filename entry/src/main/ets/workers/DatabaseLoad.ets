import { Kdbx, KdbxCredentials } from 'kdbxweb';
import { CredentialsService } from '../services/CredentialsService';
import { FileContentInfo } from '../services/kdbx/interfaces';
import { KdbxLoadServiceCallback } from '../services/kdbx/KdbxLoadService';
import { LoadDatabase } from './DatabaseLoadWorkerParam';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { LoadMessage, SuccessMessage, toLoadMessage } from './WorkerParam';
import KdbxUtils from '../common/utils/KdbxUtils';

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
      this.postMessage($r('app.string.creating_key'), callback?.onLoadMessage);
      // 创建凭证
      let credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
      this.postMessage($r('app.string.loading_key'), callback?.onLoadMessage);
      // 加载文件内容
      let fileContent: FileContentInfo = await this.loadKdbxFileContent(request);
      this.postMessage($r('app.string.validating'), callback?.onLoadMessage);
      // 加载数据库
      let logTime = Date.now();
      let kdbx: Kdbx = await Kdbx.load(fileContent.content, credentials);
      hilog.debug(DOMAIN, TAG, "Load database cost time: %{public}d ms", Date.now() - logTime);

      this.postMessage($r('app.string.loading_complete'), callback?.onLoadMessage);
      this.postSuccessMessage(new SuccessMessage(kdbx, fileContent.modifiedTime), callback?.onSuccessMessage);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Worker error loading database:%{public}s, stack:%{public}s', error.message, error.stack);
      this.postErrorMessage(KdbxUtils.kdbxErrorMessage(error), callback?.onErrorMessage);
    }
  }

  /**
   * 加载文件内容
   * @param request 请求
   * @return Promise<ArrayBuffer> 文件内容
   */
  async loadKdbxFileContent(request: LoadDatabase): Promise<FileContentInfo> {
    if (!request.filePath) {
      hilog.error(DOMAIN, TAG, 'Worker error loading database: file path is empty');
      throw new Error();
    }
    let result = await new KdbxFileManager(request.storageType, request.storageConfig).loadKdbxFile(request.filePath);
    this.postMessage($r('app.string.load_file_success'));
    return result;
  }

  /**
   * 发送加载消息
   * @param message 消息
   */
  postMessage(message: string | Resource, onLoadMessage?: (message: LoadMessage) => void) {
    if (onLoadMessage) {
      onLoadMessage(toLoadMessage(message));
    }
  }

  /**
   * 发送失败消息
   * @param message 消息
   */
  postErrorMessage(message: string, onErrorMessage?: (message: LoadMessage) => void) {
    if (onErrorMessage) {
      onErrorMessage(toLoadMessage(message));
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