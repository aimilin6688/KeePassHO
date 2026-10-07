import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { ImagePickerUtils } from '../../../../main/ets/common/utils/ImagePickerUtils';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

function initTestContext(): void {
  const appContext =  abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  CommonUtils.init(appContext as common.UIAbilityContext);
}

export default function ImagePickerUtilsTest() {
  describe('ImagePickerUtils', () => {
    beforeAll(() => {
      initTestContext();
    });

    // ---------------- handlerImages ----------------
    it('handlerImages with empty uri list resolves to empty array', 0, async () => {
      const result = await ImagePickerUtils.handlerImages([], 64);
      expect(result.length).assertEqual(0);
    });

    it('handlerImages with unusable uri resolves to empty array without throwing', 0, async () => {
      let result: string[] = [];
      let noThrow = true;
      try {
        result = await ImagePickerUtils.handlerImages(['file:///nonexistent-folder/nonexistent-image.bin'], 64);
      } catch {
        noThrow = false;
      }
      expect(noThrow).assertTrue();
      expect(result.length).assertEqual(0);
    });

    it('handlerImages with zero size still processes empty list', 0, async () => {
      const result = await ImagePickerUtils.handlerImages([], 0);
      expect(result.length).assertEqual(0);
    });

    // NOTE: selectImage opens the photo picker (user interaction) and real
    // image decoding needs a valid media uri; both are covered by UI
    // automation tests instead.
  });
}
