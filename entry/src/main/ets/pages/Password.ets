import { PromptAction, Router } from '@kit.ArkUI';
import { Kdbx, KdbxCredentials, KdbxError, ProtectedValue } from 'kdbxweb';
import { AuthType, FileParam } from '../services/TypeDefined';
import picker from '@ohos.file.picker';
import common from '@ohos.app.ability.common';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { StorageType } from '../services/kdbx/interfaces';
import { FileService } from '../services/FileService';

@Entry
@Component
struct Password {
  @State password: string = '';
  @State isLoading: boolean = false;
  @State fileName: string = '';
  @State authType: AuthType = AuthType.PASSWORD;
  @State keyFilePath: string = '';
  @State keyFileName: string = '';
  @State showPassword: boolean = false;
  @State hasKeyFileContent: boolean = false; // 添加状态变量跟踪密钥文件是否已加载
  @State buttonEnabled: boolean = false; // 添加状态变量控制按钮状态

  private filePath: string = '';
  private keyFileContent: ArrayBuffer | null = null;
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;

  // 更新按钮状态
  private updateButtonState(): void {
    console.log('updateButtonState-----------》', this.isLoading, this.password.length, this.hasKeyFileContent, this.authType)
    if (this.isLoading || this.password.length === 0) {
      this.buttonEnabled = false;
      return;
    }
    if (this.authType === AuthType.PASSWORD_KEYFILE && !this.hasKeyFileContent) {
      this.buttonEnabled = false;
      return;
    }
    this.buttonEnabled = true;
  }

  // 获取认证类型的索引，用于Select组件
  private getAuthTypeIndex(): number {
    switch (this.authType) {
      case AuthType.PASSWORD:
        return 0;
      case AuthType.PASSWORD_KEYFILE:
        return 1;
      default:
        return 0;
    }
  }

  // 获取认证类型的文本描述，用于Select组件
  private getAuthTypeText(): string {
    switch (this.authType) {
      case AuthType.PASSWORD:
        return '仅密码';
      case AuthType.PASSWORD_KEYFILE:
        return '密码 + 密钥文件';
      default:
        return '仅密码';
    }
  }

  aboutToAppear() {
    let fileParam: FileParam = FileService.getInstance().getFileParam();
    // 获取从LocalFile页面传递的参数
    this.filePath = fileParam.filePath ?? '';
    this.fileName = fileParam.fileName ?? '未知文件';

    if (!this.filePath || !fileParam.fileContent) {
      this.promptAction.showToast({
        message: '无效的数据文件',
        duration: 2000
      });
      this.router.back();
    }
    
    this.updateButtonState(); // 初始化按钮状态
  }

  /**
   * 加载并解密数据库
   */
  private async loadDatabase(): Promise<Kdbx | null> {
    try {
      if (!FileService.getInstance().getFileContent()) {
        throw new Error('文件内容为空');
      }

      // 创建凭证
      let credentials: KdbxCredentials;
      if (this.authType === AuthType.PASSWORD_KEYFILE && this.keyFileContent) {
        // 使用密码和密钥文件
        credentials = new KdbxCredentials(
          ProtectedValue.fromString(this.password),
          this.keyFileContent
        );
      } else {
        // 仅使用密码
        credentials = new KdbxCredentials(ProtectedValue.fromString(this.password));
      }
      // 加载数据库
      const database = await Kdbx.load(FileService.getInstance().getFileContent(), credentials);
      console.info('数据库加载成功');
      return database;
    } catch (error) {
      console.error(`加载数据库失败: ${error}`);
      let errorMessage = '加载数据库失败';

      if (error instanceof KdbxError) {
        if (error.code === 'InvalidKey') {
          errorMessage = this.authType === AuthType.PASSWORD_KEYFILE ?
            '密码或密钥文件错误，请重试' : '密码错误，请重试';
        } else {
          errorMessage = `数据库错误: ${error.message}`;
        }
      }

      this.promptAction.showToast({
        message: errorMessage,
        duration: 2000
      });
      return null;
    }
  }

  /**
   * 选择密钥文件
   */
  private async selectKeyFile() {
    try {
      const documentPicker = new picker.DocumentViewPicker(this.context);
      const result = await documentPicker.select({
        maxSelectNumber: 1,
        fileSuffixFilters: ['.key'] // 只显示key文件
      });
      if (result && result.length > 0) {
        const fileUri = result[0];
        // 获取文件名
        const fileNameMatch = fileUri.match(/[^/]+$/);
        this.keyFileName = fileNameMatch ? fileNameMatch[0] : '未知文件';
        this.keyFilePath = fileUri;

        // 读取文件内容
        try {
          const fileManager = new KdbxFileManager(StorageType.LOCAL);
          this.keyFileContent = await fileManager.loadKdbxFile(fileUri);
          this.hasKeyFileContent = true; // 更新状态变量
          this.updateButtonState(); // 更新按钮状态
          console.info('密钥文件读取成功');
        } catch (error) {
          console.error(`读取密钥文件失败: ${error}`);
          this.promptAction.showToast({
            message: '读取密钥文件失败',
            duration: 2000
          });
          this.keyFileContent = null;
          this.hasKeyFileContent = false; // 更新状态变量
          this.keyFilePath = '';
          this.keyFileName = '';
          this.updateButtonState(); // 更新按钮状态
        }
      }
    } catch (error) {
      console.error(`选择密钥文件失败: ${error}`);
      this.promptAction.showToast({
        message: '选择密钥文件失败',
        duration: 2000
      });
    }
  }

