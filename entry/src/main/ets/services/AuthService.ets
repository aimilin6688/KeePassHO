import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import ResourceManager from '../common/utils/ResourceManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = 'AuthService';

export interface AuthServiceCallback {
  /**
   * @description 验证成功
   * @param authResult
   */
  onSuccess?: (authResult: userAuth.UserAuthResult) => void;
  /**
   * @description 验证失败
   * @param authResult
   */
  onFail?: (authResult: userAuth.UserAuthResult) => void;
  /**
   * @description 验证异常
   * @param error
   */
  onError?: (error: BusinessError) => void;
}

/**
 * @description 验证服务
 */
export class AuthService {
  private static instance: AuthService = new AuthService();
  private rand = cryptoFramework.createRandom();
  private authTrustLevel: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL3; // 安全等级
  private authParam: userAuth.AuthParam = {
    challenge: this.rand?.generateRandomSync(16)?.data,
    authType: [userAuth.UserAuthType.FINGERPRINT],
    authTrustLevel: this.authTrustLevel
  };
  private widgetParam: userAuth.WidgetParam = { title: ResourceManager.getString($r("app.string.widget_auth_title")) };
  private isFingerprintSupport = this.checkFingerprintSupport();

  // 检查设备是否支持指纹功能
  private checkFingerprintSupport(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, this.authTrustLevel);
      return true;
    } catch (error) {
      hilog.info(DOMAIN, TAG, "Device does not support fingerprint");
      return false;
    }
  }

  /**
   * @description 开始指纹验证
   */
  public static startFingerprintAuth(callback: AuthServiceCallback) {
    AuthService.instance.startFingerprintAuth(callback);
  }

  /**
   * @description 检查设备是否支持指纹功能
   * @returns
   */
  public static isFingerprintSupport():boolean {
    return AuthService.instance.isFingerprintSupport;
  }

  // 开始指纹验证
  private startFingerprintAuth(callback: AuthServiceCallback) {
    try {
      const authInstance = userAuth.getUserAuthInstance(this.authParam, this.widgetParam);
      authInstance.on('result', {
        onResult(result) {
          if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
            if (callback.onSuccess) {
              callback.onSuccess(result);
            }
          } else {
            hilog.error(DOMAIN, TAG, "Auth fail，error：" + result.result);
            if (callback.onFail) {
              callback.onFail(result);
            }
          }
          authInstance.off('result');
        }
      });
      authInstance.start();
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, `auth catch error. Code is ${err?.code}, message is ${err?.message}`);
      if (callback.onError) {
        callback.onError(error);
      }
    }
  }
}