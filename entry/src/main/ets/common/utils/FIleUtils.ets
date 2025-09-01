import { fileShare, picker } from '@kit.CoreFileKit';
import { FileContentInfo, LocalFileStorage } from '../../services/kdbx/interfaces';
import { CommonUtils } from './CommonUtils';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import DateUtils from './DateUtils';

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
   * 使用保存弹框选择保存位置保存本地文件
   * @param path 文件路径
   * @param content 文件内容
   * @returns 结果
   */
  public static saveLocalFile(fileName: string, createContent: () => Promise<ArrayBuffer>): Promise<void> {
    // 使用文件选择器让用户选择保存位置
    const documentPicker = new picker.DocumentViewPicker(CommonUtils.getContext());
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];

    // 显示文件保存对话框
    return documentPicker.save(options).then(async (result) => {
      hilog.info(DOMAIN, TAG, `Selected save URIs: ${result}`);
      if (result && result.length > 0) {
        const filePath = result[0];
        return createContent().then(result => {
          return new LocalFileStorage().doWrite(filePath, result).then(result => {
            CommonUtils.showToast($r("app.string.save_success"));
          });
        }).catch((err: Error) => {
          hilog.error(DOMAIN, TAG, `Failed to create content: ${err.message}`, err.stack);
          CommonUtils.showToast(err.message);
          return Promise.reject(err.message);
        });
      }
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, `Failed to show document save dialog: ${err.message}`, err.stack);
      CommonUtils.showToast($r('app.string.CreateDatabase_location_failed', err.message));
      return Promise.reject(err.message);
    });
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
          let fileInfo = await localFile.doGetInfo(filePath);
          let fileContent = await localFile.doRead(filePath);
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

  /**
   * 替换文件名后缀
   * @param fileName 文件名
   * @param ext 后缀
   * @returns 文件名
   */
  public static replaceExt(fileName: string, ext: string): string {
    if (!fileName) {
      return "";
    }
    // 如果文件名中没有后缀，或者最后一个字符是点，则去掉最后一个点并添加新后缀
    if (!fileName.includes('.') || fileName.endsWith('.')) {
      const trimmedFileName = fileName.endsWith('.') ? fileName.slice(0, -1) : fileName;
      return `${trimmedFileName}${ext}`;
    }
    // 替换文件名后缀为指定的后缀
    return fileName.replace(/\.[^.]+$/, ext);
  }

  /**
   * 文件名追加日期
   * @param fileName 文件名
   * @returns 添加日期后的文件名
   */
  public static fileNameAppendDate(fileName: string): string {
    if (!fileName) {
      return DateUtils.getCurrentDate();
    }
    const currentDate = DateUtils.getCurrentDate();
    const lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex === -1) {
      return `${fileName}_${currentDate}`;
    }
    const namePart = fileName.substring(0, lastDotIndex);
    const extPart = fileName.substring(lastDotIndex);
    return `${namePart}_${currentDate}${extPart}`;
  }
}