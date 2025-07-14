import { KdbxEntry, KdbxGroup, Kdbx, ProtectedValue, KdbxEntryField } from 'kdbxweb';
import { Router } from '@kit.ArkUI';
import ThemeManager from '../common/utils/ThemeManager';
import { FileService } from '../services/FileService';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import KdbxUtils from '../common/utils/KdbxUtils';
import { EntryParam } from '../services/TypeDefined';
import { EntryEditFieldDialog } from '../components/EntryEditFieldDialog';
import { CustomField } from '../services/TypeDefined';

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
  @State pageTitle: string = '添加条目';
  @State passwordStrength: number = 0; // 密码强度: 0-弱, 1-中, 2-强
  @State passwordLength: number = 16; // 密码生成长度
  @State useUppercase: boolean = true; // 使用大写字母
  @State useLowercase: boolean = true; // 使用小写字母
  @State useNumbers: boolean = true; // 使用数字
  @State useSpecial: boolean = true; // 使用特殊字符
  @State useBrackets: boolean = true; // 使用括号
  @State showPasswordGenerator: boolean = false; // 显示密码生成器

  @State customFields: CustomField[] = []; // 自定义字段列表
  @State showFieldDialog: boolean = false; // 显示自定义字段对话框
  @State isEditingField: boolean = false; // 是否是编辑字段模式
  @State editingFieldIndex: number = -1; // 正在编辑的字段索引
  @State currentFieldKey: string = ''; // 当前字段的键
  @State currentFieldValue: string = ''; // 当前字段的值
  @State currentFieldProtected: boolean = false; // 当前字段是否受保护
  @State customFieldsVisibility: boolean[] = []; // 自定义字段值的可见性状态
  @State isModified: boolean = false; // 是否有字段被修改
  
  // 自定义字段对话框控制器
  fieldDialogController: CustomDialogController = new CustomDialogController({
    builder: EntryEditFieldDialog({
      isEditing: $isEditingField,
      fieldKey: $currentFieldKey,
      fieldValue: $currentFieldValue,
      isProtected: $currentFieldProtected,
      onConfirm: (customField: CustomField) => {
        console.log("接收到字段 -------", customField);
        this.confirmCustomField(customField);
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true
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
        message: '无效的数据库信息',
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
          message: '无效的分组信息',
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
      this.pageTitle = '编辑条目';
      
      // 使用KdbxUtils.getEntry方法获取现有条目
      this.entry = KdbxUtils.getEntry(this.database, routeParams.groupId, routeParams.entryId);
      
      if (!this.entry) {
        this.promptAction.showToast({
          message: '无效的条目信息',
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
      
      // 加载自定义字段
      this.loadCustomFields();
    }

    // 初始化修改状态为false
    this.isModified = false;

    // 监听主题变化
    ThemeManager.getInstance().addThemeChangeListener(() => {
      this.onThemeChanged();
    });
  }

  aboutToDisappear() {
    // 移除主题变化监听
    ThemeManager.getInstance().removeThemeChangeListenerAll();
  }

  onThemeChanged() {
    // 强制组件刷新以应用新主题
    this.forceUpdate();
  }

  /**
   * 强制组件刷新
   */
  private forceUpdate() {
    // 触发UI更新的临时变量
    let temp = this.showPassword;
    this.showPassword = !temp;
    this.showPassword = temp;
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
        message: '无效的数据库或分组信息',
        duration: 2000
      });
      return;
    }

    if (!this.title.trim()) {
      this.promptAction.showToast({
        message: '标题不能为空',
        duration: 2000
      });
      return;
    }
    this.isLoading = true;

    try {
      if (this.isEditMode && this.entry) {
        // 编辑现有条目
        this.entry.fields.set(KdbxUtils.FIELD_TITLE, this.title.trim());
        this.entry.fields.set(KdbxUtils.FIELD_USERNAME, this.username.trim());
        this.entry.fields.set(KdbxUtils.FIELD_PASSWORD, ProtectedValue.fromString(this.password));
        this.entry.fields.set(KdbxUtils.FIELD_URL, this.url.trim());
        this.entry.fields.set(KdbxUtils.FIELD_NOTES, this.notes.trim());
        
        // 清除旧的自定义字段（除了标准字段外的所有字段）
        this.entry.fields.forEach((value, key) => {
          if (![KdbxUtils.FIELD_TITLE, KdbxUtils.FIELD_USERNAME, KdbxUtils.FIELD_PASSWORD, 
                KdbxUtils.FIELD_URL, KdbxUtils.FIELD_NOTES].includes(key)) {
            this.entry?.fields.delete(key);
          }
        });
        
        // 保存自定义字段
        this.customFields.forEach(field => {
          if (field.isProtected) {
            this.entry?.fields.set(field.key, ProtectedValue.fromString(field.value));
          } else {
            this.entry?.fields.set(field.key, field.value);
          }
        });
        
        this.entry.times.update();
      } else {
        // 创建新条目
        this.entry = this.database.createEntry(this.parentGroup);
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
      }

      // 保存数据库
      this.saveDatabase();
    } catch (error) {
      console.error(`保存条目失败: ${error}`);
      this.promptAction.showToast({
        message: `保存条目失败: ${error}`,
        duration: 2000
      });
      this.isLoading = false;
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
          this.promptAction.showToast({ message: `保存成功` });
          this.isLoading = false;
          this.router.back();
        }).catch((error: Error) => {
          console.error(`保存数据库失败: ${error}`);
          this.promptAction.showToast({ message: `保存数据库失败: ${error.message}` });
          this.isLoading = false;
        });
      }).catch((error: Error) => {
        console.error(`保存数据库失败: ${error}`);
        this.promptAction.showToast({ message: `保存数据库失败: ${error.message}` });
        this.isLoading = false;
      });
    }
  }

  /**
   * 生成随机密码
   */
  private generatePassword() {
    let charset = '';
    if (this.useLowercase) charset += 'abcdefghijklmnopqrstuvwxyz';
    if (this.useUppercase) charset += 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
    if (this.useNumbers) charset += '0123456789';
    if (this.useSpecial) charset += '!@#$%^&*_+~`|;?><,./-=';
    if (this.useBrackets) charset += '(){}[]';
    
    // 确保至少有一种字符类型被选中
    if (charset.length === 0) {
      this.useLowercase = true;
      charset = 'abcdefghijklmnopqrstuvwxyz';
    }
    
    let password = '';
    for (let i = 0; i < this.passwordLength; i++) {
      const randomIndex = Math.floor(Math.random() * charset.length);
      password += charset.charAt(randomIndex);
    }
    this.password = password;
    this.evaluatePasswordStrength();
  }
  
  /**
   * 评估密码强度
   */
  private evaluatePasswordStrength() {
    if (!this.password) {
      this.passwordStrength = 0;
      return;
    }
    
    let score = 0;
    
    // 长度评分
    if (this.password.length >= 12) {
      score += 2;
    } else if (this.password.length >= 8) {
      score += 1;
    }
    
    // 复杂度评分
    const hasLower = /[a-z]/.test(this.password);
    const hasUpper = /[A-Z]/.test(this.password);
    const hasNumber = /[0-9]/.test(this.password);
    const hasSpecial = /[^A-Za-z0-9]/.test(this.password);
    
    const complexity = (hasLower ? 1 : 0) + 
                       (hasUpper ? 1 : 0) + 
                       (hasNumber ? 1 : 0) + 
                       (hasSpecial ? 1 : 0);
    
    score += complexity;
    
    // 设置密码强度
    if (score >= 5) {
      this.passwordStrength = 2; // 强
    } else if (score >= 3) {
      this.passwordStrength = 1; // 中
    } else {
      this.passwordStrength = 0; // 弱
    }
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
            message: '字段名称已存在',
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
          message: '字段名称已存在',
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
        title: '确认删除',
        message: `确定要删除字段 "${fieldKey}" 吗？`,
        buttons: [
          {
            text: '取消',
            color: $r('app.color.text_secondary')
          },
          {
            text: '删除',
            color: $r('app.color.accent'),
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
   * 更新自定义字段值
   * @param index 字段索引
   * @param newValue 新值
   */
  private updateCustomFieldValue(index: number, newValue: string) {
    if (index >= 0 && index < this.customFields.length) {
      this.customFields[index].value = newValue;
      // 标记为已修改
      this.isModified = true;
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

  build() {
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
      .backgroundColor($r('app.color.card_background'))

      // 表单内容
      Scroll() {
        Column() {
          // 标题
          Column() {
            Text('标题')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ bottom: 8 })
              .alignSelf(ItemAlign.Start)

            TextInput({ text: this.title, placeholder: '请输入标题' })
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))
              // .backgroundColor($r('app.color.input_background'))
              .borderRadius(8)
              .onChange((value) => {
                this.title = value;
                this.isModified = true;
              })
          }
          .width('100%')
          .margin({ top: 16 })

          // 用户名
          Column() {
            Text('用户名')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ bottom: 8 })
              .alignSelf(ItemAlign.Start)

            TextInput({ text: this.username, placeholder: '请输入用户名' })
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))
              .borderRadius(8)
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
              Text('密码')
                .fontSize(14)
                .fontColor($r('app.color.text_secondary'))

              Blank()

              Button('生成')
                .fontSize(14)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor('#f0f0f0')
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .borderRadius(4)
                .onClick(() => {
                  this.showPasswordGenerator = !this.showPasswordGenerator;
                })
            }
            .width('100%')
            .margin({ bottom: 8 })

            Row() {
              TextInput({ text: this.password, placeholder: '请输入密码' })
                .width('100%')
                .height(48)
                .fontSize(16)
                .fontColor($r('app.color.text_primary'))
                .borderRadius(8)
                .type(this.showPassword ? InputType.Normal : InputType.Password)
                .onChange((value) => {
                  this.password = value;
                  this.isModified = true;
                  this.evaluatePasswordStrength();
                })
            }
            .width('100%')
            .height(48)
            
            // 密码强度指示器
            if (this.password.length > 0) {
              Row() {
                Text('密码强度：')
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .margin({ right: 8 })
                
                Row() {
                  Row()
                    .width(24)
                    .height(6)
                    .backgroundColor(this.passwordStrength >= 0 ? '#FF0000' : '#EEEEEE')
                    .borderRadius(3)
                  
                  Row()
                    .width(24)
                    .height(6)
                    .backgroundColor(this.passwordStrength >= 1 ? '#FFCC00' : '#EEEEEE')
                    .borderRadius(3)
                    .margin({ left: 2, right: 2 })
                  
                  Row()
                    .width(24)
                    .height(6)
                    .backgroundColor(this.passwordStrength >= 2 ? '#00CC00' : '#EEEEEE')
                    .borderRadius(3)
                }
                
                Text(this.passwordStrength === 0 ? '弱' : this.passwordStrength === 1 ? '中' : '强')
                  .fontSize(12)
                  .fontColor(this.passwordStrength === 0 ? '#FF0000' : this.passwordStrength === 1 ? '#FFCC00' : '#00CC00')
                  .margin({ left: 8 })
              }
              .width('100%')
              .margin({ top: 8 })
            }
            
            // 密码生成器面板
            if (this.showPasswordGenerator) {
              Column() {
                Row() {
                  Text('密码长度：' + this.passwordLength)
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                  Slider({
                    value: this.passwordLength,
                    min: 1,
                    max: 32,
                    step: 1,
                    style: SliderStyle.OutSet
                  })
                    .width('60%')
                    .onChange((value: number) => {
                      this.passwordLength = value;
                    })
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
                .margin({ top: 8, bottom: 8 })
                
                Row() {
                  Checkbox({ name: 'uppercase', group: 'passwordOptions' })
                    .select(this.useUppercase)
                    .onChange((value) => {
                      this.useUppercase = value;
                    })
                  Text('大写字母 (A-Z)')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.useUppercase = !this.useUppercase;
                    })
                }
                .width('100%')
                .margin({ top: 4, bottom: 4 })
                
                Row() {
                  Checkbox({ name: 'lowercase', group: 'passwordOptions' })
                    .select(this.useLowercase)
                    .onChange((value) => {
                      this.useLowercase = value;
                    })
                  Text('小写字母 (a-z)')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.useLowercase = !this.useLowercase;
                    })
                }
                .width('100%')
                .margin({ top: 4, bottom: 4 })
                
                Row() {
                  Checkbox({ name: 'numbers', group: 'passwordOptions' })
                    .select(this.useNumbers)
                    .onChange((value) => {
                      this.useNumbers = value;
                    })
                  Text('数字 (0-9)')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.useNumbers = !this.useNumbers;
                    })
                }
                .width('100%')
                .margin({ top: 4, bottom: 4 })
                
                Row() {
                  Checkbox({ name: 'special', group: 'passwordOptions'})
                    .select(this.useSpecial)
                    .onChange((value) => {
                      this.useSpecial = value;
                    })
                  Text('特殊字符 (!@#$%^&*_+~`|;?><,./-=)')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.useSpecial = !this.useSpecial;
                    })
                }
                .width('100%')
                .margin({ top: 4, bottom: 4 })
                
                Row() {
                  Checkbox({ name: 'brackets', group: 'passwordOptions'})
                    .select(this.useBrackets)
                    .onChange((value) => {
                      this.useBrackets = value;
                    })
                  Text('括号 ((){}[])')
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.useBrackets = !this.useBrackets;
                    })
                }
                .width('100%')
                .margin({ top: 4, bottom: 4 })
                
                Row() {
                  Button('关闭')
                    .width('48%')
                    .margin({ top: 8, right: 8 })
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .backgroundColor('#f0f0f0')
                    .borderRadius(4)
                    .onClick(() => {
                      this.showPasswordGenerator = false;
                    })
                    
                  Button('生成密码')
                    .width('48%')
                    .margin({ top: 8 })
                    .fontSize(14)
                    .fontColor(Color.White)
                    .backgroundColor($r('app.color.accent'))
                    .borderRadius(4)
                    .onClick(() => {
                      this.generatePassword();
                    })
                }
                .width('100%')
                .justifyContent(FlexAlign.SpaceBetween)
              }
              .width('100%')
              .padding(12)
              .backgroundColor('#f5f5f5')
              .borderRadius(8)
              .margin({ top: 8 })
            }
          }
          .width('100%')
          .margin({ top: 16 })

          // URL
          Column() {
            Text('URL')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ bottom: 8 })
              .alignSelf(ItemAlign.Start)

            TextInput({ text: this.url, placeholder: '请输入URL' })
              .width('100%')
              .height(48)
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))
              .borderRadius(8)
              .onChange((value) => {
                this.url = value;
                this.isModified = true;
              })
          }
          .width('100%')
          .margin({ top: 16 })

          // 备注
          Column() {
            Text('备注')
              .fontSize(14)
              .fontColor($r('app.color.text_secondary'))
              .margin({ bottom: 8 })
              .alignSelf(ItemAlign.Start)

            TextArea({ text: this.notes, placeholder: '请输入备注' })
              .width('100%')
              .height(120)
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
              Text('自定义字段')
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
              .backgroundColor('#f0f0f0')
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
                    .backgroundColor('#f0f0f0')
                    .borderRadius(16)
                    .margin({ right: 8 })
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
                    .backgroundColor('#f0f0f0')
                    .borderRadius(16)
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
                .padding(12)
                .backgroundColor('#f5f5f5')
                .borderRadius(8)
                .margin({ bottom: 8 })
                .onClick(() => {
                  this.openEditFieldDialog(index);
                })
              })
            } else {
              Text('暂无自定义字段')
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
      .backgroundColor($r('app.color.background_primary'))
    }
    .width('100%')
    .height('100%')
  }
}
