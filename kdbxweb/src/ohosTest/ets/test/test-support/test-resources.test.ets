import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, KdbxUuid } from '../../../../main/ets/index';
import { TestResources } from './test-resources';

export default function ResourcesTest() {
  describe('Resources', () => {
    it('create file', 0, () => {
      console.log(ByteUtils.bytesToString(TestResources.demoKdbx));
    });
  });
}