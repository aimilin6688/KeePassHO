import { describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { WindowUtils } from '../../../../main/ets/common/utils/WindowUtils';
import { SettingsService } from '../../../../main/ets/services/SettingsService';

function getAppContext(): common.UIAbilityContext {
  return abilityDelegatorRegistry.getAbilityDelegator().getAppContext() as common.UIAbilityContext;
}

export default function WindowUtilsTest() {
  describe('WindowUtils', () => {
    // ---------------- setWindowPrivacyModeInPage ----------------
    // The method internally catches sync errors and attaches .catch to all
    // promises, so calling it with a non-window context must never throw.
    it('setWindowPrivacyModeInPage no-throw when enabling privacy mode', 0, () => {
      let noThrow = true;
      try {
        WindowUtils.setWindowPrivacyModeInPage(getAppContext(), true);
      } catch {
        noThrow = false;
      }
      expect(noThrow).assertTrue();
    });

    it('setWindowPrivacyModeInPage no-throw when disabling privacy mode', 0, () => {
      let noThrow = true;
      try {
        WindowUtils.setWindowPrivacyModeInPage(getAppContext(), false);
      } catch {
        noThrow = false;
      }
      expect(noThrow).assertTrue();
    });

    // ---------------- onPageShow ----------------
    it('onPageShow no-throw (reads privacy setting async)', 0, () => {
      let noThrow = true;
      try {
        WindowUtils.onPageShow(getAppContext());
      } catch {
        noThrow = false;
      }
      expect(noThrow).assertTrue();
    });

    // ---------------- privacy setting constants ----------------
    it('privacy window setting key and default are configured', 0, () => {
      expect(SettingsService.KEY_SECURITY_PRIVACY_WINDOW).assertEqual('Security_privacy_window');
      expect(SettingsService.KEY_SECURITY_PRIVACY_WINDOW_DEFAULT).assertTrue();
    });

    // NOTE: real window privacy mode changes require a live window stage and
    // are covered by UI automation tests instead.
  });
}
