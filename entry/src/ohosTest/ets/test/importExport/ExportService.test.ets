import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ExportService } from '../../../../main/ets/services/importExport/service/ExportService';
import { FormatHandlerRegistry } from '../../../../main/ets/services/importExport/FormatHandlerRegistry';
import { CsvExportHandler } from '../../../../main/ets/services/importExport/handlers/export/CsvExportHandler';
import { XmlExportHandler } from '../../../../main/ets/services/importExport/handlers/export/XmlExportHandler';
import { KdbxExportHandler } from '../../../../main/ets/services/importExport/handlers/export/KdbxExportHandler';
import { KeyFileExportHandler } from '../../../../main/ets/services/importExport/handlers/export/KeyFileExportHandler';
import { ExportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { StorageType } from '../../../../main/ets/storage';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { CommonUtils, ResourceManager, DateUtils } from '../../../../main/ets/common/utils';
import { Kdbx, KdbxCredentials } from 'kdbxweb';

/**
 * ExportService 单元测试
 * 测试目标：
 * 1. getExportFileName 全分支：有/无处理器、扩展名替换/保留、appendDate 开关、空 baseName、默认 .kdbx 兜底
 * 2. export 端到端编排：注册真实处理器 → handler.export 生成内容 → KdbxFileManager 写入本地文件
 *    （CSV / XML / KDBX 三条路径），写后回读校验
 * 3. 错误分支：不支持的格式抛 ExportError(UNSUPPORTED_FORMAT)
 */
export default function ExportServiceTest() {
  describe('ExportService', () => {
    let registry: FormatHandlerRegistry;
    let service: ExportService;
    let testDir: string;
    let appContext: common.Context;

    beforeAll(async () => {
      appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      ResourceManager.getInstance().init(appContext as common.UIAbilityContext);

      testDir = appContext.filesDir + '/export-service-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }

      registry = FormatHandlerRegistry.getInstance();
      registry.registerExportHandler(new CsvExportHandler());
      registry.registerExportHandler(new XmlExportHandler());
      registry.registerExportHandler(new KdbxExportHandler());
      registry.registerExportHandler(new KeyFileExportHandler());
      service = new ExportService(registry);
    });

    afterEach(() => {
      FileService.init();
    });

    afterAll(() => {
      FileService.init();
    });

    describe('getExportFileName', () => {
      it('shouldAppendCsvExtensionAndDate', 0, () => {
        const now = DateUtils.getCurrentDate();
        const name = service.getExportFileName('CSV', 'mydb');
        expect(name).assertEqual(`mydb_${now}.csv`);
      });

      it('shouldKeepExistingCsvExtension', 0, () => {
        const now = DateUtils.getCurrentDate();
        const name = service.getExportFileName('CSV', 'mydb.csv');
        expect(name).assertEqual(`mydb_${now}.csv`);
      });

      it('shouldReplaceWrongExtensionWithCsv', 0, () => {
        const now = DateUtils.getCurrentDate();
        const name = service.getExportFileName('CSV', 'mydb.txt');
        expect(name).assertEqual(`mydb_${now}.csv`);
      });

      it('shouldNotAppendDateWhenAppendDateFalse', 0, () => {
        const name = service.getExportFileName('CSV', 'mydb', false);
        expect(name).assertEqual('mydb.csv');
      });

      it('shouldKeepExistingExtensionWhenAppendDateFalse', 0, () => {
        const name = service.getExportFileName('CSV', 'mydb.csv', false);
        expect(name).assertEqual('mydb.csv');
      });

      it('shouldReplaceMultiDotBaseNameExtension', 0, () => {
        const name = service.getExportFileName('CSV', 'archive.tar', false);
        expect(name).assertEqual('archive.csv');
      });

      it('shouldFallbackToKdbxForUnknownFormat', 0, () => {
        const now = DateUtils.getCurrentDate();
        const name = service.getExportFileName('UNKNOWN_FORMAT', 'mydb');
        expect(name).assertEqual(`mydb_${now}.kdbx`);
      });

      it('shouldKeepKdbxExtensionForUnknownFormat', 0, () => {
        const now = DateUtils.getCurrentDate();
        const name = service.getExportFileName('UNKNOWN_FORMAT', 'mydb.kdbx');
        expect(name).assertEqual(`mydb_${now}.kdbx`);
      });

      it('shouldFallbackToKdbxWithoutDateWhenAppendDateFalse', 0, () => {
        const name = service.getExportFileName('UNKNOWN_FORMAT', 'mydb', false);
        expect(name).assertEqual('mydb.kdbx');
      });

      it('shouldUseCurrentDateWhenBaseNameEmpty', 0, () => {
        const now = DateUtils.getCurrentDate();
        const name = service.getExportFileName('CSV', '');
        // baseName 为空 → fileName=nowTime → 追加 .csv → 再追加日期
        expect(name).assertEqual(`${now}_${now}.csv`);
      });

      it('shouldHandleKeyFileFormat', 0, () => {
        const now = DateUtils.getCurrentDate();
        const name = service.getExportFileName('KEY_FILE', 'mykey');
        // KeyFileExportHandler.supportedExtensions[0] = '.key'
        expect(name).assertEqual(`mykey_${now}.key`);
      });
    });

    describe('exportCsvOrchestration', () => {
      it('shouldExportCsvToLocalStorageFile', 0, async () => {
        const db = await TestUtils.createTestDatabase('Export Csv');
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Csv Entry', 'cu', 'cp');

        const filePath = testDir + '/export.csv';
        await service.export(db, 'CSV', filePath, StorageType.LOCAL);

        // 回读校验
        const content = await readTextFile(filePath);
        expect(content).assertContain('Title');
        expect(content).assertContain('Csv Entry');
        expect(content).assertContain('cu');
      });
    });

    describe('exportXmlOrchestration', () => {
      it('shouldExportXmlToLocalStorageFile', 0, async () => {
        const db = await TestUtils.createTestDatabase('Export Xml');
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Xml Entry', 'xu');

        const filePath = testDir + '/export.xml';
        await service.export(db, 'XML', filePath, StorageType.LOCAL);

        const content = await readTextFile(filePath);
        expect(content).assertContain('<?xml');
        expect(content).assertContain('Xml Entry');
      });
    });

    describe('exportKdbxOrchestration', () => {
      it('shouldExportKdbxToLocalStorageFile', 0, async () => {
        const db = await TestUtils.createTestDatabase('Export Kdbx');
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Kdbx Entry', 'ku', 'kp');

        const filePath = testDir + '/export.kdbx';
        await service.export(db, 'KDBX', filePath, StorageType.LOCAL);

        const bytes = await readBytesFile(filePath);
        expect(bytes.byteLength).assertLarger(0);
        const view = new Uint8Array(bytes);
        expect(view[0]).assertEqual(0x03);
        expect(view[1]).assertEqual(0xd9);
      });

      it('shouldProduceReloadableKdbxFile', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Reload Me', 'ru', 'rp');

        const filePath = testDir + '/reload.kdbx';
        await service.export(db, 'KDBX', filePath, StorageType.LOCAL);

        const bytes = await readBytesFile(filePath);
        const cred = new KdbxCredentials(null);
        const reloaded = await Kdbx.load(bytes, cred);
        expect(reloaded.getDefaultGroup().entries.length).assertEqual(1);
        expect(reloaded.getDefaultGroup().entries[0].fields.get('Title')).assertEqual('Reload Me');
      });
    });

    describe('exportErrorHandling', () => {
      it('shouldThrowExportErrorForUnsupportedFormat', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());

        try {
          await service.export(db, 'NO_SUCH_FORMAT', testDir + '/bad.unknown', StorageType.LOCAL);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          expect(error instanceof ExportError).assertTrue();
          if (error instanceof ExportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.UNSUPPORTED_FORMAT);
          }
        }
      });
    });
  });
}

async function readTextFile(path: string): Promise<string> {
  const file = await fs.open(path, fs.OpenMode.READ_ONLY);
  try {
    const stat = await fs.stat(file.fd);
    const buf = new ArrayBuffer(stat.size);
    await fs.read(file.fd, buf);
    return TestUtils.decodeBuffer(buf);
  } finally {
    await fs.close(file.fd);
  }
}

async function readBytesFile(path: string): Promise<ArrayBuffer> {
  const file = await fs.open(path, fs.OpenMode.READ_ONLY);
  try {
    const stat = await fs.stat(file.fd);
    const buf = new ArrayBuffer(stat.size);
    await fs.read(file.fd, buf);
    return buf;
  } finally {
    await fs.close(file.fd);
  }
}
