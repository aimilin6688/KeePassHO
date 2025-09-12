import { Router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { BusinessError } from '@kit.BasicServicesKit';

@Entry
@Component
struct Reward {
  @State isShowOtherPay: boolean = false;

  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();

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
        Text($r('app.string.about_give_a_reward'))
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

            Text($r('app.string.reward_thanks'))
              .fontSize(18)
              .fontWeight(FontWeight.Medium)
              .margin({ top: 20, bottom: 10 })

            Text($r('app.string.reward_description'))
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
            // ¥10 赏一杯奶茶
            this.RewardOption(
              '¥10',
              $r('app.string.reward_milk_tea_desc'),
              () => {
                this.showThankYouMessage($r('app.string.reward_milk_tea_thanks'));
              }
            )

            // ¥30 赞助一顿午餐
            this.RewardOption(
              '¥30',
              $r('app.string.reward_lunch_desc'),
              () => {
                this.showThankYouMessage($r('app.string.reward_lunch_thanks'));
              }
            )

            // ¥50 成为助力伙伴
            this.RewardOption(
              '¥50',
              $r('app.string.reward_partner_desc'),
              () => {
                this.showThankYouMessage($r('app.string.reward_partner_thanks'));
              }
            )

            // ¥100 坐上产品经理席
            this.RewardOption(
              '¥100',
              $r('app.string.reward_pm_desc'),
              () => {
                this.showThankYouMessage($r('app.string.reward_pm_thanks'));
              }
            )
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
              Text($r('app.string.reward_wechat_pay'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })

              // 使用应用图标作为占位符
              Image($r("app.media.startIcon"))
                .width(200)
                .height(200)
                .margin({ bottom: 10 })
                .borderRadius(8)
                .backgroundColor($r('app.color.card_bg'))
            }
            .width('100%')
          }
          .margin({ bottom: 30 })

          // 支付宝
          ListItem() {
            Column() {
              Text($r('app.string.reward_alipay'))
                .fontSize(16)
                .fontWeight(FontWeight.Medium)
                .margin({ bottom: 10 })

              // 使用应用图标作为占位符
              Image($r("app.media.startIcon"))
                .width(200)
                .height(200)
                .margin({ bottom: 10 })
                .borderRadius(8)
                .backgroundColor($r('app.color.card_bg'))
            }
            .width('100%')
          }
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
   * @param description 描述
   * @param onClick 点击事件
   */
  @Builder
  private RewardOption(amount: string, description: Resource, onClick: () => void) {
    Column() {
      Row() {
        Text(amount)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.button_bg_blue'))
        
        Blank()
        
        Button($r('app.string.reward_support'))
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
      .padding({ left: 16, right: 16 })

      Text(description)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .textAlign(TextAlign.Start)
        .padding({ left: 16, right: 16, top: 8, bottom: 16 })
    }
    .width('100%')
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .margin({ bottom: 12 })
  }

  /**
   * 显示感谢信息
   * @param message 感谢信息
   */
  private showThankYouMessage(message: Resource) {
    try {
      this.promptAction.showToast({
        message: message,
        duration: 3000
      });
    } catch (error) {
      console.error('显示感谢信息失败:', error);
    }
  }
}