/**
 * 条目到期提醒条组件（M1）
 * 封装：解锁后到期评估（防打扰判定）、根组可见性、「关闭」与提示条 UI
 * 父组件在解锁完成后通过 ExpiryHintBarController.evaluateExpiry() 触发评估
 */
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Kdbx, KdbxGroup } from 'kdbxweb';
import { ExpiryRemindResult, ExpiryRemindService } from '../services/ExpiryRemindService';
import { FileService } from '../services/FileService';
import { NavigationManager, ResourceManager } from '../common/utils';
import { PageConstants } from '../common/constants/PageConstants';
import { HintBanner } from './HintBanner';

const DOMAIN = 0x0000;
const TAG = 'ExpiryHintBar';

/**
 * 到期提醒条控制器：父组件持有，解锁完成后调用 evaluateExpiry() 触发评估
 */
export class ExpiryHintBarController {
  evaluateExpiry = (): void => {
  };
}

@Component
export struct ExpiryHintBar {
  /** 控制器：父组件持有并在解锁完成后触发评估 */
  controller: ExpiryHintBarController | undefined = undefined;
  /** 当前分组（@Link 同步父组件；仅根组视图显示提示条） */
  @Link currentGroup: KdbxGroup | undefined;
  /** 移动模式下隐藏 */
  @Prop moveMode: boolean = false;
  /** 选择模式下隐藏 */
  @Prop selectionMode: boolean = false;
  /** 解锁评估结果与显示状态 */
  @State expiryRemindResult: ExpiryRemindResult | null = null;
  @State showExpiryHint: boolean = false;

  aboutToAppear(): void {
    if (this.controller) {
      this.controller.evaluateExpiry = this.evaluateExpiryHint;
    }
  }

  build() {
    if (this.showExpiryHint && this.expiryRemindResult !== null && !this.moveMode && !this.selectionMode
      && this.currentGroup !== undefined && this.currentGroup.parentGroup === undefined) {
      HintBanner({
        message: ResourceManager.getString($r('app.string.expiry_remind_banner_text'), this.expiryRemindResult.totalCount, this.expiryRemindResult.remindDays),
        actionLabel: $r('app.string.expiry_remind_view'),
        dismissLabel: $r('app.string.close_button_text'),
        onAction: (): void => {
          NavigationManager.getInstance().navigateTo(PageConstants.PAGE_EXPIRY_REPORT);
        },
        onDismiss: ():void => {
          this.closeExpiryHint();
        }
      })
    }
  }

  /**
   * 条目到期提醒（M1）：解锁完成后评估一次。
   * 通过防打扰判定（开关 → 今日隐藏 → 24h 间隔/每次解锁）后生成提醒数据并显示提示条；
   * lastRemindTime 仅在此处写入，刷新/重载路径不重复计时
   */
  private evaluateExpiryHint = (): void => {
    this.expiryRemindResult = null;
    this.showExpiryHint = false;
    try {
      const database: Kdbx | null = FileService.getDbFileParam().database ?? null;
      if (database === null) {
        return;
      }
      const iocKey: string = FileService.getRegistry().getCurrentKey() ?? '';
      if (iocKey.length === 0) {
        return;
      }
      const result: ExpiryRemindResult | null = ExpiryRemindService.getInstance().evaluate(database, iocKey);
      if (result === null || result.totalCount === 0) {
        return;
      }
      this.expiryRemindResult = result;
      this.showExpiryHint = true;
      hilog.info(DOMAIN, TAG, 'Expiry remind shown: expired=%{public}d, expiring=%{public}d', result.expiredCount, result.expiringCount);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to evaluate expiry hint: %{public}s', `${error}`);
    }
  }

  /**
   * 「关闭」到期提醒条：仅隐藏当前提示条。
   * 每 24 小时频率：记录关闭时间（下次解锁按 24h 间隔判断是否再次提醒）；
   * 每次解锁频率：不记录，下次解锁仍会提醒
   */
  private closeExpiryHint(): void {
    const iocKey: string = FileService.getRegistry().getCurrentKey() ?? '';
    ExpiryRemindService.getInstance().closeRemind(iocKey).catch((): void => {
      hilog.warn(DOMAIN, TAG, 'Failed to persist expiry remind close time');
    });
    this.showExpiryHint = false;
  }
}
