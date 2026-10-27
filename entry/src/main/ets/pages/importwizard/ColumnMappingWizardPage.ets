import { NavigationManager, ResourceManager } from '../../common/utils';
import { ImportWizardBridge } from '../../services/importExport/wizard/ImportWizardBridge';
import {
  ColumnMappingItem,
  ColumnMappingProfile,
  CsvMappingPreview,
  WizardMappingConflict,
  WizardValidationResult
} from '../../services/importExport/csvimport/CsvMappingModels';
import { CsvTargetField } from '../../services/importExport/csvimport/CsvImportModels';
import { CsvEncoding, CsvEncodingUtils } from '../../services/importExport/csvimport/CsvEncodingUtils';
import { CsvParser } from '../../services/importExport/csvimport/CsvParser';

/** 向导总步数（预览 → 映射 → 选项 → 确认） */
const WIZARD_STEP_COUNT = 4;

/** 预览表格单元格字符截断上限（超过 20 字符显示 ...） */
const PREVIEW_CELL_MAX_CHARS = 20;

/** 预览表格单列宽度（vp，列多时横向滚动） */
const PREVIEW_COL_WIDTH = 120;

/** 悬浮底栏预留高度（内容穿透底栏时保证末行可滚动至可见区） */
const FLOATING_BAR_RESERVED_HEIGHT = 96;

/** 目标字段下拉可选项（与 CsvTargetField 一致） */
const TARGET_OPTIONS: CsvTargetField[] = [
  CsvTargetField.SKIP,
  CsvTargetField.GROUP,
  CsvTargetField.TITLE,
  CsvTargetField.USERNAME,
  CsvTargetField.PASSWORD,
  CsvTargetField.URL,
  CsvTargetField.NOTES,
  CsvTargetField.TOTP,
  CsvTargetField.TAGS,
  CsvTargetField.ICON,
  CsvTargetField.EXPIRY_TIME,
  CsvTargetField.LAST_MODIFIED,
  CsvTargetField.CREATED,
  CsvTargetField.CUSTOM
];

/** 编码下拉可选项（AUTO = 跟随自动检测结果） */
const ENCODING_OPTIONS: string[] = [CsvEncoding.AUTO, CsvEncoding.UTF8, CsvEncoding.GBK];

@Builder
export function ColumnMappingWizardBuilder(name: string, param: Object): void {
  NavDestination() {
    ColumnMappingWizard()
  }
  .title($r('app.string.import_wizard_title'))
  .backgroundColor($r('app.color.bg_primary'))
}

/**
 * CSV 列映射向导页（M2-4，§5.1 四步流程）
 * 由 ImportWizardBridge 在 CSV 未知来源（或强制预览）时推入：
 * Step1 预览（识别结果 + 表格式采样数据）→ Step2 逐列映射（目标下拉 + 自定义字段名）
 * → Step3 选项（导入目标分组）→ Step4 校验确认（冲突提示 + 映射明细）。
 * 标准标题栏（含返回键）+ Tabs 步骤条；底部操作栏悬浮（内容可穿透滚动）。
 * 确认后经 bridge.notifyComplete(profile) 回传；取消/页面销毁 notifyCancelled 兜底防挂起。
 */
@Component
struct ColumnMappingWizard {
  private navPathStack: NavPathStack | null = NavigationManager.getInstance().getNavPathStack();
  private bridge: ImportWizardBridge = ImportWizardBridge.getInstance();
  @State hasPreview: boolean = false;
  @State step: number = 0;
  @State headers: string[] = [];
  @State sampleRows: string[][] = [];
  @State items: ColumnMappingItem[] = [];
  @State targetGroupName: string = '';
  @State detectedFormatName: string = '';
  @State totalRowEstimate: number = 0;
  @State selectedEncoding: string = CsvEncoding.AUTO;
  @State detectedEncoding: string = '';

  aboutToAppear(): void {
    const preview: CsvMappingPreview | null = this.bridge.getPendingPreview();
    if (preview === null) {
      this.hasPreview = false;
      return;
    }
    this.hasPreview = true;
    this.headers = preview.headers;
    this.sampleRows = preview.sampleRows;
    this.items = preview.suggestedItems;
    this.detectedFormatName = preview.detectedFormatName;
    this.totalRowEstimate = preview.totalRowEstimate;
    this.detectedEncoding = preview.detectedEncoding;
    this.selectedEncoding = CsvEncoding.AUTO;
  }

