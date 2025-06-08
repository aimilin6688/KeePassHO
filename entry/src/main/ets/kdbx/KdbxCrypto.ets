import cryptoFramework from '@ohos.security.cryptoFramework';
import { Binary, KdfParameters} from './models/KdbxTypes';
import { InnerRandomStreamID } from './KdbxFormat';
import util from '@ohos.util';
import { ChaCha20 } from './crypto/ChaCha20';
import { Salsa20 } from './crypto/Salsa20';
import { KdbxUtils } from './utils/KdbxUtils';

/**
 * 保护字段加密器接口
 */
export interface ProtectedStreamEncryptor {
  /**
   * 加密数据
   * @param data 要加密的数据
   * @returns 加密后的数据
   */
  encrypt(data: Uint8Array): Uint8Array;

  /**
   * 解密数据
   * @param data 要解密的数据
   * @returns 解密后的数据
   */
  decrypt(data: Uint8Array): Uint8Array;
}

/**
 * Argon2变体类型
 */
type Argon2Variant = 'Argon2d' | 'Argon2id';

/**
 * KDBX4加密相关功能实现
 */
@Observed
export class KdbxCrypto {
  /**
   * 计算主密钥
   * @param password 密码
   * @param keyFile 密钥文件（可选）
   * @param masterSeed 主种子
   * @param kdfParameters KDF参数
   * @returns 主密钥
   * @throws Error 当计算失败时抛出错误
   */
  public static async computeMasterKey(
    password: string,
    keyFile: Binary | null,
    masterSeed: Binary,
    kdfParameters: KdfParameters
  ): Promise<Binary> {
    try {
      // 1. 计算密码哈希
      const passwordData = new util.TextEncoder().encode(password);
      const passwordHash = await KdbxCrypto.sha256(passwordData);

      // 2. 计算密钥文件哈希（如果有）
      let compositeKey: Binary;
      if (keyFile) {
        const keyFileHash = await this.sha256(keyFile);
        // 组合密码哈希和密钥文件哈希
        const combined = new Uint8Array(64);
        combined.set(passwordHash, 0);
        combined.set(keyFileHash, 32);
        compositeKey = await KdbxCrypto.sha256(combined);
      } else {
        compositeKey = passwordHash;
      }

      // 3. 使用KDF参数进行密钥转换
      const transformedKey = await this.transformKey(compositeKey, kdfParameters);

      // 4. 组合主种子和转换后的密钥
      const finalKey = new Uint8Array(masterSeed.length + transformedKey.length);
      finalKey.set(masterSeed, 0);
      finalKey.set(transformedKey, masterSeed.length);

      // 5. 计算最终的主密钥
      return await KdbxCrypto.sha256(finalKey);
    } catch (error) {
      console.error('Failed to compute master key:', error);
      throw new Error(`Failed to compute master key: ${error.message}`);
    }
  }

  /**
   * 使用SHA-256计算哈希
   * @param data 输入数据
   * @returns 哈希值
   * @throws Error 当计算失败时抛出错误
   */
  private static async sha256(data: Uint8Array): Promise<Uint8Array> {
    try {
      const md = await cryptoFramework.createMd("SHA-256");
      await md.update(data);
      return new Uint8Array(await md.digest());
    } catch (error) {
      console.error('SHA-256 calculation failed:', error);
      throw new Error(`SHA-256 calculation failed: ${error.message}`);
    }
  }

  /**
   * 使用AES-256-CBC进行加密
   * @param data 待加密数据
   * @param key 密钥
   * @param iv 初始化向量
   * @returns 加密后的数据
   * @throws Error 当加密失败时抛出错误
   */
  public static async aes256CbcEncrypt(data: Uint8Array, key: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    try {
      const cipher = await cryptoFramework.createCipher('AES-256-CBC');
      const params = {
        iv: iv,
        padding: 'PKCS7'
      };
      await cipher.init(key, params);
      return new Uint8Array(await cipher.update(data));
    } catch (error) {
      console.error('AES-256-CBC encryption failed:', error);
      throw new Error(`AES-256-CBC encryption failed: ${error.message}`);
    }
  }

