import { describe, expect, it } from '@ohos/hypium';
import { NavigationConstants } from '../../../../main/ets/common/constants/NavigationConstants';

export default function NavigationConstantsTest() {
  describe('NavigationConstants', () => {
    it('navBarWidthRangeHasExpectedBounds', 0, () => {
      expect(NavigationConstants.NAV_BAR_WIDTH_RANGE.length).assertEqual(2);
      expect(NavigationConstants.NAV_BAR_WIDTH_RANGE[0]).assertEqual(240);
      expect(NavigationConstants.NAV_BAR_WIDTH_RANGE[1]).assertEqual(700);
    });

    it('defaultNavBarWidthIsInsideWidthRange', 0, () => {
      expect(NavigationConstants.DEFAULT_NAV_BAR_WIDTH).assertEqual(360);
      expect(NavigationConstants.DEFAULT_NAV_BAR_WIDTH >= NavigationConstants.NAV_BAR_WIDTH_RANGE[0]).assertTrue();
      expect(NavigationConstants.DEFAULT_NAV_BAR_WIDTH <= NavigationConstants.NAV_BAR_WIDTH_RANGE[1]).assertTrue();
    });

    it('minContentWidthHasExpectedValue', 0, () => {
      expect(NavigationConstants.MIN_CONTENT_WIDTH).assertEqual(400);
    });

    it('splitModeThresholdEqualsNavBarWidthPlusMinContentWidth', 0, () => {
      expect(NavigationConstants.SPLIT_MODE_THRESHOLD).assertEqual(760);
      expect(NavigationConstants.SPLIT_MODE_THRESHOLD)
        .assertEqual(NavigationConstants.DEFAULT_NAV_BAR_WIDTH + NavigationConstants.MIN_CONTENT_WIDTH);
    });

    it('splitAspectRatioThresholdHasExpectedValue', 0, () => {
      expect(NavigationConstants.SPLIT_ASPECT_RATIO_THRESHOLD).assertEqual(1.2);
    });

    it('rootPagesContainFourEntriesInDeclaredOrder', 0, () => {
      const rootPages: string[] = NavigationConstants.ROOT_PAGES;
      expect(rootPages.length).assertEqual(4);
      expect(rootPages[0]).assertEqual('Index');
      expect(rootPages[1]).assertEqual('DatabaseView');
      expect(rootPages[2]).assertEqual('TotpView');
      expect(rootPages[3]).assertEqual('Settings');
    });

    it('rootPagesHaveNoDuplicates', 0, () => {
      const rootPages: string[] = NavigationConstants.ROOT_PAGES;
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < rootPages.length; i++) {
        unique.add(rootPages[i]);
      }
      expect(unique.size).assertEqual(rootPages.length);
    });

    it('isRootPageReturnsTrueForEveryRootPage', 0, () => {
      const rootPages: string[] = NavigationConstants.ROOT_PAGES;
      for (let i = 0; i < rootPages.length; i++) {
        expect(NavigationConstants.isRootPage(rootPages[i])).assertTrue();
      }
    });

    it('isRootPageReturnsFalseForNonRootPages', 0, () => {
      expect(NavigationConstants.isRootPage('EntryView')).assertFalse();
      expect(NavigationConstants.isRootPage('EntryEdit')).assertFalse();
      expect(NavigationConstants.isRootPage('')).assertFalse();
      expect(NavigationConstants.isRootPage('settings')).assertFalse();
      expect(NavigationConstants.isRootPage('IndexPage')).assertFalse();
    });
  });
}
