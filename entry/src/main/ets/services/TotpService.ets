/**
 * TOTP服务 - 基于时间的一次性密码生成与解析
 * 支持RFC6238标准、Steam令牌和自定义令牌
 */
import cryptoFramework from '@ohos.security.cryptoFramework';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { url } from '@kit.ArkTS';

const DOMAIN = 0x0000;
const TAG = 'TotpService';

/**
 * TOTP令牌类型
 */
export enum TotpType {
  /**
   * RFC6238标准令牌
   */
  RFC6238 = 'RFC6238',

  /**
   * Steam令牌
   */
  STEAM = 'STEAM',

  /**
   * 自定义令牌
   */
  CUSTOM = 'CUSTOM'
}

/**
 * TOTP算法类型
 */
export enum TotpAlgorithm {
  /**
   * SHA1算法
   */
  SHA1 = 'SHA1',

  /**
   * SHA256算法
   */
  SHA256 = 'SHA256',

  /**
   * SHA512算法
   */
  SHA512 = 'SHA512'
}

/**
 * TOTP配置参数
 */
export interface TotpConfig {
  /**
   * 令牌类型
   */
  type: TotpType;

  /**
   * 密钥（Base32编码）
   */
  secret: string;

  /**
   * 算法（默认SHA1）
   */
  algorithm?: TotpAlgorithm;

  /**
   * 令牌位数（默认6位）
   */
  digits?: number;

  /**
   * 时间步长（默认30秒）
   */
  period?: number;

  /**
   * 令牌名称（可选）
   */
  name?: string;

  /**
   * 发行者（可选）
   */
  issuer?: string;
}

/**
 * TOTP服务类
 */
export class TotpService {
  private static instance: TotpService;

  /**
   * 获取TotpService单例
   */
  public static getInstance(): TotpService {
    if (!TotpService.instance) {
      TotpService.instance = new TotpService();
    }
    return TotpService.instance;
  }

  /**
   * 生成TOTP令牌
   * @param config TOTP配置
   * @param timestamp 可选时间戳（毫秒），默认为当前时间
   * @returns 生成的令牌
   */
  public async generateToken(config: TotpConfig, timestamp?: number): Promise<string> {
    // 使用当前时间戳（如果未提供）
    const currentTime = timestamp || Date.now();

    // 根据令牌类型选择不同的生成方法
    switch (config.type) {
      case TotpType.STEAM:
        return this.generateSteamToken(config, currentTime);
      case TotpType.RFC6238:
      case TotpType.CUSTOM:
      default:
        return this.generateRfc6238Token(config, currentTime);
    }
  }

  /**
   * 生成RFC6238标准令牌
   * @param config TOTP配置
   * @param timestamp 时间戳（毫秒）
   * @returns 生成的令牌
   */
  private async generateRfc6238Token(config: TotpConfig, timestamp: number): Promise<string> {
    // 设置默认值
    const algorithm = config.algorithm || TotpAlgorithm.SHA1;
    const digits = config.digits || 6;
    const period = config.period || 30;

    // 解码Base32密钥
    const secretBytes = this.base32Decode(config.secret);

    // 计算时间计数器（时间戳除以步长）
    const counter = Math.floor(timestamp / 1000 / period);

    // 生成HMAC
    const hmac = await this.generateHmac(secretBytes, counter, algorithm);

    // 截断HMAC并生成OTP
    return this.truncateHmac(hmac, digits);
  }

  /**
   * 生成Steam令牌（Steam使用特殊的TOTP变种）
   * @param config TOTP配置
   * @param timestamp 时间戳（毫秒）
   * @returns 生成的令牌
   */
  private async generateSteamToken(config: TotpConfig, timestamp: number): Promise<string> {
    // Steam令牌固定使用SHA1算法，5位数字
    const algorithm = TotpAlgorithm.SHA1;
    const period = config.period || 30;

    // 解码Base32密钥
    const secretBytes = this.base32Decode(config.secret);

    // 计算时间计数器
    const counter = Math.floor(timestamp / 1000 / period);

    // 生成HMAC
    const hmac = await this.generateHmac(secretBytes, counter, algorithm);

    // Steam使用特殊的截断方法
    return this.truncateSteamHmac(hmac);
  }

