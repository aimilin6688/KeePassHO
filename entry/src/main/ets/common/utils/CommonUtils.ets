import { util } from '@kit.ArkTS';
import { promptAction, router, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'CommonUtils';

export class CommonUtils {
  private static context: common.UIAbilityContext | null = null;
  private static uiContext: UIContext | undefined = undefined;
  // Worker 线程注入的应用沙箱路径（Actor 模型：Worker 无 Context，跨线程仅能传字符串）
  private static injectedAppFilesDir: string = '';
  private static injectedCacheDir: string = '';

  /**
   * 初始化主题管理器
   * @param context UIAbilityContext
   */
  public static init(context: common.UIAbilityContext, uiContext?: UIContext): void {
    CommonUtils.context = context;
    CommonUtils.uiContext = uiContext;
  }

  /**
   * 获取上下文
   * @returns
   */
  public static getContext(): common.UIAbilityContext {
    return CommonUtils.context as common.UIAbilityContext;
  }

  /**
   * 注入 Worker 线程可用的沙箱路径（由主线程在 Worker 启动时调用；
   * Worker 线程内 CommonUtils.context 恒为 null，只能依赖注入值）
   */
  public static setWorkerPaths(appFilesDir: string, cacheDir: string): void {
    CommonUtils.injectedAppFilesDir = appFilesDir;
    CommonUtils.injectedCacheDir = cacheDir;
  }

  /**
   * 应用级文件目录（ApplicationContext.filesDir）
   * 主线程取自 Context；Worker 线程取注入值
   */
  public static getAppFilesDir(): string {
    const ctx = CommonUtils.context;
    if (ctx !== null) {
      return ctx.getApplicationContext().filesDir;
    }
    return CommonUtils.injectedAppFilesDir;
  }

  /**
   * 应用缓存目录（UIAbilityContext.cacheDir）
   * 主线程取自 Context；Worker 线程取注入值
   */
  public static getCacheDir(): string {
    const ctx = CommonUtils.context;
    if (ctx !== null) {
      return ctx.cacheDir;
    }
    return CommonUtils.injectedCacheDir;
  }

  /**
   * 供 FTPClient 等以 any 接收 Context 的三方库使用的上下文对象：
   * 主线程返回应用 Context；Worker 线程返回仅含 cacheDir 的等价替身
   */
  public static getStorageContext(): common.UIAbilityContext | StorageContextStub {
    const ctx = CommonUtils.context;
    if (ctx !== null) {
      return ctx;
    }
    return new StorageContextStub(CommonUtils.injectedCacheDir);
  }

  public static getUiContext(): UIContext {
    return CommonUtils.uiContext as UIContext;
  }

  /**
   * base64编码
   * @param str
   * @returns
   */
  public static base64Encode(str: string): string {
    const base64 = new util.Base64Helper();
    const encoder = new util.TextEncoder()
    return base64.encodeToStringSync(encoder.encodeInto(str));
  }


  /**
   * 响应头类型
   * @param filePath
   * @returns
   */
  public static getMimeTypeFromExtension(filePath: string): string {
    const extension = filePath.split('.').pop()?.toLowerCase() ?? '';

    const mimeMap: Record<string, string> = {
      'txt': 'text/plain',
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'ico': 'image/x-icon',
      'mp3': 'audio/mpeg',
      'mp4': 'video/mp4',
      'doc': 'application/msword',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'zip': 'application/zip',
      'rar': 'application/x-rar-compressed',
      'json': 'application/json',
      'html': 'text/html',
      'css': 'text/css',
      'js': 'text/javascript'
    };

    return mimeMap[extension] || 'application/octet-stream';
  }

  /**
   * 显示提示信息
   * @param message
   * @param duration
   */
  public static showToast(message: ResourceStr | promptAction.ShowToastOptions, duration?: number): void {
    try {
      if (CommonUtils.uiContext) {
        CommonUtils.uiContext.getPromptAction().showToast(CommonUtils.toShowToastOptions(message, duration));
      } else {
        promptAction.showToast(CommonUtils.toShowToastOptions(message, duration));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `showToast error: ${error?.message}`);
    }
  }

  /**
   * 显示弹框
   * @param showDialogOptions
   * @returns
   */
  public static showDialog(showDialogOptions: promptAction.ShowDialogOptions): Promise<ShowDialogSuccessResponse> {
    if (CommonUtils.uiContext) {
      return CommonUtils.uiContext.getPromptAction().showDialog(showDialogOptions).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, `uiContext showDialog error: ${error?.message}`);
        return Promise.reject(error);
      });
    } else {
      return promptAction.showDialog(showDialogOptions).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, `showDialog error: ${error?.message}`);
        return Promise.reject(error);
      });
    }
  }

  /**
   * 获取已存在文件弹框
   * @returns
   */
  public static getExistsFileDialog(): promptAction.ShowDialogOptions {
    return {
      title: $r('app.string.dialog_prompt_title'),
      message: $r('app.string.dialog_exists_file_message'),
      buttons: [
        {
          text: $r('app.string.cancel_button_text'),
          color: $r('app.color.text_secondary')
        },
        {
          text: $r('app.string.replace_button_text'),
          color: $r("app.color.button_bg_blue"),
        }
      ],
    }
  }

  /**
   * 跳转页面
   * @param options
   * @returns
   */
  public static pushUrl(options: router.RouterOptions, mode?: router.RouterMode,): Promise<void> {
    if (CommonUtils.uiContext) {
      return CommonUtils.uiContext.getRouter().pushUrl(options, mode).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, `uiContext pushUrl error: ${error?.message}`);
        return Promise.reject(error);
      });
    }
    return router.pushUrl(options, mode).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, `pushUrl error: ${error?.message}`);
      return Promise.reject(error);
    });
  }

  /**
   * 替换页面
   * @param options
   * @param mode
   * @returns
   */
  public static replaceUrl(options: router.RouterOptions, mode?: router.RouterMode,): Promise<void> {
    if (CommonUtils.uiContext) {
      return CommonUtils.uiContext.getRouter().replaceUrl(options, mode).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, `uiContext replaceUrl error: ${error?.message}`);
        return Promise.reject(error);
      });
    }
    return router.replaceUrl(options, mode).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, `replaceUrl error: ${error?.message}`);
      return Promise.reject(error);
    });
  }

  /**
   * 返回
   * @param options
   */
  public static back(options?: router.RouterOptions): void {
    if (CommonUtils.uiContext) {
      return CommonUtils.uiContext.getRouter().back(options);
    }
    return router.back(options);
  }

  /**
   * 转换为提示信息参数
   * @param message 消息格式
   * @param duration 延时时间
   * @returns 结果
   */
  private static toShowToastOptions(param: ResourceStr | promptAction.ShowToastOptions, duration?: number): promptAction.ShowToastOptions {
    if (typeof param === 'string') {
      return { message: param, duration: duration ?? 2000 };
    }
    if (Object.keys(param).indexOf('bundleName') !== -1) {
      return { message: param as ResourceStr, duration: duration ?? 2000 };
    }
    return param as promptAction.ShowToastOptions;
  }

  /**
   * 未保存弹框确认
   * @param context 上下文
   * @param cancel 取消回调
   * @param confirm 确定回调
   */
  public static showUnSaveConfirm(context: UIContext, callback?: ConfirmCallback): void {
    CommonUtils.showConfirmDialog(context, $r('app.string.dialog_confirm_title'), $r('app.string.dialog_changes_confirm_message'), callback);
  }

  /**
   * 确认删除弹框
   * @param context 上下文
   * @param cancel 取消回调
   * @param confirm 确定回调
   */
  public static showDeleteConfirm(context: UIContext, callback?: ConfirmCallback): void {
    CommonUtils.showConfirmDialog(context, $r('app.string.dialog_confirm_title'), $r('app.string.dialog_delete_confirm_message'), callback);
  }

  /**
   * 确认弹框
   * @param context 上下文
   * @param title 标题
   * @param message 消息
   * @param callback 回调
   */
  public static showConfirmDialog(context: UIContext, title: ResourceStr, message: ResourceStr, callback?: ConfirmCallback): void {
    context.showAlertDialog({
      title: title,
      message: message,
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {
          callback?.onCancel?.();
        }
      },
      secondaryButton: {
        value: $r('app.string.confirm_button_text'),
        action: () => {
          callback?.onConfirm?.();
        }
      }
    });
  }

}

/**
 * 确认弹框回调
 */
export interface ConfirmCallback {
  onCancel?: () => void;
  onConfirm?: () => void;
}

/**
 * Worker 线程的存储层上下文替身：仅携带 cacheDir 路径字符串，
 * 供只读 cacheDir 属性的三方库（如 basic-ftp 的 FTPClient）在无 Context 的 Worker 中使用
 */
export class StorageContextStub {
  readonly cacheDir: string;

  constructor(cacheDir: string) {
    this.cacheDir = cacheDir;
  }
}