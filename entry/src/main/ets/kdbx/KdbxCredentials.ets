import { Binary } from './models/KdbxTypes';

/**
 * 凭证类型
 */
export enum CredentialType {
  /**
   * 密码
   */
  PASSWORD = 'password',

  /**
   * 密钥文件
   */
  KEY_FILE = 'keyfile',

  /**
   * Windows用户账户
   */
  WINDOWS_USER = 'windows_user'
}

/**
 * 密钥文件格式
 */
export enum KeyFileFormat {
  /**
   * XML格式
   */
  XML = 'xml',

  /**
   * 二进制格式
   */
  BINARY = 'binary',

  /**
   * 十六进制格式
   */
  HEX = 'hex'
}

/**
 * 数据库凭证
 */
export class KdbxCredentials {
  /**
   * 密码
   */
  private password?: string;

  /**
   * 密钥文件数据
   */
  private keyFileData?: Binary;

  /**
   * Windows用户账户数据
   */
  private windowsUserData?: Binary;

  /**
   * 设置密码
   * @param password 密码
   */
  setPassword(password: string): void {
    this.password = password;
  }

  /**
   * 设置密钥文件数据
   * @param data 密钥文件数据
   */
  setKeyFileData(data: Binary): void {
    this.keyFileData = data;
  }

  /**
   * 设置Windows用户账户数据
   * @param data Windows用户账户数据
   */
  setWindowsUserData(data: Binary): void {
    this.windowsUserData = data;
  }

  /**
   * 获取密码哈希
   * @returns 密码哈希
   */
  private async getPasswordHash(): Promise<Binary> {
    if (!this.password) {
      return new Uint8Array(32);
    }

    // 使用UTF-8编码密码
    const encoder = new TextEncoder();
    const passwordData = encoder.encode(this.password);

    // 计算SHA-256哈希
    const hashBuffer = await crypto.subtle.digest('SHA-256', passwordData);
    return new Uint8Array(hashBuffer);
  }

  /**
   * 解析密钥文件
   * @param data 密钥文件数据
   * @returns 密钥数据
   */
  private async parseKeyFile(data: Binary): Promise<Binary> {
    // 尝试解析XML格式
    const xmlString = new TextDecoder().decode(data);
    if (xmlString.includes('<?xml')) {
      try {
        const parser = new DOMParser();
        const xmlDoc = parser.parseFromString(xmlString, 'text/xml');
        const keyData = xmlDoc.querySelector('KeyFile > Key > Data')?.textContent;

        if (keyData) {
          // Base64解码
          const binaryString = atob(keyData);
          const bytes = new Uint8Array(binaryString.length);
          for (let i = 0; i < binaryString.length; i++) {
            bytes[i] = binaryString.charCodeAt(i);
          }
          return bytes;
        }
      } catch (e) {
        // XML解析失败，尝试其他格式
      }
    }

    // 检查是否为十六进制格式
    const hexString = new TextDecoder().decode(data).trim();
    if (/^[0-9A-Fa-f]{64}$/.test(hexString)) {
      const bytes = new Uint8Array(32);
      for (let i = 0; i < 32; i++) {
        bytes[i] = parseInt(hexString.substr(i * 2, 2), 16);
      }
      return bytes;
    }

    // 如果不是XML或十六进制格式，则视为二进制格式
    // 如果数据长度为32字节，直接使用
    if (data.length === 32) {
      return data;
    }

    // 否则计算哈希
    const hashBuffer = await crypto.subtle.digest('SHA-256', data);
    return new Uint8Array(hashBuffer);
  }

  /**
   * 获取Windows用户账户哈希
   * @returns Windows用户账户哈希
   */
  private async getWindowsUserHash(): Promise<Binary> {
    if (!this.windowsUserData) {
      return new Uint8Array(32);
    }

    const hashBuffer = await crypto.subtle.digest('SHA-256', this.windowsUserData);
    return new Uint8Array(hashBuffer);
  }

  /**
   * 获取组合密钥
   * @returns 组合密钥
   */
  async getCompositeKey(): Promise<Binary> {
    // 获取各个凭证的哈希
    const [passwordHash, keyFileHash, windowsUserHash] = await Promise.all([
      this.getPasswordHash(),
      this.keyFileData ? this.parseKeyFile(this.keyFileData) : new Uint8Array(32),
      this.getWindowsUserHash()
    ]);

    // 组合所有哈希
    const compositeData = new Uint8Array(96); // 32 * 3
    compositeData.set(passwordHash, 0);
    compositeData.set(keyFileHash, 32);
    compositeData.set(windowsUserHash, 64);

    // 计算最终哈希
    const hashBuffer = await crypto.subtle.digest('SHA-256', compositeData);
    return new Uint8Array(hashBuffer);
  }

  /**
   * 验证凭证
   * @returns 是否有效
   */
  isValid(): boolean {
    return !!(this.password || this.keyFileData || this.windowsUserData);
  }

  /**
   * 清除凭证
   */
  clear(): void {
    this.password = undefined;
    this.keyFileData = undefined;
    this.windowsUserData = undefined;
  }

  /**
   * 生成密钥文件
   * @param format 密钥文件格式
   * @returns 密钥文件数据
   */
  static async generateKeyFile(format: KeyFileFormat = KeyFileFormat.XML): Promise<Binary> {
    // 生成32字节随机数据
    const keyData = crypto.getRandomValues(new Uint8Array(32));

    switch (format) {
      case KeyFileFormat.XML:
        // 生成XML格式密钥文件
        const base64Data = btoa(String.fromCharCode(...keyData));
        const xmlContent = `<?xml version="1.0" encoding="utf-8"?>
<KeyFile>
  <Meta>
    <Version>2.0</Version>
  </Meta>
  <Key>
    <Data>${base64Data}</Data>
  </Key>
</KeyFile>`;
        return new TextEncoder().encode(xmlContent);

      case KeyFileFormat.HEX:
        // 生成十六进制格式密钥文件
        let hexString = '';
        for (const byte of keyData) {
          hexString += byte.toString(16).padStart(2, '0');
        }
        return new TextEncoder().encode(hexString);

      case KeyFileFormat.BINARY:
      default:
        // 直接返回二进制数据
        return keyData;
    }
  }
}
