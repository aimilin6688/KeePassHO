import { fileShare } from '@kit.CoreFileKit';

export default class FileUtils {
  private static FolderAuthorization: string = 'SystemCapability.FileManagement.AppFileService.FolderAuthorization';
  /**
   * 获取文件名
   * @param filePath 文件路径
   */
  public static getFileName(filePath: string): string {
    if (!filePath) {
      return "";
    }
    const fileNameMatch = filePath.match(/[^/]+$/);
    return fileNameMatch ? decodeURIComponent(fileNameMatch[0]) : '';
  }


  /**
   * 激活文件权限
   * @param path 文件路径
   * @returns 结果
   */
  public static activatePermission(path: string, operationMode: fileShare.OperationMode): Promise<void> {
    if (!canIUse(FileUtils.FolderAuthorization)) {
      throw new Error('this api is not supported on this device');
    }
    let policyInfo: fileShare.PolicyInfo = {
      uri: path,
      operationMode: operationMode,
    };
    let policies: Array<fileShare.PolicyInfo> = [policyInfo];
    return fileShare.activatePermission(policies);
  }

  /**
   * 激活文件权限
   * @param path 文件路径
   * @returns 结果
   */
  public static persistPermission(path: string, operationMode: fileShare.OperationMode): Promise<void> {
    if (!canIUse(FileUtils.FolderAuthorization)) {
      throw new Error('this api is not supported on this device');
    }
    let policyInfo: fileShare.PolicyInfo = {
      uri: path,
      operationMode: operationMode,
    };
    let policies: Array<fileShare.PolicyInfo> = [policyInfo];
    return fileShare.persistPermission(policies);
  }

  /**
   * 校验文件权限
   * @param path 文件路径
   * @returns 结果
   */
  public static checkPersistPermission(path: string, operationMode: fileShare.OperationMode): Promise<Array<boolean>> {
    if (!canIUse(FileUtils.FolderAuthorization)) {
      throw new Error('this api is not supported on this device');
    }
    let policyInfo: fileShare.PolicyInfo = {
      uri: path,
      operationMode: operationMode,
    };
    let policies: Array<fileShare.PolicyInfo> = [policyInfo];
    return fileShare.checkPersistentPermission(policies);
  }

  /**
   * 取消文件持久化权限
   * @param path 文件路径
   * @returns 结果
   */
  public static revokePermission(path: string, operationMode: fileShare.OperationMode): Promise<void> {
    if (!canIUse(FileUtils.FolderAuthorization)) {
      throw new Error('this api is not supported on this device');
    }
    let policyInfo: fileShare.PolicyInfo = {
      uri: path,
      operationMode: operationMode,
    };
    let policies: Array<fileShare.PolicyInfo> = [policyInfo];
    return fileShare.revokePermission(policies);
  }
}