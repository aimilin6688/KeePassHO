import IconUtils from '../common/utils/IconUtils';
import { IconResource } from '../services/TypeDefined';
import { ImagePickerUtils } from '../common/utils/ImagePickerUtils';
import common from '@ohos.app.ability.common';
import KdbxUtils from '../common/utils/KdbxUtils';
import { Kdbx } from 'kdbxweb';
import { FileService } from '../services/FileService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from '../common/utils/CommonUtils';
import { DownloadImageDialog } from './DownloadImageDialog';

const DOMAIN = 0x0000;
const TAG = 'IconSelectorDialog';

@CustomDialog
export struct IconSelectorDialog {
  @State selectedIconId: number | string = -1;
  @State isUploading: boolean = false;
  @State icons: IconResource[] = [];

  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  public onIconSelected: (iconId: number | string) => void = () => {
  };
  public database: Kdbx | null = null; // 数据库实例
  // 每行显示的图标数量
  private readonly columnsPerRow: number = 5;
  // 图标大小
  private readonly iconSize: number = 40;
  // 图标间距
  private readonly iconGap: number = 16;

  // 下载图片对话框控制器
  private downloadImageDialogController: CustomDialogController = new CustomDialogController({
    builder: DownloadImageDialog({
      onSuccess: (imageData: string) => {
        this.saveCustomIcon([imageData]);
      },
      onCancel: () => {
        // 取消操作
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });
  private controller: CustomDialogController;

  aboutToAppear() {
    // 获取所有图标
    this.icons = IconUtils.getAllIcons();
  }

  /**
   * 上传自定义图片
   */
  private async uploadCustomIcon() {
    this.isUploading = true;
    ImagePickerUtils.selectImage(this.context, 64).then((images) => {
      this.saveCustomIcon(images);
    });
  }

  /**
   * 保存图标
   * @param images 图片BASE64数组
   */
  private async saveCustomIcon(images: string[] | null) {
    try {
      if (!images || images.length === 0) {
        return;
      }
      // 添加自定义图标到数据库
      KdbxUtils.addCustomIcon(FileService.getDatabase(), images, {
        onSuccess: () => {
          this.isUploading = false;
          this.icons = IconUtils.getAllIcons(true);
          CommonUtils.showToast($r('app.string.save_success'));
        },
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Save web icon failed：' + error.message);
      CommonUtils.showToast(error.message);
    } finally {
      this.isUploading = false;
    }
  }

  @Builder
  AddMenu() {
    Menu() {
      MenuItem({
        startIcon: $r('app.media.ic_add'),
        content: $r('app.string.add_from_local'),
      }).onClick(() => {
        this.uploadCustomIcon();
      })
      MenuItem({
        startIcon: $r('app.media.ic_download'),
        content: $r('app.string.add_from_web'),
      }).onClick(() => {
        this.downloadImageDialogController.open();
      })
    }
    .subMenuExpandingMode(SubMenuExpandingMode.EMBEDDED_EXPAND)
    .backgroundColor($r("app.color.bg_secondary"))
    .fontColor($r('app.color.text_primary'))
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r("app.string.select_icon"))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)

        Blank()

        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .onClick(() => {
          this.controller.close();
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r("app.color.bg_primary"))
      .borderRadius({ topLeft: 16, topRight: 16 })

      // 图标网格
      Grid() {
        ForEach(this.icons.length > 0 ? this.icons : IconUtils.getAllIcons(), (icon: IconResource) => {
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
            .backgroundColor(this.selectedIconId === icon.id ? '#E8F3FF' : 'transparent')
            .border(this.selectedIconId === icon.id ? {
              width: 2,
              color: '#007DFF',
              style: BorderStyle.Solid
            } : {
              width: 0
            })
            .onClick(() => {
              this.selectedIconId = icon.id;
              this.controller.close();
              if (this.onIconSelected) {
                this.onIconSelected(icon.id);
              }
            })
          }
        })

        GridItem() {
          // 上传自定义图标
          Button() {
            Image($r('app.media.ic_add'))
              .width(this.iconSize)
              .height(this.iconSize)
              .fillColor(Color.White)
          }
          .width(this.iconSize)
          .height(this.iconSize)
          .borderRadius(this.iconSize / 2)
          .backgroundColor($r("app.color.button_bg_blue"))
          .enabled(!this.isUploading)
          .bindMenu(this.AddMenu)
        }
      }
      .height('90%')
      .columnsTemplate('1fr '.repeat(this.columnsPerRow))
      .columnsGap(this.iconGap)
      .rowsGap(this.iconGap)
      .padding({ left: 24, right: 24, bottom: 16 })
    }
    .width('100%')
    .height('85%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
  }
}
