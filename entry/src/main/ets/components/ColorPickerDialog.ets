/**
 * 颜色选择器对话框组件
 * 用于选择条目或分组的前景色和背景色
 */

/**
 * 预定义颜色项
 */
export interface ColorItem {
  id: string;
  value: string;
}

/**
 * 预定义的14种颜色（在浅色和深色模式下都适用）
 */
export const PRESET_COLORS: ColorItem[] = [
  { id: 'red', value: '#E74C3C' },
  { id: 'orange', value: '#E67E22' },
  { id: 'yellow', value: '#F1C40F' },
  { id: 'olive', value: '#8B8B00' },
  { id: 'green', value: '#27AE60' },
  { id: 'cyan', value: '#1ABC9C' },
  { id: 'teal', value: '#008080' },
  { id: 'blue', value: '#3498DB' },
  { id: 'purple', value: '#9B59B6' },
  { id: 'pink', value: '#E91E63' },
  { id: 'brown', value: '#8B4513' },
  { id: 'gray', value: '#95A5A6' },
  { id: 'navy', value: '#1E3A5F' },
  { id: 'black', value: '#2C3E50' }
];

/**
 * 颜色选择结果
 */
export interface ColorPickerResult {
  foregroundColor: string | undefined;
  backgroundColor: string | undefined;
}

@CustomDialog
export struct ColorEditDialog {
  @State selectedFgColor: string | undefined = undefined;
  @State selectedBgColor: string | undefined = undefined;
  @State currentTabIndex: number = 0; // 0: 前景色, 1: 背景色
  @State customColorInput: string = ''; // 自定义颜色输入
  
  // 初始颜色值 - 使用 @Prop 实现从父组件同步
  @Prop initialFgColor: string | undefined = undefined;
  @Prop initialBgColor: string | undefined = undefined;
  
  // 回调函数
  public onConfirm: (result: ColorPickerResult) => void = () => {};
  public onCancel: () => void = () => {};
  
  private controller: CustomDialogController;
  
  aboutToAppear(): void {
    this.selectedFgColor = this.initialFgColor;
    this.selectedBgColor = this.initialBgColor;
  }
  
  /**
   * 判断颜色是否被选中
   */
  private isColorSelected(colorValue: string, isForeground: boolean): boolean {
    if (isForeground) {
      return this.selectedFgColor === colorValue;
    }
    return this.selectedBgColor === colorValue;
  }
  
  /**
   * 获取当前选中的颜色
   */
  private getCurrentSelectedColor(): string | undefined {
    if (this.currentTabIndex === 0) {
      return this.selectedFgColor;
    }
    return this.selectedBgColor;
  }
  
  /**
   * 切换颜色选择
   */
  private toggleColor(colorValue: string): void {
    if (this.currentTabIndex === 0) {
      // 前景色
      if (this.selectedFgColor === colorValue) {
        this.selectedFgColor = undefined;
      } else {
        this.selectedFgColor = colorValue;
      }
    } else {
      // 背景色
      if (this.selectedBgColor === colorValue) {
        this.selectedBgColor = undefined;
      } else {
        this.selectedBgColor = colorValue;
      }
    }
  }
  
  /**
   * 清除当前选中颜色
   */
  private clearCurrentColor(): void {
    if (this.currentTabIndex === 0) {
      this.selectedFgColor = undefined;
    } else {
      this.selectedBgColor = undefined;
    }
  }
  
  /**
   * 应用自定义颜色
   */
  private applyCustomColor(): void {
    let colorValue = this.customColorInput.trim();
    if (colorValue && this.isValidColor(colorValue)) {
      // 确保颜色格式正确
      if (!colorValue.startsWith('#')) {
        colorValue = '#' + colorValue;
      }
      this.toggleColor(colorValue);
      this.customColorInput = '';
    }
  }
  
  /**
   * 验证颜色值是否有效
   */
  private isValidColor(color: string): boolean {
    // 支持 #RGB, #RRGGBB, #RRGGBBAA 格式
    let hexPattern = /^#?([0-9A-Fa-f]{3}|[0-9A-Fa-f]{6}|[0-9A-Fa-f]{8})$/;
    return hexPattern.test(color);
  }
  
