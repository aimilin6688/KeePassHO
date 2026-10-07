import { describe, expect, it } from '@ohos/hypium';
import { UIConstants } from '../../../../main/ets/common/constants/UIConstants';

export default function UIConstantsTest() {
  describe('UIConstants', () => {
    it('widthThresholdConstantsHaveExpectedValues', 0, () => {
      expect(UIConstants.CONTENT_MAX_WIDTH_THRESHOLD).assertEqual(600);
      expect(UIConstants.DIALOG_MAX_WIDTH).assertEqual(600);
      expect(UIConstants.DIALOG_MAX_HEIGHT_RATIO).assertEqual('80%');
    });

    it('cornerRadiusConstantsHaveExpectedValues', 0, () => {
      expect(UIConstants.CORNER_RADIUS_SMALL).assertEqual(8);
      expect(UIConstants.CORNER_RADIUS_MEDIUM).assertEqual(12);
      expect(UIConstants.CORNER_RADIUS_LARGE).assertEqual(16);
    });

    it('cornerRadiusConstantsAreOrderedSmallToLarge', 0, () => {
      expect(UIConstants.CORNER_RADIUS_SMALL < UIConstants.CORNER_RADIUS_MEDIUM).assertTrue();
      expect(UIConstants.CORNER_RADIUS_MEDIUM < UIConstants.CORNER_RADIUS_LARGE).assertTrue();
    });

    it('iconSizeConstantsHaveExpectedValues', 0, () => {
      expect(UIConstants.ICON_SIZE_SMALL).assertEqual(16);
      expect(UIConstants.ICON_SIZE_MEDIUM).assertEqual(24);
      expect(UIConstants.ICON_SIZE_LARGE).assertEqual(32);
    });

    it('iconSizeConstantsAreOrderedSmallToLarge', 0, () => {
      expect(UIConstants.ICON_SIZE_SMALL < UIConstants.ICON_SIZE_MEDIUM).assertTrue();
      expect(UIConstants.ICON_SIZE_MEDIUM < UIConstants.ICON_SIZE_LARGE).assertTrue();
    });

    it('shadowConstantsHaveExpectedValues', 0, () => {
      expect(UIConstants.SHADOW_RADIUS).assertEqual(20);
      expect(UIConstants.SHADOW_OFFSET_X).assertEqual(0);
      expect(UIConstants.SHADOW_OFFSET_Y).assertEqual(4);
    });

    it('paddingConstantsHaveExpectedValues', 0, () => {
      expect(UIConstants.PADDING_WIDE).assertEqual(24);
      expect(UIConstants.PADDING_NARROW).assertEqual(16);
      expect(UIConstants.PADDING_WIDE > UIConstants.PADDING_NARROW).assertTrue();
    });

    it('componentHeightConstantsHaveExpectedValues', 0, () => {
      expect(UIConstants.LIST_ITEM_HEIGHT).assertEqual(48);
      expect(UIConstants.BUTTON_HEIGHT).assertEqual(44);
      expect(UIConstants.INPUT_HEIGHT).assertEqual(44);
      expect(UIConstants.DIVIDER_HEIGHT).assertEqual(1);
    });

    it('buttonAndInputShareSameHeight', 0, () => {
      expect(UIConstants.BUTTON_HEIGHT === UIConstants.INPUT_HEIGHT).assertTrue();
    });
  });
}