  /**
   * 验证密码并打开数据库
   */
  // 密钥文件选择器组件
  @Builder
  KeyFileSelector() {
    Column() {
      Text('密钥文件')
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 16 })
        .alignSelf(ItemAlign.Start)

      Button(this.keyFileName ? '重新选择密钥文件' : '选择密钥文件')
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.button_background'))
        .onClick(() => {
          this.selectKeyFile();
        })

      if (this.keyFileName) {
        Text(this.keyFileName)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ top: 8 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
    }
    .width('90%')
    .padding({ left: 16, right: 16, bottom: 24 })
  }

  async verifyAndOpenDatabase() {
    // 验证输入
    if (!this.password) {
      this.promptAction.showToast({
        message: '请输入密码',
        duration: 2000
      });
      return;
    }

    if (this.authType === AuthType.PASSWORD_KEYFILE && !this.keyFileContent) {
      this.promptAction.showToast({
        message: '请选择密钥文件',
        duration: 2000
      });
      return;
    }

    this.isLoading = true;
    this.updateButtonState(); // 更新按钮状态
    try {
      // 加载并验证数据库
      const database = await this.loadDatabase();
      if (!database) {
        return;
      }

      FileService.getInstance().setDbFileParam({
        filePath: this.filePath,
        password: this.password,
        fileName: this.fileName,
        database: database,
        keyFilePath: this.keyFilePath, // 添加密钥文件路径，以便后续保存时使用
        authType: this.authType // 添加认证类型
      })
      // 验证成功，跳转到数据库展示页面
      this.router.pushUrl({
        url: 'pages/DatabaseShow'
      });
    } catch (error) {
      this.promptAction.showToast({
        message: `数据库加载失败: ${error}`,
        duration: 2000
      });
    } finally {
      this.isLoading = false;
      this.updateButtonState(); // 更新按钮状态
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

        Text('解锁数据库')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r('app.color.card_background'))

      // 主要内容区域
      Column() {
        // 文件名显示
        Text(this.fileName)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .margin({ top: 24, bottom: 32 })
          .textAlign(TextAlign.Center)
          .width('80%')
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })

        // 认证方式选择
        Column() {
          Text('认证方式')
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: 16 })
            .alignSelf(ItemAlign.Start)

          Select([
            { value: '仅密码' },
            { value: '密码 + 密钥文件' }
          ])
            .selected(this.getAuthTypeIndex())
            .value(this.getAuthTypeText())
            .font({ size: 16 })
            .fontColor($r('app.color.text_primary'))
            .selectedOptionFont({ size: 16 })
            .optionFont({ size: 16 })
            .width('100%')
            .onSelect((index: number, value: string) => {
              if (index === 0) {
                this.authType = AuthType.PASSWORD;
                this.keyFileContent = null;
                this.hasKeyFileContent = false; // 更新状态变量
                this.keyFilePath = '';
                this.keyFileName = '';
              } else if (index === 1) {
                this.authType = AuthType.PASSWORD_KEYFILE;
              }
              this.updateButtonState(); // 更新按钮状态
            })
        }
        .width('90%')
        .padding({ left: 16, right: 16, bottom: 24 })

        // 密码输入框
        Row() {
          TextInput({ placeholder: '请输入密码' })
            .type(this.showPassword ? InputType.Normal : InputType.Password)
            .placeholderColor($r('app.color.text_secondary'))
            .placeholderFont({ size: 16 })
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .backgroundColor(Color.Transparent)
            .width('100%')
            .height(48)
            .onChange((value) => {
              this.password = value;
              this.updateButtonState(); // 更新按钮状态
            })
        }
        .width('90%')
        .padding({ left: 16, right: 16 })
        .border({
          width: { bottom: 1 },
          color: $r('app.color.divider')
        })
        .margin({ bottom: 16 })

        // 密钥文件选择（仅在选择密码+密钥文件时显示）
        if (this.authType === AuthType.PASSWORD_KEYFILE) {
          this.KeyFileSelector()
        }

        // 确认按钮
        Button(this.isLoading ? '验证中...' : '确认')
          .width('90%')
          .height(48)
          .margin({ top: 32 })
          .enabled(this.buttonEnabled)
          .backgroundColor(this.buttonEnabled ? $r('app.color.button_background') : $r('app.color.button_disabled_background'))
          .onClick(() => {
            this.verifyAndOpenDatabase();
          })

        if (this.isLoading) {
          LoadingProgress()
            .width(24)
            .height(24)
            .margin({ top: 16 })
            .color($r('app.color.text_primary'))
        }
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r('app.color.background_primary'))
      .padding({ top: 16 })
    }
    .width('100%')
    .height('100%')
  }
}
