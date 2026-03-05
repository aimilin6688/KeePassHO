/**
 * 模板选择对话框
 * 提供模板选择界面，支持分类筛选和搜索
 */
import { Kdbx } from 'kdbxweb';
import { ITemplate, IPresetTemplate, IUserTemplate, TemplateCategory, isPresetTemplate } from '../services/template/TemplateTypes';
import { TemplateService } from '../services/template/TemplateService';
import { IconUtils, ResourceManager } from '../common/utils';

@CustomDialog
export struct TemplateSelectorDialog {
  @State selectedTemplate: ITemplate | null = null;
  @State searchText: string = '';
  @State currentCategory: TemplateCategory | 'all' = 'all';
  @State presetTemplates: IPresetTemplate[] = [];
  @State userTemplates: IUserTemplate[] = [];
  @State filteredTemplates: ITemplate[] = [];

  public onTemplateSelected: (template: ITemplate) => void = () => {};
  public database: Kdbx | null = null;
  public showUserTemplates: boolean = true;

  private controller: CustomDialogController;
  private templateService: TemplateService = TemplateService.getInstance();
  private readonly iconSize: number = 32;

  aboutToAppear() {
    // 加载预置模板
    this.presetTemplates = this.templateService.getPresetTemplates();

    // 加载用户模板
    if (this.database && this.showUserTemplates) {
      this.userTemplates = this.templateService.getUserTemplates(this.database);
    }

    // 初始化过滤后的模板列表
    this.filterTemplates();
  }

  /**
   * 过滤模板
   */
  private filterTemplates(): void {
    let templates: ITemplate[] = [];

    // 按分类筛选
    if (this.currentCategory === 'all') {
      templates = [...this.presetTemplates, ...this.userTemplates];
    } else {
      templates = [
        ...this.presetTemplates.filter(t => t.category === this.currentCategory),
        ...this.userTemplates
      ];
    }

    // 按搜索文本筛选（使用 searchName 或 name）
    if (this.searchText.trim()) {
      const keyword = this.searchText.toLowerCase();
      templates = templates.filter(t => {
        if (isPresetTemplate(t)) {
          const preset = t as IPresetTemplate;
          return preset.id.toLowerCase().includes(keyword)
            || ResourceManager.getString(preset.name).toLowerCase().includes(keyword)
            || (preset.description && ResourceManager.getString(preset.description).toLowerCase().includes(keyword));
        }
        return (t as IUserTemplate).name.toLowerCase().includes(keyword);
      });
    }

    this.filteredTemplates = templates;
  }

  /**
   * 获取模板名称
   */
  private getTemplateName(template: ITemplate): ResourceStr {
    if (isPresetTemplate(template)) {
      return (template as IPresetTemplate).name;
    }
    return (template as IUserTemplate).name;
  }

  /**
   * 获取模板图标资源
   */
  private getTemplateIcon(template: ITemplate): ResourceStr {
    const iconId = isPresetTemplate(template) ?
      (template as IPresetTemplate).iconId :
      (template as IUserTemplate).iconId;

    if (typeof iconId === 'number') {
      return IconUtils.getIconResourcePath(iconId);
    }
    // 自定义图标暂用默认图标
    return IconUtils.getIconResourcePath(0);
  }

  /**
   * 获取分类名称
   */
  private getCategoryName(category: TemplateCategory | 'all'): ResourceStr {
    const categoryNames: Record<string, ResourceStr> = {
      'all': $r('app.string.template_category_all'),
      [TemplateCategory.GENERAL]: $r('app.string.template_category_general'),
      [TemplateCategory.IDENTITY]: $r('app.string.template_category_identity'),
      [TemplateCategory.FINANCE]: $r('app.string.template_category_finance'),
      [TemplateCategory.NETWORK]: $r('app.string.template_category_network'),
      [TemplateCategory.DEVELOPMENT]: $r('app.string.template_category_development'),
      [TemplateCategory.OTHER]: $r('app.string.template_category_other')
    };
    return categoryNames[category] || category;
  }

  /**
   * 获取模板描述
   */
  private getTemplateDescription(template: ITemplate): ResourceStr {
    if (isPresetTemplate(template)) {
      const preset = template as IPresetTemplate;
      return preset.description ?? '';
    }
    return $r('app.string.template_user_description');
  }

  /**
   * 检查模板是否有描述
   */
  private hasTemplateDescription(template: ITemplate): boolean {
    if (isPresetTemplate(template)) {
      const preset = template as IPresetTemplate;
      return preset.description !== undefined;
    }
    return true;
  }

