/**
 * TotpQrHelper
 */
export class TotpQrHelper {
  /**
   * 构建可导出的二维码内容
   * @param otpAuthUrl 兼容层归一的 otpauth URI
   * @param entryTitle 条目标题（name/issuer 均空时兜底）
   * @returns 成功返回最终 URI；解析失败返回 null
   */
  public static buildQrContent(otpAuthUrl: string, entryTitle: string): string | null {
    return null;
  }
}
