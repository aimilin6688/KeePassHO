import { KdbxEntry, KdbxGroup, Kdbx, ProtectedValue, KdbxUuid } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { Router } from '@kit.ArkUI';
import { FileService } from '../services/FileService';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import KdbxUtils from '../common/utils/KdbxUtils';
import IconUtils from '../common/utils/IconUtils';
import { EntryParam, Icons } from '../services/TypeDefined';
import { EntryEditFieldDialog } from '../components/EntryEditFieldDialog';
import { CustomField } from '../services/TypeDefined';
import { IconSelectorDialog } from '../components/IconSelectorDialog';
import { PasswordGeneratorDialog } from '../components/PasswordGeneratorDialog';
import ResourceManager from '../common/utils/ResourceManager';

const DOMAIN = 0xFF00;
const TAG = 'EntryEdit';

@Entry
@Component
struct EntryEdit {
  @State title: string = '';
  @State username: string = '';
  @State password: string = '';
  @State url: string = '';
  @State notes: string = '';
  @State showPassword: boolean = false;
  @State isLoading: boolean = false;
  @State isEditMode: boolean = false;
  @State pageTitle: string = ResourceManager.getInstance().getString($r('app.string.add_entry_button'));

  @State customFields: CustomField[] = []; // 自定义字段列表
  @State showFieldDialog: boolean = false; // 显示自定义字段对话框
  @State isEditingField: boolean = false; // 是否是编辑字段模式
  @State editingFieldIndex: number = -1; // 正在编辑的字段索引
  @State currentFieldKey: string = ''; // 当前字段的键
  @State currentFieldValue: string = ''; // 当前字段的值
  @State currentFieldProtected: boolean = false; // 当前字段是否受保护
  @State customFieldsVisibility: boolean[] = []; // 自定义字段值的可见性状态
  @State isModified: boolean = false; // 是否有字段被修改
  @State iconId: number | string | undefined = -1; // 当前选择的图标ID
  @State tags: string = ''; // 标签，以逗号分隔
  