  /**
   * 处理模板选择
   */
  private handleSelect(template: ITemplate): void {
    this.selectedTemplate = template;
    this.controller.close();
    if (this.onTemplateSelected) {
      this.onTemplateSelected(template);
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r('app.string.template_selector_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))

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
      .backgroundColor($r('app.color.bg_primary'))
      .borderRadius({ topLeft: 16, topRight: 16 })

      // 搜索栏
      Row() {
        Image($r('sys.media.ohos_ic_public_search_filled'))
          .width(20)
          .height(20)
          .fillColor($r('app.color.text_secondary'))

        TextInput({ placeholder: $r('app.string.template_search_placeholder'), text: this.searchText })
          .layoutWeight(1)
          .backgroundColor('transparent')
          .fontSize(16)
          .onChange((value: string) => {
            this.searchText = value;
            this.filterTemplates();
          })
      }
      .width('100%')
      .height(44)
      .padding({ left: 16, right: 16 })
      .margin({ left: 16, right: 16, top: 8, bottom: 8 })
      .backgroundColor($r('app.color.bg_secondary'))
      .borderRadius(22)

      // 分类标签
      Scroll() {
        Row() {
          ForEach([
            'all',
            TemplateCategory.GENERAL,
            TemplateCategory.IDENTITY,
            TemplateCategory.FINANCE,
            TemplateCategory.NETWORK,
            TemplateCategory.DEVELOPMENT,
            TemplateCategory.OTHER
          ], (category: TemplateCategory | 'all') => {
            Text(this.getCategoryName(category))
              .fontSize(14)
              .padding({ left: 16, right: 16, top: 6, bottom: 6 })
              .borderRadius(16)
              .backgroundColor(this.currentCategory === category ?
                $r('app.color.button_bg_blue') : $r('app.color.bg_secondary'))
              .fontColor(this.currentCategory === category ?
                $r('app.color.button_text') : $r('app.color.text_primary'))
              .margin({ right: 8 })
              .onClick(() => {
                this.currentCategory = category;
                this.filterTemplates();
              })
          }
          )
        }
        .padding({ left: 16, right: 16 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .width('100%')
      .height(40)

      // 模板列表
      List() {
        // 用户模板分组（优先显示）
        if (this.filteredTemplates.filter(t => !isPresetTemplate(t)).length > 0) {
          ListItemGroup({
            header: this.ListGroupHeader($r('app.string.template_user'))
          }) {
            ForEach(this.filteredTemplates.filter(t => !isPresetTemplate(t)), (template: ITemplate) => {
              ListItem() {
                this.TemplateItem(template)
              }
            })
          }
        }

        // 预置模板分组
        if (this.filteredTemplates.filter(t => isPresetTemplate(t)).length > 0) {
          ListItemGroup({
            header: this.ListGroupHeader($r('app.string.template_preset'))
          }) {
            ForEach(this.filteredTemplates.filter(t => isPresetTemplate(t)), (template: ITemplate) => {
              ListItem() {
                this.TemplateItem(template)
              }
            })
          }
        }

        // 空状态
        if (this.filteredTemplates.length === 0) {
          ListItem() {
            Column() {
              Image($r('sys.media.ohos_ic_public_cancel_filled'))
                .width(64)
                .height(64)
                .fillColor($r('app.color.text_secondary'))
              Text($r('app.string.template_empty'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ top: 8 })
            }
            .width('100%')
            .height(200)
            .justifyContent(FlexAlign.Center)
          }
        }
      }
      .layoutWeight(1)
      .width('100%')
      .height('auto')
      .padding({ left: 16, right: 16, bottom: 16 })
      .divider({
        strokeWidth: 1,
        color: $r('app.color.divider'),
        startMargin: 56,
        endMargin: 0
      })
    }
    .width('100%')
    .height('85%')
    .backgroundColor($r('app.color.bg_primary'))
    .borderRadius(16)
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }

  @Builder
  ListGroupHeader(title: ResourceStr) {
    Text(title)
      .fontSize(14)
      .fontColor($r('app.color.text_secondary'))
      .padding({ left: 0, top: 8, bottom: 8 })
  }

  @Builder
  TemplateItem(template: ITemplate) {
    Row() {
      // 图标
      Image(this.getTemplateIcon(template))
        .width(this.iconSize)
        .height(this.iconSize)
        .objectFit(ImageFit.Contain)
        .margin({ right: 12 })

      // 模板信息
      Column() {
        Text(this.getTemplateName(template))
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        if (this.hasTemplateDescription(template)) {
          Text(this.getTemplateDescription(template))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .margin({ top: 2 })
        }
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 用户模板标识
      if (!isPresetTemplate(template)) {
        Text($r('app.string.template_user_badge'))
          .fontSize(10)
          .fontColor($r('app.color.button_text'))
          .backgroundColor($r('app.color.button_bg_blue'))
          .padding({ left: 6, right: 6, top: 2, bottom: 2 })
          .borderRadius(8)
          .margin({ left: 8 })
      }
    }
    .width('100%')
    .padding({ top: 12, bottom: 12 })
    .onClick(() => this.handleSelect(template))
  }
}
