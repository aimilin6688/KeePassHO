import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid } from 'kdbxweb';

import { AutoOpenFieldName } from './AutoOpenConstants';
import { AutoOpenPathResolver } from './AutoOpenPathResolver';
import { AutoOpenService } from './AutoOpenService';
import { IfDeviceParser } from './IfDeviceParser';
import { DbFileParam } from '../TypeDefined';
import { KdbxUtils } from '../../common/utils';

/**
 * AutoOpen 子库条目写服务（M4 子数据库管理页）
 *
 * 与 kp2a ConfigureChildDatabasesActivity / KeeAutoExec 对齐：
 * - 新添加的子库条目仅对本设备启用（IfDevice 白名单，保守默认）；
 * - URL / 密钥文件路径与父库同目录时写 `{DB_DIR}{ENV_DIRSEP}相对路径`（跨设备可移植）；
 * - 子库主密码经 memoryProtection 判定写入（通常为 ProtectedValue 内存保护字段）；
 * - 「本设备停用」改写 IfDevice 后若为空串则删除该字段（避免残留空字段）。
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
      AutoOpenPathResolver.makeRelative(child.filePath, parentFilePath), memoryProtection.url);
    entry.setField(KdbxUtils.FIELD_PASSWORD, child.password, memoryProtection.password ?? true);
    const keyFilePath: string = child.keyLocation?.filePath ?? '';
    if (keyFilePath.length > 0) {
      entry.setField(KdbxUtils.FIELD_USERNAME,
        AutoOpenPathResolver.makeRelative(keyFilePath, parentFilePath), memoryProtection.userName);
    }
    AutoOpenEntryService.writeOnlyThisDevice(entry, deviceId);
    return entry;
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
