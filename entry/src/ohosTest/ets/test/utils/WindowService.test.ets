import { describe, expect, it } from '@ohos/hypium';
import { UIContext } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { WindowInfo, WindowService } from '../../../../main/ets/common/utils/WindowService';
import { NavigationConstants } from '../../../../main/ets/common/constants/NavigationConstants';

class FakeUIContext extends UIContext {
  px2vp(value: number): number {
    return value / 3;
  }
}

function getAppContext(): common.UIAbilityContext {
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.UIAbilityContext;
}

export default function WindowServiceTest() {
  describe('WindowService', () => {
    // ---------------- singleton ----------------
    it('getInstance returns the same instance', 0, () => {
      expect(WindowService.getInstance() === WindowService.getInstance()).assertTrue();
    });

    // ---------------- WindowInfo defaults ----------------
    it('WindowInfo has zero size and SM/MD breakpoints by default', 0, () => {
      const info: WindowInfo = new WindowInfo();
      expect(info.windowWidthVp).assertEqual(0);
      expect(info.windowHeightVp).assertEqual(0);
      expect(info.widthBp === WidthBreakpoint.WIDTH_SM).assertTrue();
      expect(info.heightBp === HeightBreakpoint.HEIGHT_MD).assertTrue();
      expect(info.isSplitMode).assertFalse();
    });

    it('WindowService exposes a WindowInfo instance', 0, () => {
      expect(WindowService.getInstance().info instanceof WindowInfo).assertTrue();
    });

    // ---------------- refresh without init ----------------
    it('refresh without init is a no-op and keeps defaults', 0, () => {
      const service = WindowService.getInstance();
      let noThrow = true;
      try {
        service.refresh();
      } catch {
        noThrow = false;
      }
      expect(noThrow).assertTrue();
      expect(service.info.windowWidthVp).assertEqual(0);
      expect(service.info.isSplitMode).assertFalse();
    });

    // ---------------- init with non-window context ----------------
    // The app (application) context has no windowStage: getMainWindowSync()
    // throws and is caught internally, so init must never throw and the
    // WindowInfo stays at defaults (refresh early-returns without a window).
    it('init with invalid context does not throw and keeps defaults', 0, () => {
      const service = WindowService.getInstance();
      const fake: UIContext = new FakeUIContext();
      let noThrow = true;
      try {
        service.init(getAppContext(), fake);
      } catch {
        noThrow = false;
      }
      expect(noThrow).assertTrue();
      expect(service.info.windowWidthVp).assertEqual(0);
    });

    // ---------------- split mode thresholds (constants used by _resolveSplitMode) ----------------
    it('SPLIT_MODE_THRESHOLD equals nav bar default width plus min content width', 0, () => {
      expect(NavigationConstants.SPLIT_MODE_THRESHOLD)
        .assertEqual(NavigationConstants.DEFAULT_NAV_BAR_WIDTH + NavigationConstants.MIN_CONTENT_WIDTH);
      expect(NavigationConstants.SPLIT_MODE_THRESHOLD).assertEqual(760);
    });

    it('SPLIT_ASPECT_RATIO_THRESHOLD is 1.2', 0, () => {
      expect(NavigationConstants.SPLIT_ASPECT_RATIO_THRESHOLD).assertEqual(1.2);
    });

    // NOTE: real windowSizeChange handling and breakpoint mapping require a
    // live window + UIContext and are covered by UI automation tests.
  });
}
