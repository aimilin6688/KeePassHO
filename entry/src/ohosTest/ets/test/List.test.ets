import ActsAbilityTest from './ActsAbility.test';
import KdbxErrorTest from './kdbx/error/KdbxError.test';
import WebDavTest from './storage/webdav/WebDav.test';
import TotpServiceTest from './services/TotpService.test';
import FileUtilsTest from './utils/FileUtils.test';
import RecentFilesServiceTest from './services/RecentFilesService.test';
import DistributedKVServiceTest from './store/DistributedKVService.test';
import SyncSettingsServiceTest from './store/SyncSettingsService.test';
import OtpCompatibilityManagerTest from './services/otp/OtpCompatibilityManager.test';
import OtpUrlParserTest from './services/otp/parsers/OtpUrlParser.test';
import KeePass2ParserTest from './services/otp/parsers/KeePass2Parser.test';
import KeeOtpParserTest from './services/otp/parsers/KeeOtpParser.test';
import KeeTrayTotpParserTest from './services/otp/parsers/KeeTrayTotpParser.test';

import S3ClientTest from './storage/s3/S3Client.test';
import S3ClientMultipartTest from './storage/s3/S3ClientMultipart.test';
import S3SignatureV4Test from './storage/s3/S3SignatureV4.test';
import S3StorageTest from './storage/s3/S3Storage.test';
import S3XmlParserTest from './storage/s3/S3XmlParser.test';
// S3 真实集成测试（20MB 分块上传/下载，需真实 S3/MinIO 环境，勿与单元测试混跑）
import S3StorageIntegrationTest from './storage/s3/S3StorageIntegration.test';

import PCloudClientTest from './storage/pcloud/PCloudClient.test';
import PCloudConfigTest from './storage/pcloud/PCloudConfig.test';
import PCloudOAuth2ProviderTest from './storage/pcloud/PCloudOAuth2Provider.test';
import PCloudStorageTest from './storage/pcloud/PCloudStorage.test';

import HuaweiDriveStorageTest from './storage/huawei/HuaweiDriveStorage.test';
import HuaweiDriveClientTest from './storage/huawei/HuaweiDriveClient.test';
import DownloadProgressAggregatorTest from './storage/huawei/DownloadProgressAggregator.test';
import SFTPHandlerTest from './storage/sftp/SFTPHandler.test';
import SFTPStorageSemanticsTest from './storage/sftp/SFTPStorageSemantics.test';
import SFTPStorageRealFileTest from './storage/sftp/SFTPStorageRealFile.test';

// 数据库加载/保存双模式单元测试（同步模式 / Worker 异步模式）
import DatabaseSyncModeTest from './workers/DatabaseSyncMode.test';
import DatabaseWorkerModeTest from './workers/DatabaseWorkerMode.test';
// Worker 常驻池化（#3）：缓存策略随任务注入与忙拒绝
import WorkerPoolPolicyTest from './workers/WorkerPoolPolicy.test';
import LoadWorkerPrewarmTest from './workers/LoadWorkerPrewarm.test';
// S6 保存管道流式路径专项（ChaCha20 v4 → saveToFile + writeFromFile，对照 AES 回退）
import DatabaseSaveStreamingTest from './workers/DatabaseSaveStreaming.test';
import DatabaseSaveFastPathTest from './workers/DatabaseSaveFastPath.test';
import StreamingXmlParserTest from './workers/StreamingXmlParser.test';
import WorkerEnvironmentInjectionTest from './workers/WorkerEnvironmentInjection.test';
// 传输进度条（双向）：限频器 / 进度消息 / 基类分发
import ProgressThrottlerTest from './workers/ProgressThrottler.test';
import ProgressMessageTest from './workers/ProgressMessage.test';
import ProgressDispatchTest from './workers/ProgressDispatch.test';
// 保存错误明细展示链路测试（LoadMessage.detail / toErrorMessage / postErrorMessage 拼接）
import SaveErrorDetailTest from './workers/SaveErrorDetail.test';
import DatabaseLoadGuardTest from './services/DatabaseLoadGuard.test';
import LoadDispatchServiceTest from './services/LoadDispatchService.test';
import HashUtilsFileTest from './utils/HashUtilsFile.test';
import FileTransferTest from './storage/FileTransfer.test';
import LocalStorageStreamingTest from './storage/LocalStorageStreaming.test';
import CacheStorageStreamingTest from './storage/CacheStorageStreaming.test';
// L9 加载链路版本快速路径：缓存元数据 sidecar / 回填与命中判定 / DatabaseLoad 编排
import CacheMetaServiceTest from './storage/cache/CacheMetaService.test';
import CacheStorageVersionMetaTest from './storage/cache/CacheStorageVersionMeta.test';
import DatabaseLoadFastPathTest from './workers/DatabaseLoadFastPath.test';
import GetInfoOrNullTest from './storage/GetInfoOrNull.test';
import KdbxErrorPayloadTest from './kdbx/KdbxErrorPayload.test';
// KDF 切换（AES↔Argon2）字典重建修复回归测试
import KdfSwitchTest from './kdbx/KdfSwitch.test';
import UploadTooLargeGuardTest from './storage/UploadTooLargeGuard.test';

