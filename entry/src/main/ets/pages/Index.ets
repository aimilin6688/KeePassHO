@Entry
@Component
struct Index {
  @State message: string = 'Hello KeePassHO';

  build() {
    RelativeContainer() {
      Text(this.message)
        .id('Hello KeePassHO')
        .fontSize($r('app.float.page_text_font_size'))
        .fontWeight(FontWeight.Bold)
        .alignRules({
          center: { anchor: '__container__', align: VerticalAlign.Center },
          middle: { anchor: '__container__', align: HorizontalAlign.Center }
        })
        .onClick(() => {
          this.message = 'Welcome';
        })
    }
    .height('100%')
    .width('100%')
  }
}