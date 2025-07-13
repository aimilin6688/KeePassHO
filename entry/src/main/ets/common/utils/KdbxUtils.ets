import { ByteUtils, Kdbx, KdbxEntry, KdbxEntryField, KdbxGroup, KdbxMeta, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { CredentialsService } from '../../services/CredentialsService';
import { FileService } from '../../services/FileService';
import { CredentialsParam } from '../../services/TypeDefined';
import { SortMode } from '../constants/SortConstants';
import IconUtils from './IconUtils';

export default class KdbxUtils {
  public static readonly FIELD_USERNAME = 'UserName';
  public static readonly FIELD_PASSWORD = 'Password';
  public static readonly FIELD_URL = 'URL';
  public static readonly FIELD_NOTES = 'Notes';
  public static readonly FIELD_TITLE = 'Title';
  public static readonly GROUP_NAME = 'GroupName';


  private static customIconMap: Map<string, string> = new Map<string, string>();

  public static init() {
    KdbxUtils.customIconMap.clear();
  }

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
  public static getIcon(iconId: number | undefined, customIcon: KdbxUuid | undefined, defaultResource: Resource, kdbxMeta?: KdbxMeta | undefined): ResourceStr {
    if (iconId === undefined && customIcon === undefined) {
      return defaultResource;
    }
    if(kdbxMeta == undefined){
      kdbxMeta = FileService.getInstance().getDbFileParam().database.meta;
    }
    if (customIcon != undefined && kdbxMeta != undefined) {
      let customIconResult = KdbxUtils.getCustomIcon(customIcon, kdbxMeta);
      if (customIconResult != null) {
        return customIconResult;
      }
    }
    return iconId != undefined ? IconUtils.getIconResourcePath(iconId) : defaultResource;
  }

  /**
   * 获取图标资源
   * @param customIcon 自定义图标ID
   * @param kdbxMeta kdbx元数据
   * @returns 图标资源
   */
  public static getCustomIcon(customIcon: KdbxUuid | undefined | string, kdbxMeta: KdbxMeta | undefined): ResourceStr | null {
    if (customIcon == undefined || kdbxMeta == undefined) {
      return null;
    }
    let value = KdbxUtils.customIconMap.get(customIcon.toString());
    if (value != undefined) {
      return value;
    }
    let icon = kdbxMeta.customIcons.get(customIcon.toString());
    if (icon != undefined) {
      let iconBase64 = KdbxUtils.toImgBase64Url(icon.data);
      if (iconBase64 != null) {
        KdbxUtils.customIconMap.set(customIcon.toString(), iconBase64);
        return iconBase64;
      }
    }
    return null;
  }


  /**
   * 将图标数据转换为DataURL
   * @param iconData 图标数据
   */
  public static toImgBase64Url(iconData: ArrayBuffer): string | null {
    return iconData ? 'data:image/png;base64,' + ByteUtils.bytesToBase64(iconData) : null;
  }

  /**
   * 将对象转换为ArrayBuffer
   * @param kdbx KDBX对象
   */
  public static async kdbxToArrayBuffer(kdbx: Kdbx): Promise<ArrayBuffer> {
    return Promise.resolve(ByteUtils.stringToBuffer(await kdbx.saveXml()));
  }

  /**
   * 将ArrayBuffer转换为对象
   * @param arrayBuffer ArrayBuffer对象
   */
  public static async arrayBufferToKdbx(arrayBuffer: ArrayBuffer, credentialsParam: CredentialsParam): Promise<Kdbx> {
    let credentials = await CredentialsService.createKdbxCredentials(credentialsParam);
    return Kdbx.loadXml(ByteUtils.bytesToString(arrayBuffer), credentials);
  }


  /**
   * 对组和条目进行排序
   * @param groups 组
   * @param entries 条目
   * @param sortMod 0: 默认排序 1: 按名称排序 2: 按修改时间排序 3: 按创建时间排序
   */
  public static sortBy(groups: Array<KdbxGroup>, entries: Array<KdbxEntry>, sortMode: SortMode) {
    // 排序前分组名称
    console.log("排序前分组名称：", sortMode, groups.map(group => group.name).join(','));
    // 根据排序方式进行排序
    switch (sortMode) {
      case SortMode.NAME:
        // 按名称排序
        groups.sort((a, b) => (a.name ?? String.fromCharCode(0xffff)).localeCompare((b.name ?? String.fromCharCode(0xffff))));
        entries.sort((a, b) => {
          const titleA = KdbxUtils.getFieldValueString(a.fields, KdbxUtils.FIELD_TITLE);
          const titleB = KdbxUtils.getFieldValueString(b.fields, KdbxUtils.FIELD_TITLE);
          return titleA.localeCompare(titleB);
        });
        break;
      case SortMode.MODIFIED:
        // 按修改日期排序（最新的在前面）
        groups.sort((a, b) => KdbxUtils.compare(b.times.lastModTime, a.times.lastModTime));
        entries.sort((a, b) => KdbxUtils.compare(b.times.lastModTime, a.times.lastModTime));
        break;
      case SortMode.CREATED:
        // 按创建日期排序（最新的在前面）
        groups.sort((a, b) => KdbxUtils.compare(b.times.creationTime, a.times.creationTime));
        entries.sort((a, b) => KdbxUtils.compare(b.times.creationTime, a.times.creationTime));
        break;
      case SortMode.DEFAULT:
      default:
      // 默认排序，不做额外处理
        break;
    }
    // 排序后分组名称
    console.log("排序后分组名称：", sortMode, groups.map(group => group.name).join(','));
  }

  /**
   * 比较两个日期
   * @param a 日期A
   * @param b 日期B
   * @returns 0表示相等，-1表示a在b前面，1表示a在b后面
   */
  public static compare(a: Date | undefined, b: Date | undefined):number {
    if (a == undefined && b == undefined) {
      return 0;
    }
    if (a == undefined) {
      return -1;
    }
    if (b == undefined) {
      return 1;
    }
    return a.getTime() - b.getTime();
  }
}

/**
 * 搜索结果
 */
export interface KdbxSearchResult {
  filteredGroups: Array<KdbxGroup>; // 过滤后的分组列表
  filteredEntries: Array<KdbxEntry>; // 过滤后的条目列表
}