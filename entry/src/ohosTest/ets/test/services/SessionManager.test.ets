import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { SessionManager, SessionEntryInfo } from '../../../../main/ets/services/SessionManager';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { Constants } from '../../../../main/ets/common/constants/Constants';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { EventBus } from '../../../../main/ets/services/EventBus';
import { LockScreenService } from '../../../../main/ets/services/LockScreenService';

function sleep(ms: number): Promise<void> {
  return new Promise<void>(resolve => setTimeout(resolve, ms));
}

/**
 * 轮询等待条件成立（emitter 投递为异步）。
 */
async function waitFor(cond: () => boolean, timeoutMs: number = 2000): Promise<boolean> {
  const deadline: number = Date.now() + timeoutMs;
  while (!cond() && Date.now() < deadline) {
    await sleep(20);
  }
  return cond();
}

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

  /**
   * 会话生命周期：unlock/lock/EVENT_LOCK_SCREEN 事件驱动、通知窗口倒计时、
   * -1 永不清除、窗口到期会话保持、切条目与复制态重置。
   * 设置快照恢复：测试 HAP 与主应用共享沙箱，用例结束恢复用户真实设置。
   */
  describe('SessionManagerActiveSession', () => {
    let savedClearTime: number;

    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
      savedClearTime = SettingsService.getSync(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME,
        SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT);
    });

    afterEach(() => {
      SessionManager.getInstance().destroy();
    });

    afterAll(async () => {
      SessionManager.getInstance().destroy();
      await SettingsService.put(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, savedClearTime);
    });

    it('unlock event starts the session and sets the AppStorage active flag', 0, async () => {
      SessionManager.getInstance().init();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      const started = await waitFor(() => SessionManager.getInstance().isActive());
      expect(started).assertTrue();
      expect(AppStorage.get<boolean>(Constants.APP_STORAGE_SESSION_ACTIVE)).assertTrue();
    });

    it('lock event ends the session and clears the AppStorage flag', 0, async () => {
      SessionManager.getInstance().init();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'lock');
      const ended = await waitFor(() => !SessionManager.getInstance().isActive());
      expect(ended).assertTrue();
      expect(AppStorage.get<boolean>(Constants.APP_STORAGE_SESSION_ACTIVE)).assertFalse();
    });

    it('EVENT_LOCK_SCREEN ends an active session', 0, async () => {
      SessionManager.getInstance().init();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_SCREEN);
      const ended = await waitFor(() => !SessionManager.getInstance().isActive());
      expect(ended).assertTrue();
    });

    it('non-string lock action payloads are ignored', 0, async () => {
      SessionManager.getInstance().init();
      EventBus.emit<number>(LockScreenService.EVENT_LOCK_ACTION, 42);
      await sleep(300);
      expect(SessionManager.getInstance().isActive()).assertFalse();
    });

    it('unknown string action also ends the session', 0, async () => {
      SessionManager.getInstance().init();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'something-else');
      const ended = await waitFor(() => !SessionManager.getInstance().isActive());
      expect(ended).assertTrue();
    });

    it('onCopied during an active session resets the window without throwing', 0, async () => {
      await SettingsService.put(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, 60);
      SessionManager.getInstance().init();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      const remaining = SessionManager.getInstance().getRemainingSec();
      expect(remaining > 50 && remaining <= 60).assertTrue();
      let threw = false;
      try {
        SessionManager.getInstance().onCopied(Constants.SESSION_FIELD_TYPE_USERNAME);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(SessionManager.getInstance().isActive()).assertTrue();
    });

    it('getRemainingSec returns -1 when auto-clear is disabled (-1)', 0, async () => {
      await SettingsService.put(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, -1);
      SessionManager.getInstance().init();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      expect(SessionManager.getInstance().getRemainingSec()).assertEqual(-1);
    });

    it('window expiry cancels the window but keeps the session alive', 0, async () => {
      await SettingsService.put(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, 1);
      SessionManager.getInstance().init();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      // 窗口 1 秒、倒计时 tick 5 秒：首个 tick 即到期并取消通知
      await sleep(6200);
      expect(SessionManager.getInstance().getRemainingSec()).assertEqual(0);
      expect(SessionManager.getInstance().isActive()).assertTrue();
    });

    it('setActiveEntry during an active session updates entry info and stays active', 0, async () => {
      SessionManager.getInstance().init();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      SessionManager.getInstance().setActiveEntry('gA', 'eA', 'Active Entry', true, false);
      const info = SessionManager.getInstance().getEntryInfo();
      expect(info.groupId).assertEqual('gA');
      expect(info.entryId).assertEqual('eA');
      expect(info.title).assertEqual('Active Entry');
      expect(info.hasUsername).assertTrue();
      expect(info.hasPassword).assertFalse();
      expect(SessionManager.getInstance().isActive()).assertTrue();
    });

    it('refreshNotification(true/false) during an active session do not throw', 0, async () => {
      SessionManager.getInstance().init();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      let threw = false;
      try {
        SessionManager.getInstance().refreshNotification(true);
        SessionManager.getInstance().refreshNotification(false);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(SessionManager.getInstance().isActive()).assertTrue();
    });

    it('onAppBackground/onAppForeground during an active session do not throw', 0, async () => {
      SessionManager.getInstance().init();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      let threw = false;
      try {
        SessionManager.getInstance().onAppBackground();
        SessionManager.getInstance().onAppForeground();
        SessionManager.getInstance().onAppForeground();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });
  });
}
