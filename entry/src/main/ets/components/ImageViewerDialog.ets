import { hilog } from '@kit.PerformanceAnalysisKit';
import { image } from '@kit.ImageKit';
import { CommonUtils } from '../common/utils';
import { fileIo as fs } from '@kit.CoreFileKit';

const DOMAIN = 0x0000;
const TAG = 'ImageViewerDialog';

/**
 * 图片预览弹窗组件
 * 支持双指缩放、双击还原、从底部弹出
 * 仅提供预览和缩放功能
 */
@CustomDialog
export struct ImageViewerDialog {
  @State pixelMap: image.PixelMap | null = null;
  @State scaleValue: number = 1.0;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  binaryFile: ArrayBuffer | null = null;
  controller: CustomDialogController;
  private tempFilePath: string = '';

  aboutToAppear() {
    this.loadImage();
  }

  aboutToDisappear() {
    if (this.pixelMap) {
      this.pixelMap.release();
    }
    this.cleanupTempFile();
  }

  /**
   * 加载图片：通过临时文件方式创建PixelMap，兼容性更好
   */
  private async loadImage() {
    if (!this.binaryFile || this.binaryFile.byteLength <= 0) {
      this.isLoading = false;
      this.errorMessage = 'Invalid image data';
      return;
    }

    try {
      // 将二进制数据写入临时文件
      const tempDir = CommonUtils.getContext().cacheDir;
      this.tempFilePath = tempDir + '/temp_preview_' + Date.now() + '.img';

      const file = await fs.open(this.tempFilePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
      await fs.write(file.fd, this.binaryFile);
      await fs.close(file.fd);

      // 通过文件描述符创建ImageSource，兼容性更好
      const readFile = await fs.open(this.tempFilePath, fs.OpenMode.READ_ONLY);
      const imageSource: image.ImageSource = image.createImageSource(readFile.fd);
      const decodingOptions: image.DecodingOptions = {
        editable: false,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
      };
      this.pixelMap = await imageSource.createPixelMap(decodingOptions);
      await imageSource.release();
      await fs.close(readFile.fd);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load image: %{public}s', `${error}`);
      this.errorMessage = `${error}`;
    } finally {
      this.isLoading = false;
      // 加载完成后立即清理临时文件
      this.cleanupTempFile();
    }
  }

  /**
   * 清理临时文件
   */
  private cleanupTempFile() {
    if (this.tempFilePath) {
      try {
        fs.unlinkSync(this.tempFilePath);
      } catch {
        // 忽略清理错误
      }
      this.tempFilePath = '';
    }
  }

  /**
   * 重置缩放和偏移
   */
  private resetScale() {
    this.scaleValue = 1.0;
    this.offsetX = 0;
    this.offsetY = 0;
  }

  build() {
    Column() {
      // 顶部标题栏（仅保留关闭按钮）
      Row() {
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

      // 图片展示区域
      Column() {
        if (this.isLoading) {
          LoadingProgress()
            .width(50)
            .height(50)
            .color($r('app.color.primary'))
        } else if (this.errorMessage) {
          Text(this.errorMessage)
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        } else if (this.pixelMap) {
          // 图片展示，支持双指缩放和双击还原
          Image(this.pixelMap)
            .objectFit(ImageFit.Contain)
            .scale({ x: this.scaleValue, y: this.scaleValue })
            .translate({ x: this.offsetX, y: this.offsetY })
            .gesture(
              GestureGroup(GestureMode.Exclusive,
                // 双指缩放
                PinchGesture({ fingers: 2 })
                  .onActionStart(() => {
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const newScale = this.scaleValue * event.scale;
                    if (newScale >= 1.0 && newScale <= 5.0) {
                      this.scaleValue = newScale;
                    }
                  })
                  .onActionEnd(() => {
                    if (this.scaleValue < 1.0) {
                      this.scaleValue = 1.0;
                    }
                  }),
                // 双击还原缩放
                TapGesture({ count: 2 })
                  .onAction(() => {
                    if (this.scaleValue > 1.0) {
                      this.resetScale();
                    } else {
                      this.scaleValue = 2.0;
                    }
                  }),
                // 拖拽偏移（缩放大于1时）
                PanGesture({ fingers: 1 })
                  .onActionUpdate((event: GestureEvent) => {
                    if (this.scaleValue > 1.0) {
                      this.offsetX += event.offsetX;
                      this.offsetY += event.offsetY;
                    }
                  })
              )
            )
        }
      }
      .layoutWeight(1)
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .backgroundColor($r("app.color.bg_primary"))
    }
    .width('100%')
    .height('80%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
