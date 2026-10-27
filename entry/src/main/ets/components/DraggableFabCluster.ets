/**
 * 可拖拽悬浮按钮组组件
 * 封装：展开/收起按钮组（添加分组/添加条目/从模板创建/TOTP/主按钮）、拖拽手势与边界钳制
 * 坐标通过 AppStorage('containerX'/'containerY') 持久化，与 DatabaseView 各自 @StorageLink 保持同步
 * 可移动边界 maxX/maxY 由父组件计算后传入
 */
@Component
export struct DraggableFabCluster {
  /** 容器X坐标（AppStorage 持久化） */
  @StorageLink("containerX") containerX: number = 0;
  /** 容器Y坐标（AppStorage 持久化） */
  @StorageLink("containerY") containerY: number = 0;
  /** 是否展开添加按钮组（与父组件双向同步，父级空白遮层依赖此状态） */
  @Link showAddButtons: boolean;
  /** 可移动x轴最大值（父组件按可用宽度计算） */
  @Prop maxX: number = 0;
  /** 可移动y轴最大值（父组件按可用高度计算） */
  @Prop maxY: number = 0;
  /** 整体可见性（移动/选择模式下隐藏） */
  @Prop visible: boolean = true;
  /** 数据库加载中（按钮置灰） */
  @Prop isLoading: boolean = false;
  /** 添加分组回调（父级弹出添加分组对话框） */
  onAddGroup: () => void = (): void => {
  };
  /** 添加条目回调（父级导航到条目编辑页） */
  onAddEntry: () => void = (): void => {
  };
  /** 从模板创建回调（父级弹出模板选择器） */
  onCreateFromTemplate: () => void = (): void => {
  };
  /** 添加 TAN 回调（父级弹出 TAN 向导，P2-4 M3） */
  onAddTan: () => void = (): void => {
  };
  /** 切换到 TOTP 根页面回调 */
  onShowTotp: () => void = (): void => {
  };
  /** 是否正在拖拽 */
  @State isDragging: boolean = false;
  private containerWidth: number = 75; // 容器宽度
  private containerHeight: number = 135; // 容器高度
  private oldContainerX: number = 0; // 拖拽起始X坐标
  private oldContainerY: number = 0; // 拖拽起始Y坐标

  build() {
    Column() {
      // 添加分组按钮
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
      .enabled(!this.isLoading)
      .visibility(this.showAddButtons ? Visibility.Visible : Visibility.None)
      .id('btn_add_group')
      .onClick(() => {
        this.showAddButtons = false;
        this.onAddGroup();
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
      .enabled(!this.isLoading)
      .visibility(this.showAddButtons ? Visibility.Visible : Visibility.None)
      .id('btn_add_entry')
      .onClick(() => {
        this.showAddButtons = false;
        this.onAddEntry();
      })

      // 从模板创建按钮
      Button() {
        Row() {
          Image($r('app.media.ic_copy'))
            .width(20)
            .height(20)
            .fillColor($r("app.color.button_text_blue"))
          Text($r('app.string.template_from_template'))
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
      .enabled(!this.isLoading)
      .visibility(this.showAddButtons ? Visibility.Visible : Visibility.None)
      .onClick(() => {
        this.showAddButtons = false;
        this.onCreateFromTemplate();
      })

      // 添加 TAN 按钮（P2-4 M3）
      Button() {
        Row() {
          Image($r('app.media.ic_tag'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.button_text_blue'))
          Text($r('app.string.tan_add_menu_text'))
            .fontSize(14)
            .fontColor($r('app.color.button_text_blue'))
            .margin({ left: 8 })
        }
      }
      .width(120)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r("app.color.button_bg_blue"))
      .margin({ bottom: 8, top: 4 })
      .enabled(!this.isLoading)
      .visibility(this.showAddButtons ? Visibility.Visible : Visibility.None)
      .onClick(() => {
        this.showAddButtons = false;
        this.onAddTan();
      })

      // 显示TOTP
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
      .margin({ bottom: 8, top: 8 })
      .enabled(!this.isLoading)
      .opacity(this.isLoading ? 0.5 : 1)
      .visibility(this.showAddButtons ? Visibility.Hidden : Visibility.Visible)
      .onClick(() => {
        this.onShowTotp();
      })

      // 主添加按钮
      Button() {
        Image(this.showAddButtons ? $r('app.media.ic_clear') : $r('app.media.ic_add'))
          .width(28)
          .height(28)
          .fillColor(Color.White)
      }
      .width(56)
      .height(56)
      .borderRadius(28)
      .backgroundColor(this.showAddButtons ? $r("app.color.error") : $r("app.color.button_bg_blue"))
      .enabled(!this.isLoading)
      .opacity(this.isLoading ? 0.5 : 1)
      .visibility(this.showAddButtons ? Visibility.Hidden : Visibility.Visible)
      .id('btn_add_fab')
      .onClick(() => {
        this.showAddButtons = true;
      })
    }
    .width(this.containerWidth)
    .height(this.showAddButtons ? 244 : this.containerHeight)
    .visibility(this.visible ? Visibility.Visible : Visibility.None)
    .zIndex(999)
    .gesture(
      // 拖拽手势（展开状态下禁用）
      PanGesture({ fingers: 1, direction: PanDirection.All })
        .onActionStart(() => {
          if (!this.showAddButtons) {
            this.isDragging = true;
            this.oldContainerX = this.containerX;
            this.oldContainerY = this.containerY;
          }
        })
        .onActionUpdate((event: GestureEvent) => {
          // 计算新位置
          if (this.isDragging) {
            this.containerX = Math.max(0, Math.min(this.oldContainerX + event.offsetX, this.maxX));
            this.containerY = Math.max(0, Math.min(this.oldContainerY + event.offsetY, this.maxY));
          }
        })
        .onActionEnd(() => {
          this.isDragging = false;
        })
    )
    .position({ x: this.containerX, y: this.containerY })
    .animation({
      duration: 200,
      curve: Curve.EaseInOut
    })
  }
}
