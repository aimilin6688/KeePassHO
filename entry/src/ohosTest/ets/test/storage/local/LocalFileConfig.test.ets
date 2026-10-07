import { describe, expect, it } from '@ohos/hypium';
import { LocalFilePageConfig, LocalFileStorageConfig } from '../../../../../main/ets/storage/local/LocalFileConfig';
import { StorageType } from '../../../../../main/ets/storage/StorageType';

export default function LocalFileConfigTest() {
  describe('LocalFileConfigTest', () => {

    describe('LocalFileStorageConfig', () => {
      it('should default size to 0 when no argument', 0, () => {
        const cfg: LocalFileStorageConfig = new LocalFileStorageConfig();
        expect(cfg.size).assertEqual(0);
      });

      it('should accept a positive size', 0, () => {
        const cfg: LocalFileStorageConfig = new LocalFileStorageConfig(1024);
        expect(cfg.size).assertEqual(1024);
      });

      it('should treat explicit undefined as default 0', 0, () => {
        const cfg: LocalFileStorageConfig = new LocalFileStorageConfig(undefined);
        expect(cfg.size).assertEqual(0);
      });

      it('should treat 0 as falsy and keep default 0', 0, () => {
        const cfg: LocalFileStorageConfig = new LocalFileStorageConfig(0);
        expect(cfg.size).assertEqual(0);
      });

      it('should allow setting size after construction', 0, () => {
        const cfg: LocalFileStorageConfig = new LocalFileStorageConfig();
        cfg.size = 4096;
        expect(cfg.size).assertEqual(4096);
      });

      it('should accept large size', 0, () => {
        const cfg: LocalFileStorageConfig = new LocalFileStorageConfig(10 * 1024 * 1024);
        expect(cfg.size).assertEqual(10 * 1024 * 1024);
      });
    });

    describe('LocalFilePageConfig', () => {
      it('should expose a non-empty pageUrl', 0, () => {
        expect(LocalFilePageConfig.pageUrl).assertEqual('storage/local/LocalFilePage');
      });

      it('should map to LOCAL storage type', 0, () => {
        expect(LocalFilePageConfig.storageType).assertEqual(StorageType.LOCAL);
      });

      it('should expose an id for UI testing', 0, () => {
        expect(LocalFilePageConfig.id).assertEqual('opt_local_file');
      });

      it('should expose icon resource', 0, () => {
        expect(LocalFilePageConfig.icon).not().assertUndefined();
      });

      it('should expose title resource', 0, () => {
        expect(LocalFilePageConfig.title).not().assertUndefined();
      });

      it('should expose selectDesc resource', 0, () => {
        expect(LocalFilePageConfig.selectDesc).not().assertUndefined();
      });

      it('should expose saveDesc resource', 0, () => {
        expect(LocalFilePageConfig.saveDesc).not().assertUndefined();
      });
    });
  });
}
