import { emitter } from '@kit.BasicServicesKit';

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'KdbxUtils';

export class EventBus {
  // 数据库合并事件
  static readonly DATABASE_UPDATE = "database_update";

  // 发送事件
  static emit<T>(event: string, data?: T) {
    hilog.debug(DOMAIN, TAG, `Emit event: ${event}`);
    let eventData: emitter.GenericEventData<T> = {
      data: data
    };
    emitter.emit(event, eventData);
  }

  // 订阅事件
  static on<T>(event: string, callback: (data?: T) => void) {
    hilog.debug(DOMAIN, TAG, `Subscribe event: ${event}`);
    emitter.on(event, (eventData: emitter.GenericEventData<T>): void => {
      callback(eventData?.data);
    });
  }

  // 取消订阅
  static off<T>(event: string, callback?: (data?: T) => void) {
    hilog.debug(DOMAIN, TAG, `Unsubscribe event: ${event}`);
    emitter.off(event, (eventData: emitter.GenericEventData<T>): void => {
      if(callback){
        callback(eventData?.data);
      }
    });
  }
}
