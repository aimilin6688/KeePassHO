import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { DeviceUtils } from '../../../../main/ets/common/utils/DeviceUtils';

export default function DeviceUtilsTest() {
  describe('DeviceUtils', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    // ---------------- isEmulator ----------------
    it('isEmulator returns a boolean', 0, () => {
      const result = DeviceUtils.isEmulator();
      expect(typeof result).assertEqual('boolean');
    });

    it('isEmulator returns true on emulator device', 0, () => {
      // Tests run on the emulator where productModel === 'emulator'
      expect(DeviceUtils.isEmulator()).assertTrue();
    });

    it('isEmulator returns consistent value across calls', 0, () => {
      const r1 = DeviceUtils.isEmulator();
      const r2 = DeviceUtils.isEmulator();
      expect(r1).assertEqual(r2);
    });
  });
}
