import { ByteUtils, Kdbx, KdbxCredentials, KdbxCustomIcon, KdbxEntry, KdbxEntryField, KdbxGroup, KdbxMeta, KdbxUuid, ProtectedValue } from 'kdbxweb';
import { CredentialsService } from '../../services/CredentialsService';
import { FileService } from '../../services/FileService';
import { CredentialsParam } from '../../services/TypeDefined';
import { SortMode } from '../constants/SortConstants';
import IconUtils from './IconUtils';

import { hilog } from '@kit.PerformanceAnalysisKit';
import KdbxSaveService, { SaveDatabaseCallback } from '../../services/kdbx/KdbxSaveService';

const DOMAIN = 0x0000;
const TAG = 'KdbxUtils';

export default class KdbxUtils {
  public static readonly FIELD_USERNAME = 'UserName';
  public static readonly FIELD_PASSWORD = 'Password';
  public static readonly FIELD_URL = 'URL';
  public static readonly FIELD_OVERRIDE_URL = 'OverrideURL';
  public static readonly FIELD_NOTES = 'Notes';
  public static readonly FIELD_TITLE = 'Title';
  public static readonly FIELD_TAGS = 'Tags';
  public static readonly FIELD_EMAIL = 'Email';
  public static readonly FIELD_PHONE = 'Phone';
  public static readonly FIELD_CUSTOM_FIELDS = 'CustomFields';
  public static readonly FIELD_CREATION_TIME = 'creationTime';
  public static readonly FIELD_LASTMOD_TIME = 'lastModTime';
  public static readonly FIELD_EXPIRY_TIME = 'expiryTime';
  public static readonly GROUP_NAME = 'GroupName';
  public static readonly GROUP_RECYCLE_BIN = 'Recycle Bin';
  public static readonly GROUP_TEMPLATES_NAME = 'Templates';
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
    return KdbxUtils.getValueString(fields.get(key));
  }

  /**
   * 获取属性的值
   * @param key key
   * @param value value
   * @returns 结果字符串
   */
  public static getValueString(value: KdbxEntryField | undefined): string {
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
  public static getEntry(kdbx: Kdbx, groupId: string, entryId: string, historyIndex?: number): KdbxEntry | null {
    const group = kdbx.getGroup(groupId);
    if (!group) {
      return null;
    }
    let entryItem: KdbxEntry | null = null;
    for (const entry of group.entries) {
      if (entry.uuid.id === entryId) {
        entryItem = entry;
      }
    }
    // 有历史记录
    if (entryItem != null && historyIndex != undefined && historyIndex >= 0) {
      entryItem = entryItem.history[historyIndex];
    }
    return entryItem;
  }

  /**
   * 判断分组是否是子分组
   * @param parentGroup 父分组
   * @param childGroup 子分组
   * @returns 结果
   */
  public static isChildGroup(parentGroup: KdbxGroup, childGroup: KdbxGroup): boolean {
    if (parentGroup.groups.length === 0) {
      return false;
    }
    for (let group of parentGroup.groups) {
      if (group.uuid.id === childGroup.uuid.id) {
        return true;
      }
      if (KdbxUtils.isChildGroup(group, childGroup)) {
        return true;
      }
    }
    return false;
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
      KdbxUtils.FIELD_NOTES,
      KdbxUtils.FIELD_TAGS
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
    if (kdbxMeta == undefined) {
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
  public static async arrayBufferToKdbx(arrayBuffer: ArrayBuffer, credentialsParam: CredentialsParam, credentials?: KdbxCredentials): Promise<Kdbx> {
    if (credentials == undefined) {
      credentials = await CredentialsService.createKdbxCredentials(credentialsParam);
    }
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
    hilog.debug(DOMAIN, TAG, 'Before sort group names: %{public}s, %{public}s', sortMode, groups.map(group => group.name).join(','));
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
    hilog.debug(DOMAIN, TAG, 'After sort group names: %{public}s, %{public}s', sortMode, groups.map(group => group.name).join(','));
  }

  /**
   * 比较两个日期
   * @param a 日期A
   * @param b 日期B
   * @returns 0表示相等，-1表示a在b前面，1表示a在b后面
   */
  public static compare(a: Date | undefined, b: Date | undefined): number {
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

  /**
   * 获取字段名称
   * @param fileKey 文件密钥
   * @returns 字段名称
   */
  public static getFieldName(fileKey: string | undefined): string | Resource | undefined {
    hilog.debug(DOMAIN, TAG, 'Get field name: %{public}s', fileKey);
    switch (fileKey) {
      case KdbxUtils.FIELD_USERNAME:
        return $r("app.string.username");
      case KdbxUtils.FIELD_PASSWORD:
        return $r("app.string.password");
      case KdbxUtils.FIELD_URL:
        return $r("app.string.url");
      case KdbxUtils.FIELD_OVERRIDE_URL:
        return $r("app.string.override_url");
      case KdbxUtils.FIELD_NOTES:
        return $r("app.string.notes");
      case KdbxUtils.FIELD_TITLE:
        return $r("app.string.title");
      case KdbxUtils.FIELD_TAGS:
        return $r("app.string.tags");
      case KdbxUtils.FIELD_CUSTOM_FIELDS:
        return $r("app.string.custom_field");
      case KdbxUtils.FIELD_CREATION_TIME:
        return $r("app.string.created_time");
      case KdbxUtils.FIELD_LASTMOD_TIME:
        return $r("app.string.updated_time");
      case KdbxUtils.FIELD_EXPIRY_TIME:
        return $r("app.string.expiry_time");
      case KdbxUtils.GROUP_NAME:
        return $r("app.string.group_name");
      case KdbxUtils.GROUP_RECYCLE_BIN:
        return $r("app.string.recycle_bin");
      case KdbxUtils.GROUP_TEMPLATES_NAME:
        return $r('app.string.templates');
      default:
        return fileKey;
    }
  }

  /**
   * 保存数据库
   * @returns 结果信息
   */
  public static saveDatabase(callback?: SaveDatabaseCallback): void {
    KdbxUtils.customIconMap.clear();
    KdbxSaveService.saveDatabase(callback);
  }

  /**
   * 添加自定义图标到数据库
   * @param database 数据库实例
   * @param base64Image base64编码的图像数据（格式：data:image/png;base64,...)
   * @returns 添加的图标ID
   */
  public static async addCustomIcon(database: Kdbx, base64Images: string[], callback?: SaveDatabaseCallback) {
    try {
      if (!database || !base64Images || base64Images.length == 0) {
        callback?.onError?.('Invalid database or base64 image');
        return;
      }
      for (const base64Image of base64Images) {
        // 从base64字符串中提取实际的base64数据部分
        const base64Data = base64Image.split(',')[1];
        if (!base64Data) {
          callback?.onError?.('Invalid base64 image');
          continue;
        }
        // 将base64转换为ArrayBuffer
        const iconData = ByteUtils.base64ToBytes(base64Data);
        // 添加自定义图标到数据库
        database.meta.customIcons.set(KdbxUuid.random().id, { data: iconData } as KdbxCustomIcon);
      }
      // 清除缓存，确保新图标可见
      KdbxUtils.customIconMap.clear();
      // 保存数据库
      KdbxUtils.saveDatabase(callback);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Add custom icon error: %{public}s', error);
      callback?.onError?.(error.message);
    }
  }

  /**
   * 检查TOTP URL是否有效
   * @param totpUrl
   * @returns
   */
  public static isTotpUrl(totpUrl: string | undefined): boolean {
    if (!totpUrl) {
      return false;
    }
    return totpUrl.length > 0 && totpUrl.startsWith('otpauth://totp/');
  }

  /**
   * 从条目中获取TOTP URL
   * @param itemEntry 条目
   * @returns TOTP URL数组
   */
  public static getTotpUrl(itemEntry: KdbxEntry): Array<string> {
    let totpUrls: Array<string> = [];
    if (!itemEntry) {
      return totpUrls;
    }
    let valueString = '';
    itemEntry.fields.forEach((value, key) => {
      valueString = KdbxUtils.getValueString(value);
      if (valueString && KdbxUtils.isTotpUrl(valueString)) {
        totpUrls.push(valueString);
      }
    });
    return totpUrls;
  }
}

/**
 * 搜索结果
 */
export interface KdbxSearchResult {
  filteredGroups: Array<KdbxGroup>; // 过滤后的分组列表
  filteredEntries: Array<KdbxEntry>; // 过滤后的条目列表
}