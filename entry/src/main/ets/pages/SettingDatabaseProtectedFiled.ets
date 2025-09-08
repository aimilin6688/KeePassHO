import { Router } from '@kit.ArkUI';
import { KdbxMemoryProtection } from 'kdbxweb';
import KdbxUtils from '../common/utils/KdbxUtils';
import { FileService } from '../services/FileService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ResourceManager from '../common/utils/ResourceManager';

const DOMAIN = 0x0000;
const TAG = 'SettingDatabaseKeyFunction';

@Entry
@Component
struct SettingDatabaseKeyFunction {
  @State isDatabaseValid: boolean = false;
  @State protectedField: KdbxMemoryProtection = {
    title: false,
    userName: false,
    password: true,
    url: false,
    notes: false
  };
  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();

  onPageShow(): void {
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
      this.promptAction.showToast({ message: $r("app.string.database_not_opened") });
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
      this.promptAction.showToast({ message: errorMsg, duration: 2000 });
    }
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
        Text($r("app.string.Settings_default_protected_field"))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)


      List() {
        if (this.isDatabaseValid) {
          // 主要内容区域
          ListItem(){
            Text($r("app.string.Setting_enable_protected_field_tips"))
              .fontSize(16)
          }
          .margin({ top: 12 })

          ListItemGroup() {
            // 标题启用保护
            ListItem() {
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
            }

            // 用户名启用保护
            ListItem() {
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
            }

            // 密码启用保护
            ListItem() {
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
            }

            // URL启用保护
            ListItem() {
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
            }

            // 备注启用保护
            ListItem() {
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
      .height('auto')
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}