import { UIUtils, DialogWindowHelper } from '../common/utils';

@CustomDialog
export struct ContextLoadingDialog {
  @Link loadingMessage: string;
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
      Row() {
        LoadingProgress()
          .width(24)
          .height(24)
          .color($r('app.color.text_primary'))

        Text(this.loadingMessage)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .margin({ left: 12 })
      }
      .backgroundColor($r("app.color.card_bg"))
      .borderRadius(20)
      .padding({left: 16, right: 16, top: 8, bottom: 8})
    }
    .width(this.dialogWidth)
    .height('30%')
    .justifyContent(FlexAlign.Center)
  }
}
