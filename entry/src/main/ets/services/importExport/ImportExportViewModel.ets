// services/importExport/viewmodel/ImportExportViewModel.ets

import { Result } from './common/Result';
import { FormatInfo } from './common/FormatInfo';
import { ImportExportFacade } from './ImportExportFacade';
import { LocationInfo } from '../beans/LocationParam';
import { KdbxGroup } from 'kdbxweb';
import { FileService } from '../FileService';
import { DateUtils, ResourceManager } from '../../common/utils';

/**
 * 导入导出视图模型
 */
export class ImportExportViewModel {
  private facade: ImportExportFacade;

  // UI 状态
  isLoading: boolean = false;
  errorMessage: string = '';
  lastImportedCount: number = 0;

  constructor() {
    this.facade = new ImportExportFacade();
  }

  /**
   * 获取支持的导入格式（用于 UI 下拉选项）
   */
  getImportFormatOptions(): FormatInfo[] {
    return this.facade.getSupportedImportFormats();
  }

  /**
   * 获取支持的导出格式
   */
  getExportFormatOptions(): FormatInfo[] {
    return this.facade.getSupportedExportFormats();
  }

  /**
   * 获取指定格式的文件扩展名
   */
  getFileExtensions(formatId: string): string[] {
    const formats = this.getImportFormatOptions();
    const format = formats.find(f => f.formatId === formatId);
    return format?.extensions || [];
  }

  /**
   * 获取导出文件名
   */
  getExportFileName(formatId: string): string {
    const dbFileParam = FileService.getDbFileParam();
    const baseName = dbFileParam?.fileName || DateUtils.getCurrentDate();
    return this.facade.getExportFileName(formatId, baseName);
  }

  /**
   * 执行导入
   */
  async executeImport(location: LocationInfo): Promise<boolean> {
    this.isLoading = true;
    this.errorMessage = '';

    const result = await this.facade.importToCurrentDatabase(location);

    this.isLoading = false;

    if (result.isSuccess && result.value) {
      this.lastImportedCount = this.countItems(result.value);
      return true;
    } else {
      this.errorMessage = result.errorMessage || ResourceManager.getString($r('app.string.import_export_import_failed'));
      return false;
    }
  }

  /**
   * 执行导出
   */
  async executeExport(formatId: string, location: LocationInfo): Promise<boolean> {
    this.isLoading = true;
    this.errorMessage = '';

    const result = await this.facade.exportCurrentDatabase(formatId, location);

    this.isLoading = false;

    if (result.isSuccess) {
      return true;
    } else {
      this.errorMessage = result.errorMessage || ResourceManager.getString($r('app.string.import_export_export_failed'));
      return false;
    }
  }

  /**
   * 统计导入的条目数量
   */
  private countItems(group: KdbxGroup): number {
    let count = group.entries?.length || 0;
    if (group.groups) {
      for (const subGroup of group.groups) {
        count += this.countItems(subGroup);
      }
    }
    return count;
  }
}
