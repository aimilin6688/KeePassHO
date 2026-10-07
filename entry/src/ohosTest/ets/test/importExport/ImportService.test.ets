import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ImportService } from '../../../../main/ets/services/importExport/service/ImportService';
import { FormatHandlerRegistry } from '../../../../main/ets/services/importExport/FormatHandlerRegistry';
import { CsvImportHandler } from '../../../../main/ets/services/importExport/handlers/import/CsvImportHandler';
import { XmlImportHandler } from '../../../../main/ets/services/importExport/handlers/import/XmlImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { StorageType } from '../../../../main/ets/storage';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { CommonUtils, ResourceManager } from '../../../../main/ets/common/utils';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * ImportService 单元测试
 * 测试目标：
 * 1. getExtension 扩展名解析（含大小写、多级点、无扩展名、路径）
 * 2. import 端到端编排：注册真实处理器 → 经 KdbxFileManager 读取本地文件 → 处理器解析
 *    （CSV / XML 两条路径）
 * 3. 错误分支：不支持的格式抛 UNSUPPORTED_FORMAT；文件不存在抛错
 */
export default function ImportServiceTest() {
  describe('ImportService', () => {
    let registry: FormatHandlerRegistry;
    let service: ImportService;
    let testDir: string;
    let appContext: common.Context;

    beforeAll(async () => {
      appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      ResourceManager.getInstance().init(appContext as common.UIAbilityContext);

      testDir = appContext.filesDir + '/import-service-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }

      registry = FormatHandlerRegistry.getInstance();
      registry.registerImportHandler(new CsvImportHandler());
      registry.registerImportHandler(new XmlImportHandler());
      service = new ImportService(registry);
    });

    beforeEach(async () => {
      // CsvImportHandler 依赖 FileService.getDatabase().meta 构造条目
      const db = await TestUtils.createTestDatabase('ImportService Test');
      FileService.resetDbFileParam(db, Date.now());
    });

    afterEach(() => {
      FileService.init();
    });

    afterAll(() => {
      FileService.init();
    });

    describe('getExtension', () => {
      it('shouldReturnLowercasedExtension', 0, () => {
        expect(service.getExtension('file.csv')).assertEqual('.csv');
      });

      it('shouldLowercaseUppercaseExtension', 0, () => {
        expect(service.getExtension('file.CSV')).assertEqual('.csv');
        expect(service.getExtension('FILE.XML')).assertEqual('.xml');
      });

      it('shouldHandlePathWithDirectories', 0, () => {
        expect(service.getExtension('dir/sub/file.csv')).assertEqual('.csv');
        expect(service.getExtension('/a/b/c/data.xml')).assertEqual('.xml');
      });

      it('shouldReturnLastExtensionForMultipleDots', 0, () => {
        expect(service.getExtension('archive.tar.gz')).assertEqual('.gz');
        expect(service.getExtension('my.file.kdbx')).assertEqual('.kdbx');
      });

      it('shouldReturnEmptyForNoExtension', 0, () => {
        expect(service.getExtension('README')).assertEqual('');
        expect(service.getExtension('path/to/nofile')).assertEqual('');
      });

      it('shouldReturnEmptyForEmptyString', 0, () => {
        expect(service.getExtension('')).assertEqual('');
      });
    });

    describe('importCsvOrchestration', () => {
      it('shouldImportCsvFileViaLocalStorage', 0, async () => {
        const csvContent = 'Title,UserName,Password\n' +
          'Entry1,u1,p1\n' +
          'Entry2,u2,p2';
        const filePath = testDir + '/import.csv';
        await writeTextFile(filePath, csvContent);

        const group = await service.import(filePath, StorageType.LOCAL);

        expect(group).not().assertNull();
        expect(group.entries.length).assertEqual(2);
        expect(group.entries[0].fields.get('Title')).assertEqual('Entry1');
        expect(group.entries[1].fields.get('Title')).assertEqual('Entry2');
      });

      it('shouldPreserveCsvEntryFields', 0, async () => {
        const csvContent = 'Title,UserName,Password,URL,Notes\n' +
          'Full,user@example.com,secret,https://example.com,notes here';
        const filePath = testDir + '/full.csv';
        await writeTextFile(filePath, csvContent);

        const group = await service.import(filePath, StorageType.LOCAL);

        expect(group.entries.length).assertEqual(1);
        const entry = group.entries[0];
        expect(entry.fields.get('Title')).assertEqual('Full');
        expect(entry.fields.get('UserName')).assertEqual('user@example.com');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('secret');
        expect(entry.fields.get('URL')).assertEqual('https://example.com');
        expect(entry.fields.get('Notes')).assertEqual('notes here');
      });

      it('shouldImportCsvWithGroups', 0, async () => {
        const csvContent = 'Group,Title\n' +
          'Work,Work Entry\n' +
          'Personal,Personal Entry';
        const filePath = testDir + '/groups.csv';
        await writeTextFile(filePath, csvContent);

        const group = await service.import(filePath, StorageType.LOCAL);

        expect(group.groups.length).assertEqual(2);
        const names: string[] = [];
        for (const g of group.groups) {
          if (g.name !== undefined) {
            names.push(g.name);
          }
        }
        expect(names.includes('Work')).assertTrue();
        expect(names.includes('Personal')).assertTrue();
      });
    });

    describe('importXmlOrchestration', () => {
      it('shouldImportXmlFileViaLocalStorage', 0, async () => {
        const db = await TestUtils.createTestDatabase('Xml Import Service');
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'Xml Entry', 'xu', 'xp');
        const xmlContent = await db.saveXml(true, true);

        const filePath = testDir + '/import.xml';
        await writeTextFile(filePath, xmlContent);

        const group = await service.import(filePath, StorageType.LOCAL);

        expect(group).not().assertNull();
        expect(group.entries.length).assertEqual(1);
        expect(group.entries[0].fields.get('Title')).assertEqual('Xml Entry');
      });

      it('shouldImportXmlWithMultipleEntries', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());
        const rootGroup = db.getDefaultGroup();
        TestUtils.createTestEntry(db, rootGroup, 'A', 'ua', 'pa');
        TestUtils.createTestEntry(db, rootGroup, 'B', 'ub', 'pb');
        const xmlContent = await db.saveXml(true, true);

        const filePath = testDir + '/multi.xml';
        await writeTextFile(filePath, xmlContent);

        const group = await service.import(filePath, StorageType.LOCAL);

        expect(group.entries.length).assertEqual(2);
      });
    });

    describe('importErrorHandling', () => {
      it('shouldThrowUnsupportedFormatForUnknownExtension', 0, async () => {
        const filePath = testDir + '/file.unknownext';

        try {
          await service.import(filePath, StorageType.LOCAL);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          expect(error instanceof ImportError).assertTrue();
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.UNSUPPORTED_FORMAT);
          }
        }
      });

      it('shouldThrowForNonExistentFile', 0, async () => {
        const filePath = testDir + '/does-not-exist.csv';

        try {
          await service.import(filePath, StorageType.LOCAL);
          expect().assertFail();
        } catch (err) {
          // KdbxFileManager.read 抛出普通 Error（文件不存在）
          expect(err).not().assertNull();
        }
      });
    });
  });
}

async function writeTextFile(path: string, content: string): Promise<void> {
  const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    await fs.write(file.fd, content);
  } finally {
    await fs.close(file.fd);
  }
}
