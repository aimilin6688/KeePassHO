import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'RecentFilesService';


/**
 * 通知服务
 * 参考文档：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/notification-kit
 */
export class NotificationService {
  constructor() {
    hilog.debug(DOMAIN, TAG, 'NotificationService constructor');
  }

  /**
   * 发布通知
   * @param title 通知标题
   * @param msg 通知内容
   */
  public static publish(title: string, msg: string) {
    hilog.debug(DOMAIN, TAG, 'NotificationService publish: %{public}s', msg);
  }
}