import { CounterComponent, CounterType, PromptAction } from '@kit.ArkUI';
import { FileService } from '../../services/FileService';
import { KdbxUtils, CommonUtils, NavigationManager } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Consts, Kdbx } from 'kdbxweb';
import { EventBus } from '../../services/EventBus';
import { ToastSaveDatabaseCallback } from '../../workers/callback/ToastSaveDatabaseCallback';

const DOMAIN = 0x0000;
const TAG = 'SettingDatabaseMeta';

// SettingDatabaseMeta页面的Builder函数
@Builder
export function SettingDatabaseMetaBuilder(name: string, param: Object): void {
  SettingDatabaseMetaPage()
}

/**
 * 数据库元数据设置页面
 * 在右侧分栏中展示，与修改主密码页面保持一致
 */
@Component
struct SettingDatabaseMetaPage {
  build() {
    NavDestination() {
      SettingDatabaseMetaContent()
    }
    .title($r('app.string.Settings_database_metadata'))
    .backgroundColor($r('app.color.bg_primary'))
  }
}

@Component
export struct SettingDatabaseMetaContent {
  @State isModified: boolean = false;
  // 数据库元数据
  @State databaseName: string = '';
  @State databaseDescription: string = '';
  @State defaultUsername: string = '';
  // 历史记录设置
  @State historyMaxItems: number | undefined = undefined;
  @State historyMaxSize: number | undefined = undefined;
  @State recycleBinEnabled: boolean | undefined = undefined;
  // 其他设置
  @State compressionEnabled: boolean = true;
  // 本地属性
  private database: Kdbx | null = null;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private navPathStack: NavPathStack = NavigationManager.getInstance().getNavPathStack()!;
  onClose?: () => void;

  /**
   * 关闭当前页面（未指定外部回调时直接出栈）
   */
  private close(): void {
    if (this.onClose) {
      this.onClose();
      return;
    }
    this.navPathStack.pop();
  }

  aboutToAppear() {
    // 获取数据库对象
    this.database = FileService.getDatabase();

    if (this.database) {
      // 获取数据库元数据
      this.databaseName = this.database.meta.name || '';
      this.databaseDescription = this.database.meta.desc || '';
      this.defaultUsername = this.database.meta.defaultUser || '';
      // 历史记录信息
      this.historyMaxItems = this.database.meta.historyMaxItems || 0;
      this.historyMaxSize = this.database.meta.historyMaxSize ? Math.round(this.database.meta.historyMaxSize / 1024 / 1024) : 0;
      this.recycleBinEnabled = this.database.meta.recycleBinEnabled;
      // 其他设置
      this.compressionEnabled = Consts.CompressionAlgorithm.GZip === this.database.header.compression;
    }
  }

  onBackPress() {
    this.handleDialogCancel();
    return true;
  }

