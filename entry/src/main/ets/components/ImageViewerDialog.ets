import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { matrix4 } from '@kit.ArkUI';
import { deviceInfo, BusinessError } from '@kit.BasicServicesKit';
import { image } from '@kit.ImageKit';
import { CommonUtils, UIUtils, DialogWindowHelper } from '../common/utils';

const DOMAIN = 0x0000;
const TAG = 'ImageViewerDialog';

const MIN_SCALE: number = 1.0;
const MAX_SCALE: number = 5.0;
const DOUBLE_TAP_SCALE: number = 2.0;
const ROTATE_STEP: number = 90;
const TITLE_BAR_HEIGHT: number = 56;
const MAX_DATA_URI_SIZE: number = 10 * 1024 * 1024; // 超过 10MB 的图片直接走 Image Kit 解码

/**
 * 图片预览弹窗组件
 * 支持双指捏合缩放（捏合中心锚点）、单指 1:1 拖拽、双指旋转、90° 旋转按钮、双击缩放/复位
 * PC（2in1）模式下支持拖动标题栏移动弹窗位置
 * 通过 Base64 Data URI 加载图片
 */
@CustomDialog
export struct ImageViewerDialog {
  @State scaleValue: number = 1.0;
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State angleValue: number = 0;
  @State isLoading: boolean = true;
  @State errorMessage: string = '';
  @State imageDataUri: string = '';
  @State imagePixelMap: image.PixelMap | undefined = undefined; // HEIC/HEIF 解码后的位图
  @State dialogWidth: string | number = '100%'; // 弹框宽度
  @State dialogDragX: number = 0; // PC 模式弹窗水平拖拽偏移（vp）
  @State dialogDragY: number = 0; // PC 模式弹窗垂直拖拽偏移（vp）
  binaryFile: ArrayBuffer | null = null;
  binaryFileName: string = '';
  /**
   * 附件内容延迟提供者（S4 磁盘引用附件异步回读场景）：
   * 弹窗打开时才取值，binaryFile 为空时兜底调用
   */
  binaryFileProvider: (() => ArrayBuffer | null) | null = null;
  controller: CustomDialogController;
  private windowHelper: DialogWindowHelper = new DialogWindowHelper();
  private isPcMode: boolean = deviceInfo.deviceType === '2in1';
  private displayWidth: number = 0; // 图片展示区域宽度（vp）
  private displayHeight: number = 0; // 图片展示区域高度（vp）
  private contentWidth: number = 0; // Contain 适配后内容宽度（vp）
  private contentHeight: number = 0; // Contain 适配后内容高度（vp）
  private imageAspectRatio: number = 0; // 图片宽高比
  private pinchStartScale: number = 1.0;
  private pinchStartOffsetX: number = 0;
  private pinchStartOffsetY: number = 0;
  private panStartOffsetX: number = 0;
  private panStartOffsetY: number = 0;
  private rotateLastAngle: number = 0;
  private rootWidth: number = 0; // 弹窗根节点宽度（vp）
  private rootHeight: number = 0; // 弹窗根节点高度（vp）
  private dragStartDialogX: number = 0;
  private dragStartDialogY: number = 0;

  aboutToAppear() {
    // 注册窗口大小变化监听
    this.windowHelper.register(this.getUIContext(), () => {
      this.updateDialogWidth();
      this.clampDialogDrag();
    });
    // 计算弹框宽度
    this.updateDialogWidth();

    this.convertToDataUri();
  }

