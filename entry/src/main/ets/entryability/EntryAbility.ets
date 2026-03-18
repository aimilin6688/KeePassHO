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
import { DialogHelper } from '@pura/harmony-dialog';
import { CrashLogService } from '../services/CrashLogService';

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

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, TAG, 'Ability onCreate %{public}s', want.uri);
    this.createUrl = want.uri;
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
  private initNonEssentialServices(): void {
    // 初始化加解密KEY
    Sm4Utils.init();
    // 初始化kv数据库
    DistributedKVService.init(this.context);
    // 初始化崩溃日志服务
    CrashLogService.getInstance().init(this.context);
    // 初始化弹框
    DialogHelper.setDefaultConfig((config) => {
      config.uiAbilityContext = this.context;
    });
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
    FileService.close();
    DistributedKVService.close();
    // 取消订阅崩溃事件
    CrashLogService.getInstance().unsubscribeCrashEvent();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    this.windowStage = windowStage;
    // 通过URL打开数据库
    if (this.createUrl) {
      this.openDatabase(this.createUrl);
    } else {
      this.openPage('pages/Index');
    }
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
    this.windowStage = undefined;
    this.createUrl = undefined;
  }

  onForeground(): void {
    if (this.isLockScreen()) {
      this.tryLockScreen();
    }
  }

  onBackground(): void {
    if (this.isLockScreen()) {
      this.backgroundTime = new Date().getTime(); // 记录当前时间戳
    }
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    let uri = want.uri;
    hilog.info(DOMAIN, TAG, 'Ability onNewWant: %{public}s', uri);
    if (this.windowStage && uri) {
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
    // 检查是否超过30秒
    if (autoLockTime > 0 && elapsed >= autoLockTime * 1000) {
      // 显示解锁界面
      this.openPage('pages/UnLockDatabase');
    }
  }
}
