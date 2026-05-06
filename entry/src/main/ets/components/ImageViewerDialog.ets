import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { CommonUtils } from '../common/utils';

const DOMAIN = 0x0000;
const TAG = 'ImageViewerDialog';

/**
 * 图片预览弹窗组件
 * 支持双指缩放、双击还原、从底部弹出
 * 仅提供预览和缩放功能
 * 通过 Base64 Data URI 加载图片
 */
@CustomDialog
export struct ImageViewerDialog {
  @State scaleValue: number = 1.0;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State imageDataUri: string = '';
  binaryFile: ArrayBuffer | null = null;
  binaryFileName: string = '';
  controller: CustomDialogController;
  private initialScale: number = 1.0;
  private initialOffsetX: number = 0;
  private initialOffsetY: number = 0;

  aboutToAppear() {
    this.convertToDataUri();
  }

  /**
   * ArrayBuffer → Base64 Data URI
   */
  private async convertToDataUri() {
    if (!this.binaryFile || this.binaryFile.byteLength <= 0) {
      this.isLoading = false;
      this.errorMessage = '无效的图片数据';
      return;
    }

    try {
      const mimeType = CommonUtils.getMimeTypeFromExtension(this.binaryFileName) || 'image/jpeg';

      const base64Helper = new util.Base64Helper();
      const uint8Array = new Uint8Array(this.binaryFile as ArrayBuffer);
      const base64Str: string = base64Helper.encodeToStringSync(uint8Array);
      this.imageDataUri = `data:${mimeType};base64,${base64Str}`;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to create Data URI: %{public}s', `${error}`);
      this.errorMessage = `${error}`;
    } finally {
      this.isLoading = false;
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
        Text(this.binaryFileName)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

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

      // 图片展示区域（clip=true 确保缩放后的图片不超出弹框范围）
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
        } else if (this.imageDataUri) {
          Image(this.imageDataUri)
            .objectFit(ImageFit.Contain)
            .scale({ x: this.scaleValue, y: this.scaleValue })
            .translate({ x: this.offsetX, y: this.offsetY })
            .gesture(
              GestureGroup(GestureMode.Exclusive,
                PinchGesture({ fingers: 2 })
                  .onActionStart(() => {
                    // 记录手势开始时的缩放值
                    this.initialScale = this.scaleValue;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    // event.scale 是从手势开始到当前的累计缩放比
                    const newScale = this.initialScale * event.scale;
                    if (newScale >= 1.0 && newScale <= 5.0) {
                      this.scaleValue = newScale;
                    }
                  })
                  .onActionEnd(() => {
                    if (this.scaleValue < 1.0) {
                      this.scaleValue = 1.0;
                    }
                  }),
                TapGesture({ count: 2 })
                  .onAction(() => {
                    if (this.scaleValue > 1.0) {
                      this.resetScale();
                    } else {
                      this.scaleValue = 2.0;
                    }
                  }),
                PanGesture({ fingers: 1 })
                  .onActionStart(() => {
                    // 记录手势开始时的偏移值
                    this.initialOffsetX = this.offsetX;
                    this.initialOffsetY = this.offsetY;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    if (this.scaleValue > 1.0) {
                      // event.offsetX/Y 是从手势开始到当前的累计偏移
                      this.offsetX = this.initialOffsetX + event.offsetX;
                      this.offsetY = this.initialOffsetY + event.offsetY;
                    }
                  })
              )
            )
        } else {
          Text('暂无图片可显示')
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
      }
      .layoutWeight(1)
      .width('100%')
      .clip(true)
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
