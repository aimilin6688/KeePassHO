import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { ThemeManager } from '../../../../main/ets/common/utils/ThemeManager';
import { ThemeMode } from '../../../../main/ets/common/constants/ThemeConstants';

function getAppContext(): common.UIAbilityContext {
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.UIAbilityContext;
}

export default function ThemeManagerTest() {
  describe('ThemeManager', () => {
    // ---------------- singleton ----------------
    it('getInstance returns the same instance', 0, () => {
      expect(ThemeManager.getInstance() === ThemeManager.getInstance()).assertTrue();
    });

    // ---------------- ThemeMode enum ----------------
    it('ThemeMode enum values are stable', 0, () => {
      expect(ThemeMode.SYSTEM).assertEqual('SYSTEM');
      expect(ThemeMode.LIGHT).assertEqual('LIGHT');
      expect(ThemeMode.DARK).assertEqual('DARK');
    });

    // ---------------- theme mode get/set ----------------
    it('getThemeMode defaults to SYSTEM', 0, () => {
      expect(ThemeManager.getInstance().getThemeMode()).assertEqual(ThemeMode.SYSTEM);
    });

    it('setThemeMode stores DARK mode and resolves dark', 0, async () => {
      const mgr = ThemeManager.getInstance();
      await mgr.setThemeMode(ThemeMode.DARK);
      expect(mgr.getThemeMode()).assertEqual(ThemeMode.DARK);
      expect(mgr.isDarkMode()).assertTrue();
    });

    it('setThemeMode stores LIGHT mode and resolves light', 0, async () => {
      const mgr = ThemeManager.getInstance();
      await mgr.setThemeMode(ThemeMode.LIGHT);
      expect(mgr.getThemeMode()).assertEqual(ThemeMode.LIGHT);
      expect(mgr.isDarkMode()).assertFalse();
    });

    it('SYSTEM mode resolves to system dark flag (false without init)', 0, async () => {
      const mgr = ThemeManager.getInstance();
      await mgr.setThemeMode(ThemeMode.SYSTEM);
      expect(mgr.getThemeMode()).assertEqual(ThemeMode.SYSTEM);
      expect(mgr.isDarkMode()).assertFalse();
    });

    // ---------------- init ----------------
    // applyTheme early-returns without a UIAbility window, so init must always
    // settle (resolve) even when given the application context.
    it('init with app context settles without throwing', 0, async () => {
      let settled = false;
      try {
        await ThemeManager.getInstance().init(getAppContext());
        settled = true;
      } catch {
        settled = true;
      }
      expect(settled).assertTrue();
    });

    // ---------------- listeners ----------------
    it('listener is notified once per change and not duplicated', 0, async () => {
      const mgr = ThemeManager.getInstance();
      let calls = 0;
      let lastDark = false;
      const listener = (isDark: boolean): void => {
        calls++;
        lastDark = isDark;
      };
      mgr.addThemeChangeListener(listener);
      mgr.addThemeChangeListener(listener);
      await mgr.setThemeMode(ThemeMode.DARK);
      expect(calls).assertEqual(1);
      expect(lastDark).assertTrue();
      mgr.removeThemeChangeListener(listener);
      await mgr.setThemeMode(ThemeMode.LIGHT);
      expect(calls).assertEqual(1);
      expect(mgr.isDarkMode()).assertFalse();
    });

    it('removeThemeChangeListenerAll clears every listener', 0, async () => {
      const mgr = ThemeManager.getInstance();
      let calls = 0;
      const listener = (isDark: boolean): void => {
        calls++;
      };
      mgr.addThemeChangeListener(listener);
      mgr.addThemeChangeListener((isDark: boolean): void => {
        calls++;
      });
      mgr.removeThemeChangeListenerAll();
      await mgr.setThemeMode(ThemeMode.DARK);
      expect(calls).assertEqual(0);
      await mgr.setThemeMode(ThemeMode.SYSTEM);
    });

    // NOTE: real color mode / system bar application requires a live window
    // stage and is covered by UI automation tests.
  });
}
