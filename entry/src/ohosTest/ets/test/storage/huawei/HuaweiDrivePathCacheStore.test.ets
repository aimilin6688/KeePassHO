import { afterAll, afterEach, beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import {
  HuaweiDrivePathCacheData,
  HuaweiDrivePathCacheEntry,
  HuaweiDrivePathCacheStore
} from '../../../../../main/ets/storage/huawei/HuaweiDrivePathCacheStore';
import { CommonUtils } from '../../../../../main/ets/common/utils/CommonUtils';

function makeData(owner: string = 'owner-hash-abc'): HuaweiDrivePathCacheData {
  const entries: HuaweiDrivePathCacheEntry[] = [
    { p: 'keepass', id: 'file-id-1' },
    { p: 'keepass/sub', id: 'file-id-2' }
  ];
  return {
    owner: owner,
    rootId: 'root-id-123',
    entries: entries
  };
}

export default function HuaweiDrivePathCacheStoreTest() {
  describe('HuaweiDrivePathCacheStoreTest', () => {

    beforeAll(async () => {
      const appContext: common.Context = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
      await HuaweiDrivePathCacheStore.clear();
    });

    afterEach(async () => {
      await HuaweiDrivePathCacheStore.clear();
    });

    afterAll(async () => {
      await HuaweiDrivePathCacheStore.clear();
    });

    describe('ownerHash', () => {
      it('should return empty string for empty input', 0, async () => {
        expect(await HuaweiDrivePathCacheStore.ownerHash('')).assertEqual('');
      });

      it('should return a 16-char hex string for non-empty input', 0, async () => {
        const hash: string = await HuaweiDrivePathCacheStore.ownerHash('refresh-token-123');
        expect(hash.length).assertEqual(16);
        expect(/^[0-9a-f]{16}$/.test(hash)).assertTrue();
      });

      it('should be deterministic for the same input', 0, async () => {
        const a: string = await HuaweiDrivePathCacheStore.ownerHash('same-key');
        const b: string = await HuaweiDrivePathCacheStore.ownerHash('same-key');
        expect(a).assertEqual(b);
      });

      it('should differ for different inputs', 0, async () => {
        const a: string = await HuaweiDrivePathCacheStore.ownerHash('key-a');
        const b: string = await HuaweiDrivePathCacheStore.ownerHash('key-b');
        expect(a !== b).assertTrue();
      });

      it('should produce stable known hash length regardless of input length', 0, async () => {
        const short: string = await HuaweiDrivePathCacheStore.ownerHash('x');
        const long: string = await HuaweiDrivePathCacheStore.ownerHash('x'.repeat(1000));
        expect(short.length).assertEqual(16);
        expect(long.length).assertEqual(16);
      });

      it('should support unicode input', 0, async () => {
        const hash: string = await HuaweiDrivePathCacheStore.ownerHash('刷新令牌');
        expect(hash.length).assertEqual(16);
        expect(/^[0-9a-f]{16}$/.test(hash)).assertTrue();
      });
    });

    describe('load_empty', () => {
      it('should return null when no cache exists', 0, async () => {
        const loaded: HuaweiDrivePathCacheData | null = await HuaweiDrivePathCacheStore.load();
        expect(loaded).assertNull();
      });
    });

    describe('save_load_round_trip', () => {
      it('should persist and restore owner + rootId + entries', 0, async () => {
        const data: HuaweiDrivePathCacheData = makeData('owner-A');
        await HuaweiDrivePathCacheStore.save(data);

        const loaded: HuaweiDrivePathCacheData | null = await HuaweiDrivePathCacheStore.load();
        expect(loaded).not().assertNull();
        expect(loaded!.owner).assertEqual('owner-A');
        expect(loaded!.rootId).assertEqual('root-id-123');
        expect(loaded!.entries.length).assertEqual(2);
        expect(loaded!.entries[0].p).assertEqual('keepass');
        expect(loaded!.entries[0].id).assertEqual('file-id-1');
        expect(loaded!.entries[1].p).assertEqual('keepass/sub');
        expect(loaded!.entries[1].id).assertEqual('file-id-2');
      });

      it('should persist empty entries array', 0, async () => {
        const data: HuaweiDrivePathCacheData = {
          owner: 'owner-empty-entries',
          rootId: 'root-x',
          entries: []
        };
        await HuaweiDrivePathCacheStore.save(data);
        const loaded: HuaweiDrivePathCacheData | null = await HuaweiDrivePathCacheStore.load();
        expect(loaded).not().assertNull();
        expect(loaded!.entries.length).assertEqual(0);
      });

      it('should overwrite previous cache on subsequent save', 0, async () => {
        await HuaweiDrivePathCacheStore.save(makeData('owner-first'));
        await HuaweiDrivePathCacheStore.save({
          owner: 'owner-second',
          rootId: 'root-2',
          entries: [{ p: 'other', id: 'id-other' }]
        });
        const loaded: HuaweiDrivePathCacheData | null = await HuaweiDrivePathCacheStore.load();
        expect(loaded!.owner).assertEqual('owner-second');
        expect(loaded!.rootId).assertEqual('root-2');
        expect(loaded!.entries.length).assertEqual(1);
        expect(loaded!.entries[0].p).assertEqual('other');
      });

      it('should persist many entries', 0, async () => {
        const entries: HuaweiDrivePathCacheEntry[] = [];
        for (let i = 0; i < 50; i++) {
          entries.push({ p: 'path/' + i, id: 'id-' + i });
        }
        await HuaweiDrivePathCacheStore.save({ owner: 'owner-many', rootId: 'root', entries: entries });
        const loaded: HuaweiDrivePathCacheData | null = await HuaweiDrivePathCacheStore.load();
        expect(loaded!.entries.length).assertEqual(50);
        expect(loaded!.entries[25].p).assertEqual('path/25');
        expect(loaded!.entries[49].id).assertEqual('id-49');
      });
    });

    describe('clear', () => {
      it('should remove persisted cache', 0, async () => {
        await HuaweiDrivePathCacheStore.save(makeData('owner-to-clear'));
        expect(await HuaweiDrivePathCacheStore.load()).not().assertNull();
        await HuaweiDrivePathCacheStore.clear();
        expect(await HuaweiDrivePathCacheStore.load()).assertNull();
      });

      it('should be safe to call on empty cache', 0, async () => {
        await HuaweiDrivePathCacheStore.clear();
        await HuaweiDrivePathCacheStore.clear();
        expect(await HuaweiDrivePathCacheStore.load()).assertNull();
      });
    });

    describe('parse_rejection_empty_owner', () => {
      it('save with empty owner should make load return null (parse rejects empty owner)', 0, async () => {
        // 直接调用 save 写入空 owner，load 的严格解析会丢弃
        const data: HuaweiDrivePathCacheData = {
          owner: '',
          rootId: 'root',
          entries: []
        };
        await HuaweiDrivePathCacheStore.save(data);
        const loaded: HuaweiDrivePathCacheData | null = await HuaweiDrivePathCacheStore.load();
        expect(loaded).assertNull();
      });
    });

    describe('worker_mode_file_backend', () => {
      it('save and load work without Context (worker environment simulation)', 0, async () => {
        // 模拟 Worker：清除 Context + 注入沙箱路径（§11.1 注入协议）
        // 文件后端设计目标：Worker 内路径缓存可水合/落盘，不再出现 preferences "context is invalid"
        const originalContext = CommonUtils.getContext();
        const filesDir = CommonUtils.getAppFilesDir();
        const cacheDir = CommonUtils.getCacheDir();
        CommonUtils.clearContextForTest();
        CommonUtils.setWorkerPaths(filesDir, cacheDir);
        try {
          await HuaweiDrivePathCacheStore.clear();
          await HuaweiDrivePathCacheStore.save(makeData('owner-worker'));
          const loaded: HuaweiDrivePathCacheData | null = await HuaweiDrivePathCacheStore.load();
          expect(loaded).not().assertNull();
          expect(loaded!.owner).assertEqual('owner-worker');
          expect(loaded!.entries.length).assertEqual(2);
        } finally {
          CommonUtils.init(originalContext);
          await HuaweiDrivePathCacheStore.clear();
        }
      });
    });
  });
}
