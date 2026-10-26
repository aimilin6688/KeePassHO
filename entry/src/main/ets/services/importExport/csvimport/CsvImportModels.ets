/**
 * CSV 导入目标字段枚举
 * 对应 KeePassXC CSV 导入的目标列语义
 */
export enum CsvTargetField {
  GROUP = 'GROUP',
  TITLE = 'TITLE',
  USERNAME = 'USERNAME',
  PASSWORD = 'PASSWORD',
  URL = 'URL',
  NOTES = 'NOTES',
  TOTP = 'TOTP',
  TAGS = 'TAGS',
  ICON = 'ICON',
  LAST_MODIFIED = 'LAST_MODIFIED',
  CREATED = 'CREATED'
}

/**
 * CSV 解析结果
 */
export interface CsvParseResult {
  /** 解析出的所有数据行（全空行已跳过，短行已补齐到最大列数） */
  rows: string[][];
  /** 最大列数 */
  columnCount: number;
  /** 引号是否全部正确闭合 */
  isGood: boolean;
}
