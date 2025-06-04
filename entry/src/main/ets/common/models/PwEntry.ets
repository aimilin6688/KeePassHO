import { Binary, Timestamp, UUID } from './KdbxTypes';

/**
 * 密码条目实体定义
 * 表示数据库中的单个密码条目
 */
export interface PwEntry {
  /**
   * 条目唯一标识
   */
  uuid: UUID;

  /**
   * 条目标题
   */
  title: string;

  /**
   * 用户名
   */
  username?: string;

  /**
   * 密码
   */
  password?: string;

  /**
   * URL地址
   */
  url?: string;

  /**
   * 备注信息
   */
  notes?: string;

  /**
   * 图标
   * 可以是Resource资源或字符串路径
   */
  icon?: Resource | string;

  /**
   * 标签列表
   */
  tags?: string[];

  /**
   * 创建时间
   */
  createdAt: Timestamp;

  /**
   * 修改时间
   */
  updatedAt: Timestamp;

  /**
   * 最后访问时间
   */
  lastAccessTime?: Timestamp;

  /**
   * 过期时间
   */
  expiryTime?: Timestamp;

  /**
   * 自定义字段
   * 键值对形式存储的额外信息
   */
  customFields?: Map<string, string>;

  /**
   * 附件
   * 键为附件名称，值为二进制数据
   */
  binaries?: Map<string, Binary>;

  /**
   * 历史记录
   * 保存条目的历史版本
   */
  history?: PwEntry[];
}