  aboutToDisappear(): void {
    // 兜底：页面销毁而未提交结果时取消挂起请求，防止桥 Promise 永久挂起（无 pending 时为空操作）
    this.bridge.notifyCancelled();
  }

  /**
   * 构建当前确认后的映射档案
   */
  private buildProfile(): ColumnMappingProfile {
    return new ColumnMappingProfile(this.items, this.targetGroupName.trim(), this.selectedEncoding);
  }

  /**
   * 校验结果（Step4 展示与按钮可用性）
   */
  private validateProfile(): WizardValidationResult {
    return this.buildProfile().validate();
  }

  /**
   * 冲突展示文案：目标（列1、列2）
   */
  private formatConflictLabel(conflict: WizardMappingConflict): string {
    return `${conflict.targetLabel} (${conflict.columnNames.join(', ')})`;
  }

  /**
   * 已映射（非 SKIP）列数
   */
  private mappedColumnCount(): number {
    let count = 0;
    for (const item of this.items) {
      if (item.targetField !== CsvTargetField.SKIP) {
        count++;
      }
    }
    return count;
  }

  /**
   * 预览单元格文案：超过 20 字符截断显示 ...
   */
  private truncateCell(cell: string): string {
    if (cell.length > PREVIEW_CELL_MAX_CHARS) {
      return cell.substring(0, PREVIEW_CELL_MAX_CHARS) + '...';
    }
    return cell;
  }

  /**
   * 目标字段本地化标签（下拉选项与映射明细共用）
   */
  private targetFieldLabel(target: CsvTargetField): string {
    switch (target) {
      case CsvTargetField.SKIP:
        return ResourceManager.getString($r('app.string.import_wizard_target_skip'));
      case CsvTargetField.GROUP:
        return ResourceManager.getString($r('app.string.import_wizard_target_group'));
      case CsvTargetField.TITLE:
        return ResourceManager.getString($r('app.string.import_wizard_target_title'));
      case CsvTargetField.USERNAME:
        return ResourceManager.getString($r('app.string.import_wizard_target_username'));
      case CsvTargetField.PASSWORD:
        return ResourceManager.getString($r('app.string.import_wizard_target_password'));
      case CsvTargetField.URL:
        return ResourceManager.getString($r('app.string.import_wizard_target_url'));
      case CsvTargetField.NOTES:
        return ResourceManager.getString($r('app.string.import_wizard_target_notes'));
      case CsvTargetField.TOTP:
        return ResourceManager.getString($r('app.string.import_wizard_target_totp'));
      case CsvTargetField.TAGS:
        return ResourceManager.getString($r('app.string.import_wizard_target_tags'));
      case CsvTargetField.ICON:
        return ResourceManager.getString($r('app.string.import_wizard_target_icon'));
      case CsvTargetField.EXPIRY_TIME:
        return ResourceManager.getString($r('app.string.import_wizard_target_expiry_time'));
      case CsvTargetField.LAST_MODIFIED:
        return ResourceManager.getString($r('app.string.import_wizard_target_last_modified'));
      case CsvTargetField.CREATED:
        return ResourceManager.getString($r('app.string.import_wizard_target_created'));
      case CsvTargetField.CUSTOM:
        return ResourceManager.getString($r('app.string.import_wizard_target_custom'));
      default:
        return target;
    }
  }

  /**
   * 映射明细目标侧文案：CUSTOM 显示自定义字段名（未填回退"自定义"标签）
   */
  private targetDisplayLabel(item: ColumnMappingItem): string {
    if (item.targetField === CsvTargetField.CUSTOM) {
      const customName = item.customFieldName.trim();
      return customName !== '' ? customName : this.targetFieldLabel(CsvTargetField.CUSTOM);
    }
    return this.targetFieldLabel(item.targetField);
  }

  private onTargetSelected(columnIndex: number, selectedIndex: number): void {
    const target = TARGET_OPTIONS[selectedIndex];
    const next: ColumnMappingItem[] = [];
    for (const item of this.items) {
      if (item.sourceColumnIndex === columnIndex) {
        next.push(new ColumnMappingItem(item.sourceColumnIndex, item.sourceColumnName, target, item.customFieldName));
      } else {
        next.push(item);
      }
    }
    this.items = next;
  }

