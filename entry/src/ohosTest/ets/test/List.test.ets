import ActsAbilityTest from './ActsAbility.test';
import KdbxErrorTest from './kdbx/error/KdbxError.test';
import WebDavTest from './entry/WebDav.test';
import TotpServiceTest from './services/TotpService.test';
import FileUtilsTest from './utils/FileUtilsTest';


export default function testsuite() {
  ActsAbilityTest();
  KdbxErrorTest();
  WebDavTest();
  TotpServiceTest();
  FileUtilsTest();
}