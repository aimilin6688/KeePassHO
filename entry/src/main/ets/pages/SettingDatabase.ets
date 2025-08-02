import { Router } from '@kit.ArkUI';
import { ChangePasswordDialog } from '../components/ChangePasswordDialog';
import { FileService } from '../services/FileService';


@Entry
@Component
export struct SettingsDatabase {
  @State isDatabaseValid: boolean = false;
  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();
  private changePasswordDialogController: CustomDialogController = new CustomDialogController({
    builder: ChangePasswordDialog({
      onSuccess: this.handlePasswordChange.bind(this)
    }),
    cancel: this.handleDialogCancel.bind(this),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });

  aboutToAppear(): void {
  }

  onPageShow(): void {
    const dbFileParam = FileService.getDbFileParam();
    this.isDatabaseValid = dbFileParam && dbFileParam.database !== undefined;
  }

  // 修改密码弹框
  private showChangePasswordDialog() {
    this.changePasswordDialogController.open();
  }

  // 修改密码
  private handlePasswordChange() {
    this.promptAction.showToast({ message: $r('app.string.operation_success'), duration: 2000 });
    let filePath = FileService.getDbFileParam().filePath;
    FileService.getInstance().init();
    this.router.clear();
    this.router.pushUrl({
      url: 'pages/Password',
      params: {
        filePath: filePath,
      }
    });
  }

  // 取消修改密码
  private handleDialogCancel() {
    this.changePasswordDialogController.close();
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .margin({ left: 12 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => this.router.back())
        Text($r('app.string.Settings_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))


      List() {
        // 密码相关功能
        if (this.isDatabaseValid) {
          ListItemGroup() {
            // 修改主密码
            ListItem() {
              Row() {
                Text($r("app.string.change_password"))
                  .fontSize(16)
                  .flexGrow(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(20)
                  .height(20)
                  .margin({ right: 10 })
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                this.showChangePasswordDialog();
              })
            }
          }
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(12)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
          })
        } else {
          ListItem() {
            Text($r('app.string.database_not_opened'))
              .fontSize(16)
              .margin({ top: 20, bottom: 12 })
              .textAlign(TextAlign.Center)
              .width('100%')
              .fontColor($r('app.color.text_secondary'))
          }
        }
      }
      .width('100%')
      .height('auto')
      .layoutWeight(1)
      .margin({ top: 12 })
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}

/**
 * 主题选项接口
 */
export interface TimeOption {
  time: number;
  value: string;
}

/**
 * 主题选项接口
 */
export interface LengthOption {
  value: string;
}