  private onCustomNameChanged(columnIndex: number, name: string): void {
    const next: ColumnMappingItem[] = [];
    for (const item of this.items) {
      if (item.sourceColumnIndex === columnIndex) {
        next.push(new ColumnMappingItem(item.sourceColumnIndex, item.sourceColumnName, item.targetField, name));
      } else {
        next.push(item);
      }
    }
    this.items = next;
  }

  private targetOptionIndex(target: CsvTargetField): number {
    const index = TARGET_OPTIONS.indexOf(target);
    return index >= 0 ? index : 0;
  }

  /**
   * 编码下拉当前选中索引
   */
  private encodingOptionIndex(): number {
    const index = ENCODING_OPTIONS.indexOf(this.selectedEncoding);
    return index >= 0 ? index : 0;
  }

  /**
   * 编码下拉选项文案：AUTO 显示「自动（检测结果）」，其余显示编码名
   */
  private encodingOptionLabel(encoding: string): string {
    if (encoding === CsvEncoding.UTF8) {
      return 'UTF-8';
    }
    if (encoding === CsvEncoding.GBK) {
      return 'GBK';
    }
    const autoLabel = ResourceManager.getString($r('app.string.import_wizard_encoding_auto'));
    if (this.detectedEncoding === CsvEncoding.GBK) {
      return `${autoLabel}（GBK）`;
    }
    if (this.detectedEncoding === CsvEncoding.UTF8) {
      return `${autoLabel}（UTF-8）`;
    }
    return autoLabel;
  }

