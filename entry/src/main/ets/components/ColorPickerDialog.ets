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
  { id: 'red', value: '#E53935' },
  { id: 'orange', value: '#FB8C00' },
  { id: 'yellow', value: '#FDD835' },
  { id: 'lime', value: '#C0CA33' },
  { id: 'green', value: '#43A047' },
  { id: 'cyan', value: '#00ACC1' },
  { id: 'teal', value: '#00897B' },
  { id: 'blue', value: '#1E88E5' },
  { id: 'purple', value: '#8E24AA' },
  { id: 'pink', value: '#D81B60' },
  { id: 'brown', value: '#6D4C41' },
  { id: 'gray', value: '#757575' },
  { id: 'indigo', value: '#3949AB' },
  { id: 'black', value: '#212121' }
];

/**
 * 颜色选择结果
 */
export interface ColorPickerResult {
  foregroundColor: string | undefined;
  backgroundColor: string | undefined;
}

/**
 * HSV颜色转RGB
 */
function hsvToRgb(h: number, s: number, v: number): number[] {
  let r: number = 0;
  let g: number = 0;
  let b: number = 0;

  const i: number = Math.floor(h * 6);
  const f: number = h * 6 - i;
  const p: number = v * (1 - s);
  const q: number = v * (1 - f * s);
  const t: number = v * (1 - (1 - f) * s);

  switch (i % 6) {
    case 0:
      r = v; g = t; b = p;
      break;
    case 1:
      r = q; g = v; b = p;
      break;
    case 2:
      r = p; g = v; b = t;
      break;
    case 3:
      r = p; g = q; b = v;
      break;
    case 4:
      r = t; g = p; b = v;
      break;
    case 5:
      r = v; g = p; b = q;
      break;
  }

  return [Math.round(r * 255), Math.round(g * 255), Math.round(b * 255)];
}

/**
 * RGB颜色转HSV
 */
function rgbToHsv(r: number, g: number, b: number): number[] {
  r = r / 255;
  g = g / 255;
  b = b / 255;

  const max: number = Math.max(r, g, b);
  const min: number = Math.min(r, g, b);
  const d: number = max - min;

  let h: number = 0;
  const s: number = max === 0 ? 0 : d / max;
  const v: number = max;

  if (max !== min) {
    switch (max) {
      case r:
        h = (g - b) / d + (g < b ? 6 : 0);
        break;
      case g:
        h = (b - r) / d + 2;
        break;
      case b:
        h = (r - g) / d + 4;
        break;
    }
    h = h / 6;
  }

  return [h, s, v];
}

/**
 * 十六进制颜色转RGB
 */
function hexToRgb(hex: string): number[] {
  const result: RegExpExecArray | null = /^#?([a-f\d]{2})([a-f\d]{2})([a-f\d]{2})$/i.exec(hex);
  if (result) {
    return [
      parseInt(result[1], 16),
      parseInt(result[2], 16),
      parseInt(result[3], 16)
    ];
  }
  return [0, 0, 0];
}

/**
 * RGB转十六进制颜色
 */
function rgbToHex(r: number, g: number, b: number): string {
  const toHex: (n: number) => string = (n: number): string => {
    const hex: string = n.toString(16);
    return hex.length === 1 ? '0' + hex : hex;
  };
  return '#' + toHex(r) + toHex(g) + toHex(b);
}

@CustomDialog
export struct ColorEditDialog {
  @State selectedFgColor: string | undefined = undefined;
  @State selectedBgColor: string | undefined = undefined;
  @State currentTabIndex: number = 0; // 0: 前景色, 1: 背景色
  
  // HSV值 (h: 0-1, s: 0-1, v: 0-1)
  @State hue: number = 0;
  @State saturation: number = 1;
  @State value: number = 1;
  
  // 拖拽位置 (相对于选择区域的百分比)
  @State colorAreaX: number = 1; // 饱和度位置
  @State colorAreaY: number = 0; // 明度位置
  @State huePosition: number = 0; // 色相位置
  
  // 初始颜色值 - 使用 @Prop 实现从父组件同步
  @Prop initialFgColor: string | undefined = undefined;
  @Prop initialBgColor: string | undefined = undefined;
  
  // 回调函数
  public onConfirm: (result: ColorPickerResult) => void = (): void => {};
  public onCancel: () => void = (): void => {};
  
  private controller: CustomDialogController;
  
  // 颜色选择区域实际尺寸
  private colorAreaWidth: number = 0;
  private colorAreaHeight: number = 200;
  private hueBarWidth: number = 0;
  private hueBarHeight: number = 24;
  
  aboutToAppear(): void {
    this.selectedFgColor = this.initialFgColor;
    this.selectedBgColor = this.initialBgColor;
    this.updateHsvFromCurrentColor();
  }
  
