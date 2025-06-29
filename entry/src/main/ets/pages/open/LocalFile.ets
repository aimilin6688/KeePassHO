import router from '@ohos.router';

@Entry
@Component
struct LocalFile {
  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_back'))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            router.back()
          })

        Text('选择本地文件')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r('app.color.card_background'))

      // 主要内容区域
      Column() {
        // TODO: 实现文件选择功能
        Text('文件选择功能开发中...')
          .fontSize(16)
          .opacity(0.6)
          .margin({ top: 20 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background_primary'))
    }
    .width('100%')
    .height('100%')
  }
}
