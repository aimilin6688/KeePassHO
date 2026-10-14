import { BusinessError, deviceInfo } from '@kit.BasicServicesKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { SettingsService } from '../SettingsService';

const DOMAIN = 0x0000;
const TAG = 'DeviceIdentity';

/**
 * 设备身份标识（IfDevice 过滤用）
 *
 * 格式与 KeeAutoExec / keepass2android 对齐：
 * `厂商 型号 (本地设备 UUID)`，并把 `!` `,` `;` 替换为 `_`。
 * 本地 UUID 首次使用时生成并持久化到设置中（HarmonyOS 无 ANDROID_ID 等价物，
 * ODID 可被用户重置且需权限，本地 UUID 最稳定）。
 */
export class DeviceIdentity {
  /** 本地设备 UUID 的设置键 */
  public static readonly KEY_DEVICE_LOCAL_UUID = 'device_local_uuid';

  private static cachedDeviceId: string = '';
  private static cachedLocalUuid: string = '';

  /**
   * 纯函数：拼接设备 ID 并替换保留字符（便于单测）
   * @param manufacturer 厂商
   * @param model 型号
   * @param rawId 原始设备标识
   */
  public static buildDeviceId(manufacturer: string, model: string, rawId: string): string {
    let id = manufacturer + ' ' + model + ' (' + rawId + ')';
    id = id.split('!').join('_').split(',').join('_').split(';').join('_');
    return id;
  }

  /**
   * 获取（不存在则生成并持久化）本地设备 UUID
   */
  public static getLocalDeviceUuid(): string {
    if (DeviceIdentity.cachedLocalUuid.length > 0) {
      return DeviceIdentity.cachedLocalUuid;
    }
    const saved = SettingsService.getSync<string>(DeviceIdentity.KEY_DEVICE_LOCAL_UUID, '');
    if (saved.length > 0) {
      DeviceIdentity.cachedLocalUuid = saved;
      return saved;
    }
    const uuid = util.generateRandomUUID();
    // 先写内存缓存再异步持久化，避免连续调用在 put 未落盘前重复生成
    DeviceIdentity.cachedLocalUuid = uuid;
    SettingsService.put(DeviceIdentity.KEY_DEVICE_LOCAL_UUID, uuid).catch((error: BusinessError) => {
      hilog.warn(DOMAIN, TAG, 'persist local uuid failed: %{public}s', error.message);
    });
    return uuid;
  }

  /**
   * 获取本设备 ID（进程内缓存）
   */
  public static getDeviceId(): string {
    if (DeviceIdentity.cachedDeviceId.length > 0) {
      return DeviceIdentity.cachedDeviceId;
    }
    DeviceIdentity.cachedDeviceId = DeviceIdentity.buildDeviceId(
      deviceInfo.manufacture, deviceInfo.productModel, DeviceIdentity.getLocalDeviceUuid());
    return DeviceIdentity.cachedDeviceId;
  }

  /**
   * 清除进程内缓存（测试用）
   */
  public static resetCache(): void {
    DeviceIdentity.cachedDeviceId = '';
    DeviceIdentity.cachedLocalUuid = '';
  }
}
