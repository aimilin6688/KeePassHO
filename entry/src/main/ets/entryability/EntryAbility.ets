import { AbilityConstant, contextConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SettingsService } from '../services/SettingsService';
import ThemeManager from '../common/utils/ThemeManager';
import ResourceManager from '../common/utils/ResourceManager';
import { RecentFilesService } from '../services/RecentFilesService';
import { FileService } from '../services/FileService';
import { CommonUtils } from '../common/utils/CommonUtils';
import { FilenameUtils } from '../common/utils/FilenameUtils';
import { LocalFileStorageConfig, StorageType } from '../services/kdbx/interfaces';
import { BusinessError } from '@kit.BasicServicesKit';
import { Constants } from '../common/constants/Constants';
import { SupportService } from '../services/SupportService';

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
    CommonUtils.getInstance().init(this.context);
    // 初始化主题管理器
    ThemeManager.getInstance().init(this.context);
    // 初始化资源管理器
    ResourceManager.getInstance().init(this.context);
    // 最近打开的文件服务
    RecentFilesService.getInstance().init(this.context);
    // 初始化设置服务
    await SettingsService.getInstance().init(this.context).then(()=>{
      // 设值应用安装时间
      SupportService.initAppInstallTime();
    })

  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
    FileService.close();
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');
    this.windowStage = windowStage;
    // 通过URL打开数据库
    if (this.createUrl) {
      this.createStorage(this.createUrl);
      windowStage.loadContent('pages/Password', (err, data) => {
        this.loadContentCallback(err, data)
      });
    } else {
      windowStage.loadContent('pages/Index');
    }
  }


  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
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
      this.createStorage(uri);
      this.windowStage.loadContent('pages/Password', (err, data) => {
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

  private isLockScreen(): boolean {
    let dbFileParam = FileService.getDbFileParam();
    return dbFileParam && dbFileParam.filePath !== undefined;
  }

  private async tryLockScreen() {
    if (this.backgroundTime == 0) {
      return;
    }
    const elapsed = new Date().getTime() - this.backgroundTime;
    const autoLockTime =
      await SettingsService.getInstance().get(SettingsService.KEY_SECURITY_AUTO_LOCK_TIME, SettingsService.KEY_SECURITY_AUTO_LOCK_TIME_DEFAULT);
    // 检查是否超过30秒
    if (autoLockTime > 0 && elapsed >= autoLockTime * 1000) {
      this.showLockScreen(); // 显示锁定界面
    }
  }

  // 显示锁定界面
  private showLockScreen(): void {
    window.getLastWindow(this.context).then((win) => {
      win.setUIContent("pages/UnLockDatabase"); // 跳转到锁定页面
    });
  }
}
