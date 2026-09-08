import { Router } from '@kit.ArkUI';
import { IconResource } from '../../services/TypeDefined';
import { FileService } from '../../services/FileService';
import { KdbxUtils, IconUtils } from '../../common/utils';
import { ToastSaveDatabaseCallback } from '../../workers/callback/ToastSaveDatabaseCallback';
import { ImageAddComponent } from '../../components/ImageAddComponent';

// SettingCustomIcons页面的Builder函数
@Builder
export function SettingCustomIconsBuilder(name: string, param: Object): void {
  SettingCustomIconsPage()
}

/**
 * 自定义图标管理页面
 * 在右侧分栏中展示，与修改主密码页面保持一致
 */
@Component
struct SettingCustomIconsPage {
  build() {
    NavDestination() {
      SettingCustomIconsContent()
    }
    .title($r('app.string.Settings_custom_icons'))
    .backgroundColor($r('app.color.bg_primary'))
  }
}

@Component
export struct SettingCustomIconsContent {
  @State icons: IconResource[] = [];
  @State selectIcons: Set<string | number> = new Set();
  // 图标大小
  private readonly iconSize: number = 52;

  aboutToAppear() {
    this.icons = IconUtils.getAllIcons(true);
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

  /**
   * 刷新图标列表
   */
  private refreshIcons() {
    this.icons = IconUtils.getAllIcons(true);
  }

  build() {
    Column() {
      // 图标网格
      Scroll() {
        Flex({
          direction: FlexDirection.Row,
          wrap: FlexWrap.Wrap,
          justifyContent: FlexAlign.Start,
          alignContent: FlexAlign.Start
        }) {
          // 添加图标按钮
          ImageAddComponent({
            onSuccess: () => {
              this.refreshIcons();
            }
          })
            .width(this.iconSize)
            .height(this.iconSize)
            .margin(8)

          ForEach(this.icons, (icon: IconResource) => {
            Column() {
              Stack() {
                Image(icon.resource)
                  .width(this.iconSize)
                  .height(this.iconSize)
                  .objectFit(ImageFit.Contain)

                Checkbox({ name: 'check_' + icon.id, group: 'icon_group' })
                  .id('key_' + icon.id)
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
        .height('auto')
        .padding({
          top: 12,
          left: 12,
          right: 12,
          bottom: 16
        })
      }
      .width('100%')
      .layoutWeight(1)
      .scrollBar(BarState.Auto)
      .edgeEffect(EdgeEffect.Spring)

      // 底部操作按钮
      Row() {
        Button($r('app.string.delete_not_use'))
          .width('45%')
          .height(40)
          .fontSize(16)
          .fontColor($r('app.color.button_text'))
          .borderRadius(20)
          .backgroundColor(Color.Gray)
          .onClick(() => {
            this.deleteNotUse();
          })

        Blank()

        Button($r('app.string.delete_button_text'))
          .width('45%')
          .height(40)
          .fontSize(16)
          .fontColor($r('app.color.button_text'))
          .borderRadius(20)
          .enabled(this.selectIcons.size > 0)
          .backgroundColor($r('app.color.button_bg_blue'))
          .onClick(() => {
            this.deleteIcons();
          })
      }
      .width('100%')
      .height(60)
      .padding({
        top: 8,
        bottom: 8,
        left: 16,
        right: 16
      })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
  }
}