  /**
   * 使用AES-256-CBC进行解密
   * @param data 待解密数据
   * @param key 密钥
   * @param iv 初始化向量
   * @returns 解密后的数据
   * @throws Error 当解密失败时抛出错误
   */
  public static async aes256CbcDecrypt(data: Uint8Array, key: Uint8Array, iv: Uint8Array): Promise<Uint8Array> {
    try {
      const decipher = await cryptoFramework.createDecipher('AES-256-CBC');
      const params = {
        iv: iv,
        padding: 'PKCS7'
      };
      await decipher.init(key, params);
      return new Uint8Array(await decipher.update(data));
    } catch (error) {
      console.error('AES-256-CBC decryption failed:', error);
      throw new Error(`AES-256-CBC decryption failed: ${error.message}`);
    }
  }

  /**
   * 使用HMAC-SHA-256计算消息认证码
   * @param data 输入数据
   * @param key 密钥
   * @returns HMAC值
   * @throws Error 当计算失败时抛出错误
   */
  public static async hmacSha256(data: Uint8Array, key: Uint8Array): Promise<Uint8Array> {
    try {
      const mac = await cryptoFramework.createMac('HMAC256');
      await mac.init(key);
      await mac.update(data);
      return new Uint8Array(await mac.doFinal());
    } catch (error) {
      console.error('HMAC-SHA-256 calculation failed:', error);
      throw new Error(`HMAC-SHA-256 calculation failed: ${error.message}`);
    }
  }

  /**
   * 使用PBKDF2派生密钥
   * @param password 密码
   * @param salt 盐值
   * @param iterations 迭代次数
   * @param keyLength 密钥长度（字节）
   * @returns 派生的密钥
   * @throws Error 当派生失败时抛出错误
   */
  public static async pbkdf2(password: Uint8Array, salt: Uint8Array, iterations: number, keyLength: number): Promise<Uint8Array> {
    try {
      const params = {
        iterations: iterations,
        salt: salt,
        keySize: keyLength
      };
      const derivedKey = await cryptoFramework.pbkdf2('PBKDF2-HMAC-SHA-256', password, params);
      return new Uint8Array(derivedKey);
    } catch (error) {
      console.error('PBKDF2 key derivation failed:', error);
      throw new Error(`PBKDF2 key derivation failed: ${error.message}`);
    }
  }

  /**
   * 使用KDF进行密钥转换
   * @param key 输入密钥
   * @param kdfParameters KDF参数
   * @returns 转换后的密钥
   * @throws Error 当转换失败时抛出错误
   */
  private static async transformKey(key: Uint8Array, kdfParameters: KdfParameters): Promise<Uint8Array> {
    const kdfUuid = kdfParameters.uuid;

    // 检查KDF类型
    if (KdbxUtils.bytesToHex(kdfUuid) === 'ef636ddf8c29444b91f7a9a403e30a0c') {
      // Argon2d
      console.info('Using Argon2d KDF');
      return await this.transformKeyArgon2(key, kdfParameters, 'Argon2d');
    } else if (KdbxUtils.bytesToHex(kdfUuid) === '9e298b1956db4773b23dfc3ec6f0a1e6') {
      // Argon2id
      console.info('Using Argon2id KDF');
      return await this.transformKeyArgon2(key, kdfParameters, 'Argon2id');
    } else if (KdbxUtils.bytesToHex(kdfUuid) === '7c02bb8279a74ac0927d114a00648238') {
      // AES-KDF
      console.info('Using AES-KDF');
      return await this.transformKeyAes(key, kdfParameters);
    } else {
      // 默认使用PBKDF2
      console.info('Using PBKDF2 as fallback KDF');
      const iterations = kdfParameters.rounds || 60000;
      const salt = kdfParameters.salt || KdbxUtils.generateRandom(new Uint8Array(32));
      return await this.pbkdf2(key, salt, iterations, 32);
    }
  }

