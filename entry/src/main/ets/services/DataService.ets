import { ReadDataOptions, WriteDataOptions } from './TypeDefined';
import { Router } from '@kit.ArkUI';
import { RecentFilesService } from './RecentFilesService';
import { KdbxExportService } from './kdbx/KdbxExportService';
import { KdbxFileManager } from './kdbx/KdbxFileManager';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from '../common/utils/CommonUtils';

const DOMAIN = 0x0000;
const TAG = 'DataService';
/**
 * 数据服务
 */
export class DataService {
  /**
   * 设置数据库信息，并跳转到打开页面
   * @param router
   * @param param
   */
  public static readData(router: Router, param: ReadDataOptions): void {
    // 添加到最近打开的文件列表
    RecentFilesService.addRecentFile({
      filePath: param.filePath,
      fileName: param.fileName,
      storageType: param.storageType,
      storageConfig: param.storageConfig
    }).then(() => {
      // 导航到密码输入页面
      router.pushUrl({
        url: 'pages/Password',
        params: {
          filePath: param.filePath
        }
      });
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to read data file: %{public}s, error: %{public}s', param.filePath, error.message);
      CommonUtils.showToast($r('app.string.open_failed', error.message));
    });
  }

  /**
   * 写入数据到指定配置
   */
  public static writeData(param: WriteDataOptions): Promise<void> {
    // 触发写入前的事件
    if (param.onBeforeWrite) {
      param.onBeforeWrite(param);
    }
    return KdbxExportService.createExportFile(param).then(result => {
      return new KdbxFileManager(param.storageType, param.storageConfig).write(param.filePath, result.content);
    });
  }
}