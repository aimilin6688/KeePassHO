export class Constants {
  /**
   * 是否异步保存数据库
   */
  public static readonly ASYNC_SAVE_DATABASE: boolean = true;
  /**
   * 是否异步加载数据库
   */
  public static readonly ASYNC_LOAD_DATABASE: boolean = true;
  /**
   * 数据库 Worker 常驻池化（性能优化 #3）：true 时加载/保存 Worker 进程级常驻复用，
   * 消除每操作 isolate 冷启动（估 50-200ms）；false 时恢复每操作 terminate + 重建旧行为
   */
  public static readonly POOL_DATABASE_WORKER: boolean = true;

  // --------------- S4 附件磁盘化（内容寻址加密缓存） ----------------
  /**
   * 附件池总量达到该阈值时转入加密磁盘缓存（字节），低于阈值保持纯内存模式（小库零行为差异）
   */
  public static readonly ATTACH_DISK_THRESHOLD_BYTES: number = 16 * 1024 * 1024;
  /**
   * 附件加密缓存目录总占用上限（字节），超出按 LRU 清理
   */
  public static readonly ATTACH_CACHE_MAX_TOTAL_BYTES: number = 256 * 1024 * 1024;
  /**
   * 附件缓存加密密钥的 Asset Kit 别名
   */
  public static readonly ATTACH_CACHE_ASSET_ALIAS: string = "keepassho.attach.cache.key";
  /**
   * 附件缓存目录名（filesDir 下）
   */
  public static readonly ATTACH_CACHE_DIR_NAME: string = "attach-cache";
  /**
   * 编辑条目时单次最多可选附件数
   */
  public static readonly ATTACH_SELECT_MAX_COUNT: number = 9;

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