import { BusinessError, commonEventManager } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Kdbx, KdbxEntry, KdbxFieldReference } from 'kdbxweb';
import { Constants } from '../common/constants/Constants';
import { ClipboardUtils } from '../common/utils';
import { KdbxUtils } from '../common/utils/KdbxUtils';
import { FileService } from './FileService';
import { SessionManager } from './SessionManager';
import { SessionNotificationService } from './SessionNotificationService';

const DOMAIN = 0x0000;
const TAG = 'CopyEventService';

/**
 * 通知按钮复制事件参数
 */
export interface CopyFieldParam {
  groupId: string;
  entryId: string;
  fieldType: string;
}

/**
 * 通知栏快捷复制公共事件订阅服务
 * 订阅 SESSION_ACTION_COPY_FIELD（通知按钮复制）与 SESSION_ACTION_NOTIFY_REMOVED（划掉通知），
 * 复制事件在后台完成取值、字段引用解析与静默复制，全程不离开用户当前应用
 */
export class CopyEventService {
  private static instance: CopyEventService = new CopyEventService();
  private subscriber: commonEventManager.CommonEventSubscriber | null = null;

  private constructor() {
  }

  public static getInstance(): CopyEventService {
    return CopyEventService.instance;
  }

  /**
   * 初始化：订阅会话通知相关公共事件（动态订阅，免权限声明）
   */
  public async init(): Promise<void> {
    if (this.subscriber) {
      return;
    }
    try {
      const subscribeInfo: commonEventManager.CommonEventSubscribeInfo = {
        events: [Constants.SESSION_ACTION_COPY_FIELD, Constants.SESSION_ACTION_NOTIFY_REMOVED]
      };
      this.subscriber = await commonEventManager.createSubscriber(subscribeInfo);
      commonEventManager.subscribe(this.subscriber, (err: BusinessError, data: commonEventManager.CommonEventData) => {
        if (err) {
          hilog.error(DOMAIN, TAG, 'subscribe event failed: %{public}s %{public}s', err.code, err.message);
          return;
        }
        CopyEventService.handleEvent(data);
      });
      hilog.info(DOMAIN, TAG, 'CopyEventService initialized');
    } catch (error) {
      const e = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'init failed: %{public}s %{public}s', e.code, e.message);
      this.subscriber = null;
    }
  }

  /**
   * 销毁：取消订阅
   */
  public destroy(): void {
    if (!this.subscriber) {
      return;
    }
    try {
      commonEventManager.unsubscribe(this.subscriber);
    } catch (error) {
      const e = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'unsubscribe failed: %{public}s %{public}s', e.code, e.message);
    }
    this.subscriber = null;
  }

  /**
   * 公共事件分发
   */
  private static handleEvent(data: commonEventManager.CommonEventData): void {
    if (data.event === Constants.SESSION_ACTION_NOTIFY_REMOVED) {
      SessionManager.getInstance().onNotificationRemoved();
      return;
    }
    if (data.event === Constants.SESSION_ACTION_COPY_FIELD) {
      const param = CopyEventService.parseParams(data.parameters);
      if (param) {
        CopyEventService.copyField(param);
      }
    }
  }

  /**
   * 解析并校验事件参数（严格类型校验，防篡改/缺失，不含明文）
   */
  private static parseParams(parameters?: Record<string, Object>): CopyFieldParam | null {
    if (!parameters) {
      return null;
    }
    const groupId = parameters['groupId'];
    const entryId = parameters['entryId'];
    const fieldType = parameters['fieldType'];
    if (typeof groupId !== 'string' || typeof entryId !== 'string' || typeof fieldType !== 'string') {
      hilog.warn(DOMAIN, TAG, 'Invalid copy field event parameters');
      return null;
    }
    const param: CopyFieldParam = {
      groupId: groupId,
      entryId: entryId,
      fieldType: fieldType
    };
    return param;
  }

  /**
   * 后台复制条目字段（与页面内复制完全一致：字段引用解析 + 按安全设置自动清除，静默无 toast）
   */
  private static copyField(param: CopyFieldParam): void {
    const manager = SessionManager.getInstance();
    if (!manager.isActive()) {
      // 会话已过期但通知残留（后台冻结期间 TTL 到期），清理残留通知
      SessionNotificationService.getInstance().cancelSession();
      return;
    }
    if (!FileService.isDatabaseValid()) {
      return;
    }
    const db: Kdbx = FileService.getDatabase();
    const entry: KdbxEntry | null = KdbxUtils.getEntry(db, param.groupId, param.entryId);
    if (!entry) {
      hilog.warn(DOMAIN, TAG, 'Entry not found for copy event');
      return;
    }
    const fieldKey = param.fieldType === Constants.SESSION_FIELD_TYPE_PASSWORD ? KdbxUtils.FIELD_PASSWORD : KdbxUtils.FIELD_USERNAME;
    const rawValue = KdbxUtils.getFieldValueString(entry.fields, fieldKey);
    if (!rawValue) {
      return;
    }
    const text = KdbxFieldReference.resolveFieldRefsInText(rawValue, db, entry);
    // 静默复制（silent=true，后台不弹 toast）
    ClipboardUtils.copyAutoClear(text, true);
    // 重置会话计时并记录复制态（与剪贴板内容生命周期同步），随后更新通知文案
    manager.onCopied(param.fieldType);
    SessionNotificationService.getInstance().publishCopied(manager.getEntryInfo(), manager.getRemainingSec(), param.fieldType);
  }
}
