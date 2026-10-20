import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { deviceInfo } from '@kit.BasicServicesKit';
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

    it('isEmulator matches productModel heuristic on the current device', 0, () => {
      // 真机/模拟器通用：判定结果应与 productModel 启发式一致
      expect(DeviceUtils.isEmulator()).assertEqual(deviceInfo.productModel === 'emulator');
    });

    it('isEmulator returns consistent value across calls', 0, () => {
      const r1 = DeviceUtils.isEmulator();
      const r2 = DeviceUtils.isEmulator();
      expect(r1).assertEqual(r2);
    });
  });
}