  /**
   * 使用Argon2进行密钥转换
   * @param key 输入密钥
   * @param kdfParameters KDF参数
   * @param variant Argon2变体（Argon2d或Argon2id）
   * @returns 转换后的密钥
   * @throws Error 当转换失败时抛出错误
   */
  private static async transformKeyArgon2(
    key: Uint8Array,
    kdfParameters: KdfParameters,
    variant: Argon2Variant
  ): Promise<Uint8Array> {
    // 由于OpenHarmony目前不直接支持Argon2，我们使用PBKDF2作为替代
    // 在实际应用中，应该实现或引入Argon2库
    console.warn(`${variant} not directly supported, using PBKDF2 as fallback`);

    // 从KDF参数中提取值
    const salt = kdfParameters.salt || KdbxUtils.generateRandom(new Uint8Array(32));
    const rounds = kdfParameters.rounds || 10;
    const memory = kdfParameters.memory || 1024 * 1024; // 默认1MB
    const parallelism = kdfParameters.parallelism || 2;

    // 使用PBKDF2作为替代，增加迭代次数以提高安全性
    // 注意：这不是Argon2的安全等效，仅用于开发
    const enhancedIterations = rounds * 1000; // 增加迭代次数作为补偿
    return await this.pbkdf2(key, salt, enhancedIterations, 32);
  }

  /**
   * 使用AES-KDF进行密钥转换
   * @param key 输入密钥
   * @param kdfParameters KDF参数
   * @returns 转换后的密钥
   * @throws Error 当转换失败时抛出错误
   */
  private static async transformKeyAes(key: Uint8Array, kdfParameters: KdfParameters): Promise<Uint8Array> {
    const rounds = kdfParameters.rounds || 60000;
    const secretKey = kdfParameters.secretKey;

    if (!secretKey) {
      throw new Error('AES-KDF requires a secretKey parameter');
    }

    let result = key;

    // 使用AES-ECB模式进行多轮转换
    for (let i = 0; i < rounds; i++) {
      // 由于OpenHarmony可能不直接支持AES-ECB，我们使用CBC模式并将IV设置为全零
      const zeroIv = new Uint8Array(16);
      result = await this.aes256CbcEncrypt(result, secretKey, zeroIv);
    }

    // 最后进行SHA-256哈希
    return await this.sha256(result);
  }

  /**
   * 创建受保护字段加密器
   * @param key 密钥
   * @param streamId 流ID
   * @returns 加密器对象
   * @throws Error 当不支持的流密码类型时抛出错误
   */
  public static createProtectedStreamEncryptor(key: Binary, streamId: InnerRandomStreamID): ProtectedStreamEncryptor {
    switch (streamId) {
      case InnerRandomStreamID.CHACHA20:
        return new ChaCha20Encryptor(key);
      case InnerRandomStreamID.SALSA20:
        return new Salsa20Encryptor(key);
      default:
        throw new Error(`Unsupported stream cipher: ${streamId}`);
    }
  }
}

/**
 * ChaCha20加密器实现
 */
@Observed
class ChaCha20Encryptor implements ProtectedStreamEncryptor {
  private cipher: ChaCha20;

  constructor(key: Binary) {
    // 生成随机的12字节nonce
    const nonce = KdbxUtils.generateRandom(new Uint8Array(12));
    this.cipher = new ChaCha20(key, nonce);
  }

  public encrypt(data: Uint8Array): Uint8Array {
    return this.cipher.process(data);
  }

  public decrypt(data: Uint8Array): Uint8Array {
    // ChaCha20是对称的，加密和解密使用相同的操作
    return this.cipher.process(data);
  }
}

/**
 * Salsa20加密器实现
 */
@Observed
class Salsa20Encryptor implements ProtectedStreamEncryptor {
  private cipher: Salsa20;

  constructor(key: Binary) {
    // 生成随机的8字节nonce
    const nonce = KdbxUtils.generateRandom(new Uint8Array(8));
    this.cipher = new Salsa20(key, nonce);
  }

  public encrypt(data: Uint8Array): Uint8Array {
    return this.cipher.process(data);
  }

  public decrypt(data: Uint8Array): Uint8Array {
    // Salsa20是对称的，加密和解密使用相同的操作
    return this.cipher.process(data);
  }
}