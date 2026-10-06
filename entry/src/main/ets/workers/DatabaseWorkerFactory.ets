import { worker } from '@kit.ArkTS';
import { CommonUtils } from '../common/utils';
import { CacheConstants } from '../storage/cache/CacheConstants';
import { AttachmentCacheService } from '../services/kdbx/AttachmentCacheService';
import { SessionFileService } from '../services/kdbx/SessionFileService';
import { InitWorkerMessage } from './WorkerParam';

/**
 * 数据库 Worker 工厂。
 *
 * useNormalizedOHMUrl 开启时 Worker 仅支持相对路径加载，且创建点必须与 Worker 文件同包；
 * 本工厂与 Worker 壳文件同目录，统一以 './' 相对路径创建，供服务层与单元测试共用，
 * 避免各处散写绝对模块路径（该形式在测试 HAP 环境会按 HSP 解析导致进程崩溃）。
 *
 * 创建后立即注入主线程沙箱路径与缓存策略快照：Actor 模型下 Worker 线程无
 * Context/AppStorage/preferences，存储层所需的 filesDir/cacheDir 与缓存策略只能以
 * 快照形式传入；消息按序处理，初始化消息先于任何任务消息。
 */
export class DatabaseWorkerFactory {
  /** 创建数据库加载 Worker */
  public static createLoadWorker(): worker.ThreadWorker {
    const w = new worker.ThreadWorker('./DatabaseLoadWorker.ets');
    // 加载 Worker 的消息通道为 JSON 字符串（见 DatabaseLoadWorker.onmessage）
    w.postMessage(JSON.stringify(DatabaseWorkerFactory.buildInitMessage()));
    return w;
  }

  /** 创建数据库保存 Worker */
  public static createSaveWorker(): worker.ThreadWorker {
    const w = new worker.ThreadWorker('./DatabaseSaveWorker.ets');
    // 保存 Worker 的消息通道为结构化克隆对象（见 DatabaseSaveWorker.onmessage）
    w.postMessage(DatabaseWorkerFactory.buildInitMessage());
    return w;
  }

  private static buildInitMessage(): InitWorkerMessage {
    // forceRefresh 为一次性标志：创建 Worker 时在主线程消费，
    // 避免快照在 Worker 内无法回写主线程 AppStorage 导致标志粘连
    const forceRefresh: boolean = CacheConstants.getForceRefresh();
    if (forceRefresh) {
      CacheConstants.clearForceRefresh();
    }
    // 附件缓存密钥主线程解析（Asset Kit），Worker 线程仅使用注入快照
    const attachCacheKey: string = AttachmentCacheService.getWorkerKeyBase64();
    // §7.4：会话密钥与会话目录主线程生成，Worker 经注入共享（isolate 静态不共享）
    return new InitWorkerMessage(CommonUtils.getAppFilesDir(), CommonUtils.getCacheDir(),
      CacheConstants.isEnableLocalCache(), CacheConstants.getOnlyCache(), forceRefresh, attachCacheKey,
      SessionFileService.getWorkerKeyBase64(), SessionFileService.getSessionDir());
  }
}
