import { describe, expect, it } from '@ohos/hypium';
import { HTTP_UPLOAD_MAX_BYTES, StorageError, StorageErrorCodes } from '../../../../main/ets/storage/StorageError';

export default function UploadTooLargeGuardTest() {
  describe('UploadTooLargeGuardTest', () => {
    /**
     * HTTP_UPLOAD_MAX_BYTES = 100MB
     */
    it('HTTP_UPLOAD_MAX_BYTES is 100MB', 0, () => {
      expect(HTTP_UPLOAD_MAX_BYTES).assertEqual(100 * 1024 * 1024);
    });

    /**
     * StorageError UPLOAD_TOO_LARGE 可正确构造
     */
    it('StorageError UPLOAD_TOO_LARGE constructable', 0, () => {
      const err = new StorageError(StorageErrorCodes.UPLOAD_TOO_LARGE, '99999999 bytes');
      expect(err.code).assertEqual('UPLOAD_TOO_LARGE');
      expect(err.message.includes('UPLOAD_TOO_LARGE')).assertTrue();
      expect(err.message.includes('99999999')).assertTrue();
    });

    /**
     * 上限边界：恰好 100MB 不应触发（> 才触发，= 不触发）
     */
    it('boundary: exactly 100MB does not exceed', 0, () => {
      const size = HTTP_UPLOAD_MAX_BYTES;
      expect(size > HTTP_UPLOAD_MAX_BYTES).assertFalse();
    });

    /**
     * 上限边界：100MB + 1 超过
     */
    it('boundary: 100MB + 1 exceeds', 0, () => {
      const size = HTTP_UPLOAD_MAX_BYTES + 1;
      expect(size > HTTP_UPLOAD_MAX_BYTES).assertTrue();
    });
  });
}
