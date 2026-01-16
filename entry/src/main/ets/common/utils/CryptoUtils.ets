import huks from '@ohos.security.huks';
import { BusinessError } from '@kit.BasicServicesKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { ByteUtils } from 'kdbxweb';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { CommonUtils } from './CommonUtils';

const DOMAIN = 0x0000;
const TAG = 'CryptoUtils';

export class CryptoUtils {
  private static readonly KeePassHO_AES_KEY_ALIAS: string = 'KeePassHO_AES_KEY_ALIAS';
  private static readonly rand: cryptoFramework.Random = cryptoFramework.createRandom();
  private static readonly IV_LENGTH: number = 16;
  private static EXISTS_AES_KEY: boolean = false;

  /**
   * 生成RSA加密密钥
   * @returns
   */
  private static getGenerateProperties(): huks.HuksOptions {
    const properties: huks.HuksOptions = {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_128 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT | huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT }
      ]
    };
    return properties;
  }

  /**
   * 生成加密配置信息
   * @param inData 加密数据
   * @returns 加密配置信息
   */
  private static getEncryptProperties(inData: string | Uint8Array, iv: Uint8Array): huks.HuksOptions {
    const properties: huks.HuksOptions = {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_128 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_ENCRYPT },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
        { tag: huks.HuksTag.HUKS_TAG_IV, value: iv }
      ]
    };
    if (inData) {
      properties.inData = typeof inData === 'string' ? ByteUtils.stringToBytes(inData) : inData;
    }
    return properties;
  }

  /**
   * 生成解密配置信息
   * @param inData 解密数据
   * @returns 解密配置信息
   */
  private static getDecryptProperties(inData: string | Uint8Array, iv: Uint8Array): huks.HuksOptions {
    const properties: huks.HuksOptions = {
      properties: [
        { tag: huks.HuksTag.HUKS_TAG_ALGORITHM, value: huks.HuksKeyAlg.HUKS_ALG_AES },
        { tag: huks.HuksTag.HUKS_TAG_KEY_SIZE, value: huks.HuksKeySize.HUKS_AES_KEY_SIZE_128 },
        { tag: huks.HuksTag.HUKS_TAG_PURPOSE, value: huks.HuksKeyPurpose.HUKS_KEY_PURPOSE_DECRYPT },
        { tag: huks.HuksTag.HUKS_TAG_PADDING, value: huks.HuksKeyPadding.HUKS_PADDING_PKCS7 },
        { tag: huks.HuksTag.HUKS_TAG_BLOCK_MODE, value: huks.HuksCipherMode.HUKS_MODE_CBC },
        { tag: huks.HuksTag.HUKS_TAG_IV, value: iv }
      ]
    };
    if (inData) {
      properties.inData = typeof inData === 'string' ? ByteUtils.stringToBytes(inData) : inData;
    }
    return properties;
  }

  /**
   * 生成RSA加密密钥
   * @returns 结果
   */
  private static generateKeyItem(): Promise<boolean> {
    return huks.generateKeyItem(CryptoUtils.KeePassHO_AES_KEY_ALIAS, CryptoUtils.getGenerateProperties()).then(() => {
      return true;
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'generate key item failed,message is' + JSON.stringify(error));
      return false;
    });
  }

  /**
   * 生成RSA加密密钥
   * @returns
   */
  public static async generateKey(): Promise<boolean> {
    if (CryptoUtils.EXISTS_AES_KEY) {
      return Promise.resolve(true);
    }
    return huks.hasKeyItem(CryptoUtils.KeePassHO_AES_KEY_ALIAS, { properties: [] }).then((result: boolean) => {
      if (result) {
        CryptoUtils.EXISTS_AES_KEY = true;
        return Promise.resolve(true);
      } else {
        return CryptoUtils.generateKeyItem();
      }
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'has key item failed,message is' + JSON.stringify(error));
      return CryptoUtils.generateKeyItem();
    });
  }

  /**
   * 加密密码
   * @param alias 密钥别名
   * @param password 字符串
   * @returns 结果Base64编码
   */
  public static async encryptText(plainText: string): Promise<string> {
    if (!plainText) {
      return Promise.resolve('');
    }
    await CryptoUtils.generateKey();
    const iv = ByteUtils.randomData(CryptoUtils.IV_LENGTH);
    let encryptResult: string = '';
    let handle: number = -1;
    let options: huks.HuksOptions = CryptoUtils.getEncryptProperties(plainText, iv);
    await huks.initSession(CryptoUtils.KeePassHO_AES_KEY_ALIAS, options).then((data) => {
      handle = data.handle;
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'init session failed,message is' + JSON.stringify(error));
      CommonUtils.showToast(error.message);
    });

    await huks.finishSession(handle, options).then((data) => {
      if (data === undefined || data.outData === undefined) {
        hilog.error(DOMAIN, TAG, 'encrypt data finish session failed');
      } else {
        encryptResult = CryptoUtils.toBase64(data.outData, iv);
      }
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'encrypt data failed,message is' + JSON.stringify(error));
      CommonUtils.showToast(error.message);
    });
    return encryptResult;
  }

  /**
   * 解密密码
   * @param alias
   * @param encryptedData base64编码的字符串
   * @returns
   */
  public static async decryptText(encryptedData: string): Promise<string> {
    if (!encryptedData) {
      return Promise.resolve('');
    }
    await CryptoUtils.generateKey();
    const combined = new util.Base64Helper().decodeSync(encryptedData);
    let decryptResult: string = '';
    let options: huks.HuksOptions = CryptoUtils.getDecryptProperties(combined.slice(CryptoUtils.IV_LENGTH), combined.slice(0, CryptoUtils.IV_LENGTH));

    let handle: number = -1;
    await huks.initSession(CryptoUtils.KeePassHO_AES_KEY_ALIAS, options).then((data) => {
      handle = data.handle;
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'init session failed,message is' + JSON.stringify(error));
      CommonUtils.showToast(error.message);
    });

    await huks.finishSession(handle, options).then((data) => {
      decryptResult = ByteUtils.bytesToString(data.outData);
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'decrypt data failed,message is' + JSON.stringify(error));
      CommonUtils.showToast(error.message);
    });
    return decryptResult;
  }

  /**
   * 将加密数据转换为Base64编码， [iv, 16] + [data, n]
   * @param data 加密数据
   * @param iv 随机IV
   * @returns Base64编码
   */
  private static toBase64(data: Uint8Array, iv: Uint8Array): string {
    const combined = new Uint8Array(iv.length + data.length);
    combined.set(iv, 0);
    combined.set(data, iv.length);
    return new util.Base64Helper().encodeToStringSync(combined);
  }
}