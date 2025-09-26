import { CounterComponent, CounterType, PromptAction, Router } from '@kit.ArkUI';
import { FileService } from '../../services/FileService';
import KdbxUtils from '../../common/utils/KdbxUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Consts, Kdbx } from 'kdbxweb';
import { EventBus } from '../../services/EventBus';
import { CommonUtils } from '../../common/utils/CommonUtils';
import { ToastSaveDatabaseCallback } from '../../workers/callback/ToastSaveDatabaseCallback';

const DOMAIN = 0x0000;
const TAG = 'SettingDatabaseMeta';

@Entry
@Component
struct SettingDatabaseMeta {
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
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

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
      this.promptAction.showToast({
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
          // 返回上一页
          this.router.back();
        }
      }));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to update database metadata: %{public}s', error.message);
      this.promptAction.showToast({
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
      this.router.back();
      return;
    }
    CommonUtils.showUnSaveConfirm(this.getUIContext(), {
      onConfirm: () => {
        this.router.back();
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
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.handleDialogCancel();
          })

        Text($r('app.string.Settings_database_metadata'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)

      Scroll() {
        // 主要内容区域
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

          List() {
            // 历史记录设置
            ListItemGroup() {
              ListItem() {
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
              }

              // 条目最大大小
              ListItem() {
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
            }
            .margin({ top: 12, bottom: 12 })
            .backgroundColor($r("app.color.card_bg"))
            .borderRadius(12)
            .divider({
              strokeWidth: 1,
              color: $r('app.color.divider'),
            })

            // 其他设置
            ListItemGroup() {
              // 启用回收站
              ListItem() {
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
              }

              // 启用压缩
              ListItem() {
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
          .margin({ top: 12 })

          // 底部占位符
          List() {
          }
          .width('100%')
          .height('100')
        }
        .width('100%')
        .height('auto')
        .layoutWeight(1)
        .margin({ top: 12 })
        .padding({ left: 12, right: 12 })
      }.width('100%')
      .height('auto')


      // 操作按钮
      Row() {
        // 取消
        Button() {
          Row() {
            Text($r('app.string.cancel_button_text'))
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
          this.router.back();
        })

        Blank()
        // 保存
        Button() {
          Row() {
            Text($r('app.string.save_button_text'))
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
          this.saveMetadata();
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
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP,SafeAreaEdge.BOTTOM])
  }
}
