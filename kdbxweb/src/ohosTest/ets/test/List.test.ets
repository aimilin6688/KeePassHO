import KdbxErrorTest from './errors/kdbx-error.test';
import ChaCha20Test from './crypto/chacha20.test';
import Salsa20Test from './crypto/salsa20.test';
import ProtectedValueTest from './crypto/protected-value.test';
import CryptoEngineTest from './crypto/crypto-engine.test';
import HashedBlockTransformTest from './crypto/hashed-block-transform.test';
import HmacBlockTransformTest from './crypto/hmac-block-transform.test';
import KeyEncryptorAesTest from './crypto/key-encryptor-aes.test';
import KeyEncryptorKdfTest from './crypto/key-encryptor-kdf.test';
import ProtectSaltGeneratorTest from './crypto/protected-salt-generator.test';


// import KdbxMergeTest from './format/kdbx.merge.test';
// import KdbxTest from './format/kdbx.test';
// import KdbxBinariesTest from './format/kdbx-binaries.test';
// import KdbxCredentialsTest from './format/kdbx-credentials.test';
// import KdbxCustomDataTest from './format/kdbx-custom-data.test';
// import KdbxHeaderTest from './format/kdbx-header.test';
import KdbxUuidTest from './format/kdbx-uuid.test';
import ByteUtilsTest from './utils/byte-utils.test';
import Int64Test from './utils/int64.test';


export default function testsuite() {
  KdbxErrorTest();
  ChaCha20Test();
  Salsa20Test();
  ProtectedValueTest();
  CryptoEngineTest();
  HashedBlockTransformTest();
  HmacBlockTransformTest();
  KeyEncryptorAesTest();
  KeyEncryptorKdfTest();
  ProtectSaltGeneratorTest();

  // KdbxMergeTest();
  // KdbxTest();
  // KdbxBinariesTest();
  // KdbxCredentialsTest();
  // KdbxCustomDataTest();
  // KdbxHeaderTest();
  KdbxUuidTest();

  ByteUtilsTest();
  Int64Test();
}