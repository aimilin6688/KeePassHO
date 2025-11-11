import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import {FilenameUtils} from '../../../../main/ets/common/utils/FilenameUtils';
import DateUtils from '../../../../main/ets/common/utils/DateUtils';

export default function FileUtilsTest() {
  describe('FileUtils', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('replaceExt replaces file extension correctly', 0, () => {
      // 测试正常的文件名替换后缀
      expect(FilenameUtils.replaceExt('test.txt', '.kdbx')).assertEqual('test.kdbx');
      expect(FilenameUtils.replaceExt('document.pdf', '.docx')).assertEqual('document.docx');
      expect(FilenameUtils.replaceExt('archive.tar.gz', '.zip')).assertEqual('archive.tar.zip');
    });

    it('replaceExt handles edge cases', 0, () => {
      // 测试没有后缀的文件名
      expect(FilenameUtils.replaceExt('README', '.txt')).assertEqual('README.txt');
      // 测试以点结尾的文件名
      expect(FilenameUtils.replaceExt('file.', '.txt')).assertEqual('file.txt');
      // 测试空文件名
      expect(FilenameUtils.replaceExt('', '.txt')).assertEqual('');
    });

    it('fileNameAppendDate appends date to filename correctly', 0, () => {
      // 保存原始getCurrentDate函数
      const originalGetCurrentDate = DateUtils.getCurrentDate();
      // 测试正常的文件名添加日期
      expect(FilenameUtils.fileNameAppendDate('test.txt')).assertEqual(`test_${originalGetCurrentDate}.txt`);
      expect(FilenameUtils.fileNameAppendDate('document.pdf')).assertEqual(`document_${originalGetCurrentDate}.pdf`);
      expect(FilenameUtils.fileNameAppendDate('archive.tar.gz')).assertEqual(`archive.tar_${originalGetCurrentDate}.gz`);
    });

    it('fileNameAppendDate handles edge cases', 0, () => {
      // 保存原始getCurrentDate函数
      const originalGetCurrentDate = DateUtils.getCurrentDate();
        // 测试没有后缀的文件名
        expect(FilenameUtils.fileNameAppendDate('README')).assertEqual(`README_${originalGetCurrentDate}`);
        // 测试以点结尾的文件名
        expect(FilenameUtils.fileNameAppendDate('file.')).assertEqual(`file_${originalGetCurrentDate}.`);
        // 测试空文件名
        expect(FilenameUtils.fileNameAppendDate('')).assertEqual(`${originalGetCurrentDate}`);
    });
  });
}