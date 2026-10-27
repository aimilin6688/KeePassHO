import { TotpConfig, TotpService } from '../../services/TotpService';

/**
 * TotpQrHelper
 */
export class TotpQrHelper {
  private static readonly MAX_QR_CONTENT_LENGTH = 512;

  /**
   * 构建可导出的二维码内容
   * @param otpAuthUrl 兼容层归一的 otpauth URI
   * @param entryTitle 条目标题（name/issuer 均空时兜底）
   * @returns 成功返回最终 URI；解析失败返回 null
   */
  public static buildQrContent(otpAuthUrl: string, entryTitle: string): string | null {
    if (!otpAuthUrl) {
      return null;
    }

    const totpService = TotpService.getInstance();
    const parsed: TotpConfig | null = totpService.parseUri(otpAuthUrl);
    if (parsed === null) {
      return null;
    }

    let result: string = otpAuthUrl;
    const hasName: boolean = (parsed.name ?? '').trim() !== '';
    const hasIssuer: boolean = (parsed.issuer ?? '').trim() !== '';
    if (!hasName && !hasIssuer) {
      const trimmedTitle: string = (entryTitle ?? '').trim();
      if (trimmedTitle !== '') {
        parsed.name = trimmedTitle;
        result = totpService.generateUri(parsed);
      }
    }

    if (result.length > TotpQrHelper.MAX_QR_CONTENT_LENGTH) {
      return null;
    }
    return result;
  }
}
