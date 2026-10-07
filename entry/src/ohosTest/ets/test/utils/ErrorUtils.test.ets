import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { ErrorUtils } from '../../../../main/ets/common/utils/ErrorUtils';

export default function ErrorUtilsTest() {
  describe('ErrorUtils', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    // ---------------- toError ----------------
    it('toError returns object with given code and string message', 0, () => {
      const err = ErrorUtils.toError(999, 'test message');
      expect(err.code).assertEqual(999);
      expect(err.message).assertEqual('test message');
    });

    it('toError returns object with given code and resource message', 0, () => {
      const err = ErrorUtils.toError(500, $r('app.string.database_not_opened'));
      expect(err.code).assertEqual(500);
      expect(err.message).not().assertNull();
    });

    it('toError with code zero', 0, () => {
      const err = ErrorUtils.toError(0, 'zero');
      expect(err.code).assertEqual(0);
      expect(err.message).assertEqual('zero');
    });

    it('toError with negative code', 0, () => {
      const err = ErrorUtils.toError(-1, 'neg');
      expect(err.code).assertEqual(-1);
    });

    // ---------------- static error constants ----------------
    it('DATABASE_NOT_OPENED has code 1001', 0, () => {
      expect(ErrorUtils.DATABASE_NOT_OPENED.code).assertEqual(1001);
    });

    it('DATABASE_NOT_SET has code 1002', 0, () => {
      expect(ErrorUtils.DATABASE_NOT_SET.code).assertEqual(1002);
    });

    it('AUTH_CANCELED has code 1002', 0, () => {
      expect(ErrorUtils.AUTH_CANCELED.code).assertEqual(1002);
    });

    it('DATABASE_NOT_OPENED message is a resource object', 0, () => {
      expect(ErrorUtils.DATABASE_NOT_OPENED.message).not().assertNull();
    });

    it('DATABASE_NOT_SET message is a resource object', 0, () => {
      expect(ErrorUtils.DATABASE_NOT_SET.message).not().assertNull();
    });

    it('AUTH_CANCELED message is a resource object', 0, () => {
      expect(ErrorUtils.AUTH_CANCELED.message).not().assertNull();
    });

    it('DATABASE_NOT_OPENED and DATABASE_NOT_SET have different messages', 0, () => {
      const m1 = ErrorUtils.DATABASE_NOT_OPENED.message;
      const m2 = ErrorUtils.DATABASE_NOT_SET.message;
      expect(m1 === m2).assertFalse();
    });
  });
}
