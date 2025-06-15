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
}