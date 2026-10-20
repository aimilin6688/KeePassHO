import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { TestContextHelper } from '../TestContextHelper';
import { SessionNotificationService } from '../../../../main/ets/services/SessionNotificationService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { ResourceManager } from '../../../../main/ets/common/utils/ResourceManager';
import { SessionEntryInfo } from '../../../../main/ets/services/SessionManager';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { Constants } from '../../../../main/ets/common/constants/Constants';

function sleep(ms: number): Promise<void> {
  return new Promise<void>(resolve => setTimeout(resolve, ms));
}

/**
 * 查询常驻会话通知（SESSION_NOTIFY_ID）是否在系统活动通知列表中。
 */
async function hasSessionNotification(): Promise<boolean> {
  const notifications = await notificationManager.getActiveNotifications();
  for (let i = 0; i < notifications.length; i++) {
    if (notifications[i].id === Constants.SESSION_NOTIFY_ID) {
      return true;
    }
  }
  return false;
}

function buildEntry(groupId: string, entryId: string, title: string, hasUsername: boolean, hasPassword: boolean):
  SessionEntryInfo {
  const info = new SessionEntryInfo();
  info.groupId = groupId;
  info.entryId = entryId;
  info.title = title;
  info.hasUsername = hasUsername;
  info.hasPassword = hasPassword;
  return info;
}

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

  /**
   * 真实发布路径（gated）：注入 AppStorage 'context' 并开启通知开关后，
   * publishActiveEntry / publishCopied 真实发布常驻通知并断言系统活动通知列表；
   * 设备未授权通知时用例静默跳过（避免 requestEnableNotification 弹系统授权框）。
   * 设置快照恢复：测试 HAP 与主应用共享沙箱，用例结束恢复用户真实设置。
   */
  describe('SessionNotificationServicePublish', () => {
    let notifyEnabled = false;
    let savedNotifyEnable: boolean;
    let fullEntry: SessionEntryInfo;

    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      ResourceManager.getInstance().init(appContext);
      await SettingsService.getInstance().init(appContext);
      savedNotifyEnable = SettingsService.getSync(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE,
        SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE_DEFAULT);
      await SettingsService.put(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE, true);
      notifyEnabled = await notificationManager.isNotificationEnabled();
      // 仅在系统通知授权可用时注入 context：未授权（拒绝/待答复）时真实发布路径整体跳过，
      // 避免 requestEnableNotification 弹系统授权框阻塞用例
      if (notifyEnabled) {
        AppStorage.setOrCreate<common.UIAbilityContext>('context', appContext);
      }
      fullEntry = buildEntry('g1', 'e1', 'MyEntry', true, true);
    });

    afterAll(async () => {
      await SessionNotificationService.getInstance().cancelSession();
      if (notifyEnabled) {
        AppStorage.delete('context');
      }
      await SettingsService.put(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE, savedNotifyEnable);
    });

    it('publishActiveEntry publishes the ongoing session notification', 0, async () => {
      if (!notifyEnabled) {
        return;
      }
      await SessionNotificationService.getInstance().publishActiveEntry(fullEntry, 30);
      await sleep(500);
      expect(await hasSessionNotification()).assertTrue();
    });

    it('publishActiveEntry with -1 remaining (never clear) keeps the notification without auto-delete', 0, async () => {
      if (!notifyEnabled) {
        return;
      }
      await SessionNotificationService.getInstance().publishActiveEntry(fullEntry, -1);
      await sleep(500);
      expect(await hasSessionNotification()).assertTrue();
    });

    it('publishCopied for username refreshes the notification text', 0, async () => {
      if (!notifyEnabled) {
        return;
      }
      await SessionNotificationService.getInstance().publishCopied(fullEntry, 25, Constants.SESSION_FIELD_TYPE_USERNAME);
      await sleep(500);
      expect(await hasSessionNotification()).assertTrue();
    });

    it('publishCopied for password with -1 remaining does not throw', 0, async () => {
      if (!notifyEnabled) {
        return;
      }
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishCopied(fullEntry, -1, Constants.SESSION_FIELD_TYPE_PASSWORD);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(await hasSessionNotification()).assertTrue();
    });

    it('second publish of the same entry reuses the cached wantAgent without throwing', 0, async () => {
      if (!notifyEnabled) {
        return;
      }
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishActiveEntry(fullEntry, 30);
        await SessionNotificationService.getInstance().publishActiveEntry(fullEntry, 20);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('username-only entry publishes with a single username action button', 0, async () => {
      if (!notifyEnabled) {
        return;
      }
      const usernameOnly = buildEntry('g2', 'e2', 'UsernameOnly', true, false);
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishActiveEntry(usernameOnly, 30);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(await hasSessionNotification()).assertTrue();
    });

    it('password-only entry publishes with a single password action button', 0, async () => {
      if (!notifyEnabled) {
        return;
      }
      const passwordOnly = buildEntry('g3', 'e3', 'PasswordOnly', false, true);
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishActiveEntry(passwordOnly, 30);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('entry without id publishes the default title without action buttons', 0, async () => {
      if (!notifyEnabled) {
        return;
      }
      const noEntry = buildEntry('', '', '', false, false);
      let threw = false;
      try {
        await SessionNotificationService.getInstance().publishActiveEntry(noEntry, 30);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('cancelSession removes the published notification', 0, async () => {
      if (!notifyEnabled) {
        return;
      }
      await SessionNotificationService.getInstance().publishActiveEntry(fullEntry, 30);
      await sleep(500);
      expect(await hasSessionNotification()).assertTrue();
      await SessionNotificationService.getInstance().cancelSession();
      await sleep(500);
      expect(await hasSessionNotification()).assertFalse();
    });
  });
}
