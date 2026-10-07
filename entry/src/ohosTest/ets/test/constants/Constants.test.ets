import { describe, expect, it } from '@ohos/hypium';
import { Constants } from '../../../../main/ets/common/constants/Constants';

export default function ConstantsTest() {
  describe('Constants', () => {
    it('asyncDatabaseFlagsAreTrue', 0, () => {
      expect(Constants.ASYNC_SAVE_DATABASE).assertTrue();
      expect(Constants.ASYNC_LOAD_DATABASE).assertTrue();
    });

    it('attachmentDiskThresholdConstantsHaveExpectedValues', 0, () => {
      expect(Constants.ATTACH_DISK_THRESHOLD_BYTES).assertEqual(16 * 1024 * 1024);
      expect(Constants.ATTACH_DISK_THRESHOLD_BYTES).assertEqual(16777216);
      expect(Constants.ATTACH_CACHE_MAX_TOTAL_BYTES).assertEqual(256 * 1024 * 1024);
      expect(Constants.ATTACH_CACHE_MAX_TOTAL_BYTES).assertEqual(268435456);
      expect(Constants.ATTACH_DISK_THRESHOLD_BYTES < Constants.ATTACH_CACHE_MAX_TOTAL_BYTES).assertTrue();
    });

    it('attachmentCacheNamingConstantsHaveExpectedValues', 0, () => {
      expect(Constants.ATTACH_CACHE_ASSET_ALIAS).assertEqual('keepassho.attach.cache.key');
      expect(Constants.ATTACH_CACHE_DIR_NAME).assertEqual('attach-cache');
    });

    it('appStorageLocationConstantsHaveExpectedValues', 0, () => {
      expect(Constants.APP_STORAGE_LOCATION_INFO).assertEqual('locationInfo');
      expect(Constants.APP_STORAGE_PRELOAD_RECENT_FILE).assertEqual('preloadRecentFile');
      expect(Constants.APP_STORAGE_PRELOAD_READY).assertEqual('preloadReady');
    });

    it('sessionNotifyIdHasExpectedValue', 0, () => {
      expect(Constants.SESSION_NOTIFY_ID).assertEqual(0x1001);
      expect(Constants.SESSION_NOTIFY_ID).assertEqual(4097);
    });

    it('sessionActionConstantsHaveExpectedValues', 0, () => {
      expect(Constants.SESSION_ACTION_COPY_FIELD).assertEqual('keepassho.action.COPY_FIELD');
      expect(Constants.SESSION_ACTION_NOTIFY_REMOVED).assertEqual('keepassho.action.SESSION_NOTIFY_REMOVED');
    });

    it('sessionStateConstantsHaveExpectedValues', 0, () => {
      expect(Constants.APP_STORAGE_SESSION_ACTIVE).assertEqual('sessionActive');
      expect(Constants.SESSION_FIELD_TYPE_USERNAME).assertEqual('USERNAME');
      expect(Constants.SESSION_FIELD_TYPE_PASSWORD).assertEqual('PASSWORD');
      expect(Constants.SESSION_FIELD_TYPE_USERNAME === Constants.SESSION_FIELD_TYPE_PASSWORD).assertFalse();
    });
  });
}
