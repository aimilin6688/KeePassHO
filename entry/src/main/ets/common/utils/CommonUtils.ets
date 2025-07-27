import { util } from '@kit.ArkTS';
import { promptAction } from '@kit.ArkUI';

export class CommonUtils {
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
  public static showToast(message: string, duration?: number): void {
    promptAction.showToast({ message: message, duration: duration ?? 2000 });
  }
}