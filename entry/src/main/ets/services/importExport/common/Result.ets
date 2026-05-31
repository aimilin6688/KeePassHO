/**
 * 操作结果封装类
 */
export class Result<T> {
  readonly isSuccess: boolean;
  readonly value?: T;
  readonly errorCode?: string;
  readonly errorMessage?: string;

  private constructor(isSuccess: boolean, value?: T, errorCode?: string, errorMessage?: string) {
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
    return new Result(false, undefined, errorCode, errorMessage);
  }
}