  aboutToDisappear() {
    this.windowHelper.unregister();
    // 释放 HEIC 解码位图
    if (this.imagePixelMap) {
      this.imagePixelMap.release().catch((error: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'Release pixel map failed: %{public}s', error.message);
      });
      this.imagePixelMap = undefined;
    }
  }

  /**
   * 更新弹框宽度
   */
  private updateDialogWidth(): void {
    const widthConfig = UIUtils.calculateDialogWidth(this.getUIContext(), this.windowHelper.windowWidth);
    this.dialogWidth = widthConfig.width;
  }

  /**
   * ArrayBuffer → Base64 Data URI（大图/HEIC/HEIF 走 Image Kit 解码为 PixelMap）
   */
  private async convertToDataUri() {
    // 磁盘引用附件：打开时经 provider 读取最新内容（构造期 binaryFile 可能为空）
    const binaryFile = this.binaryFile ??
      (this.binaryFileProvider ? this.binaryFileProvider() : null);
    if (!binaryFile || binaryFile.byteLength <= 0) {
      this.isLoading = false;
      this.errorMessage = '无效的图片数据';
      return;
    }

    try {
      // HEIC/HEIF：Image 组件不支持，使用 Image Kit 解码为 PixelMap 后显示
      if (this.isHeicFile()) {
        await this.decodeToPixelMap(binaryFile);
        return;
      }

      // 大图：Base64 峰值内存约为原始数据的 2.7 倍（原始数据 + Base64 串 + Data URI 串），
      // 低内存设备（模拟器/低端真机）易分配失败，直接走 Image Kit 降采样解码
      if (binaryFile.byteLength > MAX_DATA_URI_SIZE) {
        await this.decodeToPixelMap(binaryFile);
        return;
      }

      const mimeType = CommonUtils.getMimeTypeFromExtension(this.binaryFileName) || 'image/jpeg';

      const base64Helper = new util.Base64Helper();
      const uint8Array = new Uint8Array(binaryFile as ArrayBuffer);
      const base64Str: string = base64Helper.encodeToStringSync(uint8Array);
      this.imageDataUri = `data:${mimeType};base64,${base64Str}`;
    } catch (error) {
      // 低内存设备（模拟器/低端真机）Base64 分配失败属预期降级场景，走 Image Kit 解码兜底
      hilog.warn(DOMAIN, TAG, 'Failed to create Data URI: %{public}s', `${error}`);
      if (!this.isHeicFile() && !this.imagePixelMap) {
        try {
          await this.decodeToPixelMap(binaryFile);
          hilog.info(DOMAIN, TAG, 'Fallback Image Kit decode succeeded');
          return;
        } catch (fallbackError) {
          hilog.error(DOMAIN, TAG, 'Fallback decode failed: %{public}s', `${fallbackError}`);
        }
      }
      this.errorMessage = '图片加载失败';
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 是否为 HEIC/HEIF 图片（Image 组件不支持，需经 Image Kit 解码）
   */
  private isHeicFile(): boolean {
    const lowerName = this.binaryFileName.toLowerCase();
    return lowerName.endsWith('.heic') || lowerName.endsWith('.heif');
  }

  /**
   * Image Kit 解码为 PixelMap（HEIC/HEIF 及大图场景，内存占用远低于 Base64 Data URI）
   * 超过 2048px 的大图降采样解码，避免内存占用过高
   */
  private async decodeToPixelMap(binaryFile: ArrayBuffer): Promise<void> {
    const imageSource = image.createImageSource(binaryFile);
    try {
      const maxDimension = 2048;
      const sourceInfo = await imageSource.getImageInfo();
      const sourceWidth = sourceInfo.size.width;
      const sourceHeight = sourceInfo.size.height;
      const decodingOptions: image.DecodingOptions = {};
      if (sourceWidth > maxDimension || sourceHeight > maxDimension) {
        const scale = maxDimension / Math.max(sourceWidth, sourceHeight);
        decodingOptions.desiredSize = {
          width: Math.round(sourceWidth * scale),
          height: Math.round(sourceHeight * scale)
        };
      }
      this.imagePixelMap = await imageSource.createPixelMap(decodingOptions);
      const pixelMapInfo = await this.imagePixelMap.getImageInfo();
      if (pixelMapInfo.size.width > 0 && pixelMapInfo.size.height > 0) {
        this.imageAspectRatio = pixelMapInfo.size.width / pixelMapInfo.size.height;
        this.updateContentSize();
      }
    } finally {
      imageSource.release().catch((error: BusinessError) => {
        hilog.warn(DOMAIN, TAG, 'Release image source failed: %{public}s', error.message);
      });
    }
  }

  /**
   * 图片加载成功：记录宽高比并计算内容尺寸
   */
  private onImageLoaded(width: number, height: number): void {
    if (width > 0 && height > 0) {
      this.imageAspectRatio = width / height;
      this.updateContentSize();
    }
  }

  /**
   * 根据展示区域与图片宽高比，计算 Contain 适配后的内容尺寸
   */
  private updateContentSize(): void {
    if (this.imageAspectRatio > 0 && this.displayWidth > 0 && this.displayHeight > 0) {
      const areaRatio = this.displayWidth / this.displayHeight;
      if (this.imageAspectRatio > areaRatio) {
        this.contentWidth = this.displayWidth;
        this.contentHeight = this.displayWidth / this.imageAspectRatio;
      } else {
        this.contentHeight = this.displayHeight;
        this.contentWidth = this.displayHeight * this.imageAspectRatio;
      }
      this.clampOffsets();
    }
  }

  /**
   * 当前旋转 + 缩放后内容包围盒的半宽（vp）
   */
  private rotatedBoxHalfWidth(): number {
    const rad = this.angleValue * Math.PI / 180;
    return this.scaleValue *
      (Math.abs(this.contentWidth * Math.cos(rad)) + Math.abs(this.contentHeight * Math.sin(rad))) / 2;
  }

  /**
   * 当前旋转 + 缩放后内容包围盒的半高（vp）
   */
  private rotatedBoxHalfHeight(): number {
    const rad = this.angleValue * Math.PI / 180;
    return this.scaleValue *
      (Math.abs(this.contentWidth * Math.sin(rad)) + Math.abs(this.contentHeight * Math.cos(rad))) / 2;
  }

  /**
   * 边界限制：内容超出展示区域时允许拖动，未超出时该轴强制居中
   */
  private clampOffsets(): void {
    const maxX = Math.max(0, this.rotatedBoxHalfWidth() - this.displayWidth / 2);
    const maxY = Math.max(0, this.rotatedBoxHalfHeight() - this.displayHeight / 2);
    this.offsetX = Math.min(maxX, Math.max(-maxX, this.offsetX));
    this.offsetY = Math.min(maxY, Math.max(-maxY, this.offsetY));
  }

  /**
   * 构建变换矩阵：绕展示区域中心（组件锚点）缩放 + 旋转，再整体平移
   * 不使用 .scale()/.translate() 属性，避免 PanGesture 位移被缩放比补偿导致拖拽不跟手
   */
  private buildMatrix(): matrix4.Matrix4Transit {
    const rad = this.angleValue * Math.PI / 180;
    const cos = Math.cos(rad) * this.scaleValue;
    const sin = Math.sin(rad) * this.scaleValue;
    const ui = this.getUIContext();
    const tx = ui.vp2px(this.offsetX);
    const ty = ui.vp2px(this.offsetY);
    return matrix4.init([
      cos, sin, 0, 0,
      -sin, cos, 0, 0,
      0, 0, 1, 0,
      tx, ty, 0, 1
    ]);
  }

  /**
   * 应用增量旋转（deg，顺时针为正），保持锚点 (px, py)（vp，展示区域坐标系）处内容不动
   */
  private applyRotationDelta(delta: number, px: number, py: number): void {
    if (delta === 0) {
      return;
    }
    const rad = delta * Math.PI / 180;
    const cosD = Math.cos(rad);
    const sinD = Math.sin(rad);
    const cx = this.displayWidth / 2;
    const cy = this.displayHeight / 2;
    const vx = px - cx - this.offsetX;
    const vy = py - cy - this.offsetY;
    this.angleValue += delta;
    this.offsetX = (px - cx) - (vx * cosD - vy * sinD);
    this.offsetY = (py - cy) - (vx * sinD + vy * cosD);
    this.clampOffsets();
  }

  /**
   * 双击复位（保留旋转角度）
   */
  private animateReset(): void {
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.scaleValue = MIN_SCALE;
      this.offsetX = 0;
      this.offsetY = 0;
    });
  }

  /**
   * 双击放大：以点击位置为锚点缩放
   */
  private animateZoomIn(px: number, py: number): void {
    const cx = this.displayWidth / 2;
    const cy = this.displayHeight / 2;
    const k = this.scaleValue > 0 ? DOUBLE_TAP_SCALE / this.scaleValue : 1;
    const targetX = (1 - k) * (px - cx) + k * this.offsetX;
    const targetY = (1 - k) * (py - cy) + k * this.offsetY;
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.scaleValue = DOUBLE_TAP_SCALE;
      this.offsetX = targetX;
      this.offsetY = targetY;
      this.clampOffsets();
    });
  }

  /**
   * 旋转按钮：绕展示区域中心整体旋转 90°，当前偏移随视图一起旋转
   */
  private rotateByStep(): void {
    const rad = ROTATE_STEP * Math.PI / 180;
    const cosD = Math.cos(rad);
    const sinD = Math.sin(rad);
    const nx = this.offsetX * cosD - this.offsetY * sinD;
    const ny = this.offsetX * sinD + this.offsetY * cosD;
    this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
      this.angleValue += ROTATE_STEP;
      this.offsetX = nx;
      this.offsetY = ny;
      this.clampOffsets();
    });
  }

  /**
   * 旋转手势结束：角度吸附到最近的 90° 整数倍，避免图片停在任意角度
   */
  private snapRotation(): void {
    const snapped = Math.round(this.angleValue / 90) * 90;
    const delta = snapped - this.angleValue;
    if (delta === 0) {
      return;
    }
    const rad = delta * Math.PI / 180;
    const cosD = Math.cos(rad);
    const sinD = Math.sin(rad);
    const nx = this.offsetX * cosD - this.offsetY * sinD;
    const ny = this.offsetX * sinD + this.offsetY * cosD;
    this.getUIContext().animateTo({ duration: 150, curve: Curve.EaseOut }, () => {
      this.angleValue = snapped;
      this.offsetX = nx;
      this.offsetY = ny;
      this.clampOffsets();
    });
  }

  /**
   * PC 模式弹窗拖拽边界：保证标题栏始终在窗口内可见
   */
  private clampDialogDrag(): void {
    if (!this.isPcMode) {
      return;
    }
    const ui = this.getUIContext();
    const winW = ui.px2vp(this.windowHelper.windowWidth);
    const winH = ui.px2vp(this.windowHelper.windowHeight);
    if (winW <= 0 || winH <= 0 || this.rootWidth <= 0 || this.rootHeight <= 0) {
      return;
    }
    // Bottom 对齐 + 水平居中时根节点的原始位置
    const rootLeft = (winW - this.rootWidth) / 2;
    const rootTop = winH - this.rootHeight;
    const minX = -rootLeft;
    const maxX = winW - this.rootWidth - rootLeft;
    const minY = -rootTop;
    const maxY = this.rootHeight - TITLE_BAR_HEIGHT;
    this.dialogDragX = Math.min(maxX, Math.max(minX, this.dialogDragX));
    this.dialogDragY = Math.min(maxY, Math.max(minY, this.dialogDragY));
  }

  /**
   * 旋转手势锚点：旋转事件未提供捏合中心时回退到展示区域中心
   */
  private rotationAnchorX(pinchCenterX: number): number {
    return pinchCenterX > 0 ? pinchCenterX : this.displayWidth / 2;
  }

  private rotationAnchorY(pinchCenterY: number): number {
    return pinchCenterY > 0 ? pinchCenterY : this.displayHeight / 2;
  }

  build() {
    Column() {
      // 顶部标题栏（文件名 + 旋转 + 关闭；PC 模式下可拖拽移动弹窗）
      Row() {
        Text(this.binaryFileName)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .layoutWeight(1)

        Button() {
          Image($r('app.media.ic_rotate'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .margin({ right: 8 })
        .onClick(() => {
          this.rotateByStep();
        })

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
      .height(TITLE_BAR_HEIGHT)
      .padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r("app.color.bg_primary"))
      .borderRadius({ topLeft: 16, topRight: 16 })
      .gesture(
        PanGesture({ fingers: 1, distance: 2 })
          .onActionStart(() => {
            if (this.isPcMode) {
              this.dragStartDialogX = this.dialogDragX;
              this.dragStartDialogY = this.dialogDragY;
            }
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.isPcMode) {
              this.dialogDragX = this.dragStartDialogX + event.offsetX;
              this.dialogDragY = this.dragStartDialogY + event.offsetY;
              this.clampDialogDrag();
            }
          })
      )

      // 图片展示区域（clip=true 确保变换后的图片不超出弹框范围）
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
        } else if (this.imagePixelMap || this.imageDataUri) {
          Image(this.imagePixelMap ?? this.imageDataUri)
            .objectFit(ImageFit.Contain)
            .width('100%')
            .height('100%')
            .transform(this.buildMatrix())
            .onComplete((event) => {
              if (event) {
                this.onImageLoaded(event.width, event.height);
              }
            })
            .onError((error: ImageError) => {
              hilog.error(DOMAIN, TAG, 'Failed to load image: %{public}s', error.message);
              this.errorMessage = '图片加载失败';
            })
            .gesture(
              GestureGroup(GestureMode.Exclusive,
                RotationGesture({ angle: 5 })
                  .onActionStart(() => {
                    this.rotateLastAngle = 0;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    const delta = event.angle - this.rotateLastAngle;
                    this.rotateLastAngle = event.angle;
                    this.applyRotationDelta(delta,
                      this.rotationAnchorX(event.pinchCenterX),
                      this.rotationAnchorY(event.pinchCenterY));
                  })
                  .onActionEnd(() => {
                    this.snapRotation();
                  })
                  .onActionCancel(() => {
                    this.snapRotation();
                  }),
                PinchGesture({ fingers: 2 })
                  .onActionStart(() => {
                    this.pinchStartScale = this.scaleValue;
                    this.pinchStartOffsetX = this.offsetX;
                    this.pinchStartOffsetY = this.offsetY;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    // 以捏合中心为锚点缩放，保证缩放跟手
                    const target = Math.min(MAX_SCALE, Math.max(MIN_SCALE, this.pinchStartScale * event.scale));
                    const k = this.pinchStartScale > 0 ? target / this.pinchStartScale : 1;
                    const cx = this.displayWidth / 2;
                    const cy = this.displayHeight / 2;
                    this.scaleValue = target;
                    this.offsetX = (1 - k) * (event.pinchCenterX - cx) + k * this.pinchStartOffsetX;
                    this.offsetY = (1 - k) * (event.pinchCenterY - cy) + k * this.pinchStartOffsetY;
                    this.clampOffsets();
                  })
                  .onActionEnd(() => {
                    if (this.scaleValue <= MIN_SCALE) {
                      this.animateReset();
                    }
                  }),
                TapGesture({ count: 2 })
                  .onAction((event: GestureEvent) => {
                    if (this.scaleValue > MIN_SCALE) {
                      this.animateReset();
                    } else {
                      const location = event.tapLocation;
                      if (location) {
                        this.animateZoomIn(location.x, location.y);
                      } else {
                        this.animateZoomIn(this.displayWidth / 2, this.displayHeight / 2);
                      }
                    }
                  }),
                PanGesture({ fingers: 1 })
                  .onActionStart(() => {
                    this.panStartOffsetX = this.offsetX;
                    this.panStartOffsetY = this.offsetY;
                  })
                  .onActionUpdate((event: GestureEvent) => {
                    // 矩阵平移为屏幕空间 1:1 映射，无需缩放补偿
                    this.offsetX = this.panStartOffsetX + event.offsetX;
                    this.offsetY = this.panStartOffsetY + event.offsetY;
                    this.clampOffsets();
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
      .onAreaChange((_oldArea: Area, newArea: Area) => {
        const w = Number(newArea.width);
        const h = Number(newArea.height);
        if (w > 0 && h > 0 && (w !== this.displayWidth || h !== this.displayHeight)) {
          this.displayWidth = w;
          this.displayHeight = h;
          this.updateContentSize();
        }
      })
    }
    .width(this.dialogWidth)
    .height('80%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
    .translate({ x: this.dialogDragX, y: this.dialogDragY })
    .onAreaChange((_oldArea: Area, newArea: Area) => {
      this.rootWidth = Number(newArea.width);
      this.rootHeight = Number(newArea.height);
      this.clampDialogDrag();
    })
  }
}
