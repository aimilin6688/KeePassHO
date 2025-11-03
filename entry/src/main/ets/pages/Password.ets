import { PromptAction, Router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ErrorEvent } from '@ohos.worker';

import { AuthType, AuthTypeInfo, CredentialsParam, RecentFile } from '../services/TypeDefined';
import { RecentFilesService } from '../services/RecentFilesService';
import { StorageType } from '../services/kdbx/interfaces';
import { FileService } from '../services/FileService';
import { LoadDatabase } from '../workers/DatabaseLoadWorkerParam';
import { StorageConfig } from '../services/kdbx/interfaces/StorageConfig';
import KdbxUtils from '../common/utils/KdbxUtils';
import { Kdbx } from 'kdbxweb';
import { ContextLoadingDialog } from '../components/ContextLoadingDialog';
import ResourceManager from '../common/utils/ResourceManager';
import { LoadMessage, SuccessMessage } from '../workers/WorkerParam';
import KdbxLoadService from '../services/kdbx/KdbxLoadService';
import { FocusController } from '@ohos.arkui.UIContext';
import { SettingsService, UnlockAuthType } from '../services/SettingsService';
import { AuthService, AuthServiceCallback } from '../services/AuthService';
import { CryptoUtils } from '../common/utils/CryptoUtils';
import { DataService } from '../services/DataService';
import { LocationInfo, LocationMode, LocationParam } from '../services/beans/LocationParam';
import { Constants } from '../common/constants/Constants';

const DOMAIN = 0x0000;
const TAG = 'Password';

@Entry
@Component
struct Password {
  @State password: string = '';
  @State encryptPassword: string | undefined = undefined;
  @State isLoading: boolean = false;
  @State fileName: string = '';
  @State authTypeInfo: AuthTypeInfo = AuthType.PASSWORD;
  @State authTypeIndex: number = 0;
  @State authTypeText: string = '';
  @State keyLocation: LocationInfo | undefined = undefined;
  @State keyFileName: string = '';
  @State showPassword: boolean = false;
  @State buttonEnabled: boolean = false; // 添加状态变量控制按钮状态
  @State loadingMessage: string = ResourceManager.getString($r('app.string.loading_message'));
  private filePath: string = '';
  private storageType: StorageType | undefined = undefined;
  private storageConfig: StorageConfig | undefined = undefined;
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private focusController: FocusController = new FocusController();
  private isFingerprintSupport: boolean = false;
  private isFaceSupport: boolean = false;
  private allAuthType: AuthTypeInfo[] = AuthType.getAllTypes();
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
    //初始化认证方式
    this.setAuthType(this.authTypeInfo);

