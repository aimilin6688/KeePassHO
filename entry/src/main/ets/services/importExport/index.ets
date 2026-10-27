// services/importExport/index.ets

import { FormatHandlerRegistry } from './FormatHandlerRegistry';
import { CsvFamilyDispatcherImportHandler } from './handlers/import/CsvFamilyDispatcherImportHandler';
import { XmlImportHandler } from './handlers/import/XmlImportHandler';
import { BitwardenJsonImportHandler } from './handlers/import/BitwardenJsonImportHandler';
import { JsonFamilyDispatcherImportHandler } from './handlers/import/JsonFamilyDispatcherImportHandler';
import { CsvExportHandler } from './handlers/export/CsvExportHandler';
import { XmlExportHandler } from './handlers/export/XmlExportHandler';
import { KdbxExportHandler } from './handlers/export/KdbxExportHandler';
import { KeyFileExportHandler } from './handlers/export/KeyFileExportHandler';

// 公共类型
export { Result } from './common/Result';
export { ImportError, ExportError, ImportExportErrorCode } from './common/ImportExportError';
export type { FormatInfo } from './common/FormatInfo';

// 接口
export type { IImportHandler } from './handlers/IImportHandler';
export type { IExportHandler } from './handlers/IExportHandler';

// 注册表
export { FormatHandlerRegistry } from './FormatHandlerRegistry';

// 服务
export { ImportService } from './service/ImportService';
export { ExportService } from './service/ExportService';

// Facade
export { ImportExportFacade } from './ImportExportFacade';

// ViewModel
export { ImportExportViewModel } from './ImportExportViewModel';

// 导入处理器
export { CsvFamilyDispatcherImportHandler } from './handlers/import/CsvFamilyDispatcherImportHandler';
export { XmlImportHandler } from './handlers/import/XmlImportHandler';
export { BitwardenJsonImportHandler } from './handlers/import/BitwardenJsonImportHandler';
export { JsonFamilyDispatcherImportHandler } from './handlers/import/JsonFamilyDispatcherImportHandler';
export { PresetCsvImportHandler } from './handlers/import/PresetCsvImportHandler';

// 签名库（M2-4）
export { FormatSignatureLibrary, CsvFormatSignature, SignatureMatchResult } from './sniffing/FormatSignatureLibrary';

// 列映射向导（M2-4）
export { ImportWizardBridge, WizardPagePresenter } from './wizard/ImportWizardBridge';
export {
  ColumnMappingItem,
  ColumnMappingProfile,
  CsvMappingPreview,
  WizardMappingConflict,
  WizardValidationResult
} from './csvimport/CsvMappingModels';
export { CsvTargetField } from './csvimport/CsvImportModels';

// 导出处理器
export { CsvExportHandler } from './handlers/export/CsvExportHandler';
export { XmlExportHandler } from './handlers/export/XmlExportHandler';
export { KdbxExportHandler } from './handlers/export/KdbxExportHandler';
export { KeyFileExportHandler } from './handlers/export/KeyFileExportHandler';

/**
 * 注册默认处理器
 * 应在应用启动时调用一次
 */
export function registerDefaultHandlers(): void {
  const registry = FormatHandlerRegistry.getInstance();

  // 注册导入处理器
  registry.registerImportHandler(new CsvFamilyDispatcherImportHandler());
  registry.registerImportHandler(new XmlImportHandler());
  registry.registerImportHandler(new JsonFamilyDispatcherImportHandler());

  // 注册导出处理器
  registry.registerExportHandler(new CsvExportHandler());
  registry.registerExportHandler(new XmlExportHandler());
  registry.registerExportHandler(new KdbxExportHandler());
  registry.registerExportHandler(new KeyFileExportHandler());
}
