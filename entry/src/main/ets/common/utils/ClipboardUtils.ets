import { BusinessError, pasteboard } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SettingsService } from '../../services/SettingsService';
import { CommonUtils } from '.';

const DOMAIN = 0x0000;
const TAG = 'ClipboardUtils';

export class ClipboardUtils {
  private static timeOutObj: number = -1;
  /** 当前清除任务的到期时间戳（ms），用于应用后台冻结时 setTimeout 暂停的补偿 */
  private static clearExpireAt: number = 0;

  /**
   * 复制文本到剪贴板，并按安全设置自动清理
   * @param text 文本
   * @param silent 静默模式，后台复制时跳过 toast
   */
  public static copyAutoClear(text: string, silent?: boolean) {
    SettingsService.get(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT, (value) => {
      ClipboardUtils.copy(text, value, silent);
    });
  }

  /**
   * 复制文本到剪贴板
   * @param text 文本
   * @param timeoutClear 自动清理时间，单位秒, 小于等于0则不进行清理
   * @param silent 静默模式，后台复制时跳过 toast
   */
  public static copy(text: string, timeoutClear?: number, silent?: boolean) {
    // 获取系统剪贴板实例
    const pasteboardData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text);
    // 仅本机应用可用，禁止剪贴板内容跨设备同步
    pasteboardData.getProperty().shareOption = pasteboard.ShareOption.INAPP;
    // 将数据写入剪贴板
    pasteboard.getSystemPasteboard().setData(pasteboardData, (error, data) => {
      if (error) {
        hilog.error(DOMAIN, TAG, 'Failed to copy to clipboard: %{public}s %{public}s %{public}s %{public}s', error.message, error.code, error.name,
          error.stack);
        if (!silent) {
          CommonUtils.showToast({ message: $r("app.string.copy_failed") });
        }
      } else {
        if (timeoutClear && timeoutClear > 0) {
          ClipboardUtils.scheduleClear(timeoutClear);
        }
        if (!silent) {
          CommonUtils.showToast({ message: $r("app.string.copied"), duration: 1500 });
        }
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
        ClipboardUtils.forceClearNow();
        return;
      }
      ClipboardUtils.scheduleClear(timeout);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to clear clipboard: ${error}`)
    }
  }

  /**
   * 安排延时清除任务（带到期时间戳，供前台补偿扫描）
   * @param timeoutSec 自动清理时间，单位秒
   */
  private static scheduleClear(timeoutSec: number) {
    try {
      if (ClipboardUtils.timeOutObj != -1) {
        clearTimeout(ClipboardUtils.timeOutObj);
        ClipboardUtils.timeOutObj = -1;
      }
      ClipboardUtils.clearExpireAt = new Date().getTime() + timeoutSec * 1000;
      ClipboardUtils.timeOutObj = setTimeout(() => {
        ClipboardUtils.timeOutObj = -1;
        ClipboardUtils.clearExpireAt = 0;
        ClipboardUtils.doClearNow('timeout');
      }, 1000 * timeoutSec);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to schedule clipboard clear: ${error}`)
    }
  }

  /**
   * 切回前台补偿：应用后台冻结期间 setTimeout 不执行，回前台检查清除任务是否已到期未执行
   */
  public static flushPendingClears(): void {
    if (ClipboardUtils.clearExpireAt <= 0) {
      return;
    }
    if (new Date().getTime() >= ClipboardUtils.clearExpireAt) {
      ClipboardUtils.forceClearNow();
    }
  }

  /**
   * 重置未执行的清除任务（通知窗口重启时调用，使剪贴板清理与通知窗口同步重新计算）；
   * 无未执行任务（剪贴板无本次会话复制的内容）时不做任何处理
   */
  public static restartAutoClear(): void {
    if (ClipboardUtils.clearExpireAt <= 0) {
      return;
    }
    const timeoutSec = SettingsService.getSync(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME,
      SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT);
    if (timeoutSec <= 0) {
      return;
    }
    ClipboardUtils.scheduleClear(timeoutSec);
  }

  /**
   * 立即清除剪贴板并取消未执行的清除任务（锁库/关库时调用）
   */
  public static forceClearNow(): void {
    if (ClipboardUtils.timeOutObj != -1) {
      clearTimeout(ClipboardUtils.timeOutObj);
      ClipboardUtils.timeOutObj = -1;
    }
    ClipboardUtils.clearExpireAt = 0;
    ClipboardUtils.doClearNow('force');
  }

  /**
   * 执行清除剪贴板
   * @param reason 清除原因（仅日志）
   */
  private static doClearNow(reason: string): void {
    pasteboard.getSystemPasteboard().clearData().then(() => {
      hilog.info(DOMAIN, TAG, 'Clear clipboard success, reason: %{public}s', reason);
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'Failed to clear clipboard, reason: %{public}s, code: %{public}s, message: %{public}s', reason, error.code, error
        .message);
    });
  }
}
