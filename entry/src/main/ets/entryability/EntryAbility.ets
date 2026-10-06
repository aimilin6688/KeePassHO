import { AbilityConstant, contextConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SettingsService } from '../services/SettingsService';
import { CommonUtils, FilenameUtils, ResourceManager, Sm4Utils, ThemeManager } from '../common/utils';
import { RecentFilesService } from '../services/RecentFilesService';
import { FileService } from '../services/FileService';
import { LocalFileStorageConfig, StorageType } from '../storage';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from '../common/constants/Constants';
import { SupportService } from '../services/SupportService';
import { DistributedKVService } from '../services/store/DistributedKVService';
import { SyncSettingsService } from '../services/store/SyncSettingsService';
import { DialogHelper } from '@pura/harmony-dialog';
import { CrashLogService } from '../services/CrashLogService';
import { LockScreenService } from '../services/LockScreenService';
import { NavigationManager } from '../common/utils/NavigationManager';
import { ClipboardUtils } from '../common/utils/ClipboardUtils';
import { SessionManager } from '../services/SessionManager';
import { CopyEventService } from '../services/CopyEventService';
import { TempFileSweeper } from '../services/kdbx/TempFileSweeper';
import { SessionFileService } from '../services/kdbx/SessionFileService';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

export const storage: LocalStorage = new LocalStorage();

/**
 * 入口Ability
 */
