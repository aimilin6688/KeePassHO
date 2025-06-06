import ARC4UnitTest from './kdbx/crypto/ARC4.test';
import ChaCha20UnitTest from './kdbx/crypto/ChaCha20.test';
import Salsa20UnitTest from './kdbx/crypto/Salsa20.test';
// import KdbxCredentialsUnitTest from './kdbx/KdbxCredentials.test';
// import KdbxCryptoUnitTest from './kdbx/KdbxCrypto.test';
import KdbxErrorUnitTest from './kdbx/KdbxError.test';
// import KdbxFileUnitTest from './kdbx/KdbxFile.test';
// import KdbxFormatUnitTest from './kdbx/KdbxFormat.test';
// import KdbxHeaderUnitTest from './kdbx/KdbxHeader.test';
// import KdbxManagerUnitTest from './kdbx/KdbxManager.test';
// import KdbxReaderUnitTest from './kdbx/KdbxReader.test';
// import KdbxWriterUnitTest from './kdbx/KdbxWriter.test';
import KdbxDatabaseUnitTest from './kdbx/models/KdbxDatabase.test';
import KdbxEntryUnitTest from './kdbx/models/KdbxEntry.test';
import KdbxGroupUnitTest from './kdbx/models/KdbxGroup.test';
// import KdbxXmlProcessorUnitTest from './kdbx/xml/KdbxXmlProcessor.test';


export default function testsuite() {
  ARC4UnitTest();
  ChaCha20UnitTest();
  Salsa20UnitTest();
  KdbxDatabaseUnitTest();
  KdbxEntryUnitTest();
  KdbxGroupUnitTest();
  // KdbxXmlProcessorUnitTest();
  // KdbxCredentialsUnitTest();
  // KdbxCryptoUnitTest();
  KdbxErrorUnitTest();
  // KdbxFileUnitTest();
  // KdbxFormatUnitTest();
  // KdbxHeaderUnitTest();
  // KdbxManagerUnitTest();
  // KdbxReaderUnitTest();
  // KdbxWriterUnitTest();
}