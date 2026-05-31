// services/importExport/facade/ImportExportFacade.ets

import { KdbxGroup } from 'kdbxweb';
import { Result } from '../common/Result';
import { ImportExportErrorCode, ImportError, ExportError } from '../common/ImportExportError';
import { ImportService } from '../service/ImportService';
import { ExportService } from '../service/ExportService';
import { FormatHandlerRegistry } from '../registry/FormatHandlerRegistry';
import { FormatInfo } from '../common/FormatInfo';
import { FileService } from '../../FileService';
import { KdbxUtils } from '../../../common/utils';
import { LocationInfo } from '../../beans/LocationParam';
import { ToastSaveDatabaseCallback } from '../../../workers/callback/ToastSaveDatabaseCallback';

/**
 * 导入导出外观服务
 */
export class ImportExportFacade {
  private importService: ImportService;
  private exportService: ExportService;
  private registry: FormatHandlerRegistry;

  constructor() {
    this.registry = FormatHandlerRegistry.getInstance();
    this.importService = new ImportService(this.registry);
    this.exportService = new ExportService(this.registry);
  }

  /**
   * 导入文件到当前数据库
   */
  async importToCurrentDatabase(location: LocationInfo): Promise<Result<KdbxGroup>> {
    try {
      // 1. 执行导入
      const importedGroup = await this.importService.import(
        location.filePath,
        location.storageType,
        location.storageConfig
      );

      // 2. 合并到当前数据库
      const database = FileService.getDatabase();
      const rootGroup = database.getDefaultGroup();

      // 合并分组
      if (importedGroup.groups && importedGroup.groups.length > 0) {
        for (const group of importedGroup.groups) {
          group.parentGroup = rootGroup;
          rootGroup.groups.push(group);
        }
      }

      // 合并条目
      if (importedGroup.entries && importedGroup.entries.length > 0) {
        for (const entry of importedGroup.entries) {
          entry.parentGroup = rootGroup;
          rootGroup.entries.push(entry);
        }
      }

      // 3. 保存数据库
      await this.saveDatabase();

      return Result.success(importedGroup);
    } catch (error) {
      return this.handleError(error);
    }
  }

  /**
   * 导出当前数据库
   */
  async exportCurrentDatabase(
    formatId: string,
    location: LocationInfo
  ): Promise<Result<void>> {
    try {
      const database = FileService.getDatabase();

      await this.exportService.export(
        database,
        formatId,
        location.filePath,
        location.storageType,
        location.storageConfig
      );

      return Result.success<void>(undefined as void);
    } catch (error) {
      return this.handleError(error);
    }
  }

  /**
   * 获取支持的导入格式列表
   */
  getSupportedImportFormats(): FormatInfo[] {
    return this.registry.getSupportedImportFormats();
  }

  /**
   * 获取支持的导出格式列表
   */
  getSupportedExportFormats(): FormatInfo[] {
    return this.registry.getSupportedExportFormats();
  }

  /**
   * 获取导出文件名
   */
  getExportFileName(formatId: string, baseName: string): string {
    return this.exportService.getExportFileName(formatId, baseName);
  }

  /**
   * 保存数据库
   */
  private saveDatabase(): Promise<void> {
    return new Promise((resolve, reject) => {
      KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
        onSuccess: () => resolve(),
        onError: (message: string) => reject(new Error(message))
      }));
    });
  }

  /**
   * 统一错误处理
   */
  private handleError<T>(error: Error | ImportError | ExportError): Result<T> {
    if (error instanceof ImportError || error instanceof ExportError) {
      return Result.failure(error.code, error.message);
    }
    if (error instanceof Error) {
      return Result.failure(ImportExportErrorCode.PARSE_ERROR, error.message);
    }
    return Result.failure(ImportExportErrorCode.PARSE_ERROR, '未知错误');
  }
}
