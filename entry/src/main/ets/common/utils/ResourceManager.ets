import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'ResourceManager';

/**
 * 资源工具类
 */
export class ResourceManager {
  private static instance: ResourceManager = new ResourceManager();
  private context: common.UIAbilityContext | null = null;

  private constructor() {
  }

  /**
   * 初始化资源管理器；传 null 清空已初始化的上下文（测试隔离用）
   * @param context UIAbilityContext，传 null 表示清除
   */
  public init(context: common.UIAbilityContext | null): void {
    this.context = context;
  }

  /**
   * 获取单例实例
   */
  public static getInstance(): ResourceManager {
    return ResourceManager.instance;
  }


  /**
   * 获取字符串
   * @param resource
   * @returns
   */
  public getString(resource: Resource | number | string, ...args: Array<string | number>): string {
    if (typeof resource === 'string') {
      return resource;
    }
    if (!this.context) {
      return '';
    }
    try {
      if (typeof resource === 'number') {
        return this.context.resourceManager.getStringSync(resource, ...args);
      }
      return this.context.resourceManager.getStringSync(resource.id, ...args);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `load resource error: ${resource}, ${e.message}`);
      return e.message;
    }
  }

  /**
   * 获取字符串
   * @param resource 资源
   * @returns 结果
   */
  public static getString(resource: Resource | number | string, ...args: Array<string | number>): string {
    try {
      return ResourceManager.getInstance().getString(resource, ...args);
    } catch (e) {
      hilog.error(DOMAIN, TAG, `load resource error: ${resource}, ${e.message}`);
      return resource.toString();
    }
  }

  /**
   * 解析跨线程消息：worker 传资源名（如 'loading_key'）或原始文本，
   * 按名解析可免疫多 HAP/测试包场景下资源 ID 漂移（default 与 ohosTest
   * 构建变体对同名资源分配不同包前缀的 ID）；解析失败时原文透传。
   * @param message 资源名或原始文本
   * @returns 本地化文本
   */
  public getMessage(message: string | number): string {
    if (typeof message === 'number') {
      return this.getString(message);
    }
    if (!this.context) {
      return message;
    }
    try {
      return this.context.resourceManager.getStringByNameSync(message);
    } catch (e) {
      hilog.debug(DOMAIN, TAG, `resolve message by name fail, passthrough: %{public}s`, message);
      return message;
    }
  }

  /**
   * 解析跨线程消息（静态入口）
   * @param message 资源名或原始文本
   * @returns 本地化文本
   */
  public static getMessage(message: string | number): string {
    return ResourceManager.getInstance().getMessage(message);
  }
}