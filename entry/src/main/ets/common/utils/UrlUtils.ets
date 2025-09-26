import { url } from '@kit.ArkTS';

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
    let parsedUrl = url.URL.parseURL(urlString);
    return parsedUrl.protocol + "//" + parsedUrl.host;
  }
}