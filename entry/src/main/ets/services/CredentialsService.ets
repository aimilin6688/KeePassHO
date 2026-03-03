import { KdbxCredentials, ProtectedValue } from 'kdbxweb';
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

    if (AuthType.isKeyfileOnly(param.authType)) {
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