  private buildEncodingOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const encoding of ENCODING_OPTIONS) {
      options.push({ value: this.encodingOptionLabel(encoding) });
    }
    return options;
  }

  private onEncodingSelected(index: number): void {
    const encoding = ENCODING_OPTIONS[index];
    if (encoding === this.selectedEncoding) {
      return;
    }
    this.selectedEncoding = encoding;
    this.reparseWithEncoding(encoding);
  }

  /**
   * 切换编码后重新解码解析并刷新预览（表头/采样/建议映射随新编码重建）
   */
  private reparseWithEncoding(encoding: string): void {
    const preview: CsvMappingPreview | null = this.bridge.getPendingPreview();
    if (preview === null || preview.sourceContent.byteLength === 0) {
      return;
    }
    const effective = encoding !== CsvEncoding.AUTO ? encoding : preview.detectedEncoding;
    if (effective === '') {
      return;
    }
    const text = CsvEncodingUtils.decode(new Uint8Array(preview.sourceContent), effective);
    const reparsed = new CsvParser().parse(text);
    if (reparsed.rows.length === 0) {
      return;
    }
    const rebuilt = ImportWizardBridge.buildPreview(
      reparsed.rows,
      preview.detectedFormatName,
      preview.sourceContent,
      preview.detectedEncoding
    );
    this.headers = rebuilt.headers;
    this.sampleRows = rebuilt.sampleRows;
    this.items = rebuilt.suggestedItems;
    this.totalRowEstimate = rebuilt.totalRowEstimate;
  }

  private goToStep(step: number): void {
    if (step >= 0 && step < WIZARD_STEP_COUNT) {
      this.step = step;
    }
  }

  private submit(): void {
    this.bridge.notifyComplete(this.buildProfile());
    this.navPathStack?.pop();
  }

  private cancelWizard(): void {
    this.bridge.notifyCancelled();
    this.navPathStack?.pop();
  }

  @Builder
  private previewStep() {
    Column() {
      Row() {
        if (this.detectedFormatName !== '') {
          Text(ResourceManager.getString($r('app.string.import_wizard_detected_format'), this.detectedFormatName))
            .fontSize(15)
            .fontColor($r('app.color.text_primary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        } else {
          Text(ResourceManager.getString($r('app.string.import_wizard_unknown_format')))
            .fontSize(15)
            .fontColor($r('app.color.text_secondary'))
            .layoutWeight(1)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        Text(ResourceManager.getString($r('app.string.import_wizard_total_rows'), this.totalRowEstimate))
          .fontSize(13)
          .fontColor($r('app.color.text_secondary'))
      }
      .width('100%')
      .padding(16)

      Row() {
        Text(ResourceManager.getString($r('app.string.import_wizard_encoding_label')))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .layoutWeight(1)
        Select(this.buildEncodingOptions())
          .selected(this.encodingOptionIndex())
          .value(this.encodingOptionLabel(this.selectedEncoding))
          .font({ size: 14 })
          .onSelect((index: number) => {
            this.onEncodingSelected(index);
          })
      }
      .width('100%')
      .padding({ left: 16, right: 16, bottom: 12 })

      Scroll() {
        Column() {
          // 表格式预览：第一行为标题（表头），列多时横向滚动，单元格超过 20 字符截断
          Scroll() {
            Column() {
              Row() {
                ForEach(this.headers, (header: string, index: number) => {
                  Text(this.truncateCell(header))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .width(PREVIEW_COL_WIDTH)
                    .padding({ left: 8, right: 8, top: 10, bottom: 10 })
                }, (header: string, index: number) => `${index}-${header}`)
              }
              .width('100%')
              .backgroundColor($r('app.color.bg_secondary'))

              ForEach(this.sampleRows, (row: string[], rowIndex: number) => {
                Row() {
                  ForEach(row, (cell: string, colIndex: number) => {
                    Text(this.truncateCell(cell))
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .maxLines(1)
                      .width(PREVIEW_COL_WIDTH)
                      .padding({ left: 8, right: 8, top: 10, bottom: 10 })
                  }, (cell: string, colIndex: number) => `${rowIndex}-${colIndex}-${cell}`)
                }
                .width('100%')
                .backgroundColor($r('app.color.card_bg'))
                .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
              }, (row: string[], rowIndex: number) => `${rowIndex}`)
            }
          }
          .scrollable(ScrollDirection.Horizontal)
          .width('100%')
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)
          .clipContent(ContentClipMode.SAFE_AREA)
        }
        .width('100%')
        .padding({ bottom: FLOATING_BAR_RESERVED_HEIGHT })
      }
      .layoutWeight(1)
      .width('100%')
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  private mappingStep() {
    List({ space: 0 }) {
      ForEach(this.items, (item: ColumnMappingItem) => {
        ListItem() {
          Column({ space: 8 }) {
            Row() {
              Text(item.sourceColumnName)
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('app.color.text_primary'))
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Select(this.buildSelectOptions())
                .selected(this.targetOptionIndex(item.targetField))
                .value(this.targetFieldLabel(item.targetField))
                .font({ size: 14 })
                .onSelect((index: number) => {
                  this.onTargetSelected(item.sourceColumnIndex, index);
                })
            }
            .width('100%')

            if (item.targetField === CsvTargetField.CUSTOM) {
              TextInput({
                text: item.customFieldName,
                placeholder: ResourceManager.getString($r('app.string.import_wizard_custom_field_name'))
              })
                .fontSize(14)
                .onChange((value: string) => {
                  this.onCustomNameChanged(item.sourceColumnIndex, value);
                })
            }
          }
          .width('100%')
          .padding({ left: 16, right: 16, top: 12, bottom: 12 })
        }
      }, (item: ColumnMappingItem) => `${item.sourceColumnIndex}-${item.targetField}-${item.customFieldName}`)
    }
    .width('100%')
    .height('100%')
    .padding({ bottom: FLOATING_BAR_RESERVED_HEIGHT })
    .backgroundColor($r('app.color.bg_primary'))
    .divider({ strokeWidth: 1, color: $r('app.color.divider') })
  }

  @Builder
  private optionsStep() {
    Scroll() {
      Column({ space: 8 }) {
        Text(ResourceManager.getString($r('app.string.import_wizard_target_group_name')))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
        TextInput({
          text: this.targetGroupName,
          placeholder: ResourceManager.getString($r('app.string.import_wizard_target_group_placeholder'))
        })
          .fontSize(14)
          .onChange((value: string) => {
            this.targetGroupName = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(16)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
  }

  @Builder
  private confirmStep() {
    Scroll() {
      Column() {
        Text(ResourceManager.getString(
          $r('app.string.import_wizard_mapped_summary'),
          this.mappedColumnCount(),
          this.items.length
        ))
          .fontSize(14)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .padding(16)

        // 映射明细：源列 → 目标字段（含跳过列，完整呈现映射关系）
        Column() {
          ForEach(this.items, (item: ColumnMappingItem) => {
            Row() {
              Text(item.sourceColumnName)
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('→')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ left: 8, right: 8 })
              Text(this.targetDisplayLabel(item))
                .fontSize(14)
                .fontWeight(FontWeight.Medium)
                .fontColor(item.targetField === CsvTargetField.SKIP
                  ? $r('app.color.text_secondary')
                  : $r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 10, bottom: 10 })
            .border({ width: { bottom: 1 }, color: $r('app.color.divider') })
          }, (item: ColumnMappingItem) => `${item.sourceColumnIndex}-${item.targetField}-${item.customFieldName}`)
        }
        .width('100%')
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(12)
        .margin({ left: 12, right: 12 })
        .clip(true)

        ForEach(this.validateProfile().conflicts, (conflict: WizardMappingConflict) => {
          Text(ResourceManager.getString(
            $r('app.string.import_wizard_conflict_warning'),
            this.formatConflictLabel(conflict)
          ))
            .fontSize(13)
            .fontColor($r('app.color.warn'))
            .width('100%')
            .padding({ left: 16, right: 16, top: 8 })
        }, (conflict: WizardMappingConflict) => conflict.targetLabel)
      }
      .width('100%')
      .padding({ bottom: FLOATING_BAR_RESERVED_HEIGHT })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
  }

  @Builder
  private bottomBar() {
    // 悬浮底栏（DatabaseView MoveModeBar 布局）：Stack alignContent Bottom 定位，内容可穿透滚动
    Row({ space: 12 }) {
      Button(ResourceManager.getString($r('app.string.import_wizard_cancel_button')), { type: ButtonType.Normal })
        .height(40)
        .borderRadius(20)
        .layoutWeight(1)
        .backgroundColor($r('app.color.card_bg'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.cancelWizard();
        })

      if (this.step > 0) {
        Button(ResourceManager.getString($r('app.string.import_wizard_prev_button')), { type: ButtonType.Normal })
          .height(40)
          .borderRadius(20)
          .layoutWeight(1)
          .backgroundColor($r('app.color.card_bg'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.goToStep(this.step - 1);
          })
      }

      if (this.step < WIZARD_STEP_COUNT - 1) {
        Button(ResourceManager.getString($r('app.string.import_wizard_next_button')), { type: ButtonType.Normal })
          .height(40)
          .borderRadius(20)
          .layoutWeight(1)
          .backgroundColor($r('app.color.button_bg_blue'))
          .fontColor($r('app.color.button_text_blue'))
          .onClick(() => {
            this.goToStep(this.step + 1);
          })
      } else {
        Button(ResourceManager.getString($r('app.string.import_wizard_confirm_button')), { type: ButtonType.Normal })
          .height(40)
          .borderRadius(20)
          .layoutWeight(1)
          .backgroundColor($r('app.color.button_bg_blue'))
          .fontColor($r('app.color.button_text_blue'))
          .enabled(this.validateProfile().isValid)
          .onClick(() => {
            this.submit();
          })
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, top: 8, bottom: 16 })
  }

  private buildSelectOptions(): SelectOption[] {
    const options: SelectOption[] = [];
    for (const target of TARGET_OPTIONS) {
      options.push({ value: this.targetFieldLabel(target) });
    }
    return options;
  }

  build() {
    // alignContent: Bottom——悬浮底栏（未定位子节点）自动贴容器底部，内容可穿透滚动（同 DatabaseView）
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        if (!this.hasPreview) {
          Column() {
            Text(ResourceManager.getString($r('app.string.import_wizard_no_pending_request')))
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Tabs({ index: this.step, barPosition: BarPosition.Start }) {
            TabContent() {
              this.previewStep()
            }
            .tabBar(new SubTabBarStyle(ResourceManager.getString($r('app.string.import_wizard_step_preview'))))

            TabContent() {
              this.mappingStep()
            }
            .tabBar(new SubTabBarStyle(ResourceManager.getString($r('app.string.import_wizard_step_mapping'))))

            TabContent() {
              this.optionsStep()
            }
            .tabBar(new SubTabBarStyle(ResourceManager.getString($r('app.string.import_wizard_step_options'))))

            TabContent() {
              this.confirmStep()
            }
            .tabBar(new SubTabBarStyle(ResourceManager.getString($r('app.string.import_wizard_step_confirm'))))
          }
          .onChange((index: number) => {
            this.step = index;
          })
          .layoutWeight(1)
          .width('100%')
        }
      }
      .width('100%')
      .height('100%')

      if (this.hasPreview) {
        this.bottomBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
