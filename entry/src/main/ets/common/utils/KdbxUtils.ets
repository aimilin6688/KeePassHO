import {
  ByteUtils,
  Consts,
  Kdbx,
  KdbxBinaries,
  KdbxCredentials,
  KdbxEntry,
  KdbxEntryField,
  KdbxError,
  KdbxGroup,
  KdbxMeta,
  KdbxSnapshot,
  KdbxUuid,
  ProtectedValue
} from 'kdbxweb';
import { CredentialsService } from '../../services/CredentialsService';
import { FileService } from '../../services/FileService';
import { CredentialsParam } from '../../services/TypeDefined';
import { DatabaseLoadGuard } from '../../services/kdbx/DatabaseLoadGuard';
import { AttachmentCacheService } from '../../services/kdbx/AttachmentCacheService';
import { SessionFileService } from '../../services/kdbx/SessionFileService';
import { SuccessMessage } from '../../workers/WorkerParam';
import { StorageError, StorageErrorCodes } from '../../storage/StorageError';
import { SortMode } from '../constants/SortConstants';
import { IconUtils, ResourceManager, StringUtils, DateUtils } from '.';
import { ConfigDecryptError, STORAGE_CONFIG_DECRYPT_FAILED_RES } from './ConfigDecryptError';
import { OtpCompatibilityManager, OtpExtractionResult } from '../../services/otp';

import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'KdbxUtils';

