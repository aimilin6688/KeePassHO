import { Router } from '@kit.ArkUI';
import { KdbxMemoryProtection } from 'kdbxweb';
import { CommonUtils, KdbxUtils } from '../../common/utils';
import { FileService } from '../../services/FileService';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'SettingDatabaseProtectedFiled';

// SettingDatabaseProtectedFiled页面的Builder函数
@Builder
export function SettingDatabaseProtectedFiledBuilder(name: string, param: Object): void {
  SettingDatabaseProtectedFiledPage()
}

/**
 * 默认保护字段设置页面
 * 在右侧分栏中展示，与修改主密码页面保持一致
 */
@Component
struct SettingDatabaseProtectedFiledPage {
  build() {
    NavDestination() {
      Scroll() {
        SettingDatabaseProtectedFiledContent()
      }
      .width('100%')
      .height('100%')
      .scrollBar(BarState.Off)
    }
    .title($r('app.string.Settings_default_protected_field'))
    .backgroundColor($r('app.color.bg_primary'))
  }
}

@Component
export struct SettingDatabaseProtectedFiledContent {
  @State isDatabaseValid: boolean = false;
  @State protectedField: KdbxMemoryProtection = {
    title: false,
    userName: false,
    password: true,
    url: false,
    notes: false
  };
  private promptAction = this.getUIContext().getPromptAction();

  aboutToAppear(): void {
    const dbFileParam = FileService.getDbFileParam();
    this.isDatabaseValid = dbFileParam && dbFileParam.database !== undefined;
    if (this.isDatabaseValid && dbFileParam.database.meta.memoryProtection) {
      this.protectedField.title = dbFileParam.database.meta.memoryProtection.title ?? false;
      this.protectedField.userName = dbFileParam.database.meta.memoryProtection.userName ?? false;
      this.protectedField.password = dbFileParam.database.meta.memoryProtection.password ?? true;
      this.protectedField.url = dbFileParam.database.meta.memoryProtection.url ?? false;
      this.protectedField.notes = dbFileParam.database.meta.memoryProtection.notes ?? false;
    }
  }

  // 重新加密算法
  private save() {
    if (!this.isDatabaseValid) {
      CommonUtils.showToast({ message: $r("app.string.database_not_opened") });
      return;
    }
    try {
      const dbFileParam = FileService.getDbFileParam();
      dbFileParam.database.meta.memoryProtection = this.protectedField;
      hilog.debug(DOMAIN, TAG, "saveAlgoParams:%{public}s", JSON.stringify(this.protectedField));
      // 保存数据库
      KdbxUtils.saveDatabase();
    } catch (error) {
      const errorMsg = KdbxUtils.kdbxErrorMessage(error);
      hilog.error(DOMAIN, TAG, 'Failed to save database algo: %{public}s', errorMsg);
      CommonUtils.showToast({ message: errorMsg, duration: 2000 });
    }
  }

  build() {
    Column() {
      if (this.isDatabaseValid) {
        Text($r("app.string.Setting_enable_protected_field_tips"))
          .fontSize(16)
          .margin({ top: 12, left: 16, right: 16 })

        Column() {
          // 标题启用保护
          Row() {
            Column() {
              Text($r("app.string.title"))
                .fontSize(16)
                .flexGrow(1)
            }
            .alignItems(HorizontalAlign.Start)
            .flexGrow(1)
            .layoutWeight(1)

            Blank()
            Column() {
              Toggle({ type: ToggleType.Switch, isOn: this.protectedField.title })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.protectedField.title = isOn;
                  this.save();
                })
            }
          }.width("100%")
          .padding(12)

          Divider()
            .strokeWidth(1)
            .color($r('app.color.divider'))

          // 用户名启用保护
          Row() {
            Column() {
              Text($r("app.string.username"))
                .fontSize(16)
                .flexGrow(1)
            }
            .alignItems(HorizontalAlign.Start)
            .flexGrow(1)
            .layoutWeight(1)

            Blank()
            Column() {
              Toggle({ type: ToggleType.Switch, isOn: this.protectedField.userName })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.protectedField.userName = isOn;
                  this.save();
                })
            }
          }.width("100%")
          .padding(12)

          Divider()
            .strokeWidth(1)
            .color($r('app.color.divider'))

          // 密码启用保护
          Row() {
            Column() {
              Text($r("app.string.password"))
                .fontSize(16)
                .flexGrow(1)
            }
            .alignItems(HorizontalAlign.Start)
            .flexGrow(1)
            .layoutWeight(1)

            Blank()
            Column() {
              Toggle({ type: ToggleType.Switch, isOn: this.protectedField.password })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.protectedField.password = isOn;
                  this.save();
                })
            }
          }.width("100%")
          .padding(12)

          Divider()
            .strokeWidth(1)
            .color($r('app.color.divider'))

          // URL启用保护
          Row() {
            Column() {
              Text($r("app.string.url"))
                .fontSize(16)
                .flexGrow(1)
            }
            .alignItems(HorizontalAlign.Start)
            .flexGrow(1)
            .layoutWeight(1)

            Blank()
            Column() {
              Toggle({ type: ToggleType.Switch, isOn: this.protectedField.url })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.protectedField.url = isOn;
                  this.save();
                })
            }
          }.width("100%")
          .padding(12)

          Divider()
            .strokeWidth(1)
            .color($r('app.color.divider'))

          // 备注启用保护
          Row() {
            Column() {
              Text($r("app.string.notes"))
                .fontSize(16)
                .flexGrow(1)
            }
            .alignItems(HorizontalAlign.Start)
            .flexGrow(1)
            .layoutWeight(1)

            Blank()
            Column() {
              Toggle({ type: ToggleType.Switch, isOn: this.protectedField.notes })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.protectedField.notes = isOn;
                  this.save();
                })
            }
          }.width("100%")
          .padding(12)
        }
        .margin({ top: 12, bottom: 12 })
        .backgroundColor($r("app.color.card_bg"))
        .borderRadius(12)
      } else {
        Text($r('app.string.database_not_opened'))
          .fontSize(16)
          .margin({ top: 20, bottom: 12 })
          .textAlign(TextAlign.Center)
          .width('100%')
          .fontColor($r('app.color.text_secondary'))
      }
    }
    .width('100%')
    .backgroundColor($r("app.color.bg_primary"))
  }
}
