import display from '@ohos.display';

/**
 * 可拖拽的浮动按钮容器
 */
@Component
export struct DraggableButtonContainer {
  @State containerX: number = 0; // 容器X坐标
  @State containerY: number = 0; // 容器Y坐标
  @State isDragging: boolean = false; // 是否正在拖拽
  @State showAddButtons: boolean = false; // 是否显示添加按钮
  @State screenWidth: number = 360; // 屏幕宽度（默认值）
  @State screenHeight: number = 640; // 屏幕高度（默认值）
  private maxX: number = 0;
  private maxY: number = 0;
  private containerWidth: number = 75; // 容器宽度
  private containerHeight: number = 135; // 容器高度（收起时）
  private oldContainerX: number = 0;
  private oldContainerY: number = 0;
  // 回调函数
  onAddEntry?: () => void; // 添加条目回调
  onAddGroup?: () => void; // 添加分组回调
  onShowTotp?: () => void; // 显示TOTP回调

  aboutToAppear() {
    try {
      // 获取屏幕尺寸
      this.screenWidth = this.getUIContext().px2vp(display.getDefaultDisplaySync().width);
      this.screenHeight = this.getUIContext().px2vp(display.getDefaultDisplaySync().height);
    } catch (error) {
      console.error('获取屏幕尺寸失败:', error);
      // 使用默认值
    }
    // 初始位置在右下角
    this.updateInitialPosition();
  }

  /**
   * 更新初始位置
   */
  private updateInitialPosition() {
    this.maxX = this.screenWidth - this.containerWidth;
    this.maxY = this.screenHeight - this.containerHeight;
    this.containerX = this.maxX - 22;
    this.containerY = this.maxY - 32;
  }

  /**
   * 更新容器位置以确保不超出屏幕范围
   */
  private updateContainerPosition() {
    // 确保容器不超出屏幕底部
    if (this.containerY + this.containerHeight > this.screenHeight) {
      this.containerY = this.maxY;
    }

    // 确保容器不超出屏幕右侧
    if (this.containerX + this.containerWidth > this.screenWidth) {
      this.containerX = this.maxX;
    }
  }

  build() {
    Stack() {
      // 容器内容
      Column() {
        // 添加分组按钮
        if (this.showAddButtons) {
          Button() {
            Row() {
              Image($r('app.media.ic_folder'))
                .width(20)
                .height(20)
                .fillColor($r('app.color.button_text_blue'))
              Text($r('app.string.add_group_button'))
                .fontSize(14)
                .fontColor($r('app.color.button_text_blue'))
                .margin({ left: 8 })
            }
          }
          .width(120)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r("app.color.button_bg_blue"))
          .margin({ bottom: 8, top: 12 })
          .onClick(() => {
            this.showAddButtons = false;
            this.onAddGroup?.();
          })

          // 添加条目按钮
          Button() {
            Row() {
              Image($r('app.media.ic_file'))
                .width(20)
                .height(20)
                .fillColor($r("app.color.button_text_blue"))
              Text($r('app.string.add_entry_button'))
                .fontSize(14)
                .fontColor($r("app.color.button_text_blue"))
                .margin({ left: 8 })
            }
          }
          .width(120)
          .height(40)
          .borderRadius(20)
          .backgroundColor($r("app.color.button_bg_blue"))
          .margin({ bottom: 8, top: 4 })
          .onClick(() => {
            this.showAddButtons = false;
            this.onAddEntry?.();
          })
        }

        // TOTP按钮
        Button() {
          Image($r('app.media.ic_clock'))
            .width(28)
            .height(28)
            .fillColor(Color.White)
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor($r("app.color.button_bg_blue"))
        .margin({ bottom: 8 })
        .onClick(() => {
          this.onShowTotp?.();
        })
        .visibility(this.showAddButtons ? Visibility.Hidden : Visibility.Visible)

        // 主添加按钮
        Button() {
          Image($r('app.media.ic_add'))
            .width(28)
            .height(28)
            .fillColor(Color.White)
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor($r("app.color.button_bg_blue"))
        .visibility(this.showAddButtons ? Visibility.Hidden : Visibility.Visible)
        .onClick(() => {
          this.showAddButtons = !this.showAddButtons;
          // 切换状态后更新位置以确保不超出屏幕
          this.updateContainerPosition();
        })
      }
      .width(this.containerWidth)
      .height(this.containerHeight)
      .gesture(
        // 拖拽手势
        PanGesture({ fingers: 1, direction: PanDirection.All })
          .onActionStart(() => {
            this.isDragging = true;
            this.oldContainerX = this.containerX;
            this.oldContainerY = this.containerY;
          })
          .onActionUpdate((event: GestureEvent) => {
            if (this.isDragging) {
              // 计算新位置
              this.containerX = Math.max(0, Math.min(this.oldContainerX + event.offsetX, this.maxX));
              this.containerY = Math.max(0, Math.min(this.oldContainerY + event.offsetY, this.maxY));
            }
          })
          .onActionEnd(() => {
            this.isDragging = false;
          })
      )
      .position({x: this.containerX, y: this.containerY})
      .animation({
        duration: 200,
        curve: Curve.EaseInOut
      })
    }
    .width('auto')
    .height('auto')
  }
}