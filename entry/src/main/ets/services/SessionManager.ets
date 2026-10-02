import { emitter } from '@kit.BasicServicesKit';
import { backgroundTaskManager } from '@kit.BackgroundTasksKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../common/constants/Constants';
import { ClipboardUtils } from '../common/utils';
import { EventBus } from './EventBus';
import { LockScreenService } from './LockScreenService';
import { SessionNotificationService } from './SessionNotificationService';
import { SettingsService } from './SettingsService';

const DOMAIN = 0x0000;
const TAG = 'SessionManager';
/** 倒计时刷新间隔（毫秒） */
const COUNTDOWN_TICK_MS = 5000;

/**
 * 会话绑定的条目信息（仅 id、标题与字段可用性标记，不含任何凭据明文）
 */
export class SessionEntryInfo {
  groupId: string = '';
  entryId: string = '';
  title: string = '';
  /** 条目是否含账号（决定通知是否显示复制账号按钮） */
  hasUsername: boolean = false;
  /** 条目是否含密码（决定通知是否显示复制密码按钮） */
  hasPassword: boolean = false;
}

/**
 * 解锁会话管理
 * 会话生命周期 = 数据库解锁期间（锁库/关库才结束）；
 * 通知窗口 = 自动清理粘贴板时长设置：解锁/切换条目/复制成功都会重置窗口并重新发布通知；
 * 窗口到期仅取消通知（会话保持），再次切换条目或复制时重新触发
 */
export class SessionManager {
  private static instance: SessionManager = new SessionManager();
  private active: boolean = false;
  /** 通知窗口时长 = 自动清理粘贴板时长设置（-1 为永不清除，通知持续到锁库） */
  private windowSec: number = SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT;
  private windowStart: number = 0;
  private timerId: number = -1;
  private entryInfo: SessionEntryInfo = new SessionEntryInfo();
  /** 最近一次复制的字段类型（'' 表示当前无未过期的复制态），决定窗口期内通知文案 */
  private lastFieldType: string = '';
  /** 短时任务（延迟挂起）ID，-1 表示未申请；会话进行中切后台时申请，避免进程冻结导致定时器停止、通知按钮事件无法投递 */
  private suspendRequestId: number = -1;

  private constructor() {
  }

  public static getInstance(): SessionManager {
    return SessionManager.instance;
  }

  /**
   * 初始化：监听解锁/锁库/关库事件（与 LockScreenService 各自独立订阅，互不影响）
   */
  public init(): void {
    EventBus.on(LockScreenService.EVENT_LOCK_ACTION, (eventData: emitter.EventData) => {
      const data = eventData?.data;
      if (typeof data === 'string') {
        if (data === 'unlock') {
          SessionManager.getInstance().start();
        } else {
          SessionManager.getInstance().end();
        }
      }
    });
    // 手动锁/自动锁（LockScreenService.showLockWindow）
    EventBus.on(LockScreenService.EVENT_LOCK_SCREEN, () => {
      SessionManager.getInstance().end();
    });
    hilog.info(DOMAIN, TAG, 'SessionManager initialized');
  }

  /**
   * 销毁：取消监听并结束会话
   */
  public destroy(): void {
    EventBus.off(LockScreenService.EVENT_LOCK_ACTION);
    EventBus.off(LockScreenService.EVENT_LOCK_SCREEN);
    this.end();
  }

  /**
   * 会话是否进行中（数据库解锁期间始终有效，与通知窗口过期无关）
   */
  public isActive(): boolean {
    return this.active;
  }

  /**
   * 当前会话绑定的条目信息
   */
  public getEntryInfo(): SessionEntryInfo {
    return this.entryInfo;
  }

  /**
   * 当前通知窗口剩余秒数；永不清除时返回 -1，已过期返回 0
   */
  public getRemainingSec(): number {
    if (this.windowSec <= 0) {
      return -1;
    }
    const elapsedSec = (new Date().getTime() - this.windowStart) / 1000;
    return Math.max(0, Math.ceil(this.windowSec - elapsedSec));
  }

  /**
   * 复制成功后：重置通知窗口（定时清理任务重新触发）并记录复制态刷新文案
   * @param fieldType 复制的字段类型（Constants.SESSION_FIELD_TYPE_*）
   */
  public onCopied(fieldType: string): void {
    if (!this.active) {
      return;
    }
    this.lastFieldType = fieldType;
    this.restartWindow();
  }

  /**
   * 通知开关变更时刷新通知（设置页调用）：
   * 禁用→立即删除已显示的通知（即使会话进行中）；启用→会话进行中立即恢复发布。
   * @param enabled 开关新值（由调用方显式传入；put 异步落盘，回读会拿到旧值）
   */
  public refreshNotification(enabled: boolean): void {
    if (this.active && enabled) {
      SessionNotificationService.getInstance().publishActiveEntry(this.entryInfo, this.getRemainingSec());
    } else {
      // 开关禁用或会话未开始：清除当前通知（含永不清除窗口的无兜底残留）
      SessionNotificationService.getInstance().cancelSession();
    }
  }

  /**
   * 更新当前浏览条目（条目详情页打开时调用）：
   * 无论通知窗口是否已过期，都重新发布通知绑定新条目并重置窗口
   */
  public setActiveEntry(groupId: string, entryId: string, title: string, hasUsername: boolean, hasPassword: boolean): void {
    this.entryInfo.groupId = groupId;
    this.entryInfo.entryId = entryId;
    this.entryInfo.title = title;
    this.entryInfo.hasUsername = hasUsername;
    this.entryInfo.hasPassword = hasPassword;
    if (this.active) {
      // 切换条目即结束复制态文案（通知回到条目绑定态），剪贴板清理任务由 restartWindow 同步重置
      this.lastFieldType = '';
      this.restartWindow();
      SessionNotificationService.getInstance().publishActiveEntry(this.entryInfo, this.getRemainingSec());
    }
  }

