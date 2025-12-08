import { aegis, SafeRandom } from '@hw-agconnect/petal-aegis';
import { ProtectedValue } from 'kdbxweb';
import { AssetUtils } from './AssetUtils';

/**
 * SM4加密工具类
 * 参考文档：https://developer.huawei.com/consumer/cn/doc/AppGallery-connect-References/sm4dectexthex-0000001937701458
 */
export class Sm4Utils {
  /**
   * 密钥文件名
   */
  private static readonly ASSET_SM4_KEY_NAME = 'sm4_key';
  /**
   * 密钥内存保护KEY，只会初始化一次
   */
  private static SM4_KEY: ProtectedValue | undefined = undefined;
  /**
   * 加密前缀
   */
  private static readonly SM4_ENCRYPT_PREFIX = 'SM4:';

  /**
   * 初始化
   */
  public static init(): Promise<void> {
    return new Promise((resolve, reject) => {
      try {
        Sm4Utils.initKey();
        resolve();
      } catch (error) {
        reject(error);
      }
    });
  }

  /**
   * 初始化密码，16进制的字符串
   * @returns
   */
  public static initKey(): string {
    // 如果已经初始化过，则直接返回
    if (Sm4Utils.SM4_KEY != undefined) {
      return Sm4Utils.SM4_KEY.getText();
    }

    // 关键资产中查询是否存在
    let key = AssetUtils.querySync(Sm4Utils.ASSET_SM4_KEY_NAME);
    if (key != undefined) {
      Sm4Utils.SM4_KEY = ProtectedValue.fromString(key);
      return key;
    }

    key = SafeRandom.ohAegRandomHex(16);
    AssetUtils.saveSync(Sm4Utils.ASSET_SM4_KEY_NAME, key);
    Sm4Utils.SM4_KEY = ProtectedValue.fromString(key);
    return key;
  }

  /**
   * 加密
   * @param data
   * @returns 返回16进制的字符串
   */
  public static encrypt(data: string): string {
    if (!data) {
      return '';
    }
    return aegis.sm4EncTextHexSync(aegis.SM4Alg.SM4_CBC_PKCS5Padding, data, Sm4Utils.initKey());
  }

  /**
   * 解密
   * @param data 16进制的字符串
   * @returns 明文字符串
   */
  public static decrypt(data: string): string {
    if (!data) {
      return '';
    }
    return aegis.sm4DecTextHexSync(aegis.SM4Alg.SM4_CBC_PKCS5Padding, data, Sm4Utils.initKey());
  }


  /**
   * SM4加密，返回有前缀的字符串
   * @param data 明文字符串
   * @returns 返回16进制的字符串， SM4:1234567890123
   */
  public static encryptWithPrefix(data: string): string {
    if (!data) {
      return '';
    }
    if (data && data.startsWith(Sm4Utils.SM4_ENCRYPT_PREFIX)) {
      return data;
    }
    return Sm4Utils.SM4_ENCRYPT_PREFIX + aegis.sm4EncTextHexSync(aegis.SM4Alg.SM4_CBC_PKCS5Padding, data, Sm4Utils.initKey());
  }

  /**
   * SM4解密，认准SM4:前缀，有前缀才解密
   * @param data 16进制的字符串， SM4:1234567890123
   * @returns 明文字符串
   */
  public static decryptWithPrefix(data: string): string {
    if (!data) {
      return '';
    }
    if (data && data.startsWith(Sm4Utils.SM4_ENCRYPT_PREFIX)) {
      return aegis.sm4DecTextHexSync(aegis.SM4Alg.SM4_CBC_PKCS5Padding, data.substring(Sm4Utils.SM4_ENCRYPT_PREFIX.length), Sm4Utils.initKey());
    }
    return data;
  }
}
