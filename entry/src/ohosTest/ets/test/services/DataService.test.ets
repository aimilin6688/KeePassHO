import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { DataService } from '../../../../main/ets/services/DataService';
import { ExportType, SaveKdbxParam } from '../../../../main/ets/services/TypeDefined';
import { LocationInfo, LocationMode } from '../../../../main/ets/services/beans/LocationParam';
import { StorageType } from '../../../../main/ets/storage/StorageType';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

function buildLocation(filePath: string): LocationInfo {
  return {
    mode: LocationMode.SAVE,
    filePath: filePath,
    fileName: 'out.kdbx',
    fileSuffix: [],
    storageType: StorageType.LOCAL,
    storageConfig: {}
  };
}

function undefinedKdbx(): Kdbx | undefined {
  return undefined;
}

export default function DataServiceTest() {
  describe('DataService', () => {
    let kdbx: Kdbx;

    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
      const credentials = new KdbxCredentials(ProtectedValue.fromString('pw'));
      kdbx = Kdbx.create(credentials, 'data-test');
      // CSV 导出对空库抛 DATABASE_EMPTY，夹具库至少放入一个条目
      const entry = kdbx.createEntry(kdbx.getDefaultGroup());
      entry.fields.set('Title', 'data-test-entry');
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('getFileContent rejects with Unsupported export type when no kdbx and not CREATE_KEY', 0, async () => {
      const param: SaveKdbxParam = {
        exportType: ExportType.KDBX,
        kdbx: undefinedKdbx() as Kdbx,
        locationInfo: buildLocation('/no/path.kdbx')
      };
      let threw = false;
      let msg = '';
      try {
        await DataService.getFileContent(param);
      } catch (e) {
        threw = true;
        msg = (e as Error).message;
      }
      expect(threw).assertTrue();
      expect(msg).assertContain('Unsupported export type');
    });

    it('getFileContent for CREATE_KEY produces a non-empty key file content', 0, async () => {
      const param: SaveKdbxParam = {
        exportType: ExportType.CREATE_KEY,
        kdbx: undefinedKdbx() as Kdbx,
        locationInfo: buildLocation('/no/key.key')
      };
      const content = await DataService.getFileContent(param);
      expect(content !== null && content !== undefined).assertTrue();
      expect(content.filePath).assertEqual('/no/key.key');
      expect(content.content.byteLength > 0).assertTrue();
    });

    it('getFileContent for KDBX export serializes the in-memory database', 0, async () => {
      const param: SaveKdbxParam = {
        exportType: ExportType.KDBX,
        kdbx: kdbx,
        locationInfo: buildLocation('/no/db.kdbx')
      };
      const content = await DataService.getFileContent(param);
      expect(content.filePath).assertEqual('/no/db.kdbx');
      expect(content.content.byteLength > 0).assertTrue();
    });

    it('getFileContent for XML export returns a non-empty buffer', 0, async () => {
      const param: SaveKdbxParam = {
        exportType: ExportType.XML,
        kdbx: kdbx,
        locationInfo: buildLocation('/no/db.xml')
      };
      const content = await DataService.getFileContent(param);
      expect(content.content.byteLength > 0).assertTrue();
    });

    it('getFileContent for CSV export returns a non-empty buffer', 0, async () => {
      const param: SaveKdbxParam = {
        exportType: ExportType.CSV,
        kdbx: kdbx,
        locationInfo: buildLocation('/no/db.csv')
      };
      const content = await DataService.getFileContent(param);
      expect(content.content.byteLength > 0).assertTrue();
    });

    // NOTE: saveKdbx / selectKdbx / toPasswordPage / saveKey require UI navigation, storage
    // backends and LoadingDialog which are unavailable in the unit-test environment.
    // They are covered by UI acceptance tests instead.
  });
}
