import { NavigationManager, ResourceManager } from '../../common/utils';
import { ImportWizardBridge } from '../../services/importExport/wizard/ImportWizardBridge';
import {
  ColumnMappingItem,
  ColumnMappingProfile,
  CsvMappingPreview,
  WizardMappingConflict,
  WizardTargetField,
  WizardValidationResult
} from '../../services/importExport/csvimport/CsvMappingModels';

/** 向导总步数（预览 → 映射 → 选项 → 确认） */
const WIZARD_STEP_COUNT = 4;

/** 目标字段下拉可选项（与 WizardTargetField 一致） */
const TARGET_OPTIONS: WizardTargetField[] = [
  WizardTargetField.SKIP,
  WizardTargetField.GROUP,
  WizardTargetField.TITLE,
  WizardTargetField.USERNAME,
  WizardTargetField.PASSWORD,
  WizardTargetField.URL,
  WizardTargetField.NOTES,
  WizardTargetField.TOTP,
  WizardTargetField.TAGS,
  WizardTargetField.ICON,
  WizardTargetField.EXPIRY_TIME,
  WizardTargetField.LAST_MODIFIED,
  WizardTargetField.CREATED,
  WizardTargetField.CUSTOM
];

@Builder
export function ColumnMappingWizardBuilder(name: string, param: Object): void {
  NavDestination() {
    ColumnMappingWizard()
  }
  .hideTitleBar(true)
  .backgroundColor($r('app.color.bg_primary'))
}

/**
 * CSV 列映射向导页（M2-4，§5.1 四步流程）
 * 由 ImportWizardBridge 在 CSV 未知来源（或强制预览）时推入：
 * Step1 预览（识别结果 + 采样行）→ Step2 逐列映射（目标下拉 + 自定义字段名）
 * → Step3 选项（导入目标分组）→ Step4 校验确认（冲突提示 + 映射摘要）。
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
  }

  aboutToDisappear(): void {
    // 兜底：页面销毁而未提交结果时取消挂起请求，防止桥 Promise 永久挂起（无 pending 时为空操作）
    this.bridge.notifyCancelled();
  }

  /**
   * 构建当前确认后的映射档案
   */
  private buildProfile(): ColumnMappingProfile {
    return new ColumnMappingProfile(this.items, this.targetGroupName.trim());
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
      if (item.targetField !== WizardTargetField.SKIP) {
        count++;
      }
    }
    return count;
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

  private targetOptionIndex(target: WizardTargetField): number {
    const index = TARGET_OPTIONS.indexOf(target);
    return index >= 0 ? index : 0;
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
  private stepIndicator() {
    Row({ space: 8 }) {
      Text(ResourceManager.getString($r('app.string.import_wizard_step_preview')))
        .fontSize(12)
        .fontColor(this.step === 0 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      Text('1/4')
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
      Text(ResourceManager.getString($r('app.string.import_wizard_step_mapping')))
        .fontSize(12)
        .fontColor(this.step === 1 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      Text(ResourceManager.getString($r('app.string.import_wizard_step_options')))
        .fontSize(12)
        .fontColor(this.step === 2 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
      Text(ResourceManager.getString($r('app.string.import_wizard_step_confirm')))
        .fontSize(12)
        .fontColor(this.step === 3 ? $r('app.color.text_primary') : $r('app.color.text_secondary'))
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  private previewStep() {
    Column() {
      Row() {
        Column({ space: 4 }) {
          if (this.detectedFormatName !== '') {
            Text(ResourceManager.getString($r('app.string.import_wizard_detected_format'), this.detectedFormatName))
              .fontSize(15)
              .fontColor($r('app.color.text_primary'))
          } else {
            Text(ResourceManager.getString($r('app.string.import_wizard_unknown_format')))
              .fontSize(15)
              .fontColor($r('app.color.text_secondary'))
          }
          Text(ResourceManager.getString($r('app.string.import_wizard_total_rows'), this.totalRowEstimate))
            .fontSize(13)
            .fontColor($r('app.color.text_secondary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(16)

      Scroll() {
        Column() {
          ForEach(this.sampleRows, (row: string[]) => {
            Row() {
              ForEach(row, (cell: string) => {
                Text(cell)
                  .fontSize(12)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .layoutWeight(1)
                  .padding(4)
              }, (cell: string) => cell)
            }
            .width('100%')
          }, (row: string[], index: number) => `${index}`)
        }
        .width('100%')
      }
      .layoutWeight(1)
      .backgroundColor($r('app.color.card_bg'))
      .borderRadius(12)
      .margin({ left: 12, right: 12, bottom: 12 })
      .clipContent(ContentClipMode.SAFE_AREA)
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
                .value(item.targetField)
                .font({ size: 14 })
                .onSelect((index: number) => {
                  this.onTargetSelected(item.sourceColumnIndex, index);
                })
            }
            .width('100%')

            if (item.targetField === WizardTargetField.CUSTOM) {
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
    .backgroundColor($r('app.color.card_bg'))
    .borderRadius(12)
    .divider({ strokeWidth: 1, color: $r('app.color.divider') })
    .clipContent(ContentClipMode.SAFE_AREA)
  }

  @Builder
  private optionsStep() {
    Column() {
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
  }

  @Builder
  private confirmStep() {
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

      ForEach(this.validateProfile().conflicts, (conflict: WizardMappingConflict) => {
        Text(ResourceManager.getString(
          $r('app.string.import_wizard_conflict_warning'),
          this.formatConflictLabel(conflict)
        ))
          .fontSize(13)
          .fontColor($r('app.color.warn'))
          .width('100%')
          .padding({ left: 16, right: 16, bottom: 8 })
      }, (conflict: WizardMappingConflict) => conflict.targetLabel)
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  private bottomBar() {
    Row({ space: 12 }) {
      Button(ResourceManager.getString($r('app.string.import_wizard_cancel_button')))
        .type(ButtonType.Capsule)
        .layoutWeight(1)
        .backgroundColor($r('app.color.card_bg'))
        .fontColor($r('app.color.text_primary'))
        .onClick(() => {
          this.cancelWizard();
        })

      if (this.step > 0) {
        Button(ResourceManager.getString($r('app.string.import_wizard_prev_button')))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .backgroundColor($r('app.color.card_bg'))
          .fontColor($r('app.color.text_primary'))
          .onClick(() => {
            this.goToStep(this.step - 1);
          })
      }

      if (this.step < WIZARD_STEP_COUNT - 1) {
        Button(ResourceManager.getString($r('app.string.import_wizard_next_button')))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
          .onClick(() => {
            this.goToStep(this.step + 1);
          })
      } else {
        Button(ResourceManager.getString($r('app.string.import_wizard_confirm_button')))
          .type(ButtonType.Capsule)
          .layoutWeight(1)
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
      options.push({ value: target });
    }
    return options;
  }

  build() {
    Column() {
      // 自定义标题栏：标题 + 步骤指示
      Row() {
        Text(ResourceManager.getString($r('app.string.import_wizard_title')))
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.text_primary'))
          .layoutWeight(1)
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12 })

      this.stepIndicator()

      if (!this.hasPreview) {
        Text(ResourceManager.getString($r('app.string.import_wizard_no_pending_request')))
          .fontSize(15)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 40 })
      } else {
        Column() {
          if (this.step === 0) {
            this.previewStep()
          } else if (this.step === 1) {
            this.mappingStep()
          } else if (this.step === 2) {
            this.optionsStep()
          } else {
            this.confirmStep()
          }
        }
        .layoutWeight(1)
        .width('100%')
        .clip(true)
      }

      this.bottomBar()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
