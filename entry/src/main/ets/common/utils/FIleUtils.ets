import { fileShare } from '@kit.CoreFileKit';
import { BusinessError } from '@kit.BasicServicesKit';

export default class FileUtils {

  /**
   * 获取文件名
   * @param filePath 文件路径
   */
  public static getFileName(filePath: string): string {
    if(!filePath){
      return "";
    }
    const fileNameMatch = filePath.match(/[^/]+$/);
    return  fileNameMatch ? fileNameMatch[0] : '';
  }


  /**
   * 激活文件权限
   * @param path 文件路径
   * @returns 结果
   */
  public static async  activatePermission(path: string, operationMode: fileShare.OperationMode): Promise<void> {
    if (!canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')) {
      throw new Error('this api is not supported on this device');
    }
    let policyInfo: fileShare.PolicyInfo = {
      uri: path,
      operationMode: operationMode,
    };
    let policies: Array<fileShare.PolicyInfo> = [policyInfo];
    fileShare.activatePermission(policies).then(() => {
      return Promise.resolve();
    }).catch((error: BusinessError<Array<fileShare.PolicyErrorResult>>) => {
      console.error("activatePermission failed with error message: " + error.message + ", error code: " + error.code);
      throw new Error(`Failed to activate Permission file: ${error.message}`);
    });
  }

  /**
   * 激活文件权限
   * @param path 文件路径
   * @returns 结果
   */
  public static async persistPermission(path: string, operationMode: fileShare.OperationMode): Promise<void> {
    if (!canIUse('SystemCapability.FileManagement.AppFileService.FolderAuthorization')) {
      throw new Error('this api is not supported on this device');
    }
    let policyInfo: fileShare.PolicyInfo = {
      uri: path,
      operationMode: operationMode,
    };
    let policies: Array<fileShare.PolicyInfo> = [policyInfo];
    return fileShare.persistPermission(policies).catch((error: BusinessError<Array<fileShare.PolicyErrorResult>>) => {
      console.error("PersistPermission failed with error message: " + error.message + ", error code: " + error.code);
      throw new Error(`Failed to persist Permission file: ${error.message}`);
    });
  }
}