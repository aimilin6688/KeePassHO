import { Binary } from './models/KdbxTypes';
import { KdbxCrypto } from './KdbxCrypto';
import { InnerRandomStreamID } from './KdbxFormat';
import { KdbxXmlProcessor } from './xml/KdbxXmlProcessor';
import util from '@ohos.util';

/**
 * KDBX4文件读取器
 */
export class KdbxReader {
  private data: Uint8Array;
  private offset: number;
  private littleEndian: boolean;
  private version: number;

  /**
   * 创建KDBX文件读取器
   * @param data KDBX文件数据
   */
  constructor(data: Uint8Array) {
    this.data = data;
    this.offset = 0;
    this.littleEndian = true; // KDBX使用小端序
    this.version = 0;
  }

  /**
   * 读取KDBX文件
   * @param password 密码
   * @param keyFile 密钥文件（可选）
   */
  async read(password: string, keyFile: Binary | null = null): Promise<any> {
    try {
      // 1. 读取文件头
      const header = await this.readHeader();

      // 2. 验证签名和版本
      if (!this.validateSignature()) {
        throw new Error('Invalid KDBX file signature');
      }

      // 3. 读取加密参数
      const masterSeed = header.get('MasterSeed');
      const transformSeed = header.get('TransformSeed');
      const encryptionIV = header.get('EncryptionIV');
      const kdfParameters = header.get('KdfParameters');
      const streamStartBytes = header.get('StreamStartBytes');

      if (!masterSeed || !encryptionIV || !kdfParameters) {
        throw new Error('Missing required header fields');
      }

      // 4. 计算主密钥
      const masterKey = await KdbxCrypto.computeMasterKey(
        password,
        keyFile,
        masterSeed,
        kdfParameters
      );

      // 5. 解密数据块
      const encryptedData = this.readRemaining();
      const decryptedData = await KdbxCrypto.aes256CbcDecrypt(
        encryptedData,
        masterKey,
        encryptionIV
      );

      // 6. 验证解密是否成功
      if (!this.validateDecryption(decryptedData, streamStartBytes)) {
        throw new Error('Decryption failed - invalid credentials');
      }

      // 7. 解析XML内容
      return await this.parseXmlContent(decryptedData, header);
    } catch (error) {
      console.error('Failed to read KDBX file:', error);
      throw error;
    }
  }

  /**
   * 读取文件头
   */
  private async readHeader(): Promise<Map<string, any>> {
    const header = new Map<string, any>();

    // 读取版本信息
    this.version = this.readUint32();
    if (this.version !== 0x00040000) {
      throw new Error(`Unsupported KDBX version: ${this.version.toString(16)}`);
    }

    // 读取头部字段
    while (true) {
      const fieldId = this.readUint8();
      if (fieldId === 0) {
        break; // 头部结束
      }

      const fieldLength = this.readUint32();
      const fieldData = this.readBytes(fieldLength);

      switch (fieldId) {
        case 1: // 结束标记
          break;
        case 2: // 注释
          header.set('Comment', this.decodeUtf8(fieldData));
          break;
        case 3: // 密码加密ID
          header.set('CipherID', fieldData);
          break;
        case 4: // 压缩标志
          header.set('CompressionFlags', this.readUint32());
          break;
        case 5: // 主种子
          header.set('MasterSeed', fieldData);
          break;
        case 6: // 转换种子
          header.set('TransformSeed', fieldData);
          break;
        case 7: // 转换轮数
          header.set('TransformRounds', this.readUint64());
          break;
        case 8: // 加密IV
          header.set('EncryptionIV', fieldData);
          break;
        case 9: // 保护流密钥
          header.set('ProtectedStreamKey', fieldData);
          break;
        case 10: // 流起始字节
          header.set('StreamStartBytes', fieldData);
          break;
        case 11: // 内部随机流ID
          header.set('InnerRandomStreamID', this.readUint32() as InnerRandomStreamID);
          break;
        case 12: // KDF参数
          header.set('KdfParameters', this.parseKdfParameters(fieldData));
          break;
        default:
          console.warn(`Unknown header field: ${fieldId}`);
          break;
      }
    }

    return header;
  }

  /**
   * 验证文件签名
   */
  private validateSignature(): boolean {
    const signature1 = this.readUint32();
    const signature2 = this.readUint32();
    return signature1 === 0x9AA2D903 && signature2 === 0xB54BFB67;
  }

