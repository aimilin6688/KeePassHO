import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { SessionManager, SessionEntryInfo } from '../../../../main/ets/services/SessionManager';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { Constants } from '../../../../main/ets/common/constants/Constants';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

export default function SessionManagerTest() {
  describe('SessionManager', () => {
    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    beforeEach(() => {
    });

    afterEach(() => {
      SessionManager.getInstance().destroy();
    });

    afterAll(() => {
      SessionManager.getInstance().destroy();
    });

    it('getInstance returns the singleton instance', 0, () => {
      const a = SessionManager.getInstance();
      const b = SessionManager.getInstance();
      expect(a === b).assertTrue();
    });

    it('isActive is false initially', 0, () => {
      expect(SessionManager.getInstance().isActive()).assertFalse();
    });

    it('getEntryInfo returns a SessionEntryInfo instance with default empty fields', 0, () => {
      const info = SessionManager.getInstance().getEntryInfo();
      expect(info instanceof SessionEntryInfo).assertTrue();
      expect(info.groupId).assertEqual('');
      expect(info.entryId).assertEqual('');
      expect(info.title).assertEqual('');
      expect(info.hasUsername).assertFalse();
      expect(info.hasPassword).assertFalse();
    });

    it('getRemainingSec returns 0 when windowStart is zero (initial state)', 0, () => {
      const v = SessionManager.getInstance().getRemainingSec();
      expect(v).assertEqual(0);
    });

    it('onCopied is a no-op when session inactive (does not throw)', 0, () => {
      let threw = false;
      try {
        SessionManager.getInstance().onCopied('USERNAME');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(SessionManager.getInstance().isActive()).assertFalse();
    });

    it('refreshNotification(false) does not throw when inactive', 0, () => {
      let threw = false;
      try {
        SessionManager.getInstance().refreshNotification(false);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('refreshNotification(true) does not throw when inactive', 0, () => {
      let threw = false;
      try {
        SessionManager.getInstance().refreshNotification(true);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('setActiveEntry updates entry info even when inactive, without starting session', 0, () => {
      SessionManager.getInstance().setActiveEntry('g1', 'e1', 'My Entry', true, false);
      const info = SessionManager.getInstance().getEntryInfo();
      expect(info.groupId).assertEqual('g1');
      expect(info.entryId).assertEqual('e1');
      expect(info.title).assertEqual('My Entry');
      expect(info.hasUsername).assertTrue();
      expect(info.hasPassword).assertFalse();
      expect(SessionManager.getInstance().isActive()).assertFalse();
    });

    it('onAppBackground is a no-op when inactive', 0, () => {
      let threw = false;
      try {
        SessionManager.getInstance().onAppBackground();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onAppForeground is a no-op (no suspend request to release)', 0, () => {
      let threw = false;
      try {
        SessionManager.getInstance().onAppForeground();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('onNotificationRemoved clears AppStorage session flag and does not throw', 0, () => {
      AppStorage.setOrCreate<boolean>(Constants.APP_STORAGE_SESSION_ACTIVE, true);
      let threw = false;
      try {
        SessionManager.getInstance().onNotificationRemoved();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(AppStorage.get<boolean>(Constants.APP_STORAGE_SESSION_ACTIVE)).assertFalse();
    });

    it('init registers EventBus listeners without throwing', 0, () => {
      let threw = false;
      try {
        SessionManager.getInstance().init();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('destroy cleans up without throwing and leaves session inactive', 0, () => {
      SessionManager.getInstance().init();
      let threw = false;
      try {
        SessionManager.getInstance().destroy();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(SessionManager.getInstance().isActive()).assertFalse();
    });
  });
}
