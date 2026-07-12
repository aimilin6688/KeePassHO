import { UIUtils } from '../common/utils/UIUtils';
import { SettingDialogConstants } from '../common/constants/SettingDialogConstants';

/**
 * 设置弹框统一包装器
 *
 * 宽度规则：
 * - 屏幕宽度 > 700vp：使用固定宽度 700vp，圆角 16vp
 * - 屏幕宽度 ≤ 700vp：使用 100% 宽度，圆角 16vp
 */
@Component
export struct SettingDialogWrapper {
  @Prop title: ResourceStr = '';
  @Prop context: UIContext | null = null;
  @BuilderParam content: () => void;
  @Prop onClose: () => void = () => {};

  @State width: string | number = SettingDialogConstants.DIALOG_MAX_WIDTH;
  @State isPercentage: boolean = false;

  aboutToAppear() {
    if (this.context) {
      const widthConfig = UIUtils.calculateDialogWidth(this.context);
      this.width = widthConfig.width;
      this.isPercentage = widthConfig.isPercentage;
    }
  }

  build() {
    Column() {
      // 标题栏
      Row() {
        Text(this.title)
          .fontSize(SettingDialogConstants.TITLE_FONT_SIZE)
          .fontWeight(FontWeight.Medium)

        Blank()

        Image($r('app.media.ic_close'))
          .width(SettingDialogConstants.CLOSE_BUTTON_SIZE)
          .height(SettingDialogConstants.CLOSE_BUTTON_SIZE)
          .onClick(() => this.onClose())
      }
      .width('100%')
      .height(SettingDialogConstants.HEADER_HEIGHT)
      .padding({
        left: SettingDialogConstants.PADDING_WIDE,
        right: SettingDialogConstants.PADDING_WIDE
      })

      Divider()

      // 内容区
      Scroll() {
        Column() {
          this.content();
        }
        .width('100%')
        .padding(this.isPercentage
          ? SettingDialogConstants.PADDING_NARROW
          : SettingDialogConstants.PADDING_WIDE)
      }
      .layoutWeight(1)
    }
    .width(this.width)
    .maxHeight(SettingDialogConstants.DIALOG_MAX_HEIGHT_RATIO)
    .backgroundColor($r('app.color.bg_primary'))
    .borderRadius(SettingDialogConstants.CORNER_RADIUS)
    .shadow(this.isPercentage ? {} : {
      radius: SettingDialogConstants.SHADOW_RADIUS,
      color: $r('app.color.shadow'),
      offsetX: 0,
      offsetY: SettingDialogConstants.SHADOW_OFFSET_Y
    })
  }
}
