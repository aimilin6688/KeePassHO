import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { ResourceUtils } from '../../../../main/ets/common/utils/ResourceUtils';

class FullResourceObj {
  bundleName: string = 'com.test.app';
  id: number = 100;
}

class PartialBundleOnly {
  bundleName: string = 'com.test.app';
}

class PartialIdOnly {
  id: number = 200;
}

class EmptyObj {
}

class ExtraFieldsObj {
  bundleName: string = 'com.test.app';
  id: number = 300;
  extra: string = 'value';
}

export default function ResourceUtilsTest() {
  describe('ResourceUtils', () => {
    beforeAll(() => {});
    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    it('isResourceStr returns true for non-empty string', 0, () => {
      expect(ResourceUtils.isResourceStr('hello')).assertTrue();
    });

    it('isResourceStr returns true for empty string', 0, () => {
      expect(ResourceUtils.isResourceStr('')).assertTrue();
    });

    it('isResourceStr returns true for object with bundleName and id', 0, () => {
      expect(ResourceUtils.isResourceStr(new FullResourceObj())).assertTrue();
    });

    it('isResourceStr returns true for object with extra fields plus bundleName and id', 0, () => {
      expect(ResourceUtils.isResourceStr(new ExtraFieldsObj())).assertTrue();
    });

    it('isResourceStr returns false for object with only bundleName', 0, () => {
      expect(ResourceUtils.isResourceStr(new PartialBundleOnly())).assertFalse();
    });

    it('isResourceStr returns false for object with only id', 0, () => {
      expect(ResourceUtils.isResourceStr(new PartialIdOnly())).assertFalse();
    });

    it('isResourceStr returns false for empty object', 0, () => {
      expect(ResourceUtils.isResourceStr(new EmptyObj())).assertFalse();
    });
  });
}
