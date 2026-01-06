import { Router } from '@kit.ArkUI';
import { iap } from '@kit.IAPKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { fileIo as fs } from '@kit.CoreFileKit';

import { common } from '@kit.AbilityKit';
import { SupportService } from '../../services/SupportService';
import { SettingsService } from '../../services/SettingsService';
import { DateUtils, DateUnit } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'Support';

interface ProductOption {
  goodId: string;
  amount: string;
  title: ResourceStr;
  thanksMessage: ResourceStr;
}

@Entry
@Component
struct Support {
  @State clickCount: number = 0;
  @State isShowOtherPay: boolean = false;
  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private products: Array<ProductOption> = [
    {
      goodId: "10010",
      amount: '¥10',
      title: $r("app.string.support_milk_tea_title"),
      thanksMessage: $r("app.string.support_milk_tea_thanks")
    },
    {
      goodId: "10011",
      amount: '¥30',
      title: $r("app.string.support_lunch_title"),
      thanksMessage: $r("app.string.support_lunch_thanks")
    },
    {
      goodId: "10012",
      amount: '¥50',
      title: $r("app.string.support_partner_title"),
      thanksMessage: $r("app.string.support_partner_thanks")
    },
    {
      goodId: "10013",
      amount: '¥100',
      title: $r("app.string.support_pm_title"),
      thanksMessage: $r("app.string.support_pm_thanks")
    }
  ];

