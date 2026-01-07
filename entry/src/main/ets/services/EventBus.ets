import { emitter } from '@kit.BasicServicesKit';

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'KdbxUtils';

export class EventBus {
  // 数据库合并事件
  public static readonly DATABASE_RELOAD = "database_reload";
  // 数据库更新事件
  public static readonly DATABASE_UPDATE = "database_update";
  // KV 数据变更事件
  public static readonly KV_DATA_CHANGE = "kv_data_change";

  // 发送事件
  static emit<T>(event: string, data?: T) {
    hilog.debug(DOMAIN, TAG, `Emit event: ${event}`);
    let eventData: emitter.GenericEventData<T> = {
      data: data
    };
    emitter.emit(event, eventData);
  }

  // 订阅事件
  static on(event: string, callback: Callback<emitter.EventData>) {
    hilog.debug(DOMAIN, TAG, `Subscribe event: ${event}`);
    emitter.on(event, callback);
  }

  /**
   * 取消事件所有订阅者
   * @param event
   */
  static off(event: string, callback?: Callback<emitter.EventData>) {
    hilog.debug(DOMAIN, TAG, `Unsubscribe event: ${event}`);
    if (callback) {
      emitter.off(event, callback);
    } else {
      emitter.off(event);
    }
  }
}
