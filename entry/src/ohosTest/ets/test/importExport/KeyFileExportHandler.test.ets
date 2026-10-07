import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { KeyFileExportHandler } from '../../../../main/ets/services/importExport/handlers/export/KeyFileExportHandler';
import { ExportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { Kdbx, KdbxCredentials } from 'kdbxweb';

/**
 * KeyFileExportHandler 单元测试
 * 测试目标：
 * 1. canHandle 仅匹配 KEY_FILE 格式 ID
 * 2. 格式元信息（扩展名 .key/.keyx、默认文件名、formatId/formatName）
 * 3. export 生成合法 KeePass XML 密钥文件（含 <?xml / <KeyFile> / <Meta> / <Version> / <Key> / <Data>）
 * 4. 多次 export 生成不同随机内容
 * 5. 生成的密钥文件可作为 KdbxCredentials 密钥实际加解锁数据库（端到端可用性）
 */
export default function KeyFileExportHandlerTest() {
  describe('KeyFileExportHandler', () => {
    let handler: KeyFileExportHandler = new KeyFileExportHandler();

    beforeEach(() => {
      handler = new KeyFileExportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptKeyFileFormatId', 0, () => {
        expect(handler.canHandle('KEY_FILE')).assertTrue();
      });

      it('shouldRejectOtherFormatIds', 0, () => {
        expect(handler.canHandle('CSV')).assertFalse();
        expect(handler.canHandle('XML')).assertFalse();
        expect(handler.canHandle('KDBX')).assertFalse();
        expect(handler.canHandle('BITWARDEN_JSON')).assertFalse();
      });

      it('shouldRejectCaseVariants', 0, () => {
        expect(handler.canHandle('key_file')).assertFalse();
        expect(handler.canHandle('Key_File')).assertFalse();
        expect(handler.canHandle('KEYFILE')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldExposeCorrectFormatMetadata', 0, () => {
        expect(handler.formatId).assertEqual('KEY_FILE');
        expect(handler.formatName).assertEqual('Key File');
        expect(handler.defaultFileName).assertEqual('keyfile.key');
        expect(handler.supportedExtensions.length).assertEqual(2);
        expect(handler.supportedExtensions.includes('.key')).assertTrue();
        expect(handler.supportedExtensions.includes('.keyx')).assertTrue();
      });
    });

    describe('exportFormat', () => {
      it('shouldReturnNonEmptyArrayBuffer', 0, async () => {
        const db = await TestUtils.createTestDatabase('KeyFile Db');
        FileService.resetDbFileParam(db, Date.now());

        const result = await handler.export(db);

        expect(result instanceof ArrayBuffer).assertTrue();
        expect(result.byteLength).assertLarger(0);
      });

      it('shouldProduceKeePassXmlKeyFile', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());

        const result = await handler.export(db);
        const content = TestUtils.decodeBuffer(result);

        expect(content.startsWith('<?xml')).assertTrue();
        expect(content).assertContain('<KeyFile>');
        expect(content).assertContain('<Meta>');
        expect(content).assertContain('<Version>');
        expect(content).assertContain('<Key>');
        expect(content).assertContain('<Data>');
        expect(content).assertContain('</KeyFile>');
      });

      it('shouldProduceVersion1KeyFile', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());

        const result = await handler.export(db);
        const content = TestUtils.decodeBuffer(result);

        // createRandomKeyFile 默认 version=1 → <Version>1.00</Version>
        expect(content).assertContain('<Version>1.00</Version>');
      });

      it('shouldGenerateDifferentContentEachCall', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());

        const result1 = await handler.export(db);
        const result2 = await handler.export(db);
        const content1 = TestUtils.decodeBuffer(result1);
        const content2 = TestUtils.decodeBuffer(result2);

        expect(content1 !== content2).assertTrue();
        // 但两者都是合法的密钥文件结构
        expect(content1).assertContain('<KeyFile>');
        expect(content2).assertContain('<KeyFile>');
      });

      it('shouldNotDependOnDatabaseContent', 0, async () => {
        // export 应忽略数据库内容，仅生成随机密钥文件
        const emptyDb = await TestUtils.createTestDatabase('Empty');
        FileService.resetDbFileParam(emptyDb, Date.now());
        const dbWithEntries = await TestUtils.createTestDatabase('WithEntries');
        FileService.resetDbFileParam(dbWithEntries, Date.now());
        const rootGroup = dbWithEntries.getDefaultGroup();
        TestUtils.createTestEntry(dbWithEntries, rootGroup, 'Entry', 'u', 'p');

        const fromEmpty = await handler.export(emptyDb);
        const fromFull = await handler.export(dbWithEntries);

        expect(fromEmpty.byteLength).assertEqual(fromFull.byteLength);
      });
    });

    describe('exportedKeyFileUsability', () => {
      it('shouldBeUsableAsKdbxCredentialsKeyFile', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());

        const keyFileBuffer = await handler.export(db);

        // 用导出的密钥文件构造凭证
        const cred = new KdbxCredentials(null, keyFileBuffer);
        await cred.ready;

        // 用该凭证创建并保存数据库
        const protectedDb = await Kdbx.create(cred, 'Protected By Key File');
        const rootGroup = protectedDb.getDefaultGroup();
        TestUtils.createTestEntry(protectedDb, rootGroup, 'Secret', 'su', 'sp');

        const savedBytes = await protectedDb.save();

        // 用同一密钥文件重新加载
        const reloaded = await Kdbx.load(savedBytes, cred);
        expect(reloaded).not().assertNull();
        expect(reloaded.getDefaultGroup().entries.length).assertEqual(1);
        expect(reloaded.getDefaultGroup().entries[0].fields.get('Title')).assertEqual('Secret');
      });

      it('shouldFailToUnlockWithDifferentKeyFile', 0, async () => {
        const db = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(db, Date.now());

        const keyFileBuffer = await handler.export(db);
        const cred = new KdbxCredentials(null, keyFileBuffer);
        await cred.ready;

        const protectedDb = await Kdbx.create(cred, 'Protected');
        const savedBytes = await protectedDb.save();

        // 用另一个新生成的密钥文件尝试解锁 → 应失败
        const otherKeyFile = await handler.export(db);
        const wrongCred = new KdbxCredentials(null, otherKeyFile);
        await wrongCred.ready;

        try {
          await Kdbx.load(savedBytes, wrongCred);
          expect().assertFail();
        } catch (err) {
          // 解锁失败（错误密钥）→ 预期抛错
          expect(err).not().assertNull();
        }
      });
    });
  });
}
