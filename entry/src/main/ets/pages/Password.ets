import {PromptAction, router, Router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import worker, { ErrorEvent, MessageEvents } from '@ohos.worker';


import { AuthType, AuthTypeInfo, CredentialsParam, FileParam } from '../services/TypeDefined';
import { RecentFilesService } from '../services/RecentFilesService';
import picker from '@ohos.file.picker';
import common from '@ohos.app.ability.common';
import { fileShare } from '@kit.CoreFileKit';
import { StorageType } from '../services/kdbx/interfaces';
import { FileService } from '../services/FileService';
import FileUtils from '../common/utils/FIleUtils';
import { LoadDatabase, LoadMessage, MessageType, SuccessMessage, WorkerMessage } from '../workers/DatabaseWorkerParam';
import { StorageConfig } from '../services/kdbx/interfaces/StorageConfig';
import KdbxUtils from '../common/utils/KdbxUtils';
import { Kdbx } from 'kdbxweb';
import { ContextLoadingDialog } from '../components/ContextLoadingDialog';
import ResourceManager from '../common/utils/ResourceManager';

const DOMAIN = 0x0000;
const TAG = 'Password';

@Entry
@Component
struct Password {
  @State password: string = '';
  @State isLoading: boolean = false;
  @State fileName: string = '';
  @State authType: AuthTypeInfo = AuthType.PASSWORD;
  @State keyFilePath: string = '';
  @State keyFileName: string = '';
  @State showPassword: boolean = false;
  @State buttonEnabled: boolean = false; // 添加状态变量控制按钮状态
  @State loadingMessage:string =  '';

  private filePath: string = '';
  private storageType: StorageType | null = null;
  private storageConfig: StorageConfig | null = null;
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private recentFileService = RecentFilesService.getInstance();
  private databaseWorker: worker.ThreadWorker | null = null;

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
    const params = this.router.getParams() as Record<string, string>;
    // 通过最近文件打开
    if (params && params.filePath) {
      this.openRecentFile(params.filePath);
    }
    // 数据库选择器打开
    else {
      this.openFileParam();
    }
    // 初始化按钮状态
    this.updateButtonState();
  }

  aboutToDisappear() {
    this.stopWorker();
  }

  // 更新按钮状态
  private updateButtonState(): void {
    hilog.info(DOMAIN, TAG, '%{public}s', `updateButtonState: isLoading=${this.isLoading}, passwordLength=${this.password.length}, keyFilePath=${this.keyFilePath}, authType=${this.authType.type}`)
    if (this.isLoading || this.password.length === 0) {
      this.buttonEnabled = false;
      return;
    }
    if ((this.authType.type === AuthType.PASSWORD_KEYFILE.type ||
      this.authType.type === AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) &&
      !this.keyFilePath) {
      this.buttonEnabled = false;
      return;
    }
    this.buttonEnabled = true;
  }

  // 获取认证类型的索引，用于Select组件
  private getAuthTypeIndex(): number {
    const allTypes = AuthType.getAllTypes();
    const index = allTypes.findIndex(item => item.type === this.authType.type);
    return index >= 0 ? index : 0;
  }

  // 获取认证类型的文本描述，用于Select组件
  private getAuthTypeText(): ResourceStr {
    return this.authType.description;
  }

  /**
   * 数据库选择器打开
   */
  private openFileParam() {
    let fileParam: FileParam = FileService.getInstance().getFileParam();
    // 获取从LocalFile页面传递的参数
    this.filePath = fileParam.filePath ?? '';
    this.fileName = fileParam.fileName ?? '';
    this.storageType = fileParam.storageType;
    this.storageConfig = fileParam.storageConfig;
  }

  /**
   * 通过最近文件打开
   */
  private openRecentFile(filePath: string) {
    if (!filePath) {
      this.promptAction.showToast({ message: $r('app.string.invalid_data_file'), duration: 2000 });
      this.router.back();
    }
    // 获取最近打开记录
    this.recentFileService.getRecentFile(filePath).then(recentFile => {
      if (recentFile) {
        this.fileName = recentFile.fileName;
        this.filePath = recentFile.filePath;
        this.storageType = recentFile.storageType;
        this.storageConfig = recentFile.storageConfig;
        // 设置认证类型
        if (recentFile.authType) {
          this.authType = recentFile.authType;
        }
        // 获取密钥文件路径
        if (recentFile.keyFilePath) {
          this.keyFilePath = recentFile.keyFilePath;
          this.keyFileName = FileUtils.getFileName(this.keyFilePath);
        }
      }
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to open recent file: %{public}s, stack: %{public}s', error.message, error.stack);
      this.promptAction.showToast({
        message: $r('app.string.open_failed', error.message),
        duration: 2000
      });
      this.router.back();
    });
  }

  /**
   * 终止 Worker
   */
  private stopWorker() {
    // 终止 Worker
    if (this.databaseWorker) {
      this.databaseWorker.terminate();
      this.databaseWorker = null;
      hilog.info(DOMAIN, TAG, 'Database worker terminated');
    }
  }

  /**
   * 选择密钥文件
   */
  private async selectKeyFile() {
    const documentPicker = new picker.DocumentViewPicker(this.context);
    const result = await documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['.key'] // 只显示key文件
    });
    if (result && result.length > 0) {
      const fileUri = result[0];
      FileUtils.persistPermission(fileUri, fileShare.OperationMode.READ_MODE).then(async () => {
        this.keyFilePath = fileUri;
        this.keyFileName = FileUtils.getFileName(fileUri);
        this.updateButtonState();
      }).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Failed to open key file: %{public}s', error.message);
        this.promptAction.showToast({
          message: $r('app.string.open_failed') + error.message,
          duration: 2000
        });
      });
    }
  }

  /**
   * 更改数据库
   */
  changeDatabase() {
    // 返回到文件选择页面
    this.router.pushUrl({ url: 'pages/open/OpenDatabase' }, router.RouterMode.Single)
  }

  /**
   * 打开进度弹框
   */
  private openLoadingDialog(){
    this.isLoading = true;
    this.updateButtonState(); // 更新按钮状态
    this.loadingDialogController.open();
  }

  /**
   * 管理进度弹框
   */
  private closeLoadingDialog(){
    this.isLoading = false;
    this.updateButtonState(); // 更新按钮状态
    this.loadingDialogController.close();
  }

  /**
   * 验证密码并打开数据库
   */
  private verifyAndOpenDatabase() {
    // 验证输入
    if (!this.password) {
      this.promptAction.showToast({
        message: $r('app.string.password_placeholder'),
        duration: 2000
      });
      return;
    }

    if ((this.authType.type === AuthType.PASSWORD_KEYFILE.type ||
      this.authType.type === AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) && !this.keyFilePath) {
      this.promptAction.showToast({
        message: $r('app.string.select_key_file'),
        duration: 2000
      });
      return;
    }

    if (this.storageType === null) {
      this.promptAction.showToast({ message: $r('app.string.storage_type_empty') });
      return;
    }
    this.openLoadingDialog();
    this.stopWorker();
    this.databaseWorker = new worker.ThreadWorker('entry/ets/workers/DatabaseWorker.ets');
    this.databaseWorker.postMessage(JSON.stringify(
      new LoadDatabase(this.filePath, this.fileName, this.password, this.authType, this.keyFilePath, this.storageType, this.storageConfig)
    ));

    // 注册onmessage回调，当宿主线程接收到来自其创建的Worker通过workerPort.postMessage接口发送的消息时被调用，在宿主线程执行
    this.databaseWorker.onmessage = (e: MessageEvents) => {
      let data = e.data as WorkerMessage;
      // // 加载进度消息
      if (data.type == MessageType.LOAD_MESSAGE) {
        const loadMessage = data as LoadMessage;
        hilog.info(DOMAIN, TAG, 'Received loading progress:  %{public}s', loadMessage.message);
        this.loadingMessage =  loadMessage.message;
      }
      // 数据库加载成功
      if (data.type == MessageType.LOAD_SUCCESS) {
        let successMessage = data as SuccessMessage;
        this.init();
        this.putFileToRecentFile();
        this.setFileParam(successMessage.data).then(() => {
          this.loadingMessage = ResourceManager.getInstance().getString($r('app.string.open_success'));
          this.router.pushUrl({ url: 'pages/DatabaseView' });
          setTimeout(() => {
            this.closeLoadingDialog();
          }, 300);
        }).catch((error: Error) => {
          hilog.error(DOMAIN, TAG, 'Database open failed: %{public}s', error.message);
          this.promptAction.showToast({message: error.message, duration: 3000});
          this.closeLoadingDialog();
        });
      }
      // 错误消息
      if (data.type == MessageType.LOAD_ERROR) {
        let errorMessage = data as LoadMessage;
        this.promptAction.showToast({ message: errorMessage.message, duration: 3000 });
        this.closeLoadingDialog();
      }
    }

    // 注册onmessageerror回调，当Worker对象接收到无法序列化的消息时被调用，在宿主线程执行
    this.databaseWorker.onAllErrors = (err: ErrorEvent) => {
      hilog.error(DOMAIN, TAG, 'Open database error: %{public}s', err.message);
      if (err.message.indexOf('NativeCustomSpan') != -1) {
        return;
      }
      this.promptAction.showToast({ message: err.message })
      this.closeLoadingDialog();
    }

    // 注册onexit回调，当Worker销毁时被调用，在宿主线程执行
    this.databaseWorker.onexit = (e: number) => {
      this.closeLoadingDialog();
    }
  }

  /**
   * 设置数据库文件信息
   */
  private setFileParam(kdbxContent: ArrayBuffer): Promise<void> {
    return KdbxUtils.arrayBufferToKdbx(kdbxContent, {
      password: this.password,
      authType: this.authType,
      keyFilePath: this.keyFilePath,
    } as CredentialsParam).then((kdbx: Kdbx) => {
      // 设置数据库文件信息
      FileService.getInstance().setDbFileParam({
        filePath: this.filePath,
        password: this.password,
        fileName: this.fileName,
        database: kdbx,
        keyFilePath: this.keyFilePath, // 添加密钥文件路径，以便后续保存时使用
        authType: this.authType, // 添加认证类型
        storageType: this.storageType ?? StorageType.LOCAL,
        storageConfig: this.storageConfig ?? {}
      })
    });
  }

  /**
   * 初始化
   */
  private init() {
    KdbxUtils.init();
    FileService.getInstance().init();
  }

  /**
   * 文件打开成功，保存到最近访问列表中
   */
  private putFileToRecentFile() {
    let fileParam = FileService.getInstance().getFileParam();
    hilog.info(DOMAIN, TAG, '%{public}s', `Database file opened: ${fileParam?.filePath}`)

    // 添加到最近打开的文件列表，包含认证方式和认证文件信息
    RecentFilesService.getInstance().getRecentFile(this.filePath).then((recentFile) => {
      if (recentFile) {
        RecentFilesService.getInstance().addRecentFile({
          filePath: this.filePath,
          fileName: this.fileName,
          storageType: this.storageType ?? StorageType.LOCAL,
          authType: this.authType,
          keyFilePath: this.keyFilePath,
          storageConfig: this.storageConfig ?? {}
        });
      }
    })
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

        Text($r('app.string.Password_unlock_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r("app.color.card_bg"))

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
          Text($r('app.string.auth_type'))
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .margin({ bottom: 16 })
            .alignSelf(ItemAlign.Start)

          Select(AuthType.getAllTypes().map(type => ({ value: type.description } as SelectOption)))
            .selected(this.getAuthTypeIndex())
            .value(this.getAuthTypeText())
            .font({ size: 16 })
            .fontColor($r('app.color.text_primary'))
            .selectedOptionFont({ size: 16 })
            .optionFont({ size: 16 })
            .width('100%')
            .onSelect((index: number, value: string) => {
              const allTypes = AuthType.getAllTypes();
              if (index >= 0 && index < allTypes.length) {
                this.authType = allTypes[index];
                // 如果选择的认证类型不需要密钥文件，则清除密钥文件相关的状态
                if (this.authType.type !== AuthType.PASSWORD_KEYFILE.type && this.authType.type !== AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) {
                  this.keyFilePath = '';
                  this.keyFileName = '';
                }
              }
              this.updateButtonState(); // 更新按钮状态
            })
        }
        .width('90%')
        .padding({ left: 16, right: 16, bottom: 24 })

        // 密码输入框
        Row() {
          TextInput({ placeholder: $r('app.string.password_placeholder') })
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
            .onSubmit(() => {
              this.verifyAndOpenDatabase();
            })
        }
        .width('90%')
        .padding({ left: 16, right: 16 })
        .border({
          width: { bottom: 1 },
          color: $r('app.color.divider')
        })
        .margin({ bottom: 16 })

        // 密钥文件选择（仅在需要密钥文件的认证方式时显示）
        if (this.authType.type === AuthType.PASSWORD_KEYFILE.type ||
          this.authType.type === AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) {
          this.KeyFileSelector()
        }

        // 底部固定按钮栏
        Row() {
          // 左侧 - 更改数据库按钮
          Button($r('app.string.change_database'))
            .height(48)
            .layoutWeight(1)
            .margin({ left: 16, right: 8 })
            .backgroundColor($r('app.color.card_bg'))  // 浅灰色背景
            .fontColor($r('app.color.text_primary'))        // 深灰色文字
            .onClick(() => {
              this.changeDatabase();
            })

          // 右侧 - 解锁按钮
          Button(this.isLoading ? $r('app.string.loading_message') : $r('app.string.Password_unlock_title'))
            .height(48)
            .layoutWeight(1)
            .margin({ left: 8, right: 16 })
            .enabled(this.buttonEnabled)
            .backgroundColor(this.buttonEnabled ? $r("app.color.button_bg_blue") : $r("app.color.button_bg_disabled"))
            .onClick(() => {
              this.verifyAndOpenDatabase();
            })
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })
        .position({ x: 0, y: '100%' })
        .translate({ y: -74 }) // 调整位置，确保正确显示
      }
      .width('100%')
      .layoutWeight(1)
      .backgroundColor($r("app.color.bg_primary"))
      .padding({ top: 16 })
    }
    .width('100%')
    .height('100%')
  }

  /**
   * 验证密码并打开数据库
   */
  @Builder
  KeyFileSelector() {
    Column() {
      Text($r('app.string.key_file'))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 16 })
        .alignSelf(ItemAlign.Start)

      Button(this.keyFileName ? $r('app.string.reselect_key_file') : $r('app.string.select_key_file_button'))
        .width('100%')
        .height(48)
        .backgroundColor($r("app.color.button_bg_blue"))
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
}
