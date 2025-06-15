import KdbxErrorTest from './errors/kdbx-error.test';
import ChaCha20Test from './crypto/chacha20.test';
import Salsa20Test from './crypto/salsa20.test';
import ProtectedValueTest from './crypto/protected-value.test';
import CryptoEngineTest from './crypto/crypto-engine.test';

export default function testsuite() {
  KdbxErrorTest();
  ChaCha20Test();
  Salsa20Test();
  ProtectedValueTest();
  CryptoEngineTest();
}