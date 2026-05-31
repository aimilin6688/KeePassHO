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
import S3StorageTest from './storage/s3/S3Storage.test';
import S3XmlParserTest from './storage/s3/S3XmlParser.test';
import S3SignatureV4Test from './storage/s3/S3SignatureV4.test';
import S3ClientTest from './storage/s3/S3Client.test';
import PCloudClientTest from './storage/pcloud/PCloudClient.test';
import PCloudConfigTest from './storage/pcloud/PCloudConfig.test';
import PCloudOAuth2ProviderTest from './storage/pcloud/PCloudOAuth2Provider.test';
import PCloudClientIntegrationTest from './storage/pcloud/PCloudClientIntegration.test';


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
  S3StorageTest();
  S3XmlParserTest();
  S3SignatureV4Test();
  S3ClientTest();
  PCloudClientTest();
  PCloudConfigTest();
  PCloudOAuth2ProviderTest();
  PCloudClientIntegrationTest();
}