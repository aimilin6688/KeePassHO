import { SettingsService } from '../../services/SettingsService';
import { Router } from '@kit.ArkUI';
import { SupportService } from '../../services/SupportService';
import { LoadingDialog } from '../../components/loading/LoadingDialogUtils';
import { SyncSettingsService } from '../../services/store/SyncSettingsService';
import { CommonUtils } from '../../common/utils';


@Entry
@Component
struct SettingApplication {
  @State isHideSupportDialog: boolean = !SettingsService.KEY_SHOW_SUPPORT_DIALOG_DEFAULT;
  @State isLimitDbExt: boolean = SettingsService.KEY_APP_LIMIT_DB_EXT_DEFAULT;
  @State isSyncSetting: boolean = SettingsService.KEY_APP_SYNC_SETTING_ENABLE_DEFAULT;
  @State isHoldingHand: boolean = SettingsService.KEY_APP_HOLDING_HAND_ENABLE_DEFAULT;
  @State isEnableLocalCache: boolean = SettingsService.KEY_APP_ENABLE_LOCAL_CACHE_DEFAULT;
  private settingsService: SettingsService = SettingsService.getInstance();
  private router: Router = this.getUIContext().getRouter();

  aboutToAppear(): void {
    this.initSettings();
  }

  // 初始化设置信息
  private initSettings(): void {
    // 是否隐藏支持对话框
    this.settingsService.get(SettingsService.KEY_SHOW_SUPPORT_DIALOG, SettingsService.KEY_SHOW_SUPPORT_DIALOG_DEFAULT).then(result => {
      this.isHideSupportDialog = !result;
    });
    // 是否开启跨设备同步数据
    this.isSyncSetting = this.settingsService.getSync(SettingsService.KEY_APP_SYNC_SETTING_ENABLE, SettingsService.KEY_APP_SYNC_SETTING_ENABLE_DEFAULT);
    // 是否限制打开数据库后缀
    this.isLimitDbExt = this.settingsService.getSync(SettingsService.KEY_APP_LIMIT_DB_EXT, SettingsService.KEY_APP_LIMIT_DB_EXT_DEFAULT);
    // 智感握姿
    this.isHoldingHand = this.settingsService.getSync(SettingsService.KEY_APP_HOLDING_HAND_ENABLE, SettingsService.KEY_APP_HOLDING_HAND_ENABLE_DEFAULT);
    // 启用本地缓存
    this.isEnableLocalCache = this.settingsService.getSync(SettingsService.KEY_APP_ENABLE_LOCAL_CACHE, SettingsService.KEY_APP_ENABLE_LOCAL_CACHE_DEFAULT);
  }

  // 隐藏支持弹框
  private checkHideSupportDialog(): HitTestMode {
    if (!this.isHideSupportDialog == false) {
      return HitTestMode.Default;
    }
    // 开启隐藏时处理
    LoadingDialog.showLoading($r('app.string.loading_message')).then(() => {
      SupportService.isCanHideSupport().then(result => {
        // 已经使用过一段时间了,隐藏捐赠弹框
        if (result) {
          this.isHideSupportDialog = true;
          SettingsService.put(SettingsService.KEY_SHOW_SUPPORT_DIALOG, false);
        } else {
          CommonUtils.showToast($r('app.string.application_hide_support_tips'));
        }
        LoadingDialog.hideLoading();
      })
    });
    return HitTestMode.None;
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
        Text($r('app.string.Settings_application'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })
      }
      .width('100%')
      .height(56)


