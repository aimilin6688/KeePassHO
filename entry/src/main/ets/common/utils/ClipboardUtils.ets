import { pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SettingsService } from '../../services/SettingsService';
import { CommonUtils } from './CommonUtils';

const DOMAIN = 0x0000;
const TAG = 'EntryViewFieldItem';

export class ClipboardUtils {
  private static timeOutObj: number = -1;

  /**
   * 复制文本到剪贴板，并自动清理
   * @param text 文本
   * @param timeoutClear 自动清理时间，单位秒, 小于等于0则不进行清理
   */
  public static copyAutoClear(text: string) {
    SettingsService.get(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT, (value) => {
      ClipboardUtils.copy(text, value);
    });
  }

  /**
   * 复制文本到剪贴板
   * @param text 文本
   * @param timeoutClear 自动清理时间，单位秒, 小于等于0则不进行清理
   */
  public static copy(text: string, timeoutClear?: number) {
    // 获取系统剪贴板实例
    const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    // 将数据写入剪贴板
    pasteboard.getSystemPasteboard().setData(pasteboardData, (error, data) => {
      if (error) {
        hilog.error(DOMAIN, TAG, 'Failed to copy to clipboard: %{public}s %{public}s %{public}s %{public}s', error.message, error.code, error.name,
          error.stack);
        CommonUtils.showToast({ message: $r("app.string.copy_failed") });
      } else {
        if (timeoutClear && timeoutClear > 0) {
          ClipboardUtils.clear(timeoutClear);
        }
        CommonUtils.showToast({ message: $r("app.string.copied"), duration: 1500 });
      }
    });
  }

  /**
   * 清理剪切板数据
   * @param timeout 自动清理时间，单位秒
   */
  public static clear(timeout?: number) {
    try {
      if (!timeout || timeout <= 0) {
        pasteboard.getSystemPasteboard().clearData();
        return;
      }
      if (ClipboardUtils.timeOutObj != -1) {
        clearTimeout(ClipboardUtils.timeOutObj);
        ClipboardUtils.timeOutObj = -1;
      }
      ClipboardUtils.timeOutObj = setTimeout(() => {
        pasteboard.getSystemPasteboard().clearData().then(() => {
          hilog.debug(DOMAIN, TAG, 'Clear clipboard success');
          ClipboardUtils.timeOutObj = -1;
        });
      }, 1000 * timeout);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to clear clipboard: ${error}`)
    }
  }
}