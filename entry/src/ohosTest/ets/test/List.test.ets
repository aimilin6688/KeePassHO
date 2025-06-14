import ActsAbilityTest from './ActsAbility.test';
import KdbxErrorTest from './kdbx/error/KdbxError.test';


export default function testsuite() {
  ActsAbilityTest();
  KdbxErrorTest();
}