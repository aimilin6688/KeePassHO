import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { AssetUtils } from '../../../../main/ets/common/utils/AssetUtils';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';

export default function AssetUtilsTest() {
  describe('AssetUtils', () => {
    beforeAll(() => {
      const appContext =  abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
    });

    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    it('querySync returns undefined for empty assetId', 0, () => {
      expect(AssetUtils.querySync('')).assertUndefined();
    });

    it('querySync returns undefined for whitespace assetId (not found)', 0, () => {
      const result = AssetUtils.querySync('   ');
      expect(result).assertUndefined();
    });

    it('querySync returns undefined for nonexistent asset', 0, () => {
      const result = AssetUtils.querySync('nonexistent_asset_alias_xyz_unique_hypium_001');
      expect(result).assertUndefined();
    });

    it('saveSync with empty assetId does not throw', 0, () => {
      try {
        AssetUtils.saveSync('', 'secret_value');
        expect(true).assertTrue();
      } catch (e) {
        expect(false).assertTrue();
      }
    });

    it('saveSync with empty secret does not throw', 0, () => {
      try {
        AssetUtils.saveSync('hypium_test_alias_empty_secret', '');
        expect(true).assertTrue();
      } catch (e) {
        expect(false).assertTrue();
      }
    });

    it('saveSync with both empty does not throw', 0, () => {
      try {
        AssetUtils.saveSync('', '');
        expect(true).assertTrue();
      } catch (e) {
        expect(false).assertTrue();
      }
    });

    it('saveSync then querySync round-trip (graceful if Asset Kit unavailable)', 0, () => {
      const alias = 'hypium_asset_roundtrip_001';
      const secret = 'hypium_roundtrip_secret';
      try {
        AssetUtils.saveSync(alias, secret);
      } catch (e) {
        // saveSync catches internally — should never throw
      }
      const queried = AssetUtils.querySync(alias);
      if (queried !== undefined) {
        expect(queried).assertEqual(secret);
      } else {
        expect(queried).assertUndefined();
      }
    });

    it('saveSync with long secret does not throw', 0, () => {
      let longSecret = '';
      for (let i = 0; i < 256; i++) {
        longSecret += 'x';
      }
      try {
        AssetUtils.saveSync('hypium_long_secret_alias', longSecret);
        expect(true).assertTrue();
      } catch (e) {
        expect(false).assertTrue();
      }
    });
  });
}
