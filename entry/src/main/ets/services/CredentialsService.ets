import { KdbxCredentials, ProtectedValue } from 'kdbxweb';
import ResourceManager from '../common/utils/ResourceManager';
import { StorageType } from './kdbx/interfaces';
import { KdbxFileManager } from './kdbx/KdbxFileManager';
import { AuthType, CredentialsParam } from './TypeDefined';

/**
 * 凭证服务
 */
export class CredentialsService {
  /**
   * 创建凭证
   * @param param 请求
   * @return Promise<KdbxCredentials> 凭证
   */
  public static async createKdbxCredentials(param: CredentialsParam): Promise<KdbxCredentials> {
    // 创建凭证
    let credentials: KdbxCredentials;
    if (AuthType.useKeyAuth(param.authType)) {
      if (param.keyFilePath === undefined) {
        throw new Error(ResourceManager.getInstance().getString($r('app.string.error_keyfile_not_found')));
      }
      // 使用密码和密钥文件
      let keyFileContent = await new KdbxFileManager(StorageType.LOCAL).loadKdbxFile(param.keyFilePath);
      console.log('Load key file content success, keyFilePath: ', param.keyFilePath);
      credentials = new KdbxCredentials(ProtectedValue.fromString(param.password), keyFileContent);
    } else {
      // 仅使用密码
      credentials = new KdbxCredentials(ProtectedValue.fromString(param.password));
    }
    return Promise.resolve(credentials);
  }
}