import { util } from '@kit.ArkTS';
import { promptAction, router, ShowDialogSuccessResponse } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';

export class CommonUtils {
  private static instance: CommonUtils = new CommonUtils();
  private context: common.UIAbilityContext | null = null;

  /**
   * 初始化主题管理器
   * @param context UIAbilityContext
   */
  public init(context: common.UIAbilityContext): void {
    this.context = context;
  }


  /**
   * 获取单例实例
   */
  public static getInstance(): CommonUtils {
    return CommonUtils.instance;
  }

  /**
   * 获取上下文
   * @returns
   */
  public static getContext(): common.UIAbilityContext {
    return CommonUtils.getInstance().context as common.UIAbilityContext;
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
    promptAction.showToast(CommonUtils.toShowToastOptions(message, duration));
  }

  /**
   * 显示弹框
   * @param showDialogOptions
   * @returns
   */
  public static showDialog(showDialogOptions: promptAction.ShowDialogOptions):Promise<ShowDialogSuccessResponse> {
    return promptAction.showDialog(showDialogOptions);
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
  public static pushUrl(options: router.RouterOptions): Promise<void> {
    return router.pushUrl(options);
  }

  /**
   * 返回
   * @param options
   */
  public static back(options?: router.RouterOptions): void {
    router.back(options);
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
    context.showAlertDialog({
      title: $r('app.string.dialog_confirm_title'),
      message: $r('app.string.dialog_changes_confirm_message'),
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