import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from '../common/utils/CommonUtils';
import { WebImageDownloader } from '../common/utils/WebImageDownloader';
import { UrlUtils } from '../common/utils/UrlUtils';

const DOMAIN = 0x0000;
const TAG = 'DownloadImageDialog';

@CustomDialog
export struct DownloadImageDialog {
  @State url: string = '';
  @State isDownloading: boolean = false;
  @State errorMessage: ResourceStr = '';
  controller: CustomDialogController;
  onSuccess: (imageData: string) => void = () => {
  };
  onCancel: () => void = () => {
  };

  /**
   * 下载图片
   */
  private async downloadImage() {
    if (!this.url.trim()) {
      this.errorMessage = $r("app.string.download_image_url_empty_message");
      return;
    }

    if (!UrlUtils.isValidUrl(this.url.trim())) {
      this.errorMessage = $r("app.string.download_image_url_invalid_message");
      return;
    }

    this.isDownloading = true;
    this.errorMessage = '';

    try {
      const imageData = await WebImageDownloader.downloadImage(this.url.trim(), 64);

      if (imageData) {
        this.controller.close();
        if (this.onSuccess) {
          this.onSuccess(imageData);
        }
        CommonUtils.showToast($r('app.string.download_image_success_message'));
      } else {
        this.errorMessage = $r('app.string.download_image_failed_message');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Download image failed: ' + error.message);
      this.errorMessage = error.message || $r('app.string.download_image_failed_message');
    } finally {
      this.isDownloading = false;
    }
  }

  /**
   * 清除错误信息
   */
  private clearError() {
    if (this.errorMessage) {
      this.errorMessage = '';
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r('app.string.download_image_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)

        Blank()

        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor('#666666')
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .onClick(() => {
          this.controller.close();
          if (this.onCancel) {
            this.onCancel();
          }
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r("app.color.bg_primary"))
      .borderRadius({ topLeft: 16, topRight: 16 })

      // 内容区域
      Column() {
        // URL输入框
        Column() {
          TextInput({
            placeholder: $r('app.string.download_image_url_placeholder'),
            text: this.url
          })
            .width('100%')
            .height(48)
            .fontColor($r('app.color.text_primary'))
            .borderRadius(8)
            .padding({ left: 12, right: 12 })
            .onChange((value: string) => {
              this.url = value;
              this.clearError();
            })
        }
        .width('100%')
        .padding({
          left: 24,
          right: 24,
          top: 16,
          bottom: 16
        })

        // 提示信息
        Text($r('app.string.download_image_tips'))
          .fontSize(12)
          .fontColor('#999999')
          .width('100%')
          .textAlign(TextAlign.Start)
          .padding({ left: 24, right: 24, bottom: 8 })

        // 错误信息显示
        if (this.errorMessage) {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor('#FF4444')
            .width('100%')
            .textAlign(TextAlign.Start)
            .padding({ left: 24, right: 24, bottom: 24 })
        }
      }
      .width('100%')
      .backgroundColor($r("app.color.bg_primary"))

      // 加载指示器
      if (this.isDownloading) {
        Row() {
          LoadingProgress()
            .width(32)
            .height(32)
            .color($r('app.color.button_bg_blue'))

          Text($r('app.string.loading_message'))
            .fontSize(14)
            .fontColor('#666666')
            .margin({ left: 12 })
        }
        .width('100%')
        .height(60)
        .justifyContent(FlexAlign.Center)
        .backgroundColor($r("app.color.bg_primary"))
      }
      // 底部按钮
      Row() {
        Button($r('app.string.cancel_button_text'))
          .onClick(() => {
            this.controller.close();
            if (this.onCancel) {
              this.onCancel();
            }
          })
          .backgroundColor(Color.Gray)
          .fontColor($r('app.color.button_text'))
          .width('45%')
          .height(40)
          .borderRadius(16)
          .enabled(!this.isDownloading)

        Button($r('app.string.download_button_text'))
          .enabled(!this.isDownloading && this.url.trim().length > 0)
          .onClick(() => {
            this.downloadImage();
          })
          .backgroundColor(!this.isDownloading && this.url.trim().length > 0 ? $r("app.color.button_bg_blue") : $r("app.color.button_bg_disabled"))
          .fontColor($r('app.color.button_text'))
          .width('45%')
          .height(40)
          .borderRadius(16)
      }
      .width('100%')
      .padding({
        left: 24,
        right: 24,
        top: 16,
        bottom: 30
      })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor($r("app.color.bg_primary"))
    }
    .width('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
  }
}