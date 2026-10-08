import { PromptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ErrorEvent } from '@ohos.worker';

import { AuthType, AuthTypeInfo, CredentialsParam, RecentFile } from '../services/TypeDefined';
import { RecentFilesService } from '../services/RecentFilesService';
import { StorageConfig, StorageType } from '../storage';
import { FileService } from '../services/FileService';
import { LoadDatabase } from '../workers/DatabaseLoadWorkerParam';
import { CommonUtils, CryptoUtils, KdbxUtils, NavigationManager, ResourceManager, StringUtils, WindowUtils } from '../common/utils';
import { Kdbx } from 'kdbxweb';
import { LoadProgressDialog } from '../components/LoadProgressDialog';
import { LoadMessage, ProgressMessage, SuccessMessage } from '../workers/WorkerParam';
import KdbxLoadService from '../services/kdbx/KdbxLoadService';
import { LoadDispatchService } from '../services/kdbx/LoadDispatchService';
import { FocusController } from '@ohos.arkui.UIContext';
import { SettingsService, UnlockAuthType } from '../services/SettingsService';
import { LockScreenService } from '../services/LockScreenService';
import { EventBus } from '../services/EventBus';
import { AuthService, AuthServiceCallback } from '../services/AuthService';
import { DataService } from '../services/DataService';
import { LocationInfo, LocationMode, LocationParam } from '../services/beans/LocationParam';
import { Constants } from '../common/constants/Constants';
import { common } from '@kit.AbilityKit';
import { CacheConstants } from '../storage/cache/CacheConstants';
import { PageConstants } from '../common/constants/PageConstants';

const DOMAIN = 0x0000;
const TAG = 'Password';

// Password页面的Builder函数
@Builder
export function PasswordBuilder(name: string, param: Object): void {
  NavDestination() {
    Password()
  }
  .title($r('app.string.Password_unlock_title'))
  .backgroundColor($r('app.color.bg_primary'))
  .onShown(() => {
    // NavDestination 下 onPageShow 不回调，通过计数驱动页面显示处理
    AppStorage.set<number>('password_page_shown_tick', (AppStorage.get<number>('password_page_shown_tick') ?? 0) + 1);
  })
}

