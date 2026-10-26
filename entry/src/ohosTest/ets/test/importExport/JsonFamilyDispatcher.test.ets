import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { JsonFamilyDispatcherImportHandler } from '../../../../main/ets/services/importExport/handlers/import/JsonFamilyDispatcherImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';

/**
 * JsonFamilyDispatcherImportHandler 单元测试
 * 占据 '.json' 路由键，按顶层键嗅探分发（报告 §4.5）：
 * vaults→Proton Pass JSON；items（folders 可选）→Bitwarden JSON；
 * 未知结构→INVALID_FILE_FORMAT；非法 JSON→INVALID_JSON_FORMAT（无通用回落，JSON 族无法启发式映射）。
 */
export default function JsonFamilyDispatcherTest() {
  describe('JsonFamilyDispatcherImportHandler', () => {
    let dispatcher: JsonFamilyDispatcherImportHandler = new JsonFamilyDispatcherImportHandler();

    beforeEach(() => {
      dispatcher = new JsonFamilyDispatcherImportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptJsonExtension', 0, () => {
        expect(dispatcher.canHandle('.json')).assertTrue();
        expect(dispatcher.canHandle('.JSON')).assertTrue();
      });

      it('shouldRejectNonJsonExtensions', 0, () => {
        expect(dispatcher.canHandle('.csv')).assertFalse();
        expect(dispatcher.canHandle('.xml')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(dispatcher.formatId).assertEqual('JSON');
        expect(dispatcher.formatName).assertEqual('JSON');
        expect(dispatcher.supportedExtensions.length).assertEqual(1);
        expect(dispatcher.supportedExtensions[0]).assertEqual('.json');
      });
    });

    describe('detectFormatId', () => {
      it('shouldDetectBitwardenFormat', 0, () => {
        const content = '{"encrypted":false,"folders":[{"id":"f1","name":"Social"}],"items":[{"id":"1","type":1,"name":"X"}]}';
        expect(dispatcher.detectFormatId(content)).assertEqual('BITWARDEN_JSON');
      });

      it('shouldDetectFolderlessBitwardenFormat', 0, () => {
        // Bitwarden folders 为可选键，无 folders 时仍须识别（保持迁移前行为兼容）
        const content = '{"encrypted":false,"items":[{"id":"1","type":1,"name":"X"}]}';
        expect(dispatcher.detectFormatId(content)).assertEqual('BITWARDEN_JSON');
      });

      it('shouldDetectProtonFormat', 0, () => {
        const content = '{"encrypted":false,"vaults":{"v1":{"name":"Personal","items":[]}}}';
        expect(dispatcher.detectFormatId(content)).assertEqual('PROTONPASS_JSON');
      });

      it('shouldReturnEmptyForUnknownShape', 0, () => {
        expect(dispatcher.detectFormatId('{}')).assertEqual('');
        expect(dispatcher.detectFormatId('{"foo":"bar"}')).assertEqual('');
      });

      it('shouldReturnEmptyForInvalidJson', 0, () => {
        expect(dispatcher.detectFormatId('not valid json')).assertEqual('');
        expect(dispatcher.detectFormatId('')).assertEqual('');
      });
    });

    describe('import', () => {
      it('shouldDispatchBitwardenImport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('JSON Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":1,"name":"Test Login","login":{"username":"user","password":"pass"}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await dispatcher.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Title')).assertEqual('Test Login');
      });

      it('shouldDispatchProtonImport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('JSON Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v1":{"name":"Personal","items":[' +
          '{"uuid":"i","data":{"type":"login","metadata":{"name":"GitHub"},' +
          '"content":{"itemUsername":"u","password":"p"}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await dispatcher.import(fileContent);

        expect(result.groups[0].name).assertEqual('Personal');
        expect(result.groups[0].entries[0].fields.get('Title')).assertEqual('GitHub');
      });

      it('shouldThrowInvalidJsonFormatForInvalidJson', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('JSON Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('not valid json', 'test.json');
        try {
          await dispatcher.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.INVALID_JSON_FORMAT);
          }
        }
      });

      it('shouldThrowInvalidFileFormatForUnknownShape', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('JSON Dispatcher Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('{"foo":"bar"}', 'test.json');
        try {
          await dispatcher.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.INVALID_FILE_FORMAT);
          }
        }
      });
    });
  });
}
