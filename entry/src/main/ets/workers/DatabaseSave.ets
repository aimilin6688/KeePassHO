import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { CredentialsService } from '../services/CredentialsService';
import { FileContentInfo } from '../services/kdbx/interfaces';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SuccessMessage } from './WorkerParam';
import { SaveDatabase, SaveDatabaseDbParam, SaveDatabaseMessage } from './DatabaseSaveWorkerParam';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import ResourceManager from '../common/utils/ResourceManager';
import KdbxUtils from '../common/utils/KdbxUtils';
import { SaveDatabaseCallback } from './callback/SaveDatabaseCallback';

const DOMAIN = 0x0000;
const TAG = 'DatabaseLoad';

/**
 * 保存数据库
 */
export class DatabaseSave {
  private callback?: SaveDatabaseCallback = undefined;

  constructor(callback?: SaveDatabaseCallback) {
    this.callback = callback;
  }

  /**
   * 处理数据库保存任务
   * @param request 请求
   */
  public async handleSaveDatabase(requestMessage: SaveDatabaseMessage) {
    try {
      let request = new SaveDatabase(JSON.parse(requestMessage.dbFileParam) as SaveDatabaseDbParam, requestMessage);
      this.postMessage($r('app.string.loading_key'));
      // 创建凭证
      let credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
      // 加载文件内容
      let fileContent: FileContentInfo = await this.loadKdbxFileContent(request);
      let isMerge = false;
      // 修改时间不一致，则合并数据库
      if (fileContent.modifiedTime !== request.modifiedTime) {
        this.postMessage($r('app.string.merging_database'));
        fileContent = await this.mergeDatabase(request, fileContent, credentials);
        isMerge = true;
      } else {
        fileContent = await this.saveDatabase(request, credentials);
      }
      this.postSuccessMessage(new SuccessMessage(fileContent.content, fileContent.modifiedTime, isMerge));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Worker error loading database:%{public}s, stack:%{public}s', error.message, error.stack);
      this.postErrorMessage(KdbxUtils.kdbxErrorMessage(error));
    }
  }

  /**
   * 加载文件内容
   * @param request 请求
   * @return Promise<ArrayBuffer> 文件内容
   */
  private async loadKdbxFileContent(request: SaveDatabase): Promise<FileContentInfo> {
    if (!request.filePath) {
      hilog.error(DOMAIN, TAG, 'Worker error loading database: file path is empty');
      throw new Error();
    }
    let result = await new KdbxFileManager(request.storageType, request.storageConfig).read(request.filePath);
    this.postMessage($r('app.string.load_file_success'));
    return result;
  }


  /**
   * 合并数据库
   * @param request 请求
   * @param fileContent 新文件内容
   */
  private async mergeDatabase(request: SaveDatabase, fileContent: FileContentInfo, credentials: KdbxCredentials): Promise<FileContentInfo> {
    // 校验文件签名
    this.postMessage($r('app.string.validating'));
    // 尝试加载数据库（仅验证，不保留结果）
    let newKdbx: Kdbx = await Kdbx.load(fileContent.content, credentials);
    this.postMessage($r('app.string.merging_database'));
    // 合并数据库
    let oldKdbx: Kdbx = await KdbxUtils.arrayBufferToKdbx(request.data, request, credentials);
    oldKdbx.merge(newKdbx);
    // 保存数据库
    return await this.saveDatabase(request, credentials, oldKdbx);
  }


  /**
   * 保存数据库
   * @param request 请求
   * @returns 结果
   */
  private async saveDatabase(request: SaveDatabase, credentials: KdbxCredentials, kdbx?: Kdbx): Promise<FileContentInfo> {
    this.postMessage($r('app.string.save_saving'));
    let database: Kdbx = kdbx ? kdbx : await KdbxUtils.arrayBufferToKdbx(request.data, request, credentials);
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
    let kdbxFileManager = new KdbxFileManager(request.storageType, request.storageConfig);
    const now = new Date().getTime();
    return await database.save().then(async savedDb => {
      hilog.debug(DOMAIN, TAG, 'Worker save database success, time: %{public}d ms', new Date().getTime() - now);
      await kdbxFileManager.write(request.filePath, savedDb).then(() => {
        this.postMessage($r("app.string.save_success"));
      });
      return await kdbxFileManager.getInfo(request.filePath).then(fileInfo => {
        return new FileContentInfo(fileInfo, savedDb);
      });
    });
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
   * @param message 消息
   */
  postErrorMessage(message: string) {
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
}