@Builder
export function OpenMethodButton(icon: Resource, title: string|Resource, description: string|Resource, onClick: () => void) {
  Divider()
    .color($r("app.color.bg_primary"))
    .strokeWidth(1)
  Button() {
    Row() {
      Image(icon)
        .width(32)
        .height(32)
        .margin({ right: 16 })
        .fillColor($r('app.color.text_primary'))

      Column() {
        Text(title)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .alignSelf(ItemAlign.Start)

        Text(description)
          .fontSize(14)
          .opacity(0.6)
          .margin({ top: 4 })
          .fontColor($r('app.color.text_primary'))
          .alignSelf(ItemAlign.Start)
      }
      .alignItems(HorizontalAlign.Start)

      Blank()

      Image($r('app.media.ic_arrow_right'))
        .width(24)
        .height(24)
        .fillColor($r('app.color.text_primary'))
    }
    .width('100%')
    .padding({ left: 16, right: 16 })
  }
  .width('100%')
  .height(80)
  .backgroundColor($r("app.color.card_bg"))
  .margin({ top: 1 })
  .onClick(onClick)
}