  /**
   * 生成HMAC
   * @param key 密钥字节数组
   * @param counter 计数器值
   * @param algorithm 算法类型
   * @returns HMAC字节数组
   */
  private async generateHmac(key: Uint8Array, counter: number, algorithm: TotpAlgorithm): Promise<Uint8Array> {
    // 将计数器转换为8字节的大端字节数组
    const counterBytes = new Uint8Array(8);
    for (let i = 7; i >= 0; i--) {
      counterBytes[i] = counter & 0xff;
      counter = counter >> 8;
    }

    // 选择HMAC算法
    let hmacAlgorithm: string;
    switch (algorithm) {
      case TotpAlgorithm.SHA256:
        hmacAlgorithm = 'SHA256';
        break;
      case TotpAlgorithm.SHA512:
        hmacAlgorithm = 'SHA512';
        break;
      case TotpAlgorithm.SHA1:
      default:
        hmacAlgorithm = 'SHA1';
        break;
    }

    try {
      // 使用鸿蒙的加密框架计算HMAC
      let symKeyBlob: cryptoFramework.DataBlob = { data: key };
      let aesGenerator = cryptoFramework.createSymKeyGenerator('HMAC');
      let symKey = await aesGenerator.convertKey(symKeyBlob);

      const macObj = cryptoFramework.createMac(hmacAlgorithm);
      await macObj.init(symKey);
      await macObj.update({ data: counterBytes });
      const hmacResult = await macObj.doFinal();
      // 转换为Uint8Array
      return hmacResult.data;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'HMAC计算错误: ${error.message}');
      throw new Error(error.message);
    }
  }

  /**
   * 截断HMAC并生成OTP（RFC6238标准方法）
   * @param hmac HMAC字节数组
   * @param digits 令牌位数
   * @returns 生成的令牌
   */
  private truncateHmac(hmac: Uint8Array, digits: number): string {
    // 获取偏移量（最后一个字节的低4位）
    const offset = hmac[hmac.length - 1] & 0x0f;

    // 从偏移量开始提取4个字节并转换为整数
    const binary = ((hmac[offset] & 0x7f) << 24) |
      ((hmac[offset + 1] & 0xff) << 16) |
      ((hmac[offset + 2] & 0xff) << 8) |
      (hmac[offset + 3] & 0xff);

    // 计算模数（10^digits）
    const modulus = Math.pow(10, digits);

    // 生成OTP
    const otp = binary % modulus;

    // 格式化为固定位数的字符串
    return otp.toString().padStart(digits, '0');
  }

  /**
   * 截断HMAC并生成Steam令牌
   * @param hmac HMAC字节数组
   * @returns 生成的Steam令牌
   */
  private truncateSteamHmac(hmac: Uint8Array): string {
    // 获取偏移量（最后一个字节的低4位）
    const offset = hmac[19] & 0x0f;

    // 从偏移量开始提取4个字节并转换为整数
    let fullCode = ((hmac[offset] & 0x7f) << 24) |
      ((hmac[offset + 1] & 0xff) << 16) |
      ((hmac[offset + 2] & 0xff) << 8) |
      (hmac[offset + 3] & 0xff);

    // Steam使用的字符集
    const steamChars = '23456789BCDFGHJKMNPQRTVWXY';

    // 生成5位Steam令牌
    let code = '';
    for (let i = 0; i < 5; i++) {
      code += steamChars.charAt(fullCode % steamChars.length);
      fullCode = Math.floor(fullCode / steamChars.length);
    }

    return code;
  }

  /**
   * 解码Base32字符串为字节数组
   * @param base32 Base32编码的字符串
   * @returns 解码后的字节数组
   */
  private base32Decode(base32: string): Uint8Array {
    // 标准Base32字符集
    const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

    // 移除所有空格和连字符
    let cleanedInput = base32.replace(/[\s-]/g, '').toUpperCase();

    // 如果字符串末尾有填充字符（=），移除它们
    cleanedInput = cleanedInput.replace(/=+$/, '');

    // 计算输出长度
    const outputLength = Math.floor((cleanedInput.length * 5) / 8);
    const result = new Uint8Array(outputLength);

    // 解码
    let buffer = 0;
    let bitsLeft = 0;
    let outputIndex = 0;

    for (let i = 0; i < cleanedInput.length; i++) {
      const char = cleanedInput.charAt(i);
      const value = ALPHABET.indexOf(char);

      if (value === -1) {
        throw new Error(`非法Base32字符: ${char}`);
      }

      // 将5位添加到缓冲区
      buffer = (buffer << 5) | value;
      bitsLeft += 5;

      // 如果我们至少有8位，提取一个字节
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        result[outputIndex++] = (buffer >> bitsLeft) & 0xff;
      }
    }

    return result;
  }

  /**
   * 编码字节数组为Base32字符串
   * @param bytes 字节数组
   * @returns Base32编码的字符串
   */
  public base32Encode(bytes: Uint8Array): string {
    // 标准Base32字符集
    const ALPHABET = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

    let result = '';
    let buffer = 0;
    let bitsLeft = 0;

    for (let i = 0; i < bytes.length; i++) {
      // 将8位添加到缓冲区
      buffer = (buffer << 8) | bytes[i];
      bitsLeft += 8;

      // 提取5位直到缓冲区少于5位
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        result += ALPHABET.charAt((buffer >> bitsLeft) & 0x1f);
      }
    }

    // 如果还有剩余位，添加最后一个字符
    if (bitsLeft > 0) {
      result += ALPHABET.charAt((buffer << (5 - bitsLeft)) & 0x1f);
    }

    return result;
  }

  /**
   * 生成随机TOTP密钥
   * @param length 密钥长度（字节），默认为16
   * @returns Base32编码的密钥
   */
  public async generateRandomSecret(length: number = 16): Promise<string> {
    try {
      // 使用鸿蒙的加密框架生成随机字节
      const randomBytes = await cryptoFramework.createRandom().generateRandom(length);
      const secretBytes = new Uint8Array(randomBytes.data);

      // 编码为Base32
      return this.base32Encode(secretBytes);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Generate random secret error: ${error.message}`)
      throw new Error(error.message);
    }
  }

  /**
   * 从URI解析TOTP配置
   * @param uri TOTP URI (otpauth://totp/...)
   * @returns TOTP配置对象
   */
  public parseUri(uri: string): TotpConfig | null {
    try {
      // 检查URI格式
      if (!uri.startsWith('otpauth://totp/')) {
        hilog.error(DOMAIN, TAG, 'Invalid URI format');
        return null;
      }

      // 解析URI
      const urlObject = url.URL.parseURL(uri);

      // 解析路径部分获取标签（格式可能是 Issuer:AccountName 或仅 AccountName）
      const label = decodeURIComponent(urlObject.pathname.substring(1));
      let issuer = '';
      let name = label;
      let type = TotpType.RFC6238;

      // 检查标签中是否包含发行者
      const labelParts = label.split(':');
      if (labelParts.length > 1) {
        issuer = labelParts[0].trim();
        name = labelParts.slice(1).join(':').trim();
      }

      // 从查询参数获取密钥和其他参数
      const params = urlObject.params;
      const secret = params.get('secret');

      if (!secret) {
        hilog.error(DOMAIN, TAG, 'Missing secret parameter');
        return null;
      }

      // 获取其他可选参数
      const algorithm = this.parseAlgorithm(params.get('algorithm'));
      const digits = parseInt(params.get('digits') || '6', 10);
      const period = parseInt(params.get('period') || '30', 10);

      // 如果查询参数中有发行者，优先使用它
      if (params.get('issuer')) {
        issuer = params.get('issuer') || '';
      }
      const encoder = params.get('encoder');
      if (encoder && encoder.toUpperCase() === 'STEAM') {
        type = TotpType.STEAM;
      }

      // 创建配置对象
      return {
        type: type,
        secret: secret.toUpperCase(),
        algorithm,
        digits,
        period,
        name,
        issuer
      };
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Parse URI error: ${error.message}`)
      return null;
    }
  }

  /**
   * 解析算法字符串
   * @param algorithm 算法字符串
   * @returns TOTP算法枚举值
   */
  private parseAlgorithm(algorithm: string | null): TotpAlgorithm {
    if (!algorithm) {
      return TotpAlgorithm.SHA1;
    }

    switch (algorithm.toUpperCase()) {
      case 'SHA256':
        return TotpAlgorithm.SHA256;
      case 'SHA512':
        return TotpAlgorithm.SHA512;
      case 'SHA1':
      default:
        return TotpAlgorithm.SHA1;
    }
  }

  /**
   * 生成TOTP URI
   * @param config TOTP配置
   * @returns TOTP URI字符串
   */
  public generateUri(config: TotpConfig): string {
    // 构建标签（Issuer:Name 格式）
    let label = config.name || '';
    if (config.issuer) {
      label = `${config.issuer}:${label}`;
    }

    // 创建基本URI
    const uri = `otpauth://totp/${encodeURIComponent(label)}?secret=${config.secret}`;

    // 添加可选参数
    const params = new url.URLParams();

    if (config.issuer) {
      params.append('issuer', config.issuer);
    }

    if (config.algorithm && config.algorithm !== TotpAlgorithm.SHA1) {
      params.append('algorithm', config.algorithm);
    }

    if (config.digits && config.digits !== 6) {
      params.append('digits', config.digits.toString());
    }

    if (config.period && config.period !== 30) {
      params.append('period', config.period.toString());
    }

    if (config.type && config.type === TotpType.STEAM) {
      params.append('encoder', TotpType.STEAM.toLowerCase());
    }

    // 构建完整URI
    const queryString = params.toString();
    return queryString ? `${uri}&${queryString}` : uri;
  }

  /**
   * 获取令牌剩余有效时间（秒）
   * @param config TOTP配置
   * @param timestamp 可选时间戳（毫秒），默认为当前时间
   * @returns 剩余有效时间（秒）
   */
  public getRemainingSeconds(config: TotpConfig, timestamp?: number): number {
    const currentTime = timestamp || Date.now();
    const period = config.period || 30;

    // 计算当前周期的结束时间
    const currentPeriod = Math.floor(currentTime / 1000 / period);
    const nextPeriodStart = (currentPeriod + 1) * period;
    const currentTimeSeconds = Math.floor(currentTime / 1000);

    // 计算剩余秒数
    return nextPeriodStart - currentTimeSeconds;
  }

  /**
   * 解析Steam令牌密钥
   * @param steamSecret Steam令牌密钥（可能是特殊格式）
   * @returns 标准化的Base32密钥
   */
  public parseSteamSecret(steamSecret: string): string {
    // 移除所有空格和连字符
    let cleanedSecret = steamSecret.replace(/[\s-]/g, '').toUpperCase();

    // 检查是否是Steam特殊格式（以"STE"开头）
    if (cleanedSecret.startsWith('STE')) {
      // 移除前缀并进行必要的转换
      cleanedSecret = cleanedSecret.substring(3);
    }

    return cleanedSecret;
  }
}