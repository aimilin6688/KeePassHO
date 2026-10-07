import { describe, expect, it } from '@ohos/hypium';
import { SettingDialogConstants } from '../../../../main/ets/common/constants/SettingDialogConstants';

export default function SettingDialogConstantsTest() {
  describe('SettingDialogConstants', () => {
    it('dialogSizeConstantsHaveExpectedValues', 0, () => {
      expect(SettingDialogConstants.DIALOG_MAX_WIDTH).assertEqual(700);
      expect(SettingDialogConstants.DIALOG_MAX_HEIGHT_RATIO).assertEqual('80%');
    });

    it('headerAndButtonConstantsHaveExpectedValues', 0, () => {
      expect(SettingDialogConstants.HEADER_HEIGHT).assertEqual(56);
      expect(SettingDialogConstants.CLOSE_BUTTON_SIZE).assertEqual(24);
      expect(SettingDialogConstants.CLOSE_BUTTON_SIZE < SettingDialogConstants.HEADER_HEIGHT).assertTrue();
    });

    it('cornerRadiusConstantHasExpectedValue', 0, () => {
      expect(SettingDialogConstants.CORNER_RADIUS).assertEqual(16);
    });

    it('paddingConstantsHaveExpectedValues', 0, () => {
      expect(SettingDialogConstants.PADDING_WIDE).assertEqual(24);
      expect(SettingDialogConstants.PADDING_NARROW).assertEqual(16);
      expect(SettingDialogConstants.PADDING_WIDE > SettingDialogConstants.PADDING_NARROW).assertTrue();
    });

    it('titleFontConstantHasExpectedValue', 0, () => {
      expect(SettingDialogConstants.TITLE_FONT_SIZE).assertEqual(18);
    });

    it('shadowConstantsHaveExpectedValues', 0, () => {
      expect(SettingDialogConstants.SHADOW_RADIUS).assertEqual(20);
      expect(SettingDialogConstants.SHADOW_OFFSET_Y).assertEqual(4);
    });
  });
}
