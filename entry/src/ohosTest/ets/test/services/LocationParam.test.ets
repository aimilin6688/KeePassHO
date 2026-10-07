import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { LocationInfo, LocationMode, LocationParam } from '../../../../main/ets/services/beans/LocationParam';
import { StorageType } from '../../../../main/ets/storage/StorageType';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

export default function LocationParamTest() {
  describe('LocationParam', () => {
    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    beforeEach(() => {
      LocationParam.clear();
    });

    afterEach(() => {
      LocationParam.clear();
    });

    afterAll(() => {
      LocationParam.clear();
    });

    it('LocationMode enum values', 0, () => {
      expect(LocationMode.SAVE).assertEqual('SAVE');
      expect(LocationMode.SELECT).assertEqual('SELECT');
    });

    it('ofSelect builds a SELECT-mode param with file suffix', 0, () => {
      const p = LocationParam.ofSelect(['kdbx']);
      expect(p.mode).assertEqual(LocationMode.SELECT);
      expect(p.fileSuffix.length).assertEqual(1);
      expect(p.fileSuffix[0]).assertEqual('kdbx');
    });

    it('ofSave builds a SAVE-mode param with fileName', 0, () => {
      const p = LocationParam.ofSave('my.kdbx');
      expect(p.mode).assertEqual(LocationMode.SAVE);
      expect(p.fileName).assertEqual('my.kdbx');
      expect(p.fileSuffix.length).assertEqual(0);
    });

    it('of builds a param from a LocationInterface', 0, () => {
      const p = LocationParam.of({
        mode: LocationMode.SAVE,
        fileName: 'x.kdbx',
        fileSuffix: ['kdbx']
      });
      expect(p.mode).assertEqual(LocationMode.SAVE);
      expect(p.fileName).assertEqual('x.kdbx');
      expect(p.fileSuffix[0]).assertEqual('kdbx');
    });

    it('getInstance returns a SELECT-mode default when not initialized', 0, () => {
      const p = LocationParam.getInstance();
      expect(p.mode).assertEqual(LocationMode.SELECT);
    });

    it('isSelectMode / isSaveMode reflect the current instance', 0, () => {
      LocationParam.ofSelect(['kdbx']);
      expect(LocationParam.isSelectMode()).assertTrue();
      expect(LocationParam.isSaveMode()).assertFalse();
      LocationParam.ofSave('a.kdbx');
      expect(LocationParam.isSaveMode()).assertTrue();
      expect(LocationParam.isSelectMode()).assertFalse();
    });

    it('getMode returns the current mode', 0, () => {
      LocationParam.ofSave('b.kdbx');
      expect(LocationParam.getMode()).assertEqual(LocationMode.SAVE);
    });

    it('getFileName returns the configured fileName in SAVE mode', 0, () => {
      LocationParam.ofSave('named.kdbx');
      expect(LocationParam.getFileName()).assertEqual('named.kdbx');
    });

    it('getFileName falls back to current date when no fileName set', 0, () => {
      LocationParam.ofSelect([]);
      const name = LocationParam.getFileName();
      expect(name.length > 0).assertTrue();
    });

    it('getFileSuffix returns the configured suffix list', 0, () => {
      LocationParam.ofSelect(['kdbx', 'kdb']);
      const s = LocationParam.getFileSuffix();
      expect(s.length).assertEqual(2);
      expect(s[0]).assertEqual('kdbx');
      expect(s[1]).assertEqual('kdb');
    });

    it('getFileSuffix is empty when not set', 0, () => {
      LocationParam.ofSave('a.kdbx');
      expect(LocationParam.getFileSuffix().length).assertEqual(0);
    });

    it('callOnLocation invokes the registered callback with the info', 0, () => {
      let received: LocationInfo | null = null;
      LocationParam.ofSelect(['kdbx'], (info: LocationInfo) => {
        received = info;
      });
      const info: LocationInfo = {
        mode: LocationMode.SELECT,
        filePath: '/p/x.kdbx',
        fileName: 'x.kdbx',
        fileSuffix: ['kdbx'],
        storageType: StorageType.LOCAL,
        storageConfig: {}
      };
      LocationParam.callOnLocation(info);
      expect(received !== null).assertTrue();
      expect(received!.filePath).assertEqual('/p/x.kdbx');
    });

    it('toLocationInfo builds a LocationInfo from current state', 0, () => {
      LocationParam.ofSelect(['kdbx']);
      const info = LocationParam.toLocationInfo(StorageType.LOCAL, '/path/a.kdbx');
      expect(info.mode).assertEqual(LocationMode.SELECT);
      expect(info.filePath).assertEqual('/path/a.kdbx');
      expect(info.storageType).assertEqual(StorageType.LOCAL);
      const suffix: Array<string> = info.fileSuffix ?? [];
      expect(suffix.length).assertEqual(1);
      expect(suffix[0]).assertEqual('kdbx');
    });

    it('toLocationInfo uses default empty path and config when omitted', 0, () => {
      LocationParam.ofSave('z.kdbx');
      const info = LocationParam.toLocationInfo(StorageType.LOCAL);
      expect(info.filePath).assertEqual('');
      expect(info.storageConfig !== null && info.storageConfig !== undefined).assertTrue();
    });

    it('clear resets the singleton so getInstance returns the default', 0, () => {
      LocationParam.ofSave('cleared.kdbx');
      expect(LocationParam.isSaveMode()).assertTrue();
      LocationParam.clear();
      expect(LocationParam.getInstance().mode).assertEqual(LocationMode.SELECT);
    });
  });
}
