import { afterAll, afterEach, beforeAll, beforeEachIt, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { TestContextHelper } from '../TestContextHelper';
import { ImportExportViewModel } from '../../../../main/ets/services/importExport/ImportExportViewModel';
import { FormatHandlerRegistry } from '../../../../main/ets/services/importExport/FormatHandlerRegistry';
import { CsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/CsvImportHandler';
import { XmlImportHandler } from '../../../../main/ets/services/importExport/handlers/import/XmlImportHandler';
import { CsvExportHandler } from '../../../../main/ets/services/importExport/handlers/export/CsvExportHandler';
import { XmlExportHandler } from '../../../../main/ets/services/importExport/handlers/export/XmlExportHandler';
import { KdbxExportHandler } from '../../../../main/ets/services/importExport/handlers/export/KdbxExportHandler';
import { KeyFileExportHandler } from '../../../../main/ets/services/importExport/handlers/export/KeyFileExportHandler';
import { LocationInfo, LocationMode } from '../../../../main/ets/services/beans/LocationParam';
import { StorageType, StorageConfig } from '../../../../main/ets/storage';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { CommonUtils, ResourceManager, DateUtils } from '../../../../main/ets/common/utils';

/**
 * ImportExportViewModel 单元测试
 * 测试目标：
 * 1. 公共 API：getImportFormatOptions / getExportFormatOptions / getFileExtensions / getExportFileName
 * 2. executeExport 端到端成功（真实 LOCAL 存储）→ returns true，isLoading 复位，errorMessage 清空
 * 3. executeImport / executeExport 失败分支 → returns false，isLoading 复位，errorMessage 写入
 */
export default function ImportExportViewModelTest() {
  describe('ImportExportViewModel', () => {
    let viewModel: ImportExportViewModel;
    let testDir: string;
    let appContext: common.UIAbilityContext;

    beforeAll(async () => {
      appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      ResourceManager.getInstance().init(appContext);

      testDir = appContext.filesDir + '/viewmodel-test';
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
    });

    // beforeEachIt：Hypium 中父级 beforeEach 不会传播到嵌套 describe 的用例，需用 beforeEachIt
    beforeEachIt(() => {
      viewModel = new ImportExportViewModel();
    });

    afterEach(() => {
      FileService.init();
    });

    afterAll(() => {
      FileService.init();
    });

    describe('getImportFormatOptions', () => {
      it('shouldReturnNonEmptyList', 0, () => {
        const options = viewModel.getImportFormatOptions();
        expect(options.length).assertLarger(0);
      });

      it('shouldIncludeCsvAndXml', 0, () => {
        const options = viewModel.getImportFormatOptions();
        const ids: string[] = [];
        for (const o of options) {
          ids.push(o.formatId);
        }
        expect(ids.includes('CSV')).assertTrue();
        expect(ids.includes('XML')).assertTrue();
      });
    });

    describe('getExportFormatOptions', () => {
      it('shouldReturnNonEmptyList', 0, () => {
        const options = viewModel.getExportFormatOptions();
        expect(options.length).assertLarger(0);
      });

      it('shouldIncludeAllRegisteredExportFormats', 0, () => {
        const options = viewModel.getExportFormatOptions();
        const ids: string[] = [];
        for (const o of options) {
          ids.push(o.formatId);
        }
        expect(ids.includes('CSV')).assertTrue();
        expect(ids.includes('XML')).assertTrue();
        expect(ids.includes('KDBX')).assertTrue();
        expect(ids.includes('KEY_FILE')).assertTrue();
      });
    });

    describe('getFileExtensions', () => {
      it('shouldReturnExtensionsForCsv', 0, () => {
        const exts = viewModel.getFileExtensions('CSV');
        expect(exts.length).assertEqual(1);
        expect(exts[0]).assertEqual('.csv');
      });

      it('shouldReturnExtensionsForXml', 0, () => {
        const exts = viewModel.getFileExtensions('XML');
        expect(exts.length).assertEqual(1);
        expect(exts[0]).assertEqual('.xml');
      });

      it('shouldReturnEmptyForUnknownFormat', 0, () => {
        const exts = viewModel.getFileExtensions('UNKNOWN_FORMAT');
        expect(exts.length).assertEqual(0);
      });
    });

    describe('getExportFileName', () => {
      it('shouldUseDbFileParamFileNameAsBase', 0, () => {
        FileService.init();
        FileService.getDbFileParam().fileName = 'mydb';

        const now = DateUtils.getCurrentDate();
        const name = viewModel.getExportFileName('CSV');
        expect(name).assertEqual(`mydb_${now}.csv`);
      });

      it('shouldFallbackToCurrentDateWhenFileNameMissing', 0, () => {
        FileService.init(); // 无 fileName
        const now = DateUtils.getCurrentDate();
        const name = viewModel.getExportFileName('CSV');
        // baseName 为空 → nowTime → 追加 .csv → 再追加日期
        expect(name).assertEqual(`${now}_${now}.csv`);
      });
    });

    describe('executeExport', () => {
      it('shouldReturnTrueOnSuccessAndResetState', 0, async () => {
        const db = await TestUtils.createTestDatabase('Vm Export');
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Vm Entry', 'vu', 'vp');

        const filePath = testDir + '/vm-export.csv';
        const location = buildLocation(filePath, StorageType.LOCAL);

        const ok = await viewModel.executeExport('CSV', location);

        expect(ok).assertTrue();
        expect(viewModel.isLoading).assertFalse();
        expect(viewModel.errorMessage).assertEqual('');
        // 文件已写入
        const content = await readTextFile(filePath);
        expect(content).assertContain('Vm Entry');
      });

      it('shouldReturnFalseOnUnsupportedFormatAndSetError', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());

        const location = buildLocation(testDir + '/vm-bad.nosuch', StorageType.LOCAL);
        const ok = await viewModel.executeExport('NO_SUCH_FORMAT', location);

        expect(ok).assertFalse();
        expect(viewModel.isLoading).assertFalse();
        expect(viewModel.errorMessage.length).assertLarger(0);
      });
    });

    describe('executeImport', () => {
      it('shouldReturnFalseOnUnsupportedFormatAndSetError', 0, async () => {
        const location = buildLocation(testDir + '/vm-import.unknownext', StorageType.LOCAL);
        const ok = await viewModel.executeImport(location);

        expect(ok).assertFalse();
        expect(viewModel.isLoading).assertFalse();
        expect(viewModel.errorMessage.length).assertLarger(0);
        expect(viewModel.lastImportedCount).assertEqual(0);
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
