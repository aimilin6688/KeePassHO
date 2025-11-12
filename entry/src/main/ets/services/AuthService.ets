import { userAuth } from '@kit.UserAuthenticationKit';
import ResourceManager from '../common/utils/ResourceManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { SettingsService } from './SettingsService';
import { CommonUtils } from '../common/utils/CommonUtils';
import { ByteUtils } from 'kdbxweb';

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
  private authTrustLevel: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL3; // 安全等级
  private authParam: userAuth.AuthParam = {
    challenge: ByteUtils.randomData(32),
    authType: [userAuth.UserAuthType.FINGERPRINT],
    authTrustLevel: this.authTrustLevel
  };
  private widgetParam: userAuth.WidgetParam = { title: ResourceManager.getString($r("app.string.widget_auth_title")) };
  private isFingerprintSupport = false;
  private isFaceSupport = false;

  private constructor() {
    this.isFingerprintSupport = this.checkFingerprintSupport();
    this.isFaceSupport = this.checkFaceSupport();
  }

  // 检查设备是否支持指纹功能
  private checkFingerprintSupport(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, this.authTrustLevel);
      return true;
    } catch (error) {
      hilog.info(DOMAIN, TAG, "Device does not support fingerprint auth!");
      return false;
    }
  }

  // 检查设备是否支持人脸识别
  private checkFaceSupport(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FACE, this.authTrustLevel);
      return true;
    } catch (error) {
      hilog.info(DOMAIN, TAG, "Device does not support face auth!");
      return false;
    }
  }

  /**
   * @description 开始指纹验证
   */
  public static startFingerprintAuth(callback: AuthServiceCallback) {
    if (!AuthService.instance.isFingerprintSupport) {
      CommonUtils.showToast($r('app.string.fingerprint_not_support'));
      return;
    }
    if (!SettingsService.isFingerprintAuthEnable()) {
      CommonUtils.showToast($r('app.string.fingerprint_not_enabled'));
      return;
    }
    AuthService.instance.authParam.authType = [userAuth.UserAuthType.FINGERPRINT];
    AuthService.instance.startAuth(callback);
  }

  /**
   * @description 开始人脸验证
   */
  public static startFaceAuth(callback: AuthServiceCallback) {
    if (!AuthService.instance.isFaceSupport) {
      CommonUtils.showToast($r('app.string.face_not_support'));
      return;
    }
    if (!SettingsService.isFaceAuthEnable()) {
      CommonUtils.showToast($r('app.string.face_not_enabled'));
      return;
    }
    AuthService.instance.authParam.authType = [userAuth.UserAuthType.FACE];
    AuthService.instance.startAuth(callback);
  }

  /**
   * @description 检查设备是否支持指纹功能
   * @returns
   */
  public static isFingerprintSupport(): boolean {
    try {
      return AuthService.instance.isFingerprintSupport;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, `isFingerprintSupport error. Code is ${err?.code}, message is ${err?.message}`);
      return false;
    }
  }

  public static isFaceSupport(): boolean {
    try {
      return AuthService.instance.isFaceSupport;
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, `isFaceSupport error. Code is ${err?.code}, message is ${err?.message}`);
      return false;
    }
  }

  public static isFingerprintSupportAndEnabled(): boolean {
    return AuthService.instance.isFingerprintSupport && SettingsService.isFingerprintAuthEnable();
  }

  public static isFaceSupportAndEnabled(): boolean {
    return AuthService.instance.isFaceSupport && SettingsService.isFaceAuthEnable();
  }

  // 开始指纹验证
  private startAuth(callback: AuthServiceCallback) {
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