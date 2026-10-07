import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { NetworkUtils } from '../../../../main/ets/common/utils/NetworkUtils';

export default function NetworkUtilsTest() {
  describe('NetworkUtils', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    // ---------------- hasNetwork ----------------
    it('hasNetwork returns a boolean', 0, async () => {
      const result = await NetworkUtils.hasNetwork();
      expect(typeof result).assertEqual('boolean');
    });

    it('hasNetwork does not throw', 0, async () => {
      let threw = false;
      try {
        await NetworkUtils.hasNetwork();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('hasNetwork returns consistent value across calls', 0, async () => {
      const r1 = await NetworkUtils.hasNetwork();
      const r2 = await NetworkUtils.hasNetwork();
      expect(r1).assertEqual(r2);
    });
  });
}
