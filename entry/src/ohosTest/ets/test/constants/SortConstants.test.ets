import { describe, expect, it } from '@ohos/hypium';
import { SortConstants, SortMode, SortOption } from '../../../../main/ets/common/constants/SortConstants';

export default function SortConstantsTest() {
  describe('SortConstants', () => {
    it('sortModeEnumHasExpectedRawValues', 0, () => {
      const defaultValue: string = SortMode.DEFAULT;
      const nameValue: string = SortMode.NAME;
      const modifiedValue: string = SortMode.MODIFIED;
      const createdValue: string = SortMode.CREATED;
      expect(defaultValue).assertEqual('DEFAULT');
      expect(nameValue).assertEqual('NAME');
      expect(modifiedValue).assertEqual('MODIFIED');
      expect(createdValue).assertEqual('CREATED');
    });

    it('sortModeEnumMembersAreUnique', 0, () => {
      const values: string[] = [SortMode.DEFAULT, SortMode.NAME, SortMode.MODIFIED, SortMode.CREATED];
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < values.length; i++) {
        unique.add(values[i]);
      }
      expect(unique.size).assertEqual(4);
    });

    it('sortOptionsContainFourEntriesInDeclaredOrder', 0, () => {
      const options: SortOption[] = SortConstants.SORT_OPTIONS;
      expect(options.length).assertEqual(4);
      expect(options[0].type).assertEqual(SortMode.DEFAULT);
      expect(options[1].type).assertEqual(SortMode.NAME);
      expect(options[2].type).assertEqual(SortMode.MODIFIED);
      expect(options[3].type).assertEqual(SortMode.CREATED);
    });

    it('sortOptionsHaveUniqueTypes', 0, () => {
      const options: SortOption[] = SortConstants.SORT_OPTIONS;
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < options.length; i++) {
        unique.add(options[i].type);
      }
      expect(unique.size).assertEqual(options.length);
    });

    it('sortOptionsHaveDefinedResourceValues', 0, () => {
      const options: SortOption[] = SortConstants.SORT_OPTIONS;
      for (let i = 0; i < options.length; i++) {
        expect(options[i].value).not().assertNull();
        expect(options[i].value).not().assertUndefined();
      }
    });

    it('getSortOptionByTypeReturnsMatchingOptionValue', 0, () => {
      expect(SortConstants.getSortOptionByType(SortMode.DEFAULT) === SortConstants.SORT_OPTIONS[0].value).assertTrue();
      expect(SortConstants.getSortOptionByType(SortMode.NAME) === SortConstants.SORT_OPTIONS[1].value).assertTrue();
      expect(SortConstants.getSortOptionByType(SortMode.MODIFIED) === SortConstants.SORT_OPTIONS[2].value).assertTrue();
      expect(SortConstants.getSortOptionByType(SortMode.CREATED) === SortConstants.SORT_OPTIONS[3].value).assertTrue();
    });

    it('getSortOptionByTypeFallsBackToDefaultForUnknownType', 0, () => {
      const unknownRaw: string = 'UNKNOWN';
      const unknownType: SortMode = unknownRaw as SortMode;
      const result: Resource = SortConstants.getSortOptionByType(unknownType);
      expect(result === SortConstants.SORT_OPTIONS[0].value).assertTrue();
    });
  });
}
