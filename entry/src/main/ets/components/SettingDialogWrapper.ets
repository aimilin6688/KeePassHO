import { UIUtils } from '../common/utils/UIUtils';
import { SettingDialogConstants } from '../common/constants/SettingDialogConstants';

/**
 * 设置弹框统一包装器
 *
 * 宽度规则：
 * - 屏幕宽度 > 700vp：使用固定宽度 700vp，圆角 16vp
 * - 屏幕宽度 ≤ 700vp：使用 100% 宽度，圆角 16vp
 *
 * 显示位置：底部弹框样式
 */
@Component
export struct SettingDialogWrapper {
  @Prop title: ResourceStr = '';
  @Prop context: UIContext | null = null;
  @BuilderParam content: () => void;
  onClose: () => void = () => {};

  @State dialogWidth: string | number = SettingDialogConstants.DIALOG_MAX_WIDTH;
  @State isPercentage: boolean = false;

  aboutToAppear() {
    if (this.context) {
      const widthConfig = UIUtils.calculateDialogWidth(this.context);
      this.dialogWidth = widthConfig.width;
      this.isPercentage = widthConfig.isPercentage;
    }
  }

  build() {
    Column() {
      // 顶部空白区域（点击可关闭）
      Column()
        .width('100%')
        .layoutWeight(1)
        .onClick(() => this.onClose())

      // 底部弹框内容
      Column() {
        // 拖拽条
        Row() {
          Row()
            .width(36)
            .height(4)
            .borderRadius(2)
            .backgroundColor($r('app.color.text_secondary'))
            .opacity(0.3)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 8, bottom: 4 })

        // 标题栏
        Row() {
          Text(this.title)
            .fontSize(SettingDialogConstants.TITLE_FONT_SIZE)
            .fontWeight(FontWeight.Medium)

          Blank()

          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(SettingDialogConstants.CLOSE_BUTTON_SIZE)
            .fontColor([$r('app.color.text_primary')])
            .onClick(() => this.onClose())
        }
        .width('100%')
        .height(SettingDialogConstants.HEADER_HEIGHT)
        .padding({
          left: SettingDialogConstants.PADDING_WIDE,
          right: SettingDialogConstants.PADDING_WIDE
        })

        Divider()

        // 内容区 - 使用Scroll包裹，但只在内容超出时才显示滚动条
        Scroll() {
          Column() {
            this.content();
          }
          .width('100%')
          .padding(this.isPercentage
            ? SettingDialogConstants.PADDING_NARROW
            : SettingDialogConstants.PADDING_WIDE)
        }
        .width('100%')
        .constraintSize({ maxHeight: '90%' })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
      }
      .width(this.dialogWidth)
      .backgroundColor($r('app.color.bg_primary'))
      .borderRadius({
        topLeft: SettingDialogConstants.CORNER_RADIUS,
        topRight: SettingDialogConstants.CORNER_RADIUS,
        bottomLeft: 0,
        bottomRight: 0
      })
      .shadow({
        radius: SettingDialogConstants.SHADOW_RADIUS,
        color: Color.Gray,
        offsetX: 0,
        offsetY: -SettingDialogConstants.SHADOW_OFFSET_Y
      })
      .padding({ bottom: 5 })
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.End)
  }
}
