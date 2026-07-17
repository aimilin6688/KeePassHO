// services/importExport/service/ExportService.ets

import { Kdbx } from 'kdbxweb';
import { FormatHandlerRegistry } from '../FormatHandlerRegistry';
import { KdbxFileManager } from '../../kdbx/KdbxFileManager';
import { ExportError, ImportExportErrorCode } from '../common/ImportExportError';
import { StorageType, StorageConfig } from '../../../storage';
import { DateUtils, ResourceManager } from '../../../common/utils';
import hilog from '@ohos.hilog';

const TAG = 'ExportService';
const DOMAIN = 0xFF00;

/**
 * 导出服务
 */
export class ExportService {
  private registry: FormatHandlerRegistry;

  constructor(registry: FormatHandlerRegistry) {
    this.registry = registry;
  }

  /**
   * 导出数据库
   * @param database 数据库对象
   * @param formatId 导出格式ID
   * @param filePath 保存路径
   * @param storageType 存储类型
   * @param storageConfig 存储配置
   */
  async export(
    database: Kdbx,
    formatId: string,
    filePath: string,
    storageType: StorageType,
    storageConfig?: StorageConfig
  ): Promise<void> {
    // 1. 查找处理器
    const handler = this.registry.getExportHandler(formatId);
    if (!handler) {
      hilog.error(DOMAIN, TAG, 'Unsupported export format: %{public}s', formatId);
      throw new ExportError(
        ImportExportErrorCode.UNSUPPORTED_FORMAT,
        ResourceManager.getString($r('app.string.import_export_unsupported_format'), formatId)
      );
    }

    // 2. 生成导出内容
    const content = await handler.export(database);

    // 3. 写入文件
    const fileManager = new KdbxFileManager(storageType, storageConfig);
    await fileManager.write(filePath, content);
  }

  /**
   * 获取导出文件名
   * @param formatId 格式ID
   * @param baseName 基础文件名
   * @param appendDate 是否追加日期
   */
  getExportFileName(formatId: string, baseName: string, appendDate: boolean = true): string {
    const handler = this.registry.getExportHandler(formatId);
    const nowTime = DateUtils.getCurrentDate();
    let fileName = baseName || nowTime;

    // 获取扩展名
    if (handler && handler.supportedExtensions.length > 0) {
      const ext = handler.supportedExtensions[0];
      // 确保文件名有正确的扩展名
      if (!fileName.toLowerCase().endsWith(ext.toLowerCase())) {
        // 移除现有扩展名
        const lastDot = fileName.lastIndexOf('.');
        if (lastDot > 0) {
          fileName = fileName.substring(0, lastDot);
        }
        fileName = fileName + ext;
      }
    } else {
      // 默认使用 .kdbx
      if (!fileName.toLowerCase().endsWith('.kdbx')) {
        const lastDot = fileName.lastIndexOf('.');
        if (lastDot > 0) {
          fileName = fileName.substring(0, lastDot);
        }
        fileName = fileName + '.kdbx';
      }
    }

    // 追加日期
    if (appendDate && fileName !== nowTime) {
      const lastDot = fileName.lastIndexOf('.');
      if (lastDot > 0) {
        fileName = fileName.substring(0, lastDot) + '_' + nowTime + fileName.substring(lastDot);
      }
    }

    return fileName;
  }
}
