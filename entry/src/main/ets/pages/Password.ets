import { PromptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ErrorEvent } from '@ohos.worker';

import { AuthType, AuthTypeInfo, CredentialsParam, DbFileParam, RecentFile } from '../services/TypeDefined';
import { RecentFilesService } from '../services/RecentFilesService';
import { StorageConfig, StorageType } from '../storage';
import { BusinessError } from '@kit.BasicServicesKit';
import { FileService } from '../services/FileService';
import { LoadDatabase } from '../workers/DatabaseLoadWorkerParam';
import { CommonUtils, ConfigDecryptError, CryptoUtils, KdbxUtils, NavigationManager, ResourceManager, WindowUtils } from '../common/utils';
import { ByteUtils, Kdbx } from 'kdbxweb';
import { LoadingDialog } from '../components/loading/LoadingDialogUtils';
import { LoadMessage, SuccessMessage } from '../workers/WorkerParam';
import { ToastLoadDatabaseCallback } from '../workers/callback/ToastLoadDatabaseCallback';
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
import { OtpAuxFileService } from '../services/otpkey/OtpAuxFileService';
import { OtpDerivedSecret, OtpKeyProvService } from '../services/otpkey/OtpKeyProvService';
import { OtpInfo } from '../services/otpkey/OtpInfo';
import { AutoOpenCoordinator } from '../services/autoopen/AutoOpenCoordinator';
import { AutoOpenEntryService } from '../services/autoopen/AutoOpenEntryService';
import { DeviceIdentity } from '../services/autoopen/DeviceIdentity';
import { DatabaseRegistry } from '../services/kdbx/DatabaseRegistry';
import KdbxSaveService from '../services/kdbx/KdbxSaveService';
import { ToastSaveDatabaseCallback } from '../workers/callback/ToastSaveDatabaseCallback';
import { EncodingUtil, OtpDataFmt } from '../services/otpkey/EncodingUtil';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import { fileIo } from '@kit.CoreFileKit';
import {
  KdbxHeaderInfo,
  KdbxHeaderParseError,
  KdbxHeaderParseErrorCode,
  KdbxHeaderReader
} from '../services/kdbx/KdbxHeaderReader';
import { YubiKeySlot } from '../services/otpkey/YubiKeyNfcService';
import { NfcChallengeDialog } from '../components/yubikey/NfcChallengeDialog';

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
  @State showCacheCheckbox: boolean = false; // 是否显示缓存复选框
  @State onlyUseCache: boolean = false; // 是否仅使用本地缓存
  private filePath: string = '';
  private storageType: StorageType | undefined = undefined;
  private storageConfig: StorageConfig | undefined = undefined;
  // 添加模式（切换面板「打开其他数据库」中继）：解锁成功后保留多库注册表，仅追加新库
  private openAddMode: boolean = false;
  // 子库管理页「选择文件」中继：解锁成功后把该库登记为指定父库的子库（AutoOpen 条目）
  private addChildParentIocKey: string = '';
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
  // ===== OTP（OtpKeyProv）解锁状态 =====
  // 辅助文件解析结果（password_otp 模式）
  @State otpInfo: OtpInfo | undefined = undefined;
  // OTP 码输入（与 OtpsRequired 等长）
  @State otpCodes: string[] = [];
  // 辅助文件加载状态：idle | loading | ready | missing
  @State otpAuxState: string = 'idle';
  // 恢复模式：secret 输入与编码格式
  @State recoverySecret: string = '';
  @State recoveryFmtIndex: number = 0;
  // 辅助文件实际位置（同目录推导或手动选择）
  private auxLocation: LocationInfo | undefined = undefined;
  // 本次解锁派生结果（解锁成功后写回 Counter）
  private pendingDerived: OtpDerivedSecret | undefined = undefined;
  // v2 OTP Counter 已在加载前写回辅助文件（解锁成功后跳过二次写回，防双倍前进）
  private otpCounterWrittenBack: boolean = false;
  // 恢复模式编码格式下拉选项
  private formatOptions: SelectOption[] = [];
  // ===== 挑战-应答（YubiKey NFC + KeePassXC）解锁状态 =====
  // YubiKey HMAC 挑战槽位（默认槽位 2：出厂 OTP 占用槽位 1）
  @State yubikeySlot: YubiKeySlot = YubiKeySlot.SLOT_2;
  // 槽位下拉选项
  private yubikeySlotOptions: SelectOption[] = [
    { value: $r('app.string.yubikey_slot_1') },
    { value: $r('app.string.yubikey_slot_2') }
  ];
  // NFC 贴卡弹层控制器（阶段二，运行时按挑战值创建）
  private nfcChallengeController: CustomDialogController | null = null;
  // 本次解锁派生的 OTP/恢复 secret（hex）：解锁成功后随 DbFileParam 保存链路重建凭证用（内存态，不持久化）
  private otpSecretHex: string | undefined = undefined;
  // 本次解锁的 YubiKey 挑战应答（hex）：解锁成功后随 DbFileParam 供容器还原/远端重载重建凭证（seed 未变前有效）
  private challengeResponseHex: string | undefined = undefined;

  aboutToAppear() {
    //初始化认证方式
    this.setAuthType(this.authTypeInfo);

    // 初始化恢复模式编码格式下拉选项
    for (const fmt of EncodingUtil.FORMATS) {
      this.formatOptions.push({ value: fmt });
    }

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
    // 添加模式（切换面板「打开其他数据库」中继）：解锁成功后不清多库注册表
    this.openAddMode = params !== undefined && params.openMode === 'add';
    // 子库管理页「选择文件」中继：解锁成功后把该库登记为指定父库的子库
    this.addChildParentIocKey = params !== undefined && params.addChildParent ? params.addChildParent : '';
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
    // 恢复 OTP 辅助文件位置记忆（手动选择过则免重新定位）
    this.auxLocation = recentFile.otpAuxLocation;
    // 设置认证类型
    if (recentFile.authType) {
      this.setAuthType(recentFile.authType);
      this.onAuthTypeChanged();
    }
    // 恢复 YubiKey 挑战槽位记忆
    if (recentFile.yubikeySlot === YubiKeySlot.SLOT_1) {
      this.yubikeySlot = YubiKeySlot.SLOT_1;
    } else {
      this.yubikeySlot = YubiKeySlot.SLOT_2;
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

    // OTP 模式（含恢复模式）：需要密码 + OTP 因子
    if (AuthType.useOtpAuth(this.authTypeInfo)) {
      if (this.isLoading || this.password.length === 0) {
        this.buttonEnabled = false;
        return;
      }
      if (AuthType.isRecoveryMode(this.authTypeInfo)) {
        this.buttonEnabled = this.recoverySecret.length > 0;
        return;
      }
      if (!this.otpInfo || this.otpAuxState !== 'ready' || !this.areOtpCodesComplete()) {
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
   * 认证方式切换钩子：加载/重置 OTP 区块状态
   */
  private onAuthTypeChanged(): void {
    this.pendingDerived = undefined;
    this.otpCounterWrittenBack = false;
    // 清理上次尝试的派生 secret / 挑战应答（防止换认证方式后残留随 DbFileParam 带出）
    this.otpSecretHex = undefined;
    this.challengeResponseHex = undefined;
    if (AuthType.useOtpAuth(this.authTypeInfo) && !AuthType.isRecoveryMode(this.authTypeInfo) && !this.otpInfo) {
      // 优先使用记忆的辅助文件位置，其次同目录自动定位
      this.loadAuxFile(this.auxLocation);
    }
    this.updateButtonState();
  }

  /**
   * OTP 码是否全部输入完整（长度对齐辅助文件 OtpLength）
   */
  private areOtpCodesComplete(): boolean {
    const info = this.otpInfo;
    if (!info || this.otpAuxState !== 'ready') {
      return false;
    }
    if (this.otpCodes.length < info.otpsRequired) {
      return false;
    }
    const needLength = info.otpLength > 0 ? info.otpLength : 1;
    for (let i = 0; i < info.otpsRequired; i++) {
      if ((this.otpCodes[i] ?? '').length < needLength) {
        return false;
      }
    }
    return true;
  }

  /**
   * 构造与数据库同目录的辅助文件位置（自动推导）
   */
  private buildAutoAuxLocation(): LocationInfo | undefined {
    if (!this.filePath || this.storageType === undefined) {
      return undefined;
    }
    const loc: LocationInfo = {
      mode: LocationMode.SELECT,
      filePath: OtpAuxFileService.buildAuxFilePath(this.filePath),
      fileName: OtpKeyProvService.buildAuxFileName(this.fileName),
      storageType: this.storageType,
      storageConfig: this.storageConfig ?? {}
    };
    return loc;
  }

  /**
   * 加载 OTP 辅助文件并解析（自动定位失败时 UI 引导手动选择）
   */
  private loadAuxFile(target?: LocationInfo): void {
    const loc = target ?? this.buildAutoAuxLocation();
    if (!loc) {
      this.otpAuxState = 'missing';
      this.updateButtonState();
      return;
    }
    this.otpAuxState = 'loading';
    this.updateButtonState();
    OtpAuxFileService.loadOtpInfo(loc).then((info: OtpInfo) => {
      this.auxLocation = loc;
      this.otpInfo = info;
      this.otpCodes = [];
      for (let i = 0; i < info.otpsRequired; i++) {
        this.otpCodes.push('');
      }
      this.otpAuxState = 'ready';
      this.updateButtonState();
    }).catch((error: Error) => {
      hilog.warn(DOMAIN, TAG, 'Load otp aux file failed: %{public}s', error.message);
      this.otpInfo = undefined;
      this.otpAuxState = 'missing';
      this.updateButtonState();
    });
  }

  /**
   * 手动选择 OTP 辅助文件（本地存储无同目录读权限时的兜底路径）
   */
  private selectAuxFile(): void {
    // 保留已输入内容（密码/OTP 码）
    this.shouldPreservePassword = true;
    LocationParam.ofSelect(['xml'], (locationInfo: LocationInfo) => {
      this.shouldStartAuth = false;
      this.loadAuxFile(locationInfo);
      this.navigateBack();
    });
    if (this.workingNavPathStack) {
      this.workingNavPathStack.pushPathByName('SelectLocation', null);
    } else {
      hilog.error(DOMAIN, TAG, 'selectAuxFile: NavPathStack is null!');
    }
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
            // OTP/恢复模式：生物识别仅代填密码分量，OTP 因子仍需手动输入（不自动提交）
            // XC 挑战-应答：同理仅代填密码，由用户按解锁键触发 NFC 贴卡（避免自动弹出读卡弹层）
            if (AuthType.useOtpAuth(this.authTypeInfo) || AuthType.useChallengeResponseXc(this.authTypeInfo)) {
              this.updateButtonState();
              return;
            }
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
    this.recoverySecret = '';
    // 派生 secret 属敏感材料，随页面状态清理（otpCodes 为短时效 OTP 码，保留以改善输入体验）
    this.pendingDerived = undefined;
    this.otpCounterWrittenBack = false;
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
    LoadingDialog.showLoading(ResourceManager.getString($r('app.string.loading_message')));
  }

  /**
   * 管理进度弹框
   */
  private closeLoadingDialog() {
    this.isLoading = false;
    this.updateButtonState(); // 更新按钮状态
    LoadingDialog.hideLoading();
  }

  /**
   * 存储配置解密失败引导：弹框确认后跳转对应存储的连接配置页，
   * 用户重新填写连接信息并再次选中该文件后，最近记录会被新配置覆盖（见 DataService.toPasswordPage）
   */
  private showReEditConfigGuide(storageType: StorageType, filePath: string): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.dialog_prompt_title'),
      message: $r('app.string.storage_config_decrypt_failed'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.re_edit_connection_config'),
        action: () => {
          DataService.reEditStorageConfig(storageType, filePath);
        }
      }
    });
  }

  /**
   * 验证密码并打开数据库
   */
  private verifyAndOpenDatabase() {
    // OTP 认证（含恢复模式）：密码 + OTP 因子校验后走独立派生路径
    if (AuthType.useOtpAuth(this.authTypeInfo)) {
      this.verifyAndOpenDatabaseWithOtp();
      return;
    }

    // 挑战-应答（KeePassXC + YubiKey NFC）：校验后进入两阶段贴卡流程
    if (AuthType.useChallengeResponseXc(this.authTypeInfo)) {
      this.verifyAndOpenDatabaseWithChallengeResponse();
      return;
    }

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
    const loadDatabase = new LoadDatabase(this.filePath, this.fileName, this.password, this.authTypeInfo, this.keyLocation, this.storageType, this.storageConfig);
    this.startLoadDatabase(loadDatabase);
  }

  /**
   * OTP 认证（含恢复模式）校验 + 派生 secret + 打开数据库：
   * 密码 + OTP 码（或恢复 secret）→ 主线程派生 otpSecretHex → 交 Worker 构建 customKey
   */
  private verifyAndOpenDatabaseWithOtp(): void {
    if (this.isLoading) {
      return;
    }
    if (!this.password) {
      CommonUtils.showToast({ message: $r('app.string.password_placeholder'), duration: 2000 });
      return;
    }
    if (AuthType.isRecoveryMode(this.authTypeInfo)) {
      if (!this.recoverySecret) {
        CommonUtils.showToast({ message: $r('app.string.otp_recovery_secret_placeholder'), duration: 2000 });
        return;
      }
    } else {
      if (!this.otpInfo || this.otpAuxState !== 'ready') {
        CommonUtils.showToast({ message: $r('app.string.otp_aux_file_missing'), duration: 2000 });
        return;
      }
      if (!this.areOtpCodesComplete()) {
        CommonUtils.showToast({ message: $r('app.string.otp_input_incomplete'), duration: 2000 });
        return;
      }
    }
    if (this.storageType === null) {
      CommonUtils.showToast({ message: $r('app.string.storage_type_empty') });
      return;
    }

    // 打开加载进度弹框（派生与加载共用）
    this.openLoadingDialog();
    this.buildOtpLoadDatabase().then((loadDatabase: LoadDatabase) => {
      this.startLoadDatabase(loadDatabase);
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'OTP derive secret failed: %{public}s', error.message);
      this.closeLoadingDialog();
      CommonUtils.showToast({ message: $r('app.string.otp_key_error'), duration: 3000 });
    });
  }

  /**
   * 构建 OTP 加载参数：恢复模式直接按编码格式解析；OTP 码模式经 KeyFromOtps 派生
   */
  private async buildOtpLoadDatabase(): Promise<LoadDatabase> {
    let secretHex = '';
    if (AuthType.isRecoveryMode(this.authTypeInfo)) {
      const fmt = EncodingUtil.getOtpDataFormat(EncodingUtil.FORMATS[this.recoveryFmtIndex]) ?? OtpDataFmt.Hex;
      const secret = OtpKeyProvService.deriveSecretFromRecoveryInput(this.recoverySecret, fmt);
      secretHex = ByteUtils.bytesToHex(secret);
      // 恢复模式无 Counter 写回
      this.pendingDerived = undefined;
    } else {
      const info = this.otpInfo;
      if (!info) {
        throw new Error('otp aux file not loaded');
      }
      const otps: string[] = [];
      for (let i = 0; i < info.otpsRequired; i++) {
        otps.push(this.otpCodes[i] ?? '');
      }
      const derived = await OtpKeyProvService.deriveSecretFromOtps(info, otps);
      this.pendingDerived = derived;
      secretHex = derived.secretHex;
      // v2 派生命中即 PlainTextHash 校验通过：加载前写回 Counter（对齐 KP2A
      // SaveOtpAuxFileAndLoadDb 先写后加载时序），避免令牌前进而文件未动导致 OTP 锁死
      if (derived.verified) {
        await this.advanceOtpCounterBeforeLoad();
      }
    }
    // 暂存派生 secret：解锁成功后 setFileParam 随 DbFileParam 带入保存链路
    this.otpSecretHex = secretHex;
    const loadDatabase = new LoadDatabase(this.filePath, this.fileName, this.password, this.authTypeInfo,
      this.keyLocation, this.storageType, this.storageConfig);
    loadDatabase.otpSecretHex = secretHex;
    return loadDatabase;
  }

  /**
   * 挑战-应答（KeePassXC + YubiKey NFC）解锁，两阶段流程：
   * 阶段一（主线程）：读库文件 → KdbxHeaderReader 预解析 → 提取挑战值（KDF seed 原文）
   * 阶段二（贴卡弹层 → Worker）：YubiKey NFC HMAC-SHA1 应答 → challengeResponseHex 固定应答加载
   */
  private verifyAndOpenDatabaseWithChallengeResponse(): void {
    if (this.isLoading) {
      return;
    }
    if (!this.password) {
      CommonUtils.showToast({ message: $r('app.string.password_placeholder'), duration: 2000 });
      return;
    }
    if (AuthType.useKeyAuth(this.authTypeInfo) && !this.keyLocation) {
      CommonUtils.showToast({ message: $r('app.string.select_key_file'), duration: 2000 });
      return;
    }
    if (this.storageType === null) {
      CommonUtils.showToast({ message: $r('app.string.storage_type_empty') });
      return;
    }
    this.openLoadingDialog();
    this.readChallengeSeed()
      .then((seed: number[]) => {
        this.closeLoadingDialog();
        this.showNfcChallengeDialog(seed);
      })
      .catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Challenge phase-1 (header pre-parse) failed: %{public}s', error.message);
        this.closeLoadingDialog();
        CommonUtils.showToast({ message: this.challengePhaseOneErrorText(error), duration: 3000 });
      });
  }

  /**
   * 阶段一：下载库文件到临时路径并预解析 KDBX 头，返回挑战值（KDF seed）字节。
   * 走 readToFile 而非整读：缓存装饰器回填缓存与版本元数据后，
   * 阶段二 Worker 加载命中同一缓存版本，避免远端文件被二次下载
   */
  private async readChallengeSeed(): Promise<number[]> {
    const manager = new KdbxFileManager(this.storageType, this.storageConfig);
    const tempPath: string = CommonUtils.getCacheDir() + '/xc_seed_' + Date.now() + '.tmp';
    try {
      await manager.readToFile(this.filePath, tempPath);
      const headerInfo: KdbxHeaderInfo = await KdbxHeaderReader.readHeaderFromFile(tempPath);
      const seedBytes = new Uint8Array(headerInfo.kdfSeed);
      const seed: number[] = [];
      for (let i = 0; i < seedBytes.length; i++) {
        seed.push(seedBytes[i]);
      }
      return seed;
    } finally {
      try {
        await fileIo.unlink(tempPath);
      } catch (e) {
        // 临时文件清理失败可忽略
      }
    }
  }

  /**
   * 阶段一错误 → 提示文案（KDBX3 / 头损坏 / 读失败分类）
   */
  private challengePhaseOneErrorText(error: Error): ResourceStr {
    if (error instanceof KdbxHeaderParseError) {
      if (error.code === KdbxHeaderParseErrorCode.KDBX3_NOT_SUPPORTED) {
        return $r('app.string.challenge_response_kdbx3_unsupported');
      }
      return $r('app.string.challenge_response_header_invalid');
    }
    return $r('app.string.challenge_response_read_failed');
  }

  /**
   * 弹出 YubiKey NFC 贴卡弹层（阶段二）
   */
  private showNfcChallengeDialog(seed: number[]): void {
    this.nfcChallengeController = new CustomDialogController({
      builder: NfcChallengeDialog({
        challenge: seed,
        slot: this.yubikeySlot,
        onChallengeResponse: (responseHex: string) => {
          this.handleChallengeResponse(responseHex);
        },
        onCancel: () => {
          this.nfcChallengeController = null;
        }
      }),
      alignment: DialogAlignment.Center,
      customStyle: true,
      autoCancel: false
    });
    this.nfcChallengeController.open();
  }

  /**
   * 阶段二完成：携带 YubiKey HMAC 应答进入 Worker 加载
   */
  private handleChallengeResponse(responseHex: string): void {
    this.nfcChallengeController = null;
    // 暂存应答：解锁成功后 setFileParam 随 DbFileParam 带入（容器还原/远端重载重建凭证）
    this.challengeResponseHex = responseHex;
    const loadDatabase = new LoadDatabase(this.filePath, this.fileName, this.password, this.authTypeInfo,
      this.keyLocation, this.storageType, this.storageConfig);
    loadDatabase.challengeResponseHex = responseHex;
    this.openLoadingDialog();
    this.startLoadDatabase(loadDatabase);
  }

  /**
   * 统一启动数据库加载（进度 HUD/吐司由 ToastLoadDatabaseCallback 默认行为驱动）
   */
  private startLoadDatabase(loadDatabase: LoadDatabase): void {
    KdbxLoadService.loadDatabase(loadDatabase, ToastLoadDatabaseCallback.wrap({
      onSuccessMessage: (message: SuccessMessage) => {
        this.handleSuccessMessage(message);
      },
      onErrorMessage: (message: LoadMessage) => {
        this.closeLoadingDialog();
        // 存储配置解密失败（Worker 抛出的 ConfigDecryptError 以资源名回传）：
        // 弹框引导重新编辑连接配置（简短吐司已由 ToastLoadDatabaseCallback 默认行为展示）
        if (this.storageType !== undefined && ConfigDecryptError.isDecryptFailedMessage(message.message)) {
          this.showReEditConfigGuide(this.storageType, this.filePath);
        }
      },
      onAllErrors: (error: ErrorEvent) => {
        this.closeLoadingDialog();
      },
      onexit: (e: number) => {
        this.closeLoadingDialog();
      }
    }));
  }

  /**
   * 处理数据库加载完成事件
   * @param data
   */
  private handleSuccessMessage(successMessage: SuccessMessage) {
    if (this.openAddMode) {
      // 添加模式：保留多库注册表（不清已打开的库），仅复位 KdbxUtils IO 缓存
      KdbxUtils.init();
    } else {
      this.init();
    }
    this.putFileToRecentFile(successMessage);
    // OTP 解锁成功：Counter 写回辅助文件（失败仅告警，见 writeBackOtpCounter）
    this.writeBackOtpCounter();
    this.setFileParam(successMessage).then(() => {
      // 子库管理页「选择文件」回环：把刚解锁的库登记为发起页指定父库的子库，
      // 生成 AutoOpen 条目并恢复父库为当前库（随后静默保存父库）
      if (this.openAddMode && this.addChildParentIocKey.length > 0) {
        this.completeAddChildFromOpened();
      }
      LoadingDialog.showLoading(ResourceManager.getString($r('app.string.open_success')));
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
      // 子数据库：父库解锁成功后后台扫描并串行打开 AutoOpen 子库（不抢当前库）；
      // 子数据库功能禁用时跳过（不自动打开）
      if (SettingsService.isChildDbEnable()) {
        const parentIocKey: string = DatabaseRegistry.buildIocKey(
          this.storageType ?? StorageType.LOCAL, this.filePath);
        AutoOpenCoordinator.getInstance().onParentUnlocked(parentIocKey);
      }
    }).catch((error: Error) => {
      hilog.error(DOMAIN, TAG, 'Database open failed: %{public}s', error.message);
      CommonUtils.showToast({ message: error.message, duration: 3000 });
      this.closeLoadingDialog();
    });
  }

  /**
   * 子库管理页「选择文件」回环收尾：刚解锁的库已入注册表（当前库），
   * 在指定父库生成 AutoOpen 条目 → 恢复父库为当前库 → 静默保存父库。
   * M6：本地/远端子库均支持——本地条目 URL 写 {DB_DIR} 相对化路径，
   * 远端条目 URL 写 scheme URL 并追加 IocUserName/IocPassword 连接凭据
   * （OAuth 云盘仅写 URL，令牌留设备本地）；失败仅提示，
   * 子库保持已打开状态（可稍后在管理页手动补建条目）。
   */
  private completeAddChildFromOpened(): void {
    const registry: DatabaseRegistry = FileService.getRegistry();
    const parentIocKey: string = this.addChildParentIocKey;
    this.addChildParentIocKey = '';
    const parentParam: DbFileParam | undefined = registry.get(parentIocKey);
    const childParam: DbFileParam | undefined = registry.getCurrent();
    if (parentParam === undefined || !parentParam.database
      || childParam === undefined || !childParam.database) {
      hilog.warn(DOMAIN, TAG, 'add child from opened skipped: parent or child missing');
      return;
    }
    const entry = AutoOpenEntryService.addEntryForOpenedChild(parentParam.database,
      parentParam.filePath, childParam, DeviceIdentity.getDeviceId());
    if (entry === undefined) {
      CommonUtils.showToast({ message: $r('app.string.child_dbs_add_failed'), duration: 2000 });
      return;
    }
    // 恢复父库为当前库（DatabaseView 落在父库视图）
    registry.setCurrent(parentIocKey);
    // 静默保存父库（子库条目落盘），终态吐司由回调包装器给出
    KdbxSaveService.saveDatabaseFromUi(ToastSaveDatabaseCallback.wrap({
      onSuccess: () => {
        EventBus.emit<void>(EventBus.DATABASE_UPDATE);
      },
      onError: (error: string) => {
        hilog.error(DOMAIN, TAG, 'save parent after add child failed: %{public}s', error);
      }
    }));
  }

  /**
   * v2（verified）加载前写回 Counter（对齐 KP2A SaveOtpAuxFileAndLoadDb 先写后加载时序）：
   * Counter += delta → 新 Counter 重新加密 secret → 写回辅助文件。
   * 令牌已前进（OTP 码被消耗），文件必须同步前进，否则重试时旧码全部失效导致 OTP 锁死；
   * 写盘失败不阻断加载——解锁成功后 writeBackOtpCounter 仅重试写盘（不再前进，防双倍消耗）
   */
  private async advanceOtpCounterBeforeLoad(): Promise<void> {
    this.otpCounterWrittenBack = false;
    const derived = this.pendingDerived;
    const info = this.otpInfo;
    const loc = this.auxLocation;
    if (!derived || !info || !loc) {
      return;
    }
    try {
      await OtpAuxFileService.saveAfterUnlock(info, derived.secret, derived.counterDelta, loc);
      this.otpCounterWrittenBack = true;
      hilog.info(DOMAIN, TAG, 'Otp counter pre-load write-back success');
    } catch (error) {
      const err = error as BusinessError;
      hilog.warn(DOMAIN, TAG, 'Otp counter pre-load write-back failed: %{public}s', err.message);
      CommonUtils.showToast({ message: $r('app.string.otp_counter_save_failed'), duration: 3000 });
    }
  }

  /**
   * OTP 解锁成功后写回 Counter：
   * - v2（verified）：加载前已写回（advanceOtpCounterBeforeLoad）——已落盘则跳过，
   *   曾失败则仅重试写盘（内存 Counter/密文已前进，不得再次前进，防双倍消耗）；
   * - v1：派生无校验，解锁成功才证明 secret 正确，此处首次前进并写回；
   * fire-and-forget，写回失败仅告警不阻断（远端存储可能只读）
   */
  private writeBackOtpCounter(): void {
    const derived = this.pendingDerived;
    const info = this.otpInfo;
    const loc = this.auxLocation;
    // 恢复模式/未派生：无写回
    if (!derived || !info || !loc || AuthType.isRecoveryMode(this.authTypeInfo)) {
      return;
    }
    if (derived.verified) {
      if (this.otpCounterWrittenBack) {
        return;
      }
      // 内存 Counter 已前进：重新加密（幂等）+ 重试写盘，不再次前进
      OtpKeyProvService.encryptOtpInfoSecret(info, derived.secret)
        .then(() => OtpAuxFileService.writeOtpInfo(info, loc))
        .then(() => {
          this.otpCounterWrittenBack = true;
          hilog.info(DOMAIN, TAG, 'Otp counter write-back retry success');
        })
        .catch((error: Error) => {
          hilog.error(DOMAIN, TAG, 'Otp counter write-back retry failed: %{public}s', error.message);
          CommonUtils.showToast({ message: $r('app.string.otp_counter_save_failed'), duration: 3000 });
        });
      return;
    }
    // v1：解锁成功后首次前进（对齐 KP2A v1 成功后写回路径）
    OtpAuxFileService.saveAfterUnlock(info, derived.secret, derived.counterDelta, loc)
      .then(() => {
        hilog.info(DOMAIN, TAG, 'Otp counter write-back success');
      })
      .catch((error: Error) => {
        hilog.error(DOMAIN, TAG, 'Otp counter write-back failed: %{public}s', error.message);
        CommonUtils.showToast({ message: $r('app.string.otp_counter_save_failed'), duration: 3000 });
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
    // 派生 secret / 挑战应答随凭证参数传入：容器还原（m0Path）重建凭证依赖（缺省时策略抛错，
    // 大库 Worker 加载路径在最后一步失败）；secret 仅存内存 DbFileParam，不持久化
    return KdbxUtils.successMessageToKdbx(successMessage, {
      password: this.password,
      authType: this.authTypeInfo,
      keyLocation: this.keyLocation,
      otpSecretHex: this.otpSecretHex,
      challengeResponseHex: this.challengeResponseHex
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
        otpSecretHex: this.otpSecretHex, // OTP/恢复 secret：保存/重载链路重建凭证
        challengeResponseHex: this.challengeResponseHex, // 挑战应答：远端重载重建凭证（seed 未变前有效）
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
      // 挑战-应答槽位记忆（仅 XC 挑战-应答认证持久化）
      yubikeySlot: AuthType.useChallengeResponseXc(this.authTypeInfo) ? this.yubikeySlot : undefined,
      // OTP 辅助文件位置记忆（仅 OTP 认证持久化，含自动定位结果）
      otpAuxLocation: AuthType.useOtpAuth(this.authTypeInfo) ? this.auxLocation : undefined,
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
                    this.onAuthTypeChanged();
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

              // YubiKey 槽位选择（KeePassXC 挑战-应答）
              if (AuthType.useChallengeResponseXc(this.authTypeInfo)) {
                this.YubiKeySlotSelector()
              }

              // OTP 输入区（密码 + OTP：OtpsRequired 个码）
              if (AuthType.useOtpAuth(this.authTypeInfo) && !AuthType.isRecoveryMode(this.authTypeInfo)) {
                this.OtpInputArea()
              }

              // OTP 恢复模式区（令牌丢失时直接输入 secret）
              if (AuthType.useOtpAuth(this.authTypeInfo) && AuthType.isRecoveryMode(this.authTypeInfo)) {
                this.OtpRecoveryArea()
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

  /**
   * OTP 输入区：辅助文件加载状态 + OtpsRequired 个 OTP 码输入框
   */
  @Builder
  OtpInputArea() {
    Column() {
      Text($r('app.string.otp_inputs_title'))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 16 })
        .alignSelf(ItemAlign.Start)

      if (this.otpAuxState === 'loading') {
        Text($r('app.string.otp_aux_file_loading'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .alignSelf(ItemAlign.Start)
      } else if (this.otpAuxState !== 'ready' || !this.otpInfo) {
        // 辅助文件缺失/不可读：引导手动选择
        Text($r('app.string.otp_aux_file_missing'))
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 12 })
          .alignSelf(ItemAlign.Start)

        Button($r('app.string.otp_select_aux_file'))
          .width('100%')
          .height(44)
          .fontSize(16)
          .fontColor($r('app.color.button_text'))
          .backgroundColor($r("app.color.button_bg_blue"))
          .id('btn_select_otp_aux_file')
          .onClick(() => {
            this.selectAuxFile();
          })
      } else {
        // 辅助文件名提示
        Text(this.auxLocation?.fileName ?? '')
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .margin({ bottom: 12 })
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .alignSelf(ItemAlign.Start)

        Row({ space: 8 }) {
          ForEach(this.otpCodes, (code: string, index: number) => {
            TextInput({ text: code, placeholder: $r('app.string.otp_input_hint', index + 1) })
              .id('input_otp_' + index)
              .type(InputType.Number)
              .maxLength(this.otpInfo?.otpLength ?? 8)
              .placeholderColor($r('app.color.text_secondary'))
              .placeholderFont({ size: 14 })
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))
              .textAlign(TextAlign.Center)
              .height(44)
              .layoutWeight(1)
              .backgroundColor(Color.Transparent)
              .border({
                width: { bottom: 1 },
                color: $r('app.color.divider')
              })
              .onChange((value: string) => {
                this.otpCodes[index] = value;
                this.updateButtonState();
              })
              .onSubmit(() => {
                this.verifyAndOpenDatabase();
              })
          }, (code: string, index: number) => index.toString() + '_' + code.length.toString())
        }
        .width('100%')
        .alignItems(VerticalAlign.Center)
      }
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 24 })
  }

  /**
   * OTP 恢复模式区：secret 输入 + 编码格式选择（Hex/Base64/UTF-8/Dec/Base32）
   */
  @Builder
  OtpRecoveryArea() {
    Column() {
      Text($r('app.string.otp_recovery_hint'))
        .fontSize(14)
        .fontColor($r('app.color.text_secondary'))
        .margin({ bottom: 12 })
        .alignSelf(ItemAlign.Start)

      TextInput({ placeholder: $r('app.string.otp_recovery_secret_placeholder') })
        .id('input_otp_recovery_secret')
        .placeholderColor($r('app.color.text_secondary'))
        .placeholderFont({ size: 16 })
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .width('100%')
        .height(48)
        .backgroundColor(Color.Transparent)
        .onChange((value: string) => {
          this.recoverySecret = value;
          this.updateButtonState();
        })
        .onSubmit(() => {
          this.verifyAndOpenDatabase();
        })

      Text($r('app.string.otp_secret_format'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16, bottom: 8 })
        .alignSelf(ItemAlign.Start)

      Select(this.formatOptions)
        .selected(this.recoveryFmtIndex)
        .value(EncodingUtil.FORMATS[this.recoveryFmtIndex])
        .font({ size: 16 })
        .fontColor($r('app.color.text_primary'))
        .selectedOptionFont({ size: 16 })
        .optionFont({ size: 16 })
        .id('select_otp_recovery_format')
        .width('100%')
        .onSelect((index: number, value: string) => {
          this.recoveryFmtIndex = index;
        })
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 24 })
  }

  /**
   * YubiKey 槽位选择区（KeePassXC 挑战-应答：槽位与 KeePassXC 中配置的 HMAC 槽位一致）
   */
  @Builder
  YubiKeySlotSelector() {
    Column() {
      Text($r('app.string.yubikey_slot_title'))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .margin({ bottom: 16 })
        .alignSelf(ItemAlign.Start)

      Select(this.yubikeySlotOptions)
        .selected(this.yubikeySlot === YubiKeySlot.SLOT_1 ? 0 : 1)
        .value(this.yubikeySlot === YubiKeySlot.SLOT_1
          ? ResourceManager.getString($r('app.string.yubikey_slot_1'))
          : ResourceManager.getString($r('app.string.yubikey_slot_2')))
        .font({ size: 16 })
        .fontColor($r('app.color.text_primary'))
        .selectedOptionFont({ size: 16 })
        .optionFont({ size: 16 })
        .id('select_yubikey_slot')
        .width('100%')
        .onSelect((index: number, value: string) => {
          this.yubikeySlot = index === 0 ? YubiKeySlot.SLOT_1 : YubiKeySlot.SLOT_2;
        })

      Text($r('app.string.yubikey_slot_hint'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
        .margin({ top: 8 })
        .alignSelf(ItemAlign.Start)
    }
    .width('100%')
    .padding({ left: 16, right: 16, bottom: 24 })
  }
}
