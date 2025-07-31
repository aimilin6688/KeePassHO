import { FileService } from '../services/FileService';
import { SettingsService } from '../services/SettingsService';
import { DbFileParam } from '../services/TypeDefined';
import { PromptAction, Router } from '@kit.ArkUI';
import { userAuth } from '@kit.UserAuthenticationKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ResourceManager from '../common/utils/ResourceManager';

const DOMAIN = 0x0000;
const TAG = 'UnLockDatabase';

@Entry
@Component
struct UnLockDatabase {
  @State quickLockPasswordLength: number = SettingsService.KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH_DEFAULT;
  @State quickPassword: string = '';
  private dbFileParam: DbFileParam = FileService.getDbFileParam();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private router: Router = this.getUIContext().getRouter();
  private rand = cryptoFramework.createRandom();
  private authTrustLevel: userAuth.AuthTrustLevel = userAuth.AuthTrustLevel.ATL3; // 安全等级
  private authParam: userAuth.AuthParam = {
    challenge: this.rand?.generateRandomSync(16)?.data,
    authType: [userAuth.UserAuthType.FINGERPRINT],
    authTrustLevel: this.authTrustLevel
  };
  private widgetParam: userAuth.WidgetParam = {title:  ResourceManager.getString($r("app.string.please_auth_fingerprint"))};
  private isFingerprintSupport =  this.checkFingerprintSupport();


  aboutToAppear(): void {

  }

  onPageShow(): void {
    SettingsService.get(SettingsService.KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH, this.quickLockPasswordLength, (value) => {
      this.quickLockPasswordLength = value;
    });
    if(this.isFingerprintSupport){
      this.startFingerprintAuth();
    }
  }

  private quickUnlock() {
    if (!this.quickPassword) {
      this.promptAction.showToast({ message: $r('app.string.password_placeholder') });
      return
    }
    let password = this.dbFileParam.password;
    // 密码长度 <= 快速解锁密码要求长度
    if (password.length <= this.quickLockPasswordLength) {
      if (password.lastIndexOf(this.quickPassword) != -1) {
        return this.router.pushUrl({ url: 'pages/DatabaseView' });
      } else {
        this.promptAction.showToast({ message: $r('app.string.password_error') });
        return;
      }
    }
    // 密码长度 > 快速解锁密码要求长度
    if (this.quickPassword.length < this.quickLockPasswordLength) {
      this.promptAction.showToast({ message: $r('app.string.password_length_error') });
      return;
    }
    if (password.lastIndexOf(this.quickPassword) != -1) {
      return this.router.pushUrl({ url: 'pages/DatabaseView' });
    } else {
      this.promptAction.showToast({ message: $r('app.string.password_error') });
      return;
    }
  }

  private closeDatabase() {
    FileService.getInstance().init();
    this.router.pushUrl({ url: 'pages/Index' });
  }

  // 检查设备是否支持指纹功能
  private checkFingerprintSupport(): boolean {
    try {
      userAuth.getAvailableStatus(userAuth.UserAuthType.FINGERPRINT, this.authTrustLevel);
      return true;
    } catch (error) {
      hilog.info(DOMAIN, TAG, "Device does not support fingerprint");
      return false;
    }
  }

  // 开始指纹验证
  private startFingerprintAuth() {
    try {
      const authInstance = userAuth.getUserAuthInstance(this.authParam, this.widgetParam);
      const router = this.router;
      authInstance.on('result', {
        onResult(result) {
          if (result.result === userAuth.UserAuthResultCode.SUCCESS) {
            router.pushUrl({ url: 'pages/DatabaseView' });
          } else {
            hilog.error(DOMAIN, TAG, "Auth fail，error：" + result.result);
          }
          authInstance.off('result');
        }
      });
      authInstance.start();
    } catch (error) {
      const err: BusinessError = error as BusinessError;
      hilog.error(DOMAIN, TAG, `auth catch error. Code is ${err?.code}, message is ${err?.message}`);
    }
  }


  build() {
    Column() {
      // 主要内容区域
      Column() {
        // Logo或应用图标
        Image($r('app.media.startIcon'))
          .width(120)
          .height(120)
          .margin({ top: 60, bottom: 40 })

        Text($r('app.string.quick_unlock'))
          .fontSize(22)
          .width('100%')
          .fontColor($r('app.color.text_primary'))

        Text(this.dbFileParam.fileName)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .margin({ top: 8 })

        // 用户名
        Column() {
          Text($r('app.string.input_quick_unlock_password', this.quickLockPasswordLength))
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: 8 })
            .alignSelf(ItemAlign.Start)

          TextInput({ text: this.quickPassword })
            .width('100%')
            .key("quickPasswordInput")
            .type(InputType.Password)
            .fontSize(16)
            .enableAutoFill(false)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(8)
            .onChange((value) => {
              this.quickPassword = value;
            })
            .onSubmit(() => {
              this.quickUnlock();
            })
        }
        .width('100%')
        .margin({ top: 16 })

      }
      .width('100%')
      .justifyContent(FlexAlign.Start)
      .layoutWeight(1)
      .padding({ left: 16, right: 16 })

      if (this.isFingerprintSupport){
        Row() {
          Text($r('app.string.auth_by_fingerprint'))
            .fontSize(14)
            .fontColor($r('app.color.button_bg_blue'))
            .margin({ bottom: 8 })
            .decoration({
              type: TextDecorationType.Underline,
              color: $r('app.color.button_bg_blue')
            })
            .onClick(() => {
              this.startFingerprintAuth();
            })
        }
        .justifyContent(FlexAlign.Center)
        .width('100%')
        .position({ x: 0, y: '100%' })
        .translate({ y: -100 }) // 调整位置，确保正确显示
      }

      // 操作按钮
      Row() {
        // 关闭数据库
        Button() {
          Row() {
            Image($r('sys.media.ohos_ic_public_cancel_filled'))
              .width(20)
              .height(20)
              .fillColor($r('app.color.button_text'))
              .margin({ right: 8 })

            Text($r('app.string.close_button_text'))
              .fontSize(16)
              .fontColor($r('app.color.button_text'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('45%')
        .height(40)
        .borderRadius(16)
        .backgroundColor(Color.Gray)
        .onClick(() => {
          this.closeDatabase();
        })

        Blank()
        // 解锁按钮
        Button() {
          Row() {
            Image($r('app.media.ic_check'))
              .width(20)
              .height(20)
              .fillColor($r('app.color.button_text'))
              .margin({ right: 8 })

            Text($r('app.string.unlock'))
              .fontSize(16)
              .fontColor($r('app.color.button_text'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('45%')
        .height(40)
        .borderRadius(16)
        .backgroundColor($r('app.color.button_bg_blue'))
        .onClick(() => {
          this.quickUnlock();
        })
      }
      .width('100%')
      .height(45)
      .padding({
        top: 12,
        bottom: 0,
        left: 16,
        right: 16
      })
      .position({ x: 0, y: '100%' })
      .translate({ y: -45 }) // 调整位置，确保正确显示
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}