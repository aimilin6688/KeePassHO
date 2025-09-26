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
  value: Resource;
}

/**
 * 排序相关常量
 */
export class SortConstants {
  /**
   * 排序选项
   */
  static readonly SORT_OPTIONS: SortOption[] = [
    { value: $r('app.string.SortConstants_default'), type: SortMode.DEFAULT },
    { value: $r('app.string.SortConstants_name'), type: SortMode.NAME },
    { value: $r('app.string.SortConstants_modified'), type: SortMode.MODIFIED },
    { value: $r('app.string.SortConstants_created'), type: SortMode.CREATED }
  ];

  /**
   * 根据值获取排序选项
   * @param value 值
   * @returns 排序选项
   */
  public static getSortOptionByType(type: SortMode): Resource {
    return SortConstants.SORT_OPTIONS.find((option) => option.type === type)?.value ?? SortConstants.SORT_OPTIONS[0].value;
  }
}
