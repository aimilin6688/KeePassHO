import { Kdbx, KdbxEntry, KdbxGroup } from 'kdbxweb';
import { KdbxUtils } from '../../common/utils';
import { AUTO_OPEN_GROUP_NAME, AutoOpenFieldName } from './AutoOpenConstants';
import { AutoOpenItem } from './AutoOpenItem';
import { IfDeviceParser } from './IfDeviceParser';

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
    item.skipIfNotExists = AutoOpenService.getBoolField(entry, AutoOpenFieldName.SKIP_IF_NOT_EXISTS) === true
      || AutoOpenService.getBoolField(entry, AutoOpenFieldName.SKIP_IF_NOT_EXISTS_LEGACY) === true;
    item.skipIfKeyFileNotExists =
      AutoOpenService.getBoolField(entry, AutoOpenFieldName.SKIP_IF_KEY_FILE_NOT_EXISTS) === true;
    return item;
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
