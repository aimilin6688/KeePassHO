/**
 * 批量选择模式底部操作栏
 * 展示「移动」「删除」「取消」按钮，绝对定位贴容器底部；无选中项时移动/删除置灰
 */
@Component
export struct SelectionModeBar {
  /** 是否存在选中项（控制移动/删除按钮可用性） */
  hasSelection: boolean = false;
  /** 是否显示"恢复到原位置"按钮（回收站分组内批量恢复） */
  showRestore: boolean = false;
  /** 批量恢复到原位置回调 */
  onBatchRestore: () => void = (): void => {
  };
  /** 批量移动回调 */
  onBatchMove: () => void = (): void => {
  };
  /** 批量删除（含确认）回调 */
  onBatchDelete: () => void = (): void => {
  };
  /** 退出选择模式回调 */
  onCancel: () => void = (): void => {
  };

  build() {
    Column() {
      Row() {
        // 恢复按钮（回收站内）
        if (this.showRestore) {
          Button($r('app.string.restore_button_text'))
            .layoutWeight(1)
            .height(40)
            .margin({ right: 8 })
            .borderRadius(20)
            .backgroundColor($r("app.color.button_bg_blue"))
            .fontColor($r("app.color.button_text_blue"))
            .enabled(this.hasSelection)
            .opacity(this.hasSelection ? 1 : 0.5)
            .id('btn_batch_restore')
            .onClick(() => {
              this.onBatchRestore();
            })
        }

        // 移动按钮
        Button($r('app.string.move_button_text'))
          .layoutWeight(1)
          .height(40)
          .margin({ right: 8 })
          .borderRadius(20)
          .backgroundColor($r("app.color.button_bg_blue"))
          .fontColor($r("app.color.button_text_blue"))
          .enabled(this.hasSelection)
          .opacity(this.hasSelection ? 1 : 0.5)
          .id('btn_batch_move')
          .onClick(() => {
            this.onBatchMove();
          })

        // 删除按钮
        Button($r('app.string.delete_button_text'))
          .layoutWeight(1)
          .height(40)
          .margin({ right: 8 })
          .borderRadius(20)
          .backgroundColor($r("app.color.error"))
          .fontColor(Color.White)
          .enabled(this.hasSelection)
          .opacity(this.hasSelection ? 1 : 0.5)
          .id('btn_batch_delete')
          .onClick(() => {
            this.onBatchDelete();
          })

        // 取消按钮
        Button($r('app.string.cancel_button_text'))
          .layoutWeight(1)
          .height(40)
          .borderRadius(20)
          .backgroundColor(Color.Gray)
          .fontColor(Color.White)
          .id('btn_cancel_selection')
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
