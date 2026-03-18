export class Constants {
  /**
   * 是否异步保存数据库
   */
  public static readonly ASYNC_SAVE_DATABASE: boolean = false;
  /**
   * 是否异步加载数据库
   */
  public static readonly ASYNC_LOAD_DATABASE: boolean = false;

  /**
   * 应用存储位置信息
   */
  public static readonly APP_STORAGE_LOCATION_INFO: string = "locationInfo";

  /**
   * 预加载的最近文件信息（用于冷启动优化）
   */
  public static readonly APP_STORAGE_PRELOAD_RECENT_FILE: string = "preloadRecentFile";

  /**
   * 预加载是否完成（用于冷启动优化）
   */
  public static readonly APP_STORAGE_PRELOAD_READY: string = "preloadReady";
}