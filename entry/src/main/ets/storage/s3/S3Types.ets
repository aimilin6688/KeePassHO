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

/**
 * Multipart Upload 初始化响应
 */
export interface MultipartUploadInit {
  /**
   * Upload ID，用于后续操作
   */
  uploadId: string;

  /**
   * 对象键
   */
  key: string;

  /**
   * 存储桶名称
   */
  bucket: string;
}

/**
 * 已上传的 Part 信息
 */
export interface UploadedPart {
  /**
   * Part 编号（1-10000）
   */
  partNumber: number;

  /**
   * Part 的 ETag，用于完成上传
   */
  etag: string;

  /**
   * Part 大小（字节）
   */
  size: number;
}

/**
 * Multipart Upload 上传进度回调
 */
export interface MultipartUploadProgress {
  /**
   * 已上传字节数
   */
  uploadedBytes: number;

  /**
   * 总字节数
   */
  totalBytes: number;

  /**
   * 当前 Part 编号
   */
  currentPart: number;

  /**
   * 总 Part 数量
   */
  totalParts: number;
}

/**
 * 上传进度回调函数类型
 */
export type ProgressCallback = (progress: MultipartUploadProgress) => void;