@Component
export struct Password {
  private navManager: NavigationManager = NavigationManager.getInstance();
  // 实际使用的导航栈（在 aboutToAppear 中初始化）
  private workingNavPathStack: NavPathStack | null = null;
  @State password: string = '';
  @State isShowBiometric: boolean = false; // 是否显示生物认证
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
  @State showCacheCheckbox: boolean = false; // 是否显示缓存复选框
  @State onlyUseCache: boolean = false; // 是否仅使用本地缓存
  // 下载数据库进度（-1 表示当前阶段无进度）
  @State progressPercent: number = -1;
  @State progressDetail: string = '';
  private filePath: string = '';
  private storageType: StorageType | undefined = undefined;
  private storageConfig: StorageConfig | undefined = undefined;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private focusController: FocusController = new FocusController();
  // 生物认证支持状态（在 onPageShow 中初始化，依赖 SettingsService）
  private isFingerprintSupport: boolean = false;
  private isFaceSupport: boolean = false;
  private allAuthType: AuthTypeInfo[] = AuthType.getAllTypes();
  private recentFile: RecentFile | undefined = undefined;
  // 标记是否需要启动生物认证（用于 onPageShow 判断）
  private shouldStartAuth: boolean = false;
  // 标记是否应该保留密码（用于选择密钥文件等场景）
  private shouldPreservePassword: boolean = false;
  // 带内容的进度弹框（下载数据库阶段带线性进度条）
  private loadingDialogController: CustomDialogController = new CustomDialogController({
    builder: LoadProgressDialog({
      loadingMessage: this.loadingMessage,
      progressPercent: this.progressPercent,
      progressDetail: this.progressDetail
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });

  aboutToAppear() {
    //初始化认证方式
    this.setAuthType(this.authTypeInfo);

    // 优先使用当前导航栈：页面被 push 到哪个栈就从哪个栈取参
    // （如从 DatabaseView 根切换数据库时 replaceAll 会把本页 push 到 DatabaseView 栈，
    //   若固定从 Index 栈取参会读到首次打开时残留的旧 Password 参数，导致显示旧数据库）
    this.workingNavPathStack = NavigationManager.getInstance().getNavPathStack();

    if (!this.workingNavPathStack) {
      // 降级方案: 使用 Index 根页面导航栈
      this.workingNavPathStack = NavigationManager.getInstance().getNavPathStackByRoot('Index');
    }

    if (!this.workingNavPathStack) {
      hilog.error(DOMAIN, TAG, 'Failed to get NavPathStack from NavigationManager');
      return;
    }

    hilog.info(DOMAIN, TAG, 'NavPathStack initialized successfully');

    // 通过Navigation系统获取参数
    const paramsArray: Object[] = this.workingNavPathStack.getParamByName(PageConstants.PAGE_PASSWORD) as Object[];
    // 取最后一个（最近 push 的）参数，避免读到栈中残留的旧参数
    const params: Record<string, string> | undefined = paramsArray && paramsArray.length > 0
      ? paramsArray[paramsArray.length - 1] as Record<string, string> : undefined;
    // 通过位置信息直接打开
    const locationInfo: LocationInfo | undefined = AppStorage.get(Constants.APP_STORAGE_LOCATION_INFO);
    if (locationInfo) {
      this.openLocationInfo(locationInfo);
    }
    // 通过最近文件打开
    else if (params && params.filePath) {
      // 使用预加载的最近文件信息
      this.openRecentFileOptimized(params.filePath);
    }
    // 其他方式打开
    else {
      this.passwordInputFocus();
    }
    // 初始化按钮状态
    this.updateButtonState();
  }

  // NavDestination 下 onPageShow 不回调，由 NavDestination.onShown 驱动页面显示处理
  @StorageProp('password_page_shown_tick') @Watch('onPageShownTickChange') pageShownTick: number = 0;

  onPageShownTickChange(): void {
    this.onPageShow();
  }

  onPageShow(): void {
    // 安全措施: 页面显示时清除敏感数据
    // 除非明确标记需要保留密码（如选择密钥文件场景）
    if (!this.shouldPreservePassword) {
      this.clearSensitiveData();
      hilog.info(DOMAIN, TAG, 'onPageShow: cleared sensitive data for security');
    } else {
      // 重置标志,下次进入时清除
      this.shouldPreservePassword = false;
      hilog.info(DOMAIN, TAG, 'onPageShow: preserved password for current operation');
    }

    // 因为 SettingsService 可能还在异步初始化中
    this.isFingerprintSupport = AuthService.isFingerprintSupportAndEnabled();
    this.isFaceSupport = AuthService.isFaceSupportAndEnabled();
    hilog.info(DOMAIN, TAG, `onPageShow: isFingerprintSupport=${this.isFingerprintSupport}, isFaceSupport=${this.isFaceSupport}, shouldStartAuth=${this.shouldStartAuth}`);
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);

    // 如果标记需要启动生物认证，则启动
    if (this.shouldStartAuth) {
      this.shouldStartAuth = false;
      hilog.info(DOMAIN, TAG, 'onPageShow: starting auth due to shouldStartAuth=true');
      this.startAuth();
    }
  }

  aboutToDisappear() {
    // 安全措施: 页面销毁时清除敏感数据
    // 注意：不再 stopWorker——常驻池化下 Worker 进程级复用，
    // 解锁跳转即销毁会使池化失效（loading 弹框关闭由三终态回调覆盖）
    this.clearSensitiveData();
  }

  /**
   * 通过位置信息打开
   */
  private openLocationInfo(locationInfo: LocationInfo) {
    setTimeout(() => {
      this.passwordInputFocus();
    }, 0);
    hilog.debug(DOMAIN, TAG, 'Open Location Info: %{public}s', locationInfo)
    this.fileName = locationInfo.fileName;
    this.filePath = locationInfo.filePath;
    this.storageType = locationInfo.storageType;
    this.storageConfig = locationInfo.storageConfig;
    AppStorage.delete(Constants.APP_STORAGE_LOCATION_INFO);
    this.initCacheCheckbox();
    this.prewarmLoadWorker();
  }

  /**
   * 通过最近文件打开（优化版）
   * 优先使用预加载数据，加速生物认证调用
   */
  private openRecentFileOptimized(filePath: string): void {
    if (!filePath) {
      CommonUtils.showToast({ message: $r('app.string.invalid_data_file'), duration: 2000 });
      this.navigateBack();
      return;
    }

    // 优先使用预加载的最近文件信息
    const preloadedRecentFile = AppStorage.get<RecentFile>(Constants.APP_STORAGE_PRELOAD_RECENT_FILE);
    if (preloadedRecentFile && preloadedRecentFile.filePath === filePath) {
      hilog.info(DOMAIN, TAG, 'Using preloaded recent file for password page');
      this.applyRecentFile(preloadedRecentFile);
      // 尝试启动生物认证
      this.tryStartAuth();
      return;
    }

    // 回退到原始方式
    hilog.info(DOMAIN, TAG, 'Fallback to getRecentFile for: %{public}s', filePath);
    this.openRecentFile(filePath);
  }

  /**
   * 应用最近文件信息
   */
  private applyRecentFile(recentFile: RecentFile): void {
    this.recentFile = recentFile;
    this.fileName = recentFile.fileName;
    this.filePath = recentFile.filePath;
    this.storageType = recentFile.storageType;
    this.storageConfig = recentFile.storageConfig;
    // 设置认证类型
    if (recentFile.authType) {
      this.setAuthType(recentFile.authType);
    }
    // 是否使用缓存复选框
    this.initCacheCheckbox();
    this.updateButtonState();
    // 分级加载预热点：大库在用户输密码期间预热常驻 Worker
    this.prewarmLoadWorker();
  }

  /**
   * 分级加载预热点：远端大库（> 主线程阈值）预热常驻加载 Worker
   * （isolate 模块图 + 存储连接 + 大小探测），小库/本地库不建 Worker
   */
  private prewarmLoadWorker(): void {
    const storageType = this.storageType;
    if (storageType !== undefined && storageType !== StorageType.LOCAL && this.filePath) {
      LoadDispatchService.prepare(storageType, this.storageConfig ?? {}, this.filePath);
    }
  }

  // 更新按钮状态
  private updateButtonState(): void {
    // 仅密钥文件模式：不需要密码，但需要密钥文件
    if (AuthType.isKeyfileOnly(this.authTypeInfo)) {
      if (this.isLoading || !this.keyLocation) {
        this.buttonEnabled = false;
        return;
      }
      this.buttonEnabled = true;
      return;
    }

    // 其他模式：需要密码
    if (this.isLoading || this.password.length === 0) {
      this.buttonEnabled = false;
      return;
    }

    // 密码+密钥文件模式：需要密钥文件
    if (AuthType.useKeyAuth(this.authTypeInfo) && !AuthType.isKeyfileOnly(this.authTypeInfo) && !this.keyLocation) {
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
      CommonUtils.showToast({ message: $r('app.string.invalid_data_file'), duration: 2000 });
      this.navigateBack();
      return;
    }
    // 获取最近打开记录
    RecentFilesService.getRecentFile(filePath).then(recentFile => {
      if (recentFile) {
        this.applyRecentFile(recentFile);
        // 尝试启动生物认证
        this.tryStartAuth();
      } else {
        // 文件记录未找到（可能已被自动清理或远端同步覆盖），提示并返回
        hilog.warn(DOMAIN, TAG, 'Recent file not found for: %{public}s', filePath);
        CommonUtils.showToast({
          message: $r('app.string.recent_file_not_found'),
          duration: 2000
        });
        this.navigateBack();
      }
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Failed to open recent file: %{public}s, stack: %{public}s', error.message, error.stack);
      CommonUtils.showToast({
        message: $r('app.string.open_failed', error.message),
        duration: 2000
      });
      this.navigateBack();
    });
  }

  /**
   * 尝试启动生物认证
   * - 如果生物认证支持状态已初始化，直接启动
   * - 否则标记需要在 onPageShow 中启动
   */
  private tryStartAuth(): void {
    hilog.info(DOMAIN, TAG, `tryStartAuth: isFingerprintSupport=${this.isFingerprintSupport}, isFaceSupport=${this.isFaceSupport}`);
    // 如果生物认证支持状态已初始化（onPageShow 已执行）
    if (this.isFingerprintSupport || this.isFaceSupport) {
      hilog.info(DOMAIN, TAG, 'tryStartAuth: starting auth immediately');
      this.startAuth();
    } else {
      // 标记需要启动，等待 onPageShow 执行
      hilog.info(DOMAIN, TAG, 'tryStartAuth: setting shouldStartAuth=true');
      this.shouldStartAuth = true;
    }
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
   * 初始化缓存复选框状态
   */
  private async initCacheCheckbox(): Promise<void> {
    // 仅对远程存储类型显示缓存复选框
    if (this.storageType !== StorageType.LOCAL && this.filePath) {
      this.showCacheCheckbox = await CacheConstants.cacheExists(this.filePath);
      this.onlyUseCache = CacheConstants.getOnlyCache();
    } else {
      this.showCacheCheckbox = false;
      this.onlyUseCache = false;
    }
  }

  /**
   * 通过指纹认证
   */
  private async startAuth(authType?: UnlockAuthType) {
    hilog.info(DOMAIN, TAG, `startAuth called: authType=${authType}, isKeyfileOnly=${AuthType.isKeyfileOnly(this.authTypeInfo)}, hasPassword=${!!this.recentFile?.password}`);
    // 仅密钥文件模式：不需要密码，但需要密钥文件
    if (!AuthType.isKeyfileOnly(this.authTypeInfo)) {
      // 获取密钥文件路径
      if (this.recentFile?.keyLocation) {
        this.keyLocation = this.recentFile.keyLocation;
        this.keyFileName = this.keyLocation.fileName;
      }
      // 未保存密钥信息
      if (!this.recentFile?.password || this.recentFile?.password == '') {
        this.passwordInputFocus();
        return;
      }
    }

    if (!this.isFingerprintSupport && !this.isFaceSupport) {
      hilog.debug(DOMAIN, TAG, `auth is not supported. isFingerprintSupport: ${this.isFingerprintSupport}, isFaceSupport: ${this.isFaceSupport}`);
      this.passwordInputFocus();
      return;
    }
    this.isShowBiometric = true;
    // 默认认证方式
    authType = authType ?? await SettingsService.getInstance().get(SettingsService.KEY_SECURITY_AUTH_DEFAULT_TYPE, SettingsService.KEY_SECURITY_AUTH_DEFAULT_TYPE_DEFAULT);
    hilog.info(DOMAIN, TAG, `call authType: ${authType}`);
    // 指纹或者人脸验证
    if (authType === UnlockAuthType.FINGERPRINT) {
      AuthService.startFingerprintAuth(this.authCallback());
    } else if (authType === UnlockAuthType.FACE) {
      AuthService.startFaceAuth(this.authCallback());
    } else {
      this.passwordInputFocus();
    }
  }

  // 认证结果回调
  private authCallback() {
    return {
      onSuccess: (result) => {
        // 仅密钥模式
        if (AuthType.isKeyfileOnly(this.authTypeInfo)) {
          this.keyLocation = this.recentFile?.keyLocation;
          this.keyFileName = this.keyLocation?.fileName || '';
          this.verifyAndOpenDatabase();
        } else {
          CryptoUtils.decryptText(this.recentFile?.password || '').then(result => {
            this.password = result;
            this.verifyAndOpenDatabase();
          });
        }
      },
      onError: (error) => {
        hilog.info(DOMAIN, TAG, 'Fingerprint auth error: ' + error.message);
        // 安全措施: 认证失败或取消时清除密码
        this.clearSensitiveData();
        CommonUtils.showToast({ message: error.message });
      }
    } as AuthServiceCallback;
  }

  /**
   * 清除敏感数据
   * 安全措施: 在生物认证失败/取消或页面离开时清除
   */
  private clearSensitiveData(): void {
    this.password = '';
    this.showPassword = false;
    this.shouldPreservePassword = false; // 重置保留标志
    this.updateButtonState();
    hilog.info(DOMAIN, TAG, 'Sensitive data cleared for security');
  }

  /**
   * 选择密钥文件
   */
  private selectKeyFile() {
    // 标记需要保留密码,因为用户可能已经输入了密码
    this.shouldPreservePassword = true;

    LocationParam.of({
      mode: LocationMode.SELECT,
      onLocation: (locationInfo: LocationInfo) => {
        this.keyLocation = locationInfo;
        this.keyFileName = locationInfo.fileName;
        this.shouldStartAuth = false; // 清除生物认证标志
        this.updateButtonState();
        // 返回到密码页面
        this.navigateBack();
      }
    });
    if (this.workingNavPathStack) {
      this.workingNavPathStack.pushPathByName('SelectLocation', null);
    } else {
      hilog.error(DOMAIN, TAG, 'selectKeyFile: NavPathStack is null!');
    }
  }

  /**
   * 更改数据库
   */
  changeDatabase() {
    // 返回到文件选择页面
    DataService.selectKdbx();

    // 防御性检查 + 自动恢复
    if (!this.workingNavPathStack) {
      hilog.warn(DOMAIN, TAG, 'NavPathStack is null, attempting to recover...');
      this.workingNavPathStack = NavigationManager.getInstance().getNavPathStackByRoot('Index') ||
                                   NavigationManager.getInstance().getNavPathStack();
    }

    if (this.workingNavPathStack) {
      try {
        this.workingNavPathStack.pushPathByName('SelectLocation', null);
        hilog.info(DOMAIN, TAG, 'Navigated to SelectLocation');
      } catch (error) {
        hilog.error(DOMAIN, TAG, `Navigation failed: ${JSON.stringify(error)}`);
        CommonUtils.showToast({
          message: '导航失败',
          duration: 2000
        });
      }
    } else {
      hilog.error(DOMAIN, TAG, 'Cannot navigate: NavPathStack unavailable');
      CommonUtils.showToast({
        message: '导航栈不可用',
        duration: 2000
      });
    }
  }

  /**
   * 统一的返回导航方法
   */
  private navigateBack(): void {
    if (this.workingNavPathStack) {
      this.workingNavPathStack.pop();
    } else {
      hilog.error(DOMAIN, TAG, 'Cannot navigate back: NavPathStack is null');
    }
  }

  /**
   * 打开进度弹框
   */
  private openLoadingDialog() {
    this.isLoading = true;
    this.updateButtonState(); // 更新按钮状态
    this.resetProgressState();
    this.loadingDialogController.open();
  }

  /**
   * 重置传输进度状态（每次加载开始时清零）
   */
  private resetProgressState() {
    this.progressPercent = -1;
    this.progressDetail = '';
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
    // 仅密钥文件模式验证
    if (AuthType.isKeyfileOnly(this.authTypeInfo)) {
      if (!this.keyLocation) {
        CommonUtils.showToast({
          message: $r('app.string.select_key_file'),
          duration: 2000
        });
        return;
      }
    } else {
      // 其他模式：验证密码输入
      if (!this.password) {
        CommonUtils.showToast({
          message: $r('app.string.password_placeholder'),
          duration: 2000
        });
        return;
      }

      // 密码+密钥文件模式验证
      if (AuthType.useKeyAuth(this.authTypeInfo) && !this.keyLocation) {
        CommonUtils.showToast({
          message: $r('app.string.select_key_file'),
          duration: 2000
        });
        return;
      }
    }

    if (this.storageType === null) {
      CommonUtils.showToast({ message: $r('app.string.storage_type_empty') });
      return;
    }

    // 打开加载进度弹框
    this.openLoadingDialog();
    // 打开数据库
    let loadDatabase = new LoadDatabase(this.filePath, this.fileName, this.password, this.authTypeInfo, this.keyLocation, this.storageType, this.storageConfig);
    KdbxLoadService.loadDatabase(loadDatabase, {
      onLoadMessage: (message: LoadMessage) => {
        this.loadingMessage = ResourceManager.getMessage(message.message);
        this.resetProgressState();
      },
      onProgressMessage: (message: ProgressMessage) => {
        this.progressPercent = message.percent;
        if (message.totalBytes > 0) {
          this.progressDetail =
            `${StringUtils.formatFileSize(message.transferredBytes)} / ${StringUtils.formatFileSize(message.totalBytes)}`;
        }
      },
      onSuccessMessage: (message: SuccessMessage) => {
        this.handleSuccessMessage(message);
      },
      onErrorMessage: (message: LoadMessage) => {
        CommonUtils.showToast({ message: ResourceManager.getMessage(message.message), duration: 3000 });
        this.closeLoadingDialog();
      },
      onAllErrors: (error: ErrorEvent) => {
        CommonUtils.showToast({ message: error.message })
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
    this.putFileToRecentFile(successMessage);
    this.setFileParam(successMessage).then(() => {
      this.loadingMessage = ResourceManager.getString($r('app.string.open_success'));
      // 清空本页所在的导航栈（移除 Password 自身及其下方残留页面），
      // 否则切换根页面后该栈残留 Password，之后切回此根（如点击设置）会再次显示解锁页面
      if (this.workingNavPathStack) {
        this.workingNavPathStack.clear();
      }
      // DatabaseView 是根页面，使用 navigateBackToRoot 切换
      this.navManager.navigateBackToRoot(PageConstants.PAGE_DATABASE_VIEW);
      this.closeLoadingDialog();
      // 通知解锁会话：与 UnLockDatabase 页保持同一事件流（冷启动/换库路径此前缺失）
      EventBus.emit(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Database open failed: %{public}s', error.message);
      CommonUtils.showToast({ message: error.message, duration: 3000 });
      this.closeLoadingDialog();
    });
  }

  /**
   * 设置数据库文件信息
   * @param successMessage successMessage
   * @returns Promise<void>
   * @throws Error
   */
  private setFileParam(successMessage: SuccessMessage): Promise<void> {
    let date = new Date().getTime();
    return KdbxUtils.successMessageToKdbx(successMessage, {
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
        modifiedTime: successMessage.modifiedTime,
        version: successMessage.version ?? null,
        contentHash: successMessage.contentHash ?? null
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
   * @param successMessage 加载成功消息（fileSize 持久化为分级调度快照）
   */
  private putFileToRecentFile(successMessage?: SuccessMessage) {
    // 最近打开的文件
    let recentFile = {
      filePath: this.filePath,
      fileName: this.fileName,
      storageType: this.storageType ?? StorageType.LOCAL,
      authType: this.authTypeInfo,
      keyLocation: this.keyLocation,
      storageConfig: this.storageConfig ?? {},
      fileSize: (successMessage?.fileSize !== undefined && successMessage.fileSize > 0)
        ? successMessage.fileSize : undefined
    } as RecentFile;
    hilog.info(DOMAIN, TAG, '%{public}s', `Put database file to recent file list: ${this.filePath}`)
    // 如果开启指纹登录
    if (this.isFingerprintSupport || this.isFaceSupport) {
      CryptoUtils.encryptText(this.password).then(result => {
        recentFile.password = result;
        RecentFilesService.addRecentFile(recentFile).catch((error: Error) => {
          hilog.error(DOMAIN, TAG, 'Add database file to recent file list failed: %{public}s', error.message);
          CommonUtils.showToast({ message: error.message, duration: 3000 });
        });
      });
    } else {
      RecentFilesService.addRecentFile(recentFile).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Add database file to recent file list failed: %{public}s', error.message);
        CommonUtils.showToast({ message: error.message, duration: 3000 });
      });
    }
  }

  /**
   * 密码输入框获取焦点
   */
  private passwordInputFocus() {
    try {
      this.focusController.requestFocus("passwordInput");
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'PasswordInput con not get focus: %{public}s', error?.message);
    }
  }

  build() {
    Column() {
      GridRow({
        columns: { xs: 2, sm: 5, md: 8, lg: 12, xl: 12, xxl: 12 },
        breakpoints: {
          value: ['320vp', '600vp', '840vp'],
          reference: BreakpointsReference.WindowSize
        }
      }) {
        GridCol({
          span: { xs: 2, sm: 5, md: 6, lg: 6, xl: 4, xxl: 4 },
          offset: { xs: 0, sm: 0, md: 1, lg: 3, xl: 4, xxl: 4 }
        }) {
          Column() {
            // 顶部：表单内容组
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
                .width('100%')
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
                  .id('select_auth_type')
                  .width('100%')
                  .onSelect((index: number, value: string) => {
                    this.setAuthType(AuthType.getByIndex(index));
                    // 如果选择的认证类型不需要密钥文件，则清除密钥文件相关的状态
                    if (!AuthType.useKeyAuth(this.authTypeInfo)) {
                      this.keyLocation = undefined;
                      this.keyFileName = '';
                    }
                    this.updateButtonState(); // 更新按钮状态
                  })
              }
              .width('100%')
              .padding({ left: 16, right: 16, bottom: 24 })

              // 密码输入框（仅密钥文件模式下隐藏）
              if (!AuthType.isKeyfileOnly(this.authTypeInfo)) {
                Row() {
                  TextInput({ placeholder: $r('app.string.password_placeholder') })
                    .id('input_password')
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
                .width('100%')
                .padding({ left: 16, right: 16 })
                .border({
                  width: { bottom: 1 },
                  color: $r('app.color.divider')
                })
                .margin({ bottom: 16 })
              }

              // 密钥文件选择（仅在需要密钥文件的认证方式时显示）
              if (AuthType.useKeyAuth(this.authTypeInfo)) {
                this.KeyFileSelector()
              }

              // 仅使用本地缓存复选框（仅在远程存储且有缓存时显示）
              if (this.showCacheCheckbox) {
                Row() {
                  Checkbox({ name: 'onlyUseCache' })
                    .select(this.onlyUseCache)
                    .shape(CheckBoxShape.ROUNDED_SQUARE)
                    .onChange((isSelected: boolean) => {
                      this.onlyUseCache = isSelected;
                      CacheConstants.setOnlyCache(isSelected);
                    })
                  Text($r('app.string.only_use_local_cache'))
                    .fontSize(14)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ left: 8 })
                    .onClick(() => {
                      this.onlyUseCache = !this.onlyUseCache;
                      CacheConstants.setOnlyCache(this.onlyUseCache);
                    })
                }
                .width('100%')
                .padding({
                  left: 16,
                  right: 16,
                  top: 8,
                  bottom: 8
                })
                .alignItems(VerticalAlign.Center)
              }
            }

            // 底部：生物认证 + 按钮组（SpaceBetween 自然贴底，替代原 position/translate 绝对定位）
            Column() {
              if (this.isShowBiometric) {
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
                        this.startAuth(UnlockAuthType.FINGERPRINT);
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
                        this.startAuth(UnlockAuthType.FACE);
                      })
                  }
                }
                .justifyContent(FlexAlign.Center)
                .width('100%')
              }

              // 底部固定按钮栏
              Row() {
                // 左侧 - 更改数据库按钮
                Button($r("app.string.change_database"))
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(16)
                  .fontColor($r('app.color.button_text'))
                  .borderRadius(20)
                  .backgroundColor(Color.Gray)
                  .id('btn_change_database')
                  .onClick(() => {
                    this.changeDatabase();
                  })

                Blank().width("30")

                // 右侧 - 解锁按钮
                Button(this.isLoading ? $r('app.string.loading_message') : $r('app.string.Password_unlock_title'))
                  .layoutWeight(1)
                  .height(40)
                  .fontSize(16)
                  .fontColor($r('app.color.button_text'))
                  .borderRadius(20)
                  .enabled(this.buttonEnabled)
                  .backgroundColor(this.buttonEnabled ? $r("app.color.button_bg_blue") : $r("app.color.button_bg_disabled"))
                  .id('btn_unlock')
                  .onClick(() => {
                    this.verifyAndOpenDatabase();
                  })
              }
              .width('100%')
              .height(60)
              .backgroundColor(Color.Transparent)
              .padding({
                top: 8,
                bottom: 8,
                left: 16,
                right: 16
              })
            }
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
      }
      .width('100%')
      .height('100%')
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
        .id('btn_select_key_file')
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
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 24 })
  }
}
