import { UUID, TimeStamp, Binary } from './KdbxTypes';

/**
 * 内存保护设置接口
 * 定义哪些字段需要在内存中进行保护
 */
export interface MemoryProtection {
  /**
   * 是否保护标题
   */
  protectTitle: boolean;

  /**
   * 是否保护用户名
   */
  protectUserName: boolean;

  /**
   * 是否保护密码
   */
  protectPassword: boolean;

  /**
   * 是否保护URL
   */
  protectURL: boolean;

  /**
   * 是否保护备注
   */
  protectNotes: boolean;
}

/**
 * 数据库元数据实体定义
 * 包含数据库的配置信息和全局设置
 */
export interface KdbxMeta {
  /**
   * 生成器
   * 标识创建此数据库的应用程序
   */
  generator: string;

  /**
   * 头部哈希
   * 用于验证头部数据的完整性
   */
  headerHash: Binary;

  /**
   * 数据库名称
   */
  databaseName: string;

  /**
   * 数据库描述
   */
  databaseDescription?: string;

  /**
   * 数据库名称修改时间
   */
  databaseNameChanged: TimeStamp;

  /**
   * 历史维护天数
   * 定义条目历史记录的保留时间
   */
  maintenanceHistoryDays: number;

  /**
   * 回收站是否启用
   */
  recycleBinEnabled: boolean;

  /**
   * 回收站UUID
   */
  recycleBinUUID?: UUID;

  /**
   * 回收站修改时间
   */
  recycleBinChanged: TimeStamp;

  /**
   * 条目模板组UUID
   */
  entryTemplatesGroup?: UUID;

  /**
   * 条目模板组修改时间
   */
  entryTemplatesGroupChanged: TimeStamp;

  /**
   * 最大历史记录数
   * 每个条目最多保留的历史版本数量
   */
  historyMaxItems: number;

  /**
   * 最大历史记录大小
   * 历史记录的最大存储空间（字节）
   */
  historyMaxSize: number;

  /**
   * 最后选择的组
   */
  lastSelectedGroup: UUID;

  /**
   * 最后可见的顶层组
   */
  lastTopVisibleGroup: UUID;

  /**
   * 内存保护设置
   */
  memoryProtection: MemoryProtection;
}
