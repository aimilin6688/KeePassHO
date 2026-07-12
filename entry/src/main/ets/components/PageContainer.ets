import { NavigationManager } from '../common/utils/NavigationManager';
import { PageConfig, NavigationModeType } from '../common/constants/PageConfig';

/**
 * 页面容器
 *
 * 功能：
 * 1. 根据页面配置自动处理最大宽度限制
 * 2. 支持配置继承
 * 3. 统一页面样式
 */
@Component
export struct PageContainer {
  /**
   * 页面名称（用于获取配置）
   */
  @Prop pageName: string = '';

  /**
   * UI 上下文（用于计算宽度）
   */
  @Prop context: UIContext | null = null;

  @BuilderParam content: () => void;

  // 页面配置
  @State config: PageConfig | null = null;

  aboutToAppear() {
    // 获取页面的有效配置（处理继承）
    const navManager = NavigationManager.getInstance();
    this.config = navManager.getCurrentPageConfig(this.pageName);
  }

  build() {
    if (this.config && this.config.constrainMaxWidth) {
      // 需要限制最大宽度（首页相关页面）
      Row() {
        Blank()
          .layoutWeight(1)

        Column() {
          this.content();
        }
        .width('100%')
        .constraintSize({ maxWidth: this.config.maxWidth || 700 })
        .backgroundColor($r('app.color.bg_primary'))
        .padding(this.config.padding || 16)

        Blank()
          .layoutWeight(1)
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_secondary'))
    } else {
      // 不限制宽度（分栏模式或无需限制）
      Column() {
        this.content();
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.bg_primary'))
      .padding(this.config?.padding || 0)
    }
  }
}
