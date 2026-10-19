import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid } from 'kdbxweb';

import { AutoOpenFieldName } from './AutoOpenConstants';
import { AutoOpenPathResolver } from './AutoOpenPathResolver';
import { AutoOpenService } from './AutoOpenService';
import { IfDeviceParser } from './IfDeviceParser';
import { SchemeMapper } from './SchemeMapper';
import { DbFileParam } from '../TypeDefined';
import { KdbxUtils, Sm4Utils } from '../../common/utils';
import { PageConfig, StorageConfig, StorageType } from '../../storage';
import { FileStorageFactory } from '../../storage/FileStorageFactory';

/**
 * 远端子库连接凭据（解密明文，仅在内存中，写完即弃）
 */
class IocCredentials {
  userName: string;
  password: string;

  constructor(userName: string, password: string) {
    this.userName = userName;
    this.password = password;
  }
}

/**
 * AutoOpen 子库条目写服务（M4 子数据库管理页 / M6 远端子库）
 *
 * 与 kp2a ConfigureChildDatabasesActivity / KeeAutoExec 对齐：
 * - 新添加的子库条目仅对本设备启用（IfDevice 白名单，保守默认）；
 * - URL / 密钥文件路径与父库同目录时写 `{DB_DIR}{ENV_DIRSEP}相对路径`（跨设备可移植）；
 * - 子库主密码经 memoryProtection 判定写入（通常为 ProtectedValue 内存保护字段）；
 * - 「本设备停用」改写 IfDevice 后若为空串则删除该字段（避免残留空字段）；
 * - 远端子库（M6）：URL 按 scheme 反向映射（SchemeMapper.buildUrl），
 *   凭据型（WEBDAV/S3/FTP）追加 IocUserName/IocPassword 自定义字符串
 *   （与 KeeAutoExec.cs:409-414 同名同义，PC 端可读；IocPassword 内存保护），
 *   OAuth 型仅写 URL（令牌留设备本地，打开时从 RecentFiles 克隆）。
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
    const keyFilePath: string = child.keyLocation?.filePath ?? '';
    if (keyFilePath.length > 0) {
      entry.setField(KdbxUtils.FIELD_USERNAME,
        AutoOpenPathResolver.makeRelative(keyFilePath, parentFilePath), memoryProtection.userName);
    }
    // M6：凭据型远端子库写 IocUserName/IocPassword（OAuth 型不写，令牌设备本地）
    if (child.storageType !== StorageType.LOCAL) {
      const credentials: IocCredentials | undefined = AutoOpenEntryService.extractIocCredentials(child);
      if (credentials !== undefined) {
        entry.setField(AutoOpenFieldName.IOC_USER_NAME, credentials.userName, false);
        entry.setField(AutoOpenFieldName.IOC_PASSWORD, credentials.password, true);
      }
      AutoOpenEntryService.writeExtraFields(entry, child);
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
   * 从子库 storageConfig 解密读取远端连接凭据（按 PageConfig.childDbCredentialKeys
   * 声明的字段名：WEBDAV/FTP 登录凭据、S3 AK/SK 等，类实例与 plain JSON 同名字段）；
   * 未声明凭据键（OAuth 型）或 LOCAL 返回 undefined（无连接凭据概念 / 令牌不入库）；
   * 解密失败（SM4 密钥变更/密文损坏）返回 undefined，由调用方跳过 Ioc 字段写入
   */
  private static extractIocCredentials(child: DbFileParam): IocCredentials | undefined {
    const config: StorageConfig | undefined = child.storageConfig;
    if (config === undefined || config === null) {
      return undefined;
    }
    const pageConfig = AutoOpenEntryService.findPageConfig(child.storageType);
    const credentialKeys = pageConfig?.childDbCredentialKeys;
    if (credentialKeys === undefined) {
      return undefined;
    }
    try {
      const record = config as Record<string, Object>;
      const userName: Object | undefined = record[credentialKeys.userKey];
      const password: Object | undefined = record[credentialKeys.passwordKey];
      if (userName === undefined || password === undefined) {
        return undefined;
      }
      return new IocCredentials(Sm4Utils.tryDecryptWithPrefix(String(userName)),
        Sm4Utils.tryDecryptWithPrefix(String(password)));
    } catch (error) {
      return undefined;
    }
  }

  /**
   * 写侧附加自定义字符串（按 PageConfig.childDbExtraFields 声明，如 S3 的
   * S3Region/S3PathStyle 微调字段）：由存储声明的函数从 storageConfig 产出
   * 字段表，框架统一写入条目
   */
  private static writeExtraFields(entry: KdbxEntry, child: DbFileParam): void {
    if (child.storageConfig === undefined || child.storageConfig === null) {
      return;
    }
    const pageConfig = AutoOpenEntryService.findPageConfig(child.storageType);
    const extraFields = pageConfig?.childDbExtraFields;
    if (extraFields === undefined) {
      return;
    }
    const fields: Map<string, string> = extraFields(child.storageConfig);
    for (const field of fields.entries()) {
      entry.fields.set(field[0], field[1]);
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
