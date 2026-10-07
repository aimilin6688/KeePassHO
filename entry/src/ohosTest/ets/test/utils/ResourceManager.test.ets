import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { ResourceManager } from '../../../../main/ets/common/utils/ResourceManager';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';

export default function ResourceManagerTest() {
  describe('ResourceManager', () => {
    let appContext: common.Context;

    beforeAll(() => {
      appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext().getApplicationContext();
    });

    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    it('getInstance returns singleton (same instance)', 0, () => {
      const a = ResourceManager.getInstance();
      const b = ResourceManager.getInstance();
      expect(a === b).assertTrue();
    });

    it('getString returns string passthrough without context', 0, () => {
      expect(ResourceManager.getInstance().getString('plain_text')).assertEqual('plain_text');
    });

    it('getString returns empty for number resource without context', 0, () => {
      expect(ResourceManager.getInstance().getString(999999)).assertEqual('');
    });

    it('getString returns empty for Resource object without context', 0, () => {
      const resource: Resource = {
        bundleName: 'com.test.app',
        moduleName: 'entry',
        id: 999999,
        type: 1,
        params: []
      };
      expect(ResourceManager.getInstance().getString(resource)).assertEqual('');
    });

    it('static getString returns string passthrough', 0, () => {
      expect(ResourceManager.getString('static_plain_text')).assertEqual('static_plain_text');
    });

    it('static getString returns empty for number without context', 0, () => {
      expect(ResourceManager.getString(888888)).assertEqual('');
    });

    it('getMessage returns string passthrough without context', 0, () => {
      expect(ResourceManager.getInstance().getMessage('message_text')).assertEqual('message_text');
    });

    it('getMessage returns empty for number without context', 0, () => {
      expect(ResourceManager.getInstance().getMessage(999999)).assertEqual('');
    });

    it('static getMessage returns string passthrough', 0, () => {
      expect(ResourceManager.getMessage('static_message_text')).assertEqual('static_message_text');
    });

    it('init sets context without error', 0, () => {
      try {
        ResourceManager.getInstance().init(appContext as common.UIAbilityContext);
        expect(true).assertTrue();
      } catch (e) {
        expect(false).assertTrue();
      }
    });

    it('getString returns string passthrough after init', 0, () => {
      expect(ResourceManager.getInstance().getString('after_init_text')).assertEqual('after_init_text');
    });

    it('getString with args returns string passthrough', 0, () => {
      expect(ResourceManager.getString('text_with_args', 'arg1', 42)).assertEqual('text_with_args');
    });

    it('getMessage passes through unknown name after init', 0, () => {
      const unknown = 'nonexistent_resource_name_xyz_unique';
      const result = ResourceManager.getInstance().getMessage(unknown);
      expect(result).assertEqual(unknown);
    });

    it('static getMessage passes through unknown name after init', 0, () => {
      const unknown = 'nonexistent_resource_name_xyz_static';
      const result = ResourceManager.getMessage(unknown);
      expect(result).assertEqual(unknown);
    });

    it('getMessage with number after init returns a string', 0, () => {
      const result = ResourceManager.getInstance().getMessage(999999);
      expect(typeof result === 'string').assertTrue();
    });
  });
}
