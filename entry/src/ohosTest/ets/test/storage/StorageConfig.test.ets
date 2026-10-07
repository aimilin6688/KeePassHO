import { describe, expect, it } from '@ohos/hypium';
import { PageConfig, StorageConfig } from '../../../../main/ets/storage/StorageConfig';

/**
 * StorageConfig / PageConfig 是纯接口，无运行时逻辑。
 * 此测试为结构回归保护：确保接口字段 shape 稳定，可被实现并正确读写。
 */
class PageConfigImpl implements PageConfig {
  icon: Resource = $r('app.media.ic_file');
  title: ResourceStr = '';
  selectDesc: ResourceStr = '';
  saveDesc: ResourceStr = '';
  pageUrl: string = '';
  storageType: string = '';
  id?: string;
}

class EmptyConfig implements StorageConfig {}

export default function StorageConfigTest() {
  describe('StorageConfigTest', () => {

    describe('StorageConfig', () => {
      it('should be implementable as empty interface', 0, () => {
        const cfg: StorageConfig = new EmptyConfig();
        expect(cfg).not().assertUndefined();
      });
    });

    describe('StoragePageConfig', () => {
      it('should implement all required fields with defaults', 0, () => {
        const cfg: PageConfigImpl = new PageConfigImpl();
        expect(cfg.icon).not().assertUndefined();
        expect(cfg.title).assertEqual('');
        expect(cfg.selectDesc).assertEqual('');
        expect(cfg.saveDesc).assertEqual('');
        expect(cfg.pageUrl).assertEqual('');
        expect(cfg.storageType).assertEqual('');
      });

      it('id should be optional (undefined by default)', 0, () => {
        const cfg: PageConfigImpl = new PageConfigImpl();
        expect(cfg.id).assertUndefined();
      });

      it('should allow setting all fields', 0, () => {
        const cfg: PageConfigImpl = new PageConfigImpl();
        cfg.title = 'S3';
        cfg.pageUrl = 'storage/s3/S3Page';
        cfg.storageType = 'S3';
        cfg.id = 'opt_s3';
        expect(cfg.title).assertEqual('S3');
        expect(cfg.pageUrl).assertEqual('storage/s3/S3Page');
        expect(cfg.storageType).assertEqual('S3');
        expect(cfg.id).assertEqual('opt_s3');
      });

      it('should be usable via interface type', 0, () => {
        const cfg: PageConfig = new PageConfigImpl();
        cfg.storageType = 'FTP';
        expect(cfg.storageType).assertEqual('FTP');
      });
    });
  });
}
