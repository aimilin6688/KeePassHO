/**
 * 面包屑导航条组件
 * 展示当前分组导航路径，点击非末项跳转到对应分组
 * 顶部（布局流内）与底部（绝对定位浮层）两种用法：定位/可见性属性由使用方链式追加
 */

/**
 * 面包屑导航路径项接口
 */
export interface NavigationPathItem {
  id: string;
  name: string;
}

@Component
export struct BreadcrumbBar {
  /** 导航路径：[{id: 'root', name: '/'}] */
  @Prop navigationPath: NavigationPathItem[] = [];
  /** 滚动控制器：由使用方持有，便于路径变化后滚动到末尾 */
  scroller: Scroller = new Scroller();
  /** 点击非末项路径时的导航回调 */
  onNavigate: (groupId: string) => void = (groupId: string): void => {
  };

  build() {
    Scroll(this.scroller) {
      Row() {
        ForEach(this.navigationPath, (pathItem: NavigationPathItem, index: number) => {
          Row() {
            // 路径项
            Text(pathItem.name)
              .fontSize(14)
              .fontColor(index === this.navigationPath.length - 1 ? $r('app.color.text_primary') : $r('app.color.button_bg_blue'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .onClick(() => {
                // 仅非末项可点击导航
                if (index < this.navigationPath.length - 1) {
                  this.onNavigate(pathItem.id);
                }
              })

            // 分隔符（最后一项不显示）
            if (index < this.navigationPath.length - 1) {
              Text(' > ')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
            }
          }
        })
      }
      .justifyContent(FlexAlign.Start)
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(36)
    .padding({ left: 16, right: 16 })
    .backgroundColor($r("app.color.bg_secondary"))
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off) // 隐藏滚动条，保持美观
    .align(Alignment.Start) // 内容居左对齐
  }
}
