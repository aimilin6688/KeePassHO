import { DateUnit, DateUtils, CommonUtils } from '../common/utils';
import { SettingsService } from './SettingsService';
import { promptAction } from '@kit.ArkUI';
import { iap } from '@kit.IAPKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils } from 'kdbxweb';

const DOMAIN = 0x0000;
const TAG = 'SupportService';

export class SupportService {
  constructor() {
  }

  /**
   * 显示支持弹框
   */
  public static showSupportDialog(context: UIContext): Promise<void> {
    return new Promise((resolve, reject) => {
      if (!SupportService.isShowSupport()) {
        return resolve();
      }
      CommonUtils.showDialog(SupportService.getShowSupportDialog()).then(async result => {
        SettingsService.put(SettingsService.KEY_SHOW_SUPPORT_TIME, new Date().getTime());
        if (result.index === 1) {
          context.getRouter().pushUrl({ url: "pages/about/Support" });
        }
      });
    });
  }

  /**
   * 初始化安装时间
   */
  public static initAppInstallTime() {
    if (SettingsService.getSync(SettingsService.KEY_APP_INSTALL_TIME, -1) > 0) {
      return;
    }
    SettingsService.put(SettingsService.KEY_APP_INSTALL_TIME, new Date().getTime());
  }

  /**
   * 是否可以隐藏支持
   */
  public static isCanHideSupport(): Promise<boolean> {
    return new Promise((resolve, reject) => {
      // 获取安装时间
      const appInstallTime = SettingsService.getSync(SettingsService.KEY_APP_INSTALL_TIME, -1);
      // 没有安装时间
      if (appInstallTime <= 0) {
        return resolve(false);
      }
      // 安装时间超过一个月
      return resolve(DateUtils.offset(new Date(), -1, DateUnit.Month).getTime() >= appInstallTime || SupportService.isSupported());
    });
  }

  /**
   * 自动完成
   */
  public static autoFinish(): Promise<void> {
    return new Promise((resolve, reject) => {
      const parameter: iap.QueryPurchasesParameter = {
        productType: iap.ProductType.CONSUMABLE,
        queryType: iap.PurchaseQueryType.UNFINISHED
      }
      iap.queryPurchases(CommonUtils.getContext(), parameter).then((data: iap.QueryPurchaseResult) => {
        hilog.info(DOMAIN, TAG, `Succeeded in querying purchases. data len: ${data.purchaseDataList?.length}`);
        if (data.purchaseDataList?.length > 0) {
          data.purchaseDataList.forEach(purchaseData => {
            SupportService.finishPurchase(purchaseData)
          })
        }
        resolve();
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, `Failed to query purchases. Code is ${err.code}, message is ${err.message}`);
        reject(err);
      });
    });
  }


  /**
   * 完成购买
   * @param purchaseData
   */
  public static finishPurchase(purchaseString: string, onSuccess?: () => void, onError?: (err: BusinessError) => void) {
    try {
      const purchaseData: PurchaseData = JSON.parse(purchaseString);
      const payload: string = ByteUtils.base64ToString(purchaseData.jwsPurchaseOrder.split('.')[1]);
      const jwsPurchaseOrder: PurchaseOrderPayload = JSON.parse(payload);
      const finishPurchaseParam: iap.FinishPurchaseParameter = {
        productType: iap.ProductType.CONSUMABLE,
        purchaseToken: jwsPurchaseOrder.purchaseToken,
        purchaseOrderId: jwsPurchaseOrder.purchaseOrderId
      };
      iap.finishPurchase(CommonUtils.getContext(), finishPurchaseParam).then(() => {
        hilog.debug(DOMAIN, TAG, 'Finish purchase success: ' + jwsPurchaseOrder.purchaseOrderId);
        onSuccess && onSuccess();
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'Finish purchase failed: ' + err.message);
        onError && onError(err);
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Finish purchase failed: ' + err.message);
      onError && onError(err as BusinessError);
    }
  }

  /**
   * 获取支持弹框
   */
  private static getShowSupportDialog():
    promptAction.ShowDialogOptions {
    return {
      title: $r('app.string.support_dialog_title'),
      message: $r('app.string.support_dialog_message'),
      buttons: [
        {
          text: $r('app.string.cancel_button_text'),
          color: $r('app.color.text_secondary')
        },
        {
          text: $r('app.string.confirm_button_text'),
          color: $r("app.color.button_bg_blue"),
        }
      ],
    }
  }

  /**
   * 查询账户是否已经支持过
   * @returns
   */
  private static isSupported():
    Promise<boolean> {
    try {
      const
        parameter: iap.QueryPurchasesParameter = {
          productType: iap.ProductType.CONSUMABLE,
          queryType: iap.PurchaseQueryType.ALL
        }
      return iap.queryPurchases(CommonUtils.getContext(), parameter).then((data: iap.QueryPurchaseResult) => {
        hilog.info(DOMAIN, TAG, `Succeeded in querying purchases. data len:${data.purchaseDataList?.length}`);
        return data.purchaseDataList?.length > 0;
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, `Failed to query purchases. Code is ${err.code}, message is${err.message}`);
        return false;
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, `Failed to query purchases. message is ${err.message}`);
      return Promise.resolve(false);
    }
  }

  /**
   * 是否需要显示支持弹框
   */
  private static isShowSupport():
    boolean {
    // 不需要显示支持弹框
    if (!SettingsService.getSync(SettingsService.KEY_SHOW_SUPPORT_DIALOG, SettingsService.KEY_SHOW_SUPPORT_DIALOG_DEFAULT)) {
      return false;
    }
    // 今天支持弹款已经显示过了
    const lastShowTime = SettingsService.getSync(SettingsService.KEY_SHOW_SUPPORT_TIME, -1);
    hilog.debug(DOMAIN, TAG, `Last show support time: ${lastShowTime}`);
    return lastShowTime <= 0 || DateUtils.isNotToday(new Date(lastShowTime));
  }
}

interface PurchaseData {
  type: number,
  jwsPurchaseOrder: string,
  jwsSubscriptionStatus: string
}

/**
 * https://developer.huawei.com/consumer/cn/doc/harmonyos-references/iap-data-model#section260562820380
 */
interface PurchaseOrderPayload {
  environment: string,
  purchaseOrderId: string,
  purchaseToken: string,
  productId: string,
  productType: string
}