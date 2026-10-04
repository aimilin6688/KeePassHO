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

  PCloudClientTest();
  PCloudConfigTest();
  PCloudOAuth2ProviderTest();
  PCloudStorageTest();

  // 华为云盘单元测试
  HuaweiDriveStorageTest();
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