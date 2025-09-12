import { PromptAction, Router } from '@kit.ArkUI';
import ResourceManager from '../../common/utils/ResourceManager';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'About';

@Entry
@Component
struct About {
  @State version: string = '';
  private router: Router = this.getUIContext().getRouter();
  private context: common.UIAbilityContext = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private bundleName: string = '';

  aboutToAppear() {
    this.setVersion();
  }

  // 获取当前应用版本号
  private setVersion() {
    let bundleFlags = bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION;
    bundleManager.getBundleInfoForSelf(bundleFlags).then((result) => {
      this.version = ResourceManager.getString($r('app.string.About_version')) + result.versionName
      this.bundleName = result.name;
    })
  }

  /*
   * 发送反馈邮件
   */
  private sendFeedback() {
    // 配置邮件参数
    const subject = encodeURIComponent('KeePassHO问题反馈,' + this.version); // 邮件主题
    const body = encodeURIComponent('开发者您好：\n\n'); // 邮件正文

    let sendMail: Want = {
      action: 'ohos.want.action.sendToData',
      uri: `mailto:aimilin@yeah.net?subject=${subject}&body=${body}`
    };

    // 唤起邮件应用
    this.context.startAbility(sendMail)
      .then(() => {
        hilog.info(DOMAIN, TAG, '邮件发送成功');
      })
      .catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, '邮件发送失败：' + error.message);
      });
  }

  /**
   * 给个好评
   */
  private rate() {
    let want: Want = {
      action: 'ohos.want.action.appdetail',
      uri: 'store://appgallery.huawei.com/app/detail?id=' + this.bundleName + '&action=write-review',
    };
    this.context.startAbility(want).then(() => {
      hilog.info(DOMAIN, TAG, "Succeeded in starting Ability successfully.")
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, `Failed to startAbility.Code: ${error.code}, message is ${error.message}`);
    });
  }

  build() {
    Stack() {
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

          Text($r('app.string.Settings_about'))
            .fontSize(18)
            .fontWeight(FontWeight.Medium)

          Blank()
        }
        .width('100%')
        .height(56)

        // 内容
        Column() {
          // Logo或应用图标
          Image($r('app.media.startIcon'))
            .width(90)
            .height(90)
            .margin({ top: 40, bottom: 10 })
          Text(this.version)
            .fontSize(16)
            .margin(5)

          Text($r('app.string.About_description'))
            .margin({ top: 20 })
            .fontColor($r('app.color.text_secondary'))
            .fontSize(16)
            .margin(5)

          List() {
            ListItemGroup() {
              // 意见反馈
              ListItem() {
                Row() {
                  Text($r("app.string.feedback"))
                    .fontSize(16)
                    .flexGrow(1)
                  Image($r('app.media.ic_arrow_right'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.text_primary'))
                }
                .width('100%')
                .padding(16)
                .onClick(() => {
                  this.sendFeedback();
                })
              }

              // 给个好评
              ListItem() {
                Row() {
                  Text($r("app.string.rate_for_us"))
                    .fontSize(16)
                    .flexGrow(1)
                  Image($r('app.media.ic_arrow_right'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.text_primary'))
                }
                .onClick(() => {
                  this.rate();
                })
                .width('100%')
                .padding(16)
              }

              // 打赏作者
              ListItem() {
                Row() {
                  Text($r("app.string.about_give_a_reward"))
                    .fontSize(16)
                    .flexGrow(1)
                  Image($r('app.media.ic_arrow_right'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.text_primary'))
                }
                .onClick(() => {
                  this.router.pushUrl({ url: 'pages/about/Reward' })
                })
                .width('100%')
                .padding(16)
              }
            }
            .margin({ top: 12, bottom: 12 })
            .backgroundColor($r("app.color.card_bg"))
            .borderRadius(12)
            .divider({
              strokeWidth: 1,
              color: $r('app.color.divider'),
            })
          }
          .width('100%')
          .height('auto')
          .layoutWeight(1)
          .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .padding(16)
      }
    }
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP,SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
