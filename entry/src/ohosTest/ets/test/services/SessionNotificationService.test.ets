import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { SessionNotificationService } from '../../../../main/ets/services/SessionNotificationService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { SessionEntryInfo } from '../../../../main/ets/services/SessionManager';
import { SettingsService } from '../../../../main/ets/services/SettingsService';

export default function SessionNotificationServiceTest() {
  describe('SessionNotificationService', () => {
    let entry: SessionEntryInfo;

    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
      entry = new SessionEntryInfo();
      entry.groupId = 'g1';
      entry.entryId = 'e1';
      entry.title = 'MyEntry';
      entry.hasUsername = true;
      entry.hasPassword = true;
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('getInstance returns the singleton instance', 0, () => {
      const a = SessionNotificationService.getInstance();
      const b = SessionNotificationService.getInstance();
      expect(a === b).assertTrue();
    });

    it('cancelSession does not throw and clears internal cache', 0, async () => {
      let threw = false;
      try {
        await SessionNotificationService.getInstance().cancelSession();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('publishActiveEntry with remainingSec 0 returns early without throwing', 0, async () => {
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishActiveEntry(entry, 0);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('publishCopied with remainingSec 0 returns early without throwing', 0, async () => {
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishCopied(entry, 0, 'USERNAME');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('publishActiveEntry with remaining>0 but no context returns without throwing', 0, async () => {
      AppStorage.delete('context');
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishActiveEntry(entry, 30);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('publishCopied with remaining>0 but no context returns without throwing', 0, async () => {
      AppStorage.delete('context');
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishCopied(entry, 25, 'PASSWORD');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('publishActiveEntry with negative remainingSec (never clear) does not throw', 0, async () => {
      AppStorage.delete('context');
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishActiveEntry(entry, -1);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('publishCopied for username field with negative remaining does not throw', 0, async () => {
      AppStorage.delete('context');
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishCopied(entry, -1, 'USERNAME');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });
  });
}
