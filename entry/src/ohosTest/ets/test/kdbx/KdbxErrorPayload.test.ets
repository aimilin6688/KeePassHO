import { describe, expect, it } from '@ohos/hypium';
import { KdbxError, Consts } from 'kdbxweb';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { StorageError, StorageErrorCodes } from '../../../../main/ets/storage/StorageError';

export default function KdbxErrorPayloadTest() {
  describe('KdbxErrorPayloadTest', () => {
    /**
     * DecompressedTooLarge 映射到 database_decompressed_too_large 资源 ID
     */
    it('DecompressedTooLarge maps to database_decompressed_too_large resource id', 0, () => {
      try {
        throw new KdbxError(Consts.ErrorCodes.DecompressedTooLarge, 'payload exceeds limit');
      } catch (e) {
        const payload = KdbxUtils.kdbxErrorPayload(e);
        expect(typeof payload).assertEqual('number');
        expect(payload as number).assertLarger(0);
      }
    });

    /**
     * StorageError UPLOAD_TOO_LARGE 映射到 storage_upload_too_large 资源 ID
     */
    it('UPLOAD_TOO_LARGE maps to storage_upload_too_large resource id', 0, () => {
      try {
        throw new StorageError(StorageErrorCodes.UPLOAD_TOO_LARGE, '99999999 bytes');
      } catch (e) {
        const payload = KdbxUtils.kdbxErrorPayload(e);
        expect(typeof payload).assertEqual('number');
        expect(payload as number).assertLarger(0);
      }
    });

    /**
     * StorageError 其他错误码（非 UPLOAD_TOO_LARGE）返回 error.message
     */
    it('other StorageError returns message', 0, () => {
      try {
        throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, 'read failed');
      } catch (e) {
        const payload = KdbxUtils.kdbxErrorPayload(e);
        expect(typeof payload).assertEqual('string');
        expect((payload as string).includes('FILE_READ_ERROR')).assertTrue();
      }
    });

    /**
     * 普通 Error 返回 message
     */
    it('plain Error returns message', 0, () => {
      try {
        throw new Error('database_too_large');
      } catch (e) {
        const payload = KdbxUtils.kdbxErrorPayload(e);
        expect(payload).assertEqual('database_too_large');
      }
    });

    /**
     * 已有的 KdbxError 错误码仍正常映射（回归）
     */
    it('InvalidKey still maps correctly (regression)', 0, () => {
      try {
        throw new KdbxError(Consts.ErrorCodes.InvalidKey, 'bad key');
      } catch (e) {
        const payload = KdbxUtils.kdbxErrorPayload(e);
        expect(typeof payload).assertEqual('number');
      }
    });

    /**
     * FileCorrupt 仍正常映射（回归）
     */
    it('FileCorrupt still maps correctly (regression)', 0, () => {
      try {
        throw new KdbxError(Consts.ErrorCodes.FileCorrupt, 'corrupt');
      } catch (e) {
        const payload = KdbxUtils.kdbxErrorPayload(e);
        expect(typeof payload).assertEqual('number');
      }
    });

    /**
     * Consts.ErrorCodes 包含 DecompressedTooLarge
     */
    it('ErrorCodes has DecompressedTooLarge', 0, () => {
      expect(Consts.ErrorCodes.DecompressedTooLarge).assertEqual('DecompressedTooLarge');
    });

    /**
     * StorageErrorCodes 新增 UPLOAD_TOO_LARGE 枚举值
     */
    it('StorageErrorCodes has UPLOAD_TOO_LARGE', 0, () => {
      expect(StorageErrorCodes.UPLOAD_TOO_LARGE).assertEqual('UPLOAD_TOO_LARGE');
    });
  });
}