  /**
   * 保存数据库元数据
   */
  private saveMetadata() {
    if (!this.database) {
      CommonUtils.showToast({
        message: $r('app.string.invalid_database'),
        duration: 2000
      });
      return;
    }

    try {
      // 更新数据库元数据
      this.database.meta.name = this.databaseName;
      this.database.meta.desc = this.databaseDescription;
      this.database.meta.defaultUser = this.defaultUsername;

      //  历史记录信息
      this.database.meta.historyMaxItems = this.historyMaxItems ? this.historyMaxItems : undefined;
      this.database.meta.historyMaxSize = this.historyMaxSize ? this.historyMaxSize * 1024 * 1024 : undefined;
      this.database.meta.recycleBinEnabled = this.recycleBinEnabled;

      // 其他设置
      this.database.header.compression = this.compressionEnabled ? Consts.CompressionAlgorithm.GZip : Consts.CompressionAlgorithm.None;

      // 保存数据库
      KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
        onSuccess: () => {
          // 通知数据库已更新
          EventBus.emit<void>(EventBus.DATABASE_UPDATE);
          // 关闭当前页面
          this.close();
        }
      }));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update database metadata: %{public}s', error.message);
      CommonUtils.showToast({
        message: $r('app.string.save_failed_message', error.message),
        duration: 2000
      });
    }
  }

  /**
   * 返回弹框确认
   */
  private handleDialogCancel() {
    if (!this.isModified) {
      this.close();
      return;
    }
    CommonUtils.showUnSaveConfirm(this.getUIContext(), {
      onConfirm: () => {
        this.close();
      }
    });
  }

  build() {
    Column() {
      // 主要内容区域
      Scroll() {
        Column() {
          // 数据库名称
          Text($r('app.string.database_name'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ left: 16 })
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)

          TextInput({ placeholder: $r('app.string.database_name_placeholder'), text: this.databaseName })
            .type(InputType.Normal)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .margin({ top: 8, left: 16, right: 16 })
            .padding({ left: 12, right: 12 })
            .height(48)
            .width('100%')
            .borderRadius(8)
            .onChange((value) => {
              if (this.databaseName !== value) {
                this.isModified = true;
              }
              this.databaseName = value;
            })

          // 数据库描述
          Text($r('app.string.database_description'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)

          TextArea({ placeholder: $r('app.string.database_description_placeholder'), text: this.databaseDescription })
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.card_bg'))
            .margin({ top: 8, left: 16, right: 16 })
            .padding({ left: 12, right: 12 })
            .height(90)
            .width('100%')
            .borderRadius(8)
            .onChange((value) => {
              if (this.databaseDescription !== value) {
                this.isModified = true;
              }
              this.databaseDescription = value;
            })

          // 默认用户名
          Text($r('app.string.default_username'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .width('100%')
            .textAlign(TextAlign.Start)

          TextInput({ placeholder: $r('app.string.default_username_placeholder'), text: this.defaultUsername })
            .type(InputType.Normal)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.card_bg'))
            .margin({ top: 8, left: 16, right: 16 })
            .padding({ left: 12, right: 12 })
            .height(48)
            .width('100%')
            .borderRadius(8)
            .onChange((value) => {
              if (this.defaultUsername !== value) {
                this.isModified = true;
              }
              this.defaultUsername = value;
            })

          Column() {
            // 历史记录设置
            Column() {
              Row() {
                Column() {
                  Text($r("app.string.history_max_items"))
                    .fontSize(16)
                    .fontColor($r("app.color.text_primary"))

                  Text($r("app.string.history_max_items_tips"))
                    .fontSize(12)
                    .fontColor($r("app.color.text_secondary"))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .flexGrow(1)
                .layoutWeight(1)

                Blank()
                CounterComponent({
                  options: {
                    type: CounterType.COMPACT,
                    numberOptions: {
                      min: 0,
                      value: this.historyMaxItems,
                      max: 999,
                      onChange: (value) => {
                        if (this.historyMaxItems !== value) {
                          this.isModified = true;
                        }
                        this.historyMaxItems = value;
                      }
                    }
                  }
                })
                  .margin({ top: 10 })
              }
              .width("100%")
              .padding(12)

              Divider()
                .strokeWidth(1)
                .color($r('app.color.divider'))

              // 条目最大大小
              Row() {
                Column() {
                  Text($r("app.string.history_max_size"))
                    .fontSize(16)
                    .fontColor($r("app.color.text_primary"))

                  Text($r("app.string.history_max_size_tips"))
                    .fontSize(12)
                    .fontColor($r("app.color.text_secondary"))
                    .margin({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .flexGrow(1)
                .layoutWeight(1)

                Blank()
                CounterComponent({
                  options: {
                    type: CounterType.COMPACT,
                    numberOptions: {
                      min: 0,
                      value: this.historyMaxSize,
                      max: 999,
                      onChange: (value) => {
                        if (this.historyMaxSize !== value) {
                          this.isModified = true;
                        }
                        this.historyMaxSize = value;
                      }
                    },
                  }
                })
                  .margin({ top: 10 })
              }
              .width('100%')
              .padding(12)
            }
            .margin({ top: 12, bottom: 12 })
            .backgroundColor($r("app.color.card_bg"))
            .borderRadius(12)

            // 其他设置
            Column() {
              // 启用回收站
              Row() {
                Text($r("app.string.recycle_bin_enabled"))
                  .fontSize(16)
                  .flexGrow(1)
                Toggle({ type: ToggleType.Switch, isOn: this.recycleBinEnabled })
                  .selectedColor('#007DFF')
                  .switchPointColor('#FFFFFF')
                  .onChange((isOn: boolean) => {
                    if (this.recycleBinEnabled !== isOn) {
                      this.isModified = true;
                    }
                    this.recycleBinEnabled = isOn;
                  })
              }
              .justifyContent(FlexAlign.SpaceBetween)
              .width('100%')
              .padding(12)

              Divider()
                .strokeWidth(1)
                .color($r('app.color.divider'))

              // 启用压缩
              Row() {
                Column() {
                  Text($r("app.string.compression_enabled"))
                    .fontSize(16)
                    .flexGrow(1)

                  Text($r("app.string.compression_enabled_tips"))
                    .fontSize(12)
                    .fontColor($r("app.color.text_secondary"))
                    .padding({ top: 4 })
                }
                .alignItems(HorizontalAlign.Start)
                .flexGrow(1)
                .layoutWeight(1)

                Blank()
                Column() {
                  Toggle({ type: ToggleType.Switch, isOn: this.compressionEnabled })
                    .selectedColor('#007DFF')
                    .switchPointColor('#FFFFFF')
                    .onChange((isOn: boolean) => {
                      this.compressionEnabled = isOn;
                      this.isModified = true;
                    })
                }
              }.width("100%")
              .padding(12)
            }
            .margin({ top: 12, bottom: 12 })
            .backgroundColor($r("app.color.card_bg"))
            .borderRadius(12)
          }
          .width('100%')
          .height('auto')
          .margin({ top: 12 })
        }
        .width('100%')
        .height('100%')
        .margin({ top: 4 })
        // 底部留出悬浮按钮栏等高空间，防止最后的内容被按钮遮挡
        .padding({ left: 12, right: 12, bottom: 70 })
        // 顶部对齐，避免内容在滚动区域中被垂直居中
        .justifyContent(FlexAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      // 底部操作按钮
      Row() {
        Button($r('app.string.cancel_button_text'))
          .width('45%')
          .height(40)
          .fontSize(16)
          .fontColor($r('app.color.button_text'))
          .borderRadius(20)
          .backgroundColor(Color.Gray)
          .id('btn_cancel')
          .onClick(() => {
            this.handleDialogCancel();
          })

        Blank()

        Button($r('app.string.save_button_text'))
          .width('45%')
          .height(40)
          .fontSize(16)
          .fontColor($r('app.color.button_text'))
          .borderRadius(20)
          .backgroundColor($r('app.color.button_bg_blue'))
          .id('btn_save')
          .onClick(() => {
            this.saveMetadata();
          })
      }
      .width('100%')
      .height(60)
      .backgroundColor(Color.Transparent)
      .padding({
        top: 8,
        bottom: 8,
        left: 16,
        right: 16
      })
      .position({ x: 0, y: '100%' })
      .translate({ y: -70 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
