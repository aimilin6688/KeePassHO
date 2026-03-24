import { FieldReference, FieldReferenceValue, Kdbx, KdbxEntry, KdbxEntryField, KdbxGroup } from 'kdbxweb';
import { CommonUtils, KdbxUtils, ResourceManager } from '../common/utils';

const DOMAIN = 0x0000;
const TAG = 'FieldReferenceDialog';

/**
 * 字段引用对话框参数
 */
export interface FieldReferenceDialogParams {
  database: Kdbx;
  fieldName: string;
  existingReference?: FieldReferenceValue | null;
  onConfirm?: (fieldName: string, ref: FieldReferenceValue) => void;
}

@CustomDialog
export struct FieldReferenceDialog {
  @Prop database: Kdbx;
  @Prop fieldName: string = '';
  @Prop existingReference: FieldReferenceValue | null = null;
  onConfirm?: (fieldName: string, ref: FieldReferenceValue) => void;
  private controller: CustomDialogController;
  @State selectedEntry: KdbxEntry | null = null;
  @State selectedField: string = '';
  @State entries: Array<KdbxEntry> = [];
  @State searchText: string = '';

  aboutToAppear() {
    this.loadEntries();
  }

  private loadEntries() {
    this.entries = [];
    const rootGroup = this.database.getDefaultGroup();
    this.collectEntries(rootGroup);
    // 如果存在已有引用，自动选中对应的条目和字段
    if (this.existingReference && this.existingReference.ref) {
      this.preSelectExistingReference();
    }
  }

  private preSelectExistingReference() {
    if (!this.existingReference || !this.existingReference.ref) {
      return;
    }
    const ref = this.existingReference.ref;
    const refEntryUuid = ref.entryUuid;
    const refField = ref.field;
    // 查找匹配的条目
    for (let i = 0; i < this.entries.length; i++) {
      if (this.entries[i].uuid.id === refEntryUuid) {
        this.selectedEntry = this.entries[i];
        this.selectedField = refField;
        break;
      }
    }
  }

  private collectEntries(group: KdbxGroup) {
    for (const entry of group.entries) {
      this.entries.push(entry);
    }
    for (const subGroup of group.groups) {
      this.collectEntries(subGroup);
    }
  }

