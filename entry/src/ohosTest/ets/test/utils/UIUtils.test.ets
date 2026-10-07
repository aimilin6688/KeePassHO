import { describe, expect, it } from '@ohos/hypium';
import { UIContext } from '@kit.ArkUI';
import { UIUtils, WidthResult } from '../../../../main/ets/common/utils/UIUtils';
import { UIConstants } from '../../../../main/ets/common/constants/UIConstants';

class FakeUIContext extends UIContext {
  private readonly scale: number;

  constructor(scale: number) {
    super();
    this.scale = scale;
  }

  px2vp(value: number): number {
    return value / this.scale;
  }
}

class ThrowingUIContext extends UIContext {
  px2vp(value: number): number {
    throw new Error('px2vp failed');
  }
}

const SCALE = 3;

export default function UIUtilsTest() {
  describe('UIUtils', () => {
    // ---------------- getMaxWidth ----------------
    it('getMaxWidth returns the content threshold constant', 0, () => {
      expect(UIUtils.getMaxWidth()).assertEqual(UIConstants.CONTENT_MAX_WIDTH_THRESHOLD);
      expect(UIUtils.getMaxWidth()).assertEqual(600);
    });

    // ---------------- calculateMaxWidth (wide window) ----------------
    it('calculateMaxWidth returns fixed width when vp width exceeds threshold', 0, () => {
      const ctx: UIContext = new FakeUIContext(SCALE);
      // 2400px / 3 = 800vp > 600vp threshold
      const result: WidthResult = UIUtils.calculateMaxWidth(ctx, 2400);
      expect(result.isPercentage).assertFalse();
      expect(result.width).assertEqual(UIConstants.CONTENT_MAX_WIDTH_THRESHOLD);
    });

    // ---------------- calculateMaxWidth (narrow window) ----------------
    it('calculateMaxWidth returns 100% when vp width is below threshold', 0, () => {
      const ctx: UIContext = new FakeUIContext(SCALE);
      // 900px / 3 = 300vp <= 600vp threshold
      const result: WidthResult = UIUtils.calculateMaxWidth(ctx, 900);
      expect(result.isPercentage).assertTrue();
      expect(result.width).assertEqual('100%');
    });

    it('calculateMaxWidth treats exactly-threshold width as percentage', 0, () => {
      const ctx: UIContext = new FakeUIContext(SCALE);
      // 1800px / 3 = 600vp == threshold (not strictly greater)
      const result: WidthResult = UIUtils.calculateMaxWidth(ctx, 1800);
      expect(result.isPercentage).assertTrue();
      expect(result.width).assertEqual('100%');
    });

    // ---------------- error fallback branch ----------------
    // A context whose px2vp throws makes calculateMaxWidth hit the catch
    // branch, which must return the fixed-width fallback.
    it('calculateMaxWidth falls back to fixed width on error', 0, () => {
      const ctx: UIContext = new ThrowingUIContext();
      const result: WidthResult = UIUtils.calculateMaxWidth(ctx, 100);
      expect(result.isPercentage).assertFalse();
      expect(result.width).assertEqual(UIConstants.CONTENT_MAX_WIDTH_THRESHOLD);
    });

    // ---------------- calculateDialogWidth ----------------
    it('calculateDialogWidth mirrors calculateMaxWidth for wide windows', 0, () => {
      const ctx: UIContext = new FakeUIContext(SCALE);
      const result: WidthResult = UIUtils.calculateDialogWidth(ctx, 2400);
      expect(result.isPercentage).assertFalse();
      expect(result.width).assertEqual(UIConstants.CONTENT_MAX_WIDTH_THRESHOLD);
    });

    it('calculateDialogWidth mirrors calculateMaxWidth for narrow windows', 0, () => {
      const ctx: UIContext = new FakeUIContext(SCALE);
      const result: WidthResult = UIUtils.calculateDialogWidth(ctx, 900);
      expect(result.isPercentage).assertTrue();
      expect(result.width).assertEqual('100%');
    });

    // ---------------- usePercentageWidth ----------------
    // Uses the real display width (device dependent), so only assert the type.
    it('usePercentageWidth returns a boolean', 0, () => {
      const ctx: UIContext = new FakeUIContext(SCALE);
      const result: boolean = UIUtils.usePercentageWidth(ctx);
      expect(typeof result).assertEqual('boolean');
    });

    // NOTE: display-based default resolution depends on the test device's
    // screen and is asserted loosely on purpose.
  });
}