  /**
   * 应用切后台：会话进行中申请短时任务（延迟挂起，约 3 分钟），
   * 避免进程被系统冻结导致：剪贴板清理/倒计时定时器停摆、通知按钮公共事件无法投递
   */
  public onAppBackground(): void {
    if (!this.active || this.suspendRequestId != -1) {
      return;
    }
    try {
      const delayInfo = backgroundTaskManager.requestSuspendDelay('KeePassHO quick fill window', () => {
        // 短时任务即将超时（系统上限约 3 分钟）：窗口期（默认 30 秒）早已结束，通知已由系统清除
        SessionManager.getInstance().suspendRequestId = -1;
        hilog.warn(DOMAIN, TAG, 'Suspend delay about to time out');
      });
      this.suspendRequestId = delayInfo.requestId;
      hilog.info(DOMAIN, TAG, 'Suspend delay requested, id: %{public}d, actual: %{public}d', delayInfo.requestId,
        delayInfo.actualDelayTime);
    } catch (error) {
      const e = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'requestSuspendDelay failed: %{public}s %{public}s', e.code, e.message);
    }
  }

  /**
   * 应用回前台：释放短时任务
   */
  public onAppForeground(): void {
    this.releaseSuspendDelay();
  }

  /**
   * 释放短时任务
   */
  private releaseSuspendDelay(): void {
    if (this.suspendRequestId == -1) {
      return;
    }
    try {
      backgroundTaskManager.cancelSuspendDelay(this.suspendRequestId);
    } catch (error) {
      const e = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'cancelSuspendDelay failed: %{public}s %{public}s', e.code, e.message);
    }
    this.suspendRequestId = -1;
  }

  /**
   * 用户划掉通知：仅结束通知窗口状态，不锁库、不清剪贴板
   */
  public onNotificationRemoved(): void {
    this.stopTicker();
    this.lastFieldType = '';
    AppStorage.setOrCreate(Constants.APP_STORAGE_SESSION_ACTIVE, false);
    hilog.info(DOMAIN, TAG, 'Session notification removed by user');
  }

  /**
   * 开启会话（解锁成功触发）：会话存活 + 首个通知窗口
   */
  private start(): void {
    const notifyEnabled = SettingsService.getSync(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE,
      SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE_DEFAULT);
    this.active = true;
    this.lastFieldType = '';
    AppStorage.setOrCreate(Constants.APP_STORAGE_SESSION_ACTIVE, true);
    this.restartWindow();
    if (notifyEnabled) {
      SessionNotificationService.getInstance().publishActiveEntry(this.entryInfo, this.getRemainingSec());
    } else {
      // 通知开关关闭：清理可能残留的旧通知
      SessionNotificationService.getInstance().cancelSession();
    }
    hilog.info(DOMAIN, TAG, 'Session started, window: %{public}d', this.windowSec);
  }

  /**
   * 结束会话（锁库/关库触发），取消常驻通知；通知窗口过期不调用此方法
   */
  private end(): void {
    this.stopTicker();
    this.releaseSuspendDelay();
    if (!this.active) {
      return;
    }
    this.active = false;
    this.lastFieldType = '';
    AppStorage.setOrCreate(Constants.APP_STORAGE_SESSION_ACTIVE, false);
    SessionNotificationService.getInstance().cancelSession();
    hilog.info(DOMAIN, TAG, 'Session ended');
  }

  /**
   * 重置通知窗口：窗口时长取自动清理粘贴板时长设置，窗口起点归零并重启定时器；
   * 同时重置剪贴板清理任务，使通知窗口与剪贴板内容生命周期保持同步
   */
  private restartWindow(): void {
    this.windowSec = SettingsService.getSync(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME,
      SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT);
    this.windowStart = new Date().getTime();
    // 切换条目/复制等交互重新触发通知时，剪贴板 30 秒清理同步重新计算
    ClipboardUtils.restartAutoClear();
    this.startTicker();
  }

  /**
   * 启动窗口倒计时定时器：
   * 每 COUNTDOWN_TICK_MS 重发同 ID 通知刷新剩余时间文案（复制态）；
   * 窗口到期仅取消通知（会话保持，切换条目/复制可重新触发），锁库/关库才真正结束会话；
   * 应用后台冻结时定时器暂停，冻结场景由通知 autoDeletedTime 兜底
   */
  private startTicker(): void {
    this.stopTicker();
    if (this.windowSec <= 0) {
      // 永不清除：无倒计时亦无窗口到期，通知持续到锁库/划掉
      return;
    }
    this.timerId = setInterval(() => {
      const remainingSec = this.getRemainingSec();
      if (remainingSec <= 0) {
        this.expireWindow();
        return;
      }
      if (this.lastFieldType !== '') {
        SessionNotificationService.getInstance().publishCopied(this.entryInfo, remainingSec, this.lastFieldType);
      }
    }, COUNTDOWN_TICK_MS);
  }

  /**
   * 停止窗口倒计时定时器
   */
  private stopTicker(): void {
    if (this.timerId != -1) {
      clearInterval(this.timerId);
      this.timerId = -1;
    }
  }

  /**
   * 通知窗口到期：取消通知但会话保持存活，切换条目或再次复制时重新触发
   */
  private expireWindow(): void {
    this.stopTicker();
    this.releaseSuspendDelay();
    this.lastFieldType = '';
    SessionNotificationService.getInstance().cancelSession();
    hilog.info(DOMAIN, TAG, 'Notification window expired, session kept');
  }
}