  /**
   * 验证解密是否成功
   */
  private validateDecryption(decryptedData: Uint8Array, streamStartBytes: Uint8Array): boolean {
    if (!streamStartBytes || streamStartBytes.length === 0) {
      return true; // 没有验证数据
    }

    const startBytes = decryptedData.slice(0, streamStartBytes.length);
    for (let i = 0; i < streamStartBytes.length; i++) {
      if (startBytes[i] !== streamStartBytes[i]) {
        return false;
      }
    }
    return true;
  }

  /**
   * 解析KDF参数
   */
  private parseKdfParameters(data: Uint8Array): Map<string, any> {
    const params = new Map<string, any>();
    let offset = 0;

    while (offset < data.length) {
      const fieldType = data[offset++];
      const nameLength = this.readVarInt(data, offset);
      offset += this.getVarIntSize(nameLength);

      const name = this.decodeUtf8(data.slice(offset, offset + nameLength));
      offset += nameLength;

      const valueLength = this.readVarInt(data, offset);
      offset += this.getVarIntSize(valueLength);

      const value = data.slice(offset, offset + valueLength);
      offset += valueLength;

      switch (fieldType) {
        case 0x04: // UInt32
          params.set(name, new DataView(value.buffer).getUint32(0, true));
          break;
        case 0x05: // UInt64
          params.set(name, new DataView(value.buffer).getBigUint64(0, true));
          break;
        case 0x08: // Bool
          params.set(name, value[0] !== 0);
          break;
        case 0x0C: // Binary
          params.set(name, value);
          break;
        default:
          console.warn(`Unknown KDF parameter type: ${fieldType}`);
          break;
      }
    }

    return params;
  }

  /**
   * 读取可变长度整数
   */
  private readVarInt(data: Uint8Array, offset: number): number {
    let value = 0;
    let shift = 0;
    let byte;

    do {
      byte = data[offset++];
      value |= (byte & 0x7F) << shift;
      shift += 7;
    } while (byte & 0x80);

    return value;
  }

  /**
   * 获取可变长度整数的字节数
   */
  private getVarIntSize(value: number): number {
    let size = 0;
    do {
      size++;
      value >>= 7;
    } while (value > 0);
    return size;
  }

  /**
   * 读取8位无符号整数
   */
  private readUint8(): number {
    return this.data[this.offset++];
  }

  /**
   * 读取32位无符号整数
   */
  private readUint32(): number {
    const value = new DataView(this.data.buffer).getUint32(this.offset, this.littleEndian);
    this.offset += 4;
    return value;
  }

  /**
   * 读取64位无符号整数
   */
  private readUint64(): bigint {
    const value = new DataView(this.data.buffer).getBigUint64(this.offset, this.littleEndian);
    this.offset += 8;
    return value;
  }

  /**
   * 读取指定长度的字节
   */
  private readBytes(length: number): Uint8Array {
    const bytes = this.data.slice(this.offset, this.offset + length);
    this.offset += length;
    return bytes;
  }

  /**
   * 读取剩余的所有字节
   */
  private readRemaining(): Uint8Array {
    return this.data.slice(this.offset);
  }

  /**
   * 解码UTF-8字符串
   */
  private decodeUtf8(data: Uint8Array): string {
    return new util.TextDecoder().decode(data);
  }

  /**
   * 解析XML内容
   * @param data 解密后的数据
   * @param header 文件头信息
   * @returns 解析后的数据库对象
   */
  private async parseXmlContent(data: Uint8Array, header: Map<string, any>): Promise<any> {
    try {
      // 1. 跳过StreamStartBytes
      const streamStartBytes = header.get('StreamStartBytes');
      const contentData = data.slice(streamStartBytes.length);

      // 2. 获取必要的参数
      const compressed = (header.get('CompressionFlags') & 1) !== 0;
      const protectedStreamKey = header.get('ProtectedStreamKey');
      const innerRandomStreamID = header.get('InnerRandomStreamID') as InnerRandomStreamID;

      if (!protectedStreamKey || innerRandomStreamID === undefined) {
        throw new Error('Missing required header fields for XML processing');
      }

      // 3. 使用XML处理器解析内容
      return await KdbxXmlProcessor.parseXml(
        contentData,
        compressed,
        protectedStreamKey,
        innerRandomStreamID
      );
    } catch (error) {
      console.error('Failed to parse XML content:', error);
      throw error;
    }
  }
}