// KPSN 二进制快照协议单元测试（跨线程传输格式编解码）
import KdbxSnapshotTest from './kdbx/KdbxSnapshot.test';

// S4 附件磁盘化单元测试（加密磁盘缓存 / 阈值转换 / 快照 v2 / v3 兼容）
import AttachmentDiskRefTest from './kdbx/AttachmentDiskRef.test';
import AttachmentCacheServiceTest from './services/AttachmentCacheService.test';

// S7-b 管道临时文件清扫单元测试
import TempFileSweeperTest from './services/TempFileSweeper.test';

// §7.4 会话文件协议单元测试（M0 包裹/解包裹/清扫）
import SessionFileServiceTest from './kdbx/SessionFileService.test';
import KdbxSnapshotV3Test from './kdbx/KdbxSnapshotV3.test';

// 公共原生 AES-256-GCM 单元测试（seal/open 往返 / 篡改拒绝 / 流式会话等价）
import AesGcmTest from './kdbx/AesGcm.test';

// ChaCha20 原生路径设备端验证（libkdbxweb_native.so chacha20Xor：可用性 / RFC 7539 向量 / 流式等价）
import Chacha20NativeTest from './kdbx/Chacha20Native.test';

// Salsa20 原生路径设备端验证（libkdbxweb_native.so salsa20Xor：djb 向量 / JS 等价 / 分块续算 / view 入参）
import Salsa20NativeTest from './kdbx/Salsa20Native.test';

// KdbxCredentials customKey（自定义密钥分量，KcpCustomKey 等价）单元测试
import KdbxCredentialsCustomKeyTest from './kdbx/KdbxCredentialsCustomKey.test';

// §10/§12 大文件验收测试（att-100/300/500 + text-10k + CP2' + 残留清扫）
import LargeFileAcceptanceTest from './acceptance/LargeFileAcceptance.test';

// S7-a OneDrive upload session 单元测试（未初始化拒绝常驻；真实 API 用例按令牌门控注册）
import OneDriveUploadSessionTest from './storage/onedrive/OneDriveUploadSession.test';

// Import/Export 单元测试
import ImportExportCommonTest from './importExport/ImportExportCommon.test';
import FormatHandlerRegistryTest from './importExport/FormatHandlerRegistry.test';
import CsvImportHandlerTest from './importExport/CsvImportHandler.test';
import XmlExportHandlerTest from './importExport/XmlExportHandler.test';
import BitwardenJsonImportHandlerTest from './importExport/BitwardenJsonImportHandler.test';
import KdbxExportHandlerTest from './importExport/KdbxExportHandler.test';
import SimpleHandlerTest from './importExport/SimpleHandler.test';

// UI 自动化测试（真实操作界面，建议用 -s class 单独运行，勿与单元测试混跑）
import OpenDatabaseUiTest from './ui/OpenDatabaseUi.test';
import StorageConflictUiTest from './ui/StorageConflictUi.test';

// ===== 新增：common/constants 常量单元测试 =====
import SortConstantsTest from './constants/SortConstants.test';
import UIConstantsTest from './constants/UIConstants.test';
import SettingDialogConstantsTest from './constants/SettingDialogConstants.test';
import NavigationConstantsTest from './constants/NavigationConstants.test';
import ThemeConstantsTest from './constants/ThemeConstants.test';
import PageConfigTest from './constants/PageConfig.test';
import ConstantsTest from './constants/Constants.test';

