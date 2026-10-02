import { common, wantAgent, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/constants/Constants';
import { ResourceManager } from '../common/utils';
import { SessionEntryInfo } from './SessionManager';
import { SettingsService } from './SettingsService';

const DOMAIN = 0x0000;
const TAG = 'SessionNotificationService';

/**
 * 解锁会话常驻通知服务
 * 解锁后发布常驻通知，按条目字段可用性动态携带 [复制账号][复制密码] 按钮（SEND_COMMON_EVENT wantAgent）：
 * 仅含账号→只显示复制账号，仅含密码→只显示复制密码，两者都有→双按钮；
 * 供用户在其他应用内后台复制凭据；锁库/关库/会话到期时取消
 */
export class SessionNotificationService {
  private static instance: SessionNotificationService = new SessionNotificationService();
  /** wantAgent 缓存键（条目+字段可用性），倒计时刷新时免重建 */
  private cachedAgentKey: string = '';
  private cachedTapAgent: WantAgent | null = null;
  private cachedRemovedAgent: WantAgent | null = null;
  private cachedUsernameAgent: WantAgent | null = null;
  private cachedPasswordAgent: WantAgent | null = null;

  private constructor() {
  }

  public static getInstance(): SessionNotificationService {
    return SessionNotificationService.instance;
  }

  /**
   * 会话通知开关是否开启（所有发布路径统一校验，关闭后解锁/切条目均不再发布）
   */
  private isNotifyEnabled(): boolean {
    return SettingsService.getSync(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE,
      SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE_DEFAULT);
  }

  /**
   * 发布/更新会话通知（绑定当前浏览条目，按条目字段动态显示按钮）
   * @param entryInfo 当前条目信息
   * @param remainingSec 会话剩余秒数（-1 为永不清除；通知 autoDeletedTime 兜底清除）
   */
  public async publishActiveEntry(entryInfo: SessionEntryInfo, remainingSec: number): Promise<void> {
    if (!this.isNotifyEnabled()) {
      return;
    }
    if (remainingSec === 0) {
      return;
    }
    if (!await this.ensurePermission()) {
      return;
    }
    const request = await this.buildRequest(entryInfo, remainingSec, '');
    if (!request) {
      return;
    }
    try {
      await notificationManager.publish(request);
    } catch (error) {
      const e = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'publish failed: %{public}s %{public}s', e.code, e.message);
    }
  }

  /**
   * 复制成功后更新通知文案（如“已复制密码，25秒后自动清除”），由会话定时器周期性调用刷新剩余时间
   */
  public async publishCopied(entryInfo: SessionEntryInfo, remainingSec: number, fieldType: string): Promise<void> {
    if (!this.isNotifyEnabled()) {
      return;
    }
    if (remainingSec === 0) {
      return;
    }
    if (!await this.ensurePermission()) {
      return;
    }
    const request = await this.buildRequest(entryInfo, remainingSec, fieldType);
    if (!request) {
      return;
    }
    try {
      await notificationManager.publish(request);
    } catch (error) {
      const e = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'publish copied notify failed: %{public}s %{public}s', e.code, e.message);
    }
  }

  /**
   * 结束会话通知（锁库/关库/到期/划掉通知场景）
   */
  public async cancelSession(): Promise<void> {
    this.cachedAgentKey = '';
    try {
      await notificationManager.cancel(Constants.SESSION_NOTIFY_ID);
    } catch (error) {
      const e = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'cancel session notify failed: %{public}s %{public}s', e.code, e.message);
    }
  }

  /**
   * 查询并申请通知授权（系统弹窗仅首次出现；用户拒绝后静默降级）
   */
  private async ensurePermission(): Promise<boolean> {
    const context = AppStorage.get<common.UIAbilityContext>('context');
    if (!context) {
      return false;
    }
    try {
      let enabled = await notificationManager.isNotificationEnabled();
      if (!enabled) {
        await notificationManager.requestEnableNotification(context);
        enabled = await notificationManager.isNotificationEnabled();
      }
      return enabled;
    } catch (error) {
      const e = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'ensure notification permission failed: %{public}s %{public}s', e.code, e.message);
      return false;
    }
  }

  /**
   * 构建通知请求：常驻、点击不自动清除、到期系统兜底、按条目字段动态显示按钮、划掉可感知
   */
  private async buildRequest(entryInfo: SessionEntryInfo, remainingSec: number, copiedFieldType: string):
    Promise<notificationManager.NotificationRequest | null> {
    const context = AppStorage.get<common.UIAbilityContext>('context');
    if (!context) {
      return null;
    }
    // 按钮可用性：无绑定条目不显示按钮；仅含账号→复制账号，仅含密码→复制密码，两者都有→双按钮
    const hasUsername = entryInfo.entryId !== '' && entryInfo.hasUsername;
    const hasPassword = entryInfo.entryId !== '' && entryInfo.hasPassword;
    const agentKey = `${entryInfo.groupId}|${entryInfo.entryId}|${hasUsername}|${hasPassword}`;
    try {
      let tapAgent: WantAgent;
      let removedAgent: WantAgent;
      let usernameAgent: WantAgent | null;
      let passwordAgent: WantAgent | null;
      if (agentKey === this.cachedAgentKey && this.cachedTapAgent && this.cachedRemovedAgent) {
        // 倒计时刷新等场景复用缓存的 wantAgent
        tapAgent = this.cachedTapAgent;
        removedAgent = this.cachedRemovedAgent;
        usernameAgent = this.cachedUsernameAgent;
        passwordAgent = this.cachedPasswordAgent;
      } else {
        // 点击通知主体：拉起应用
        const tapAgentInfo: wantAgent.WantAgentInfo = {
          wants: [{
            deviceId: '',
            bundleName: context.abilityInfo.bundleName,
            abilityName: 'EntryAbility',
            action: '',
            entities: [],
            uri: '',
            parameters: {}
          }],
          actionType: wantAgent.OperationType.START_ABILITY,
          requestCode: 0,
          actionFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG]
        };
        tapAgent = await wantAgent.getWantAgent(tapAgentInfo);

        // 用户划掉通知：发布公共事件（removalWantAgent 仅支持公共事件）
        const removedAgentInfo: wantAgent.WantAgentInfo = {
          wants: [{
            action: Constants.SESSION_ACTION_NOTIFY_REMOVED,
            parameters: {}
          }],
          actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
          requestCode: 0,
          actionFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG]
        };
        removedAgent = await wantAgent.getWantAgent(removedAgentInfo);

        // 仅构建当前条目可用的按钮 wantAgent
        usernameAgent = hasUsername ? await wantAgent.getWantAgent(
          SessionNotificationService.buildCopyAgentInfo(entryInfo, Constants.SESSION_FIELD_TYPE_USERNAME, 1)) : null;
        passwordAgent = hasPassword ? await wantAgent.getWantAgent(
          SessionNotificationService.buildCopyAgentInfo(entryInfo, Constants.SESSION_FIELD_TYPE_PASSWORD, 2)) : null;

        this.cachedAgentKey = agentKey;
        this.cachedTapAgent = tapAgent;
        this.cachedRemovedAgent = removedAgent;
        this.cachedUsernameAgent = usernameAgent;
        this.cachedPasswordAgent = passwordAgent;
      }

      const actionButtons: notificationManager.NotificationActionButton[] = [];      if (usernameAgent) {
        actionButtons.push({
          title: ResourceManager.getString($r('app.string.session_copy_username')),
          wantAgent: usernameAgent
        });
      }
      if (passwordAgent) {
        actionButtons.push({
          title: ResourceManager.getString($r('app.string.session_copy_password')),
          wantAgent: passwordAgent
        });
      }

      const request: notificationManager.NotificationRequest = {
        id: Constants.SESSION_NOTIFY_ID,
        notificationSlotType: notificationManager.SlotType.SOCIAL_COMMUNICATION,
        isOngoing: true,
        tapDismissed: false,
        // 永不清除（remainingSec<0）时不设置自动清除，通知持续到锁库/关库
        autoDeletedTime: remainingSec > 0 ? new Date().getTime() + remainingSec * 1000 : 0,
        wantAgent: tapAgent,
        removalWantAgent: removedAgent,
        actionButtons: actionButtons,
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: {
            // 标题实时跟随当前条目名称；未绑定条目（或条目无标题）时回退为应用名
            title: (entryInfo.entryId !== '' && entryInfo.title) ? entryInfo.title :
              ResourceManager.getString($r('app.string.session_notify_title')),
            text: SessionNotificationService.buildNotifyText(entryInfo, copiedFieldType, remainingSec)
          }
        }
      };
      return request;
    } catch (error) {
      const e = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'build session notify request failed: %{public}s %{public}s', e.code, e.message);
      return null;
    }
  }

  /**
   * 构建复制字段按钮的公共事件 wantAgent（事件参数仅含条目 id，不含凭据明文）
   */
  private static buildCopyAgentInfo(entryInfo: SessionEntryInfo, fieldType: string, requestCode: number): wantAgent.WantAgentInfo {
    const copyParams: Record<string, Object> = {
      'groupId': entryInfo.groupId,
      'entryId': entryInfo.entryId,
      'fieldType': fieldType
    };
    const agentInfo: wantAgent.WantAgentInfo = {
      wants: [{
        action: Constants.SESSION_ACTION_COPY_FIELD,
        parameters: copyParams
      }],
      actionType: wantAgent.OperationType.SEND_COMMON_EVENT,
      requestCode: requestCode,
      actionFlags: [wantAgent.WantAgentFlags.CONSTANT_FLAG]
    };
    return agentInfo;
  }

  /**
   * 通知正文（严禁包含凭据明文，仅条目标题与操作状态）
   */
  private static buildNotifyText(entryInfo: SessionEntryInfo, copiedFieldType: string, remainingSec: number): string {
    if (copiedFieldType === Constants.SESSION_FIELD_TYPE_USERNAME) {
      if (remainingSec < 0) {
        return ResourceManager.getString($r('app.string.session_copied_text_no_clear'),
          ResourceManager.getString($r('app.string.session_field_username')));
      }
      return ResourceManager.getString($r('app.string.session_copied_text'),
        ResourceManager.getString($r('app.string.session_field_username')), remainingSec);
    }
    if (copiedFieldType === Constants.SESSION_FIELD_TYPE_PASSWORD) {
      if (remainingSec < 0) {
        return ResourceManager.getString($r('app.string.session_copied_text_no_clear'),
          ResourceManager.getString($r('app.string.session_field_password')));
      }
      return ResourceManager.getString($r('app.string.session_copied_text'),
        ResourceManager.getString($r('app.string.session_field_password')), remainingSec);
    }
    if (entryInfo.entryId) {
      // 标题已实时显示条目名称，正文仅保留与动态按钮联动的操作提示
      if (entryInfo.hasUsername && entryInfo.hasPassword) {
        return ResourceManager.getString($r('app.string.session_copy_hint_both'));
      }
      if (entryInfo.hasUsername) {
        return ResourceManager.getString($r('app.string.session_copy_hint_username'));
      }
      return ResourceManager.getString($r('app.string.session_copy_hint_password'));
    }
    return ResourceManager.getString($r('app.string.session_notify_text_default'));
  }
}
