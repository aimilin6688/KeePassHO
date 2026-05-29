/**
 * S3 对象信息
 */
export interface S3Object {
  /**
   * 对象键（路径）
   */
  key: string;

  /**
   * 大小（字节）
   */
  size: number;

  /**
   * 最后修改时间戳（毫秒）
   */
  lastModified: number;

  /**
   * ETag
   */
  etag: string;
}

/**
 * S3 存储桶信息
 */
export interface S3Bucket {
  /**
   * 存储桶名称
   */
  name: string;

  /**
   * 创建时间戳（毫秒）
   */
  creationDate: number;
}

/**
 * S3 API 响应结果
 */
export interface S3Result<T> {
  /**
   * 是否成功
   */
  success: boolean;

  /**
   * HTTP 状态码
   */
  statusCode: number;

  /**
   * 错误消息
   */
  message?: string;

  /**
   * 响应数据
   */
  data?: T;

  /**
   * 响应头
   */
  headers?: Record<string, string>;
}

/**
 * S3 错误信息
 */
export interface S3Error {
  code: string;
  message: string;
  resourceId?: string;
  resource?: string;
}
