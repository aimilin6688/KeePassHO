/**
 * 移动模式底部浮动操作栏
 * 展示「移动到此处」与「取消」按钮，绝对定位贴容器底部
 */
@Component
export struct MoveModeBar {
  /** 移动到当前分组回调 */
  onMoveHere: () => void = (): void => {
  };
  /** 取消移动模式并返回源分组回调 */
  onCancel: () => void = (): void => {
  };

  build() {
    Column() {
      Row() {
        Button($r('app.string.move_here'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(40)
          .margin({ right: 8 })
          .borderRadius(20)
          .backgroundColor($r("app.color.button_bg_blue"))
          .fontColor($r("app.color.button_text_blue"))
          .id('btn_move_here')
          .onClick(() => {
            this.onMoveHere();
          })

        Button($r('app.string.cancel_button_text'), { type: ButtonType.Normal })
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.Gray)
          .fontColor(Color.White)
          .id('btn_cancel_move')
          .onClick(() => {
            this.onCancel();
          })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height(60)
    .padding({
      top: 8,
      bottom: 8,
      left: 16,
      right: 16
    })
    .position({ x: 0, y: '100%' })
    .translate({ y: -60 })
    .justifyContent(FlexAlign.Center)
  }
}
