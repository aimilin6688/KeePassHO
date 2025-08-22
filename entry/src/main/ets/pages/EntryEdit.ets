import { Kdbx, KdbxBinary, KdbxBinaryWithHash, KdbxEntry, KdbxGroup, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';

import { Router } from '@kit.ArkUI';
import { FileService } from '../services/FileService';
import KdbxUtils from '../common/utils/KdbxUtils';
import IconUtils from '../common/utils/IconUtils';
import { CustomField, EntryParam, Icons } from '../services/TypeDefined';
import { EntryEditFieldDialog } from '../components/EntryEditFieldDialog';
import { IconSelectorDialog } from '../components/IconSelectorDialog';
import { PasswordGeneratorDialog } from '../components/PasswordGeneratorDialog';
import ResourceManager from '../common/utils/ResourceManager';
import DateUtils from '../common/utils/DateUtils';
import { ContextLoadingDialog } from '../components/ContextLoadingDialog';
import { CommonUtils } from '../common/utils/CommonUtils';
import { TotpConfigDialog } from '../components/TotpConfigDialog';
import FileUtils from '../common/utils/FIleUtils';

const DOMAIN = 0xFF00;
const TAG = 'EntryEdit';

@Entry
@Component
struct EntryEdit {
  @State title: string = '';
  @State username: string = '';
  @State password: string = '';
  @State url: string = '';
  @State overrideUrl: string | undefined = undefined;
  @State notes: string = '';
  @State showPassword: boolean = false;
  @State isLoading: boolean = false;
  @State isEditMode: boolean = false;
  @State pageTitle: string = ResourceManager.getString($r('app.string.add_entry_button'));
  @State customFields: CustomField[] = []; // 自定义字段列表
  @State showFieldDialog: boolean = false; // 显示自定义字段对话框
  @State isEditingField: boolean = false; // 是否是编辑字段模式
  @State editingFieldIndex: number = -1; // 正在编辑的字段索引
  @State currentFieldKey: string = ''; // 当前字段的键
  @State currentFieldValue: string = ''; // 当前字段的值
  @State currentFieldProtected: boolean = false; // 当前字段是否受保护
  @State customFieldsVisibility: boolean[] = []; // 自定义字段值的可见性状态
  @State isModified: boolean = false; // 是否有字段被修改
  @State iconId: number | string | undefined = Icons.Key; // 当前选择的图标ID
  @State tags: string = ''; // 标签，以逗号分隔
  @State expiryTime: Date | undefined = undefined; // 过期时间
  @State isExpiryEnabled: boolean | null | undefined = undefined; // 是否启用过期时间
  @State loadingMessage: string = ResourceManager.getString($r('app.string.loading_message'));
  @State attachments: Map<string, KdbxBinary | KdbxBinaryWithHash> = new Map<string, KdbxBinary | KdbxBinaryWithHash>();
  private database: Kdbx | null = null;
  private parentGroup: KdbxGroup | undefined = undefined;
  private entry: KdbxEntry | null = null;
  private standardFields: Array<string> = [KdbxUtils.FIELD_TITLE, KdbxUtils.FIELD_USERNAME, KdbxUtils.FIELD_PASSWORD, KdbxUtils.FIELD_URL, KdbxUtils.FIELD_NOTES];
  private router: Router = this.getUIContext().getRouter();
  private promptAction = this.getUIContext().getPromptAction();
  // 自定义字段对话框控制器
  private fieldDialogController: CustomDialogController = new CustomDialogController({
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
  private iconSelectorController: CustomDialogController = new CustomDialogController({
    builder: IconSelectorDialog({
      selectedIconId: this.iconId,
      onIconSelected: (iconId: number | string) => {
        this.iconId = iconId;
        this.checkEntryModified();
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });
  // 密码生成器弹框
  private passwordGeneratorController: CustomDialogController = new CustomDialogController({
    builder: PasswordGeneratorDialog({
      password: this.password,
      onGenerate: (password: string) => {
        this.password = password;
        this.checkEntryModified();
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true
  });
  // 带内容的进度弹框
  private loadingDialogController: CustomDialogController = new CustomDialogController({
    builder: ContextLoadingDialog({
      loadingMessage: this.loadingMessage,
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });
  // otp令牌弹框
  private otpDialogController: CustomDialogController = new CustomDialogController({
    builder: TotpConfigDialog({
      name: this.title,
      issuer: this.username,
      checkFieldName: (fieldName: string) => {
        return this.checkCustomField(fieldName);
      },
      onConfirm: (fieldName: string, otpUrl: string) => {
        this.confirmCustomField({
          key: fieldName,
          value: otpUrl,
          isProtected: true
        } as CustomField);
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true
  });

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
      this.pageTitle = ResourceManager.getString($r("app.string.edit_entry"));


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
      this.overrideUrl = this.entry.overrideUrl;

      // 加载标签
      this.notes = KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_NOTES);

      // 加载标签
      if (this.entry.tags && this.entry.tags.length > 0) {
        this.tags = this.entry.tags.join(', ');
      }

      // 加载图标ID
      this.iconId = this.entry.customIcon ? this.entry.customIcon.id : this.entry.icon;

      // 过期时间
      this.expiryTime = this.entry.times.expiryTime;
      this.isExpiryEnabled = this.entry.times.expires;

      // 加载自定义字段
      this.loadCustomFields();

      // 加载附件
      this.attachments = this.entry.binaries;

      // 检验是否修改了
      this.isModified = false;
    } else {
      this.isEditMode = false;
      this.username = this.database.meta.defaultUser || '';
    }
  }

  onBackPress() {
    if (this.isModified) {
      CommonUtils.showUnSaveConfirm(this.getUIContext(), {
        onConfirm: () => {
          this.router.back();
        }
      });
      return true;
    }
    return false;
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
        if (this.standardFields.includes(key)) {
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
    this.loadingDialogController.open();

    try {
      if (this.isEditMode && this.entry) {
        // 添加到历史记录中
        this.pushEntryToHistory();
        this.loadingMessage = ResourceManager.getString($r('app.string.load_save_history'));
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
      this.entry.overrideUrl = this.overrideUrl;
      this.entry.times.expires = this.isExpiryEnabled;
      this.entry.times.expiryTime = this.isExpiryEnabled ? this.expiryTime : undefined;

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
      this.loadingDialogController.close();
    }
  }

  /**
   * 添加条目到历史记录
   */
  private pushEntryToHistory() {
    if (!this.database || !this.entry) {
      return;
    }
    // 限制历史条目格式
    const historyMaxItems = this.database.meta.historyMaxItems;
    if (historyMaxItems && historyMaxItems > 0 && this.entry.history.length >= historyMaxItems) {
      const deleteCount = this.entry.history.length - historyMaxItems + 1;
      this.entry.removeHistory(0, deleteCount);
    }
    // TODO 限制历史条目总大小

    // 添加到历史记录中
    this.entry.pushHistory();
  }

  /**
   * 保存标签
   */
  private setTags() {
    if (!this.entry) {
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
  private setEntryIcon() {
    if (!this.entry || !this.iconId) {
      return;
    }
    if (typeof this.iconId === 'number') {
      this.entry.icon = this.iconId as number;
      this.entry.customIcon = undefined;
    } else {
      this.entry.icon = undefined;
      this.entry.customIcon = new KdbxUuid(this.iconId);
    }
  }

  /**
   * 保存数据库
   */
  private saveDatabase() {
    if (this.database) {
      this.loadingMessage = ResourceManager.getString($r('app.string.load_save_database'));
      KdbxUtils.saveDatabase({
        showToast: false,
        onSuccess: () => {
          this.loadingMessage = ResourceManager.getString($r("app.string.save_success"));
          let timeOut = setTimeout(() => {
            this.isLoading = false;
            this.loadingDialogController.close();
            this.router.back();
            clearTimeout(timeOut);
          }, 150);
        },
        onMessage: (message) => {
          this.loadingMessage = message;
        },
        onError: (error) => {
          this.handleSaveError(error);
        }
      })
    }
  }

  /**
   * 处理保存错误
   * @param error 错误信息
   */
  private handleSaveError(error: string) {
    hilog.error(DOMAIN, TAG, '%{public}s', `Failed to save database: ${error}`);
    this.promptAction.showToast({ message: $r('app.string.save_failed_message', error) });
    this.isLoading = false;
    this.loadingDialogController.close();
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
   * 检测自定义字段名称是否存在
   * @param customFieldName 字段名称
   * @returns 结果
   */
  private checkCustomField(customFieldName: string): boolean {
    // 检查字段名称是否已存在（排除当前编辑的字段）
    const existingField = this.customFields.findIndex(field => field.key === customFieldName && this.customFields.indexOf(field) !== this.editingFieldIndex);
    return existingField !== -1;
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
        if (this.checkCustomField(customField.key)) {
          this.promptAction.showToast({
            message: $r("app.string.field_name_exists"),
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
        this.checkEntryModified();
        this.fieldDialogController.close();
      }
    } else {
      // 添加新字段
      // 检查字段名称是否已存在
      const existingField = this.customFields.find(field => field.key === customField.key);
      if (existingField) {
        this.promptAction.showToast({
          message: $r("app.string.field_name_exists"),
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
      this.checkEntryModified();
      this.fieldDialogController.close();
    }
  }

  /**
   * 删除自定义字段
   * @param index 字段索引
   */
  private deleteCustomField(index: number) {
    if (index >= 0 && index < this.customFields.length) {
      const fieldKey: string = this.customFields[index].key;
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
          this.checkEntryModified();
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

  /**
   * 日期时间选择
   */
  private openExpiryTimePicker() {
    this.getUIContext().showDatePickerDialog({
      start: new Date(),
      end: new Date('2099-12-31'),
      selected: this.expiryTime,
      showTime: true,
      useMilitaryTime: true,
      onDateAccept: (value: Date) => {
        this.expiryTime = value;
        this.checkEntryModified();
      }
    });
  }

  /**
   * 判断实体是否被修改了
   */
  private checkEntryModified() {
    if (this.isModified) {
      return;
    }
    // 标题修改了
    if (this.entry == null) {
      if (this.title != '') {
        this.isModified = true;
      }
      return;
    }
    if (KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_TITLE) != this.title.trim()) {
      this.isModified = true;
      return;
    }
    if (KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_USERNAME) != this.username.trim()) {
      this.isModified = true;
      return;
    }
    if (KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_PASSWORD) != this.password.trim()) {
      this.isModified = true;
      return;
    }
    if (KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_URL) != this.url.trim()) {
      this.isModified = true;
      return;
    }
    if (KdbxUtils.getFieldValueString(this.entry.fields, KdbxUtils.FIELD_NOTES) != this.notes.trim()) {
      this.isModified = true;
      return;
    }
    if (this.entry.overrideUrl != this.overrideUrl) {
      this.isModified = true;
      return;
    }
    if (this.entry.times.expires != this.isExpiryEnabled) {
      this.isModified = true;
      return;
    }
    if (DateUtils.format(this.entry.times.expiryTime) != DateUtils.format(this.expiryTime)) {
      this.isModified = true;
      return;
    }
    // 自定义字段删除
    let customKeys = this.customFields.map((item) => item.key);
    for (let key of this.entry.fields.keys()) {
      if (this.standardFields.includes(key)) {
        continue;
      }
      if (!customKeys.includes(key)) {
        this.isModified = true;
        return;
      }
    }


    for (let item of this.customFields) {
      // 标准字段不计入
      if (this.standardFields.includes(item.key)) {
        continue;
      }
      if (!this.entry.fields.has(item.key)) {
        this.isModified = true;
        return;
      }
      if (KdbxUtils.getFieldValueString(this.entry.fields, item.key) != item.value) {
        this.isModified = true;
        return;
      }
      // 保护类型变更
      let entryProtected = this.entry.fields.get(item.key) instanceof ProtectedValue;
      if (entryProtected != item.isProtected) {
        this.isModified = true;
        return;
      }
    }

    if (typeof this.iconId === 'number') {
      if (this.entry.icon != this.iconId) {
        1
        this.isModified = true;
        return;
      }
    } else if (typeof this.iconId === 'string') {
      if (this.entry.customIcon?.id != this.iconId) {
        this.isModified = true;
        return;
      }
    }
    if (this.entry.tags.join(", ") != this.tags) {
      this.isModified = true;
      return;
    }
  }

  // 添加附件
  private addAttachment() {
    FileUtils.selectFiles(1).then(result => {
      for (let file of result) {
        this.attachments.set(file.name, file.content);
      }
      this.isModified = true;
    }).catch((error: Error) => {
      this.promptAction.showToast({ message: error.message })
    });
  }

  // 删除附件
  private deleteAttachment(key: string) {
    this.attachments.delete(key);
    this.isModified = true;
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Image($r("app.media.ic_angle_left"))
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
              .width(26)
              .height(26)
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
              Row() {
                Text("*").fontColor($r('app.color.required'))
                Text(KdbxUtils.getFieldName(KdbxUtils.FIELD_TITLE))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ bottom: 8 })
                  .alignSelf(ItemAlign.Start)
              }.width('100%')

              Row() {
                TextArea({ text: this.title, placeholder: $r('app.string.title_placeholder') })
                  .layoutWeight(1)
                  .fontSize(16)
                  .lineHeight(24)
                  .padding({ top: 12, bottom: 12 })
                  .fontColor($r('app.color.text_primary'))
                  .borderRadius(8)
                  .onChange((value) => {
                    this.title = value;
                    this.checkEntryModified();
                  })

                // 图标选择按钮
                Button() {
                  Image(IconUtils.getIconResourcePath(this.iconId || Icons.Key))
                    .width(32)
                    .height(32)
                    .borderRadius(8)
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
                .padding({ top: 12, bottom: 12 })
                .onChange((value) => {
                  this.username = value;
                  this.checkEntryModified();
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
                    this.checkEntryModified();
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
                .padding({ top: 12, bottom: 12 })
                .onChange((value) => {
                  this.url = value;
                  this.checkEntryModified();
                })
            }
            .width('100%')
            .margin({ top: 16 })

            // Override URL
            Column() {
              Text(KdbxUtils.getFieldName(KdbxUtils.FIELD_OVERRIDE_URL))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              TextArea({ text: this.overrideUrl, placeholder: $r('app.string.override_url_placeholder') })
                .width('100%')
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .borderRadius(8)
                .lineHeight(24)
                .padding({ top: 12, bottom: 12 })
                .onChange((value) => {
                  this.overrideUrl = value;
                  this.checkEntryModified();
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
                .padding({ top: 12, bottom: 12 })
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .borderRadius(8)
                .onChange((value) => {
                  this.tags = value;
                  this.checkEntryModified();
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
                .padding({ top: 12, bottom: 12 })
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .borderRadius(8)
                .onChange((value) => {
                  this.notes = value;
                  this.checkEntryModified();
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
                  .height(32)

                Blank()

                Button() {
                  Text('OTP')
                    .width(56)
                    .height(24)
                    .fontColor($r('app.color.text_primary'))
                    .textAlign(TextAlign.Center)
                }
                .height(32)
                .backgroundColor($r("app.color.card_bg"))
                .borderRadius(16)
                .margin({ right: 5 })
                .onClick(() => {
                  this.otpDialogController.open();
                })

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
                        .height(32)
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
                        .lineHeight(24)
                        .borderWidth(0)
                        .padding({
                          left: 0,
                          right: 0
                        })
                        .layoutWeight(1)
                        .backgroundColor($r("app.color.bg_secondary"))
                        .onClick(() => {
                          this.openEditFieldDialog(index);
                        })

                      if (field.isProtected) {
                        Image(this.customFieldsVisibility[index] ? $r('app.media.ic_eye_off') : $r('app.media.ic_eye'))
                          .width(24)
                          .height(24)
                          .fillColor($r('app.color.text_secondary'))
                          .margin({ left: 8, right: 8 })
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
                  .padding({ top: 12, bottom: 12, left: 12 })
                  .backgroundColor($r("app.color.bg_secondary"))
                  .borderRadius(8)
                  .margin({ bottom: 8 })
                })
              } else {
                Text($r('app.string.no_custom_fields_message'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ top: 8, bottom: 8 })
              }
            }
            .width('100%')
            .margin({ top: 16 })

            // 附件
            Column() {
              Row() {
                Text($r('app.string.attachment'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .alignSelf(ItemAlign.Start)
                  .height(32)
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
                  this.addAttachment();
                })
              }
              .width('100%')
              .margin({ bottom: 8 })

              ForEach(Array.from(this.attachments.keys()), (field: string, index) => {
                Column() {
                  Row() {
                    Text(field)
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                      .height(32)
                      .width('90%')
                    Blank()
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
                      this.deleteAttachment(field);
                    })
                  }
                  .width('100%')
                }
                .width('100%')
                .height('auto')
                .padding({ top: 12, bottom: 12, left: 12 })
                .backgroundColor($r("app.color.bg_secondary"))
                .borderRadius(8)
                .margin({ bottom: 8 })
              });
            }
            .width('100%')
            .margin({ top: 16, bottom: 24 })

            // 过期时间
            Column() {
              Text(KdbxUtils.getFieldName(KdbxUtils.FIELD_EXPIRY_TIME))
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))
                .margin({ bottom: 8 })
                .alignSelf(ItemAlign.Start)

              Row() {
                Toggle({ type: ToggleType.Switch, isOn: this.isExpiryEnabled })
                  .onChange((isOn: boolean) => {
                    this.isExpiryEnabled = isOn;
                    this.expiryTime = this.expiryTime ? this.expiryTime : new Date();
                    this.checkEntryModified();
                  })
                  .margin({ right: 16 })

                if (this.isExpiryEnabled) {
                  Text(DateUtils.format(this.expiryTime))
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                    .layoutWeight(1)
                    .height(48)
                    .onClick(() => {
                      this.openExpiryTimePicker();
                    })
                }
              }
              .width('100%')
              .height(48)
              .borderRadius(8)
              .backgroundColor($r("app.color.bg_secondary"))
              .padding({ left: 12, right: 12 })
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
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
  }
}
