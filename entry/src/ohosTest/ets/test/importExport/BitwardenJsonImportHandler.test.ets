import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { BitwardenJsonImportHandler } from '../../../../main/ets/services/importExport/handlers/import/BitwardenJsonImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { Kdbx } from 'kdbxweb';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * Bitwarden JSON 导入完整功能测试
 * 测试目标：
 * 1. 能够正确解析 Bitwarden 未加密 JSON 导出文件
 * 2. 支持所有 Bitwarden 条目类型（Login、Card、Identity、Secure Note）
 * 3. 正确处理文件夹结构
 * 4. 正确处理自定义字段
 */
export default function BitwardenJsonImportHandlerTest() {
  describe('BitwardenJsonImportHandler', () => {
    let handler: BitwardenJsonImportHandler = new BitwardenJsonImportHandler();

    beforeEach(() => {
      handler = new BitwardenJsonImportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptJsonExtension', 0, () => {
        expect(handler.canHandle('.json')).assertTrue();
      });

      it('shouldBeCaseInsensitive', 0, () => {
        expect(handler.canHandle('.JSON')).assertTrue();
        expect(handler.canHandle('.Json')).assertTrue();
      });

      it('shouldRejectNonJsonExtensions', 0, () => {
        expect(handler.canHandle('.csv')).assertFalse();
        expect(handler.canHandle('.xml')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('BITWARDEN_JSON');
        expect(handler.formatName).assertEqual('Bitwarden JSON');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.json');
      });
    });

    describe('importLoginItems', () => {
      it('shouldImportBasicLoginItem', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":1,"name":"Test Login","login":{"username":"user@example.com","password":"secret123"}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        expect(result).not().assertNull();
        expect(result.entries.length).assertEqual(1);

        const entry = result.entries[0];
        expect(entry.fields.get('Title')).assertEqual('Test Login');
        expect(entry.fields.get('UserName')).assertEqual('user@example.com');
      });

      it('shouldImportLoginWithURL', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":1,"name":"Website","login":{"username":"user","password":"pass","uris":[{"uri":"https://example.com"}]}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('URL')).assertEqual('https://example.com');
      });

      it('shouldImportLoginWithMultipleURLs', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":1,"name":"Multi URL","login":{"username":"user","password":"pass","uris":[{"uri":"https://example.com"},{"uri":"https://backup.com"}]}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        const url = result.entries[0].fields.get('URL');
        expect(url).assertContain('https://example.com');
        expect(url).assertContain('https://backup.com');
      });

      it('shouldImportLoginWithTOTP', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":1,"name":"TOTP Login","login":{"username":"user","password":"pass","totp":"otpauth://totp/issuer?secret=ABCDEF"}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(KdbxUtils.getFieldValueString(result.entries[0].fields, 'TOTP')).assertEqual('otpauth://totp/issuer?secret=ABCDEF');
      });
    });

    describe('importCardItems', () => {
      it('shouldImportCardItem', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":3,"name":"My Card","card":{"cardholderName":"John Doe","brand":"Visa","number":"4111111111111111","expMonth":"12","expYear":"2025","code":"123"}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];

        expect(entry.fields.get('Title')).assertEqual('[Card] My Card');
        expect(entry.fields.get('Cardholder Name')).assertEqual('John Doe');
        expect(entry.fields.get('Brand')).assertEqual('Visa');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Number')).assertEqual('4111111111111111');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'CVV')).assertEqual('123');
      });
    });

    describe('importIdentityItems', () => {
      it('shouldImportIdentityItem', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":4,"name":"My Identity","identity":{"firstName":"John","lastName":"Doe","email":"john@example.com","phone":"+1234567890"}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];

        expect(entry.fields.get('Title')).assertEqual('[Identity] My Identity');
        expect(entry.fields.get('Full Name')).assertEqual('John Doe');
        expect(entry.fields.get('Email')).assertEqual('john@example.com');
        expect(entry.fields.get('Phone')).assertEqual('+1234567890');
      });
    });

    describe('importSecureNoteItems', () => {
      it('shouldImportSecureNoteItem', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":2,"name":"Secure Note","notes":"This is a secure note"}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Title')).assertEqual('Secure Note');
        expect(result.entries[0].fields.get('Notes')).assertEqual('This is a secure note');
      });
    });

    describe('importFolderHandling', () => {
      it('shouldCreateGroupsFromFolders', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"folders":[{"id":"f1","name":"Personal"},{"id":"f2","name":"Work"}],"items":[{"id":"1","type":1,"name":"Personal Entry","folderId":"f1","login":{"username":"user1"}},{"id":"2","type":1,"name":"Work Entry","folderId":"f2","login":{"username":"user2"}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        expect(result.groups.length).assertEqual(2);

        const groupNames: string[] = [];
        for (const g of result.groups) {
          if (g.name !== undefined) {
            groupNames.push(g.name);
          }
        }
        expect(groupNames.includes('Personal')).assertTrue();
        expect(groupNames.includes('Work')).assertTrue();
      });

      it('shouldPlaceEntriesInCorrectFolders', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"folders":[{"id":"f1","name":"Personal"}],"items":[{"id":"1","type":1,"name":"Entry in Folder","folderId":"f1","login":{"username":"user"}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        // 找到 Personal 分组
        let personalGroup = result.groups[0];
        for (const g of result.groups) {
          if (g.name === 'Personal') {
            personalGroup = g;
            break;
          }
        }
        expect(personalGroup.entries.length).assertEqual(1);
        expect(personalGroup.entries[0].fields.get('Title')).assertEqual('Entry in Folder');
      });

      it('shouldHandleEntriesWithoutFolder', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":1,"name":"No Folder Entry","login":{"username":"user"}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        // 没有文件夹的条目应该在根分组
        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Title')).assertEqual('No Folder Entry');
      });
    });

    describe('importCustomFields', () => {
      it('shouldImportCustomFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":1,"name":"Entry with Fields","login":{"username":"user"},"fields":[{"name":"API Key","value":"abc123","type":0},{"name":"Secret","value":"hidden","type":1}]}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(1);
        const entry = result.entries[0];

        expect(entry.fields.get('API Key')).assertEqual('abc123');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Secret')).assertEqual('hidden');
      });
    });

    describe('importErrorHandling', () => {
      it('shouldThrowUnsupportedFormatForEncrypted', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":true,"items":[]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.UNSUPPORTED_FORMAT);
          }
        }
      });

      it('shouldThrowFileEmptyForEmptyItems', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.FILE_EMPTY);
          }
        }
      });

      it('shouldThrowInvalidJsonForInvalidJSON', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('not valid json', 'test.json');

        try {
          await handler.import(fileContent);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.INVALID_JSON_FORMAT);
          }
        }
      });
    });

    describe('importNotesHandling', () => {
      it('shouldImportNotesField', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":1,"name":"Entry with Notes","notes":"Important notes here","login":{"username":"user"}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        expect(result.entries[0].fields.get('Notes')).assertEqual('Important notes here');
      });
    });

    describe('importFavoriteMarking', () => {
      it('shouldMarkFavoriteItems', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"items":[{"id":"1","type":1,"name":"Favorite Entry","favorite":true,"login":{"username":"user"}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'test.json');

        const result = await handler.import(fileContent);

        expect(result.entries[0].fields.get('Favorite')).assertEqual('true');
      });
    });

    describe('importCompleteScenario', () => {
      it('shouldImportCompleteBitwardenExport', 0, async () => {
        const testDb = await TestUtils.createTestDatabase();
        FileService.resetDbFileParam(testDb, Date.now());

        // 模拟一个完整的 Bitwarden 导出（使用字符串避免 ArkTS 对象字面量限制）
        const jsonContent = '{"encrypted":false,"folders":[{"id":"f1","name":"Work"},{"id":"f2","name":"Personal"}],"items":[{"id":"1","type":1,"name":"Work Login","folderId":"f1","favorite":true,"notes":"Work account","login":{"username":"work@example.com","password":"workpass","uris":[{"uri":"https://work.example.com"}],"totp":"otpauth://totp/work?secret=WORKKEY"},"fields":[{"name":"Department","value":"IT","type":0}]},{"id":"2","type":1,"name":"Personal Login","folderId":"f2","login":{"username":"personal@example.com","password":"personalpass"}},{"id":"3","type":2,"name":"Secure Note","notes":"This is confidential"}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'bitwarden.json');

        const result = await handler.import(fileContent);

        // 验证总体结构
        expect(result.name).assertEqual('Bitwarden Import');
        expect(result.groups.length).assertEqual(2);

        // 验证分组中的条目
        let totalEntries = result.entries.length;
        for (const g of result.groups) {
          totalEntries += g.entries.length;
        }
        expect(totalEntries).assertEqual(3);

        // 验证 Work 分组的条目
        let workGroup = result.groups[0];
        for (const g of result.groups) {
          if (g.name === 'Work') {
            workGroup = g;
            break;
          }
        }
        expect(workGroup.entries.length).assertEqual(1);

        const workEntry = workGroup.entries[0];
        expect(workEntry.fields.get('Title')).assertEqual('Work Login');
        expect(workEntry.fields.get('UserName')).assertEqual('work@example.com');
        expect(workEntry.fields.get('URL')).assertEqual('https://work.example.com');
        expect(KdbxUtils.getFieldValueString(workEntry.fields, 'TOTP')).assertEqual('otpauth://totp/work?secret=WORKKEY');
        expect(workEntry.fields.get('Department')).assertEqual('IT');
        expect(workEntry.fields.get('Favorite')).assertEqual('true');
      });
    });
  });
}