export class KdbxUtils {
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
  public static readonly FIELD_TOTP = 'TOTP';
  public static readonly GROUP_NAME = 'GroupName';
  public static readonly GROUP_RECYCLE_BIN = 'Recycle Bin';
  public static readonly GROUP_TEMPLATES_NAME = 'Templates';
  /** 置顶标签 */
  public static readonly PINNED_TAG = '__PINNED__';
  /** 收藏标签 */
  public static readonly FAVORITE_TAG = '__FAVORITE__';
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
   * 判断字段是否是保护字段
   * @param value 字段值
   * @returns 结果
   */
  public static isProtectedValue(value: KdbxEntryField | undefined): boolean {
    return value instanceof ProtectedValue;
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
   * @param database 数据库对象（用于判断是否在回收站中）
   * @param includeRecycleBin 是否包含回收站中的内容，默认 false
   */
  public static searchInGroup(group: KdbxGroup, searchText: string, database?: Kdbx, includeRecycleBin: boolean = false): KdbxSearchResult {
    const result: KdbxSearchResult = {
      filteredGroups: [],
      filteredEntries: []
    };
    if (!group) {
      return result;
    }
    const searchTextLower = searchText.toLowerCase().trim();

    // 检查当前分组是否匹配（排除回收站）
    if (group.name?.toLowerCase().includes(searchTextLower)) {
      if (includeRecycleBin || !database || !database.isInRecycleBin(group)) {
        result.filteredGroups.push(group);
      }
    }

    // 搜索当前分组中的条目（排除回收站中的条目）
    for (const entry of group.entries) {
      if (KdbxUtils.entryMatchesSearch(entry, searchTextLower)) {
        if (includeRecycleBin || !database || !database.isInRecycleBin(entry)) {
          result.filteredEntries.push(entry);
        }
      }
    }

    // 递归搜索子分组
    for (const subGroup of group.groups) {
      let subGroupResult = KdbxUtils.searchInGroup(subGroup, searchText, database, includeRecycleBin);
      result.filteredGroups.push(...subGroupResult.filteredGroups);
      result.filteredEntries.push(...subGroupResult.filteredEntries);
    }

    return result;
  }

  /**
   * 搜索条目
   * @param totpEntries 条目
   * @param searchText 搜索文本
   * @returns
   */
  public static searchInEntries(entries: Array<KdbxEntry>, searchText: string): Array<KdbxEntry> {
    const result = new Array<KdbxEntry>();
    if (!entries || entries.length === 0 || !searchText) {
      return result;
    }

    const searchTextLower = searchText.toLowerCase().trim();
    for (const entry of entries) {
      if (KdbxUtils.entryMatchesSearch(entry, searchTextLower)) {
        result.push(entry);
      }
    }
    return result;
  }

  /**
   * 解析到期搜索语法的天数（对齐 KeePassXC is:expired / is:expired-N）
   * @param searchText 搜索文本（已小写）
   * @returns is:expired 返回 0；is:expired-N 返回 N；非该语法返回 undefined
   */
  public static parseExpiredSearchDays(searchText: string): number | undefined {
    const text: string = searchText.trim().toLowerCase();
    if (text === 'is:expired') {
      return 0;
    }
    const match = /^is:expired-(\d+)$/.exec(text);
    if (match !== null) {
      return parseInt(match[1], 10);
    }
    return undefined;
  }

  /**
   * 检查条目是否匹配搜索文本
   * @param entry 要检查的条目
   * @param searchText 搜索文本（小写）
   * @returns 是否匹配
   */
  private static entryMatchesSearch(entry: KdbxEntry, searchText: string): boolean {
    // 到期搜索语法：is:expired（仅已过期）/ is:expired-N（已过期或 N 天内到期）
    const expiredSearchDays: number | undefined = KdbxUtils.parseExpiredSearchDays(searchText);
    if (expiredSearchDays !== undefined) {
      const expires: boolean = entry.times.expires === true;
      return DateUtils.willExpireInDays(expires, entry.times.expiryTime, expiredSearchDays);
    }
    // 搜索标准字段
    const standardFields = [
      KdbxUtils.FIELD_TITLE,
      KdbxUtils.FIELD_USERNAME,
      KdbxUtils.FIELD_URL,
      KdbxUtils.FIELD_NOTES,
      KdbxUtils.FIELD_TAGS
    ];

    for (const field of standardFields) {
      if (KdbxUtils.FIELD_TAGS === field) {
        for (const tag of entry.tags) {
          if (tag.toLowerCase().includes(searchText)) {
            return true;
          }
        }
      } else {
        const value = KdbxUtils.getFieldValueString(entry.fields, field);
        if (value.toLowerCase().includes(searchText)) {
          return true;
        }
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
  public static getIcon(iconId: number | undefined, customIcon: KdbxUuid | undefined, defaultResource: Resource,
    kdbxMeta?: KdbxMeta | undefined): ResourceStr {
    if (iconId === undefined && customIcon === undefined) {
      return defaultResource;
    }
    if (kdbxMeta == undefined) {
      // 数据库可能已关闭（如修改主密码后 FileService.close() 触发页面卸载重渲染），不能裸读 database.meta
      const database = FileService.getInstance().getDbFileParam().database;
      if (database != undefined) {
        kdbxMeta = database.meta;
      }
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
   * 将对象转换为ArrayBuffer（KPSN 二进制快照：条目树XML仅含附件Ref + 原始二进制附件池 + 文件头）
   * @param kdbx KDBX对象
   */
  public static async kdbxToArrayBuffer(kdbx: Kdbx | ArrayBuffer): Promise<ArrayBuffer> {
    if (kdbx instanceof ArrayBuffer) {
      return Promise.resolve(kdbx);
    }
    const startTime = Date.now();
    return kdbx.saveSnapshot().then((buffer: ArrayBuffer) => {
      hilog.info(DOMAIN, TAG, 'kdbx to array buffer (KPSN serialize) time: %{public}d ms', Date.now() - startTime);
      return buffer;
    });
  }

  /**
   * 将ArrayBuffer转换为对象
   * @param arrayBuffer ArrayBuffer对象
   * @param credentialsParam 凭据参数
   * @param credentials 凭据
   * @throws KdbxError 如果凭据无效，则抛出KdbxError
   */
  public static async arrayBufferToKdbx(arrayBuffer: ArrayBuffer | Kdbx, credentialsParam: CredentialsParam, credentials?: KdbxCredentials): Promise<Kdbx> {
    if (arrayBuffer instanceof Kdbx) {
      return arrayBuffer;
    }
    if (credentials == undefined) {
      credentials = await CredentialsService.createKdbxCredentials(credentialsParam);
    }
    // CP2'：解压后载荷上限（进程内缓存，跨线程各自探测一次）
    const maxDecompressedBytes: number = await DatabaseLoadGuard.getMaxDecompressedBytes();
    // KPSN 快照（跨线程边界格式）：魔数分发，免解密直接还原模型
    if (KdbxSnapshot.isSnapshot(arrayBuffer)) {
      // v2 快照可能携带磁盘引用附件，主线程 store 必须就绪（不可用时明确报错而非静默损坏）
      return Kdbx.loadSnapshot(arrayBuffer, credentials, {
        maxDecompressedBytes: maxDecompressedBytes,
        attachmentStore: AttachmentCacheService.getStore()
      });
    }
    // 尝试用 Kdbx.load() 加载加密的二进制格式（合并远端等场景：保持纯内存模式）
    try {
      return await Kdbx.load(arrayBuffer, credentials, { maxDecompressedBytes: maxDecompressedBytes });
    } catch (error) {
      hilog.error(DOMAIN, TAG, `arrayBufferToKdbx error: ${error?.message}, stack: ${error?.stack}`);
      return Kdbx.loadXml(ByteUtils.bytesToString(arrayBuffer), credentials);
    }
  }

  /**
   * 从 Worker 成功消息还原模型（§7.4 会话文件协议 + M0 v3 直传容器）
   * 自动识别包裹格式：SFW1 分块流 = v3 直传容器（原始 inner XML + 头部 + 池引用），
   * 边解包边协作解析（256KB 块间真实 IO 边界，模型只构建一次）；
   * legacy 单封 = v1/v2 KPSN 快照，整缓冲还原；
   * 无 M0 时回退消息内 data（同步模式直接传 Kdbx 实例 / 历史缓冲）
   * @param message Worker 成功消息
   * @param credentialsParam 凭据参数
   * @param credentials 凭据
   */
  public static async successMessageToKdbx(message: SuccessMessage, credentialsParam: CredentialsParam,
    credentials?: KdbxCredentials): Promise<Kdbx> {
    if (message.m0Path) {
      const startTime = Date.now();
      const reader = await SessionFileService.openUnwrapReader(message.m0Path);
      try {
        let kdbx: Kdbx;
        if (reader.isStreaming) {
          // v3 直传容器：协作式解析（解包 4MB 块 + 拉取解析 256KB 块交替进行）
          let creds = credentials;
          if (creds === undefined) {
            creds = await CredentialsService.createKdbxCredentials(credentialsParam);
          }
          const maxDecompressedBytes: number = await DatabaseLoadGuard.getMaxDecompressedBytes();
          kdbx = await KdbxSnapshot.loadFromReader(reader, creds, {
            maxDecompressedBytes: maxDecompressedBytes,
            attachmentStore: AttachmentCacheService.getStore()
          });
        } else {
          // legacy 单封（v1/v2 KPSN 快照 / 合并产物）：整缓冲还原
          const bytes: ArrayBuffer = ByteUtils.bytesToBuffer(await reader.readAll());
          kdbx = await KdbxUtils.arrayBufferToKdbx(bytes, credentialsParam, credentials);
        }
        hilog.info(DOMAIN, TAG, 'm0 consume: %{public}d ms, streaming=%{public}s',
          Date.now() - startTime, reader.isStreaming);
        return kdbx;
      } finally {
        reader.close();
        SessionFileService.removeFile(message.m0Path);
      }
    }
    return KdbxUtils.arrayBufferToKdbx(message.data, credentialsParam, credentials);
  }


  /**
   * 对组和条目进行排序
   * @param items 条目和分组的合并数组
   * @param sortMode 0: 默认排序 1: 按名称排序 2: 按修改时间排序 3: 按创建时间排序
   */
  public static sortBy(items: Array<KdbxGroup | KdbxEntry>, sortMode: SortMode) {
    // 根据排序方式进行排序
    switch (sortMode) {
      case SortMode.NAME:
        // 按名称排序（置顶优先，同是置顶的按修改时间排序）
        items.sort((a, b) => {
          const pinnedResult = KdbxUtils.comparePinnedAndTime(a, b);
          if (pinnedResult !== 0) {
            return pinnedResult;
          }
          // 获取名称
          const nameA = a instanceof KdbxGroup ? (a.name ?? '') : KdbxUtils.getFieldValueString(a.fields, KdbxUtils.FIELD_TITLE);
          const nameB = b instanceof KdbxGroup ? (b.name ?? '') : KdbxUtils.getFieldValueString(b.fields, KdbxUtils.FIELD_TITLE);
          return StringUtils.getPinyin(nameA).localeCompare(StringUtils.getPinyin(nameB));
        });
        break;
      case SortMode.MODIFIED:
        // 按修改日期排序（置顶优先，同是置顶的按修改时间排序）
        items.sort((a, b) => {
          const pinnedResult = KdbxUtils.comparePinnedAndTime(a, b);
          if (pinnedResult !== 0) {
            return pinnedResult;
          }
          return KdbxUtils.compare(b.times.lastModTime, a.times.lastModTime);
        });
        break;
      case SortMode.CREATED:
        // 按创建日期排序（置顶优先，同是置顶的按修改时间排序）
        items.sort((a, b) => {
          const pinnedResult = KdbxUtils.comparePinnedAndTime(a, b);
          if (pinnedResult !== 0) {
            return pinnedResult;
          }
          return KdbxUtils.compare(b.times.creationTime, a.times.creationTime);
        });
        break;
      case SortMode.DEFAULT:
      default:
      // 默认排序（置顶优先，同是置顶的按修改时间排序）
        items.sort((a, b) => KdbxUtils.comparePinnedAndTime(a, b));
        break;
    }
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
   * 检查条目或分组是否置顶
   * @param item 条目或分组
   * @returns 是否置顶
   */
  public static isPinned(item: KdbxEntry | KdbxGroup): boolean {
    return item.tags && item.tags.includes(KdbxUtils.PINNED_TAG);
  }

  /**
   * 切换条目或分组的置顶状态
   * @param item 条目或分组
   * @returns 切换后是否置顶
   */
  public static togglePinned(item: KdbxEntry | KdbxGroup): boolean {
    if (!item.tags) {
      item.tags = [];
    }
    const index = item.tags.indexOf(KdbxUtils.PINNED_TAG);
    if (index >= 0) {
      // 取消置顶
      item.tags.splice(index, 1);
      return false;
    } else {
      // 置顶
      item.tags.push(KdbxUtils.PINNED_TAG);
      return true;
    }
  }

  /**
   * 检查条目或分组是否收藏
   * @param item 条目或分组
   * @returns 是否收藏
   */
  public static isFavorite(item: KdbxEntry | KdbxGroup): boolean {
    return item.tags && item.tags.includes(KdbxUtils.FAVORITE_TAG);
  }

  /**
   * 切换条目或分组的收藏状态
   * @param item 条目或分组
   * @returns 切换后是否收藏
   */
  public static toggleFavorite(item: KdbxEntry | KdbxGroup): boolean {
    if (!item.tags) {
      item.tags = [];
    }
    const index = item.tags.indexOf(KdbxUtils.FAVORITE_TAG);
    if (index >= 0) {
      // 取消收藏
      item.tags.splice(index, 1);
      return false;
    } else {
      // 收藏
      item.tags.push(KdbxUtils.FAVORITE_TAG);
      return true;
    }
  }

  /**
   * 在数据库中获取所有收藏的条目和分组
   * @param database 数据库
   * @returns 收藏的条目和分组列表
   */
  public static getFavoriteItems(database: Kdbx): Array<KdbxGroup | KdbxEntry> {
    const favoriteItems: Array<KdbxGroup | KdbxEntry> = [];
    if (!database) {
      return favoriteItems;
    }

    const rootGroup = database.getDefaultGroup();
    const collectFavorites = (group: KdbxGroup) => {
      // 收集收藏的分组
      for (const subGroup of group.groups) {
        if (KdbxUtils.isFavorite(subGroup)) {
          favoriteItems.push(subGroup);
        }
        collectFavorites(subGroup);
      }
      // 收集收藏的条目
      for (const entry of group.entries) {
        if (KdbxUtils.isFavorite(entry)) {
          favoriteItems.push(entry);
        }
      }
    };

    collectFavorites(rootGroup);
    return favoriteItems;
  }

  /**
   * 比较两个条目/分组的置顶状态和时间
   * 用于排序：置顶的在前，同是置顶的按修改时间排序
   * @param a 条目A
   * @param b 条目B
   * @returns 排序结果
   */
  public static comparePinnedAndTime(a: KdbxEntry | KdbxGroup, b: KdbxEntry | KdbxGroup): number {
    const aPinned = KdbxUtils.isPinned(a);
    const bPinned = KdbxUtils.isPinned(b);

    // 如果置顶状态不同，置顶的排在前面
    if (aPinned && !bPinned) {
      return -1;
    }
    if (!aPinned && bPinned) {
      return 1;
    }

    // 如果都是置顶的，按修改时间倒序排列（最新的在前）
    if (aPinned && bPinned) {
      return KdbxUtils.compare(b.times.lastModTime, a.times.lastModTime);
    }
    // 如果都没有置顶，按位置（返回0，保持原顺序）
    return 0;
  }

  /**
   * 获取字段名称
   * @param fileKey 文件密钥
   * @returns 字段名称
   */
  public static getFieldName(fileKey: string | undefined): string | Resource | undefined {
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
   * 清空自定义图标显示缓存（保存/新增图标后由服务层调用，确保新图标可见）
   */
  public static clearCustomIconMap(): void {
    KdbxUtils.customIconMap.clear();
  }

  /**
   * 清理指定天数前的条目历史版本，并清理完全未被任何条目（当前版本+剩余历史版本）引用的孤儿附件。
   * 不调用 saveDatabase（由调用方在清理后调用），不删除条目本身（当前版本）。
   * @param database 已打开的数据库实例
   * @param days 清理天数（正整数，由调用方校验）
   * @returns 清理结果统计
   */
  public static cleanHistoryAndBinaries(database: Kdbx, days: number): CleanResult {
    const cutoff = Date.now() - days * 86400000;
    let deletedHistoryCount: number = 0;

    hilog.debug(DOMAIN, TAG, 'cleanHistoryAndBinaries: start, days=%{public}d, cutoff=%{public}s, cutoffDate=%{public}s',
      days, cutoff.toString(), new Date(cutoff).toISOString());

    const rootGroup = database.getDefaultGroup();

    // 1. 历史版本清理：遍历所有条目（含回收站），从后往前收集索引避免删除时偏移
    let processedEntryCount: number = 0;
    for (const item of rootGroup.allGroupsAndEntries()) {
      if (item instanceof KdbxEntry) {
        const entry: KdbxEntry = item;
        processedEntryCount++;
        const indicesToDelete: number[] = [];
        for (let i = entry.history.length - 1; i >= 0; i--) {
          const historyEntry = entry.history[i];
          const lastModTime = historyEntry.times.lastModTime;
          if (lastModTime == undefined) {
            hilog.debug(DOMAIN, TAG, 'cleanHistory: entry history[%{public}d] lastModTime is empty, skip', i);
            continue;
          }
          if (lastModTime.getTime() < cutoff) {
            indicesToDelete.push(i);
            hilog.debug(DOMAIN, TAG, 'cleanHistory: entry history[%{public}d] lastModTime=%{public}s < cutoff, will delete',
              i, lastModTime.toISOString());
          }
        }
        if (indicesToDelete.length > 0) {
          hilog.debug(DOMAIN, TAG, 'cleanHistory: entry totalHistory=%{public}d, willDelete=%{public}d',
            entry.history.length, indicesToDelete.length);
        }
        for (const index of indicesToDelete) {
          entry.removeHistory(index, 1);
          deletedHistoryCount++;
        }
      }
    }
    hilog.debug(DOMAIN, TAG, 'cleanHistory: done, processedEntries=%{public}d, deletedHistoryCount=%{public}d',
      processedEntryCount, deletedHistoryCount);

    // 2. 孤儿附件清理
    const deletedBinariesCount = KdbxUtils.cleanupOrphanedBinaries(database);

    hilog.debug(DOMAIN, TAG, 'cleanHistoryAndBinaries: finish, deletedHistory=%{public}d, deletedBinaries=%{public}d',
      deletedHistoryCount, deletedBinariesCount);
    return { deletedHistoryCount, deletedBinariesCount } as CleanResult;
  }

  /**
   * 收集条目 binaries Map 中所有带 hash 的附件引用到目标集合
   * @param entry 条目（当前版本或历史版本）
   * @param usedHashes 收集目标集合
   */
  private static collectUsedBinaryHashes(entry: KdbxEntry, usedHashes: Set<string>): void {
    for (const value of entry.binaries.values()) {
      if (KdbxBinaries.isKdbxBinaryWithHash(value)) {
        usedHashes.add(value.hash);
      }
    }
  }

  /**
   * 清理孤儿附件：扫描数据库中所有条目（含历史版本）的 binaries 引用，
   * 删除全局 binaries 池中无任何条目引用的附件。
   * 适用于条目永久删除、历史版本删除、附件从条目中移除后调用。
   * @param database 已打开的数据库实例
   * @returns 被清理的孤儿附件数量
   */
  public static cleanupOrphanedBinaries(database: Kdbx): number {
    const usedHashes: Set<string> = new Set<string>();
    const rootGroup = database.getDefaultGroup();
    for (const item of rootGroup.allGroupsAndEntries()) {
      if (item instanceof KdbxEntry) {
        KdbxUtils.collectUsedBinaryHashes(item, usedHashes);
        for (const historyEntry of item.history) {
          KdbxUtils.collectUsedBinaryHashes(historyEntry, usedHashes);
        }
      }
    }

    let deletedCount: number = 0;
    const allBinaries = database.binaries.getAllWithHashes();
    for (const binary of allBinaries) {
      if (!usedHashes.has(binary.hash)) {
        hilog.debug(DOMAIN, TAG, 'cleanupOrphanedBinaries: delete orphan binary, hash=%{public}s', binary.hash);
        database.binaries.deleteWithHash(binary.hash);
        deletedCount++;
      }
    }
    if (deletedCount > 0) {
      hilog.info(DOMAIN, TAG, 'cleanupOrphanedBinaries: deletedCount=%{public}d', deletedCount);
    }
    return deletedCount;
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
    if (!itemEntry) {
      return [];
    }
    // 使用兼容层管理器提取 OTP URL
    return OtpCompatibilityManager.getInstance().extractOtpUrls(itemEntry);
  }

  /**
   * 从条目中获取TOTP URL及已处理的字段名
   * @param itemEntry 条目
   * @returns 包含 TOTP URL 数组和已处理字段名集合的对象
   */
  public static getTotpUrlWithProcessedFields(itemEntry: KdbxEntry): OtpExtractionResult {
    if (!itemEntry) {
      return { urls: [], processedFields: new Set<string>() } as OtpExtractionResult;
    }
    // 使用兼容层管理器提取 OTP URL 及已处理字段
    return OtpCompatibilityManager.getInstance().extractOtpUrlsWithProcessedFields(itemEntry);
  }

  public static kdbxErrorMessage(kdbxError: Error): string {
    const payload: string | number = KdbxUtils.kdbxErrorPayload(kdbxError);
    const prefix: string = ResourceManager.getString(payload);
    // payload 为资源 ID（本地化分支）时拼接原始明细展示详细错误；payload 已是原始文本时原样返回
    if (typeof payload !== 'number') {
      return prefix;
    }
    const detail: string | undefined = KdbxUtils.kdbxErrorDetail(kdbxError);
    return detail ? `${prefix}: ${detail}` : prefix;
  }

  /**
   * 提取 KDBX 错误明细（KdbxError "Error <code>: <detail>" 中的 <detail> 部分），
   * 供调用方与本地化前缀拼接展示详细错误。
   * 仅在 payload 为资源 ID（kdbxErrorPayload 返回 number）时拼接，payload 已是原始文本时
   * 不拼接（原文已含明细，避免重复）；调用方需自行做该判断。
   * 非 KdbxError 或无明细时返回 undefined。
   * @param kdbxError 错误对象
   * @returns 错误明细文本，无明细时 undefined
   */
  public static kdbxErrorDetail(kdbxError: Error): string | undefined {
    if (!(kdbxError instanceof KdbxError)) {
      return undefined;
    }
    const prefix: string = 'Error ' + kdbxError.code + ': ';
    if (kdbxError.message.startsWith(prefix)) {
      const detail: string = kdbxError.message.substring(prefix.length);
      return detail.length > 0 ? detail : undefined;
    }
    return undefined;
  }

  /**
   * 生成 KDBX 错误的原始消息载体（不在当前线程本地化）。
   * 本地化分支返回资源 ID（数字），其余返回原始错误文本；
   * Worker 线程无 ResourceManager 上下文，必须传 ID 由主线程本地化。
   * @param kdbxError 错误对象
   * @returns 资源 ID（数字）或原始错误文本
   */
  public static kdbxErrorPayload(kdbxError: Error): string | number {
    // 先检查是否是网络错误
    if (KdbxUtils.isNetworkError(kdbxError)) {
      return $r('app.string.network_error').id;
    }

    // 跨线程契约：Worker 中 $r 同样可用，ConfigDecryptError.message 已是本地化文案，
    // 主线程无法凭文案识别该错误；统一映射为资源名，由 getMessage 按名本地化展示、
    // isDecryptFailedMessage 按名识别并弹框引导重新编辑
    if (kdbxError instanceof ConfigDecryptError) {
      return STORAGE_CONFIG_DECRYPT_FAILED_RES;
    }

    // CP-UP：整缓冲上传超限（明确拒绝而非交给 http 栈报 2300023）
    if (kdbxError instanceof StorageError && kdbxError.code === StorageErrorCodes.UPLOAD_TOO_LARGE) {
      return $r('app.string.storage_upload_too_large').id;
    }

    if (!(kdbxError instanceof KdbxError)) {
      return kdbxError.message || kdbxError.toString();
    }
    switch (kdbxError.code) {
      case Consts.ErrorCodes.NotImplemented:
        return $r('app.string.kdbx_error_NotImplemented').id;
      case Consts.ErrorCodes.InvalidArg:
        return $r('app.string.kdbx_error_InvalidArg').id;
      case Consts.ErrorCodes.BadSignature:
        return $r('app.string.kdbx_error_BadSignature').id;
      case Consts.ErrorCodes.InvalidVersion:
        return $r('app.string.kdbx_error_InvalidVersion').id;
      case Consts.ErrorCodes.Unsupported:
        return $r('app.string.kdbx_error_Unsupported').id;
      case Consts.ErrorCodes.FileCorrupt:
        return $r('app.string.kdbx_error_FileCorrupt').id;
      case Consts.ErrorCodes.MergeError:
        return $r('app.string.kdbx_error_MergeError').id;
      case Consts.ErrorCodes.InvalidKey:
        return $r('app.string.kdbx_error_InvalidKey').id;
      case Consts.ErrorCodes.InvalidState:
        return $r('app.string.kdbx_error_InvalidState').id;
      case Consts.ErrorCodes.DecompressedTooLarge:
        // CP2'：解压后载荷超限，拒绝加载防止 OOM
        return $r('app.string.database_decompressed_too_large').id;
      case Consts.ErrorCodes.NotEnoughDisk:
        // S5：流式解压磁盘余量不足
        return $r('app.string.database_not_enough_disk').id;
    }
    return kdbxError.message || kdbxError.toString();
  }

  /**
   * 检查是否是网络错误
   * @param error 错误对象
   * @returns 是否是网络错误
   */
  private static isNetworkError(error: Error): boolean {
    const message = error.message?.toLowerCase() || '';
    // 常见的网络错误关键词
    const networkErrorKeywords = [
      'couldn\'t resolve host',
      'network',
      'timeout',
      'connection refused',
      'connection reset',
      'connection failed',
      'socket',
      'dns',
      'enetunreach',
      'econnrefused',
      'etimedout',
      'ssl',
      'certificate'
    ];
    return networkErrorKeywords.some(keyword => message.includes(keyword));
  }

  /**
   * 获取分组路径
   * @param group 分组
   * @returns 分组路径字符串
   */
  public static getGroupPath(group: KdbxGroup | undefined, splitChar: string = '/', includeRoot: boolean = true): string {
    if (!group) {
      return '';
    }
    const path: string[] = [];
    let currentGroup: KdbxGroup | undefined = group;

    while (currentGroup && currentGroup.name) {
      path.unshift(currentGroup.name);
      currentGroup = currentGroup.parentGroup;
    }
    if (!includeRoot && path.length > 0) {
      path.shift();
    }
    return path.join(splitChar);
  }

  /**
   * 构建索引器数据
   * @param items 条目或分组列表
   * @param startIndex 开始索引, 默认从0开始
   * @returns  索引器数据
   */
  public static buildIndexerData(items: Array<KdbxGroup | KdbxEntry>, startIndex?: number): KdbxIndexer {
    let indexerValues = new Array<string>();
    let indexerMap = new Map<string, number>();

    if (!items || items.length === 0) {
      return { indexerValues, indexerMap };
    }

    // 收集所有首字母（从非置顶/收藏的条目开始）
    const letterSet = new Set<string>();
    for (let i = (startIndex ?? 0); i < items.length; i++) {
      const item = items[i];
      // 不存在条目，或者置顶条目
      if (!item || KdbxUtils.isPinned(item)) {
        continue;
      }
      const name = item instanceof KdbxGroup ? (item.name ?? '') : KdbxUtils.getFieldValueString(item.fields, KdbxUtils.FIELD_TITLE);
      const letter = StringUtils.getFirstLetter(name ?? '');
      // 字母表增加 字母
      letterSet.add(letter);
      // 字母索引增加索引
      if (!indexerMap.has(letter)) {
        indexerMap.set(letter, i);
      }
    }

    // 排序字母（# 放在最前面）
    const letters = Array.from(letterSet).sort((a, b) => {
      if (a === '#') {
        return -1;
      }
      if (b === '#') {
        return 1;
      }
      return a.localeCompare(b);
    });

    indexerValues.push(...letters);
    return { indexerValues, indexerMap };
  }

  /**
   * 获取可安全恢复的目标父分组（对齐 KeePass GetPreviousParentGroupSafeI，
   * MainForm_Functions.cs:6896-6928）
   * @param database 数据库
   * @param object 待恢复的条目/分组
   * @returns 目标分组；不可恢复时返回 undefined
   */
  public static getPreviousParentGroupSafe(
    database: Kdbx,
    object: KdbxEntry | KdbxGroup
  ): KdbxGroup | undefined {
    // 1. previousParentGroup 未设置 → 不可恢复
    const previousParentGroup = object.previousParentGroup;
    if (!previousParentGroup) {
      return undefined;
    }
    // 2. 按 UUID 在根组树递归查找（原分组已被永久删除 → 不可恢复）
    const target = database.getGroup(previousParentGroup);
    if (!target) {
      return undefined;
    }
    // 3. 不允许"恢复"到当前父组（已在原位置）
    if (target === object.parentGroup) {
      return undefined;
    }
    // 4. 分组恢复：目标不得是自身或自身子孙（防环）
    if (object instanceof KdbxGroup && KdbxUtils.isDescendantOrSelf(target, object)) {
      return undefined;
    }
    return target;
  }

  /**
   * 恢复条目/分组到原位置。
   * Kdbx.move 会把 previousParentGroup 更新为恢复前的父组（交换语义），
   * 与 KeePassXC restoreSelectedEntries 行为一致。
   * @param database 数据库
   * @param object 待恢复的条目/分组
   * @returns 是否恢复成功
   */
  public static restoreToPreviousLocation(
    database: Kdbx,
    object: KdbxEntry | KdbxGroup
  ): boolean {
    const target = KdbxUtils.getPreviousParentGroupSafe(database, object);
    if (!target) {
      return false;
    }
    database.move(object, target);
    return true;
  }

  /**
   * candidate 是否为 group 自身或其子孙分组（沿 parentGroup 向上遍历）
   * @param candidate 待判定分组
   * @param group 祖先分组
   */
  public static isDescendantOrSelf(candidate: KdbxGroup, group: KdbxGroup): boolean {
    let current: KdbxGroup | undefined = candidate;
    while (current) {
      if (current === group) {
        return true;
      }
      current = current.parentGroup;
    }
    return false;
  }

  /**
   * TAN 条目标题常量（对齐 KeePass PwDefs.TanTitle，大小写敏感精确匹配）
   */
  public static readonly TAN_TITLE = '<TAN>';

  /** 条目颜色合法格式：#RRGGBB */
  private static readonly ENTRY_COLOR_PATTERN: RegExp = /^#[0-9a-fA-F]{6}$/;

  /**
   * 是否为 TAN 条目（Title 精确等于 '<TAN>'，对齐 KeePass PwDefs.IsTanEntry）
   * @param entry 待判定条目
   */
  public static isTanEntry(entry: KdbxEntry): boolean {
    return KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_TITLE) === KdbxUtils.TAN_TITLE;
  }

  /**
   * 获取 TAN 条目序号（存储在 UserName 字段）
   * @param entry TAN 条目
   */
  public static getTanIndex(entry: KdbxEntry): string {
    return KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_USERNAME);
  }

  /**
   * 批量创建 TAN 条目（对齐 KeePass TanWizardForm.AddTan）：
   * Title 固定 '<TAN>'，UserName 存序号（0 视为无序号不写入），Password 存 TAN 明文（保护字段）。
   * @param group 目标分组
   * @param tans TAN 文本片段（空片段跳过，不占序号）
   * @param startIndex 起始序号（含）
   * @returns 实际创建条数
   */
  public static addTanEntries(group: KdbxGroup, tans: Array<string>, startIndex: number): number {
    let index = startIndex;
    for (const tan of tans) {
      if (!tan) {
        continue;
      }
      const entry = new KdbxEntry();
      entry.fields.set(KdbxUtils.FIELD_TITLE, KdbxUtils.TAN_TITLE);
      if (index > 0) {
        entry.fields.set(KdbxUtils.FIELD_USERNAME, String(index));
      }
      entry.fields.set(KdbxUtils.FIELD_PASSWORD, ProtectedValue.fromString(tan));
      entry.times.update();
      group.entries.push(entry);
      index++;
    }
    return index - startIndex;
  }

  /**
   * TAN 条目"使用后过期"（对齐 KeePass EntryUtil.ExpireTanEntryIfOption）：
   * 开关关闭或非 TAN 条目不变更；否则先推入历史快照再置过期（expires=true、expiryTime=当前时间）。
   * @param entry 待过期条目
   * @param expiresOnUse "TAN 使用后过期"设置开关
   * @returns 是否发生了变更
   */
  public static expireTanEntryOnUse(entry: KdbxEntry, expiresOnUse: boolean): boolean {
    if (!expiresOnUse || !KdbxUtils.isTanEntry(entry)) {
      return false;
    }
    entry.pushHistory();
    entry.times.expires = true;
    entry.times.expiryTime = new Date();
    entry.times.update();
    return true;
  }

  /**
   * 解析并归一化条目颜色（对齐 KeePass PwEntry.ForegroundColor 语义）：
   * 仅接受 #RRGGBB 格式并归一化为大写，非法/空值返回 undefined（渲染时继承默认色）。
   * @param color 数据库中存储的颜色字符串
   */
  public static parseEntryColor(color: string | undefined): string | undefined {
    if (!color || !KdbxUtils.ENTRY_COLOR_PATTERN.test(color)) {
      return undefined;
    }
    return color.toUpperCase();
  }
}

/**
 * 搜索结果
 */
export interface KdbxSearchResult {
  filteredGroups: Array<KdbxGroup>; // 过滤后的分组列表
  filteredEntries: Array<KdbxEntry>; // 过滤后的条目列表
}

export interface KdbxIndexer {
  /**
   * 索引器值
   */
  indexerValues: Array<string>;

  /**
   * 索引器映射
   */
  indexerMap: Map<string, number>;
}

/**
 * 清理结果统计
 */
export interface CleanResult {
  /** 被删除的历史版本总数 */
  deletedHistoryCount: number;
  /** 被删除的孤儿附件总数 */
  deletedBinariesCount: number;
}