export default class EntryAbility extends UIAbility {
  // 记录进入后台的时间戳
  private backgroundTime: number = 0;
  private createUrl: string | undefined = undefined;
  private windowStage: window.WindowStage | undefined = undefined;
  public static instance: EntryAbility | null = null;

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Ability onCreate %{public}s', want.uri);
    EntryAbility.instance = this;
    this.createUrl = want.uri;
    // 将 context 存入 AppStorage 供其他组件使用
    AppStorage.setOrCreate('context', this.context);
    // 初始化核心服务 + 并行预加载
    this.init();
  }

  /**
   * 初始化应用
   * 优化策略：
   * 1. 核心服务同步初始化（冷启动必需）
   * 2. 非核心服务延迟初始化
   * 3. 预加载最近文件信息，加速生物认证调用
   */
  private async init() {
    this.context.area = contextConstant.AreaMode.EL4;

    // 核心服务同步初始化（UI渲染必需）
    CommonUtils.init(this.context);
    ThemeManager.getInstance().init(this.context);
    ResourceManager.getInstance().init(this.context);

    // S7-b：清扫上次运行的管道临时文件残留（崩溃/被杀遗留），不阻塞启动
    TempFileSweeper.sweep();
    // §7.4/§8：清扫超期 session-* 会话目录（M0 会话文件），不阻塞启动
    SessionFileService.sweep();

    // 启动关键服务预加载（并行执行，不阻塞主线程）
    this.preloadEssentialServices();
  }

  /**
   * 预加载关键服务
   * 这些服务是 Password 页面启动生物认证所必需的
   */
  private async preloadEssentialServices(): Promise<void> {
    const startTime = Date.now();

    try {
      // 1. 初始化最近文件服务
      RecentFilesService.getInstance().init(this.context);

      // 2. 初始化设置服务（生物认证需要）
      await SettingsService.getInstance().init(this.context);
      SupportService.initAppInstallTime();

      // 3. 预加载最近文件信息（并行执行）
      const recentFile = await RecentFilesService.getInstance().loadMostRecentFile();

      // 4. 存储预加载结果到 AppStorage
      if (recentFile) {
        AppStorage.setOrCreate(Constants.APP_STORAGE_PRELOAD_RECENT_FILE, recentFile);
        hilog.info(DOMAIN, TAG, 'Preload recent file success: %{public}s', recentFile.filePath);
      }

      // 5. 标记预加载完成
      AppStorage.setOrCreate(Constants.APP_STORAGE_PRELOAD_READY, true);

      hilog.info(DOMAIN, TAG, 'Preload completed in %{public}d ms', Date.now() - startTime);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Preload failed: %{public}s', error.message);
      // 即使预加载失败也标记完成，避免阻塞
      AppStorage.setOrCreate(Constants.APP_STORAGE_PRELOAD_READY, true);
    }

    // 非核心服务延迟初始化
    setTimeout(() => {
      this.initNonEssentialServices();
    }, 100);
  }

  /**
   * 非核心服务延迟初始化
   */
  private async initNonEssentialServices(): Promise<void> {
    // 初始化加解密KEY
    Sm4Utils.init();
    // 初始化分布式同步服务
    await SyncSettingsService.initSync(this.context);
    // 初始化崩溃日志服务
    CrashLogService.getInstance().init(this.context);
    // 初始化弹框
    DialogHelper.setDefaultConfig((config) => {
      config.uiAbilityContext = this.context;
    });
    // 初始化解锁会话通知（SessionManager 监听解锁/锁库事件）
    SessionManager.getInstance().init();
    // 初始化通知栏快捷复制公共事件订阅
    await CopyEventService.getInstance().init();
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
    EntryAbility.instance = null;
    FileService.close();
    DistributedKVService.close();
    // S7-b：退出前同步清扫管道临时文件（进程即将销毁，异步可能来不及执行）
    TempFileSweeper.sweepSync();
    // §7.4/§8：退出前全清 session-* 会话目录与会话密钥（密钥随进程消亡，残留不可解密）
    SessionFileService.clearAllSync();
    // 取消订阅崩溃事件
    CrashLogService.getInstance().unsubscribeCrashEvent();
    // 清理会话通知与公共事件订阅
    SessionManager.getInstance().destroy();
    CopyEventService.getInstance().destroy();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    this.windowStage = windowStage;

    // 初始化锁屏服务
    LockScreenService.init(windowStage, (action: string) => {
      if (action === 'close_database') {
        // 关闭数据库后，导航回 Index 页面
        NavigationManager.getInstance().navigateBackToRoot('Index');
      }
    });

    // 通过URL打开数据库
    if (this.createUrl) {
      this.openDatabase(this.createUrl);
    } else {
      this.openPage('pages/AppNavigation');
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
    LockScreenService.destroy();
    this.windowStage = undefined;
    this.createUrl = undefined;
  }

  onForeground(): void {
    // 剪贴板清除任务补偿：后台冻结期间定时器暂停，回前台检查是否到期未清除
    ClipboardUtils.flushPendingClears();
    SessionManager.getInstance().onAppForeground();
    if (this.isLockScreen()) {
      this.tryLockScreen();
    }
    SyncSettingsService.syncOnForeground();
  }

  /**
   * 系统返回键回调。
   *
   * 当 Navigation 的路由栈非空时，返回事件会先被 Navigation 消费（弹出 NavDestination），
   * 不会走到这里；只有路由栈为空（例如 DatabaseView 内部原位进入子分组）时，
   * 才会回调到此，交由 NavigationManager 的上下文处理器决定是否消费返回事件，
   * 从而避免「在子分组页面按系统返回直接退出应用」。
   */
  onBackPressed(): boolean {
    return NavigationManager.getInstance().handleSystemBack();
  }

  onBackground(): void {
    // 会话进行中申请短时任务保活（通知窗口/剪贴板清理定时器、通知按钮事件投递依赖进程运行）
    SessionManager.getInstance().onAppBackground();
    if (this.isLockScreen()) {
      this.backgroundTime = new Date().getTime(); // 记录当前时间戳
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    let uri = want.uri;
    hilog.info(DOMAIN, TAG, 'Ability onNewWant: %{public}s', uri);
    if (this.windowStage && uri) {
      FileService.close();
      // 关闭锁屏遮罩（如果存在）
      AppStorage.setOrCreate('isLocked', false);
      this.openDatabase(uri);
    }
  }

  /**
   * 打开数据库
   */
  private openDatabase(dbUrl: string): void {
    if (this.windowStage && dbUrl) {
      this.createStorage(dbUrl);
      this.openPage('pages/Password');
    }
  }

  /**
   * 打开页面
   * @param page
   */
  private openPage(page: string): void {
    if (this.windowStage) {
      this.windowStage.loadContent(page, (err, data) => {
        this.loadContentCallback(err, data)
      });
    }
  }

  /**
   * 加载内容回调
   * @param err
   * @param data
   */
  private loadContentCallback<T>(err: BusinessError, data: T): void {
    if (err.code) {
      hilog.error(DOMAIN, TAG, 'Ability onWindowStageCreate failed, err: %{public}s', err.message);
    } else {
      hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate success');
      this.createUrl = undefined;
    }
    if (this.windowStage) {
      this.windowStage.getMainWindow().then((win) => {
        try {
          CommonUtils.init(this.context, win.getUIContext());
        } catch (error) {
          hilog.error(DOMAIN, TAG, 'Ability onWindowStageCreate failed, err: %{public}s', error.message);
        }
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'Ability onWindowStageCreate failed, err: %{public}s', err.message);
      });
    }
  }

  /**
   * 创建本地存储
   * @param createUrl
   * @returns
   */
  private createStorage(createUrl: string): void {
    AppStorage.setOrCreate(Constants.APP_STORAGE_LOCATION_INFO, {
      filePath: createUrl,
      fileName: FilenameUtils.getFileName(createUrl),
      storageType: StorageType.LOCAL,
      storageConfig: new LocalFileStorageConfig()
    });
  }

  /**
   * 是否锁屏
   * @returns
   */
  private isLockScreen(): boolean {
    let dbFileParam = FileService.getDbFileParam();
    return dbFileParam && dbFileParam.filePath !== undefined;
  }

  /**
   * 尝试锁屏
   */
  private async tryLockScreen() {
    if (this.backgroundTime == 0) {
      return;
    }
    const elapsed = new Date().getTime() - this.backgroundTime;
    const autoLockTime = SettingsService.getSync(SettingsService.KEY_SECURITY_AUTO_LOCK_TIME, SettingsService.KEY_SECURITY_AUTO_LOCK_TIME_DEFAULT);
    // 检查是否超过设定时间
    if (autoLockTime > 0 && elapsed >= autoLockTime * 1000) {
      await LockScreenService.showLockWindow(false);
    }
  }
}
