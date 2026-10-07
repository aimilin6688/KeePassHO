import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { StringUtils } from '../../../../main/ets/common/utils/StringUtils';

export default function StringUtilsTest() {
  describe('StringUtils', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    // ---------------- removeStart ----------------
    it('removeStart removes prefix when present', 0, () => {
      expect(StringUtils.removeStart('hello world', 'hello ')).assertEqual('world');
    });

    it('removeStart returns original when prefix not matched', 0, () => {
      expect(StringUtils.removeStart('hello world', 'world')).assertEqual('hello world');
    });

    it('removeStart returns original when start is empty', 0, () => {
      expect(StringUtils.removeStart('hello', '')).assertEqual('hello');
    });

    it('removeStart returns original when str is empty', 0, () => {
      expect(StringUtils.removeStart('', 'x')).assertEqual('');
    });

    it('removeStart removes only the first occurrence', 0, () => {
      expect(StringUtils.removeStart('aaa', 'a')).assertEqual('aa');
    });

    it('removeStart returns original when start longer than str', 0, () => {
      expect(StringUtils.removeStart('ab', 'abc')).assertEqual('ab');
    });

    it('removeStart handles full string equal to prefix', 0, () => {
      expect(StringUtils.removeStart('abc', 'abc')).assertEqual('');
    });

    // ---------------- getTagContent ----------------
    it('getTagContent extracts tag content', 0, () => {
      expect(StringUtils.getTagContent('<name>John</name>', 'name')).assertEqual('John');
    });

    it('getTagContent is case insensitive', 0, () => {
      expect(StringUtils.getTagContent('<NAME>John</NAME>', 'name')).assertEqual('John');
    });

    it('getTagContent returns empty for missing tag', 0, () => {
      expect(StringUtils.getTagContent('<other>John</other>', 'name')).assertEqual('');
    });

    it('getTagContent returns empty for empty content', 0, () => {
      expect(StringUtils.getTagContent('<name></name>', 'name')).assertEqual('');
    });

    it('getTagContent returns empty for empty xml', 0, () => {
      expect(StringUtils.getTagContent('', 'name')).assertEqual('');
    });

    it('getTagContent extracts content containing angle-like chars', 0, () => {
      expect(StringUtils.getTagContent('<a>x<y</a>', 'a')).assertEqual('x<y');
    });

    it('getTagContent extracts first match only', 0, () => {
      const xml = '<v>1</v><v>2</v>';
      expect(StringUtils.getTagContent(xml, 'v')).assertEqual('1');
    });

    // ---------------- isNotBlank ----------------
    it('isNotBlank returns true for non-empty string', 0, () => {
      expect(StringUtils.isNotBlank('hello')).assertTrue();
    });

    it('isNotBlank returns false for empty string', 0, () => {
      expect(StringUtils.isNotBlank('')).assertFalse();
    });

    it('isNotBlank returns false for whitespace only', 0, () => {
      expect(StringUtils.isNotBlank('   ')).assertFalse();
    });

    it('isNotBlank returns false for tab only', 0, () => {
      expect(StringUtils.isNotBlank('\t\t')).assertFalse();
    });

    it('isNotBlank returns true for string with surrounding spaces', 0, () => {
      expect(StringUtils.isNotBlank('  x  ')).assertTrue();
    });

    // ---------------- getFirstLetter ----------------
    it('getFirstLetter returns uppercased letter for lowercase word', 0, () => {
      expect(StringUtils.getFirstLetter('abc')).assertEqual('A');
    });

    it('getFirstLetter returns uppercased letter for uppercase word', 0, () => {
      expect(StringUtils.getFirstLetter('Apple')).assertEqual('A');
    });

    it('getFirstLetter returns # for empty string', 0, () => {
      expect(StringUtils.getFirstLetter('')).assertEqual('#');
    });

    it('getFirstLetter returns # for digit', 0, () => {
      expect(StringUtils.getFirstLetter('123')).assertEqual('#');
    });

    it('getFirstLetter returns # for special char', 0, () => {
      expect(StringUtils.getFirstLetter('@test')).assertEqual('#');
    });

    it('getFirstLetter returns pinyin initial for Chinese', 0, () => {
      const letter = StringUtils.getFirstLetter('中国');
      expect(letter).assertEqual('Z');
    });

    it('getFirstLetter returns single char for single Chinese char', 0, () => {
      const letter = StringUtils.getFirstLetter('中');
      expect(letter.length).assertEqual(1);
    });

    it('getFirstLetter returns uppercase for lowercase z', 0, () => {
      expect(StringUtils.getFirstLetter('zebra')).assertEqual('Z');
    });

    // ---------------- getPinyin ----------------
    it('getPinyin converts Chinese to pinyin without tone', 0, () => {
      expect(StringUtils.getPinyin('中国')).assertEqual('zhongguo');
    });

    it('getPinyin returns empty for empty string', 0, () => {
      expect(StringUtils.getPinyin('')).assertEqual('');
    });

    it('getPinyin returns original for ascii', 0, () => {
      expect(StringUtils.getPinyin('abc')).assertEqual('abc');
    });

    it('getPinyin converts mixed content', 0, () => {
      const result = StringUtils.getPinyin('中a');
      expect(result.length > 0).assertTrue();
    });

    // ---------------- formatFileSize ----------------
    it('formatFileSize returns B for zero', 0, () => {
      expect(StringUtils.formatFileSize(0)).assertEqual('0 B');
    });

    it('formatFileSize returns B for size < 1024', 0, () => {
      expect(StringUtils.formatFileSize(512)).assertEqual('512 B');
      expect(StringUtils.formatFileSize(1023)).assertEqual('1023 B');
    });

    it('formatFileSize returns KB for size in KB range', 0, () => {
      expect(StringUtils.formatFileSize(1024)).assertEqual('1.0 KB');
      expect(StringUtils.formatFileSize(1536)).assertEqual('1.5 KB');
    });

    it('formatFileSize returns MB for size in MB range', 0, () => {
      expect(StringUtils.formatFileSize(1048576)).assertEqual('1.0 MB');
      expect(StringUtils.formatFileSize(1572864)).assertEqual('1.5 MB');
    });

    it('formatFileSize returns GB for size in GB range', 0, () => {
      expect(StringUtils.formatFileSize(1073741824)).assertEqual('1.0 GB');
    });

    it('formatFileSize returns - for negative size', 0, () => {
      expect(StringUtils.formatFileSize(-1)).assertEqual('-');
      expect(StringUtils.formatFileSize(-1024)).assertEqual('-');
    });

    it('formatFileSize boundary at 1024', 0, () => {
      expect(StringUtils.formatFileSize(1023)).assertEqual('1023 B');
      expect(StringUtils.formatFileSize(1024)).assertEqual('1.0 KB');
    });

    it('formatFileSize boundary at 1MB', 0, () => {
      expect(StringUtils.formatFileSize(1048575)).assertEqual('1024.0 KB');
      expect(StringUtils.formatFileSize(1048576)).assertEqual('1.0 MB');
    });
  });
}
