import { IconUtils, UIUtils, DialogWindowHelper, CommonUtils } from '../common/utils';
import { IconResource } from '../services/TypeDefined';
import { Kdbx } from 'kdbxweb';
import { ImageAddComponent } from './ImageAddComponent';
import { BrandIconDef, BrandIcons } from '../common/utils/BrandIcons';
import KdbxSaveService from '../services/kdbx/KdbxSaveService';
import { FileService } from '../services/FileService';
import { window } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'IconSelectorDialog';

/**
 * 品牌图标网格 @Builder 按引用传参（$$）所需参数类型：
 * 按值传参时 @State 变化不会触发 @Builder 内 UI 刷新，搜索过滤会失效
 */
interface BrandGridParams {
  list: BrandIconDef[];
}

/**
 * 图标选择弹窗：三个页签
 *  - 标准图标：KeePass 内置图标 + 自定义图片添加
 *  - 国内常用 / 国外常用：内嵌品牌图标（rawfile/brand_icons），支持搜索；
 *    选中后转为数据库自定义图标并回调 UUID
 */
@CustomDialog
export struct IconSelectorDialog {
  @State selectedIconId: number | string = -1;
  @State icons: IconResource[] = [];
  @State dialogWidth: string | number = '100%'; // 弹框宽度
  @State currentTabIndex: number = 0;
  @State searchKeyword: string = '';
  @State domesticList: BrandIconDef[] = [];
  @State internationalList: BrandIconDef[] = [];
  @State converting: boolean = false; // 品牌图标转换中
  @State keyboardHeightVp: number = 0; // 软键盘高度（vp），0 表示键盘收起
  public onIconSelected: (iconId: number | string) => void = () => {
  };
  public database: Kdbx | null = null; // 数据库实例
  // 每行显示的图标数量
  private readonly columnsPerRow: number = 5;
  // 图标大小
  private readonly iconSize: number = 40;
  // 品牌图标大小
  private readonly brandIconSize: number = 36;
  // 图标间距
  private readonly iconGap: number = 16;
  // 键盘弹起时的顶部预留（状态栏高度，vp）
  private statusBarVp: number = 0;
  // 主窗口实例（avoidAreaChange 反注册用）
  private mainWindow: window.Window | null = null;
  private controller: CustomDialogController;
  private windowHelper: DialogWindowHelper = new DialogWindowHelper();

  aboutToAppear() {
    // 注册窗口大小变化监听
    this.windowHelper.register(this.getUIContext(), () => {
      this.updateDialogWidth();
    });
    // 计算弹框宽度
    this.updateDialogWidth();

    // 获取所有图标
    this.icons = IconUtils.getAllIcons();
    // 初始化品牌图标列表
    this.domesticList = BrandIcons.DOMESTIC;
    this.internationalList = BrandIcons.INTERNATIONAL;

    // 注册键盘避让监听：配合调用方 keyboardAvoidMode NONE 手动抬升弹框，消除与键盘的间隙
    this.registerKeyboardAvoid();
  }

  aboutToDisappear() {
    this.windowHelper.unregister();
    this.unregisterKeyboardAvoid();
  }

