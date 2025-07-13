/**
 * 排序方式枚举
 */
export enum SortMode {
  DEFAULT = 'DEFAULT',
  NAME = 'NAME',
  MODIFIED = 'MODIFIED',
  CREATED = 'CREATED',
}

/**
 * 排序选项接口
 */
export interface SortOption {
  type: SortMode;
  value: string;
}

/**
 * 排序相关常量
 */
export class SortConstants {
  /**
   * 排序选项
   */
  static readonly SORT_OPTIONS: SortOption[] = [
    { value: '默认排序', type: SortMode.DEFAULT },
    { value: '按名称排序', type: SortMode.NAME },
    { value: '按修改日期排序', type: SortMode.MODIFIED },
    { value: '按创建日期排序', type: SortMode.CREATED }
  ];

  /**
   * 根据值获取排序选项
   * @param value 值
   * @returns 排序选项
   */
  public static getSortOptionByType(type: SortMode): string {
    return SortConstants.SORT_OPTIONS.find((option) => option.type === type)?.value ?? SortConstants.SORT_OPTIONS[0].value;
  }
}
