import { UIUtils, DialogWindowHelper } from '../common/utils';

/**
 * 解锁页数据库加载进度弹框（底部胶囊）：
 * 阶段文案 + 旋转图标；下载数据库阶段追加线性进度条与字节明细
 */
@CustomDialog
export struct LoadProgressDialog {
  @Link loadingMessage: string;
  /** 传输进度百分比（0~100）；-1 表示当前阶段无进度（仅旋转图标） */
  @Link progressPercent: number;
  /** 传输字节明细（如 "12 MB / 45 MB"）；空串隐藏 */
  @Link progressDetail: string;
  @State dialogWidth: string | number = '100%'; // 弹框宽度
  private controller: CustomDialogController;
  private windowHelper: DialogWindowHelper = new DialogWindowHelper();

  aboutToAppear() {
    // 注册窗口大小变化监听
    this.windowHelper.register(this.getUIContext(), () => {
      this.updateDialogWidth();
    });
    // 计算弹框宽度
    this.updateDialogWidth();
  }

  aboutToDisappear() {
    this.windowHelper.unregister();
  }

  /**
   * 更新弹框宽度
   */
  private updateDialogWidth(): void {
    const widthConfig = UIUtils.calculateDialogWidth(this.getUIContext(), this.windowHelper.windowWidth);
    this.dialogWidth = widthConfig.width;
  }

  build() {
    Column() {
      Column({ space: 8 }) {
        Row() {
          LoadingProgress()
            .width(24)
            .height(24)
            .color($r('app.color.text_primary'))

          Text(this.loadingMessage)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .margin({ left: 12 })
            .layoutWeight(1)
            .maxLines(2)

          if (this.progressDetail != '') {
            Text(this.progressDetail)
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ left: 8 })
          }
        }

        if (this.progressPercent >= 0) {
          Progress({ value: this.progressPercent, total: 100, type: ProgressType.Linear })
            .width('100%')
            .style({
              strokeWidth: 6,
              enableSmoothEffect: true
            })
            .color($r('app.color.primary'))
            .backgroundColor($r('app.color.bg_secondary'))
        }
      }
      .backgroundColor($r("app.color.card_bg"))
      .borderRadius(20)
      .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    }
    .width(this.dialogWidth)
    .height('30%')
    .justifyContent(FlexAlign.Center)
  }
}
