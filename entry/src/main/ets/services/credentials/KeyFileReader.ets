import { hilog } from '@kit.PerformanceAnalysisKit';
import { ResourceManager } from '../../common/utils';
import { KdbxFileManager } from '../kdbx/KdbxFileManager';
import { CredentialsParam } from '../TypeDefined';

const DOMAIN = 0x0000;
const TAG = 'KeyFileReader';

/**
 * 密钥文件读取工具
 */
export class KeyFileReader {
  /**
   * 校验密钥文件路径并读取内容
   * @param param 凭证参数
   * @param scenario 日志场景标识
   * @throws Error 密钥文件路径缺失时抛出
   */
  public static async requireAndRead(param: CredentialsParam, scenario: string): Promise<ArrayBuffer> {
    if (param.keyLocation === undefined) {
      throw new Error(ResourceManager.getString($r('app.string.error_keyfile_not_found')));
    }
    const keyFile = await KdbxFileManager.of(param.keyLocation).read(param.keyLocation.filePath);
    hilog.info(DOMAIN, TAG, 'Load key file content success (%{public}s), keyFilePath: %{public}s',
      scenario, param.keyLocation.filePath);
    return keyFile.content;
  }
}
