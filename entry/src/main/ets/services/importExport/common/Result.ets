/**
 * 操作结果封装类
 */
export class Result<T> {
  readonly isSuccess: boolean;
  readonly value: T | undefined;
  readonly errorCode: string | undefined;
  readonly errorMessage: string | undefined;

  private constructor(isSuccess: boolean, value: T | undefined, errorCode?: string, errorMessage?: string) {
    this.isSuccess = isSuccess;
    this.value = value;
    this.errorCode = errorCode;
    this.errorMessage = errorMessage;
  }

  /**
   * 创建成功结果
   */
  static success<T>(value: T): Result<T> {
    return new Result(true, value);
  }

  /**
   * 创建失败结果
   */
  static failure<T>(errorCode: string, errorMessage: string): Result<T> {
    return new Result<T>(false, undefined, errorCode, errorMessage);
  }
}
