
@CustomDialog
export struct ContextLoadingDialog {
  @Link loadingMessage: string;
  private controller: CustomDialogController;

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
      .backgroundColor($r('app.color.card_background'))
      .borderRadius(8)
      .padding(16)
    }
    .width('100%')
    .height('30%')
    .justifyContent(FlexAlign.Center)
  }
}
