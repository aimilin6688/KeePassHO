import abilityTest from './Ability.test';
import KdbxErrorTest from './errors/kdbx-error.test';

export default function testsuite() {
  abilityTest();
  KdbxErrorTest();
}