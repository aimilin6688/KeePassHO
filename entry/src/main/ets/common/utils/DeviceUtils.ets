import { deviceInfo } from '@kit.BasicServicesKit';

/**
 * 设备工具类
 */
export class DeviceUtils {

  /**
   * 是否模拟器
   * @returns
   */
  public static isEmulator():boolean {
    return deviceInfo.productModel === 'emulator';
  }
}