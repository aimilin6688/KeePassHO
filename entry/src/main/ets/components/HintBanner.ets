/**
 * 底部提示条公共组件
 * 结构：主文案 + 右侧操作列（主操作按钮 + 次级操作文字）
 * 用于 DatabaseView 底部提示区（到期提醒条、子数据库配置提示条）
 */
@Component
export struct HintBanner {
  /** 主文案 */
  @Prop message: ResourceStr = '';
  /** 主操作按钮文案 */
  @Prop actionLabel: ResourceStr = '';
  /** 次级操作文案（如"今日不再提示"） */
  @Prop dismissLabel: ResourceStr = '';
  /** 主操作回调 */
  onAction: () => void = () => {
  };
  /** 次级操作回调 */
  onDismiss: () => void = () => {
  };

  build() {
    Row({ space: 12 }) {
      Text(this.message)
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .layoutWeight(1)
        .lineHeight(16)
      Column({ space: 2 }) {
        Button(this.actionLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .height(28)
          .padding({ left: 14, right: 14 })
          .backgroundColor($r('app.color.button_bg_blue'))
          .fontColor(Color.White)
          .onClick(() => {
            this.onAction();
          })
        Blank().height(10)
        Text(this.dismissLabel)
          .fontSize(11)
          .fontColor($r('app.color.text_secondary'))
          .onClick(() => {
            this.onDismiss();
          })
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 8 })
    .backgroundColor($r('app.color.bg_secondary'))
    .alignItems(VerticalAlign.Center)
    .borderRadius(16)
  }
}
