import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { FormatHandlerRegistry } from '../../../../main/ets/services/importExport/FormatHandlerRegistry';
import { IImportHandler } from '../../../../main/ets/services/importExport/handlers/IImportHandler';
import { IExportHandler } from '../../../../main/ets/services/importExport/handlers/IExportHandler';
import { FileContentInfo, FileType } from '../../../../main/ets/storage';
import { KdbxGroup, Kdbx } from 'kdbxweb';

/**
 * 模拟导入处理器
 */
class MockImportHandler implements IImportHandler {
  readonly supportedExtensions: string[];
  readonly formatName: string;
  readonly formatId: string;

  constructor(formatId: string, formatName: string, extensions: string[]) {
    this.formatId = formatId;
    this.formatName = formatName;
    this.supportedExtensions = extensions;
  }

  canHandle(extension: string): boolean {
    return this.supportedExtensions.includes(extension.toLowerCase());
  }

  async import(fileContent: FileContentInfo): Promise<KdbxGroup> {
    const group = new KdbxGroup();
    group.name = this.formatName;
    return group;
  }
}

/**
 * 模拟导出处理器
 */
class MockExportHandler implements IExportHandler {
  readonly supportedExtensions: string[];
  readonly formatName: string;
  readonly formatId: string;
  readonly defaultFileName: string;

  constructor(formatId: string, formatName: string, extensions: string[], defaultFileName: string) {
    this.formatId = formatId;
    this.formatName = formatName;
    this.supportedExtensions = extensions;
    this.defaultFileName = defaultFileName;
  }

  canHandle(formatId: string): boolean {
    return this.formatId === formatId;
  }

  async export(database: Kdbx): Promise<ArrayBuffer> {
    return new ArrayBuffer(0);
  }
}

export default function FormatHandlerRegistryTest() {
  describe('FormatHandlerRegistry', () => {
    describe('getInstance', () => {
      it('shouldReturnSingletonInstance', 0, () => {
        const instance1 = FormatHandlerRegistry.getInstance();
        const instance2 = FormatHandlerRegistry.getInstance();
        expect(instance1 === instance2).assertTrue();
      });

      it('shouldAlwaysReturnSameInstance', 0, () => {
        const instance1 = FormatHandlerRegistry.getInstance();
        const instance2 = FormatHandlerRegistry.getInstance();
        const instance3 = FormatHandlerRegistry.getInstance();
        expect(instance1 === instance2).assertTrue();
        expect(instance2 === instance3).assertTrue();
      });
    });

    describe('registerImportHandler', () => {
      it('shouldRegisterHandlerByExtension', 0, () => {
        const registry = FormatHandlerRegistry.getInstance();
        const handler = new MockImportHandler('CSV_TEST', 'CSV', ['.csv_test']);
        registry.registerImportHandler(handler);

        const retrieved = registry.getImportHandler('.csv_test');
        expect(retrieved).not().assertNull();
        expect(retrieved?.formatId).assertEqual('CSV_TEST');
      });

      it('shouldRegisterHandlerByFormatId', 0, () => {
        const registry = FormatHandlerRegistry.getInstance();
        const handler = new MockImportHandler('XML_TEST', 'XML', ['.xml_test']);
        registry.registerImportHandler(handler);

        const retrieved = registry.getImportHandler('XML_TEST');
        expect(retrieved).not().assertNull();
        expect(retrieved?.formatId).assertEqual('XML_TEST');
      });

      it('shouldRegisterMultipleExtensionsForOneHandler', 0, () => {
        const registry = FormatHandlerRegistry.getInstance();
        const handler = new MockImportHandler('JSON_TEST', 'JSON', ['.json_test', '.jsonl_test']);
        registry.registerImportHandler(handler);

        expect(registry.getImportHandler('.json_test')?.formatId).assertEqual('JSON_TEST');
        expect(registry.getImportHandler('.jsonl_test')?.formatId).assertEqual('JSON_TEST');
        expect(registry.getImportHandler('JSON_TEST')?.formatId).assertEqual('JSON_TEST');
      });

      it('shouldHandleCaseInsensitiveExtensionLookup', 0, () => {
        const registry = FormatHandlerRegistry.getInstance();
        const handler = new MockImportHandler('CSV_TEST2', 'CSV', ['.csv_test2']);
        registry.registerImportHandler(handler);

        expect(registry.getImportHandler('.CSV_TEST2')?.formatId).assertEqual('CSV_TEST2');
        expect(registry.getImportHandler('.Csv_test2')?.formatId).assertEqual('CSV_TEST2');
      });
    });

    describe('registerExportHandler', () => {
      it('shouldRegisterHandlerByExtension', 0, () => {
        const registry = FormatHandlerRegistry.getInstance();
        const handler = new MockExportHandler('KDBX_TEST', 'KDBX', ['.kdbx_test'], 'export.kdbx_test');
        registry.registerExportHandler(handler);

        const retrieved = registry.getExportHandler('.kdbx_test');
        expect(retrieved).not().assertNull();
        expect(retrieved?.formatId).assertEqual('KDBX_TEST');
      });

      it('shouldRegisterHandlerByFormatId', 0, () => {
        const registry = FormatHandlerRegistry.getInstance();
        const handler = new MockExportHandler('XML_TEST2', 'XML', ['.xml_test2'], 'export.xml_test2');
        registry.registerExportHandler(handler);

        const retrieved = registry.getExportHandler('XML_TEST2');
        expect(retrieved).not().assertNull();
        expect(retrieved?.formatId).assertEqual('XML_TEST2');
      });
    });

    describe('getImportHandler', () => {
      it('shouldReturnUndefinedForUnregisteredFormat', 0, () => {
        const registry = FormatHandlerRegistry.getInstance();
        const retrieved = registry.getImportHandler('.unknown_format');
        expect(retrieved).assertUndefined();
      });
    });

    describe('getExportHandler', () => {
      it('shouldReturnUndefinedForUnregisteredFormat', 0, () => {
        const registry = FormatHandlerRegistry.getInstance();
        const retrieved = registry.getExportHandler('UNKNOWN_FORMAT');
        expect(retrieved).assertUndefined();
      });
    });

    describe('getSupportedImportFormats', () => {
      it('shouldReturnAllRegisteredFormatsWithoutDuplicates', 0, () => {
        const registry = FormatHandlerRegistry.getInstance();
        const formats = registry.getSupportedImportFormats();
        expect(formats.length).assertLarger(0);
      });
    });

    describe('getSupportedExportFormats', () => {
      it('shouldReturnAllRegisteredFormatsWithoutDuplicates', 0, () => {
        const registry = FormatHandlerRegistry.getInstance();
        const formats = registry.getSupportedExportFormats();
        expect(formats.length).assertLarger(0);
      });
    });
  });
}
