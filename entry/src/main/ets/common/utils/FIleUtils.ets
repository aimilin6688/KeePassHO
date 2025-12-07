import { fileShare, picker } from '@kit.CoreFileKit';
import { FileContentInfo, LocalFileStorage } from '../../storage';
import { CommonUtils } from './CommonUtils';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { FilenameUtils } from './FilenameUtils';

const DOMAIN = 0x0000;
const TAG = 'LocalFileStorage';

export default class FileUtils {
  private static FolderAuthorization: string = 'SystemCapability.FileManagement.AppFileService.FolderAuthorization';

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
  public static saveLocalFile(fileName: string, createContent: (filePath: string) => Promise<ArrayBuffer>): Promise<void> {
    // 使用文件选择器让用户选择保存位置
    const documentPicker = new picker.DocumentViewPicker(CommonUtils.getContext());
    const options = new picker.DocumentSaveOptions();
    options.newFileNames = [fileName];

    // 显示文件保存对话框
    return documentPicker.save(options).then(async (result) => {
      hilog.info(DOMAIN, TAG, `Selected save URIs: ${result}`);
      if (result && result.length > 0) {
        const filePath = result[0];
        return createContent(filePath).then(result => {
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

  public static getFileIcon(fileName: string): Resource {
    const fileExt = FilenameUtils.getFileExt(fileName).toLowerCase();
    switch (fileExt) {
      case 'txt':
        return $r('app.media.file_text');
      case 'pdf':
        return $r('app.media.file_pdf');
      case 'doc':
      case 'docx':
        return $r('app.media.file_word');
      case 'xls':
      case 'xlsx':
        return $r('app.media.file_excel');
      case 'ppt':
      case 'pptx':
        return $r('app.media.file_powerpoint');
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return $r('app.media.file_image');
      case 'iav':
      case 'mp3':
        return $r('app.media.file_audio');
      case 'mp4':
        return $r('app.media.file_video');
      case 'zip':
      case 'rar':
      case '7z':
        return $r('app.media.file_zipper');
      case 'kdbx':
        return $r('app.media.startIcon');
      case 'csv':
        return $r('app.media.file_csv');
      case 'xml':
        return $r('app.media.file_code');
    }
    return $r('app.media.file_text');
  }
}