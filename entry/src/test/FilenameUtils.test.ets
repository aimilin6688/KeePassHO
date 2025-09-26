import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import {FilenameUtils} from "../main/ets/common/utils/FilenameUtils"
import DateUtils from "../main/ets/common/utils/DateUtils"


export default function FilenameUtilsTest() {
  describe('FilenameUtils', () => {
    // 保存原始getCurrentDate函数
    const mockDate = DateUtils.getCurrentDate();

    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('getFileName extracts filename from path correctly', 0, () => {
      // 测试正常路径提取文件名
      expect(FilenameUtils.getFileName('/path/to/file.txt')).assertEqual('file.txt');
      expect(FilenameUtils.getFileName('file.txt')).assertEqual('file.txt');
      expect(FilenameUtils.getFileName('/path/to/document.pdf')).assertEqual('document.pdf');
    });

    it('getFileName handles edge cases', 0, () => {
      // 测试空路径
      expect(FilenameUtils.getFileName('')).assertEqual('');
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
      // 测试正常的文件名添加日期
      expect(FilenameUtils.fileNameAppendDate('test.txt')).assertEqual(`test_${mockDate}.txt`);
      expect(FilenameUtils.fileNameAppendDate('document.pdf')).assertEqual(`document_${mockDate}.pdf`);
      expect(FilenameUtils.fileNameAppendDate('archive.tar.gz')).assertEqual(`archive.tar_${mockDate}.gz`);
    });

    it('fileNameAppendDate replaces existing date at end of filename', 0, () => {
      // 测试文件名末尾已有日期时替换为当前日期
      expect(FilenameUtils.fileNameAppendDate('backup_20230101.txt')).assertEqual(`backup_${mockDate}.txt`);
      expect(FilenameUtils.fileNameAppendDate('log_20231201')).assertEqual(`log_${mockDate}`);
      expect(FilenameUtils.fileNameAppendDate('data_20221115.json')).assertEqual(`data_${mockDate}.json`);
    });

    it('fileNameAppendDate handles edge cases', 0, () => {
      // 测试空文件名
      expect(FilenameUtils.fileNameAppendDate('')).assertEqual(`${mockDate}`);
      // 测试没有后缀的文件名
      expect(FilenameUtils.fileNameAppendDate('README')).assertEqual(`README_${mockDate}`);
      // 测试以点结尾的文件名
      expect(FilenameUtils.fileNameAppendDate('file.')).assertEqual(`file_${mockDate}.`);
    });

    it('getFileExt extracts file extension correctly', 0, () => {
      // 测试正常提取文件后缀
      expect(FilenameUtils.getFileExt('test.txt')).assertEqual('txt');
      expect(FilenameUtils.getFileExt('document.pdf')).assertEqual('pdf');
      expect(FilenameUtils.getFileExt('archive.tar.gz')).assertEqual('gz');
    });

    it('getFileExt handles edge cases', 0, () => {
      // 测试没有后缀的文件名
      expect(FilenameUtils.getFileExt('README')).assertEqual('');
      // 测试空文件名
      expect(FilenameUtils.getFileExt('')).assertEqual('');
    });

    it('hasSuffix checks file suffix correctly', 0, () => {
      // 测试文件名有指定后缀
      expect(FilenameUtils.hasSuffix('test.txt', ['.txt', '.pdf'])).assertTrue();
      expect(FilenameUtils.hasSuffix('document.pdf', ['.txt', '.pdf'])).assertTrue();
      // 测试文件名没有指定后缀
      expect(FilenameUtils.hasSuffix('test.doc', ['.txt', '.pdf'])).assertFalse();
    });

    it('hasSuffix handles edge cases', 0, () => {
      // 测试空后缀数组
      expect(FilenameUtils.hasSuffix('test.txt', [])).assertTrue();
      expect(FilenameUtils.hasSuffix('test.txt', undefined)).assertTrue();
      // 测试空文件名
      expect(FilenameUtils.hasSuffix('', ['.txt'])).assertTrue();
    });

    it('getFilePath combines paths correctly', 0, () => {
      // 测试正常路径组合
      expect(FilenameUtils.getFilePath('path', 'to', 'file.txt')).assertEqual('path/to/file.txt');
      expect(FilenameUtils.getFilePath('/path/', '/to/', '/file.txt')).assertEqual('path/to/file.txt');
    });

    it('getFilePath handles edge cases', 0, () => {
      // 测试空路径
      expect(FilenameUtils.getFilePath()).assertEqual('');
      // 测试包含空字符串的路径
      expect(FilenameUtils.getFilePath('path', '', 'file.txt')).assertEqual('path/file.txt');
    });
  });
}