  aboutToAppear(): void {
    this.clickCount = 0;
    try {
      // 查询支付环境状态
      iap.queryEnvironmentStatus(this.context).then(result => {
        hilog.info(DOMAIN, TAG, 'Environment status: ' + result);
        this.queryProductList();
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'Failed to query environment status: ' + err.message);
        this.promptAction.showToast({ message: err.message });
      });
      SupportService.autoFinish();
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Failed to query environment status: ' + err.message);
    }
  }

  /**
   * 查询打赏金额列表
   * @returns
   */
  private queryProductList(): void {
    const existsProd: string[] = this.products.map(item => item.goodId);
    const parameter: iap.QueryProductsParameter = {
      productType: iap.ProductType.CONSUMABLE,
      productIds: existsProd
    }
    iap.queryProducts(this.context, parameter).then((data: Array<iap.Product>) => {
      console.info(`Succeeded in querying products. data length: ${data?.length}`);
      if (!data || data.length === 0) {
        return;
      }
      for (let i = 0; i < data.length; i++) {
        const product = data[i];
        if (existsProd.indexOf(product.id) != -1) {
          for (let j = 0; j < this.products.length; j++) {
            const option = this.products[j];
            if (product.id === option.goodId) {
              option.amount = product.localPrice ?? product.price;
            }
          }
        }
      }
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, `Failed to query products. Code is ${err.code}, message is ${err.message}`);
    });
  }

  /**
   * 支付
   * @param option
   */
  private pay(option: ProductOption) {
    try {
      iap.createPurchase(this.context, { productId: option.goodId, productType: iap.ProductType.CONSUMABLE }).then(result => {
        this.paySuccess(result, option);
      }).catch((err: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'Payment failed: ' + err.message);
        this.promptAction.showToast({ message: err.message });
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Payment failed: ' + err.message);
      this.promptAction.showToast({ message: err.message });
    }
  }

  /**
   * 支付成功
   * @param result 结果
   * @param option 商品
   */
  private paySuccess(result: iap.CreatePurchaseResult, option: ProductOption) {
    hilog.debug(DOMAIN, TAG, 'Payment result: ' + JSON.stringify(result));
    SupportService.finishPurchase(result.purchaseData, () => {
      SettingsService.put(SettingsService.KEY_SHOW_SUPPORT_DIALOG, false);
      SettingsService.put(SettingsService.KEY_APP_INSTALL_TIME, DateUtils.offset(new Date(), -3, DateUnit.Month).getTime());
      this.showThankYouMessage(option.thanksMessage);
    }, (err: BusinessError) => {
      this.promptAction.showToast({ message: err.message });
    });
  }

  /**
   * 保存图片到本地
   */
  private async saveImg(result: SaveButtonOnClickResult, imgResource: Resource): Promise<void> {
    if (result === SaveButtonOnClickResult.SUCCESS) {
      try {
        this.context?.resourceManager.getMediaContent(imgResource, async (err, data) => {
          if (err) {
            hilog.error(DOMAIN, TAG, 'Failed to get resource file content: ' + err.message);
            this.promptAction.showToast({ message: err.message });
            return;
          }
          let helper = photoAccessHelper.getPhotoAccessHelper(this.context);
          let uri = await helper.createAsset(photoAccessHelper.PhotoType.IMAGE, 'png');
          let destFile: fs.File = fs.openSync(uri, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
          await fs.write(destFile.fd, data.buffer).then(() => {
            this.promptAction.showToast({ message: $r('app.string.save_success') });
          });
          await fs.close(destFile.fd);
        })
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'Save file failed with error message: ' + err.message + ', error code: ' + err?.code);
        this.promptAction.showToast({ message: err.message });
      }
    }
  }

  /**
   * 显示感谢信息
   * @param message 感谢信息
   */
  private showThankYouMessage(message: ResourceStr) {
    try {
      this.promptAction.showToast({
        message: message,
        duration: 8000
      });
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'Show thanks message failed:' + err.message + ', error code: ' + err?.code);
    }
  }

  /**
   * 显示其他支付方式
   */
  private showOtherPay() {
    if (this.isShowOtherPay === false) {
      this.clickCount += 1;
      if (this.clickCount >= 5) {
        this.isShowOtherPay = true;
      }
    }
  }

  build() {
    // 内容区域
    Column() {
      // 标题栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 12, right: 12 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back()
          })
        Text($r("app.string.about_support"))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
        Blank()
      }
      .width('100%')
      .height(56)

      // 内容
      List() {
        ListItem() {
          // Logo或应用图标
          Column() {
            Image($r('app.media.startIcon'))
              .width(90)
              .height(90)
              .margin({ top: 40, bottom: 10 })
              .onClick(() => {
                this.showOtherPay();
              })

            Text($r("app.string.support_thanks"))
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 20, bottom: 10 })

            Text($r("app.string.support_description"))
              .margin({ top: 10, bottom: 30 })
              .fontColor($r('app.color.text_secondary'))
              .fontSize(16)
              .textAlign(TextAlign.Center)
          }
          .width('100%')
        }

        // 打赏金额选项
        ListItem() {
          Column() {
            ForEach(this.products, (option: ProductOption, index: number) => {
              this.RewardOption(
                option.amount,
                option.title,
                () => {
                  this.pay(option);
                }
              )
            })
          }
          .width('100%')
          .padding({ top: 10, bottom: 20 })
        }

        // 其他打赏方式
        if (this.isShowOtherPay) {
          // 微信支付
          ListItem() {
            // 微信支付
            Column() {
              Text($r("app.string.support_wechat_pay"))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })

              // 使用应用图标作为占位符
              Image($r("app.media.pay_wechat"))
                .width(200)
                .height(200)
                .margin({ bottom: 10 })
                .borderRadius(8)
                .backgroundColor($r('app.color.card_bg'))
              // 保存图标
              SaveButton().onClick((event, result: SaveButtonOnClickResult) => {
                this.saveImg(result, $r("app.media.pay_wechat"));
              })
            }
            .width('100%')
          }
          .margin({ bottom: 30 })

          // 支付宝
          ListItem() {
            Column() {
              Text($r("app.string.support_alipay"))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })

              // 使用应用图标作为占位符
              Image($r("app.media.pay_ali"))
                .width(200)
                .height(200)
                .margin({ bottom: 10 })
                .borderRadius(8)
                .backgroundColor($r('app.color.card_bg'))
              // 保存图标
              SaveButton().onClick((event, result: SaveButtonOnClickResult) => {
                this.saveImg(result, $r("app.media.pay_ali"));
              });
            }
            .width('100%')
          }
        }

        // 空白占位
        ListItem() {
          Column() {
          }
          .height(100)
        }
      }
      .width('100%')
      .height('100%')
      .padding(16)
    }
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
  }

  /**
   * 构建打赏选项组件
   * @param amount 金额
   * @param title 标题
   * @param description 描述
   * @param onClick 点击事件
   */
  @Builder
  private RewardOption(amount: string, title: ResourceStr, onClick: () => void) {
    Column() {
      Row() {
        Text(amount)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.button_bg_blue'))

        Blank()

        Button($r("app.string.support_support"))
          .fontSize(14)
          .fontColor($r('app.color.button_text_blue'))
          .backgroundColor($r('app.color.button_bg_blue'))
          .borderRadius(20)
          .height(36)
          .onClick(() => {
            onClick();
          })
      }
      .width('100%')
      .padding({ left: 16, right: 8, top: 8 })

      Text(title)
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .textAlign(TextAlign.Start)
        .padding({
          left: 16,
          right: 16,
          top: 8,
          bottom: 16
        })
        .width('100%')
    }
    .width('100%')
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .margin({ bottom: 12 })
  }
}