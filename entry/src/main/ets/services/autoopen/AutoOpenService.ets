import { ByteUtils, Kdbx, KdbxBinaries, KdbxBinary, KdbxBinaryDiskRef, KdbxBinaryWithHash, KdbxEntry, KdbxGroup, ProtectedValue } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KdbxUtils, ResourceManager } from '../../common/utils';
import {
  AUTO_OPEN_GROUP_NAME,
  AUTO_OPEN_KEY_FILE_ATTACHMENT_NAME,
  AutoOpenFieldName
} from './AutoOpenConstants';
import { AutoOpenItem } from './AutoOpenItem';
import { IfDeviceParser } from './IfDeviceParser';

const DOMAIN = 0x0000;
const TAG = 'AutoOpenService';

/** KeyFile.bin 内嵌密钥附件大小上限（字节）：密钥文件均为 KB 级，超限视为误挂大文件 */
const MAX_KEY_FILE_ATTACHMENT_BYTES = 16 * 1024 * 1024;

/**
 * AutoOpen 组扫描与条目解析服务
 *
 * 与 KeePass 桌面 / KeeAutoExec / keepass2android 兼容：
 * - 从根组递归查找名为 AutoOpen 的组（大小写不敏感）；
 * - 命中组收集其全部层级条目，不再下钻该子树查找更多 AutoOpen 组；
 * - URL 为空的条目忽略；Expires 过期默认禁用，自定义 Enabled 覆盖；
 * - 结果按 Priority 稳定排序（默认按扫描顺序）。
 */
export class AutoOpenService {
  /**
   * 递归收集 AutoOpen 组内的全部条目（含根组自身命中）
   * @param database 已打开的数据库
   */
  public static collectAutoOpenEntries(database: Kdbx): KdbxEntry[] {
    const result: KdbxEntry[] = [];
    const root = database.getDefaultGroup();
    if (!root) {
      return result;
    }
    AutoOpenService.collectEntriesFromGroup(root, result);
    return result;
  }

