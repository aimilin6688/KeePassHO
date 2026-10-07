import { describe, expect, it } from '@ohos/hypium';
import { ThemeConstants, ThemeMode, ThemeOption } from '../../../../main/ets/common/constants/ThemeConstants';

export default function ThemeConstantsTest() {
  describe('ThemeConstants', () => {
    it('themeModeEnumHasExpectedRawValues', 0, () => {
      const systemValue: string = ThemeMode.SYSTEM;
      const lightValue: string = ThemeMode.LIGHT;
      const darkValue: string = ThemeMode.DARK;
      expect(systemValue).assertEqual('SYSTEM');
      expect(lightValue).assertEqual('LIGHT');
      expect(darkValue).assertEqual('DARK');
    });

    it('themeModeEnumMembersAreUnique', 0, () => {
      const values: string[] = [ThemeMode.SYSTEM, ThemeMode.LIGHT, ThemeMode.DARK];
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < values.length; i++) {
        unique.add(values[i]);
      }
      expect(unique.size).assertEqual(3);
    });

    it('themeOptionsContainThreeEntriesInDeclaredOrder', 0, () => {
      const options: ThemeOption[] = ThemeConstants.THEME_OPTIONS;
      expect(options.length).assertEqual(3);
      expect(options[0].type).assertEqual(ThemeMode.SYSTEM);
      expect(options[1].type).assertEqual(ThemeMode.LIGHT);
      expect(options[2].type).assertEqual(ThemeMode.DARK);
    });

    it('themeOptionsHaveUniqueTypes', 0, () => {
      const options: ThemeOption[] = ThemeConstants.THEME_OPTIONS;
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < options.length; i++) {
        unique.add(options[i].type);
      }
      expect(unique.size).assertEqual(options.length);
    });

    it('themeOptionsHaveDefinedResourceValues', 0, () => {
      const options: ThemeOption[] = ThemeConstants.THEME_OPTIONS;
      for (let i = 0; i < options.length; i++) {
        expect(options[i].value).not().assertNull();
        expect(options[i].value).not().assertUndefined();
      }
    });

    it('getThemeOptionByTypeReturnsMatchingOptionValue', 0, () => {
      expect(ThemeConstants.getThemeOptionByType(ThemeMode.SYSTEM) === ThemeConstants.THEME_OPTIONS[0].value).assertTrue();
      expect(ThemeConstants.getThemeOptionByType(ThemeMode.LIGHT) === ThemeConstants.THEME_OPTIONS[1].value).assertTrue();
      expect(ThemeConstants.getThemeOptionByType(ThemeMode.DARK) === ThemeConstants.THEME_OPTIONS[2].value).assertTrue();
    });

    it('getThemeOptionByTypeFallsBackToSystemForUnknownType', 0, () => {
      const unknownRaw: string = 'UNKNOWN';
      const unknownType: ThemeMode = unknownRaw as ThemeMode;
      const result: Resource = ThemeConstants.getThemeOptionByType(unknownType);
      expect(result === ThemeConstants.THEME_OPTIONS[0].value).assertTrue();
    });
  });
}
