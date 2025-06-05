import { TimeStamp, UUID } from './KdbxTypes';
import { PwEntry } from './PwEntry';

/**
 * 密码组实体定义
 * 表示数据库中的密码分组，可以包含子组和密码条目
 */
export interface PwGroup {
  /**
   * 组唯一标识
   */
  uuid: UUID;

  /**
   * 组标题
   */
  title: string;

  /**
   * 图标
   * 可以是Resource资源或字符串路径
   */
  icon?: Resource | string;

  /**
   * 备注信息
   */
  notes?: string;

  /**
   * 创建时间
   */
  createdAt: TimeStamp;

  /**
   * 修改时间
   */
  updatedAt: TimeStamp;

  /**
   * 最后访问时间
   */
  lastAccessTime?: TimeStamp;

  /**
   * 过期时间
   */
  expiryTime?: TimeStamp;

  /**
   * 组内密码条目
   */
  entries?: PwEntry[];

  /**
   * 子组列表
   */
  groups?: PwGroup[];

  /**
   * 是否展开显示
   * 用于UI展示状态
   */
  isExpanded?: boolean;
}