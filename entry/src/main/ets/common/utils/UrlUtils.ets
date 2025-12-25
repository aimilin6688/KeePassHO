import { url } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'FTP';

/**
 * UrlUtils
 */
export class UrlUtils {
  /**
   * 带协议的host地址
   * http://www.aimilin.net/a/b/c -> http://www.aimilin.net
   * @param url
   * @returns
   */
  public static getHost(urlString: string | undefined): string {
    if (!urlString) {
      return "";
    }
    try {
      let parsedUrl = url.URL.parseURL(urlString);
      return parsedUrl.protocol + "//" + parsedUrl.host;
    } catch (e) {
      hilog.error(DOMAIN, TAG, "getHost error: " + e);
      return "";
    }
  }


  /**
   * 验证URL格式
   * @param url URL地址
   * @returns 是否有效
   */
  public static isValidUrl(urlPath: string): boolean {
    try {
      const urlObj: url.URL = url.URL.parseURL(urlPath);
      return urlObj.protocol === 'http:' || urlObj.protocol === 'https:';
    } catch {
      return false;
    }
  }
}