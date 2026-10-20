import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid } from 'kdbxweb';

import { AutoOpenFieldName } from './AutoOpenConstants';
import { AutoOpenPathResolver } from './AutoOpenPathResolver';
import { AutoOpenService } from './AutoOpenService';
import { IfDeviceParser } from './IfDeviceParser';
import { SchemeMapper } from './SchemeMapper';
import { DbFileParam } from '../TypeDefined';
import { KdbxUtils } from '../../common/utils';
import { IocCredentials, PageConfig, StorageConfig, StorageType } from '../../storage';
import { FileStorageFactory } from '../../storage/FileStorageFactory';

/**
 * AutoOpen 子库条目写服务（M4 子数据库管理页 / M6 远端子库）
 *
 * 与 kp2a ConfigureChildDatabasesActivity / KeeAutoExec 对齐：
 * - 新添加的子库条目仅对本设备启用（IfDevice 白名单，保守默认）；
 * - URL / 密钥文件路径与父库同目录时写 `{DB_DIR}{ENV_DIRSEP}相对路径`（跨设备可移植）；
 * - 子库主密码经 memoryProtection 判定写入（通常为 ProtectedValue 内存保护字段）；
 * - 「本设备停用」改写 IfDevice 后若为空串则删除该字段（避免残留空字段）；
 * - 远端子库（M6）：URL 按 scheme 反向映射（SchemeMapper.buildUrl）；
 *   连接凭据/附加字段经 PageConfig.childDb 端口（M6.9）——凭据型适配器声明
 *   extractCredentials 时写 IocUserName/IocPassword（与 KeeAutoExec.cs:409-414
 *   同名同义，PC 端可读；IocPassword 内存保护）与 extraFields 附加字段
 *   （如 S3 微调项），OAuth 型不写（令牌留设备本地）。
 */
export class AutoOpenEntryService {
  /**
   * 为已打开的子库在父库生成 AutoOpen 条目
   * @param parentDatabase 父库模型
   * @param parentFilePath 父库文件路径（相对化基准）
   * @param child 子库文件参数（须已打开）
   * @param deviceId 本设备 ID
   * @returns 新建条目；根组缺失时返回 undefined
   */
  public static addEntryForOpenedChild(parentDatabase: Kdbx, parentFilePath: string,
    child: DbFileParam, deviceId: string): KdbxEntry | undefined {
    const group: KdbxGroup | undefined = AutoOpenService.findOrCreateAutoOpenGroup(parentDatabase, true);
    if (group === undefined) {
      return undefined;
    }
    const entry: KdbxEntry = parentDatabase.createEntry(group);
    const memoryProtection = parentDatabase.meta.memoryProtection ?? {};
    entry.setField(KdbxUtils.FIELD_TITLE, child.fileName, memoryProtection.title);
    entry.setField(KdbxUtils.FIELD_URL,
      AutoOpenEntryService.buildChildUrl(child, parentFilePath), memoryProtection.url);
    entry.setField(KdbxUtils.FIELD_PASSWORD, child.password, memoryProtection.password ?? true);
    // 无密钥文件时必须显式清空：KdbxEntry.create 预填 UserName=父库 meta.defaultUser，
    // 残留值会被 AutoOpenService.makeItem 误读为子库密钥文件路径（KeeAutoExec 约定）
    const keyFilePath: string = child.keyLocation?.filePath ?? '';
    entry.setField(KdbxUtils.FIELD_USERNAME,
      keyFilePath.length > 0 ? AutoOpenPathResolver.makeRelative(keyFilePath, parentFilePath) : '',
      memoryProtection.userName);
    // M6：远端子库写连接凭据/附加字段（经 childDb 端口；OAuth 型不写，令牌设备本地）
    if (child.storageType !== StorageType.LOCAL) {
      AutoOpenEntryService.writeRemoteFields(entry, child);
    }
    AutoOpenEntryService.writeOnlyThisDevice(entry, deviceId);
    return entry;
  }

  /**
   * 子库条目 URL（M6.4）：
   * - LOCAL：{DB_DIR} 相对化（M1 既有语义，跨设备可移植）；
   * - 远端：SchemeMapper.buildUrl 反向映射 scheme URL
   *   （远端路径不做相对化，makeRelative 仅对本地路径有意义）。
   */
  private static buildChildUrl(child: DbFileParam, parentFilePath: string): string {
    if (child.storageType === StorageType.LOCAL) {
      return AutoOpenPathResolver.makeRelative(child.filePath, parentFilePath);
    }
    return SchemeMapper.buildUrl(child.storageType, child.filePath, child.storageConfig);
  }

