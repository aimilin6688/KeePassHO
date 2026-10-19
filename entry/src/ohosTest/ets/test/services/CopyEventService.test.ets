import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { commonEventManager } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { TestContextHelper } from '../TestContextHelper';
import { CopyEventService } from '../../../../main/ets/services/CopyEventService';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { Constants } from '../../../../main/ets/common/constants/Constants';
import { EventBus } from '../../../../main/ets/services/EventBus';
import { LockScreenService } from '../../../../main/ets/services/LockScreenService';
import { SessionManager } from '../../../../main/ets/services/SessionManager';
import { SessionNotificationService } from '../../../../main/ets/services/SessionNotificationService';
import { FileService } from '../../../../main/ets/services/FileService';
import { AuthType, DbFileParam } from '../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../main/ets/storage';

function sleep(ms: number): Promise<void> {
  return new Promise<void>(resolve => setTimeout(resolve, ms));
}

/**
 * 轮询等待条件成立（emitter / 公共事件投递均为异步）。
 */
async function waitFor(cond: () => boolean, timeoutMs: number = 2000): Promise<boolean> {
  const deadline: number = Date.now() + timeoutMs;
  while (!cond() && Date.now() < deadline) {
    await sleep(20);
  }
  return cond();
}

/**
 * 发布公共事件（callback 转 Promise）。事件名作为 publish 的首参，
 * CommonEventPublishData 仅承载 parameters 等可选字段。
 */
function publishCommonEventData(event: string, publishData: commonEventManager.CommonEventPublishData): Promise<void> {
  return new Promise<void>((resolve, reject) => {
    commonEventManager.publish(event, publishData, (err) => {
      if (err) {
        reject(new Error(`publish failed: ${err.code} ${err.message}`));
        return;
      }
      resolve();
    });
  });
}

function buildPublishData(parameters?: Record<string, Object>): commonEventManager.CommonEventPublishData {
  const publishData: commonEventManager.CommonEventPublishData = {};
  if (parameters !== undefined) {
    publishData.parameters = parameters;
  }
  return publishData;
}

/**
 * 轮询等待异步条件成立（通知栏状态查询等异步断言）。
 */
async function waitForAsync(cond: () => Promise<boolean>, timeoutMs: number = 2000): Promise<boolean> {
  const deadline: number = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    if (await cond()) {
      return true;
    }
    await sleep(50);
  }
  return await cond();
}

/**
 * 会话常驻通知是否存在于通知栏。
 * 注：HarmonyOS NEXT 粘贴板服务对无用户手势的读取返回空数据（PBS 权限校验拒绝，
 * READ_PASTEBOARD 为系统权限），测试进程无法回读剪贴板内容；
 * 复制链路改用会话窗口重置与通知状态作为可观测信号。
 */
async function hasSessionNotification(): Promise<boolean> {
  try {
    const notifications = await notificationManager.getActiveNotifications();
    for (const request of notifications) {
      if (request.id === Constants.SESSION_NOTIFY_ID) {
        return true;
      }
    }
    return false;
  } catch (e) {
    return false;
  }
}

