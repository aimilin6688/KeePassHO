import { describe, expect, it } from '@ohos/hypium';
import { FilenameUtils } from '../../../../main/ets/common/utils/FilenameUtils';
import { DateUtils } from '../../../../main/ets/common/utils/DateUtils';

/**
 * FilenameUtils 单元测试。
 *
 * 覆盖：文件名提取与 URL 解码、文件名/后缀替换、日期追加与既有日期替换、
 * 后缀判定、扩展名提取、图片格式判断、多段路径拼接。
 */
export default function FilenameUtilsTest() {
  describe('FilenameUtilsTest', () => {
    it('getFileName returns empty string for empty input', 0, () => {
      expect(FilenameUtils.getFileName('')).assertEqual('');
    });

    it('getFileName extracts the last path segment', 0, () => {
      expect(FilenameUtils.getFileName('/a/b/file.kdbx')).assertEqual('file.kdbx');
      expect(FilenameUtils.getFileName('file.kdbx')).assertEqual('file.kdbx');
    });

    it('getFileName returns empty string for a trailing slash (regex anchors at end)', 0, () => {
      expect(FilenameUtils.getFileName('/a/b/')).assertEqual('');
    });

    it('getFileName decodes URI-encoded names', 0, () => {
      expect(FilenameUtils.getFileName('%E6%95%B0%E6%8D%AE%E5%BA%93.kdbx')).assertEqual('数据库.kdbx');
    });

    it('replaceFileName swaps the last segment', 0, () => {
      expect(FilenameUtils.replaceFileName('/a/b/file.kdbx', 'new.kdbx')).assertEqual('/a/b/new.kdbx');
      expect(FilenameUtils.replaceFileName('file.kdbx', 'new.kdbx')).assertEqual('new.kdbx');
    });

    it('replaceExt appends ext when name has none', 0, () => {
      expect(FilenameUtils.replaceExt('', '.kdbx')).assertEqual('');
      expect(FilenameUtils.replaceExt('name', '.kdbx')).assertEqual('name.kdbx');
    });

    it('replaceExt trims a trailing dot before appending', 0, () => {
      expect(FilenameUtils.replaceExt('name.', '.kdbx')).assertEqual('name.kdbx');
    });

    it('replaceExt replaces only the last extension', 0, () => {
      expect(FilenameUtils.replaceExt('name.old', '.kdbx')).assertEqual('name.kdbx');
      expect(FilenameUtils.replaceExt('a.b.c', '.x')).assertEqual('a.b.x');
    });

    it('fileNameAppendDate with empty name returns the current date', 0, () => {
      expect(FilenameUtils.fileNameAppendDate('')).assertEqual(DateUtils.getCurrentDate());
    });

    it('fileNameAppendDate appends today for a plain name', 0, () => {
      const today = DateUtils.getCurrentDate();
      expect(FilenameUtils.fileNameAppendDate('db')).assertEqual(`db_${today}`);
    });

    it('fileNameAppendDate replaces an existing valid trailing date', 0, () => {
      const today = DateUtils.getCurrentDate();
      expect(FilenameUtils.fileNameAppendDate('db_20260101')).assertEqual(`db_${today}`);
    });

    it('fileNameAppendDate keeps extension while replacing the date', 0, () => {
      const today = DateUtils.getCurrentDate();
      expect(FilenameUtils.fileNameAppendDate('db.kdbx')).assertEqual(`db_${today}.kdbx`);
      expect(FilenameUtils.fileNameAppendDate('db_20260101.kdbx')).assertEqual(`db_${today}.kdbx`);
    });

    it('fileNameAppendDate treats invalid trailing digits as a plain name', 0, () => {
      const today = DateUtils.getCurrentDate();
      expect(FilenameUtils.fileNameAppendDate('db_99999999')).assertEqual(`db_99999999_${today}`);
      expect(FilenameUtils.fileNameAppendDate('db_20261301')).assertEqual(`db_20261301_${today}`);
    });

    it('hasSuffix returns true for missing/empty suffix array or empty name', 0, () => {
      expect(FilenameUtils.hasSuffix('f.kdbx', undefined)).assertTrue();
      expect(FilenameUtils.hasSuffix('f.kdbx', [])).assertTrue();
      expect(FilenameUtils.hasSuffix('', ['.kdbx'])).assertTrue();
    });

    it('hasSuffix matches any suffix in the array', 0, () => {
      expect(FilenameUtils.hasSuffix('f.kdbx', ['.kdbx'])).assertTrue();
      expect(FilenameUtils.hasSuffix('f.kdbx', ['.xml', '.kdbx'])).assertTrue();
      expect(FilenameUtils.hasSuffix('f.xml', ['.kdbx'])).assertFalse();
    });

    it('getFileExt returns empty for empty name or no dot', 0, () => {
      expect(FilenameUtils.getFileExt('')).assertEqual('');
      expect(FilenameUtils.getFileExt('noext')).assertEqual('');
    });

    it('getFileExt returns the last extension segment', 0, () => {
      expect(FilenameUtils.getFileExt('a.tar.gz')).assertEqual('gz');
      expect(FilenameUtils.getFileExt('.hidden')).assertEqual('hidden');
    });

    it('isImage matches known image extensions case-insensitively', 0, () => {
      expect(FilenameUtils.isImage('photo.JPG')).assertTrue();
      expect(FilenameUtils.isImage('photo.jpg')).assertTrue();
      expect(FilenameUtils.isImage('photo.heic')).assertTrue();
      expect(FilenameUtils.isImage('icon.svg')).assertTrue();
    });

    it('isImage rejects non-image files', 0, () => {
      expect(FilenameUtils.isImage('db.kdbx')).assertFalse();
      expect(FilenameUtils.isImage('')).assertFalse();
      expect(FilenameUtils.isImage('noext')).assertFalse();
    });

    it('getFilePath joins segments with slash', 0, () => {
      expect(FilenameUtils.getFilePath()).assertEqual('');
      expect(FilenameUtils.getFilePath('a', 'b')).assertEqual('a/b');
      expect(FilenameUtils.getFilePath('a', 'b', 'c')).assertEqual('a/b/c');
    });

    it('getFilePath trims slashes and drops empty segments', 0, () => {
      expect(FilenameUtils.getFilePath('/a/', '/b/')).assertEqual('a/b');
      expect(FilenameUtils.getFilePath('a', '', 'b')).assertEqual('a/b');
    });
  });
}
