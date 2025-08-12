import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from '../common/utils/CommonUtils';
import { Router } from '@kit.ArkUI';
import { IconResource } from '../services/TypeDefined';
import { ImagePickerUtils } from '../common/utils/ImagePickerUtils';
import { common } from '@kit.AbilityKit';
import { FileService } from '../services/FileService';
import KdbxUtils from '../common/utils/KdbxUtils';
import IconUtils from '../common/utils/IconUtils';

const DOMAIN = 0x0000;
const TAG = 'SettingCustomIcons';

@Entry
@Component
struct SettingCustomIcons {
  @State icons : IconResource[] = [];
  @State isUploading: boolean = false;
  // 私有属性
  // 每行显示的图标数量
  private readonly columnsPerRow: number = 5;
  // 图标大小
  private readonly iconSize: number = 52;
  // 图标间距
  private readonly iconGap: number = 16;
  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();
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
        CommonUtils.showToast($r('app.string.upload_custom_icon_failed'));
        return;
      }
      // 添加自定义图标到数据库
      KdbxUtils.addCustomIcon(FileService.getDbFileParam().database, images, {
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

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
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
      .backgroundColor($r("app.color.card_bg"))

      // 图标网格
      Grid() {
        ForEach(this.icons, (icon: IconResource) => {
          GridItem() {
            Column() {
              Image(icon.resource)
                .width(this.iconSize)
                .height(this.iconSize)
                .objectFit(ImageFit.Contain)
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(8)
            .onClick(() => {
            })
          }
        })
      }
      .height('100%')
      .columnsTemplate('1fr '.repeat(this.columnsPerRow))
      .columnsGap(this.iconGap)
      .rowsGap(this.iconGap)
      .padding({ left: 24, right: 24, bottom: 60 })
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}