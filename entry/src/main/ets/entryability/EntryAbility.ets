import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { SettingsService } from '../services/SettingsService';
import ThemeManager from '../common/utils/ThemeManager';
import ResourceManager from '../common/utils/ResourceManager';
import { RecentFilesService } from '../services/RecentFilesService';
import { FileService } from '../services/FileService';

const DOMAIN = 0x0000;
const TAG = 'EntryAbility';

/**
 * 入口Ability
 */
export default class EntryAbility extends UIAbility {
  private backgroundTime: number = 0;

  // 记录进入后台的时间戳

  async onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): Promise<void> {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onCreate');
    this.init();
  }

  /**
   * 初始化应用
   */
  private async init() {
    // 初始化主题管理器
    ThemeManager.getInstance().init(this.context);

    // 初始化资源管理器
    ResourceManager.getInstance().init(this.context);
    // 最近打开的文件服务
    RecentFilesService.getInstance().init(this.context);

    // 初始化设置服务
    await SettingsService.getInstance().init(this.context);
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageCreate');

    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load the content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading the content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onForeground');
    this.tryLockScreen();
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', 'Ability onBackground');
    if (this.isLockScreen()) {
      this.backgroundTime = new Date().getTime(); // 记录当前时间戳
    }
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
    const autoLockTime = await SettingsService.getInstance().get(SettingsService.KEY_SECURITY_AUTO_LOCK_TIME, SettingsService.KEY_SECURITY_AUTO_LOCK_TIME_DEFAULT);
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