// ===== 新增：common/oauth2 OAuth2 框架单元测试 =====
import OAuth2TypesTest from './oauth2/OAuth2Types.test';
import OAuth2ErrorTest from './oauth2/OAuth2Error.test';
import IOAuth2ProviderTest from './oauth2/IOAuth2Provider.test';
import BaseOAuth2ProviderTest from './oauth2/BaseOAuth2Provider.test';
import OAuth2TokenStorageServiceTest from './oauth2/OAuth2TokenStorageService.test';
import OAuth2AuthServiceTest from './oauth2/OAuth2AuthService.test';
import OAuth2IndexTest from './oauth2/Index.test';

// ===== 新增：common/utils 工具类单元测试 =====
import StringUtilsTest from './utils/StringUtils.test';
import UrlUtilsTest from './utils/UrlUtils.test';
import ErrorUtilsTest from './utils/ErrorUtils.test';
import NetworkUtilsTest from './utils/NetworkUtils.test';
import DeviceUtilsTest from './utils/DeviceUtils.test';
import FileUtilsCommonTest from './utils/FileUtilsCommon.test';
import CryptoUtilsTest from './utils/CryptoUtils.test';
import CommonUtilsTest from './utils/CommonUtils.test';
import AssetUtilsTest from './utils/AssetUtils.test';
import Sm4UtilsTest from './utils/Sm4Utils.test';
import ShareUtilsTest from './utils/ShareUtils.test';
import ClipboardUtilsTest from './utils/ClipboardUtils.test';
import ResourceUtilsTest from './utils/ResourceUtils.test';
import ResourceManagerTest from './utils/ResourceManager.test';
import WindowUtilsTest from './utils/WindowUtils.test';
import WindowServiceTest from './utils/WindowService.test';
import NavigationManagerTest from './utils/NavigationManager.test';
import StorageNavigationTest from './utils/StorageNavigation.test';
import PageConfigManagerTest from './utils/PageConfigManager.test';
import IconUtilsTest from './utils/IconUtils.test';
// 修改主密码闪退回归（database 关闭后 getIcon 回退读 meta）
import KdbxUtilsIconGuardTest from './utils/KdbxUtilsIconGuard.test';
import ThemeManagerTest from './utils/ThemeManager.test';
import WebImageDownloaderTest from './utils/WebImageDownloader.test';
import ImagePickerUtilsTest from './utils/ImagePickerUtils.test';
import DialogWindowHelperTest from './utils/DialogWindowHelper.test';
import UIUtilsTest from './utils/UIUtils.test';
import HashUtilsTest from './utils/HashUtils.test';

// ===== 新增：services 顶层服务单元测试 =====
import EventBusTest from './services/EventBus.test';
import SettingsServiceTest from './services/SettingsService.test';
import AuthServiceTest from './services/AuthService.test';
import CrashLogServiceTest from './services/CrashLogService.test';
import SessionManagerTest from './services/SessionManager.test';
import CredentialsServiceTest from './services/CredentialsService.test';
import SessionNotificationServiceTest from './services/SessionNotificationService.test';
import CopyEventServiceTest from './services/CopyEventService.test';
import FileServiceTest from './services/FileService.test';
import ScanServiceTest from './services/ScanService.test';
import DataServiceTest from './services/DataService.test';
import SupportServiceTest from './services/SupportService.test';
import LockScreenServiceTest from './services/LockScreenService.test';
import BasicDataSourceTest from './services/BasicDataSource.test';
import LocationParamTest from './services/LocationParam.test';
import KeepassHoErrorTest from './services/KeepassHoError.test';

// ===== 新增：services/template 模板子系统单元测试 =====
import TemplateTypesTest from './services/template/TemplateTypes.test';
import TemplateConstantsTest from './services/template/TemplateConstants.test';
import TemplateBuilderTest from './services/template/TemplateBuilder.test';
import TemplateFactoryTest from './services/template/TemplateFactory.test';
import TemplateServiceTest from './services/template/TemplateService.test';
import ITemplateStrategyTest from './services/template/strategies/ITemplateStrategy.test';
import UserTemplateStrategyTest from './services/template/strategies/UserTemplateStrategy.test';
import PresetTemplateStrategyTest from './services/template/strategies/PresetTemplateStrategy.test';

// ===== 新增：services/importExport 编排层单元测试 =====
import XmlImportHandlerTest from './importExport/XmlImportHandler.test';
import KeyFileExportHandlerTest from './importExport/KeyFileExportHandler.test';
import ImportServiceTest from './importExport/ImportService.test';
import ExportServiceTest from './importExport/ExportService.test';
import ImportExportFacadeTest from './importExport/ImportExportFacade.test';
import ImportExportViewModelTest from './importExport/ImportExportViewModel.test';
import ImportExportIndexTest from './importExport/Index.test';

