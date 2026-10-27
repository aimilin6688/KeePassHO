// services/importExport/viewmodel/ImportExportViewModel.ets

import { Result } from './common/Result';
import { FormatInfo } from './common/FormatInfo';
import { ImportExportFacade } from './ImportExportFacade';
import { ImportSessionInfo } from './common/ImportSessionInfo';
import { ImportFormatGroupInfo } from './catalog/ImportFormatCatalog';
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
  /** 最近一次导入失败错误码（JSON 引导弹窗判定用） */
  lastErrorCode: string = '';
  /** 最近一次导入嗅探到的格式名（成功提示文案用，未检测到为空串） */
  lastImportFormatName: string = '';

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
   * 获取导入格式分组清单（帮助面板等 UI 的单一数据源）
   */
  getImportFormatCatalog(): ImportFormatGroupInfo[] {
    return this.facade.getImportFormatCatalog();
  }

  /**
   * 顶层导入格式下拉选项显示文案（CSV 文件 / JSON 文件 / KeePass XML，未知回落原名）
   */
  displayImportFormatLabel(formatId: string): string {
    if (formatId === 'CSV') {
      return ResourceManager.getString($r('app.string.import_format_label_csv'));
    }
    if (formatId === 'JSON') {
      return ResourceManager.getString($r('app.string.import_format_label_json'));
    }
    if (formatId === 'XML') {
      return ResourceManager.getString($r('app.string.import_format_label_xml'));
    }
    return formatId;
  }

  /**
   * 执行导入
   */
  async executeImport(location: LocationInfo): Promise<boolean> {
    this.isLoading = true;
    this.errorMessage = '';
    this.lastErrorCode = '';
    this.lastImportFormatName = '';

    const result = await this.facade.importToCurrentDatabase(location);

    this.isLoading = false;

    if (result.isSuccess && result.value) {
      this.lastImportedCount = this.countItems(result.value);
      this.lastImportFormatName = ImportSessionInfo.getInstance().detectedFormatName;
      return true;
    } else {
      this.lastErrorCode = result.errorCode || '';
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
