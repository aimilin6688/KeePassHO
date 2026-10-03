import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/**
 * 哈希工具类
 */
export class HashUtils {

  /**
   * 计算数据的 SHA256 哈希值（十六进制小写）
   * @param data 待计算的数据
   * @returns 十六进制小写哈希字符串
   */
  public static sha256Hex(data: ArrayBuffer): string {
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    md.updateSync({ data: new Uint8Array(data) });
    const digest: cryptoFramework.DataBlob = md.digestSync();
    return HashUtils.toHexString(digest.data);
  }

  /**
   * 字节数组转十六进制小写字符串
   * @param bytes 字节数组
   * @returns 十六进制字符串
   */
  private static toHexString(bytes: Uint8Array): string {
    let hex: string = '';
    for (let i = 0; i < bytes.length; i++) {
      const byte: string = bytes[i].toString(16);
      hex += byte.length === 1 ? '0' + byte : byte;
    }
    return hex;
  }
}
