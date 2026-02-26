import { PromptAction, Router } from '@kit.ArkUI';
import { CommonUtils, ResourceManager } from '../../common/utils';
import { bundleManager, common, Want } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ClipboardUtils } from '../../common/utils/ClipboardUtils';
import { updateManager } from '@kit.AppGalleryKit';
import { LoadingDialog } from '../../components/loading/LoadingDialogUtils';

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
  private authEmail: string = "aimilin@yeah.net";
  private codeUrl: string = "https://github.com/aimilin6688/KeePassHO";
  private otherSystemUrl: string = "https://keepass.info/download.html";

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
      uri: `mailto:${this.authEmail}?subject=${subject}&body=${body}`
    };

    // 唤起邮件应用
    this.context.startAbility(sendMail)
      .then(() => {
        hilog.info(DOMAIN, TAG, 'Succeeded to send mail.');
      })
      .catch((error: BusinessError) => {
        hilog.error(DOMAIN, TAG, 'Failed to send mail：' + error.message);
        CommonUtils.showToast({ message: error.message });
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
      CommonUtils.showToast({ message: error.message });
    });
  }

  /**
   * 访问Url 地址
   */
  private goUrl(url: string) {
    try {
      let want: Want = {
        action: 'ohos.want.action.viewData',
        entities: ['entity.system.browsable'],
        uri: url,
      };
      this.context.startAbility(want)
        .then(() => {
          hilog.info(DOMAIN, TAG, 'Open browser successfully');
        })
        .catch((err: BusinessError) => {
          hilog.info(DOMAIN, TAG, 'Failed to open browser. Error code: ' + err.code + ', message: ' + err.message);
          CommonUtils.showToast({ message: err.message });
        });
    } catch (error) {
      hilog.info(DOMAIN, TAG, 'An unexpected error occurred. Error code: ' + error.code + ', message: ' + error.message);
      CommonUtils.showToast({ message: error.message });
    }
  }

  /**
   * 联系作者
   */
  private contactAuthor() {
    ClipboardUtils.copy(this.authEmail);
  }

  /**
   * 检查更新
   */
  private checkUpdate() {
    try {
      LoadingDialog.showLoading($r('app.string.loading_message'));
      updateManager.checkAppUpdate(this.context).then((checkResult: updateManager.CheckUpdateResult) => {
        hilog.info(DOMAIN, 'TAG', "Succeeded in checking Result updateAvailable:" + checkResult.updateAvailable);
        LoadingDialog.hideLoading();
        // 检查到新版本
        if (updateManager.UpdateAvailableCode.LATER_VERSION_EXIST == checkResult.updateAvailable) {
          updateManager.showUpdateDialog(this.context).catch((error: BusinessError) => {
            hilog.error(DOMAIN, 'TAG', "Failed to show update dialog. Error code: " + error.code + ", message: " + error.message);
          });
        } else {
          CommonUtils.showToast({ message: $r('app.string.About_app_later_version_not_exist') });
        }
      }).catch((error: BusinessError) => {
        hilog.error(DOMAIN, 'TAG', "Failed to check update. Error code: " + error.code + ", message: " + error.message);
        LoadingDialog.hideLoading();
        CommonUtils.showToast({ message: error?.message });
      });
    } catch (error) {
      hilog.error(DOMAIN, 'TAG', "An unexpected error occurred. Error code: " + error.code + ", message: " + error.message);
      LoadingDialog.hideLoading();
      if (error?.message) {
        CommonUtils.showToast({ message: error?.message });
      }
    }
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

              // 支持作者
              ListItem() {
                Row() {
                  Text($r("app.string.about_support"))
                    .fontSize(16)
                    .flexGrow(1)
                  Image($r('app.media.ic_arrow_right'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.text_primary'))
                }
                .onClick(() => {
                  CommonUtils.pushUrl({ url: 'pages/about/Support' })
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


            ListItemGroup() {
              // 联系作者
              ListItem() {
                Row() {
                  Text($r("app.string.about_contact_author"))
                    .fontSize(16)
                    .flexGrow(1)
                  Blank()
                  Text(this.authEmail)
                    .fontSize(16)
                    .enableDataDetector(true)
                }
                .width('100%')
                .padding(16)
                .onClick(() => {
                  this.contactAuthor();
                })
              }

              // 源代码
              ListItem() {
                Row() {
                  Text($r("app.string.about_source_code"))
                    .fontSize(16)
                    .flexGrow(1)
                  Image($r('app.media.ic_arrow_right'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.text_primary'))
                }
                .onClick(() => {
                  this.goUrl(this.codeUrl);
                })
                .width('100%')
                .padding(16)
              }

              // 其他系统
              ListItem() {
                Row() {
                  Text($r("app.string.about_other_system"))
                    .fontSize(16)
                    .flexGrow(1)
                  Image($r('app.media.ic_arrow_right'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.text_primary'))
                }
                .onClick(() => {
                  this.goUrl(this.otherSystemUrl);
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

            ListItemGroup() {
              // 检查更新
              ListItem() {
                Row() {
                  Text($r("app.string.about_check_update"))
                    .fontSize(16)
                    .flexGrow(1)
                  Image($r('app.media.ic_arrow_right'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.text_primary'))
                }
                .onClick(() => {
                  this.checkUpdate();
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
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
    .width('100%')
    .height('100%')
  }
}