  /**
   * 从当前选中颜色更新HSV值
   */
  private updateHsvFromCurrentColor(): void {
    const currentColor: string | undefined = this.getCurrentSelectedColor();
    if (currentColor) {
      const rgb: number[] = hexToRgb(currentColor);
      const hsv: number[] = rgbToHsv(rgb[0], rgb[1], rgb[2]);
      this.hue = hsv[0];
      this.saturation = hsv[1];
      this.value = hsv[2];
      this.colorAreaX = this.saturation;
      this.colorAreaY = 1 - this.value;
      this.huePosition = this.hue;
    } else {
      // 默认红色
      this.hue = 0;
      this.saturation = 1;
      this.value = 1;
      this.colorAreaX = 1;
      this.colorAreaY = 0;
      this.huePosition = 0;
    }
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
      this.selectedFgColor = colorValue;
    } else {
      this.selectedBgColor = colorValue;
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
   * 根据HSV计算当前颜色
   */
  private getCurrentColorFromHsv(): string {
    const rgb: number[] = hsvToRgb(this.hue, this.saturation, this.value);
    return rgbToHex(rgb[0], rgb[1], rgb[2]);
  }
  
  /**
   * 获取色相条的颜色数组
   */
  private getHueColors(): string[] {
    const colors: string[] = [];
    for (let i: number = 0; i <= 6; i++) {
      const rgb: number[] = hsvToRgb(i / 6, 1, 1);
      colors.push(rgbToHex(rgb[0], rgb[1], rgb[2]));
    }
    return colors;
  }
  
  /**
   * 构建颜色选择区域
   */
  @Builder
  buildColorArea() {
    Column() {
      // 主颜色选择区域（饱和度-明度）
      Stack() {
        // 底层：纯色背景
        Column()
          .width('100%')
          .height(this.colorAreaHeight)
          .borderRadius(12)
          .backgroundColor(this.getCurrentHueColor())
        
        // 中层：白色到透明渐变（饱和度）
        Column()
          .width('100%')
          .height(this.colorAreaHeight)
          .borderRadius(12)
          .linearGradient({
            direction: GradientDirection.Right,
            colors: [['#FFFFFF', 0], ['transparent', 1]]
          })
        
        // 顶层：透明到黑色渐变（明度）
        Column()
          .width('100%')
          .height(this.colorAreaHeight)
          .borderRadius(12)
          .linearGradient({
            direction: GradientDirection.Bottom,
            colors: [['transparent', 0], ['#000000', 1]]
          })
        
        // 选择指示器
        Column() {
          Column()
            .width(24)
            .height(24)
            .borderRadius(12)
            .border({ width: 3, color: '#FFFFFF' })
            .shadow({
              radius: 4,
              color: '#80000000',
              offsetX: 0,
              offsetY: 2
            })
        }
        .position({
          x: `${this.colorAreaX * 100}%`,
          y: `${this.colorAreaY * 100}%`
        })
        .translate({ x: -12, y: -12 })
      }
      .width('100%')
      .height(this.colorAreaHeight)
      .borderRadius(12)
      .clip(true)
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.colorAreaWidth = newValue.width as number;
        this.colorAreaHeight = newValue.height as number;
      })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Move || event.type === TouchType.Down) {
          if (this.colorAreaWidth > 0 && this.colorAreaHeight > 0) {
            const touchX: number = event.touches[0].x;
            const touchY: number = event.touches[0].y;
            
            // 计算相对位置 (0-1)
            this.colorAreaX = Math.max(0, Math.min(1, touchX / this.colorAreaWidth));
            this.colorAreaY = Math.max(0, Math.min(1, touchY / this.colorAreaHeight));
            
            // 更新饱和度和明度
            this.saturation = this.colorAreaX;
            this.value = 1 - this.colorAreaY;
            
            // 更新当前颜色
            this.toggleColor(this.getCurrentColorFromHsv());
          }
        }
      })
      
      // 色相选择条
      Column() {
        Stack() {
          // 色相渐变条
          Row()
            .width('100%')
            .height(this.hueBarHeight)
            .borderRadius(12)
            .linearGradient({
              direction: GradientDirection.Right,
              colors: this.getHueGradientColors()
            })
          
          // 色相指示器
          Column() {
            Column()
              .width(4)
              .height(this.hueBarHeight + 8)
              .borderRadius(2)
              .backgroundColor('#FFFFFF')
              .border({ width: 2, color: '#333333' })
          }
          .position({
            x: `${this.huePosition * 100}%`,
            y: -4
          })
          .translate({ x: -2 })
        }
        .width('100%')
        .height(this.hueBarHeight)
        .clip(false)
      }
      .width('100%')
      .margin({ top: 16 })
      .onAreaChange((_oldValue: Area, newValue: Area) => {
        this.hueBarWidth = newValue.width as number;
      })
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Move || event.type === TouchType.Down) {
          if (this.hueBarWidth > 0) {
            const touchX: number = event.touches[0].x;
            
            // 计算色相位置 (0-1)
            this.huePosition = Math.max(0, Math.min(1, touchX / this.hueBarWidth));
            this.hue = this.huePosition;
            
            // 更新当前颜色
            this.toggleColor(this.getCurrentColorFromHsv());
          }
        }
      })
    }
    .width('100%')
  }
  
  /**
   * 获取当前色相对应的纯色
   */
  private getCurrentHueColor(): string {
    const rgb: number[] = hsvToRgb(this.hue, 1, 1);
    return rgbToHex(rgb[0], rgb[1], rgb[2]);
  }
  
  /**
   * 获取色相渐变颜色数组
   */
  private getHueGradientColors(): Array<[string, number]> {
    const colors: Array<[string, number]> = [];
    for (let i: number = 0; i <= 6; i++) {
      const rgb: number[] = hsvToRgb(i / 6, 1, 1);
      colors.push([rgbToHex(rgb[0], rgb[1], rgb[2]), i / 6]);
    }
    return colors;
  }
  
  /**
   * 构建预设颜色列表
   */
  @Builder
  buildPresetColors() {
    Column() {
      // 分隔标题
      Row() {
        Text($r('app.string.color_preset'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .margin({ top: 16, bottom: 8 })
      
      // 预设颜色网格
      Flex({ wrap: FlexWrap.Wrap, justifyContent: FlexAlign.Start }) {
        // 无颜色选项
        Column() {
          Image($r('sys.media.ohos_ic_public_cancel'))
            .width(16)
            .height(16)
            .fillColor($r('app.color.text_secondary'))
        }
        .width(28)
        .height(28)
        .borderRadius(4)
        .backgroundColor($r('app.color.bg_secondary'))
        .justifyContent(FlexAlign.Center)
        .border(this.getCurrentSelectedColor() === undefined ?
          { width: 2, color: $r('app.color.button_bg_blue') } : { width: 0 })
        .margin({ right: 8, bottom: 8 })
        .onClick(() => {
          this.clearCurrentColor();
        })
        
        // 预设颜色
        ForEach(PRESET_COLORS, (color: ColorItem) => {
          Column() {
            if (this.getCurrentSelectedColor() === color.value) {
              Image($r('sys.media.ohos_ic_public_ok'))
                .width(14)
                .height(14)
                .fillColor(Color.White)
            }
          }
          .width(28)
          .height(28)
          .borderRadius(4)
          .backgroundColor(color.value)
          .justifyContent(FlexAlign.Center)
          .border(this.getCurrentSelectedColor() === color.value ?
            { width: 2, color: $r('app.color.button_bg_blue') } : { width: 0 })
          .margin({ right: 8, bottom: 8 })
          .onClick(() => {
            this.toggleColor(color.value);
            // 更新HSV值
            const rgb: number[] = hexToRgb(color.value);
            const hsv: number[] = rgbToHsv(rgb[0], rgb[1], rgb[2]);
            this.hue = hsv[0];
            this.saturation = hsv[1];
            this.value = hsv[2];
            this.colorAreaX = this.saturation;
            this.colorAreaY = 1 - this.value;
            this.huePosition = this.hue;
          })
        }, (color: ColorItem) => color.id)
      }
      .width('100%')
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
      
      // 前景色/背景色切换按钮
      Row() {
        Button($r('app.string.color_foreground'))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .borderRadius(20)
          .backgroundColor(this.currentTabIndex === 0 ? $r('app.color.button_bg_blue') : $r('app.color.bg_secondary'))
          .fontColor(this.currentTabIndex === 0 ? $r('app.color.button_text') : $r('app.color.text_primary'))
          .onClick(() => {
            if (this.currentTabIndex !== 0) {
              this.currentTabIndex = 0;
              this.updateHsvFromCurrentColor();
            }
          })
        
        Button($r('app.string.color_background'))
          .layoutWeight(1)
          .height(40)
          .fontSize(14)
          .borderRadius(20)
          .margin({ left: 12 })
          .backgroundColor(this.currentTabIndex === 1 ? $r('app.color.button_bg_blue') : $r('app.color.bg_secondary'))
          .fontColor(this.currentTabIndex === 1 ? $r('app.color.button_text') : $r('app.color.text_primary'))
          .onClick(() => {
            if (this.currentTabIndex !== 1) {
              this.currentTabIndex = 1;
              this.updateHsvFromCurrentColor();
            }
          })
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .margin({ top: 8 })
      .backgroundColor($r('app.color.bg_primary'))
      
      // 颜色选择区域
      Column() {
        this.buildColorArea()
        this.buildPresetColors()
      }
      .width('100%')
      .padding(16)
      .backgroundColor($r('app.color.bg_primary'))
      .layoutWeight(1)
      
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
    .height('85%')
    .backgroundColor($r('app.color.bg_primary'))
    .borderRadius(16)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
