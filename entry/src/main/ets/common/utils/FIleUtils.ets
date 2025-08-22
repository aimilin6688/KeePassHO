import { fileShare, picker } from '@kit.CoreFileKit';
import { FileContentInfo, LocalFileStorage } from '../../services/kdbx/interfaces';
import { CommonUtils } from './CommonUtils';

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'LocalFileStorage';

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

  /**
   * 写入文件内容到指定的路径
   * @param path 文件路径
   * @param content 文件内容
   * @returns 结果
   */
  public static saveFile(path: string, content: ArrayBuffer): Promise<void> {
    return new LocalFileStorage().writeFile(path, content);
  }

  /**
   * 选择文件，并返回文件内容
   * @param context 上下文
   * @returns 文件内容信息
   */
  public static async selectFiles(size: number, fileSuffixFilters?: Array<string>): Promise<Array<FileContentInfo>> {
    try {
      const documentPicker = new picker.DocumentViewPicker(CommonUtils.getContext());
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = fileSuffixFilters || []; // 只显示kdbx文件
      options.maxSelectNumber = size; // 只允许选择一个文件

      const result: Array<FileContentInfo> = [];
      const localFile = new LocalFileStorage();
      const selectResult = await documentPicker.select(options);
      if (selectResult && selectResult.length > 0) {
        for (const filePath of selectResult) {
          let fileInfo = await localFile.doFileInfo(filePath);
          let fileContent = await localFile.doReadFile(filePath);
          result.push(new FileContentInfo(fileInfo, fileContent));
        }
        return result;
      }
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to pick file: %{public}s,  stack: %{public}s`, error.message, error.stack);
      return Promise.reject(error);
    }
  }
}