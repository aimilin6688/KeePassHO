/**
 * S3 Multipart Upload 配置常量
 */
export class S3MultipartConfig {
  /**
   * 最小分块大小：5MB（S3 标准）
   * 所有非最后一个 part 必须至少 5MB
   */
  static readonly MIN_PART_SIZE = 5 * 1024 * 1024; // 5MB

  /**
   * 推荐分块大小：8MB
   * - 平衡内存占用和网络效率
   * - 适合移动设备网络环境
   */
  static readonly RECOMMENDED_PART_SIZE = 8 * 1024 * 1024; // 8MB

  /**
   * Multipart 上传阈值：5MB
   * 文件 >= 5MB 时启用 multipart upload
   */
  static readonly MULTIPART_THRESHOLD = 5 * 1024 * 1024; // 5MB

  /**
   * 最大重试次数
   */
  static readonly MAX_RETRY_COUNT = 3;
}