  /**
   * 注册键盘避让监听：调用方设置 keyboardAvoidMode NONE 后系统不再自动避让，
   * 此处按键盘高度手动抬升弹框（margin bottom），使弹框紧贴键盘上沿
   */
  private registerKeyboardAvoid(): void {
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    window.getLastWindow(context).then((win: window.Window) => {
      this.mainWindow = win;
      // 状态栏高度：键盘弹起时顶部预留，防止标题栏被状态栏遮挡
      const sysAvoid: window.AvoidArea = win.getWindowAvoidArea(window.AvoidAreaType.TYPE_SYSTEM);
      this.statusBarVp = this.getUIContext().px2vp(sysAvoid.topRect.height);
      win.on('avoidAreaChange', (data: window.AvoidAreaOptions) => {
        if (data.type !== window.AvoidAreaType.TYPE_KEYBOARD) {
          return;
        }
        const heightVp: number = this.getUIContext().px2vp(data.area.bottomRect.height);
        if (heightVp === this.keyboardHeightVp) {
          return;
        }
        this.getUIContext().animateTo({ duration: 200, curve: Curve.EaseOut }, () => {
          this.keyboardHeightVp = heightVp;
        });
      });
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'Register keyboard avoid failed: %{public}s', error.message);
    });
  }

  /**
   * 反注册键盘避让监听
   */
  private unregisterKeyboardAvoid(): void {
    if (this.mainWindow) {
      this.mainWindow.off('avoidAreaChange');
      this.mainWindow = null;
    }
  }

  /**
   * 计算键盘弹起时的弹框高度：窗口高度 - 键盘高度 - 状态栏预留，上限为窗口高度的 85%（与收起时一致）
   */
  private dialogHeightWithKeyboard(): number {
    const windowVp: number = this.getUIContext().px2vp(this.windowHelper.windowHeight);
    if (windowVp <= 0) {
      return 0;
    }
    const available: number = windowVp - this.keyboardHeightVp - this.statusBarVp;
    return Math.min(windowVp * 0.85, available);
  }

  /**
   * 更新弹框宽度
   */
  private updateDialogWidth(): void {
    const widthConfig = UIUtils.calculateDialogWidth(this.getUIContext(), this.windowHelper.windowWidth);
    this.dialogWidth = widthConfig.width;
  }

  /**
   * 刷新图标列表
   */
  private refreshIcons() {
    this.icons = IconUtils.getAllIcons(false);
  }

  /**
   * 品牌图标搜索
   */
  private onSearchChange(value: string): void {
    this.searchKeyword = value;
    this.domesticList = BrandIcons.search(BrandIcons.DOMESTIC, value);
    this.internationalList = BrandIcons.search(BrandIcons.INTERNATIONAL, value);
  }

  /**
   * 切换页签（保留搜索词：搜索条件跨国内/国外两个品牌页签共存，切换不清空；
   * 搜索框随页签展开/收起，高度+透明度动画过渡）
   */
  private onTabChange(index: number): void {
    if (index === this.currentTabIndex) {
      return;
    }
    this.getUIContext().animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
      this.currentTabIndex = index;
    });
  }

  /**
   * 应用品牌图标：SVG 转 PNG 后写入内存库（含去重复用），回调图标 UUID
   * 不自动保存数据库：由条目/群组编辑页的保存按钮统一持久化
   */
  private async applyBrandIcon(def: BrandIconDef): Promise<void> {
    if (this.converting) {
      return;
    }
    this.converting = true;
    try {
      const dataUrl = await BrandIcons.toPngDataUrl(def);
      if (!dataUrl) {
        CommonUtils.showToast($r('app.string.brand_icon_apply_failed'));
        return;
      }
      const uuids: string[] = KdbxSaveService.addCustomIcon(FileService.getDatabase(), [dataUrl]);
      const uuid: string = uuids.length > 0 ? uuids[0] : '';
      if (!uuid) {
        CommonUtils.showToast($r('app.string.brand_icon_apply_failed'));
        return;
      }
      this.controller.close();
      this.onIconSelected(uuid);
    } catch (error) {
      CommonUtils.showToast($r('app.string.brand_icon_apply_failed'));
    } finally {
      this.converting = false;
    }
  }

  @Builder
  StandardGrid() {
    Grid() {
      ForEach(this.icons.length > 0 ? this.icons : IconUtils.getAllIcons(), (icon: IconResource) => {
        GridItem() {
          Column() {
            Image(icon.resource)
              .width(this.iconSize)
              .height(this.iconSize)
              .objectFit(ImageFit.Contain)
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .borderRadius(8)
          .backgroundColor(this.selectedIconId === icon.id ? '#E8F3FF' : 'transparent')
          .border(this.selectedIconId === icon.id ? {
            width: 2,
            color: '#007DFF',
            style: BorderStyle.Solid
          } : {
            width: 0
          })
          .onClick(() => {
            this.selectedIconId = icon.id;
            this.controller.close();
            if (this.onIconSelected) {
              this.onIconSelected(icon.id);
            }
          })
        }
      })

      GridItem() {
        // 图片添加组件
        Button() {
          ImageAddComponent({
            autoSave: false,
            onSuccess: () => {
              this.refreshIcons();
            }
          })
            .width(this.iconSize)
            .height(this.iconSize)
        }
        .width(this.iconSize)
        .height(this.iconSize)
        .borderRadius(this.iconSize / 2)
        .backgroundColor($r("app.color.button_bg_blue"))
      }
    }
    .height('100%')
    .columnsTemplate('1fr '.repeat(this.columnsPerRow))
    .columnsGap(this.iconGap)
    .rowsGap(this.iconGap)
    .padding({ left: 24, right: 24, bottom: 16 })
  }

  @Builder
  BrandGrid($$: BrandGridParams) {
    if ($$.list.length === 0) {
      Column() {
        Text($r('app.string.brand_icon_no_match'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
    } else {
      Grid() {
        ForEach($$.list, (def: BrandIconDef) => {
          GridItem() {
            Column({ space: 4 }) {
              Image($rawfile(BrandIcons.rawfilePath(def)))
                .width(this.brandIconSize)
                .height(this.brandIconSize)
                .objectFit(ImageFit.Contain)
              Text(def.label)
                .fontSize(10)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ top: 8, bottom: 4 })
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .borderRadius(8)
            .onClick(() => {
              this.applyBrandIcon(def);
            })
          }
        }, (def: BrandIconDef) => def.file)
      }
      .height('100%')
      .columnsTemplate('1fr '.repeat(this.columnsPerRow))
      .columnsGap(this.iconGap)
      .rowsGap(this.iconGap)
      .padding({ left: 24, right: 24, top: 8, bottom: 16 })
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r("app.string.select_icon"))
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
        })
      }
      .width('100%')
      .height(56)
      .padding({ left: 24, right: 16 })
      .alignItems(VerticalAlign.Center)
      .backgroundColor($r("app.color.bg_primary"))
      .borderRadius({ topLeft: 16, topRight: 16 })

      // 品牌图标搜索框（仅品牌页签显示，展开/收起带高度+透明度动画；有输入时显示清空按钮）
      Column() {
        Stack({ alignContent: Alignment.End }) {
          TextInput({ placeholder: $r('app.string.search_brand_icon_placeholder'), text: this.searchKeyword })
            .height(40)
            .fontSize(14)
            .padding({ left: 16, right: 40 })
            .backgroundColor($r('app.color.bg_secondary'))
            .borderRadius(20)
            .onChange((value: string) => {
              this.onSearchChange(value);
            })
          if (this.searchKeyword !== '') {
            Image($r('sys.media.ohos_ic_public_cancel_filled'))
              .width(18)
              .height(18)
              .fillColor($r('app.color.text_secondary'))
              .margin({ right: 11 })
              .onClick(() => {
                this.onSearchChange('');
              })
          }
        }
        .margin({ top: 8 })
      }
      .width('100%')
      .padding({ left: 24, right: 24 })
      .height(this.currentTabIndex === 0 ? 0 : 48)
      .opacity(this.currentTabIndex === 0 ? 0 : 1)
      .clip(true)

      // 页签内容
      Stack() {
        Tabs({ index: this.currentTabIndex }) {
          TabContent() {
            this.StandardGrid()
          }
          .tabBar($r('app.string.tab_standard_icons'))

          TabContent() {
            this.BrandGrid({ list: this.domesticList })
          }
          .tabBar($r('app.string.tab_domestic_icons'))

          TabContent() {
            this.BrandGrid({ list: this.internationalList })
          }
          .tabBar($r('app.string.tab_international_icons'))
        }
        .scrollable(false)
        .barMode(BarMode.Fixed)
        .height('100%')
        .onChange((index: number) => {
          this.onTabChange(index);
        })

        // 转换中遮罩（阻断重复点击）
        if (this.converting) {
          Column() {
            LoadingProgress()
              .width(40)
              .height(40)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .backgroundColor('rgba(0, 0, 0, 0.08)')
          .onClick(() => {
          })
        }
      }
      .layoutWeight(1)
    }
    .width(this.dialogWidth)
    // 键盘弹起时收缩高度并整体上移（margin bottom = 键盘高度），紧贴键盘上沿
    .height(this.keyboardHeightVp > 0 ? this.dialogHeightWithKeyboard() : '85%')
    .margin({ bottom: this.keyboardHeightVp })
    .backgroundColor($r('app.color.bg_primary'))
    .borderRadius(16)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}
