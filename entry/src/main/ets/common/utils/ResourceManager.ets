import { common } from '@kit.AbilityKit';


/**
 * 资源工具类
 */
export default class ResourceManager {
  private static instance: ResourceManager;
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
    if (!ResourceManager.instance) {
      ResourceManager.instance = new ResourceManager();
    }
    return ResourceManager.instance;
  }


  /**
   * 获取字符串
   * @param resource
   * @returns
   */
  public getString(resource: Resource): string {
    if (!this.context) {
      return '';
    }
    return this.context.resourceManager.getStringSync(resource.id);
  }
}