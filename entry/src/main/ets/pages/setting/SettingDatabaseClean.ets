import KdbxSaveService from '../../services/kdbx/KdbxSaveService';
import { FileService } from '../../services/FileService';
import { CommonUtils, KdbxUtils, ResourceManager } from '../../common/utils';
import { CounterComponent, CounterType } from '@kit.ArkUI';

// SettingDatabaseClean页面的Builder函数
@Builder
export function SettingDatabaseCleanBuilder(name: string, param: Object): void {
  SettingDatabaseCleanPage()
}

/**
 * 清理数据库页面
 * 在右侧分栏中展示，与默认保护字段页面保持一致
 */
@Component
struct SettingDatabaseCleanPage {
  build() {
    NavDestination() {
      SettingDatabaseCleanContent()
    }
    .title($r('app.string.Settings_clean_database'))
    .backgroundColor($r('app.color.bg_primary'))
  }
}

@Component
export struct SettingDatabaseCleanContent {
  @State isDatabaseValid: boolean = false;
  @State daysInput: number = 7;
  @State isCleaning: boolean = false;

  aboutToAppear(): void {
    const dbFileParam = FileService.getDbFileParam();
    this.isDatabaseValid = dbFileParam && dbFileParam.database !== undefined;
  }

  /**
   * 校验天数输入是否有效（>=0 均允许，0 表示清理所有历史记录）
   */
  private isDaysInputValid(): boolean {
    return this.daysInput >= 0;
  }

  /**
   * 弹出确认对话框，确认后执行清理
   */
  private doClean(): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.Settings_clean_history_confirm_title'),
      message: $r('app.string.Settings_clean_history_confirm_message'),
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.confirm_button_text'),
        action: () => {
          this.executeClean();
        }
      }
    });
  }

  /**
   * 执行清理：历史版本 + 孤儿附件 + 保存 + 提示
   */
  private executeClean(): void {
    this.isCleaning = true;
    try {
      const dbFileParam = FileService.getDbFileParam();
      const result = KdbxUtils.cleanHistoryAndBinaries(dbFileParam.database, this.daysInput);
      KdbxSaveService.saveDatabaseFromUi();
      if (result.deletedHistoryCount === 0 && result.deletedBinariesCount === 0) {
        CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.Settings_clean_no_record')) });
      } else {
        CommonUtils.showToast({
          message: ResourceManager.getString(
            $r('app.string.Settings_clean_success'),
            result.deletedHistoryCount,
            result.deletedBinariesCount
          )
        });
      }
    } catch (error) {
      const err = error as Error;
      CommonUtils.showToast({ message: err.message });
    } finally {
      this.isCleaning = false;
    }
  }

  /**
   * 清理历史记录分组 header：标题 + 说明文案
   */
  @Builder
  private cleanHistoryHeader(): void {
    Column() {
      Text($r('app.string.Settings_clean_history_title'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .width('100%')

      Text($r('app.string.Settings_clean_history_desc'))
        .fontSize(13)
        .fontColor($r('app.color.text_secondary'))
        .width('100%')
        .margin({ top: 4 })
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 12, bottom: 4 })
  }

  build() {
    Column() {
      if (this.isDatabaseValid) {
        // 使用 List + ListItemGroup 组织清理操作分组
        // 将「清理历史记录」作为一个独立分组，未来可在同级新增其他清理操作分组
        List() {
          // 分组：清理历史记录（天数输入 + 清理按钮同一行）
          ListItemGroup({ header: this.cleanHistoryHeader() }) {
            // 操作行：[天数加减器(可输入)] [天] [清理按钮] [Loading]
            ListItem() {
              Row() {
                CounterComponent({
                  options: {
                    type: CounterType.COMPACT,
                    numberOptions: {
                      min: 0,
                      value: this.daysInput,
                      max: 9999,
                      onChange: (value: number) => {
                        this.daysInput = value;
                      }
                    }
                  }
                })

                Text($r('app.string.Settings_clean_history_days_unit'))
                  .fontSize(16)
                  .margin({ left: 8 })

                Blank()

                if (this.isCleaning) {
                  LoadingProgress()
                    .width(24)
                    .height(24)
                    .margin({ right: 12 })
                }

                Button($r('app.string.Settings_clean_button'))
                  .type(ButtonType.Capsule)
                  .enabled(this.isDaysInputValid() && !this.isCleaning)
                  .onClick(() => {
                    this.doClean();
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom: 16 })
            }
          }
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)
          .divider({ strokeWidth: 1, color: $r('app.color.divider') })
        }
        .width('100%')
        .height('auto')
        .layoutWeight(1)
        .padding({ left: 12, right: 12, top: 4 })
        .clipContent(ContentClipMode.SAFE_AREA)
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
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
