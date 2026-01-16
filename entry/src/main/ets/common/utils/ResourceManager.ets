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
   * 初始化主题管理器
   * @param context UIAbilityContext
   */
  public init(context: common.UIAbilityContext): void {
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
}