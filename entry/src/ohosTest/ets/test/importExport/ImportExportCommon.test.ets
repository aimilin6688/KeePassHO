import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { Result } from '../../../../main/ets/services/importExport/common/Result';
import { ImportError, ExportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';

interface TestObject {
  name: string;
  count: number;
}

export default function ImportExportCommonTest() {
  describe('Result', () => {
    it('successShouldCreateSuccessfulResultWithValue', 0, () => {
      const result = Result.success('test value');
      expect(result.isSuccess).assertTrue();
      expect(result.value).assertEqual('test value');
      expect(result.errorCode).assertUndefined();
      expect(result.errorMessage).assertUndefined();
    });

    it('successShouldWorkWithNumberType', 0, () => {
      const numberResult = Result.success(42);
      expect(numberResult.isSuccess).assertTrue();
      expect(numberResult.value).assertEqual(42);
    });

    it('successShouldWorkWithObjectType', 0, () => {
      const obj: TestObject = { name: 'test', count: 10 };
      const objResult = Result.success<TestObject>(obj);
      expect(objResult.isSuccess).assertTrue();
      expect(objResult.value?.name).assertEqual('test');
    });

    it('successShouldWorkWithArrayType', 0, () => {
      const arr: number[] = [1, 2, 3];
      const arrResult = Result.success<number[]>(arr);
      expect(arrResult.isSuccess).assertTrue();
      expect(arrResult.value?.length).assertEqual(3);
    });

    it('failureShouldCreateFailedResultWithErrorInfo', 0, () => {
      const result = Result.failure<string>('ERROR_CODE', 'Something went wrong');
      expect(result.isSuccess).assertFalse();
      expect(result.value).assertUndefined();
      expect(result.errorCode).assertEqual('ERROR_CODE');
      expect(result.errorMessage).assertEqual('Something went wrong');
    });

    it('failureShouldWorkWithDifferentGenericTypes', 0, () => {
      const stringResult = Result.failure<string>('ERR1', 'String error');
      expect(stringResult.isSuccess).assertFalse();
      expect(stringResult.errorCode).assertEqual('ERR1');

      const numberResult = Result.failure<number>('ERR2', 'Number error');
      expect(numberResult.isSuccess).assertFalse();
      expect(numberResult.errorCode).assertEqual('ERR2');
    });
  });

  describe('ImportError', () => {
    it('shouldCreateImportErrorWithCodeAndMessage', 0, () => {
      const error = new ImportError(ImportExportErrorCode.FILE_EMPTY, '文件为空');
      expect(error.code).assertEqual(ImportExportErrorCode.FILE_EMPTY);
      expect(error.message).assertEqual('文件为空');
      expect(error.name).assertEqual('ImportError');
    });

    it('shouldBeInstanceOfError', 0, () => {
      const error = new ImportError(ImportExportErrorCode.INVALID_CSV_HEADER, '无效的CSV头');
      expect(error instanceof Error).assertTrue();
    });

    it('shouldSupportFileNotFoundErrorCode', 0, () => {
      const error = new ImportError(ImportExportErrorCode.FILE_NOT_FOUND, '文件不存在');
      expect(error.code).assertEqual(ImportExportErrorCode.FILE_NOT_FOUND);
    });

    it('shouldSupportInvalidJsonFormatErrorCode', 0, () => {
      const error = new ImportError(ImportExportErrorCode.INVALID_JSON_FORMAT, 'JSON格式无效');
      expect(error.code).assertEqual(ImportExportErrorCode.INVALID_JSON_FORMAT);
    });
  });

  describe('ExportError', () => {
    it('shouldCreateExportErrorWithCodeAndMessage', 0, () => {
      const error = new ExportError(ImportExportErrorCode.EXPORT_FAILED, '导出失败');
      expect(error.code).assertEqual(ImportExportErrorCode.EXPORT_FAILED);
      expect(error.message).assertEqual('导出失败');
      expect(error.name).assertEqual('ExportError');
    });

    it('shouldBeInstanceOfError', 0, () => {
      const error = new ExportError(ImportExportErrorCode.DATABASE_EMPTY, '数据库为空');
      expect(error instanceof Error).assertTrue();
    });

    it('shouldSupportDatabaseEmptyErrorCode', 0, () => {
      const error = new ExportError(ImportExportErrorCode.DATABASE_EMPTY, '数据库为空');
      expect(error.code).assertEqual(ImportExportErrorCode.DATABASE_EMPTY);
    });
  });

  describe('ImportExportErrorCode', () => {
    it('shouldHaveAllExpectedErrorCodes', 0, () => {
      expect(ImportExportErrorCode.FILE_NOT_FOUND).assertEqual('FILE_NOT_FOUND');
      expect(ImportExportErrorCode.FILE_READ_ERROR).assertEqual('FILE_READ_ERROR');
      expect(ImportExportErrorCode.FILE_WRITE_ERROR).assertEqual('FILE_WRITE_ERROR');
      expect(ImportExportErrorCode.UNSUPPORTED_FORMAT).assertEqual('UNSUPPORTED_FORMAT');
      expect(ImportExportErrorCode.FILE_EMPTY).assertEqual('FILE_EMPTY');
      expect(ImportExportErrorCode.INVALID_FILE_FORMAT).assertEqual('INVALID_FILE_FORMAT');
      expect(ImportExportErrorCode.INVALID_CSV_HEADER).assertEqual('INVALID_CSV_HEADER');
      expect(ImportExportErrorCode.INVALID_JSON_FORMAT).assertEqual('INVALID_JSON_FORMAT');
      expect(ImportExportErrorCode.PARSE_ERROR).assertEqual('PARSE_ERROR');
      expect(ImportExportErrorCode.EXPORT_FAILED).assertEqual('EXPORT_FAILED');
      expect(ImportExportErrorCode.DATABASE_EMPTY).assertEqual('DATABASE_EMPTY');
    });
  });
}
