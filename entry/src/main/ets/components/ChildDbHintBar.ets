/**
 * 子数据库配置提示条组件（M5）
 * 封装：根组存在未显式配置本设备的 AutoOpen 条目时的提示判定、「不再提示」按库记忆与提示条 UI
 * 父组件在分组切换/数据刷新后通过 ChildDbHintBarController.updateHint() 触发重新判定
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Kdbx, KdbxGroup } from 'kdbxweb';
import { AutoOpenService } from '../services/autoopen/AutoOpenService';
import { DeviceIdentity } from '../services/autoopen/DeviceIdentity';
import { FileService } from '../services/FileService';
import { SettingsService } from '../services/SettingsService';
import { NavigationManager } from '../common/utils';
import { PageConstants } from '../common/constants/PageConstants';
import { HintBanner } from './HintBanner';

const DOMAIN = 0x0000;
const TAG = 'ChildDbHintBar';

/**
 * 子数据库配置提示条控制器：父组件持有，分组切换/数据刷新后调用 updateHint() 触发重新判定
 */
export class ChildDbHintBarController {
  updateHint = (): void => {
  };
}

@Component
export struct ChildDbHintBar {
  /** 控制器：父组件持有并在分组切换/数据刷新后触发重新判定 */
  controller: ChildDbHintBarController | undefined = undefined;
  /** 当前分组（@Link 同步父组件；仅根组视图显示提示条） */
  @Link currentGroup: KdbxGroup | undefined;
  /** 移动模式下隐藏 */
  @Prop moveMode: boolean = false;
  /** 选择模式下隐藏 */
  @Prop selectionMode: boolean = false;
  @State showHint: boolean = false;

  aboutToAppear(): void {
    if (this.controller) {
      this.controller.updateHint = this.updateHintVisibility;
    }
  }

  build() {
    if (this.showHint && !this.moveMode && !this.selectionMode
      && this.currentGroup !== undefined && this.currentGroup.parentGroup === undefined) {
      HintBanner({
        message: $r('app.string.unconfigured_child_dbs'),
        actionLabel: $r('app.string.child_dbs_go_configure'),
        dismissLabel: $r('app.string.child_dbs_hint_dismiss'),
        onAction: (): void => {
          NavigationManager.getInstance().navigateTo(PageConstants.PAGE_CHILD_DATABASES);
        },
        onDismiss: (): void => {
          this.dismissHint();
        }
      })
    }
  }

  /**
   * 子数据库配置提示条（M5）：根组视图且存在未显式配置本设备的 AutoOpen 条目时显示。
   * 对齐 kp2a GroupBaseActivity.UpdateChildDbInfo：根组判定 + IfDevice 未显式命中判定 + 「不再提示」按库记忆。
   */
  private updateHintVisibility = (): void => {
    this.showHint = false;
    // 子数据库功能禁用时不显示配置提示条
    if (!SettingsService.isChildDbEnable()) {
      return;
    }
    const database: Kdbx | null = FileService.getDbFileParam().database ?? null;
    if (database === null || this.currentGroup === undefined) {
      return;
    }
    // 仅根组视图显示
    if (this.currentGroup.parentGroup !== undefined) {
      return;
    }
    const iocKey: string = FileService.getRegistry().getCurrentKey() ?? '';
    if (!AutoOpenService.hasUnconfiguredForDevice(database, iocKey, DeviceIdentity.getDeviceId())) {
      return;
    }
    // 「不再提示」按库记忆（KEY_CHILD_DB_HINT_HIDDEN_<iocKeyHash>）
    const hidden: boolean = SettingsService.getSync(SettingsService.childDbHintHiddenKey(iocKey), false);
    this.showHint = !hidden;
  }

  /**
   * 「不再提示」子数据库配置条：按库记忆并立即隐藏
   */
  private dismissHint(): void {
    const iocKey: string = FileService.getRegistry().getCurrentKey() ?? '';
    if (iocKey.length > 0) {
      SettingsService.put(SettingsService.childDbHintHiddenKey(iocKey), true).catch((): void => {
        hilog.warn(DOMAIN, TAG, 'Failed to persist child db hint hidden flag');
      });
    }
    this.showHint = false;
  }
}