export default function CopyEventServiceTest() {
  describe('CopyEventService', () => {
    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    beforeEach(() => {
    });

    afterEach(() => {
      CopyEventService.getInstance().destroy();
    });

    afterAll(() => {
      CopyEventService.getInstance().destroy();
    });

    it('getInstance returns the singleton instance', 0, () => {
      const a = CopyEventService.getInstance();
      const b = CopyEventService.getInstance();
      expect(a === b).assertTrue();
    });

    it('destroy before init is a no-op without throwing', 0, () => {
      let threw = false;
      try {
        CopyEventService.getInstance().destroy();
        CopyEventService.getInstance().destroy();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('init subscribes to copy field events without throwing', 0, async () => {
      let threw = false;
      try {
        await CopyEventService.getInstance().init();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('calling init twice is idempotent (second call returns early)', 0, async () => {
      await CopyEventService.getInstance().init();
      let threw = false;
      try {
        await CopyEventService.getInstance().init();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('destroy after init clears the subscriber (idempotent re-destroy)', 0, async () => {
      await CopyEventService.getInstance().init();
      let threw = false;
      try {
        CopyEventService.getInstance().destroy();
        CopyEventService.getInstance().destroy();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('init can be called again after destroy', 0, async () => {
      await CopyEventService.getInstance().init();
      CopyEventService.getInstance().destroy();
      let threw = false;
      try {
        await CopyEventService.getInstance().init();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });
  });

  /**
   * 通知按钮公共事件端到端路径：真实 KDBX 数据库 + 真实解锁会话 + 真实公共事件发布。
   * HarmonyOS NEXT 粘贴板服务对无用户手势的读取返回空数据（PBS GetPasteDataInner 权限校验
   * 拒绝，READ_PASTEBOARD 为系统权限），测试进程无法回读剪贴板内容，改用可观测信号：
   * - 成功复制链路终点为 SessionManager.onCopied → restartWindow，getRemainingSec
   *   从衰减值跳回窗口全长（临时把自动清理设置置 60 秒使窗口可观测）；
   * - 负向用例断言窗口持续衰减未被重置；
   * - 会话未激活分支断言残留通知被 cancelSession 移除（通知授权可用时）。
   * 设置快照恢复，afterEach 锁定会话，结束清理注册表与订阅。
   */
  describe('CopyEventServiceEvents', () => {
    let groupId: string;
    let entryId: string;
    let savedClearTime: number;
    let savedNotifyEnabled: boolean;
    let notifyEnabled: boolean;

    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
      // 正数窗口（60 秒）使 restartWindow 的重置可通过 getRemainingSec 观测
      savedClearTime = SettingsService.getSync(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME,
        SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT);
      await SettingsService.put(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, 60);
      savedNotifyEnabled = SettingsService.getSync(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE,
        SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE_DEFAULT);
      await SettingsService.put(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE, true);
      notifyEnabled = await notificationManager.isNotificationEnabled();
      if (notifyEnabled) {
        AppStorage.setOrCreate<common.UIAbilityContext>('context', appContext);
      }

      // 真实加密数据库 + 真实条目（UserName / Password 供复制链路取值）
      const credentials = new KdbxCredentials(ProtectedValue.fromString('CopyEvent-Test-123'));
      const database = Kdbx.create(credentials, 'CopyEventDb');
      const entry = database.createEntry(database.getDefaultGroup());
      entry.fields.set('Title', 'CopiedEntry');
      entry.fields.set('UserName', 'user@example.com');
      entry.fields.set('Password', 's3cret-pass');
      groupId = database.getDefaultGroup().uuid.id;
      entryId = entry.uuid.id;

      const param: DbFileParam = {
        filePath: '/data/test/copy-event.kdbx',
        fileName: 'copy-event.kdbx',
        password: '',
        database: database,
        authType: AuthType.PASSWORD,
        storageType: StorageType.LOCAL,
        storageConfig: {},
        modifiedTime: 0
      };
      FileService.setDbFileParam(param);

      SessionManager.getInstance().init();
      await CopyEventService.getInstance().init();
    });

    afterEach(() => {
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'lock');
    });

    afterAll(async () => {
      SessionManager.getInstance().destroy();
      CopyEventService.getInstance().destroy();
      FileService.init();
      if (notifyEnabled) {
        AppStorage.delete('context');
      }
      await SettingsService.put(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME, savedClearTime);
      await SettingsService.put(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE, savedNotifyEnabled);
    });

    it('NOTIFY_REMOVED clears the session-active AppStorage flag', 0, async () => {
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      expect(AppStorage.get<boolean>(Constants.APP_STORAGE_SESSION_ACTIVE)).assertTrue();
      await publishCommonEventData(Constants.SESSION_ACTION_NOTIFY_REMOVED, buildPublishData());
      const cleared = await waitFor(() => AppStorage.get<boolean>(Constants.APP_STORAGE_SESSION_ACTIVE) === false);
      expect(cleared).assertTrue();
    });

    it('COPY_FIELD copies the entry username to the clipboard', 0, async () => {
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      await sleep(3100);
      const before = SessionManager.getInstance().getRemainingSec();
      const params: Record<string, Object> = {
        'groupId': groupId,
        'entryId': entryId,
        'fieldType': Constants.SESSION_FIELD_TYPE_USERNAME
      };
      await publishCommonEventData(Constants.SESSION_ACTION_COPY_FIELD, buildPublishData(params));
      // 成功复制触发 onCopied → restartWindow：剩余秒数从衰减值跳回窗口全长
      const reset = await waitFor(() => SessionManager.getInstance().getRemainingSec() > before, 6000);
      expect(reset).assertTrue();
    });

    it('COPY_FIELD copies the entry password to the clipboard', 0, async () => {
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      await sleep(3100);
      const before = SessionManager.getInstance().getRemainingSec();
      const params: Record<string, Object> = {
        'groupId': groupId,
        'entryId': entryId,
        'fieldType': Constants.SESSION_FIELD_TYPE_PASSWORD
      };
      await publishCommonEventData(Constants.SESSION_ACTION_COPY_FIELD, buildPublishData(params));
      const reset = await waitFor(() => SessionManager.getInstance().getRemainingSec() > before, 6000);
      expect(reset).assertTrue();
    });

    it('COPY_FIELD with non-string parameters is ignored', 0, async () => {
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      await sleep(3100);
      const before = SessionManager.getInstance().getRemainingSec();
      const badParams: Record<string, Object> = {
        'groupId': groupId,
        'entryId': entryId,
        'fieldType': 12345
      };
      await publishCommonEventData(Constants.SESSION_ACTION_COPY_FIELD, buildPublishData(badParams));
      await sleep(3000);
      // 参数被拒绝：窗口未重置，剩余秒数持续衰减
      expect(SessionManager.getInstance().getRemainingSec() < before).assertTrue();
    });

    it('COPY_FIELD without parameters is ignored', 0, async () => {
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      await sleep(3100);
      const before = SessionManager.getInstance().getRemainingSec();
      await publishCommonEventData(Constants.SESSION_ACTION_COPY_FIELD, buildPublishData());
      await sleep(3000);
      expect(SessionManager.getInstance().getRemainingSec() < before).assertTrue();
    });

    it('COPY_FIELD for a missing entry does not copy', 0, async () => {
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      await sleep(3100);
      const before = SessionManager.getInstance().getRemainingSec();
      const params: Record<string, Object> = {
        'groupId': groupId,
        'entryId': 'no-such-entry-id',
        'fieldType': Constants.SESSION_FIELD_TYPE_USERNAME
      };
      await publishCommonEventData(Constants.SESSION_ACTION_COPY_FIELD, buildPublishData(params));
      await sleep(3000);
      expect(SessionManager.getInstance().getRemainingSec() < before).assertTrue();
    });

    it('COPY_FIELD while the session is inactive removes the residual notification', 0, async () => {
      // 未 unlock：会话未激活，copyField 走残留通知清理分支（cancelSession）
      SessionNotificationService.getInstance()
        .publishActiveEntry(SessionManager.getInstance().getEntryInfo(), 30);
      if (notifyEnabled) {
        const shown = await waitForAsync(() => hasSessionNotification(), 5000);
        expect(shown).assertTrue();
      }
      const params: Record<string, Object> = {
        'groupId': groupId,
        'entryId': entryId,
        'fieldType': Constants.SESSION_FIELD_TYPE_USERNAME
      };
      await publishCommonEventData(Constants.SESSION_ACTION_COPY_FIELD, buildPublishData(params));
      if (notifyEnabled) {
        const removed = await waitForAsync(async () => !(await hasSessionNotification()), 5000);
        expect(removed).assertTrue();
      }
      expect(SessionManager.getInstance().isActive()).assertFalse();
    });

    it('destroy stops common event handling', 0, async () => {
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await waitFor(() => SessionManager.getInstance().isActive());
      await sleep(3100);
      const before = SessionManager.getInstance().getRemainingSec();
      CopyEventService.getInstance().destroy();
      const params: Record<string, Object> = {
        'groupId': groupId,
        'entryId': entryId,
        'fieldType': Constants.SESSION_FIELD_TYPE_USERNAME
      };
      await publishCommonEventData(Constants.SESSION_ACTION_COPY_FIELD, buildPublishData(params));
      await sleep(3000);
      expect(SessionManager.getInstance().getRemainingSec() < before).assertTrue();
    });
  });
}
