import { describe, expect, it } from '@ohos/hypium';
import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { DialogWindowHelper, WindowSizeChangeCallback } from '../../../../main/ets/common/utils/DialogWindowHelper';

class InvalidUIContext extends UIContext {
  getHostContext(): common.Context | undefined {
    return undefined;
  }
}

export default function DialogWindowHelperTest() {
  describe('DialogWindowHelper', () => {
    // ---------------- windowWidth getter ----------------
    it('windowWidth defaults to 0', 0, () => {
      const helper = new DialogWindowHelper();
      expect(helper.windowWidth).assertEqual(0);
    });

    // ---------------- register with invalid context ----------------
    // The host context of a non-UI UIContext cannot provide a window stage:
    // the internal try-catch must swallow it and return false.
    it('register with invalid UIContext returns false', 0, () => {
      const helper = new DialogWindowHelper();
      const callback: WindowSizeChangeCallback = (width: number, height: number): void => {
      };
      const ctx: UIContext = new InvalidUIContext();
      const result = helper.register(ctx, callback);
      expect(result).assertFalse();
      expect(helper.windowWidth).assertEqual(0);
    });

    // ---------------- unregister ----------------
    it('unregister before register is a no-op', 0, () => {
      const helper = new DialogWindowHelper();
      let noThrow = true;
      try {
        helper.unregister();
      } catch {
        noThrow = false;
      }
      expect(noThrow).assertTrue();
      expect(helper.windowWidth).assertEqual(0);
    });

    it('unregister resets window width after failed registration', 0, () => {
      const helper = new DialogWindowHelper();
      const callback: WindowSizeChangeCallback = (width: number, height: number): void => {
      };
      const ctx: UIContext = new InvalidUIContext();
      helper.register(ctx, callback);
      helper.unregister();
      expect(helper.windowWidth).assertEqual(0);
    });

    // NOTE: register against a real window (size change callbacks) requires a
    // live window stage and is covered by UI automation tests.
  });
}
