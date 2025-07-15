

@Entry
@Component
export struct About {
  build() {
    Column() {
      Text('关于KeePassHO')
        .fontSize(20)
        .margin(10)

      Text('版本: 1.0.0')
        .fontSize(16)
        .margin(5)

      Text('一个基于HarmonyOS的KeePass密码管理器')
        .fontSize(16)
        .margin(5)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }
}
