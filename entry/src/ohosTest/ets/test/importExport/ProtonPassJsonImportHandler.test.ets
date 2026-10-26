import { describe, expect, it, beforeEach } from '@ohos/hypium';
import { ProtonPassJsonImportHandler } from '../../../../main/ets/services/importExport/handlers/import/ProtonPassJsonImportHandler';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';
import { TestUtils } from './TestUtils';
import { FileService } from '../../../../main/ets/services/FileService';
import { KdbxUtils } from '../../../../main/ets/common/utils';

/**
 * ProtonPassJsonImportHandler 单元测试
 * 语义对齐 KeePassXC ProtonPassReader（src/format/ProtonPassReader.cpp）：
 * 顶层 vaults（vaultId→{name,description,items[]}）嵌套条目（KeePassXC 路径），
 * 或顶层 items[] + shareId 解析 vault 分组（报告 §三 形态）；
 * data.type 分派 login/creditCard/wifi/sshKey，custom/note 仅元数据，
 * 未知类型备注前缀 + content_* 自定义字段；
 * extraFields 按 fieldName 入自定义字段（hidden 受保护、totp 读 data.totpUri）；
 * pinned→FAVORITE_TAG；state==2→过期；createTime/modifyTime（秒）→条目 times。
 */
export default function ProtonPassJsonImportHandlerTest() {
  describe('ProtonPassJsonImportHandler', () => {
    let handler: ProtonPassJsonImportHandler = new ProtonPassJsonImportHandler();

    beforeEach(() => {
      handler = new ProtonPassJsonImportHandler();
    });

    describe('canHandle', () => {
      it('shouldAcceptJsonExtension', 0, () => {
        expect(handler.canHandle('.json')).assertTrue();
        expect(handler.canHandle('.JSON')).assertTrue();
      });

      it('shouldRejectNonJsonExtensions', 0, () => {
        expect(handler.canHandle('.csv')).assertFalse();
        expect(handler.canHandle('.xml')).assertFalse();
      });
    });

    describe('properties', () => {
      it('shouldHaveCorrectFormatInfo', 0, () => {
        expect(handler.formatId).assertEqual('PROTONPASS_JSON');
        expect(handler.formatName).assertEqual('Proton Pass JSON');
        expect(handler.supportedExtensions.length).assertEqual(1);
        expect(handler.supportedExtensions[0]).assertEqual('.json');
      });
    });

    describe('import', () => {
      it('shouldImportLoginItemWithAllFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"vault-1":{"name":"Personal","description":"desc","items":[' +
          '{"uuid":"item-1","pinned":false,"state":1,"data":{"type":"login",' +
          '"metadata":{"name":"GitHub","note":"Code hosting"},' +
          '"content":{"itemUsername":"user1","password":"pass1","itemEmail":"me@x.com","totpUri":"JBSWY3DPEHPK3PXP","urls":["https://github.com"]}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        expect(result.entries.length).assertEqual(0);
        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Personal');
        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('GitHub');
        expect(entry.fields.get('Notes')).assertEqual('Code hosting');
        expect(entry.fields.get('UserName')).assertEqual('user1');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('pass1');
        expect(typeof entry.fields.get('Password') !== 'string').assertTrue();
        expect(entry.fields.get('URL')).assertEqual('https://github.com');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'otp')).assertEqual('key=JBSWY3DPEHPK3PXP');
        // email 兜底语义与 Proton Pass CSV 共享：UserName 非空时存自定义字段 Email
        expect(entry.fields.get('Email')).assertEqual('me@x.com');
      });

      it('shouldStoreAdditionalUrlsAsKp2aUrlAttributes', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","data":{"type":"login","metadata":{"name":"Site"},' +
          '"content":{"itemUsername":"u","password":"p","urls":["https://a.com","https://b.com","https://c.com"]}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('URL')).assertEqual('https://a.com');
        expect(entry.fields.get('KP2A_URL_1')).assertEqual('https://b.com');
        expect(entry.fields.get('KP2A_URL_2')).assertEqual('https://c.com');
      });

      it('shouldMarkPinnedItemAsFavorite', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","pinned":true,"data":{"type":"login","metadata":{"name":"Pinned"},' +
          '"content":{"itemUsername":"u","password":"p"}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.tags.includes(KdbxUtils.FAVORITE_TAG)).assertTrue();
      });

      it('shouldImportExtraFields', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","data":{"type":"login","metadata":{"name":"Extra"},' +
          '"content":{"itemUsername":"u","password":"p"},' +
          '"extraFields":[' +
          '{"fieldName":"Recovery Email","type":"text","data":{"content":"recovery@x.com"}},' +
          '{"fieldName":"PIN","type":"hidden","data":{"content":"1234"}},' +
          '{"fieldName":"Backup TOTP","type":"totp","data":{"totpUri":"otpauth://totp/X?secret=ABC"}}]}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Recovery Email')).assertEqual('recovery@x.com');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'PIN')).assertEqual('1234');
        expect(typeof entry.fields.get('PIN') !== 'string').assertTrue();
        expect(entry.fields.get('Backup TOTP')).assertEqual('otpauth://totp/X?secret=ABC');
      });

      it('shouldFallbackEmailToUsernameWhenUsernameEmpty', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","data":{"type":"login","metadata":{"name":"Email Only"},' +
          '"content":{"itemEmail":"only@x.com","password":"p"}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('UserName')).assertEqual('only@x.com');
      });

      it('shouldImportOtpauthUriRaw', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const otpauth = 'otpauth://totp/GitHub?secret=JBSWY3DPEHPK3PXP&issuer=GitHub';
        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","data":{"type":"login","metadata":{"name":"Site"},' +
          '"content":{"itemUsername":"u","password":"p","totpUri":"' + otpauth + '"}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        expect(KdbxUtils.getFieldValueString(result.groups[0].entries[0].fields, 'otp')).assertEqual(otpauth);
      });

      it('shouldImportItemTimes', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","createTime":1730000000,"modifyTime":1730000500,' +
          '"data":{"type":"login","metadata":{"name":"Timed"},' +
          '"content":{"itemUsername":"u","password":"p"}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.times.creationTime?.getTime()).assertEqual(1730000000000);
        expect(entry.times.lastModTime?.getTime()).assertEqual(1730000500000);
        expect(entry.times.lastAccessTime?.getTime()).assertEqual(1730000500000);
      });

      it('shouldImportCreditCardItem', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","data":{"type":"creditCard","metadata":{"name":"My Card"},' +
          '"content":{"number":"4111111111111111","verificationNumber":"123","cardholderName":"John Doe","pin":"9999","expirationDate":"12/28"}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('My Card');
        expect(entry.fields.get('UserName')).assertEqual('4111111111111111');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('123');
        expect(entry.fields.get('cardholderName') === undefined || entry.fields.get('cardholderName') === 'John Doe').assertTrue();
        expect(KdbxUtils.getFieldValueString(entry.fields, 'card_cardholderName')).assertEqual('John Doe');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'card_pin')).assertEqual('9999');
        expect(typeof entry.fields.get('card_pin') !== 'string').assertTrue();
        expect(entry.fields.get('card_expirationDate')).assertEqual('12/28');
      });

      it('shouldImportWifiItem', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","data":{"type":"wifi","metadata":{"name":"Home Wifi"},' +
          '"content":{"ssid":"MyNetwork","password":"wifipass","security":"WPA2"}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('UserName')).assertEqual('MyNetwork');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('wifipass');
        expect(entry.fields.get('wifi_security')).assertEqual('WPA2');
      });

      it('shouldImportSshKeyItem', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","data":{"type":"sshKey","metadata":{"name":"Server Key"},' +
          '"content":{"publicKey":"ssh-rsa AAAA","privateKey":"-----BEGIN-----"}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('ssh_public_key')).assertEqual('ssh-rsa AAAA');
        expect(KdbxUtils.getFieldValueString(entry.fields, 'ssh_private_key')).assertEqual('-----BEGIN-----');
        expect(typeof entry.fields.get('ssh_private_key') !== 'string').assertTrue();
      });

      it('shouldImportUnknownTypeWithContentAttributes', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","data":{"type":"customThing","metadata":{"name":"Weird Item","note":"orig note"},' +
          '"content":{"itemUsername":"custom-user","password":"custom-pass"}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        const entry = result.groups[0].entries[0];
        expect(entry.fields.get('Title')).assertEqual('Weird Item');
        const notes = KdbxUtils.getFieldValueString(entry.fields, 'Notes');
        expect(notes.startsWith("Unknown entry type 'customThing'")).assertTrue();
        expect(notes.includes('orig note')).assertTrue();
        expect(entry.fields.get('content_itemUsername')).assertEqual('custom-user');
        expect(entry.fields.get('content_password')).assertEqual('custom-pass');
      });

      it('shouldMarkStateTwoAsExpired', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v":{"name":"Personal","items":[' +
          '{"uuid":"i","state":2,"data":{"type":"login","metadata":{"name":"Trashed"},' +
          '"content":{"itemUsername":"u","password":"p"}}}]}}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        expect(result.groups[0].entries[0].times.expires).assertTrue();
      });

      it('shouldImportTopLevelItemsWithVaultResolution', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{"v1":{"name":"Work"}},' +
          '"items":[' +
          '{"uuid":"i1","shareId":"v1","data":{"type":"login","metadata":{"name":"Work Site"},"content":{"itemUsername":"u1","password":"p1"}}},' +
          '{"uuid":"i2","shareId":"unknown","data":{"type":"login","metadata":{"name":"Orphan"},"content":{"itemUsername":"u2","password":"p2"}}}]}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        expect(result.groups.length).assertEqual(1);
        expect(result.groups[0].name).assertEqual('Work');
        expect(result.groups[0].entries.length).assertEqual(1);
        expect(result.groups[0].entries[0].fields.get('Title')).assertEqual('Work Site');
        // shareId 无法解析时落根组
        expect(result.entries.length).assertEqual(1);
        expect(result.entries[0].fields.get('Title')).assertEqual('Orphan');
      });

      it('shouldPreferVaultItemsOverTopLevelItems', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const vaultItem = '{"uuid":"i1","data":{"type":"login","metadata":{"name":"Vault Item"},"content":{"itemUsername":"u","password":"p"}}}';
        const jsonContent = '{"encrypted":false,"vaults":{"v1":{"name":"V","items":[' + vaultItem + ']}},' +
          '"items":[' + vaultItem + ']}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');

        const result = await handler.import(fileContent);

        // vaults 内嵌条目优先，顶层 items 跳过（防重复导入）
        expect(result.groups[0].entries.length).assertEqual(1);
        expect(result.entries.length).assertEqual(0);
      });

      it('shouldThrowUnsupportedFormatWhenEncrypted', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":true,"vaults":{}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');
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

      it('shouldThrowFileEmptyWhenNoItems', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const jsonContent = '{"encrypted":false,"vaults":{}}';
        const fileContent = TestUtils.createFileContent(jsonContent, 'proton.json');
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

      it('shouldThrowInvalidJsonFormatForInvalidJson', 0, async () => {
        const testDb = await TestUtils.createTestDatabase('Proton Pass JSON Test Database');
        FileService.resetDbFileParam(testDb, Date.now());

        const fileContent = TestUtils.createFileContent('not valid json', 'proton.json');
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
  });
}
