/**
 * 扫码服务 - 用于扫描二维码并解析TOTP配置
 */
import { scanBarcode, scanCore } from '@kit.ScanKit';
import { TotpService } from './TotpService';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import ResourceManager from '../common/utils/ResourceManager';

const DOMAIN = 0x0000;
const TAG = 'ScanService';

/**
 * 扫码服务类
 */
export class ScanService {
  private context: UIContext;

  constructor(context: UIContext) {
    this.context = context;
  }

  /**
   * 启动扫码
   * @returns 扫码结果Promise
   */
  public async startScan(): Promise<ScanResult> {
    try {
      // 定义扫码参数options
      let options: scanBarcode.ScanOptions = {
        scanTypes: [scanCore.ScanType.ALL],
        enableMultiMode: true,
        enableAlbum: true
      };
      // 启动扫码
      return scanBarcode.startScanForResult(this.context.getHostContext(), options).then((result: scanBarcode.ScanResult) => {
        if (result && result.originalValue) {
          return ScanResult.success(result.originalValue);
        } else {
          return ScanResult.fail('扫码失败');
        }
      })
        .catch((error: BusinessError) => {
          hilog.error(DOMAIN, TAG, `Failed to get ScanResult by promise with options. Code:${error.code}, message: ${error.message}`);
          return ScanResult.fail(error.message);
        });
      ;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to get ScanResult by promise with options. Code:${error.code}, message: ${error.message}`);
      return ScanResult.fail(error.message);
    }
  }

  /**
   * 扫描TOTP二维码
   * @returns 扫码结果Promise，如果成功且内容是有效的TOTP URI，则解析为TOTP配置
   */
  public async scanTotpQrCode(): Promise<ScanResult> {
    try {
      // 启动扫码
      const scanResult = await this.startScan();

      if (!scanResult.success) {
        return scanResult;
      }

      const content = scanResult.content;

      // 检查是否是TOTP URI
      if (content && content.startsWith('otpauth://totp/')) {
        // 解析TOTP URI
        const totpConfig = TotpService.getInstance().parseUri(content);

        if (totpConfig) {
          return ScanResult.success(content);
        } else {
          return ScanResult.fail(ResourceManager.getString($r("app.string.totp_invalid_uri")));
        }
      } else {
        return ScanResult.fail(ResourceManager.getString($r("app.string.qrcode_is_not_totp_uri")));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Scan content error: ${error.message}`)
      return ScanResult.fail(error.message);
    }
  }

  /**
   * 解析二维码内容
   * @param content 二维码内容
   * @returns 解析结果
   */
  public parseScanContent(content: string): ScanResult {
    try {
      // 检查是否是TOTP URI
      if (content && content.startsWith('otpauth://totp/')) {
        // 解析TOTP URI
        const totpConfig = TotpService.getInstance().parseUri(content);

        if (totpConfig) {
          return ScanResult.success(content);
        } else {
          return ScanResult.fail(ResourceManager.getString($r("app.string.totp_invalid_uri")));
        }
      } else {
        return ScanResult.fail(ResourceManager.getString($r("app.string.qrcode_is_not_totp_uri")));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Parse scan content error: ${error.message}`)
      return ScanResult.fail(error.message);
    }
  }
}

/**
 * 扫码结果接口
 */
export class ScanResult {
  /**
   * 是否成功
   */
  success: boolean;
  /**
   * 扫码内容
   */
  content?: string;
  /**
   * 错误信息
   */
  error?: string;

  constructor(success: boolean, content?: string, error?: string) {
    this.success = success;
    this.content = content;
    this.error = error;
  }

  public static success(content: string): ScanResult {
    return new ScanResult(true, content);
  }

  public static fail(error: string): ScanResult {
    return new ScanResult(false, undefined, error);
  }
}