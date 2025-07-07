import { KdbxEntry, KdbxGroup, Kdbx, ProtectedValue } from 'kdbxweb';
import { Router } from '@kit.ArkUI';
import ThemeManager from '../common/utils/ThemeManager';
import { FileService } from '../services/FileService';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import KdbxUtils from '../common/utils/KdbxUtils';
import { EntryParam } from '../services/TypeDefined';

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
    if (routeParams.entryId) {
      this.isEditMode = true;
      this.pageTitle = '编辑条目';
      // this.entry = this.database.getEntry(routeParams.entryId);
      this.entry = new KdbxEntry();
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
    }

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
        this.entry.times.update();
      } else {
        // 创建新条目
        this.entry = this.database.createEntry(this.parentGroup);
        this.entry.fields.set(KdbxUtils.FIELD_TITLE, this.title.trim());
        this.entry.fields.set(KdbxUtils.FIELD_USERNAME, this.username.trim());
        this.entry.fields.set(KdbxUtils.FIELD_PASSWORD, ProtectedValue.fromString(this.password));
        this.entry.fields.set(KdbxUtils.FIELD_URL, this.url.trim());
        this.entry.fields.set(KdbxUtils.FIELD_NOTES, this.notes.trim());
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
    const charset = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()_+~`|}{[]:;?><,./-=';
    let password = '';
    for (let i = 0; i < 16; i++) {
      const randomIndex = Math.floor(Math.random() * charset.length);
      password += charset.charAt(randomIndex);
    }
    this.password = password;
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

        Button('保存')
          .fontSize(16)
          .fontColor(Color.White)
          .backgroundColor($r('app.color.primary'))
          .margin({ right: 16 })
          .padding({ left: 16, right: 16, top: 8, bottom: 8 })
          .borderRadius(4)
          .enabled(!this.isLoading)
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
              // .backgroundColor($r('app.color.input_background'))
              .borderRadius(8)
              .onChange((value) => {
                this.username = value;
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
                .fontColor(Color.White)
                .backgroundColor($r('app.color.primary'))
                .padding({ left: 12, right: 12, top: 4, bottom: 4 })
                .borderRadius(4)
                .onClick(() => {
                  this.generatePassword();
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
                // .backgroundColor($r('app.color.input_background'))
                .borderRadius(8)
                .type(this.showPassword ? InputType.Normal : InputType.Password)
                .onChange((value) => {
                  this.password = value;
                })
            }
            .width('100%')
            .height(48)
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
              // .backgroundColor($r('app.color.input_background'))
              .borderRadius(8)
              .onChange((value) => {
                this.url = value;
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
              // .backgroundColor($r('app.color.input_background'))
              .borderRadius(8)
              .onChange((value) => {
                this.notes = value;
              })
          }
          .width('100%')
          .margin({ top: 16, bottom: 24 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background_primary'))
    }
    .width('100%')
    .height('100%')
  }
}
