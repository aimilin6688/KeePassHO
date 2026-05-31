// services/importExport/service/ImportService.ets

import { KdbxGroup } from 'kdbxweb';
import { FormatHandlerRegistry } from '../FormatHandlerRegistry';
import { KdbxFileManager } from '../../kdbx/KdbxFileManager';
import { ImportError, ImportExportErrorCode } from '../common/ImportExportError';
import { StorageType, StorageConfig } from '../../../storage';

/**
 * 导入服务
 */
export class ImportService {
  private registry: FormatHandlerRegistry;

  constructor(registry: FormatHandlerRegistry) {
    this.registry = registry;
  }

  /**
   * 导入文件
   * @param filePath 文件路径
   * @param storageType 存储类型
   * @param storageConfig 存储配置
   * @returns 解析后的 KdbxGroup
   */
  async import(
    filePath: string,
    storageType: StorageType,
    storageConfig?: StorageConfig
  ): Promise<KdbxGroup> {
    // 1. 获取文件扩展名
    const extension = this.getExtension(filePath);

    // 2. 查找处理器
    const handler = this.registry.getImportHandler(extension);
    if (!handler) {
      throw new ImportError(
        ImportExportErrorCode.UNSUPPORTED_FORMAT,
        `不支持的文件格式: ${extension}`
      );
    }

    // 3. 检查文件是否存在并读取内容
    const fileManager = new KdbxFileManager(storageType, storageConfig);
    const fileContent = await fileManager.read(filePath);

    // 4. 调用处理器解析
    return handler.import(fileContent);
  }

  /**
   * 获取文件扩展名
   */
  getExtension(filePath: string): string {
    const lastDot = filePath.lastIndexOf('.');
    return lastDot !== -1 ? filePath.substring(lastDot).toLowerCase() : '';
  }
}