  private getFilteredEntries(): Array<KdbxEntry> {
    if (!this.searchText) {
      return this.entries;
    }
    const searchTextLower = this.searchText.toLowerCase();
    return this.entries.filter(entry => {
      const title = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_TITLE);
      const username = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_USERNAME);
      return title.toLowerCase().includes(searchTextLower) ||
      username.toLowerCase().includes(searchTextLower);
    });
  }

  private getAvailableFields(entry: KdbxEntry): Array<string> {
    const fields: Array<string> = [];
    entry.fields.forEach((_value: KdbxEntryField, key: string) => {
      if (key !== KdbxUtils.FIELD_TITLE) {
        fields.push(key);
      }
    });
    return fields;
  }

  /**
   * 关闭对话框
   */
  private close() {
    this.controller.close();
  }

  private handleConfirm() {
    if (!this.selectedEntry) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.please_select_entry')), duration: 2000 });
      return;
    }
    if (!this.selectedField) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.please_select_field')), duration: 2000 });
      return;
    }

    const ref: FieldReferenceValue = {
      ref: {
        entryUuid: this.selectedEntry.uuid.id,
        field: this.selectedField
      } as FieldReference,
      resolvedValue: KdbxUtils.getFieldValueString(this.selectedEntry.fields, this.selectedField)
    };

    this.onConfirm?.(this.fieldName, ref);
    this.close();
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text(this.fieldName || $r('app.string.field_reference'))
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
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          this.close();
        })
      }
      .width('100%')
      .height(40)
      .margin({ top: 6 })
      .alignItems(VerticalAlign.Center)
      .borderRadius({ topLeft: 16, topRight: 16 })

      // 对话框内容
      Column() {
        // 搜索框
        TextInput({ placeholder: $r('app.string.search_entry') })
          .width('100%')
          .height(40)
          .margin({ bottom: 8 })
          .onChange((value: string) => {
            this.searchText = value;
          })

        // 条目列表
        List({ space: 8 }) {
          ForEach(this.getFilteredEntries(), (entry: KdbxEntry) => {
            ListItem() {
              this.EntryItemBuilder(entry)
            }
          }, (entry: KdbxEntry) => entry.uuid.id)
        }
        .width('100%')
        .layoutWeight(1)
        .margin({ bottom: 12 })

        // 字段选择
        if (this.selectedEntry) {
          Column() {
            Row() {
              Text($r('app.string.select_field'))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
              Blank()
              Button() {
                Image($r('sys.media.ohos_ic_public_cancel_filled'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.text_primary'))
              }
              .type(ButtonType.Circle)
              .backgroundColor(Color.Transparent)
              .onClick(() => {
                this.selectedEntry = null;
              })
            }
            .width('100%')
            .margin({ bottom: 8 })

            List({ space: 8 }) {
              ForEach(this.getAvailableFields(this.selectedEntry), (field: string) => {
                ListItem() {
                  Row() {
                    Text(KdbxUtils.getFieldName(field))
                      .fontSize(16)
                      .fontColor(this.selectedField === field ? $r('app.color.button_text') : $r('app.color.text_primary'))
                      .layoutWeight(1)
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })

                    Radio({ value: field, group: 'fieldGroup' })
                      .checked(this.selectedField === field)
                      .onChange((isChecked: boolean) => {
                        if (isChecked) {
                          this.selectedField = field;
                        }
                      })
                  }
                  .width('100%')
                  .padding(12)
                  .backgroundColor(this.selectedField === field ? $r('app.color.button_bg_blue') : $r('app.color.card_bg'))
                  .borderRadius(8)
                  .onClick(() => {
                    this.selectedField = field;
                  })
                }
              }, (field: string) => field)
            }
            .width('100%')
            .constraintSize({ maxHeight: 180 })
            .margin({ bottom: 12 })
          }
          .width('100%')
        }
      }
      .width('100%')
      .layoutWeight(1)
      .margin({ top: 4, bottom: 8 })

      // 底部按钮
      Row() {
        Button() {
          Row() {
            Text($r('app.string.cancel_button_text'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.White)
          }
        }
        .width('48%')
        .height(40)
        .backgroundColor(Color.Gray)
        .borderRadius(20)
        .onClick(() => {
          this.close();
        })

        Button() {
          Row() {
            Image($r('app.media.ic_check'))
              .width(24)
              .height(24)
              .margin({ right: 8 })
              .fillColor($r('app.color.button_text'))
            Text($r('app.string.confirm_button_text'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.button_text'))
          }
        }
        .width('48%')
        .height(40)
        .backgroundColor($r('app.color.button_bg_blue'))
        .borderRadius(20)
        .onClick(() => {
          this.handleConfirm();
        })
      }
      .width('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height('80%')
    .backgroundColor($r('app.color.bg_primary'))
    .borderRadius(16)
    .padding({ left: 24, right: 24, bottom: 16 })
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }

  @Builder
  EntryItemBuilder(entry: KdbxEntry) {
    Row() {
      // 条目图标
      Image(KdbxUtils.getIcon(entry.icon, entry.customIcon, $r('app.media.C00_Key'), this.database.meta))
        .width(36)
        .height(36)
        .margin({ right: 12 })

      Column() {
        Text(KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_TITLE))
          .fontSize(16)
          .fontColor(this.selectedEntry?.uuid.id === entry.uuid.id ? $r('app.color.button_text') : $r('app.color.text_primary'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        Text(KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_USERNAME))
          .fontSize(14)
          .fontColor(this.selectedEntry?.uuid.id === entry.uuid.id ? $r('app.color.button_text') : $r('app.color.text_secondary'))
          .width('100%')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      Radio({ value: entry.uuid.id, group: 'entryGroup' })
        .checked(this.selectedEntry?.uuid.id === entry.uuid.id)
        .onChange((isChecked: boolean) => {
          if (isChecked) {
            this.selectedEntry = entry;
            this.selectedField = '';
          }
        })
    }
    .width('100%')
    .padding(12)
    .backgroundColor(this.selectedEntry?.uuid.id === entry.uuid.id ? $r('app.color.button_bg_blue') : $r('app.color.card_bg'))
    .borderRadius(8)
    .onClick(() => {
      this.selectedEntry = entry;
      this.selectedField = '';
    })
  }
}
