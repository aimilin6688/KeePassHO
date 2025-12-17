import { AbilityConstant, contextConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SettingsService } from '../services/SettingsService';
import { ThemeManager, ResourceManager, CommonUtils, Sm4Utils, FilenameUtils } from '../common/utils';
import { RecentFilesService } from '../services/RecentFilesService';
import { FileService } from '../services/FileService';
import { LocalFileStorageConfig, StorageType } from '../storage';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from '../common/constants/Constants';
import { SupportService } from '../services/SupportService';
import { DistributedKVService } from '../services/store/DistributedKVService';

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
    this.init();
    this.createUrl = want.uri;
  }

  /**
   * 初始化应用
   */
  private async init() {
    this.context.area = contextConstant.AreaMode.EL4;
    // 初始化通用工具类
    CommonUtils.init(this.context);
    // 初始化主题管理器
    ThemeManager.getInstance().init(this.context);
    // 初始化资源管理器
    ResourceManager.getInstance().init(this.context);
    // 最近打开的文件服务
    RecentFilesService.getInstance().init(this.context);
    // 初始化设置服务
    SettingsService.getInstance().init(this.context).then(() => {
      // 设值应用安装时间
      SupportService.initAppInstallTime();
    })
    // 初始化加解密KEY
    Sm4Utils.init();
    // 初始化kv数据库
    DistributedKVService.init(this.context);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
    FileService.close();
    DistributedKVService.close();
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
        CommonUtils.init(this.context, win.getUIContext());
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
