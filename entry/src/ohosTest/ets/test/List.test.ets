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
import StorageTestSuite from './storage/StorageTestSuite';


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
  StorageTestSuite();
}