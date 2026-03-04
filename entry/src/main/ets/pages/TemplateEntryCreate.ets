/**
 * 模板创建条目页面
 * 根据选中的模板只显示模板定义的字段
 */
import { Kdbx, KdbxGroup, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Router } from '@kit.ArkUI';
import { FileService } from '../services/FileService';
import { CommonUtils, IconUtils, KdbxUtils, ResourceManager, WindowUtils } from '../common/utils';
import { Icons } from '../services/TypeDefined';
import { IconSelectorDialog } from '../components/IconSelectorDialog';
import { PasswordGeneratorDialog } from '../components/PasswordGeneratorDialog';
import { ContextLoadingDialog } from '../components/ContextLoadingDialog';
import { ITemplate, IPresetTemplate, IUserTemplate, ITemplateField, isPresetTemplate } from '../services/template/TemplateTypes';
import { TemplateService } from '../services/template/TemplateService';
import { ToastSaveDatabaseCallback } from '../workers/callback/ToastSaveDatabaseCallback';
import { common } from '@kit.AbilityKit';

const DOMAIN = 0xFF00;
const TAG = 'TemplateEntryCreate';

/**
 * 模板字段数据
 */
interface TemplateFieldData {
  key: string;
  value: string;
  isProtected: boolean;
  isVisible: boolean;
  placeholder: ResourceStr;
  displayName: ResourceStr;
}

@Entry
@Component
struct TemplateEntryCreate {
  @State title: string = '';
  @State template: ITemplate | null = null;
  @State templateName: ResourceStr = '';
  @State iconId: number | string = Icons.Key;
  @State tags: string = '';
  @State isLoading: boolean = false;
  @State isModified: boolean = false;
  @State fieldDataList: TemplateFieldData[] = [];
  @State loadingMessage: string = ResourceManager.getString($r('app.string.loading_message'));

  private database: Kdbx | null = null;
  private parentGroup: KdbxGroup | undefined = undefined;
  private router: Router = this.getUIContext().getRouter();
  private templateService: TemplateService = TemplateService.getInstance();