// ===== 新增：storage 配置/工厂/队列单元测试 =====
import FileStorageFactoryTest from './storage/FileStorageFactory.test';
import StorageConfigTest from './storage/StorageConfig.test';
import StorageTypeTest from './storage/StorageType.test';
import LocalFileConfigTest from './storage/local/LocalFileConfig.test';
import CacheConstantsTest from './storage/cache/CacheConstants.test';
import S3ConfigTest from './storage/s3/S3Config.test';
import S3TypesTest from './storage/s3/S3Types.test';
import S3UploadQueueTest from './storage/s3/S3UploadQueue.test';
import OneDriveConfigTest from './storage/onedrive/OneDriveConfig.test';
import OneDriveOAuth2ProviderTest from './storage/onedrive/OneDriveOAuth2Provider.test';
import GoogleOAuth2ProviderTest from './storage/googledrive/GoogleOAuth2Provider.test';
import HuaweiDriveConfigTest from './storage/huawei/HuaweiDriveConfig.test';
import HuaweiDriveOAuth2ProviderTest from './storage/huawei/HuaweiDriveOAuth2Provider.test';
import HuaweiDrivePathCacheStoreTest from './storage/huawei/HuaweiDrivePathCacheStore.test';
import FTPConfigTest from './storage/ftp/FTPConfig.test';
import FTPHandlerTest from './storage/ftp/FTPHandler.test';
import IFTPHandlerTest from './storage/ftp/IFTPHandler.test';

// ===== 新增：services/kdbx 与 workers/callback 单元测试 =====
import KdbxSaveServiceTest from './kdbx/KdbxSaveService.test';
import KdbxLoadServiceTest from './kdbx/KdbxLoadService.test';
import KdbxFileManagerTest from './kdbx/KdbxFileManager.test';
import SaveDatabaseCallbackTest from './workers/SaveDatabaseCallback.test';
import ToastSaveDatabaseCallbackTest from './workers/ToastSaveDatabaseCallback.test';

// E2E 测试数据库生成套件（结构验证 + S3 上传，需 SeaweedFS 网关与反向隧道，
// 建议 -s class GenerateE2eTestDatabaseTest 单独运行；连接方式与主密码见 docs/e2e-test-database.md）
import GenerateE2eTestDatabaseTest from './testdata/GenerateE2eTestDatabase.test';
// E2E 数据库操作单元测试（修改主密码往返 / 元数据设置持久化）
import DatabaseChangePasswordMetaTest from './testdata/DatabaseChangePasswordMeta.test';