      List() {
        ListItemGroup() {
          // 隐藏支持对话框
          ListItem() {
            Row() {
              Column() {
                Text($r("app.string.application_hide_support"))
                  .fontSize(16)
                  .flexGrow(1)
                Text($r("app.string.application_hide_support_tips"))
                  .fontSize(12)
                  .fontColor($r("app.color.text_secondary"))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .flexGrow(1)
              .layoutWeight(1)

              Blank()

              Toggle({ type: ToggleType.Switch, isOn: this.isHideSupportDialog })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onTouchIntercept(() => {
                  return this.checkHideSupportDialog();
                })
                .onChange((isOn: boolean) => {
                  this.isHideSupportDialog = isOn;
                  SettingsService.put(SettingsService.KEY_SHOW_SUPPORT_DIALOG, !isOn);
                })
            }
            .width('100%')
            .padding(16)
          }

          // 限制打开数据库后缀
          ListItem() {
            Row() {
              Column() {
                Text($r("app.string.application_limit_db_ext"))
                  .fontSize(16)
                  .flexGrow(1)
                Text($r("app.string.application_limit_db_ext_tips"))
                  .fontSize(12)
                  .fontColor($r("app.color.text_secondary"))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .flexGrow(1)
              .layoutWeight(1)

              Blank()

              Toggle({ type: ToggleType.Switch, isOn: this.isLimitDbExt })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.settingsService.put(SettingsService.KEY_APP_LIMIT_DB_EXT, isOn);
                })
            }
            .width('100%')
            .padding(16)
          }

          // 跨设备同步数据
          ListItem() {
            Row() {
              Column() {
                Text($r("app.string.application_sync_data"))
                  .fontSize(16)
                  .flexGrow(1)
                Text($r("app.string.application_sync_data_tips"))
                  .fontSize(12)
                  .fontColor($r("app.color.text_secondary"))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .flexGrow(1)
              .layoutWeight(1)

              Blank()

              Toggle({ type: ToggleType.Switch, isOn: this.isSyncSetting })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.settingsService.put(SettingsService.KEY_APP_SYNC_SETTING_ENABLE, isOn);
                  this.isSyncSetting = isOn;
                  // 开启同步时，触发全量同步
                  if (this.isSyncSetting) {
                    LoadingDialog.showLoading($r("app.string.application_sync_loading")).then(() => {
                      SyncSettingsService.triggerFullSync().then(() => {
                        LoadingDialog.hideLoading();
                        CommonUtils.showToast($r("app.string.application_sync_complete"));
                      }).catch((error: Error) => {
                        LoadingDialog.hideLoading();
                        CommonUtils.showToast(error.message);
                      });
                    });
                  }
                })
            }
            .width('100%')
            .padding(16)
          }

          // 启用智感握姿
          ListItem() {
            Row() {
              Column() {
                Text($r("app.string.application_holding_hand"))
                  .fontSize(16)
                  .flexGrow(1)
                Text($r("app.string.application_holding_hand_tips"))
                  .fontSize(12)
                  .fontColor($r("app.color.text_secondary"))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .flexGrow(1)
              .layoutWeight(1)

              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.isHoldingHand })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.isHoldingHand = isOn;
                  this.settingsService.put(SettingsService.KEY_APP_HOLDING_HAND_ENABLE, isOn);
                })
            }
            .width('100%')
            .padding(16)
          }

          // 禁用本地缓存
          ListItem() {
            Row() {
              Column() {
                Text($r("app.string.application_enable_local_cache"))
                  .fontSize(16)
                  .flexGrow(1)
                Text($r("app.string.application_enable_local_cache_tips"))
                  .fontSize(12)
                  .fontColor($r("app.color.text_secondary"))
                  .margin({ top: 4 })
              }
              .alignItems(HorizontalAlign.Start)
              .flexGrow(1)
              .layoutWeight(1)

              Blank()
              Toggle({ type: ToggleType.Switch, isOn: this.isEnableLocalCache })
                .selectedColor('#007DFF')
                .switchPointColor('#FFFFFF')
                .onChange((isOn: boolean) => {
                  this.isEnableLocalCache = isOn;
                  this.settingsService.put(SettingsService.KEY_APP_ENABLE_LOCAL_CACHE, isOn);
                })
            }
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
      .padding({ left: 12, right: 12 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}