  // 图标选择器对话框控制器
  private iconSelectorController: CustomDialogController = new CustomDialogController({
    builder: IconSelectorDialog({
      selectedIconId: this.iconId,
      onIconSelected: (iconId: number | string) => {
        this.iconId = iconId;
        this.isModified = true;
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });

  // 密码生成器弹框
  private passwordGeneratorController: CustomDialogController = new CustomDialogController({
    builder: PasswordGeneratorDialog({
      password: '',
      onGenerate: (password: string) => {
        // 找到当前正在编辑的密码字段并更新
        const newList: TemplateFieldData[] = [];
        for (let i = 0; i < this.fieldDataList.length; i++) {
          const field = this.fieldDataList[i];
          if (field.key === KdbxUtils.FIELD_PASSWORD) {
            newList.push({
              key: field.key,
              value: password,
              isProtected: field.isProtected,
              isVisible: field.isVisible,
              placeholder: field.placeholder,
              displayName: field.displayName
            });
          } else {
            newList.push(field);
          }
        }
        this.fieldDataList = newList;
        this.isModified = true;
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
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

  aboutToAppear() {
    // 获取数据库信息
    const params = FileService.getInstance().getDbFileParam();
    this.database = params.database ?? null;

    // 获取路由参数
    const routeParams = this.router.getParams() as Record<string, Object>;

    if (!this.database) {
      CommonUtils.showToast({
        message: $r("app.string.invalid_database"),
        duration: 2000
      });
      this.router.back();
      return;
    }

    // 获取父分组
    if (routeParams['groupId']) {
      this.parentGroup = this.database.getGroup(routeParams['groupId'] as string);
    } else {
      this.parentGroup = this.database.getDefaultGroup();
    }

    if (!this.parentGroup) {
      CommonUtils.showToast({
        message: $r("app.string.invalid_group"),
        duration: 2000
      });
      this.router.back();
      return;
    }

    // 获取模板
    const templateId = routeParams['templateId'] as string;
    const isPreset = routeParams['isPreset'] as boolean;

    if (templateId) {
      if (isPreset) {
        const presetTemplates = this.templateService.getPresetTemplates();
        this.template = presetTemplates.find(t => t.id === templateId) ?? null;
      } else {
        this.template = this.templateService.getUserTemplateById(this.database, templateId);
      }
    }

    if (!this.template) {
      CommonUtils.showToast({
        message: $r('app.string.template_empty'),
        duration: 2000
      });
      this.router.back();
      return;
    }

    // 初始化模板数据
    this.initTemplateData();
  }

  onPageShow(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
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
   * 初始化模板数据
   */
  private initTemplateData() {
    if (!this.template) {
      return;
    }
    // 获取模板名称
    if (isPresetTemplate(this.template)) {
      const preset = this.template as IPresetTemplate;
      this.templateName = preset.nameRes ? preset.nameRes : preset.name;
      this.iconId = preset.iconId;
    } else {
      const userTemplate = this.template as IUserTemplate;
      this.templateName = userTemplate.name;
      this.iconId = userTemplate.iconId;
    }

    // 初始化字段列表
    this.fieldDataList = [];

    // 添加标准字段（如果模板中定义了）
    const standardFields = this.template.standardFields;
    if (standardFields) {
      // 标题字段
      this.fieldDataList.push({
        key: KdbxUtils.FIELD_TITLE,
        value: standardFields.title ?? '',
        isProtected: false,
        isVisible: true,
        placeholder: $r('app.string.title_placeholder'),
        displayName: KdbxUtils.getFieldName(KdbxUtils.FIELD_TITLE) ?? KdbxUtils.FIELD_TITLE
      });

      // 用户名字段
      if (standardFields.username !== undefined || this.shouldShowField(KdbxUtils.FIELD_USERNAME)) {
        this.fieldDataList.push({
          key: KdbxUtils.FIELD_USERNAME,
          value: standardFields.username ?? '',
          isProtected: false,
          isVisible: true,
          placeholder: $r('app.string.username_placeholder'),
          displayName: KdbxUtils.getFieldName(KdbxUtils.FIELD_USERNAME) ?? KdbxUtils.FIELD_USERNAME
        });
      }

      // 密码字段
      if (standardFields.password !== undefined || this.shouldShowField(KdbxUtils.FIELD_PASSWORD)) {
        this.fieldDataList.push({
          key: KdbxUtils.FIELD_PASSWORD,
          value: standardFields.password ?? '',
          isProtected: true,
          isVisible: false,
          placeholder: $r('app.string.password_placeholder'),
          displayName: KdbxUtils.getFieldName(KdbxUtils.FIELD_PASSWORD) ?? KdbxUtils.FIELD_PASSWORD
        });
      }

      // URL字段
      if (standardFields.url !== undefined || this.shouldShowField(KdbxUtils.FIELD_URL)) {
        this.fieldDataList.push({
          key: KdbxUtils.FIELD_URL,
          value: standardFields.url ?? '',
          isProtected: false,
          isVisible: true,
          placeholder: $r('app.string.webdav_url_placeholder'),
          displayName: KdbxUtils.getFieldName(KdbxUtils.FIELD_URL) ?? KdbxUtils.FIELD_URL
        });
      }

      // 备注字段
      if (standardFields.notes !== undefined || this.shouldShowField(KdbxUtils.FIELD_NOTES)) {
        this.fieldDataList.push({
          key: KdbxUtils.FIELD_NOTES,
          value: standardFields.notes ?? '',
          isProtected: false,
          isVisible: true,
          placeholder: $r('app.string.notes_placeholder'),
          displayName: KdbxUtils.getFieldName(KdbxUtils.FIELD_NOTES) ?? KdbxUtils.FIELD_NOTES
        });
      }
    }

    // 添加自定义字段
    if (this.template.customFields && this.template.customFields.length > 0) {
      for (const field of this.template.customFields) {
        this.fieldDataList.push({
          key: field.key,
          value: field.value ?? '',
          isProtected: field.isProtected ?? false,
          isVisible: false,
          placeholder: this.getFieldPlaceholder(field.key),
          displayName: this.getFieldDisplayName(field)
        });
      }
    }

    // 应用模板标签
    if (this.template.tags && this.template.tags.length > 0) {
      this.tags = this.template.tags.join(', ');
    }
  }

  /**
   * 判断是否应该显示该字段
   */
  private shouldShowField(fieldName: string): boolean {
    if (!this.template!.customFields) {
      return false;
    }
    return this.template!.customFields.some(f => f.key === fieldName);
  }

  /**
   * 获取字段显示名称
   */
  private getFieldDisplayName(field: ITemplateField): ResourceStr {
    if (field.keyRes) {
      return field.keyRes;
    }
    return field.key;
  }

  /**
   * 获取字段占位符
   */
  private getFieldPlaceholder(key: string): ResourceStr {
    // 根据字段键名返回对应的占位符
    const placeholderMap: Record<string, ResourceStr> = {
      'id_number': $r('app.string.template_placeholder_id_card'),
      'gender': $r('app.string.template_placeholder_gender'),
      'birth_date': $r('app.string.template_placeholder_date'),
      'expiry_date': $r('app.string.template_placeholder_expiry'),
      'bank_card_number': $r('app.string.template_placeholder_bank_card_number'),
      'credit_card_number': $r('app.string.template_placeholder_credit_card_number'),
      'cvv': $r('app.string.template_placeholder_cvv'),
      'card_type': $r('app.string.template_placeholder_card_type'),
      'card_network': $r('app.string.template_placeholder_card_network'),
      'billing_day': $r('app.string.template_placeholder_billing_day'),
      'payment_day': $r('app.string.template_placeholder_payment_day'),
      'chain_type': $r('app.string.template_placeholder_chain_type'),
      'mnemonic': $r('app.string.template_placeholder_keep_safe'),
      'ssid': $r('app.string.template_placeholder_ssid'),
      'security_type': $r('app.string.template_placeholder_security_type'),
      'frequency': $r('app.string.template_placeholder_frequency'),
      'hidden_network': $r('app.string.template_placeholder_hidden_network'),
      'protocol': $r('app.string.template_placeholder_vpn_protocol'),
      'private_key': $r('app.string.template_placeholder_pem_key'),
      'public_key': $r('app.string.template_placeholder_public_key'),
      'key_passphrase': $r('app.string.template_placeholder_key_passphrase'),
      'db_type': $r('app.string.template_placeholder_db_type'),
      'os': $r('app.string.template_placeholder_os'),
      'provider': $r('app.string.template_placeholder_provider'),
      'license_type': $r('app.string.template_placeholder_license_type'),
      'git_platform': $r('app.string.template_placeholder_git_platform'),
    };
    return placeholderMap[key] ?? '';
  }

  /**
   * 切换字段可见性
   */
  private toggleFieldVisibility(index: number) {
    this.fieldDataList[index].isVisible = !this.fieldDataList[index].isVisible;
  }

  /**
   * 更新字段值
   */
  private updateFieldValue(index: number, value: string) {
    this.fieldDataList[index].value = value;
    this.isModified = true;
  }

  /**
   * 打开图标选择器
   */
  private openIconSelector() {
    this.iconSelectorController.open();
  }

  /**
   * 打开密码生成器
   */
  private openPasswordGenerator() {
    this.passwordGeneratorController.open();
  }

  /**
   * 保存条目
   */
  private saveEntry() {
    if (!this.database || !this.parentGroup || !this.template) {
      CommonUtils.showToast({
        message: $r('app.string.EntryEdit_invalid_db_or_group'),
        duration: 2000
      });
      return;
    }

    // 获取标题
    const titleField = this.fieldDataList.find(f => f.key === KdbxUtils.FIELD_TITLE);
    const title = titleField?.value ?? '';

    if (!title.trim()) {
      CommonUtils.showToast({
        message: $r('app.string.title_required_message'),
        duration: 2000
      });
      return;
    }

    this.isLoading = true;
    this.loadingDialogController.open();

    try {
      // 创建新条目
      const entry = this.database.createEntry(this.parentGroup);

      const memoryProtection = this.database.meta.memoryProtection ?? {};

      // 设置所有字段
      for (const fieldData of this.fieldDataList) {
        if (fieldData.key === KdbxUtils.FIELD_TITLE) {
          entry.setField(KdbxUtils.FIELD_TITLE, fieldData.value, memoryProtection.title);
        } else if (fieldData.key === KdbxUtils.FIELD_USERNAME) {
          entry.setField(KdbxUtils.FIELD_USERNAME, fieldData.value, memoryProtection.userName);
        } else if (fieldData.key === KdbxUtils.FIELD_PASSWORD) {
          entry.setField(KdbxUtils.FIELD_PASSWORD, fieldData.value, memoryProtection.password ?? true);
        } else if (fieldData.key === KdbxUtils.FIELD_URL) {
          entry.setField(KdbxUtils.FIELD_URL, fieldData.value, memoryProtection.url);
        } else if (fieldData.key === KdbxUtils.FIELD_NOTES) {
          entry.setField(KdbxUtils.FIELD_NOTES, fieldData.value, memoryProtection.notes);
        } else {
          // 自定义字段
          if (fieldData.isProtected) {
            entry.fields.set(fieldData.key, ProtectedValue.fromString(fieldData.value));
          } else {
            entry.fields.set(fieldData.key, fieldData.value);
          }
        }
      }

      // 设置图标
      if (typeof this.iconId === 'number') {
        entry.icon = this.iconId as number;
        entry.customIcon = undefined;
      } else {
        entry.icon = undefined;
        entry.customIcon = new KdbxUuid(this.iconId);
      }

      // 设置标签
      if (this.tags) {
        const tagsArray = this.tags.split(/[,，]/).map(tag => tag.trim()).filter(tag => tag);
        entry.tags = tagsArray;
      } else {
        entry.tags = [];
      }

      // 更新时间戳
      entry.times.update();

      // 保存数据库
      this.loadingMessage = ResourceManager.getString($r('app.string.load_save_database'));
      KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
        onSuccess: () => {
          CommonUtils.showToast($r('app.string.save_success'));
          this.loadingMessage = ResourceManager.getString($r("app.string.save_success"));
          setTimeout(() => {
            this.isLoading = false;
            this.loadingDialogController.close();
            this.router.back();
          }, 150);
        },
        onMessage: (message: string) => {
          this.loadingMessage = message;
        },
        onError: (error: string) => {
          hilog.error(DOMAIN, TAG, 'Failed to save database: %{public}s', error);
          CommonUtils.showToast({ message: $r('app.string.save_failed_message', error) });
          this.isLoading = false;
          this.loadingDialogController.close();
        }
      }));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to save entry: %{public}s', error);
      CommonUtils.showToast({
        message: $r('app.string.save_entry_failed_message', error),
        duration: 2000
      });
      this.isLoading = false;
      this.loadingDialogController.close();
    }
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

          Text(this.templateName)
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

        // 表单内容
        Scroll() {
          Column() {
            // 标题字段（带图标选择）
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
                TextArea({ text: this.fieldDataList.length > 0 ? this.fieldDataList[0].value : '', 
                  placeholder: $r('app.string.title_placeholder') })
                  .layoutWeight(1)
                  .fontSize(16)
                  .lineHeight(24)
                  .padding({ top: 12, bottom: 12 })
                  .fontColor($r('app.color.text_primary'))
                  .borderRadius(8)
                  .onChange((value) => {
                    if (this.fieldDataList.length > 0) {
                      this.updateFieldValue(0, value);
                    }
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

            // 其他字段
            ForEach(this.fieldDataList.slice(1), (fieldData: TemplateFieldData, index: number) => {
              Column() {
                Row() {
                  Text(fieldData.displayName)
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))

                  // 密码字段显示生成按钮
                  if (fieldData.key === KdbxUtils.FIELD_PASSWORD) {
                    Blank()
                    Button($r('app.string.generate_button_text'), { buttonStyle: ButtonStyleMode.TEXTUAL })
                      .fontSize(14)
                      .fontColor($r('app.color.text_primary'))
                      .backgroundColor($r("app.color.card_bg"))
                      .padding({ left: 12, right: 12 })
                      .height(32)
                      .borderRadius(16)
                      .onClick(() => {
                        this.openPasswordGenerator();
                      })
                  }

                  // 受保护字段标记
                  if (fieldData.isProtected && fieldData.key !== KdbxUtils.FIELD_PASSWORD) {
                    Blank()
                    Text($r('app.string.is_protect_field'))
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                  }
                }
                .width('100%')
                .margin({ bottom: 8 })

                // 密码字段使用TextInput
                if (fieldData.key === KdbxUtils.FIELD_PASSWORD) {
                  Row() {
                    TextInput({ text: fieldData.value, placeholder: fieldData.placeholder })
                      .width('100%')
                      .height(48)
                      .fontSize(16)
                      .fontColor($r('app.color.text_primary'))
                      .borderRadius(8)
                      .type(fieldData.isVisible ? InputType.Normal : InputType.Password)
                      .onChange((value) => {
                        this.updateFieldValue(index + 1, value);
                      })
                  }
                  .width('100%')
                  .height(48)
                } else if (fieldData.key === KdbxUtils.FIELD_NOTES) {
                  // 备注字段使用多行TextArea
                  TextArea({ text: fieldData.value, placeholder: fieldData.placeholder })
                    .width('100%')
                    .height(96)
                    .fontSize(16)
                    .lineHeight(24)
                    .padding({ top: 12, bottom: 12 })
                    .fontColor($r('app.color.text_primary'))
                    .borderRadius(8)
                    .onChange((value) => {
                      this.updateFieldValue(index + 1, value);
                    })
                } else if (fieldData.isProtected) {
                  // 受保护字段（TextInput自带显示/隐藏按钮）
                  TextInput({ text: fieldData.value, placeholder: fieldData.placeholder })
                    .width('100%')
                    .height(48)
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                    .borderRadius(8)
                    .type(InputType.Password)
                    .onChange((value) => {
                      this.updateFieldValue(index + 1, value);
                    })
                } else {
                  // 普通字段
                  TextArea({ text: fieldData.value, placeholder: fieldData.placeholder })
                    .width('100%')
                    .fontSize(16)
                    .lineHeight(24)
                    .padding({ top: 12, bottom: 12 })
                    .fontColor($r('app.color.text_primary'))
                    .borderRadius(8)
                    .onChange((value) => {
                      this.updateFieldValue(index + 1, value);
                    })
                }
              }
              .width('100%')
              .margin({ top: 16 })
            })

            // 标签字段
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
                  this.isModified = true;
                })
            }
            .width('100%')
            .margin({ top: 16, bottom: 24 })
          }
          .width('100%')
          .padding({ left: 16, right: 16 })
          .justifyContent(FlexAlign.Start)
        }
        .width('100%')
        .layoutWeight(1)
        .align(Alignment.Top)
        .backgroundColor($r("app.color.bg_primary"))
      }
      .width('100%')
      .height('100%')
    }
    .height('100%')
    .width('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