export default function testsuite() {
  ActsAbilityTest();
  KdbxErrorTest();
  WebDavTest();
  TotpServiceTest();
  FileUtilsTest();
  RecentFilesServiceTest();
  DistributedKVServiceTest();
  SyncSettingsServiceTest();
  OtpCompatibilityManagerTest();
  OtpUrlParserTest();
  KeePass2ParserTest();
  KeeOtpParserTest();
  KeeTrayTotpParserTest();

  S3ClientTest();
  S3ClientMultipartTest();
  S3SignatureV4Test();
  S3StorageTest();
  S3XmlParserTest();

  // S3 真实集成测试（需真实 S3/MinIO 环境，建议 -s class S3StorageIntegrationTest 单独运行）
  S3StorageIntegrationTest();

  PCloudClientTest();
  PCloudConfigTest();
  PCloudOAuth2ProviderTest();
  PCloudStorageTest();

  // 华为云盘单元测试
  // 华为云盘：契约纯函数用例常驻注册；真实 API 用例由 isRealApiEnabled 门控自跳过
  HuaweiDriveStorageTest();
  HuaweiDriveClientTest();
  // 华为云盘下载进度聚合器测试
  DownloadProgressAggregatorTest();

  // SFTP 处理器单元测试（错误码解析 / 未连接语义 / 原生连接失败路径）
  SFTPHandlerTest();

  // SFTP 存储层语义测试（FTPStorage L1 / CacheStorage 装饰器 / RecentFilesService L2）
  SFTPStorageSemanticsTest();

  // SFTP 真实存储操作测试（podman sftp-e2e + rport 隧道，真实 KDBX 文件读写与条件写冲突）
  SFTPStorageRealFileTest();

  // 数据库加载/保存双模式测试（同步模式：主线程 DatabaseLoad/DatabaseSave 全链路含冲突矩阵）
  DatabaseSyncModeTest();
  // 数据库加载/保存双模式测试（异步模式：真实 ThreadWorker 消息链路 + 边界序列化）
  DatabaseWorkerModeTest();
  // Worker 常驻池化测试（策略随任务注入 + forceRefresh 一次性消费 + 忙拒绝）
  WorkerPoolPolicyTest();

  // PREWARM 预热协议测试（真实 Worker 全链路 + forceRefresh 不消费回归）
  LoadWorkerPrewarmTest();

  // 分级加载调度测试（resolveSize 解析链 + 主线程/Worker 路由 + 守卫 precheckSize 去重）
  LoadDispatchServiceTest();
  // S6 保存管道流式路径测试（ChaCha20 v4 → saveToFile + writeFromFile，对照 AES 回退）
  DatabaseSaveStreamingTest();
  // S8 版本预检快速路径测试（能力声明 + 版本一致跳过下载，计数存储观测）
  DatabaseSaveFastPathTest();
  StreamingXmlParserTest();

  // Worker 环境注入机制测试（INIT_WORKER 消息 + 路径/缓存策略快照）
  WorkerEnvironmentInjectionTest();

  // 传输进度条（双向）测试（限频器 / 进度消息 / 基类分发）
  ProgressThrottlerTest();
  ProgressMessageTest();
  ProgressDispatchTest();

  // 保存错误明细展示链路测试（detail 字段 + 前缀拼接）
  SaveErrorDetailTest();

  // 数据库加载守卫测试（CP1 文件大小 / CP-DISK 磁盘余量 / CP2' 解压上限）
  DatabaseLoadGuardTest();

  // 流式文件哈希测试（sha256HexFile 增量分块 vs 整缓冲一致性）
  HashUtilsFileTest();

  // FileTransfer 默认实现测试（整缓冲包装 + 文件读写助手）
  FileTransferTest();

  // LocalStorage 流式传输测试（readToFile/writeFromFile 原子写）
  LocalStorageStreamingTest();

  // CacheStorage 流式委托测试（readToFile/writeFromFile 委托 + only-cache 模式）
  CacheStorageStreamingTest();

  // 缓存元数据 sidecar 测试（写读删往返 / 缺失与损坏容错 / 路径规则）
  CacheMetaServiceTest();

  // 缓存回填 + 版本快速路径判定测试（P2/P3.2/P4/P5：回填 meta、命中/未命中矩阵、清理无孤儿）
  CacheStorageVersionMetaTest();

  // 加载链路版本快速路径测试（命中零下载 / 远端已变 miss / force_refresh 必下载）
  DatabaseLoadFastPathTest();

  // getInfoOrNull（存在性+大小一次返回）测试（LOCAL/WebDAV/能力回退/CacheStorage 策略/调度缓存）
  GetInfoOrNullTest();

  // kdbxErrorPayload 新增映射测试（DecompressedTooLarge + UPLOAD_TOO_LARGE）
  KdbxErrorPayloadTest();

  // KDF 切换字典重建修复回归测试（AES↔Argon2d/Argon2id / V 键补齐 / 残留键清理）
  KdfSwitchTest();

  // CP-UP 上传上限守卫测试
  UploadTooLargeGuardTest();

  // KPSN 二进制快照协议测试（saveSnapshot/loadSnapshot 编解码 + 三格式分发）
  KdbxSnapshotTest();

  // S4 附件磁盘化测试（AttachmentStore 缓存 / 阈值转换 / save/快照/导出保真）
  AttachmentDiskRefTest();

  // S4 附件缓存服务测试（Asset Kit 密钥 / Worker 注入 / 优雅降级）
  AttachmentCacheServiceTest();

  // S7-b 管道临时文件清扫测试（启动清残留 / onDestroy 全清）
  TempFileSweeperTest();

  // §7.4 会话文件协议测试（包裹往返 / 大缓冲分块 / 清扫）
  SessionFileServiceTest();

  // M0 v3 直传容器测试（容器往返/错误密码/CP2'/SFW1 流式包裹/Worker 全链路）
  KdbxSnapshotV3Test();

  // 公共原生 AES-256-GCM 测试（seal/open 往返 / 篡改拒绝 / 流式会话等价）
  AesGcmTest();

  // ChaCha20 原生路径设备端验证（原生可用性 / RFC 7539 向量 / 分块流式等价）
  Chacha20NativeTest();
  // Salsa20 原生路径设备端验证（djb 向量 / JS 等价 / 分块续算 / view 入参 / 零长度）
  Salsa20NativeTest();
  KdbxCredentialsCustomKeyTest();

  // §10/§12 大文件验收测试（建议 -s class LargeFileAcceptanceTest 单独运行）
  LargeFileAcceptanceTest();

  // S7-a OneDrive upload session 测试（未初始化拒绝 / 真实 API 用例门控注册）
  OneDriveUploadSessionTest();

  // Import/Export 单元测试
  ImportExportCommonTest();
  FormatHandlerRegistryTest();
  SimpleHandlerTest();
  CsvImportHandlerTest();
  XmlExportHandlerTest();
  BitwardenJsonImportHandlerTest();
  KdbxExportHandlerTest();

  // ===== common/constants =====
  SortConstantsTest();
  UIConstantsTest();
  SettingDialogConstantsTest();
  NavigationConstantsTest();
  ThemeConstantsTest();
  PageConfigTest();
  ConstantsTest();

  // ===== common/oauth2 =====
  OAuth2TypesTest();
  OAuth2ErrorTest();
  IOAuth2ProviderTest();
  BaseOAuth2ProviderTest();
  OAuth2TokenStorageServiceTest();
  OAuth2AuthServiceTest();
  OAuth2IndexTest();

  // ===== common/utils =====
  StringUtilsTest();
  UrlUtilsTest();
  ErrorUtilsTest();
  NetworkUtilsTest();
  DeviceUtilsTest();
  FileUtilsCommonTest();
  CryptoUtilsTest();
  CommonUtilsTest();
  AssetUtilsTest();
  Sm4UtilsTest();
  ShareUtilsTest();
  ClipboardUtilsTest();
  ResourceUtilsTest();
  ResourceManagerTest();
  WindowUtilsTest();
  WindowServiceTest();
  NavigationManagerTest();
  StorageNavigationTest();
  PageConfigManagerTest();
  IconUtilsTest();
  KdbxUtilsIconGuardTest();
  ThemeManagerTest();
  WebImageDownloaderTest();
  ImagePickerUtilsTest();
  DialogWindowHelperTest();
  UIUtilsTest();
  HashUtilsTest();

  // ===== services 顶层 =====
  EventBusTest();
  SettingsServiceTest();
  AuthServiceTest();
  CrashLogServiceTest();
  SessionManagerTest();
  CredentialsServiceTest();
  SessionNotificationServiceTest();
  CopyEventServiceTest();
  FileServiceTest();
  ScanServiceTest();
  DataServiceTest();
  SupportServiceTest();
  LockScreenServiceTest();
  BasicDataSourceTest();
  LocationParamTest();
  KeepassHoErrorTest();

  // ===== services/template =====
  TemplateTypesTest();
  TemplateConstantsTest();
  TemplateBuilderTest();
  TemplateFactoryTest();
  TemplateServiceTest();
  ITemplateStrategyTest();
  UserTemplateStrategyTest();
  PresetTemplateStrategyTest();

  // ===== services/importExport 编排层 =====
  XmlImportHandlerTest();
  KeyFileExportHandlerTest();
  ImportServiceTest();
  ExportServiceTest();
  ImportExportFacadeTest();
  ImportExportViewModelTest();
  ImportExportIndexTest();

  // ===== storage 配置/工厂/队列 =====
  FileStorageFactoryTest();
  StorageConfigTest();
  StorageTypeTest();
  LocalFileConfigTest();
  CacheConstantsTest();
  S3ConfigTest();
  S3TypesTest();
  S3UploadQueueTest();
  OneDriveConfigTest();
  OneDriveOAuth2ProviderTest();
  GoogleOAuth2ProviderTest();
  HuaweiDriveConfigTest();
  HuaweiDriveOAuth2ProviderTest();
  HuaweiDrivePathCacheStoreTest();
  FTPConfigTest();
  FTPHandlerTest();
  IFTPHandlerTest();

  // ===== services/kdbx 与 workers/callback =====
  KdbxSaveServiceTest();
  KdbxLoadServiceTest();
  KdbxFileManagerTest();
  SaveDatabaseCallbackTest();
  ToastSaveDatabaseCallbackTest();

  // E2E 测试数据库生成（生成结构验证 + 上传 S3；S3 用例需隧道，建议按 class 单独运行）
  GenerateE2eTestDatabaseTest();
  // E2E 数据库操作（修改主密码往返 / 元数据设置持久化）
  DatabaseChangePasswordMetaTest();

  // UI 自动化测试
  // OpenDatabaseUiTest();
  // StorageConflictUiTest();
}