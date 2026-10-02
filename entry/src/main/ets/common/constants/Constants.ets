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

  // --------------- 快速填充：解锁会话通知 ----------------
  /**
   * 常驻会话通知 ID（同 ID 重发即更新，不堆叠）
   */
  public static readonly SESSION_NOTIFY_ID: number = 0x1001;
  /**
   * 通知按钮：复制账号/密码 公共事件
   */
  public static readonly SESSION_ACTION_COPY_FIELD: string = "keepassho.action.COPY_FIELD";
  /**
   * 用户划掉会话通知 公共事件（removalWantAgent 发布）
   */
  public static readonly SESSION_ACTION_NOTIFY_REMOVED: string = "keepassho.action.SESSION_NOTIFY_REMOVED";
  /**
   * AppStorage 键：解锁会话是否进行中
   */
  public static readonly APP_STORAGE_SESSION_ACTIVE: string = "sessionActive";
  /**
   * 通知复制事件参数 fieldType：账号
   */
  public static readonly SESSION_FIELD_TYPE_USERNAME: string = "USERNAME";
  /**
   * 通知复制事件参数 fieldType：密码
   */
  public static readonly SESSION_FIELD_TYPE_PASSWORD: string = "PASSWORD";
}