import { ByteUtils, KdbxChallengeResponseFn, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { ResourceManager } from '../common/utils';
import { KdbxFileManager } from './kdbx/KdbxFileManager';
import { AuthType, CredentialsParam } from './TypeDefined';

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'CredentialsService';

/**
 * 凭证服务
 */
export class CredentialsService {
  /**
   * 创建凭证
   * @param param 请求
   * @return Promise<KdbxCredentials> 凭证
   * @throws Error 错误
   */
  public static async createKdbxCredentials(param: CredentialsParam): Promise<KdbxCredentials> {
    // 创建凭证
    let credentials: KdbxCredentials;

    if (AuthType.useChallengeResponseXc(param.authType)) {
      // KeePassXC 兼容挑战-应答：主线程已预计算应答，以固定应答回调组装
      // （kdbxweb 加载时对 KDF seed 调用回调，对返回值 SHA-256 后并入复合密钥）
      if (!param.challengeResponseHex) {
        throw new Error(ResourceManager.getString($r('app.string.error_challenge_response_missing')));
      }
      const responseBytes: Uint8Array = ByteUtils.hexToBytes(param.challengeResponseHex);
      // 每次调用返回副本：kdbxweb 哈希后会 zeroBuffer 清零返回的缓冲
      const fixedResponse: KdbxChallengeResponseFn = (_challenge: ArrayBuffer) => {
        const copy: Uint8Array = new Uint8Array(responseBytes.length);
        copy.set(responseBytes);
        return Promise.resolve(copy);
      };
      if (AuthType.useKeyAuth(param.authType)) {
        // 密码 + 密钥文件 + 挑战-应答（XC）
        if (param.keyLocation === undefined) {
          throw new Error(ResourceManager.getString($r('app.string.error_keyfile_not_found')));
        }
        const keyFile = await KdbxFileManager.of(param.keyLocation).read(param.keyLocation.filePath);
        hilog.info(DOMAIN, TAG, 'Load key file content success (challenge-response xc), keyFilePath: %{public}s', param.keyLocation.filePath);
        credentials = new KdbxCredentials(ProtectedValue.fromString(param.password), keyFile.content, fixedResponse);
      } else {
        // 密码 + 挑战-应答（XC）
        credentials = new KdbxCredentials(ProtectedValue.fromString(param.password), null, fixedResponse);
      }
    } else if (AuthType.useOtpAuth(param.authType) || AuthType.useChallengeAuth(param.authType)) {
      // OTP（OtpKeyProv）/恢复模式，及 KeeChallenge 旧版（P2，同以 secret 作为自定义密钥分量）：
      // secret 以 KcpCustomKey（bPerformHash=true）语义并入复合密钥
      if (!param.otpSecretHex) {
        throw new Error(ResourceManager.getString($r('app.string.error_otp_secret_missing')));
      }
      credentials = new KdbxCredentials(ProtectedValue.fromString(param.password), null, undefined,
        ByteUtils.hexToBytes(param.otpSecretHex));
    } else if (AuthType.isKeyfileOnly(param.authType)) {
      // 仅密钥文件模式
      if (param.keyLocation === undefined) {
        throw new Error(ResourceManager.getString($r('app.string.error_keyfile_not_found')));
      }
      let keyFileContent = await KdbxFileManager.of(param.keyLocation).read(param.keyLocation.filePath);
      hilog.info(DOMAIN, TAG, 'Load key file content success (keyfile only), keyFilePath: %{public}s', param.keyLocation.filePath);
      // 密码为 null，仅使用密钥文件
      credentials = new KdbxCredentials(null, keyFileContent.content);
    } else if (AuthType.useKeyAuth(param.authType)) {
      // 密码 + 密钥文件模式
      if (param.keyLocation === undefined) {
        throw new Error(ResourceManager.getString($r('app.string.error_keyfile_not_found')));
      }
      let keyFileContent = await KdbxFileManager.of(param.keyLocation).read(param.keyLocation.filePath);
      hilog.info(DOMAIN, TAG, 'Load key file content success, keyFilePath: %{public}s', param.keyLocation.filePath);
      credentials = new KdbxCredentials(ProtectedValue.fromString(param.password), keyFileContent.content);
    } else {
      // 仅使用密码
      credentials = new KdbxCredentials(ProtectedValue.fromString(param.password));
    }

    return Promise.resolve(credentials);
  }
}