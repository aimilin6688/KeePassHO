import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { ErrorCodes, KeePassHoError } from '../../../../main/ets/services/error/KeepassHoError';

export default function KeepassHoErrorTest() {
  describe('KeePassHoError', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('constructor sets code, name and a formatted message with a detail', 0, () => {
      const err = new KeePassHoError('CODE_X', 'something broke');
      expect(err.code).assertEqual('CODE_X');
      expect(err.name).assertEqual('KeePassHoError');
      expect(err.message).assertContain('CODE_X');
      expect(err.message).assertContain('something broke');
    });

    it('constructor with only code produces an "Error CODE" message', 0, () => {
      const err = new KeePassHoError('ONLY_CODE');
      expect(err.code).assertEqual('ONLY_CODE');
      expect(err.message).assertEqual('Error ONLY_CODE');
    });

    it('is an instance of Error and KeePassHoError', 0, () => {
      const err = new KeePassHoError('E1', 'm');
      expect(err instanceof Error).assertTrue();
      expect(err instanceof KeePassHoError).assertTrue();
    });

    it('can be thrown and caught as KeePassHoError preserving code', 0, () => {
      let caught: KeePassHoError | null = null;
      try {
        throw new KeePassHoError('THROWN', 'detail');
      } catch (e) {
        if (e instanceof KeePassHoError) {
          caught = e;
        }
      }
      expect(caught !== null).assertTrue();
      expect(caught!.code).assertEqual('THROWN');
    });

    it('can be caught as generic Error too', 0, () => {
      let caughtAsError = false;
      try {
        throw new KeePassHoError('THROWN2');
      } catch (e) {
        if (e instanceof Error) {
          caughtAsError = true;
        }
      }
      expect(caughtAsError).assertTrue();
    });

    it('two errors with same code are equal in code but distinct instances', 0, () => {
      const a = new KeePassHoError('SAME');
      const b = new KeePassHoError('SAME');
      expect(a.code).assertEqual(b.code);
      expect(a === b).assertFalse();
    });

    it('ErrorCodes enum exposes all expected values', 0, () => {
      expect(ErrorCodes.FILE_NOT_PERMISSION).assertEqual('FILE_NOT_PERMISSION');
      expect(ErrorCodes.FILE_EMPTY).assertEqual('FILE_EMPTY');
      expect(ErrorCodes.FILE_PATH_EMPTY).assertEqual('FILE_PATH_EMPTY');
      expect(ErrorCodes.UI_CONTEXT_NOT_INIT).assertEqual('UI_CONTEXT_NOT_INIT');
      expect(ErrorCodes.FILE_TYPE_NOT_SUPPORT).assertEqual('FILE_TYPE_NOT_SUPPORT');
      expect(ErrorCodes.FILE_IMPORT_ERROR).assertEqual('FILE_IMPORT_ERROR');
      expect(ErrorCodes.INVALID_CSV_HEADER).assertEqual('INVALID_CSV_HEADER');
      expect(ErrorCodes.READ_ONLY).assertEqual('READ_ONLY');
    });

    it('a KeePassHoError with a falsy code string still carries the code', 0, () => {
      const err = new KeePassHoError(ErrorCodes.FILE_EMPTY, 'file was empty');
      expect(err.code).assertEqual(ErrorCodes.FILE_EMPTY);
      expect(err.message).assertContain('file was empty');
    });

    it('message format is "Error <code>: <message>" when detail provided', 0, () => {
      const err = new KeePassHoError('C', 'D');
      expect(err.message).assertEqual('Error C: D');
    });
  });
}