  // 自定义字段对话框控制器
  fieldDialogController: CustomDialogController = new CustomDialogController({
    builder: EntryEditFieldDialog({
      isEditing: $isEditingField,
      fieldKey: $currentFieldKey,
      fieldValue: $currentFieldValue,
      isProtected: $currentFieldProtected,
      onConfirm: (customField: CustomField) => {
        hilog.info(DOMAIN, TAG, '%{public}s', `Received field: ${JSON.stringify(customField)}`);
        this.confirmCustomField(customField);
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true
  });
  
  // 图标选择器对话框控制器
  iconSelectorController: CustomDialogController = new CustomDialogController({
    builder: IconSelectorDialog({
      selectedIconId: this.iconId,
      onIconSelected: (iconId: number|string) => {
        this.iconId = iconId;
        this.isModified = true;
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });

  // 密码生成器弹框
  passwordGeneratorController: CustomDialogController = new CustomDialogController({
    builder: PasswordGeneratorDialog({
      password: this.password,
      onGenerate: (password: string) => {
        this.password = password;
        this.isModified = true;
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true
  });

  private database: Kdbx | null = null;
  private parentGroup: KdbxGroup | undefined = undefined;
  private entry: KdbxEntry | null = null;
  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();

  aboutToAppear() {
    // 获取数据库信息
    const params = FileService.getInstance().getDbFileParam();
    this.database = params.database ?? null;

    // 获取路由参数
    const routeParams = this.router.getParams() as EntryParam;

    if (!this.database) {
      this.promptAction.showToast({
        message: $r("app.string.invalid_database"),
        duration: 2000
      });
      this.router.back();
      return;
    }

    // 获取父分组
    if (routeParams.groupId) {
      this.parentGroup = this.database.getGroup(routeParams.groupId);
      if (!this.parentGroup) {
        this.promptAction.showToast({
          message: $r("app.string.invalid_group"),
          duration: 2000
        });
        this.router.back();
        return;
      }
    } else {
      this.parentGroup = this.database.getDefaultGroup();
    }

    // 判断是编辑模式还是添加模式
    if (routeParams.entryId && routeParams.groupId) {
      this.isEditMode = true;
      this.pageTitle = ResourceManager.getInstance().getString($r("app.string.edit_entry"));

      
      // 使用KdbxUtils.getEntry方法获取现有条目
      this.entry = KdbxUtils.getEntry(this.database, routeParams.groupId, routeParams.entryId);
      
      if (!this.entry) {
        this.promptAction.showToast({
          message: $r('app.string.invalid_entry_message'),
          duration: 2000
        });
        this.router.back();
        return;
      }

      // 加载条目数据
      this.title = KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_TITLE);
      this.username = KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_USERNAME);
      this.password = KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_PASSWORD);
      this.url = KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_URL);
      this.notes = KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_NOTES);
      
      // 加载标签
      if (this.entry.tags && this.entry.tags.length > 0) {
        this.tags = this.entry.tags.join(', ');
      }
      
      // 加载图标ID
      this.iconId = this.entry.customIcon ? this.entry.customIcon.id : this.entry.icon;
      
      // 加载自定义字段
      this.loadCustomFields();
    }

    // 初始化修改状态为false
    this.isModified = false;
  }

  /**
   * 加载自定义字段
   */
  private loadCustomFields() {
    this.customFields = [];
    this.customFieldsVisibility = [];
    if (this.entry) {
      // 获取所有字段
      const fields = this.entry.fields;
      
      // 遍历字段，排除标准字段
      fields.forEach((value, key) => {
        // 跳过标准字段
        if ([KdbxUtils.FIELD_TITLE, KdbxUtils.FIELD_USERNAME, KdbxUtils.FIELD_PASSWORD, 
             KdbxUtils.FIELD_URL, KdbxUtils.FIELD_NOTES].includes(key)) {
          return;
        }
        
        let fieldValue = '';
        let isProtected = false;
        
        // 检查是否是受保护的值
        if (value instanceof ProtectedValue) {
          fieldValue = value.getText();
          isProtected = true;
        } else {
          fieldValue = value?.toString() || '';
        }
        
        // 添加到自定义字段列表
        this.customFields.push({
          key: key,
          value: fieldValue,
          isProtected: isProtected
        });
        
        // 初始化可见性状态为false（隐藏）
        this.customFieldsVisibility.push(false);
      });
    }
  }

  /**
   * 保存条目
   */
  private saveEntry() {
    if (!this.database || !this.parentGroup) {
      this.promptAction.showToast({
        message: $r('app.string.EntryEdit_invalid_db_or_group'),
        duration: 2000
      });
      return;
    }

    if (!this.title.trim()) {
      this.promptAction.showToast({
        message: $r('app.string.title_required_message'),
        duration: 2000
      });
      return;
    }
    this.isLoading = true;

    try {
      if (this.isEditMode && this.entry) {
        // 添加到历史记录中
        this.entry.pushHistory();
        // 清除旧的自定义字段（除了标准字段外的所有字段）
        this.entry.fields.forEach((value, key) => {
          if (![KdbxUtils.FIELD_TITLE, KdbxUtils.FIELD_USERNAME, KdbxUtils.FIELD_PASSWORD, 
                KdbxUtils.FIELD_URL, KdbxUtils.FIELD_NOTES].includes(key)) {
            this.entry?.fields.delete(key);
          }
        });
      } else {
        // 创建新条目
        this.entry = this.database.createEntry(this.parentGroup);
      }

      // 设置基础字段
      this.entry.fields.set(KdbxUtils.FIELD_TITLE, this.title.trim());
      this.entry.fields.set(KdbxUtils.FIELD_USERNAME, this.username.trim());
      this.entry.fields.set(KdbxUtils.FIELD_PASSWORD, ProtectedValue.fromString(this.password));
      this.entry.fields.set(KdbxUtils.FIELD_URL, this.url.trim());
      this.entry.fields.set(KdbxUtils.FIELD_NOTES, this.notes.trim());

      // 保存自定义字段
      this.customFields.forEach(field => {
        if (field.isProtected) {
          this.entry?.fields.set(field.key, ProtectedValue.fromString(field.value));
        } else {
          this.entry?.fields.set(field.key, field.value);
        }
      });

      // 保存图标
      this.setEntryIcon();
      // 保存标签
      this.setTags();
      // 保存条目时间戳
      this.entry.times.update();
      // 保存数据库
      this.saveDatabase();
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', `Failed to save entry: ${error}`);
      this.promptAction.showToast({
        message: $r('app.string.save_entry_failed_message', error.message),
        duration: 2000
      });
      this.isLoading = false;
    }
  }

  /**
   * 保存标签
   */
  private setTags() {
    if(!this.entry){
      return;
    }
    // 保存标签
    if (this.tags) {
      // 将标签字符串分割成数组，支持中英文逗号
      const tagsArray = this.tags.split(/[,，]/).map(tag => tag.trim()).filter(tag => tag);
      this.entry.tags = tagsArray;
    } else {
      this.entry.tags = [];
    }
  }

  /**
   * 设置条目图标
   */
  private setEntryIcon(){
    if(!this.entry || !this.iconId){
      return;
    }
    if(typeof this.iconId === 'number'){
      this.entry.icon = this.iconId as number;
    }else{
      this.entry.customIcon = new KdbxUuid(this.iconId);
    }
  }

  /**
   * 保存数据库
   */
  private saveDatabase() {
    if (this.database) {
      const dbFileParam = FileService.getInstance().getDbFileParam();
      this.database.save().then(async savedDb => {
        const fileManager = new KdbxFileManager(dbFileParam.storageType);
        fileManager.saveKdbxFile(dbFileParam.filePath, savedDb).then(() => {
          this.promptAction.showToast({ message: $r('app.string.save_success_message') });
          this.isLoading = false;
          this.router.back();
        }).catch(this.handleSaveError);
      }).catch(this.handleSaveError);
    }
  }

  /**
   * 处理保存错误
   * @param error 错误信息
   */
  private handleSaveError(error: Error){
    hilog.error(DOMAIN, TAG, '%{public}s', `Failed to save database: ${error}`);
    this.promptAction.showToast({ message: $r('app.string.save_failed_message', error.message) });
    this.isLoading = false;
  }

  /**
   * 打开添加自定义字段对话框
   */
  private openAddFieldDialog() {
    this.isEditingField = false;
    this.currentFieldKey = '';
    this.currentFieldValue = '';
    this.currentFieldProtected = false;
    this.fieldDialogController.open();
  }

  /**
   * 打开编辑自定义字段对话框
   * @param index 字段索引
   */
  private openEditFieldDialog(index: number) {
    const field = this.customFields[index];
    this.isEditingField = true;
    this.editingFieldIndex = index;
    this.currentFieldKey = field.key;
    this.currentFieldValue = field.value;
    this.currentFieldProtected = field.isProtected;
    this.fieldDialogController.open();
  }

  /**
   * 确认自定义字段（添加或更新）
   * @param key 字段名称
   * @param value 字段值
   * @param isProtected 是否受保护
   */
  private confirmCustomField(customField: CustomField) {
    if (this.isEditingField) {
      // 更新字段
      if (this.editingFieldIndex >= 0 && this.editingFieldIndex < this.customFields.length) {
        // 检查字段名称是否已存在（排除当前编辑的字段）
        const existingField = this.customFields.findIndex(field => 
          field.key === customField.key && this.customFields.indexOf(field) !== this.editingFieldIndex);
        
        if (existingField !== -1) {
          this.promptAction.showToast({
            message: $r('app.string.field_name_exists_message'),
            duration: 2000
          });
          return;
        }
        
        this.customFields[this.editingFieldIndex] = {
          key: customField.key,
          value: customField.value,
          isProtected: customField.isProtected
        };
        
        // 重置该字段的可见性状态为隐藏
        this.customFieldsVisibility[this.editingFieldIndex] = false;
        
        // 标记为已修改
        this.isModified = true;
      }
    } else {
      // 添加新字段
      // 检查字段名称是否已存在
      const existingField = this.customFields.find(field => field.key === customField.key);
      if (existingField) {
        this.promptAction.showToast({
          message: $r('app.string.field_name_exists_message'),
          duration: 2000
        });
        return;
      }

      // 添加自定义字段
      this.customFields.push({
        key: customField.key,
        value: customField.value,
        isProtected: customField.isProtected
      });
      
      // 添加新字段的可见性状态，默认为隐藏
      this.customFieldsVisibility.push(false);
      
      // 标记为已修改
      this.isModified = true;
    }
  }
  
  /**
   * 删除自定义字段
   * @param index 字段索引
   */
  private deleteCustomField(index: number) {
    if (index >= 0 && index < this.customFields.length) {
      const fieldKey:string = this.customFields[index].key;
      this.promptAction.showDialog({
        title: $r('app.string.dialog_confirm_title'),
        message: $r('app.string.dialog_delete_confirm_message'),
        buttons: [
          {
            text: $r('app.string.cancel_button_text'),
            color: $r('app.color.text_secondary')
          },
          {
            text: '删除',
            color: $r("app.color.button_bg_blue"),
          }
        ],
      }).then((result) => {
        if (result.index === 1) {
          this.customFields.splice(index, 1);
          // 同时删除对应的可见性状态
          this.customFieldsVisibility.splice(index, 1);
          // 标记为已修改
          this.isModified = true;
        }
      });
    }
  }
  
  /**
   * 切换自定义字段的可见性状态
   * @param index 字段索引
   */
  private toggleCustomFieldVisibility(index: number) {
    if (index >= 0 && index < this.customFieldsVisibility.length) {
      this.customFieldsVisibility[index] = !this.customFieldsVisibility[index];
    }
  }
  
  /**
   * 打开图标选择器对话框
   */
  private openIconSelector() {
    this.iconSelectorController.open();
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .margin({ left: 16 })
            .fillColor($r('app.color.text_primary'))
            .onClick(() => {
              this.router.back();
            })

          Text(this.pageTitle)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .margin({ left: 16 })
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })

          Blank()

          Button() {
            Image($r('app.media.ic_save'))
              .width(24)
              .height(24)
              .fillColor($r('app.color.text_primary'))
          }
          .width(48)
          .height(48)
          .margin({ right: 16 })
          .borderRadius(20)
          .backgroundColor(Color.Transparent)
          .enabled(!this.isLoading && this.isModified)
          .onClick(() => {
            this.saveEntry();
          })
        }
        .width('100%')
        .height(56)
        .backgroundColor($r("app.color.card_bg"))

        // 表单内容
        Scroll() {
          Column() {

            // 标题
            Column() {
              Text(KdbxUtils.getFieldName(KdbxUtils.FIELD_TITLE))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              Row() {
                TextArea({ text: this.title, placeholder: $r('app.string.title_placeholder') })
                  .layoutWeight(1)
                  .fontSize(16)
                  .lineHeight(24)
                  .padding({top:12,bottom:12})
                  .fontColor($r('app.color.text_primary'))
                  .borderRadius(8)
                  .onChange((value) => {
                    this.title = value;
                    this.isModified = true;
                  })

                // 图标选择按钮
                Button() {
                  Image(IconUtils.getIconResourcePath(this.iconId || Icons.Key))
                    .width(24)
                    .height(24)
                    .objectFit(ImageFit.Contain)
                }
                .width(48)
                .height(48)
                .margin({ left: 8 })
                .borderRadius(8)
                .backgroundColor($r("app.color.card_bg"))
                .onClick(() => {
                  this.openIconSelector();
                })
              }
              .width('100%')
            }
            .width('100%')
            .margin({ top: 16 })

            // 用户名
            Column() {
              Text(KdbxUtils.getFieldName(KdbxUtils.FIELD_USERNAME))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              TextArea({ text: this.username, placeholder: $r('app.string.username_placeholder') })
                .width('100%')
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .borderRadius(8)
                .lineHeight(24)
                .padding({top:12,bottom:12})
                .onChange((value) => {
                  this.username = value;
                  this.isModified = true;
                })
            }
            .width('100%')
            .margin({ top: 16 })

            // 密码
            Column() {
              Row() {
                Text(KdbxUtils.getFieldName(KdbxUtils.FIELD_PASSWORD))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))

                Blank()

                Button($r('app.string.generate_button_text'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r("app.color.card_bg"))
                  .padding({
                    left: 12,
                    right: 12,
                    top: 4,
                    bottom: 4
                  })
                  .borderRadius(4)
                  .onClick(() => {
                    this.passwordGeneratorController.open();
                  })
              }
              .width('100%')
              .margin({ bottom: 8 })

              Row() {
                TextInput({ text: this.password, placeholder: $r('app.string.password_placeholder') })
                  .width('100%')
                  .height(48)
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .borderRadius(8)
                  .type(this.showPassword ? InputType.Normal : InputType.Password)
                  .onChange((value) => {
                    this.password = value;
                    this.isModified = true;
                  })
              }
              .width('100%')
              .height(48)
            }
            .width('100%')
            .margin({ top: 16 })

            // URL
            Column() {
              Text(KdbxUtils.getFieldName(KdbxUtils.FIELD_URL))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              TextArea({ text: this.url, placeholder: $r('app.string.url_placeholder') })
                .width('100%')
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .borderRadius(8)
                .lineHeight(24)
                .padding({top:12,bottom:12})
                .onChange((value) => {
                  this.url = value;
                  this.isModified = true;
                })
            }
            .width('100%')
            .margin({ top: 16 })

            // 标签
            Column() {
              Text(KdbxUtils.getFieldName(KdbxUtils.FIELD_TAGS))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              TextArea({ text: this.tags, placeholder: $r('app.string.tags_placeholder') })
                .width('100%')
                .lineHeight(24)
                .padding({top:12,bottom:12})
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .borderRadius(8)
                .onChange((value) => {
                  this.tags = value;
                  this.isModified = true;
                })
            }
            .width('100%')
            .margin({ top: 16 })

            // 备注
            Column() {
              Text(KdbxUtils.getFieldName(KdbxUtils.FIELD_NOTES))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              TextArea({ text: this.notes, placeholder: $r('app.string.notes_placeholder') })
                .width('100%')
                .height(96)
                .lineHeight(24)
                .padding({top:12,bottom:12})
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .borderRadius(8)
                .onChange((value) => {
                  this.notes = value;
                  this.isModified = true;
                })
            }
            .width('100%')
            .margin({ top: 16 })

            // 自定义字段部分
            Column() {
              Row() {
                Text(KdbxUtils.getFieldName(KdbxUtils.FIELD_CUSTOM_FIELDS))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .alignSelf(ItemAlign.Start)

                Blank()

                Button() {
                  Image($r('app.media.ic_add'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.text_primary'))
                }
                .width(32)
                .height(32)
                .backgroundColor($r("app.color.card_bg"))
                .borderRadius(16)
                .onClick(() => {
                  this.openAddFieldDialog();
                })
              }
              .width('100%')
              .margin({ bottom: 8 })

              // 自定义字段列表
              if (this.customFields.length > 0) {
                ForEach(this.customFields, (field: CustomField, index) => {
                  Column() {
                    Row() {
                      Text(field.key)
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                        .margin({ bottom: 8 })

                      Blank()

                      Button() {
                        Image($r('app.media.ic_edit'))
                          .width(16)
                          .height(16)
                          .fillColor($r('app.color.text_primary'))

                      }
                      .width(32)
                      .height(32)
                      .borderRadius(16)
                      .backgroundColor($r("app.color.bg_secondary"))
                      .onClick(() => {
                        this.openEditFieldDialog(index);
                      })

                      Button() {
                        Image($r('app.media.ic_delete'))
                          .width(16)
                          .height(16)
                          .fillColor($r('app.color.text_primary'))
                      }
                      .width(32)
                      .height(32)
                      .borderRadius(16)
                      .backgroundColor($r("app.color.bg_secondary"))
                      .onClick(() => {
                        this.deleteCustomField(index);
                      })
                    }
                    .width('100%')

                    Row() {
                      Text(field.isProtected && !this.customFieldsVisibility[index] ? '******' : field.value)
                        .fontSize(16)
                        .fontColor($r('app.color.text_primary'))
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .maxLines(1)
                        .layoutWeight(1)

                      if (field.isProtected) {
                        Image(this.customFieldsVisibility[index] ? $r('app.media.ic_eye_off') : $r('app.media.ic_eye'))
                          .width(24)
                          .height(24)
                          .fillColor($r('app.color.text_secondary'))
                          .margin({ left: 8 })
                          .onClick((event) => {
                            this.toggleCustomFieldVisibility(index);
                            return false;
                          })
                      }
                    }
                    .width('100%')
                    .alignItems(VerticalAlign.Center)
                  }
                  .width('100%')
                  .height('auto')
                  .padding({top: 12, bottom: 12, left: 12})
                  .backgroundColor($r("app.color.bg_secondary"))
                  .borderRadius(8)
                  .margin({ bottom: 8 })
                  .onClick(() => {
                    this.openEditFieldDialog(index);
                  })
                })
              } else {
                Text($r('app.string.no_custom_fields_message'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 8, bottom: 8 })
              }
            }
            .width('100%')
            .margin({ top: 16, bottom: 24 })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .backgroundColor($r("app.color.bg_primary"))
      }
      .width('100%')
      .height('100%')
    }
    .height('100%')
    .width('100%')
  }
}
