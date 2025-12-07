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
}