    const params = this.router.getParams() as Record<string, string>;
    // 通过位置信息直接打开
    const locationInfo: LocationInfo | undefined = AppStorage.get(Constants.APP_STORAGE_LOCATION_INFO);
    if (locationInfo) {
      this.openLocationInfo(locationInfo);
    }
    // 通过最近文件打开
    else if (params && params.filePath) {
      this.openRecentFile(params.filePath);
    }
    // 初始化按钮状态
    this.updateButtonState();
  }

  onPageShow(): void {
    this.isFingerprintSupport = AuthService.isFingerprintSupportAndEnabled();
    this.isFaceSupport = AuthService.isFaceSupportAndEnabled();
  }

  aboutToDisappear() {
    KdbxLoadService.stopWorker();
  }

  /**
   * 通过位置信息打开
   */
  private openLocationInfo(locationInfo: LocationInfo) {
    hilog.debug(DOMAIN, TAG, 'Open Location Info: %{public}s', locationInfo)
    this.fileName = locationInfo.fileName;
    this.filePath = locationInfo.filePath;
    this.storageType = locationInfo.storageType;
    this.storageConfig = locationInfo.storageConfig;
    AppStorage.delete(Constants.APP_STORAGE_LOCATION_INFO);
  }

  // 更新按钮状态
  private updateButtonState(): void {
    if (this.isLoading || this.password.length === 0) {
      this.buttonEnabled = false;
      return;
    }
    if ((this.authTypeInfo.type === AuthType.PASSWORD_KEYFILE.type ||
      this.authTypeInfo.type === AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) && !this.keyLocation) {
      this.buttonEnabled = false;
      return;
    }
    this.buttonEnabled = true;
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
    RecentFilesService.getRecentFile(filePath).then(recentFile => {
      if (recentFile) {
        this.fileName = recentFile.fileName;
        this.filePath = recentFile.filePath;
        this.storageType = recentFile.storageType;
        this.storageConfig = recentFile.storageConfig;
        // 设置认证类型
        if (recentFile.authType) {
          this.setAuthType(recentFile.authType);
        }
        // 获取密钥文件路径
        if (recentFile.keyLocation) {
          this.keyLocation = recentFile.keyLocation;
          this.keyFileName = this.keyLocation.fileName;
        }
        // 生物认证
        this.startAuth(recentFile.password);
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
   * 设置认证方式
   */
  private setAuthType(authType: AuthTypeInfo) {
    const type = AuthType.getByType(authType.type);
    this.authTypeInfo = type;
    this.authTypeIndex = AuthType.getIndexByType(type.type);
    this.authTypeText = ResourceManager.getString(type.value);
  }

  /**
   * 通过指纹认证
   */
  private async startAuth(password: string | undefined, authType?: UnlockAuthType) {
    if (!password || password == '') {
      return;
    }
    if (!this.isFingerprintSupport && !this.isFaceSupport) {
      hilog.debug(DOMAIN, TAG, `auth is not supported. isFingerprintSupport: ${this.isFingerprintSupport}, isFaceSupport: ${this.isFaceSupport}`);
      return;
    }
    // 加密密钥
    this.encryptPassword = password;
    // 默认认证方式
    authType =
      authType ?? await SettingsService.getInstance()
        .get(SettingsService.KEY_SECURITY_AUTH_DEFAULT_TYPE, SettingsService.KEY_SECURITY_AUTH_DEFAULT_TYPE_DEFAULT);

    // 指纹或者人脸验证
    if (authType === UnlockAuthType.FINGERPRINT) {
      AuthService.startFingerprintAuth(this.authCallback(password));
    } else if (authType === UnlockAuthType.FACE) {
      AuthService.startFaceAuth(this.authCallback(password));
    }
  }

  // 认证结果回调
  private authCallback(password: string) {
    return {
      onSuccess: (result) => {
        CryptoUtils.decryptText(password).then(result => {
          this.password = result;
          this.verifyAndOpenDatabase();
        });
      },
      onError: (error) => {
        hilog.info(DOMAIN, TAG, 'Fingerprint auth error: ' + error.message);
        this.promptAction.showToast({ message: error.message });
      }
    } as AuthServiceCallback;
  }

  /**
   * 选择密钥文件
   */
  private selectKeyFile() {
    LocationParam.of({
      mode: LocationMode.SELECT,
      onLocation: (locationInfo: LocationInfo) => {
        this.keyLocation = locationInfo;
        this.keyFileName = locationInfo.fileName;
        this.updateButtonState();
        this.router.back({ url: 'pages/Password' });
      }
    });
    this.router.pushUrl({ url: 'pages/open/SelectLocation' });
  }

  /**
   * 更改数据库
   */
  changeDatabase() {
    // 返回到文件选择页面
    DataService.selectKdbx(this.router);
    this.router.pushUrl({ url: 'pages/open/SelectLocation' })
  }

  /**
   * 打开进度弹框
   */
  private openLoadingDialog() {
    this.isLoading = true;
    this.updateButtonState(); // 更新按钮状态
    this.loadingDialogController.open();
  }

  /**
   * 管理进度弹框
   */
  private closeLoadingDialog() {
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

    if ((this.authTypeInfo.type === AuthType.PASSWORD_KEYFILE.type ||
      this.authTypeInfo.type === AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) && !this.keyLocation) {
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

    // 打开加载进度弹框
    this.openLoadingDialog();
    // 打开数据库
    let loadDatabase =
      new LoadDatabase(this.filePath, this.fileName, this.password, this.authTypeInfo, this.keyLocation, this.storageType, this.storageConfig);
    KdbxLoadService.loadDatabase(loadDatabase, {
      onLoadMessage: (message: LoadMessage) => {
        this.loadingMessage = ResourceManager.getString(message.message);
      },
      onSuccessMessage: (message: SuccessMessage) => {
        this.handleSuccessMessage(message);
      },
      onErrorMessage: (message: LoadMessage) => {
        this.promptAction.showToast({ message: ResourceManager.getString(message.message), duration: 3000 });
        this.closeLoadingDialog();
      },
      onAllErrors: (error: ErrorEvent) => {
        this.promptAction.showToast({ message: error.message })
        this.closeLoadingDialog();
      },
      onexit: (e: number) => {
        this.closeLoadingDialog();
      }
    });
  }

  /**
   * 处理数据库加载完成事件
   * @param data
   */
  private handleSuccessMessage(successMessage: SuccessMessage) {
    this.init();
    this.putFileToRecentFile();
    this.setFileParam(successMessage).then(() => {
      this.loadingMessage = ResourceManager.getString($r('app.string.open_success'));
      this.router.pushUrl({ url: 'pages/DatabaseView' });
      this.closeLoadingDialog();
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Database open failed: %{public}s', error.message);
      this.promptAction.showToast({ message: error.message, duration: 3000 });
      this.closeLoadingDialog();
    });
  }

  /**
   * 设置数据库文件信息
   */
  private setFileParam(successMessage: SuccessMessage): Promise<void> {
    let date = new Date().getTime();
    return KdbxUtils.arrayBufferToKdbx(successMessage.data, {
      password: this.password,
      authType: this.authTypeInfo,
      keyLocation: this.keyLocation,
    } as CredentialsParam).then((kdbx: Kdbx) => {
      hilog.info(DOMAIN, TAG, 'Array buffer to kdbx time: %{public}d ms', new Date().getTime() - date);
      // 设置数据库文件信息
      FileService.setDbFileParam({
        filePath: this.filePath,
        password: this.password,
        fileName: this.fileName,
        database: kdbx,
        keyLocation: this.keyLocation, // 添加密钥文件路径，以便后续保存时使用
        authType: this.authTypeInfo, // 添加认证类型
        storageType: this.storageType ?? StorageType.LOCAL,
        storageConfig: this.storageConfig ?? {},
        modifiedTime: successMessage.modifiedTime
      })
    });
  }

  /**
   * 初始化
   */
  private init() {
    KdbxUtils.init();
    FileService.init();
  }

  /**
   * 文件打开成功，保存到最近访问列表中
   */
  private putFileToRecentFile() {
    // 最近打开的文件
    let recentFile = {
      filePath: this.filePath,
      fileName: this.fileName,
      storageType: this.storageType ?? StorageType.LOCAL,
      authType: this.authTypeInfo,
      keyLocation: this.keyLocation,
      storageConfig: this.storageConfig ?? {}
    } as RecentFile;
    hilog.info(DOMAIN, TAG, '%{public}s', `Put database file to recent file list: ${this.filePath}`)
    // 如果开启指纹登录
    if (this.isFingerprintSupport || this.isFaceSupport) {
      CryptoUtils.encryptText(this.password).then(result => {
        recentFile.password = result;
        RecentFilesService.getInstance().addRecentFile(recentFile);
      });
    } else {
      RecentFilesService.getInstance().addRecentFile(recentFile);
    }
  }

  /**
   * 获取认证方式名称
   * @param authType
   * @returns
   */
  private getAuthTypeName(authType: AuthTypeInfo): ResourceStr {
    return this.allAuthType.find(item => item.type === authType.type)?.value ?? this.allAuthType[0].value;
  }

  build() {
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

        Text($r('app.string.Password_unlock_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)

      // 主要内容区域
      Column() {
        // Logo或应用图标
        Image($r('app.media.startIcon'))
          .width(90)
          .height(90)
          .margin({ top: 40, bottom: 10 })
        // 文件名显示
        Text(this.fileName)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .margin({ bottom: 32 })
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

          Select(this.allAuthType)
            .selected(this.authTypeIndex)
            .value(this.authTypeText)
            .font({ size: 16 })
            .fontColor($r('app.color.text_primary'))
            .selectedOptionFont({ size: 16 })
            .optionFont({ size: 16 })
            .width('100%')
            .onSelect((index: number, value: string) => {
              this.setAuthType(AuthType.getByIndex(index));
              // 如果选择的认证类型不需要密钥文件，则清除密钥文件相关的状态
              if (this.authTypeInfo.type !== AuthType.PASSWORD_KEYFILE.type &&
                this.authTypeInfo.type !== AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) {
                this.keyLocation = undefined;
                this.keyFileName = '';
              }
              this.updateButtonState(); // 更新按钮状态
            })
        }
        .width('90%')
        .padding({ left: 16, right: 16, bottom: 24 })

        // 密码输入框
        Row() {
          TextInput({ placeholder: $r('app.string.password_placeholder') })
            .key("passwordInput")
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
            .onAppear(() => {
              try {
                this.focusController.requestFocus("passwordInput");
              } catch (error) {
                hilog.error(DOMAIN, TAG, 'PasswordInput con not get focus: %{public}s', error?.message);
              }
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
        if (this.authTypeInfo.type === AuthType.PASSWORD_KEYFILE.type ||
          this.authTypeInfo.type === AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type) {
          this.KeyFileSelector()
        }

        if (this.encryptPassword) {
          Row() {
            if (this.isFingerprintSupport) {
              Text($r('app.string.auth_by_fingerprint'))
                .fontSize(14)
                .fontColor($r('app.color.button_bg_blue'))
                .margin({ bottom: 8, left: 8, right: 8 })
                .decoration({
                  type: TextDecorationType.Underline,
                  color: $r('app.color.button_bg_blue')
                })
                .onClick(() => {
                  this.startAuth(this.encryptPassword, UnlockAuthType.FINGERPRINT);
                })
            }

            if (this.isFaceSupport) {
              Text($r('app.string.auth_by_face'))
                .fontSize(14)
                .fontColor($r('app.color.button_bg_blue'))
                .margin({ bottom: 8, left: 8, right: 8 })
                .decoration({
                  type: TextDecorationType.Underline,
                  color: $r('app.color.button_bg_blue')
                })
                .onClick(() => {
                  this.startAuth(this.encryptPassword, UnlockAuthType.FACE);
                })
            }
          }
          .justifyContent(FlexAlign.Center)
          .width('100%')
          .position({ x: 0, y: '100%' })
          .translate({ y: -100 }) // 调整位置，确保正确显示
        }

        // 底部固定按钮栏
        Row() {
          // 左侧 - 更改数据库按钮
          Button($r("app.string.change_database"))
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
      .padding({ top: 16 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
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
