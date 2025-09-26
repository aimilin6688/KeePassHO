import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from '../../common/utils/CommonUtils';
import { Router } from '@kit.ArkUI';
import { IconResource } from '../../services/TypeDefined';
import { ImagePickerUtils } from '../../common/utils/ImagePickerUtils';
import { common } from '@kit.AbilityKit';
import { FileService } from '../../services/FileService';
import KdbxUtils from '../../common/utils/KdbxUtils';
import IconUtils from '../../common/utils/IconUtils';
import { ToastSaveDatabaseCallback } from '../../workers/callback/ToastSaveDatabaseCallback';

const DOMAIN = 0x0000;
const TAG = 'SettingCustomIcons';

@Entry
@Component
struct SettingCustomIcons {
  @State icons: IconResource[] = [];
  @State isUploading: boolean = false;
  @State selectIcons: Set<string | number> = new Set();
  // 图标大小
  private readonly iconSize: number = 52;
  private router: Router = this.getUIContext().getRouter();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  aboutToAppear() {
    this.icons = IconUtils.getAllIcons(true);
  }

  /**
   * 上传自定义图片
   */
  private async uploadCustomIcon() {
    this.isUploading = true;
    try {
      // 选择图片
      const images: string[] | null = await ImagePickerUtils.selectImage(this.context, 64);
      if (!images || images.length === 0) {
        return;
      }
      // 添加自定义图标到数据库
      KdbxUtils.addCustomIcon(FileService.getDatabase(), images, {
        onSuccess: () => {
          this.isUploading = false;
          this.icons = IconUtils.getAllIcons(true);
        },
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Upload custom icon failed：' + error.message);
      CommonUtils.showToast(error.message);
    } finally {
      this.isUploading = false;
    }
  }

  /**
   * 删除选中的图标
   */
  private deleteIcons() {
    // 删除弹框
    this.getUIContext().showAlertDialog({
      title: $r("app.string.dialog_confirm_title"),
      message: $r("app.string.dialog_delete_confirm_message"),
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {
        }
      },
      // 确认删除
      secondaryButton: {
        value: $r("app.string.confirm_button_text"),
        action: () => {
          let kdbx = FileService.getDatabase();
          this.selectIcons.forEach((iconId) => {
            kdbx.meta.customIcons.delete(iconId + "");
          });
          KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
            onSuccess: () => {
              this.icons = IconUtils.getAllIcons(true);
            }
          }));
        }
      }
    });
  }

  /**
   * 删除未使用的图标
   */
  private deleteNotUse() {
    // 删除弹框
    this.getUIContext().showAlertDialog({
      title: $r("app.string.dialog_confirm_title"),
      message: $r("app.string.dialog_delete_confirm_message"),
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r("app.string.confirm_button_text"),
        action: () => {
          let kdbx = FileService.getDatabase();
          kdbx.cleanup({ customIcons: true });
          KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
            onSuccess: () => {
              this.icons = IconUtils.getAllIcons(true);
            }
          }));
        }
      }
    });
  }

  private checkedIcon(iconId: string | number) {
    if (this.selectIcons.has(iconId)) {
      this.selectIcons.delete(iconId);
    } else {
      this.selectIcons.add(iconId);
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
        Text($r('app.string.Settings_custom_icons'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 12 })

        Blank()
        Button() {
          Image($r('app.media.ic_add'))
            .width(26)
            .height(26)
            .fillColor($r('app.color.text_primary'))
        }
        .width(48)
        .height(48)
        .margin({ right: 16 })
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .enabled(!this.isUploading)
        .onClick(() => {
          this.uploadCustomIcon();
        })
      }
      .width('100%')
      .height(56)

      // 图标网格
      Scroll() {
        Flex({ direction: FlexDirection.Row, wrap: FlexWrap.Wrap }) {
          ForEach(this.icons, (icon: IconResource) => {
            Column() {
              Stack() {
                Image(icon.resource)
                  .width(this.iconSize)
                  .height(this.iconSize)
                  .objectFit(ImageFit.Contain)

                Checkbox({ name: 'check_' + icon.id, group: 'icon_group' })
                  .key('key_' + icon.id)
                  .select(this.selectIcons.has(icon.id))
                  .selectedColor($r('app.color.button_bg_blue'))
                  .shape(CheckBoxShape.CIRCLE)
                  .width(16)
                  .height(16)
                  .position({ x: this.iconSize - 21, y: -2 })
                  .onClick(() => {
                    this.checkedIcon(icon.id);
                  })
              }
              .width(this.iconSize)
              .height(this.iconSize)
            }
            .onClick(() => {
              this.checkedIcon(icon.id);
            })
            .margin(8)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(8)
          })
        }
        .width('100%')
        .height('100%')
        .padding({
          top: 12,
          left: 12,
          right: 12,
          bottom: 100
        })
      }
      .width('100%')
      .height('100%')

      // 操作按钮
      Row() {
        // 删除未使用
        Button() {
          Row() {
            Text($r('app.string.delete_not_use'))
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
          this.deleteNotUse();
        })

        Blank()
        // 删除
        Button() {
          Row() {
            Text($r('app.string.delete_button_text'))
              .fontSize(16)
              .fontColor($r('app.color.button_text'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('45%')
        .height(40)
        .enabled(this.selectIcons.size > 0)
        .borderRadius(16)
        .backgroundColor($r('app.color.button_bg_blue'))
        .onClick(() => {
          this.deleteIcons();
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
    .borderRadius(16)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP,SafeAreaEdge.BOTTOM])
  }
}