  /**
   * 远端子库连接字段写入（经 PageConfig.childDb 端口，M6.9）：
   * - extractCredentials（凭据型适配器声明）：从 storageConfig 解密提取连接
   *   凭据 → 写 IocUserName/IocPassword；未声明（OAuth 型）不写——令牌不入 kdbx；
   * - extraFields（可选声明）：由 storageConfig 产出附加自定义字符串字段表
   *   （如 S3 的 S3Region/S3PathStyle 微调字段），框架统一写入。
   * 解密失败（SM4 密钥变更/密文损坏）跳过 Ioc 字段写入，不阻塞其余字段。
   */
  private static writeRemoteFields(entry: KdbxEntry, child: DbFileParam): void {
    const config: StorageConfig | undefined = child.storageConfig;
    if (config === undefined || config === null) {
      return;
    }
    const pageConfig = AutoOpenEntryService.findPageConfig(child.storageType);
    const childDb = pageConfig?.childDb;
    if (childDb === undefined) {
      return;
    }
    const extract = childDb.extractCredentials;
    if (extract !== undefined) {
      const credentials: IocCredentials | undefined = extract(config);
      if (credentials !== undefined) {
        entry.setField(AutoOpenFieldName.IOC_USER_NAME, credentials.userName, false);
        entry.setField(AutoOpenFieldName.IOC_PASSWORD, credentials.password, true);
      }
    }
    const extra = childDb.extraFields;
    if (extra !== undefined) {
      const fields: Map<string, string> = extra(config);
      for (const field of fields.entries()) {
        entry.fields.set(field[0], field[1]);
      }
    }
  }

  /**
   * 经 FileStorageFactory 注册表查找存储的页面配置（未注册返回 undefined）
   */
  private static findPageConfig(storageType: StorageType): PageConfig | undefined {
    const storage = FileStorageFactory.getInstance().getStorageMap().get(storageType);
    return storage === undefined ? undefined : storage.getPageConfig();
  }

  /**
   * 设置条目在本设备的启用状态（改写 IfDevice 字段）
   * @param entry AutoOpen 条目
   * @param deviceId 本设备 ID
   * @param enabled 是否启用
   */
  public static setEntryDeviceEnabled(entry: KdbxEntry, deviceId: string, enabled: boolean): void {
    const raw: string = KdbxUtils.getFieldValueString(entry.fields, AutoOpenFieldName.IF_DEVICE);
    const updated: string = IfDeviceParser.setDeviceEnabled(raw, deviceId, enabled);
    if (updated.length === 0) {
      entry.fields.delete(AutoOpenFieldName.IF_DEVICE);
      return;
    }
    entry.fields.set(AutoOpenFieldName.IF_DEVICE, updated);
  }

  /**
   * 复制为本设备副本：原条目本设备置停用；新条目（新 UUID、同组）仅本设备启用、
   * Title 追加 ` (设备型号)`——用于「多设备各自一条目」场景
   * @param parentDatabase 父库模型
   * @param entry 原 AutoOpen 条目
   * @param deviceId 本设备 ID
   * @param deviceModel 设备型号（Title 后缀）
   * @returns 新克隆条目；条目无父组时返回 undefined（原条目不修改）
   */
  public static copyEntryForDevice(parentDatabase: Kdbx, entry: KdbxEntry,
    deviceId: string, deviceModel: string): KdbxEntry | undefined {
    const group: KdbxGroup | undefined = entry.parentGroup;
    if (group === undefined) {
      return undefined;
    }
    entry.pushHistory();
    entry.maintainHistory(parentDatabase.meta.historyMaxItems, parentDatabase.meta.historyMaxSize);
    AutoOpenEntryService.setEntryDeviceEnabled(entry, deviceId, false);
    const clone: KdbxEntry = parentDatabase.createEntry(group);
    clone.copyFrom(entry);
    clone.uuid = new KdbxUuid();
    const title: string = KdbxUtils.getFieldValueString(clone.fields, KdbxUtils.FIELD_TITLE);
    const suffix: string = deviceModel.length > 0 ? ' (' + deviceModel + ')' : '';
    clone.setField(KdbxUtils.FIELD_TITLE, title + suffix, false);
    AutoOpenEntryService.writeOnlyThisDevice(clone, deviceId);
    return clone;
  }

  /**
   * 写入 IfDevice = 仅本设备启用
   */
  private static writeOnlyThisDevice(entry: KdbxEntry, deviceId: string): void {
    const devices = new Map<string, boolean>();
    devices.set(deviceId, true);
    entry.fields.set(AutoOpenFieldName.IF_DEVICE, IfDeviceParser.build(devices));
  }
}
