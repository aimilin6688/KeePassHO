import DateUtils, { DateUnit } from '../common/utils/DateUtils';
import { SettingsService } from './SettingsService';
import { promptAction } from '@kit.ArkUI';


export class SupportService {
  constructor() {
  }

  public showSupportDialog(context: UIContext) {
    if (!this.isShowSupport()) {
      return;
    }
    context.getPromptAction().showDialog(this.getShowSupportDialog()).then(async result => {
      SettingsService.put(SettingsService.KEY_SHOW_SUPPORT_TIME, new Date().getTime());
      if (result.index === 1) {
        context.getRouter().pushUrl({ url: "pages/about/Support" });
      }
    });
  }

  /**
   * 初始化安装时间
   */
  public static initAppInstallTime() {
    if (SettingsService.getSync(SettingsService.KEY_APP_INSTALL_TIME, -1) > 0) {
      return;
    }
    SettingsService.put(SettingsService.KEY_APP_INSTALL_TIME, new Date().getTime());
  }

  /**
   * 是否可以隐藏支持
   */
  public static isCanHideSupport(): boolean {
    const appInstallTime = SettingsService.getSync(SettingsService.KEY_APP_INSTALL_TIME, -1);
    if (appInstallTime <= 0) {
      return false;
    }
    return DateUtils.offset(new Date(), -1, DateUnit.Month).getTime() >= appInstallTime;
  }


  /**
   * 获取支持弹框
   */
  private getShowSupportDialog(): promptAction.ShowDialogOptions {
    return {
      title: $r('app.string.support_dialog_title'),
      message: $r('app.string.support_dialog_message'),
      buttons: [
        {
          text: $r('app.string.cancel_button_text'),
          color: $r('app.color.text_secondary')
        },
        {
          text: $r('app.string.confirm_button_text'),
          color: $r("app.color.button_bg_blue"),
        }
      ],
    }
  }


  /**
   * 是否需要显示支持弹框
   */
  private isShowSupport(): boolean {
    // 不需要显示支持弹框
    if (!SettingsService.getSync(SettingsService.KEY_SHOW_SUPPORT_DIALOG, SettingsService.KEY_SHOW_SUPPORT_DIALOG_DEFAULT)) {
      return false;
    }
    // 今天支持弹款已经显示过了
    const lastShowTime = SettingsService.getSync(SettingsService.KEY_SHOW_SUPPORT_TIME, -1);
    if (lastShowTime <= 0) {
      return true;
    }
    return DateUtils.isNotToday(new Date(lastShowTime));
  }
}