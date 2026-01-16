
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
      .backgroundColor($r("app.color.card_bg"))
      .borderRadius(20)
      .padding({left: 16, right: 16, top: 8, bottom: 8})
    }
    .width('100%')
    .height('30%')
    .justifyContent(FlexAlign.Center)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
