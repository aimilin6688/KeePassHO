import cryptoFramework from '@ohos.security.cryptoFramework';
import { buffer } from '@kit.ArkTS';
import { UUID } from '../models/KdbxTypes';


export class KdbxUtils {
  // 创建随机数生成器
  private static rand: cryptoFramework.Random = cryptoFramework.createRandom();

  /**
   * 生成随机数填充 Uint8Array
   * @param uint8Array
   * @returns
   */
  static generateRandom(uint8Array: Uint8Array): Uint8Array {
    KdbxUtils.fillRandom(uint8Array);
    return uint8Array;
  }

  /**
   * 生成随机数填充 Uint8Array
   * @param uint8Array
   * @returns
   */
  static fillRandom(uint8Array: Uint8Array): void {
    try {
      // 生成随机字节
      const dataBlob: cryptoFramework.DataBlob = KdbxUtils.rand.generateRandomSync(uint8Array.length);

      // 覆盖原始数组内容
      uint8Array.set(dataBlob.data);
      // 打印随机数
      console.log("Random data:", Array.from(uint8Array).map(b => b.toString(16).padStart(2, '0')).join(''));
    } catch (error) {
      console.error("Random generation failed:", error.code, error.message);
    }
  }

  /**
   * 十六进制字符串转字节数组
   * @param hex
   * @returns
   */
  static hexToBytes(hex: string): Uint8Array {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < hex.length; i += 2) {
      bytes[i / 2] = parseInt(hex.substr(i, 2), 16);
    }
    return bytes;
  };

  /**
   * 字节数组转十六进制字符串
   * @param bytes
   * @returns
   */
  static bytesToHex(bytes: Uint8Array): string {
    return Array.from(bytes)
      .map(b => b.toString(16).padStart(2, '0'))
      .join('');
  };

  /**
   * 字符串转字节数组
   * @param str
   * @returns
   */
  static strToBytes(str: string): Uint8Array {
    return new Uint8Array(buffer.from(str, 'utf8').buffer);
  }

  /**
   * 字节数组转字符串
   * @param bytes
   * @returns
   */
  static bytesToStr(bytes: Uint8Array): string {
    return buffer.from(bytes).toString('utf8');
  }

  /**
   * 转换为UUID
   * @param uuid UUID或字符串
   * @returns UUID
   */
  static toUUID(uuid: string | UUID): UUID {
    return uuid instanceof Uint8Array ? uuid : KdbxUtils.strToBytes(uuid);
  }
}