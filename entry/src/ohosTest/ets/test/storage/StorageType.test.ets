import { describe, expect, it } from '@ohos/hypium';
import { StorageType } from '../../../../main/ets/storage/StorageType';

export default function StorageTypeTest() {
  describe('StorageTypeTest', () => {

    describe('EnumValues', () => {
      it('LOCAL should equal LOCAL', 0, () => {
        expect(StorageType.LOCAL).assertEqual('LOCAL');
      });

      it('WEBDAV should equal WEBDAV', 0, () => {
        expect(StorageType.WEBDAV).assertEqual('WEBDAV');
      });

      it('FTP should equal FTP', 0, () => {
        expect(StorageType.FTP).assertEqual('FTP');
      });

      it('ONEDRIVE should equal ONEDRIVE', 0, () => {
        expect(StorageType.ONEDRIVE).assertEqual('ONEDRIVE');
      });

      it('S3 should equal S3', 0, () => {
        expect(StorageType.S3).assertEqual('S3');
      });

      it('PCLOUD should equal PCLOUD', 0, () => {
        expect(StorageType.PCLOUD).assertEqual('PCLOUD');
      });

      it('BAIDU_NETDISK should equal BAIDU_NETDISK', 0, () => {
        expect(StorageType.BAIDU_NETDISK).assertEqual('BAIDU_NETDISK');
      });

      it('HUAWEI_DRIVE should equal HUAWEI_DRIVE', 0, () => {
        expect(StorageType.HUAWEI_DRIVE).assertEqual('HUAWEI_DRIVE');
      });
    });

    describe('EnumShape', () => {
      it('should expose 8 members', 0, () => {
        const keys: string[] = Object.keys(StorageType);
        expect(keys.length).assertEqual(8);
      });

      it('all values should be unique strings', 0, () => {
        const values: string[] = Object.values(StorageType) as string[];
        const set: Set<string> = new Set(values);
        expect(set.size).assertEqual(values.length);
        for (let i = 0; i < values.length; i++) {
          expect(typeof values[i]).assertEqual('string');
        }
      });

      it('each value should match its key (no reverse mapping for string enum)', 0, () => {
        expect(StorageType['LOCAL']).assertEqual('LOCAL');
        expect(StorageType['HUAWEI_DRIVE']).assertEqual('HUAWEI_DRIVE');
      });

      it('unknown key should be undefined', 0, () => {
        const keys: string[] = Object.keys(StorageType);
        const values: string[] = Object.values(StorageType) as string[];
        const lookup: Map<string, string> = new Map<string, string>();
        for (let i = 0; i < keys.length; i++) {
          lookup.set(keys[i], values[i]);
        }
        expect(lookup.get('UNKNOWN')).assertUndefined();
      });
    });
  });
}
