import { Router } from '@kit.ArkUI';
import ResourceManager from '../common/utils/ResourceManager';
import { ChangePasswordDialog } from '../components/ChangePasswordDialog';
import { AuthService } from '../services/AuthService';
import { FileService } from '../services/FileService';
import { RecentFilesService } from '../services/RecentFilesService';
import { SettingsService, UnlockAuthType } from '../services/SettingsService';


@Entry
@Component
struct SettingsDatabase {
  @State isDatabaseValid: boolean = false;
  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();
  private settingsService: SettingsService = SettingsService.getInstance();
  private changePasswordDialogController: CustomDialogController = new CustomDialogController({
    builder: ChangePasswordDialog({
      onSuccess: this.handlePasswordChange.bind(this)
    }),
    cancel: this.handleDialogCancel.bind(this),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });
  // 数据库导出类型
  private exportTypeOptions: Array<ExportTypeOptions> = [
    { value: ExportType.KDBX, type: ExportType.KDBX },
    { value: ExportType.XML, type: ExportType.XML },
    { value: ExportType.CSV, type: ExportType.CSV }
  ];

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

  /**
   * 密码修改成功回调
   */
  private handlePasswordChange() {
    this.promptAction.showToast({ message: $r('app.string.operation_success'), duration: 2000 });
    let filePath = FileService.getDbFileParam().filePath;
    FileService.close();
    this.router.clear();
    RecentFilesService.clearPassword(filePath);
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

  // 导出数据库
  private exportDatabase(exportType: ExportType) {
    this.router.pushUrl({
      url: 'pages/export/ExportDatabase',
      params: {
        exportType: exportType
      }
    });
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 12 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => this.router.back())
        Text($r('app.string.Settings_database'))
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

          // 数据库元数据设置
          ListItemGroup() {
            ListItem() {
              Row() {
                Text($r("app.string.Settings_database_metadata"))
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
                this.router.pushUrl({
                  url: 'pages/SettingDatabaseMeta',
                  params: {}
                });
              })
            }

            // 自定义图标
            ListItem() {
              Row() {
                Text($r("app.string.Settings_custom_icons"))
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
                this.router.pushUrl({
                  url: 'pages/SettingCustomIcons',
                  params: {}
                });
              })
            }

            // 数据库算法

          }
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(12)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
          })


          // 数据库导出
          ListItemGroup() {
            ListItem() {
              Row() {
                Text($r("app.string.Settings_database_output"))
                  .fontSize(16)
                  .flexGrow(1)
                Select(this.exportTypeOptions)
                  .value($r("app.string.please_select"))
                  .font({ size: 16 })
                  .selectedOptionFont({ size: 16 })
                  .optionFont({ size: 16 })
                  .backgroundColor($r("app.color.card_bg"))
                  .onSelect(async (index: number) => {
                    this.exportDatabase(this.exportTypeOptions[index].type);
                  })
              }
              .width('100%')
              .padding({
                left: 16,
                right: 16,
                top: 9,
                bottom: 9
              })
            }
          }
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(12)
          .divider({ strokeWidth: 1, color: $r('app.color.divider') })
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

export interface ExportTypeOptions {
  value: string;
  type: ExportType;
}

export enum ExportType {
  KDBX = "KDBX",
  XML = "XML",
  CSV = "CSV",
}