  /**
   * 构建颜色选择网格
   */
  @Builder
  buildColorGrid() {
    Column() {
      // 预设颜色网格
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        // 无颜色选项
        Column() {
          Image($r('sys.media.ohos_ic_public_cancel'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor($r('app.color.bg_secondary'))
        .justifyContent(FlexAlign.Center)
        .border(this.getCurrentSelectedColor() === undefined ?
          { width: 2, color: $r('app.color.button_bg_blue') } : { width: 0 })
        .margin({ right: 12, bottom: 12 })
        .onClick(() => {
          this.clearCurrentColor();
        })
        
        // 预设颜色
        ForEach(PRESET_COLORS, (color: ColorItem) => {
          Column() {
            if (this.getCurrentSelectedColor() === color.value) {
              Image($r('sys.media.ohos_ic_public_ok'))
                .width(20)
                .height(20)
                .fillColor(Color.White)
            }
          }
          .width(40)
          .height(40)
          .borderRadius(20)
          .backgroundColor(color.value)
          .justifyContent(FlexAlign.Center)
          .border(this.getCurrentSelectedColor() === color.value ?
            { width: 2, color: $r('app.color.button_bg_blue') } : { width: 0 })
          .margin({ right: 12, bottom: 12 })
          .onClick(() => {
            this.toggleColor(color.value);
          })
        }, (color: ColorItem) => color.id)
      }
      .width('100%')
      
      // 自定义颜色输入
      Column() {
        Text($r('app.string.color_custom'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 8 })
          .alignSelf(ItemAlign.Start)
        
        Row() {
          TextInput({ text: this.customColorInput, placeholder: '#RRGGBB' })
            .layoutWeight(1)
            .height(40)
            .fontSize(14)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(8)
            .onChange((value: string) => {
              this.customColorInput = value;
            })
          
          Button($r('app.string.confirm_button_text'))
            .height(40)
            .margin({ left: 8 })
            .backgroundColor($r('app.color.button_bg_blue'))
            .fontColor($r('app.color.button_text'))
            .borderRadius(8)
            .enabled(this.customColorInput.trim().length > 0)
            .onClick(() => {
              this.applyCustomColor();
            })
        }
        .width('100%')
      }
      .width('100%')
      .margin({ top: 16 })
    }
    .width('100%')
  }
  
  /**
   * 构建预览区域
   */
  @Builder
  buildPreview() {
    Column() {
      Text($r('app.string.color_preview'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 8 })
        .alignSelf(ItemAlign.Start)
      
      Row() {
        // 预览卡片
        Row() {
          Image($r('app.media.ic_lock'))
            .width(24)
            .height(24)
            .fillColor(this.selectedFgColor || $r('app.color.text_primary'))
          
          Column() {
            Text($r('app.string.color_preview_title'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.selectedFgColor || $r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            
            Text($r('app.string.color_preview_subtitle'))
              .fontSize(12)
              .fontColor(this.selectedFgColor || $r('app.color.text_secondary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .margin({ left: 12 })
          .layoutWeight(1)
        }
        .width('100%')
        .padding(12)
        .borderRadius(12)
        .backgroundColor(this.selectedBgColor || $r('app.color.card_bg'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .backgroundColor($r('app.color.bg_secondary'))
    .borderRadius(12)
  }
  
  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r('app.string.color_picker_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
        
        Blank()
        
        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .onClick(() => {
          this.controller.close();
          if (this.onCancel) {
            this.onCancel();
          }
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r('app.color.bg_primary'))
      .borderRadius({ topLeft: 16, topRight: 16 })
      
      // 预览区域
      Column() {
        this.buildPreview()
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 16 })
      .backgroundColor($r('app.color.bg_primary'))
      
      // Tab 切换
      Tabs({ index: this.currentTabIndex }) {
        TabContent() {
          Column() {
            this.buildColorGrid()
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.bg_primary'))
        }
        .tabBar($r('app.string.color_foreground'))
        
        TabContent() {
          Column() {
            this.buildColorGrid()
          }
          .width('100%')
          .padding(16)
          .backgroundColor($r('app.color.bg_primary'))
        }
        .tabBar($r('app.string.color_background'))
      }
      .width('100%')
      .layoutWeight(1)
      .barMode(BarMode.Fixed)
      .animationDuration(200)
      .onChange((index: number) => {
        this.currentTabIndex = index;
      })
      .backgroundColor($r('app.color.bg_primary'))
      
      // 底部按钮
      Row() {
        Button($r('app.string.cancel_button_text'))
          .onClick(() => {
            this.controller.close();
            if (this.onCancel) {
              this.onCancel();
            }
          })
          .backgroundColor($r('app.color.bg_secondary'))
          .fontColor($r('app.color.text_primary'))
          .width('45%')
          .height(40)
          .borderRadius(20)
        
        Button($r('app.string.confirm_button_text'))
          .onClick(() => {
            this.controller.close();
            if (this.onConfirm) {
              this.onConfirm({
                foregroundColor: this.selectedFgColor,
                backgroundColor: this.selectedBgColor
              });
            }
          })
          .backgroundColor($r('app.color.button_bg_blue'))
          .fontColor($r('app.color.button_text'))
          .width('45%')
          .height(40)
          .borderRadius(20)
      }
      .width('100%')
      .padding({ left: 24, right: 24, top: 12, bottom: 30 })
      .justifyContent(FlexAlign.SpaceBetween)
      .backgroundColor($r('app.color.bg_primary'))
    }
    .width('100%')
    .height('80%')
    .backgroundColor($r('app.color.bg_primary'))
    .borderRadius(16)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
