import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import {
  registerDefaultHandlers,
  FormatHandlerRegistry,
  ImportService,
  ExportService,
  ImportExportFacade,
  ImportExportViewModel,
  Result,
  ImportError,
  ExportError,
  ImportExportErrorCode,
  CsvImportHandler,
  XmlImportHandler,
  BitwardenJsonImportHandler,
  CsvExportHandler,
  XmlExportHandler,
  KdbxExportHandler,
  KeyFileExportHandler
} from '../../../../main/ets/services/importExport/index';

/**
 * importExport/index.ets 桶文件单元测试
 * 测试目标：
 * 1. registerDefaultHandlers() 将默认导入/导出处理器注册进单例注册表
 *    （按扩展名 + 格式 ID 双键可查）
 * 2. 桶再导出的公共符号（类/枚举/函数）均可访问
 */
export default function IndexTest() {
  describe('importExportIndex', () => {
    let registry: FormatHandlerRegistry;

    beforeAll(() => {
      registry = FormatHandlerRegistry.getInstance();
      registerDefaultHandlers();
    });

    describe('registerDefaultHandlers_importHandlers', () => {
      it('shouldRegisterCsvImportHandlerByExtension', 0, () => {
        const handler = registry.getImportHandler('.csv');
        expect(handler).not().assertUndefined();
        expect(handler?.formatId).assertEqual('CSV');
      });

      it('shouldRegisterXmlImportHandlerByExtension', 0, () => {
        const handler = registry.getImportHandler('.xml');
        expect(handler).not().assertUndefined();
        expect(handler?.formatId).assertEqual('XML');
      });

      it('shouldRegisterJsonFamilyDispatcherByExtension', 0, () => {
        const handler = registry.getImportHandler('.json');
        expect(handler).not().assertUndefined();
        expect(handler?.formatId).assertEqual('JSON');
      });

      it('shouldRegisterImportHandlersByFormatId', 0, () => {
        expect(registry.getImportHandler('CSV')?.formatId).assertEqual('CSV');
        expect(registry.getImportHandler('XML')?.formatId).assertEqual('XML');
        expect(registry.getImportHandler('JSON')?.formatId).assertEqual('JSON');
      });

      it('shouldIncludeAllImportFormatsInSupportedList', 0, () => {
        const formats = registry.getSupportedImportFormats();
        const ids: string[] = [];
        for (const f of formats) {
          ids.push(f.formatId);
        }
        expect(ids.includes('CSV')).assertTrue();
        expect(ids.includes('XML')).assertTrue();
        expect(ids.includes('JSON')).assertTrue();
      });
    });

    describe('registerDefaultHandlers_exportHandlers', () => {
      it('shouldRegisterCsvExportHandlerByFormatId', 0, () => {
        const handler = registry.getExportHandler('CSV');
        expect(handler).not().assertUndefined();
        expect(handler?.formatId).assertEqual('CSV');
      });

      it('shouldRegisterXmlExportHandlerByFormatId', 0, () => {
        const handler = registry.getExportHandler('XML');
        expect(handler).not().assertUndefined();
        expect(handler?.formatId).assertEqual('XML');
      });

      it('shouldRegisterKdbxExportHandlerByFormatId', 0, () => {
        const handler = registry.getExportHandler('KDBX');
        expect(handler).not().assertUndefined();
        expect(handler?.formatId).assertEqual('KDBX');
      });

      it('shouldRegisterKeyFileExportHandlerByFormatId', 0, () => {
        const handler = registry.getExportHandler('KEY_FILE');
        expect(handler).not().assertUndefined();
        expect(handler?.formatId).assertEqual('KEY_FILE');
      });

      it('shouldRegisterExportHandlersByExtension', 0, () => {
        expect(registry.getExportHandler('.csv')?.formatId).assertEqual('CSV');
        expect(registry.getExportHandler('.xml')?.formatId).assertEqual('XML');
        expect(registry.getExportHandler('.kdbx')?.formatId).assertEqual('KDBX');
        expect(registry.getExportHandler('.key')?.formatId).assertEqual('KEY_FILE');
        expect(registry.getExportHandler('.keyx')?.formatId).assertEqual('KEY_FILE');
      });

      it('shouldIncludeAllExportFormatsInSupportedList', 0, () => {
        const formats = registry.getSupportedExportFormats();
        const ids: string[] = [];
        for (const f of formats) {
          ids.push(f.formatId);
        }
        expect(ids.includes('CSV')).assertTrue();
        expect(ids.includes('XML')).assertTrue();
        expect(ids.includes('KDBX')).assertTrue();
        expect(ids.includes('KEY_FILE')).assertTrue();
      });
    });

    describe('registerDefaultHandlers_idempotent', () => {
      it('shouldNotBreakWhenCalledMultipleTimes', 0, () => {
        registerDefaultHandlers();
        registerDefaultHandlers();

        expect(registry.getImportHandler('.csv')?.formatId).assertEqual('CSV');
        expect(registry.getExportHandler('KDBX')?.formatId).assertEqual('KDBX');
      });
    });

    describe('reExportedSymbols', () => {
      it('shouldExposeServiceClasses', 0, () => {
        expect(FormatHandlerRegistry).not().assertUndefined();
        expect(ImportService).not().assertUndefined();
        expect(ExportService).not().assertUndefined();
        expect(ImportExportFacade).not().assertUndefined();
        expect(ImportExportViewModel).not().assertUndefined();
      });

      it('shouldExposeHandlerClasses', 0, () => {
        expect(CsvImportHandler).not().assertUndefined();
        expect(XmlImportHandler).not().assertUndefined();
        expect(BitwardenJsonImportHandler).not().assertUndefined();
        expect(CsvExportHandler).not().assertUndefined();
        expect(XmlExportHandler).not().assertUndefined();
        expect(KdbxExportHandler).not().assertUndefined();
        expect(KeyFileExportHandler).not().assertUndefined();
      });

      it('shouldExposeErrorTypesAndCodes', 0, () => {
        expect(ImportError).not().assertUndefined();
        expect(ExportError).not().assertUndefined();
        expect(ImportExportErrorCode).not().assertUndefined();
        expect(ImportExportErrorCode.UNSUPPORTED_FORMAT).assertEqual('UNSUPPORTED_FORMAT');
        expect(ImportExportErrorCode.FILE_EMPTY).assertEqual('FILE_EMPTY');
        expect(ImportExportErrorCode.EXPORT_FAILED).assertEqual('EXPORT_FAILED');
      });

      it('shouldExposeResultClass', 0, () => {
        expect(Result).not().assertUndefined();
        const ok = Result.success<string>('ok');
        expect(ok.isSuccess).assertTrue();
        expect(ok.value).assertEqual('ok');
        const fail = Result.failure<string>('CODE', 'msg');
        expect(fail.isSuccess).assertFalse();
        expect(fail.errorCode).assertEqual('CODE');
      });

      it('shouldConstructFacadeAndViewModelInstances', 0, () => {
        const facade = new ImportExportFacade();
        const vm = new ImportExportViewModel();
        expect(facade).not().assertNull();
        expect(vm).not().assertNull();
        // facade 委托注册表，应能返回已注册格式
        expect(facade.getSupportedExportFormats().length).assertLarger(0);
        expect(vm.getImportFormatOptions().length).assertLarger(0);
      });
    });
  });
}
