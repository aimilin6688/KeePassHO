import { PromptAction, router, Router } from '@kit.ArkUI';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import worker, { ErrorEvent, MessageEvents } from '@ohos.worker';
import { AuthType, AuthTypeInfo, FileParam } from '../services/TypeDefined';
import { RecentFilesService } from '../services/RecentFilesService';
import picker from '@ohos.file.picker';
import common from '@ohos.app.ability.common';
import { fileShare } from '@kit.CoreFileKit';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { StorageType } from '../services/kdbx/interfaces';
import { FileService } from '../services/FileService';
import FileUtils from '../common/utils/FIleUtils';
import { LoadDatabaseResult, WorkerMessage} from '../workers/DatabaseWorker'

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
  @State hasKeyFileContent: boolean = false; // 添加状态变量跟踪密钥文件是否已加载
  @State buttonEnabled: boolean = false; // 添加状态变量控制按钮状态
  private filePath: string = '';
  private keyFileContent: ArrayBuffer | null = null;
  private storageType: StorageType | null = null;
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  private recentFileService = RecentFilesService.getInstance();

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
    // 终止 Worker
    if (this.databaseWorker) {
      this.databaseWorker.terminate();
      this.databaseWorker = null;
      console.log('数据库 Worker 已终止');
    }
  }

  // 更新按钮状态
  private updateButtonState(): void {
    console.log('updateButtonState-----------》', this.isLoading, this.password.length, this.hasKeyFileContent, this.authType.type)
    if (this.isLoading || this.password.length === 0) {
      this.buttonEnabled = false;
      return;
    }
    if ((this.authType.type === AuthType.PASSWORD_KEYFILE.type ||
      this.authType.type === AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) &&
      !this.hasKeyFileContent) {
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
  private getAuthTypeText(): string {
    return this.authType.description;
  }

  /**
   * 数据库选择器打开
   */
  private openFileParam() {
    let fileParam: FileParam = FileService.getInstance().getFileParam();
    // 获取从LocalFile页面传递的参数
    this.filePath = fileParam.filePath ?? '';
    this.fileName = fileParam.fileName ?? '未知文件';
    this.storageType = fileParam.storageType;

    if (!this.filePath || !fileParam.fileContent) {
      this.promptAction.showToast({
        message: '无效的数据文件',
        duration: 2000
      });
      this.router.back();
    }
  }

  /**
   * 通过最近文件打开
   */
  private openRecentFile(filePath: string) {
    if (!filePath) {
      this.promptAction.showToast({ message: '无效的数据文件', duration: 2000 });
      this.router.back();
    }
    // 获取最近打开记录
    this.recentFileService.getRecentFile(filePath).then(recentFile => {
      if (recentFile) {
        this.fileName = recentFile.fileName;
        this.filePath = recentFile.filePath;
        this.storageType = recentFile.storageType;
        // 读取最近打开的文件内容
        this.recentFileService.readRecentFile(recentFile).then(() => {
          this.promptAction.showToast({ message: '数据库加载完成！' });
        }).catch((error: Error) => {
          console.error(`Open recent file error: ${error}`);
          this.promptAction.showToast({ message: `数据库打开失败: ${error.message}`, duration: 2000 });
          this.router.back();
        });
        // 设置认证类型
        if (recentFile.authType) {
          this.authType = recentFile.authType;
        }
        // 获取密钥文件路径
        if (recentFile.keyFilePath) {
          this.keyFilePath = recentFile.keyFilePath;
          FileUtils.activatePermission(this.keyFilePath, fileShare.OperationMode.READ_MODE).then(async () => {
            this.loadKeyFileContent(this.keyFilePath);
          })
        }
      }
    }).catch((error: Error) => {
      console.error(`Open recent file error: ${error}`);
      this.promptAction.showToast({
        message: '数据文件打开失败',
        duration: 2000
      });
      this.router.back();
    });
  }

  // Worker 实例
  private databaseWorker: worker.ThreadWorker | null = null;
  
  /**
   * 加载并解密数据库
   */
  private async loadDatabase(): Promise<Kdbx | null> {
    return new Promise<Kdbx | null>((resolve, reject) => {
      try {
        if (!FileService.getInstance().getFileContent()) {
          throw new Error('文件内容为空');
        }
        
        // 创建 Worker 实例
        if (!this.databaseWorker) {
          this.databaseWorker = new worker.ThreadWorker('entry/src/main/ets/workers/DatabaseWorker.ts');
          
          // 监听 Worker 消息
          this.databaseWorker.onmessage = (event: MessageEvents) => {
            const message: WorkerMessage = event.data;
            
            if (message.type === 'ready') {
              console.log('数据库 Worker 已准备就绪');
            } else if (message.type === 'loadDatabaseResult') {
              const result:LoadDatabaseResult = message.data;
              
              if (result.success) {
                // 数据库加载成功，使用主线程加载数据库
                // 这是因为 Worker 中加载的数据库对象无法直接传递回主线程
                // 所以我们只在 Worker 中验证凭据，然后在主线程中重新加载
                this.loadDatabaseInMainThread().then(resolve).catch(reject);
              } else {
                // 数据库加载失败
                console.error(`Worker 加载数据库失败: ${result.error?.message}`);
                let errorMessage = result.error?.message || '加载数据库失败';
                
                this.promptAction.showToast({ message: errorMessage,duration: 2000});
                reject(new Error(errorMessage));
              }
            }
          };
          
          // 监听 Worker 错误
          this.databaseWorker.onerror = (event: ErrorEvent) => {
            console.error(`Worker 错误: ${event.message}`);
            this.promptAction.showToast({
              message: `数据库处理错误: ${event.message}`,
              duration: 2000
            });
            reject(new Error(event.message));
          };
        }
        
        // 发送数据库加载请求到 Worker
        this.databaseWorker.postMessage({
          type: 'loadDatabase',
          data: {
            fileContent: FileService.getInstance().getFileContent(),
            password: this.password,
            keyFileContent: this.keyFileContent
          }
        });
      } catch (error) {
        console.error(`创建 Worker 或发送消息失败: ${error}`);
        let errorMessage = '加载数据库失败';
        
        if (error instanceof Error) {
          errorMessage = error.message;
        }
        
        this.promptAction.showToast({
          message: errorMessage,
          duration: 2000
        });
        reject(error);
      }
    });
  }
  
  /**
   * 在主线程中加载数据库（Worker 验证成功后）
   * 这是必要的，因为 Worker 中的复杂对象无法直接传递回主线程
   */
  private async loadDatabaseInMainThread(): Promise<Kdbx | null> {
    try {
      // 创建凭证
      let credentials: KdbxCredentials;
      if ((this.authType.type === AuthType.PASSWORD_KEYFILE.type ||
        this.authType.type === AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) && this.keyFileContent) {
        // 使用密码和密钥文件
        credentials = new KdbxCredentials(ProtectedValue.fromString(this.password), this.keyFileContent);
      } else {
        // 仅使用密码
        credentials = new KdbxCredentials(ProtectedValue.fromString(this.password));
      }
      
      // 加载数据库
      return Kdbx.load(FileService.getInstance().getFileContent(), credentials);
    } catch (error) {
      console.error(`主线程加载数据库失败: ${error}`);
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
        // 永久授权文件访问权限
        FileUtils.persistPermission(fileUri, fileShare.OperationMode.READ_MODE).then(async () => {
          this.loadKeyFileContent(fileUri);
        });
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
   * 读取密钥文件内容
   * @param fileUri 文件路径
   */
  private async loadKeyFileContent(fileUri: string) {
    console.log('loadKeyFileContent----------->', fileUri);
    // 获取文件名
    this.keyFilePath = fileUri;
    this.keyFileName = FileUtils.getFileName(fileUri);
    new KdbxFileManager(StorageType.LOCAL).loadKdbxFile(fileUri).then((fileContent) => {
      this.promptAction.showToast({ message: '密钥加载完成！' });
      this.keyFileContent = fileContent;
      this.hasKeyFileContent = true; // 更新状态变量
      this.updateButtonState(); // 更新按钮状态
    }).catch((error: Error) => {
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
    });
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

  /**
   * 更改数据库
   */
  changeDatabase() {
    // 返回到文件选择页面
    this.router.pushUrl({ url: 'pages/open/OpenDatabase' }, router.RouterMode.Single)
  }

  /**
   * 验证密码并打开数据库
   */
  async verifyAndOpenDatabase() {
    // 验证输入
    if (!this.password) {
      this.promptAction.showToast({
        message: '请输入密码',
        duration: 2000
      });
      return;
    }

    if ((this.authType.type === AuthType.PASSWORD_KEYFILE.type ||
      this.authType.type === AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) &&
      !this.keyFileContent) {
      this.promptAction.showToast({
        message: '请选择密钥文件',
        duration: 2000
      });
      return;
    }

    this.isLoading = true;
    this.updateButtonState(); // 更新按钮状态
    if (this.storageType === null) {
      this.promptAction.showToast({ message: `存储类型为空` });
      return;
    }
    // 加载并验证数据库
    this.loadDatabase().then((database) => {
      if (!database) {
        this.promptAction.showToast({ message: `数据库加载失败` });
        return;
      }
      // 设置数据库文件信息
      FileService.getInstance().setDbFileParam({
        filePath: this.filePath,
        password: this.password,
        fileName: this.fileName,
        database: database,
        keyFilePath: this.keyFilePath, // 添加密钥文件路径，以便后续保存时使用
        authType: this.authType, // 添加认证类型
        storageType: this.storageType ?? StorageType.LOCAL
      })

      // 添加到最近打开的文件列表，包含认证方式和认证文件信息
      this.recentFileService.getRecentFile(this.filePath).then((recentFile) => {
        if (recentFile) {
          this.recentFileService.addRecentFile({
            filePath: recentFile.filePath,
            fileName: recentFile.fileName,
            storageType: recentFile.storageType, // 假设是本地存储
            authType: this.authType,
            keyFilePath: this.keyFilePath
          });
        }
      })
      // 验证成功，跳转到数据库展示页面
      this.router.pushUrl({
        url: 'pages/DatabaseView'
      });
    }).catch((error: Error) => {
      console.error(`验证密码并打开数据库失败: ${error}`);
      this.promptAction.showToast({ message: '密码或密钥文件错误', duration: 2000 })
    }).finally(() => {
      this.isLoading = false;
      this.updateButtonState(); // 更新按钮状态
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
                if (this.authType.type !== AuthType.PASSWORD_KEYFILE.type &&
                  this.authType.type !== AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) {
                  this.keyFileContent = null;
                  this.hasKeyFileContent = false; // 更新状态变量
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
          Button('更改数据库')
            .height(48)
            .layoutWeight(1)
            .margin({ left: 16, right: 8 })
            .backgroundColor('#E0E0E0')  // 浅灰色背景
            .fontColor('#333333')        // 深灰色文字
            .onClick(() => {
              this.changeDatabase();
            })

          // 右侧 - 解锁按钮
          Button(this.isLoading ? '验证中...' : '解锁')
            .height(48)
            .layoutWeight(1)
            .margin({ left: 8, right: 16 })
            .enabled(this.buttonEnabled)
            .backgroundColor(this.buttonEnabled ? $r('app.color.button_background') : $r('app.color.button_disabled_background'))
            .onClick(() => {
              this.verifyAndOpenDatabase();
            })
        }
        .width('100%')
        .padding({ top: 12, bottom: 12 })
        .position({ x: 0, y: '100%' })
        .translate({ y: -74 }) // 调整位置，确保正确显示

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
