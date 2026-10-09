import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { CacheMeta, CacheMetaService } from '../../../../../main/ets/storage/cache/CacheMetaService';
import { CacheConstants } from '../../../../../main/ets/storage/cache/CacheConstants';
import { CommonUtils } from '../../../../../main/ets/common/utils/CommonUtils';

/**
 * 缓存元数据 sidecar 单元测试（加载链路版本快速路径 P1）
 * 覆盖：写读删往返 / 缺失容错 / 内容损坏容错 / 路径规则
 */
export default function CacheMetaServiceTest() {
  describe('CacheMetaServiceTest', () => {
    let remotePath: string;
    let metaPath: string;

    beforeAll(() => {
      const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      remotePath = appContext.filesDir + '/cache-meta-test.kdbx';
      metaPath = CacheMetaService.getMetaPath(remotePath);
      // 干净起点
      try {
        if (fs.accessSync(metaPath, fs.AccessModeType.EXIST)) {
          fs.unlinkSync(metaPath);
        }
      } catch {
        // ignore
      }
    });

    /**
     * 元数据路径 = 缓存文件路径 + .meta（生命周期与缓存文件绑定）
     */
    it('meta path is cache path plus suffix', 0, () => {
      expect(metaPath).assertEqual(CacheConstants.getCacheFilePath(remotePath) + '.meta');
    });

    /**
     * 无元数据时返回 null（fail-safe：调用方退化为全量下载）
     */
    it('readMeta returns null when meta missing', 0, () => {
      expect(CacheMetaService.readMeta(remotePath)).assertNull();
    });

    /**
     * 写读往返：版本/尺寸/时间完整保真
     */
    it('writeMeta and readMeta round trip', 0, async () => {
      const meta: CacheMeta = {
        version: 'etag-abc|Fri, 09 Oct 2026 08:00:00 GMT',
        size: 123456,
        modifiedTime: 1760000000000,
        savedAt: Date.now()
      };
      await CacheMetaService.writeMeta(remotePath, meta);
      const loaded: CacheMeta | null = CacheMetaService.readMeta(remotePath);
      expect(loaded).not().assertNull();
      expect((loaded as CacheMeta).version).assertEqual(meta.version);
      expect((loaded as CacheMeta).size).assertEqual(meta.size);
      expect((loaded as CacheMeta).modifiedTime).assertEqual(meta.modifiedTime);
    });

    /**
     * 覆盖写：版本随远端刷新（保存后回写场景）
     */
    it('writeMeta overwrites previous version', 0, async () => {
      const updated: CacheMeta = {
        version: 'etag-new|Fri, 09 Oct 2026 09:00:00 GMT',
        size: 654321,
        modifiedTime: 1760003600000,
        savedAt: Date.now()
      };
      await CacheMetaService.writeMeta(remotePath, updated);
      const loaded: CacheMeta | null = CacheMetaService.readMeta(remotePath);
      expect((loaded as CacheMeta).version).assertEqual(updated.version);
      expect((loaded as CacheMeta).size).assertEqual(updated.size);
    });

    /**
     * 内容损坏（非法 JSON）→ null，不抛错
     */
    it('readMeta returns null on corrupted content', 0, async () => {
      const file = await fs.open(metaPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(file.fd, '{ this is not json');
      await fs.close(file.fd);
      expect(CacheMetaService.readMeta(remotePath)).assertNull();
    });

    /**
     * 删除后重新读取为 null；重复删除不抛错
     */
    it('deleteMeta removes meta and is idempotent', 0, async () => {
      const meta: CacheMeta = { version: 'v1', size: 1, modifiedTime: 1, savedAt: Date.now() };
      await CacheMetaService.writeMeta(remotePath, meta);
      expect(CacheMetaService.readMeta(remotePath)).not().assertNull();
      await CacheMetaService.deleteMeta(remotePath);
      expect(CacheMetaService.readMeta(remotePath)).assertNull();
      await CacheMetaService.deleteMeta(remotePath);
      expect(CacheMetaService.readMeta(remotePath)).assertNull();
    });
  });
}
