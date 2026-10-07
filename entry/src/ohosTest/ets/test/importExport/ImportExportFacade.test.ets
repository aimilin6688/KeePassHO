import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ImportExportFacade } from '../../../../main/ets/services/importExport/ImportExportFacade';
import { FormatHandlerRegistry } from '../../../../main/ets/services/importExport/FormatHandlerRegistry';
import { CsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/CsvImportHandler';
import { XmlImportHandler } from '../../../../main/ets/services/importExport/handlers/import/XmlImportHandler';
import { CsvExportHandler } from '../../../../main/ets/services/importExport/handlers/export/CsvExportHandler';
import { XmlExportHandler } from '../../../../main/ets/services/importExport/handlers/export/XmlExportHandler';
import { KdbxExportHandler } from '../../../../main/ets/services/importExport/handlers/export/KdbxExportHandler';
import { KeyFileExportHandler } from '../../../../main/ets/services/importExport/handlers/export/KeyFileExportHandler';
import { ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { LocationInfo, LocationMode } from '../../../../main/ets/services/beans/LocationParam';
import { StorageType, StorageConfig } from '../../../../main/ets/storage';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { CommonUtils, ResourceManager, DateUtils } from '../../../../main/ets/common/utils';

/**
 * ImportExportFacade 单元测试
 * 测试目标：
 * 1. 公共 API：getSupportedImportFormats / getSupportedExportFormats / getExportFileName
 * 2. exportCurrentDatabase 端到端（真实 LOCAL 存储）+ 失败分支（不支持的格式 / 无数据库）
 * 3. importToCurrentDatabase 失败分支（不支持的格式 → handleError ImportError 分支）
 */
export default function ImportExportFacadeTest() {
  describe('ImportExportFacade', () => {
    let facade: ImportExportFacade;
    let testDir: string;
    let appContext: common.Context;

    beforeAll(() => {
      appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      ResourceManager.getInstance().init(appContext as common.UIAbilityContext);

      testDir = appContext.filesDir + '/facade-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }

      const registry = FormatHandlerRegistry.getInstance();
      registry.registerImportHandler(new CsvImportHandler());
      registry.registerImportHandler(new XmlImportHandler());
      registry.registerExportHandler(new CsvExportHandler());
      registry.registerExportHandler(new XmlExportHandler());
      registry.registerExportHandler(new KdbxExportHandler());
      registry.registerExportHandler(new KeyFileExportHandler());

      facade = new ImportExportFacade();
    });

    afterEach(() => {
      FileService.init();
    });

    afterAll(() => {
      FileService.init();
    });

    describe('getSupportedImportFormats', () => {
      it('shouldReturnNonEmptyList', 0, () => {
        const formats = facade.getSupportedImportFormats();
        expect(formats.length).assertLarger(0);
      });

      it('shouldIncludeCsvAndXmlFormats', 0, () => {
        const formats = facade.getSupportedImportFormats();
        const ids: string[] = [];
        for (const f of formats) {
          ids.push(f.formatId);
        }
        expect(ids.includes('CSV')).assertTrue();
        expect(ids.includes('XML')).assertTrue();
      });
    });

    describe('getSupportedExportFormats', () => {
      it('shouldReturnNonEmptyList', 0, () => {
        const formats = facade.getSupportedExportFormats();
        expect(formats.length).assertLarger(0);
      });

      it('shouldIncludeAllRegisteredExportFormats', 0, () => {
        const formats = facade.getSupportedExportFormats();
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

    describe('getExportFileName', () => {
      it('shouldDelegateToExportService', 0, () => {
        const now = DateUtils.getCurrentDate();
        const name = facade.getExportFileName('CSV', 'mydb');
        expect(name).assertEqual(`mydb_${now}.csv`);
      });

      it('shouldHandleXmlFormat', 0, () => {
        const now = DateUtils.getCurrentDate();
        const name = facade.getExportFileName('XML', 'export');
        expect(name).assertEqual(`export_${now}.xml`);
      });
    });

    describe('exportCurrentDatabase', () => {
      it('shouldSucceedAndWriteFileToLocalStorage', 0, async () => {
        const db = await TestUtils.createTestDatabase('Facade Export');
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Facade Entry', 'fu', 'fp');

        const filePath = testDir + '/facade-export.csv';
        const location = buildLocation(filePath, StorageType.LOCAL);

        const result = await facade.exportCurrentDatabase('CSV', location);

        expect(result.isSuccess).assertTrue();
        // 回读校验文件已写入
        const content = await readTextFile(filePath);
        expect(content).assertContain('Facade Entry');
      });

      it('shouldFailWithUnsupportedFormat', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());

        const location = buildLocation(testDir + '/bad.nosuch', StorageType.LOCAL);
        const result = await facade.exportCurrentDatabase('NO_SUCH_FORMAT', location);

        expect(result.isSuccess).assertFalse();
        expect(result.errorCode).assertEqual(ImportExportErrorCode.UNSUPPORTED_FORMAT);
      });

      it('shouldFailWhenNoDatabaseLoaded', 0, async () => {
        FileService.init(); // 清空 dbFileParam → 无数据库
        const location = buildLocation(testDir + '/nodb.csv', StorageType.LOCAL);
        const result = await facade.exportCurrentDatabase('CSV', location);

        expect(result.isSuccess).assertFalse();
        // CsvExportHandler.export(undefined) → TypeError → ExportError(EXPORT_FAILED)
        expect(result.errorCode).assertEqual(ImportExportErrorCode.EXPORT_FAILED);
      });
    });

    describe('importToCurrentDatabase', () => {
      it('shouldFailWithUnsupportedFormat', 0, async () => {
        const location = buildLocation(testDir + '/import.unknownext', StorageType.LOCAL);
        const result = await facade.importToCurrentDatabase(location);

        expect(result.isSuccess).assertFalse();
        expect(result.errorCode).assertEqual(ImportExportErrorCode.UNSUPPORTED_FORMAT);
      });

      it('shouldFailWhenNoDatabaseLoadedAfterSuccessfulImport', 0, async () => {
        // 准备一个合法 CSV 文件 → importService.import 成功
        // 但 FileService 无数据库 → database.getDefaultGroup() 抛错 → handleError 通用 Error 分支
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Src', 'su', 'sp');
        const xmlContent = await db.saveXml(true, true);
        const filePath = testDir + '/import-nodb.xml';
        await writeTextFile(filePath, xmlContent);

        // 清空数据库，使 FileService.getDatabase() 返回 undefined
        FileService.init();

        const location = buildLocation(filePath, StorageType.LOCAL);
        const result = await facade.importToCurrentDatabase(location);

        expect(result.isSuccess).assertFalse();
        // 通用 Error → PARSE_ERROR
        expect(result.errorCode).assertEqual(ImportExportErrorCode.PARSE_ERROR);
      });
    });
  });
}

function buildLocation(filePath: string, storageType: StorageType): LocationInfo {
  const config: StorageConfig = {};
  const location: LocationInfo = {
    mode: LocationMode.SAVE,
    filePath: filePath,
    fileName: 'test',
    fileSuffix: [],
    storageType: storageType,
    storageConfig: config
  };
  return location;
}

async function writeTextFile(path: string, content: string): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    await fs.write(file.fd, content);
  } finally {
    await fs.close(file.fd);
  }
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
