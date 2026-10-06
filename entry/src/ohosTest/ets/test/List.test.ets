import ActsAbilityTest from './ActsAbility.test';
import KdbxErrorTest from './kdbx/error/KdbxError.test';
import WebDavTest from './entry/WebDav.test';
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
import SFTPHandlerTest from './storage/sftp/SFTPHandler.test';
import SFTPStorageSemanticsTest from './storage/sftp/SFTPStorageSemantics.test';
import SFTPStorageRealFileTest from './storage/sftp/SFTPStorageRealFile.test';

// 数据库加载/保存双模式单元测试（同步模式 / Worker 异步模式）
import DatabaseSyncModeTest from './workers/DatabaseSyncMode.test';
import DatabaseWorkerModeTest from './workers/DatabaseWorkerMode.test';
// S6 保存管道流式路径专项（ChaCha20 v4 → saveToFile + writeFromFile，对照 AES 回退）
import DatabaseSaveStreamingTest from './workers/DatabaseSaveStreaming.test';
import WorkerEnvironmentInjectionTest from './workers/WorkerEnvironmentInjection.test';
import DatabaseLoadGuardTest from './services/DatabaseLoadGuard.test';
import HashUtilsFileTest from './utils/HashUtilsFile.test';
import FileTransferTest from './storage/FileTransfer.test';
import LocalStorageStreamingTest from './storage/LocalStorageStreaming.test';
import CacheStorageStreamingTest from './storage/CacheStorageStreaming.test';
import KdbxErrorPayloadTest from './kdbx/KdbxErrorPayload.test';
import UploadTooLargeGuardTest from './storage/UploadTooLargeGuard.test';

// KPSN 二进制快照协议单元测试（跨线程传输格式编解码）
import KdbxSnapshotTest from './kdbx/KdbxSnapshot.test';

// S4 附件磁盘化单元测试（加密磁盘缓存 / 阈值转换 / 快照 v2 / v3 兼容）
import AttachmentDiskRefTest from './kdbx/AttachmentDiskRef.test';
import AttachmentCacheServiceTest from './services/AttachmentCacheService.test';

// S7-b 管道临时文件清扫单元测试
import TempFileSweeperTest from './services/TempFileSweeper.test';

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
  // HuaweiDriveStorageTest();
  HuaweiDriveClientTest();

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
  // S6 保存管道流式路径测试（ChaCha20 v4 → saveToFile + writeFromFile，对照 AES 回退）
  DatabaseSaveStreamingTest();

  // Worker 环境注入机制测试（INIT_WORKER 消息 + 路径/缓存策略快照）
  WorkerEnvironmentInjectionTest();

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

  // kdbxErrorPayload 新增映射测试（DecompressedTooLarge + UPLOAD_TOO_LARGE）
  KdbxErrorPayloadTest();

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

  // UI 自动化测试
  OpenDatabaseUiTest();
  StorageConflictUiTest();
}