import { describe, expect, it } from '@ohos/hypium';
import { NavigationModeType, PageConfig } from '../../../../main/ets/common/constants/PageConfig';

export default function PageConfigTest() {
  describe('PageConfig', () => {
    it('navigationModeTypeHasExpectedRawValues', 0, () => {
      const exclusiveValue: string = NavigationModeType.EXCLUSIVE;
      const splitValue: string = NavigationModeType.SPLIT;
      expect(exclusiveValue).assertEqual('exclusive');
      expect(splitValue).assertEqual('split');
    });

    it('navigationModeTypeMembersAreUnique', 0, () => {
      const values: string[] = [NavigationModeType.EXCLUSIVE, NavigationModeType.SPLIT];
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < values.length; i++) {
        unique.add(values[i]);
      }
      expect(unique.size).assertEqual(2);
    });

    it('pageConfigInterfaceAcceptsFullConfiguration', 0, () => {
      const config: PageConfig = {
        name: 'Index',
        navigationMode: NavigationModeType.EXCLUSIVE,
        constrainMaxWidth: true,
        maxWidth: 700,
        padding: 16
      };
      expect(config.name).assertEqual('Index');
      expect(config.navigationMode).assertEqual(NavigationModeType.EXCLUSIVE);
      expect(config.constrainMaxWidth).assertTrue();
      expect(config.maxWidth).assertEqual(700);
      expect(config.padding).assertEqual(16);
    });

    it('pageConfigInterfaceAcceptsMinimalConfiguration', 0, () => {
      const config: PageConfig = {
        name: 'DatabaseView',
        navigationMode: NavigationModeType.SPLIT,
        constrainMaxWidth: false
      };
      expect(config.name).assertEqual('DatabaseView');
      expect(config.navigationMode).assertEqual(NavigationModeType.SPLIT);
      expect(config.constrainMaxWidth).assertFalse();
      expect(config.maxWidth).assertUndefined();
      expect(config.padding).assertUndefined();
    });

    it('pageConfigInterfaceAcceptsSplitModeWithMaxWidth', 0, () => {
      const config: PageConfig = {
        name: 'Settings',
        navigationMode: NavigationModeType.SPLIT,
        constrainMaxWidth: true,
        maxWidth: 800
      };
      expect(config.padding).assertUndefined();
      expect(config.maxWidth).assertEqual(800);
    });
  });
}
