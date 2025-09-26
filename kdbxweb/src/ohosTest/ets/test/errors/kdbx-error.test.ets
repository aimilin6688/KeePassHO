import { describe, expect, it } from '@ohos/hypium';
import { KdbxError } from '../../../../main/ets/index';

export default function KdbxErrorTest() {
  describe('KdbxError', () => {
    it('creates error without message', 0, () => {
      const err = new KdbxError('1');
      expect(err.name).assertEqual('KdbxError');
      expect(err.code).assertEqual('1');
      expect(err.message).assertEqual('Error 1');
      expect(err.toString()).assertEqual('KdbxError: Error 1');
    });

    it('creates error with message', 0, () => {
      const err = new KdbxError('2', 'msg');
      expect(err.name).assertEqual('KdbxError');
      expect(err.code).assertEqual('2');
      expect(err.message).assertEqual('Error 2: msg');
      expect(err.toString()).assertEqual('KdbxError: Error 2: msg');
    });
  });
}