  /**
   * 扫描并解析 AutoOpen 条目
   * @param database 已打开的数据库
   * @param parentIocKey 归属父库 iocKey
   */
  public static scan(database: Kdbx, parentIocKey: string): AutoOpenItem[] {
    const items: AutoOpenItem[] = [];
    const entries = AutoOpenService.collectAutoOpenEntries(database);
    for (const entry of entries) {
      const url = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_URL);
      if (url.length === 0) {
        continue;
      }
      items.push(AutoOpenService.makeItem(entry, parentIocKey, items.length));
    }
    // 按 Priority 稳定排序（保留扫描顺序为次序）
    const order = new Map<string, number>();
    items.forEach((item: AutoOpenItem, index: number) => {
      order.set(item.entryUuid, index);
    });
    items.sort((a: AutoOpenItem, b: AutoOpenItem): number => {
      if (a.priority !== b.priority) {
        return a.priority - b.priority;
      }
      return (order.get(a.entryUuid) ?? 0) - (order.get(b.entryUuid) ?? 0);
    });
    return items;
  }

  /**
   * 是否存在未显式配置指定设备的 AutoOpen 条目（M5 根组提示条判定）
   * 与 kp2a GroupBaseActivity.UpdateChildDbInfo 对齐：
   * 任一条目 IfDevice 未显式命中本设备（无字段 / 未列出）即提示用户配置
   * @param database 已打开的数据库
   * @param parentIocKey 归属父库 iocKey
   * @param deviceId 设备 ID
   */
  public static hasUnconfiguredForDevice(database: Kdbx, parentIocKey: string, deviceId: string): boolean {
    const items: AutoOpenItem[] = AutoOpenService.scan(database, parentIocKey);
    for (const item of items) {
      if (!IfDeviceParser.isEnabled(item.ifDeviceRaw, deviceId).isExplicit) {
        return true;
      }
    }
    return false;
  }

  /**
   * 解析单条 AutoOpen 条目
   * @param entry 条目
   * @param parentIocKey 归属父库 iocKey
   * @param defaultPriority 默认优先级（扫描顺序）
   */
  public static makeItem(entry: KdbxEntry, parentIocKey: string, defaultPriority: number): AutoOpenItem {
    const item = new AutoOpenItem();
    item.sourceIocKey = parentIocKey;
    item.entryUuid = entry.uuid.id;
    item.parentGroupId = entry.parentGroup ? entry.parentGroup.uuid.id : '';
    item.title = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_TITLE);
    item.url = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_URL);
    item.keyFilePath = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_USERNAME);
    item.passwordText = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_PASSWORD);
    item.iconId = entry.icon ?? 0;
    item.customIconId = entry.customIcon ? entry.customIcon.id : '';
    item.lastModificationTime = entry.lastModTime;

    // 默认规则：条目过期则禁用
    let enabled = true;
    if (entry.times && entry.times.expires === true && entry.times.expiryTime
      && entry.times.expiryTime.getTime() <= Date.now()) {
      enabled = false;
    }
    // 自定义字段覆盖
    const enabledOverride = AutoOpenService.getBoolField(entry, AutoOpenFieldName.ENABLED);
    if (enabledOverride !== undefined) {
      enabled = enabledOverride;
    }
    item.enabled = enabled;

    const visibleOverride = AutoOpenService.getBoolField(entry, AutoOpenFieldName.VISIBLE);
    item.visible = visibleOverride === undefined ? true : visibleOverride;

    const priorityRaw = KdbxUtils.getFieldValueString(entry.fields, AutoOpenFieldName.PRIORITY)
      .replace(/^\s+/, '').replace(/\s+$/, '');
    if (priorityRaw.length > 0) {
      const parsed = Number(priorityRaw);
      item.priority = isNaN(parsed) ? defaultPriority : Math.trunc(parsed);
    } else {
      item.priority = defaultPriority;
    }

    item.ifDeviceRaw = KdbxUtils.getFieldValueString(entry.fields, AutoOpenFieldName.IF_DEVICE);
    item.iocUserName = KdbxUtils.getFieldValueString(entry.fields, AutoOpenFieldName.IOC_USER_NAME);
    item.iocPassword = KdbxUtils.getFieldValueString(entry.fields, AutoOpenFieldName.IOC_PASSWORD);
    item.customStrings = AutoOpenService.collectCustomStrings(entry);
    item.skipIfNotExists = AutoOpenService.getBoolField(entry, AutoOpenFieldName.SKIP_IF_NOT_EXISTS) === true
      || AutoOpenService.getBoolField(entry, AutoOpenFieldName.SKIP_IF_NOT_EXISTS_LEGACY) === true;
    item.skipIfKeyFileNotExists =
      AutoOpenService.getBoolField(entry, AutoOpenFieldName.SKIP_IF_KEY_FILE_NOT_EXISTS) === true;
    item.hasKeyFileAttachment = entry.binaries.has(AUTO_OPEN_KEY_FILE_ATTACHMENT_NAME);
    return item;
  }

  /**
   * 按 UUID 在 AutoOpen 组条目中定位条目
   * @param database 已打开的数据库
   * @param entryUuid 条目 UUID（KdbxUuid.id）
   */
  public static findAutoOpenEntry(database: Kdbx, entryUuid: string): KdbxEntry | undefined {
    const entries: KdbxEntry[] = AutoOpenService.collectAutoOpenEntries(database);
    for (const entry of entries) {
      if (entry.uuid.id === entryUuid) {
        return entry;
      }
    }
    return undefined;
  }

  /**
   * 读取条目 KeyFile.bin 内嵌密钥附件内容（UserName 密钥路径为空时的密钥来源，
   * kp2a KeeAutoExec.cs:339-345 同义）：兼容内存态（ProtectedValue/ArrayBuffer）、
   * 哈希包裹（KdbxBinaryWithHash）与 S4 附件磁盘化（KdbxBinaryDiskRef 异步回读）。
   * @param database 父数据库模型
   * @param entryUuid AutoOpen 条目 UUID
   * @throws Error 条目/附件缺失、磁盘引用回读失败或超过大小上限时抛出
   */
  public static async readKeyFileAttachment(database: Kdbx, entryUuid: string): Promise<ArrayBuffer> {
    const entry: KdbxEntry | undefined = AutoOpenService.findAutoOpenEntry(database, entryUuid);
    if (entry === undefined) {
      throw new Error(ResourceManager.getString($r('app.string.error_keyfile_not_found')));
    }
    const binary: KdbxBinary | KdbxBinaryWithHash | undefined =
      entry.binaries.get(AUTO_OPEN_KEY_FILE_ATTACHMENT_NAME);
    if (binary === undefined) {
      throw new Error(ResourceManager.getString($r('app.string.error_keyfile_not_found')));
    }
    const content: ArrayBuffer | undefined =
      await AutoOpenService.resolveBinaryContent(database, binary);
    if (content === undefined) {
      throw new Error(ResourceManager.getString($r('app.string.error_keyfile_not_found')));
    }
    if (content.byteLength > MAX_KEY_FILE_ATTACHMENT_BYTES) {
      hilog.warn(DOMAIN, TAG, 'KeyFile.bin attachment too large: %{public}d bytes', content.byteLength);
      throw new Error(ResourceManager.getString($r('app.string.error_keyfile_attachment_too_large')));
    }
    return content;
  }

  /**
   * 解析附件二进制为字节内容（含哈希包裹递归与磁盘引用异步回读；失败返回 undefined）
   */
  private static async resolveBinaryContent(database: Kdbx,
    binary: KdbxBinary | KdbxBinaryWithHash): Promise<ArrayBuffer | undefined> {
    if (KdbxBinaries.isKdbxBinaryWithHash(binary)) {
      const wrapped: KdbxBinaryWithHash = binary as KdbxBinaryWithHash;
      return AutoOpenService.resolveBinaryContent(database, wrapped.value);
    }
    if (binary instanceof ProtectedValue) {
      return binary.getBinary();
    }
    if (binary instanceof ArrayBuffer) {
      return binary;
    }
    if (binary instanceof KdbxBinaryDiskRef) {
      try {
        return await database.binaries.readDiskRef(binary);
      } catch (error) {
        hilog.warn(DOMAIN, TAG, 'read disk-ref KeyFile.bin failed: %{public}s', `${error}`);
        return undefined;
      }
    }
    return undefined;
  }

  /**
   * 在根组下查找名为 AutoOpen 的组，不存在则创建（子库管理页「添加子库」用）
   * @param database 数据库
   * @param create 不存在时是否创建
   */
  public static findOrCreateAutoOpenGroup(database: Kdbx, create: boolean): KdbxGroup | undefined {
    const root = database.getDefaultGroup();
    if (!root) {
      return undefined;
    }
    for (const group of root.groups) {
      if (AutoOpenService.isAutoOpenGroupName(group)) {
        return group;
      }
    }
    if (!create) {
      return undefined;
    }
    return database.createGroup(root, AUTO_OPEN_GROUP_NAME);
  }

  /**
   * 判断组名是否为 AutoOpen（大小写不敏感）
   */
  public static isAutoOpenGroupName(group: KdbxGroup): boolean {
    return (group.name ?? '').toLowerCase() === AUTO_OPEN_GROUP_NAME.toLowerCase();
  }

  /**
   * 收集条目中除标准字段与框架已知字段外的全部自定义字符串字段原文
   * （含 S3Region/S3PathStyle 等；内容不解释，交由目标存储 rebuilder 按需读取）
   */
  private static collectCustomStrings(entry: KdbxEntry): Map<string, string> {
    const result = new Map<string, string>();
    for (const field of entry.fields.entries()) {
      const name = field[0];
      if (AutoOpenService.isFrameworkFieldName(name)) {
        continue;
      }
      const value = field[1];
      if (typeof value !== 'string' || value.length === 0) {
        continue;
      }
      result.set(name, value);
    }
    return result;
  }

  /**
   * 是否标准字段（Title/UserName/...）或框架已知自定义字段（AutoOpenFieldName）：
   * 这些字段有专属解析逻辑，不进 customStrings 透传包
   */
  private static isFrameworkFieldName(name: string): boolean {
    if (name === KdbxUtils.FIELD_TITLE || name === KdbxUtils.FIELD_USERNAME
      || name === KdbxUtils.FIELD_PASSWORD || name === KdbxUtils.FIELD_URL
      || name === KdbxUtils.FIELD_NOTES) {
      return true;
    }
    return name === AutoOpenFieldName.IF_DEVICE || name === AutoOpenFieldName.ENABLED
      || name === AutoOpenFieldName.VISIBLE || name === AutoOpenFieldName.PRIORITY
      || name === AutoOpenFieldName.IOC_USER_NAME || name === AutoOpenFieldName.IOC_PASSWORD
      || name === AutoOpenFieldName.SKIP_IF_NOT_EXISTS
      || name === AutoOpenFieldName.SKIP_IF_NOT_EXISTS_LEGACY
      || name === AutoOpenFieldName.SKIP_IF_KEY_FILE_NOT_EXISTS;
  }

  private static collectEntriesFromGroup(group: KdbxGroup, result: KdbxEntry[]): void {
    if (AutoOpenService.isAutoOpenGroupName(group)) {
      // 命中：收集该组全部层级条目，不再下钻查找更多 AutoOpen 组
      for (const entry of group.allEntries()) {
        result.push(entry);
      }
      return;
    }
    for (const sub of group.groups) {
      AutoOpenService.collectEntriesFromGroup(sub, result);
    }
  }

  /**
   * 读取 True/False 布尔字段（大小写不敏感；其余值视为未设置）
   */
  private static getBoolField(entry: KdbxEntry, fieldName: string): boolean | undefined {
    const raw = KdbxUtils.getFieldValueString(entry.fields, fieldName).replace(/^\s+/, '').replace(/\s+$/, '');
    if (raw.length === 0) {
      return undefined;
    }
    const lower = raw.toLowerCase();
    if (lower === 'true') {
      return true;
    }
    if (lower === 'false') {
      return false;
    }
    return undefined;
  }
}
