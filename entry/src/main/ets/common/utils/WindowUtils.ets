import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@ohos.base';
import { SettingsService } from '../../services/SettingsService';

const DOMAIN = 0x0000;
const TAG = 'WindowUtils';

export class WindowUtils {
  /**
   * 设置当前页面的隐私模式
   * @param context 上下文
   */
  public static onPageShow(context: common.UIAbilityContext) {
    // 获取隐私模式设置
    SettingsService.get(SettingsService.KEY_SECURITY_PRIVACY_WINDOW, SettingsService.KEY_SECURITY_PRIVACY_WINDOW_DEFAULT, (value) => {
      WindowUtils.setWindowPrivacyModeInPage(context, value);
    });
  }

  /**
   * 设置当前页面的隐私模式
   * @param context 上下文
   * @param isFlag 是否开启隐私模式
   */
  public static setWindowPrivacyModeInPage(context: common.UIAbilityContext, isFlag: boolean) {
    try {
      window.getLastWindow(context).then((lastWindow) => {
        lastWindow.setWindowPrivacyMode(isFlag).catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, `setWindowPrivacyMode error moded: ${isFlag},  code: ${error?.code}, message: ${error?.message}`);
        });
      }).catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, `getLastWindow error code: ${error?.code}, message: ${error?.message}`);
      });
    } catch (error) {
      console.error(`setWindowPrivacyModeInPage error: ${error?.code}, message: ${error?.message}`);
    }
  }
}