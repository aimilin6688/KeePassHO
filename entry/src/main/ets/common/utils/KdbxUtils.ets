import { Kdbx, KdbxEntry, KdbxEntryField, KdbxGroup, KdbxUuid, ProtectedValue, ByteUtils } from 'kdbxweb';
import IconUtils from './IconUtils';

export default class KdbxUtils {
  public static readonly FIELD_USERNAME = 'UserName';
  public static readonly FIELD_PASSWORD = 'Password';
  public static readonly FIELD_URL = 'URL';
  public static readonly FIELD_NOTES = 'Notes';
  public static readonly FIELD_TITLE = 'Title';

  /**
   * 获取字段值
   * @param fields 字段
   * @param key 字段key
   */
  public static getFieldValueString(fields: Map<string, KdbxEntryField>, key: string): string {
    if (!fields || !fields.has(key)) {
      return '';
    }
    let value = fields.get(key);
    if (!value) {
      return '';
    }
    if (value instanceof String) {
      return value as string;
    }

    if (value instanceof ProtectedValue) {
      return value.getText();
    }

    return value.toString();
  }

  /**
   * 获取条目
   * @param kdbx 数据库
   * @param groupId 组id
   * @param entryId 条目id
   */
  public static getEntry(kdbx: Kdbx, groupId: string, entryId: string): KdbxEntry | null {
    const group = kdbx.getGroup(groupId);
    if (!group) {
      return null;
    }
    for (const entry of group.entries) {
      if (entry.uuid.id === entryId) {
        return entry;
      }
    }
    return null;
  }

  /**
   * 搜索分组,包含子分组与条目
   * @param group 分组
   * @param searchText 搜索文本
   */
  public static searchInGroup(group: KdbxGroup, searchText: string): KdbxSearchResult {
    const result: KdbxSearchResult = {
      filteredGroups: [],
      filteredEntries: []
    };
    if (!group) {
      return result;
    }
    const searchTextLower = searchText.toLowerCase().trim();

    // 检查当前分组是否匹配
    if (group.name?.toLowerCase().includes(searchTextLower)) {
      result.filteredGroups.push(group);
    }

    // 搜索当前分组中的条目
    for (const entry of group.entries) {
      if (KdbxUtils.entryMatchesSearch(entry, searchTextLower)) {
        result.filteredEntries.push(entry);
      }
    }

    // 递归搜索子分组
    for (const subGroup of group.groups) {
      let subGroupResult = KdbxUtils.searchInGroup(subGroup, searchText);
      result.filteredGroups.push(...subGroupResult.filteredGroups);
      result.filteredEntries.push(...subGroupResult.filteredEntries);
    }

    return result;
  }

  /**
   * 检查条目是否匹配搜索文本
   * @param entry 要检查的条目
   * @param searchText 搜索文本（小写）
   * @returns 是否匹配
   */
  private static entryMatchesSearch(entry: KdbxEntry, searchText: string): boolean {
    // 搜索标准字段
    const standardFields = [
      KdbxUtils.FIELD_TITLE,
      KdbxUtils.FIELD_USERNAME,
      KdbxUtils.FIELD_URL,
      KdbxUtils.FIELD_NOTES
    ];

    for (const field of standardFields) {
      const value = KdbxUtils.getFieldValueString(entry.fields, field);
      if (value.toLowerCase().includes(searchText)) {
        return true;
      }
    }

    // 搜索自定义字段
    for (const item of entry.fields.entries()) {
      const key = item[0];
      // 跳过标准字段，因为已经搜索过了
      if (standardFields.includes(key)) {
        continue;
      }

      const fieldValue = KdbxUtils.getFieldValueString(entry.fields, key);
      if (fieldValue.toLowerCase().includes(searchText)) {
        return true;
      }
    }
    return false;
  }

  /**
   * 获取图标
   * @param iconId 图标id
   * @param customIcon 自定义图标
   */
  public static getIcon(iconId: number | undefined, customIcon: KdbxUuid | undefined, defaultResource?: Resource): ResourceStr | null {
    if (iconId === undefined && customIcon === undefined) {
      return defaultResource ?? null;
    }
    if (customIcon != undefined) {
      return KdbxUtils.toImgBase64Url(customIcon.toBytes());
    }
    return iconId != undefined ? IconUtils.getIconResourcePath(iconId) : (defaultResource ?? null);
  }

  /**
   * 将图标数据转换为DataURL
   * @param iconData 图标数据
   */
  public static toImgBase64Url(iconData: ArrayBuffer): string | null{
    return iconData ? 'data:image/png;base64,' + ByteUtils.bytesToBase64(iconData) : null;
  }
}


/**
 * 搜索结果
 */
export interface KdbxSearchResult {
  filteredGroups: Array<KdbxGroup>; // 过滤后的分组列表
  filteredEntries: Array<KdbxEntry>; // 过滤后的条目列表
}