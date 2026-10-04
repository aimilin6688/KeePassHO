import { worker } from '@kit.ArkTS';

/**
 * 数据库 Worker 工厂。
 *
 * useNormalizedOHMUrl 开启时 Worker 仅支持相对路径加载，且创建点必须与 Worker 文件同包；
 * 本工厂与 Worker 壳文件同目录，统一以 './' 相对路径创建，供服务层与单元测试共用，
 * 避免各处散写绝对模块路径（该形式在测试 HAP 环境会按 HSP 解析导致进程崩溃）。
 */
export class DatabaseWorkerFactory {
  /** 创建数据库加载 Worker */
  public static createLoadWorker(): worker.ThreadWorker {
    return new worker.ThreadWorker('./DatabaseLoadWorker.ets');
  }

  /** 创建数据库保存 Worker */
  public static createSaveWorker(): worker.ThreadWorker {
    return new worker.ThreadWorker('./DatabaseSaveWorker.ets');
  }
}
