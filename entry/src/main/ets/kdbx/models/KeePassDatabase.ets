import { KdbxHeader } from './KdbxHeader';
import { KdbxMeta } from './KdbxMeta';
import { PwGroup } from './PwGroup';

/**
 * KeePass数据库实体定义
 * 表示完整的KeePass数据库结构
 */
export interface KeePassDatabase {
  /**
   * 文件头部
   * 包含数据库的基本信息和加密参数
   */
  header: KdbxHeader;

  /**
   * 元数据
   * 包含数据库的配置信息和全局设置
   */
  meta: KdbxMeta;

  /**
   * 根组
   * 数据库的根级密码组，包含所有子组和条目
   */
  root: PwGroup;
}

/**
 * 导出所有相关类型
 */
export * from './KdbxTypes';
export * from './KdbxHeader';
export * from './KdbxMeta';
export * from './PwEntry';
export * from './PwGroup';
