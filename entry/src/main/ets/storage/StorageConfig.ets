
import { ChildDbSupport } from './ChildDbSupport';

/**
 * 存储配置接口
 */
export interface StorageConfig {}

/**
 * 页面配置信息
 */
export interface PageConfig {
  /**
   * 存储类型图标
   */
  icon: Resource;

  /**
   * 存储类型名称
   */
  title: ResourceStr;

  /**
   * 选择时存储类型描述
   */
  selectDesc: ResourceStr;

  /**
   * 保存时存储类型描述
   */
  saveDesc: ResourceStr;

  /**
   * 跳转页面路径
   */
  pageUrl: string;

  /**
   * 存储类型
   */
  storageType: string;

  /**
   * UI 测试定位用的组件标识（可选）
   */
  id?: string;

  /**
   * 子库支持适配器（M6.9，可选）：声明即接入子库链路——框架经
   * FileStorageFactory 注册表发现本声明，按适配器 schemes 路由其
   * parseTarget/buildUrl 解析/构造条目 URL（文法内聚于各适配器）。
   * 新存储接入子库只需在自身 PageConfig 加一行 childDb 声明
   * （OAuth 型 new PathChildDbSupport(storageType, 'scheme')）；凭据型
   * 在自身模块实现 ChildDbSupport 适配器类（rebuildConfig/
   * extractCredentials/extraFields 均可选）。
   */
  childDb?: ChildDbSupport;
}
