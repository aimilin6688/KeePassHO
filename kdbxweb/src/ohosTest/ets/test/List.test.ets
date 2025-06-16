import ChaCha20Test from './crypto/chacha20.test';
import CryptoEngineTest from './crypto/crypto-engine.test';
import HashedBlockTransformTest from './crypto/hashed-block-transform.test';
import HmacBlockTransformTest from './crypto/hmac-block-transform.test';
import KeyEncryptorAesTest from './crypto/key-encryptor-aes.test';
import KeyEncryptorKdfTest from './crypto/key-encryptor-kdf.test';
import ProtectSaltGeneratorTest from './crypto/protected-salt-generator.test';
import ProtectedValueTest from './crypto/protected-value.test';
import Salsa20Test from './crypto/salsa20.test';

import KdbxErrorTest from './errors/kdbx-error.test';


// import KdbxMergeTest from './format/kdbx.merge.test';
// import KdbxTest from './format/kdbx.test';
// import KdbxBinariesTest from './format/kdbx-binaries.test';
// import KdbxCredentialsTest from './format/kdbx-credentials.test';
// import KdbxCustomDataTest from './format/kdbx-custom-data.test';
import KdbxHeaderTest from './format/kdbx-header.test';
import KdbxUuidTest from './format/kdbx-uuid.test';


import BinaryStreamTest from './utils/binary-stream.test';
import ByteUtilsTest from './utils/byte-utils.test';
import Int64Test from './utils/int64.test';
import VarDictionaryTest from './utils/var-dictionary.test';
import XmlUtilsTest from './utils/xml-utils.test';







export default function testsuite() {
  // ------- crypto tests ----------------
  ChaCha20Test();
  CryptoEngineTest();
  HashedBlockTransformTest();
  HmacBlockTransformTest();
  KeyEncryptorAesTest();
  KeyEncryptorKdfTest();
  ProtectSaltGeneratorTest();
  ProtectedValueTest();
  Salsa20Test();

 //   ------- errors tests ----------------
  KdbxErrorTest();

  // ------- format tests ----------------
  // KdbxMergeTest();
  // KdbxTest();
  // KdbxBinariesTest();
  // KdbxCredentialsTest();
  // KdbxCustomDataTest();
  KdbxHeaderTest();
  KdbxUuidTest();

  // ------- utils tests ----------------
  BinaryStreamTest();
  ByteUtilsTest();
  Int64Test();
  VarDictionaryTest();
  XmlUtilsTest();
}