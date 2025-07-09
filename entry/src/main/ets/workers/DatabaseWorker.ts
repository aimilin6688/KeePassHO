import worker, { MessageEvents } from '@ohos.worker';
import { Kdbx, KdbxCredentials, KdbxError, ProtectedValue } from 'kdbxweb';

// 定义消息类型
export interface  WorkerMessage {
  type: string;
  data?: any;
}

// 定义数据库加载请求
export interface LoadDatabaseRequest {
  fileContent: ArrayBuffer;
  password: string;
  keyFileContent?: ArrayBuffer;
}

// 定义数据库加载结果
export interface LoadDatabaseResult {
  success: boolean;
  error?: {
    message: string;
    code?: string;
  };
}

// 初始化 worker
const workerPort = worker.workerPort;

// 监听主线程消息
workerPort.onmessage = (event: MessageEvents) => {
  const message: WorkerMessage = event.data;

  if (message.type === 'loadDatabase') {
    const request: LoadDatabaseRequest = message.data;
    handleLoadDatabase(request);
  }
};

// 处理数据库加载请求
async function handleLoadDatabase(request: LoadDatabaseRequest) {
  const result: LoadDatabaseResult = { success: false };

  try {
    // 创建凭证
    let credentials: KdbxCredentials;
    if (request.keyFileContent) {
      // 使用密码和密钥文件
      credentials = new KdbxCredentials(
        ProtectedValue.fromString(request.password),
        request.keyFileContent
      );
    } else {
      // 仅使用密码
      credentials = new KdbxCredentials(
        ProtectedValue.fromString(request.password)
      );
    }

    // 尝试加载数据库（仅验证，不保留结果）
    await Kdbx.load(request.fileContent, credentials);

    // 验证成功
    result.success = true;
  } catch (error) {
    // 验证失败
    result.success = false;
    if (error instanceof KdbxError) {
      result.error = {
        message: error.message,
        code: error.code
      };
    } else if (error instanceof Error) {
      result.error = {
        message: error.message
      };
    } else {
      result.error = {
        message: '未知错误'
      };
    }
  }

  // 发送结果回主线程
  workerPort.postMessage({
    type: 'loadDatabaseResult',
    data: result
  });
}

// 通知主线程 worker 已准备就绪
workerPort.postMessage({
  type: 'ready'
});
