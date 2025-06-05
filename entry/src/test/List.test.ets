import localUnitTest from './LocalUnit.test';
import ARC4UnitTest from './kdbx/crypto/ARC4.test';

export default function testsuite() {
  localUnitTest();
  ARC4UnitTest();
}