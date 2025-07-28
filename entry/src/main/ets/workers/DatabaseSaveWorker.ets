import { MessageEvents, ThreadWorkerGlobalScope, worker } from '@kit.ArkTS';
import { Kdbx, KdbxCredentials } from 'kdbxweb';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import KdbxUtils from '../common/utils/KdbxUtils';
import { CredentialsService } from '../services/CredentialsService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileContentInfo } from '../services/kdbx/interfaces';
import { MessageType, WorkerMessage, SuccessMessage, toErrorMessage, toLoadMessage } from './WorkerParam';
import { SaveDatabase, SaveDatabaseDbParam, SaveDatabaseMessage } from './DatabaseSaveWorkerParam';

const DOMAIN = 0x0000;
const TAG = 'DatabaseSaveWorker';
// 初始化 worker
const workerPort: ThreadWorkerGlobalScope = worker.workerPort;

// 监听主线程消息
workerPort.onmessage = (event: MessageEvents) => {
  hilog.info(DOMAIN, TAG, 'Worker receive message: %{public}s', event.data)
  const message = event.data as WorkerMessage;
  if (message.type === MessageType.SAVE_DATABASE) {
    const request = message as SaveDatabaseMessage;
    handleSaveDatabase(request);
  }
};

/**
 * 处理数据库保存任务
 * @param request 请求
 */
async function handleSaveDatabase(requestMessage: SaveDatabaseMessage) {
  try {
    let request = new SaveDatabase(JSON.parse(requestMessage.dbFileParam) as SaveDatabaseDbParam, requestMessage);
    postMessage($r('app.string.loading_key'));
    // 创建凭证
    let credentials: KdbxCredentials = await CredentialsService.createKdbxCredentials(request);
    // 加载文件内容
    let fileContent: FileContentInfo = await loadKdbxFileContent(request);
    // 修改时间不一致，则合并数据库
    if (fileContent.modifiedTime !== request.modifiedTime) {
      postMessage($r('app.string.merging_database'));
      fileContent = await mergeDatabase(request, fileContent, credentials);
    } else {
      fileContent = await saveDatabase(request, credentials);
    }
    postMessage($r('app.string.loading_complete'));
    workerPort.postMessage(new SuccessMessage(fileContent.content, fileContent.modifiedTime), [fileContent.content]);
  } catch (error) {
    hilog.error(DOMAIN, TAG, 'Worker error loading database:%{public}s, stack:%{public}s', error.message, error.stack);
    postErrorMessage(error.message);
  }
}

/**
 * 合并数据库
 * @param request 请求
 * @param fileContent 新文件内容
 */
async function mergeDatabase(request: SaveDatabase, fileContent: FileContentInfo,
  credentials: KdbxCredentials): Promise<FileContentInfo> {
  // 校验文件签名
  postMessage($r('app.string.validating'));
  // 尝试加载数据库（仅验证，不保留结果）
  let newKdbx: Kdbx = await Kdbx.load(fileContent.content, credentials);
  postMessage($r('app.string.merging_database'));
  // 合并数据库
  let oldKdbx: Kdbx = await KdbxUtils.arrayBufferToKdbx(request.data, request, credentials);
  oldKdbx.merge(newKdbx);
  // 设置数据库内容为新内容
  request.data = await KdbxUtils.kdbxToArrayBuffer(oldKdbx);
  // 保存数据库
  return saveDatabase(request, credentials);
}

/**
 * 保存数据库
 * @param request 请求
 * @returns 结果
 */
async function saveDatabase(request: SaveDatabase, credentials: KdbxCredentials): Promise<FileContentInfo> {
  postMessage($r('app.string.save_saving'));
  let database: Kdbx = await KdbxUtils.arrayBufferToKdbx(request.data, request, credentials);

  let kdbxFileManager = new KdbxFileManager(request.storageType, request.storageConfig);
  return database.save().then(async savedDb => {
    await kdbxFileManager.saveKdbxFile(request.filePath, savedDb);
    return await kdbxFileManager.getKdbxFileInfo(request.filePath).then(fileInfo => {
      return new FileContentInfo(fileInfo, savedDb);
    });
  });
}

/**
 * 加载文件内容
 * @param request 请求
 * @return Promise<ArrayBuffer> 文件内容
 */
async function loadKdbxFileContent(request: SaveDatabase): Promise<FileContentInfo> {
  if (!request.filePath) {
    hilog.error(DOMAIN, TAG, 'Worker error loading database: file path is empty');
    throw new Error();
  }
  let result = await new KdbxFileManager(request.storageType, request.storageConfig).loadKdbxFile(request.filePath);
  postMessage($r('app.string.load_file_success'));
  return result;
}

/**
 * 发送加载消息给主线程
 * @param message 消息
 */
function postMessage(message: string | Resource) {
  workerPort.postMessage(toLoadMessage(message));
}

/**
 * 发送加载消息给主线程
 * @param message 消息
 */
function postErrorMessage(message: string) {
  workerPort.postMessage(toErrorMessage(message));
}


