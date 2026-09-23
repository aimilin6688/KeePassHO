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
  // 添加图标成功后自增，驱动内容区刷新图标列表
  @State refreshTrigger: number = 0;

  /**
   * 标题栏右侧菜单区域：添加图标按钮
   */
  @Builder
  MenuBuilder() {
    Row() {
      ImageAddComponent({
        onSuccess: () => {
          this.refreshTrigger++;
        }
      })
        .width(24)
        .height(24)
    }
    .width(64)
    .height('100%')
    .justifyContent(FlexAlign.End)
    .alignItems(VerticalAlign.Center)
    .margin({ right: 16 })
  }

  build() {
    NavDestination() {
      SettingCustomIconsContent({ refreshTrigger: this.refreshTrigger })
    }
    .title($r('app.string.Settings_custom_icons'))
    .menus(this.MenuBuilder)
    .backgroundColor($r('app.color.bg_primary'))
  }
}

@Component
export struct SettingCustomIconsContent {
  @State icons: IconResource[] = [];
  @State selectIcons: Set<string | number> = new Set();
  // 添加图标成功后的刷新触发计数（由标题栏添加按钮驱动）
  @Prop @Watch('onRefreshTriggerChange') refreshTrigger: number = 0;
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

  /**
   * 添加图标成功后刷新列表
   */
  private onRefreshTriggerChange(): void {
    this.refreshIcons();
  }

  build() {
    Column() {
      // 图标网格：按列宽自动换行，顶部左侧对齐
      Grid() {
        ForEach(this.icons, (icon: IconResource) => {
          GridItem() {
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
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(8)
          }
          .margin(8)
        })
      }
      .columnsTemplate(`repeat(auto-fill, ${this.iconSize + 16}vp)`)
      .columnsGap(0)
      .rowsGap(0)
      .width('100%')
      .layoutWeight(1)
      // 底部留出悬浮按钮栏等高空间，防止最后的内容被按钮遮挡
      .padding({
        top: 12,
        left: 16,
        right: 16,
        bottom: 70
      })
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
          .id('btn_delete_unused')
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
          .id('btn_delete_icons')
          .onClick(() => {
            this.deleteIcons();
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
      // 脱离文档流悬浮，上移量 = 自身高度 60 + 底部留白 10
      .position({ x: 0, y: '100%' })
      .translate({ y: -70 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}