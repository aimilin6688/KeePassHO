import { aegis, SafeRandom } from '@hw-agconnect/petal-aegis';
import { ProtectedValue } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AssetUtils } from './AssetUtils';
import { ConfigDecryptError } from './ConfigDecryptError';

const DOMAIN = 0x0000;
const TAG = 'Sm4Utils';

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
    return new Promise((resolve) => {
      try {
        Sm4Utils.initKey();
      } catch (error) {
        // 瞬时故障（Asset 服务不可用/IPC 失败等）不在此中断启动：
        // 首次实际加解密时会经 initKey 惰性重试，届时仍失败才对用户可见
        hilog.error(DOMAIN, TAG, 'init sm4 key failed: %{public}s', `${error}`);
      }
      return resolve();
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

    // 关键资产中查询是否存在（未找到返回 undefined；瞬时故障上抛，绝不误生成新钥）
    let key = AssetUtils.querySync(Sm4Utils.ASSET_SM4_KEY_NAME);
    if (key != undefined) {
      Sm4Utils.SM4_KEY = ProtectedValue.fromString(key);
      return key;
    }

    // 确认密钥不存在（首次启动或资产库未创建）：生成新钥并醒目记录——
    // 若此前存在旧密文（升级/换机后资产丢失），旧密文自此永久不可解密，
    // 由 ConfigDecryptError 在解密路径给出友好引导
    key = SafeRandom.ohAegRandomHex(16);
    hilog.warn(DOMAIN, TAG, 'sm4_key not found in asset store, generating NEW key (old SM4-encrypted data becomes undecryptable)');
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
   * @throws ConfigDecryptError 解密失败（密钥变更/密文损坏，不可恢复，需重新编辑配置）
   */
  public static decryptWithPrefix(data: string): string {
    if (!data) {
      return '';
    }
    if (data && data.startsWith(Sm4Utils.SM4_ENCRYPT_PREFIX)) {
      const key = Sm4Utils.initKey();
      try {
        return aegis.sm4DecTextHexSync(aegis.SM4Alg.SM4_CBC_PKCS5Padding, data.substring(Sm4Utils.SM4_ENCRYPT_PREFIX.length), key);
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'SM4 decrypt config failed: %{public}s', `${error}`);
        throw new ConfigDecryptError(error as Error);
      }
    }
    return data;
  }

  /**
   * 尝试解密有前缀的密文，解密失败（密钥变更/密文损坏）不抛出，返回空串。
   * 适用于连接配置页预填等场景：明文可恢复则回填，不可恢复则留空由用户重新输入。
   * @param data 16进制的字符串， SM4:1234567890123
   * @returns 明文字符串，解密失败返回空串
   */
  public static tryDecryptWithPrefix(data: string): string {
    try {
      return Sm4Utils.decryptWithPrefix(data);
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'SM4 try decrypt failed, return empty: %{public}s', `${error}`);
      return '';
    }
  }
}
