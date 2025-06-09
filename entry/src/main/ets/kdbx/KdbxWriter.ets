import { Binary } from './models/KdbxTypes';
import { KdbxCrypto } from './KdbxCrypto';
import { InnerRandomStreamID } from './KdbxFormat';
import { KdbxXmlProcessor } from './xml/KdbxXmlProcessor';
import { KdbxUtils } from './utils/KdbxUtils';
import util from '@ohos.util';

/**
 * KDBX4文件写入器
 */
export class KdbxWriter {
  private buffer: Uint8Array[];
  private littleEndian: boolean;

  /**
   * 创建KDBX文件写入器
   */
  constructor() {
    this.buffer = [];
    this.littleEndian = true; // KDBX使用小端序
  }

  /**
   * 写入KDBX文件
   * @param database 数据库对象
   * @param password 密码
   * @param keyFile 密钥文件（可选）
   * @returns 写入的文件数据
   * @throws 如果写入过程中发生错误
   */
  async write(database: any, password: string, keyFile: Binary | null = null): Promise<Uint8Array> {
    try {
      // 验证输入参数
      if (!database) {
        throw new Error('数据库对象不能为空');
      }
      
      if (!password && !keyFile) {
        throw new Error('必须提供密码或密钥文件');
      }

      // 1. 生成加密参数
      const masterSeed = KdbxUtils.generateRandom(new Uint8Array(32));
      const encryptionIV = KdbxUtils.generateRandom(new Uint8Array(16));
      const streamStartBytes = KdbxUtils.generateRandom(new Uint8Array(32));
      const protectedStreamKey = KdbxUtils.generateRandom(new Uint8Array(32));
      const innerRandomStreamID = InnerRandomStreamID.CHACHA20;

      // 2. 创建KDF参数
      const kdfParameters = this.createKdfParameters();

      // 3. 写入文件头
      this.writeHeader(
        masterSeed,
        encryptionIV,
        streamStartBytes,
        protectedStreamKey,
        innerRandomStreamID,
        kdfParameters
      );

      // 4. 计算主密钥
      const masterKey = await KdbxCrypto.computeMasterKey(
        password,
        keyFile,
        masterSeed,
        kdfParameters
      );

      if (!masterKey || masterKey.length !== 32) {
        throw new Error('主密钥计算失败或长度不正确');
      }

      // 5. 准备XML内容
      const xmlContent = await this.prepareXmlContent(database, protectedStreamKey, innerRandomStreamID);

      if (!xmlContent || xmlContent.length === 0) {
        throw new Error('XML内容生成失败');
      }

      // 6. 加密内容
      const encryptedContent = await KdbxCrypto.aes256CbcEncrypt(
        this.concatUint8Arrays([streamStartBytes, xmlContent]),
        masterKey,
        encryptionIV
      );

      if (!encryptedContent || encryptedContent.length === 0) {
        throw new Error('内容加密失败');
      }

      // 7. 将加密内容添加到缓冲区
      this.buffer.push(encryptedContent);

      // 8. 合并所有缓冲区并返回
      return this.concatUint8Arrays(this.buffer);
    } catch (error) {
      console.error('KDBX文件写入失败:', error instanceof Error ? error.message : String(error));
      throw new Error(`KDBX文件写入失败: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  /**
   * 写入文件头
   */
  private writeHeader(
    masterSeed: Binary,
    encryptionIV: Binary,
    streamStartBytes: Binary,
    protectedStreamKey: Binary,
    innerRandomStreamID: InnerRandomStreamID,
    kdfParameters: Map<string, any>
  ): void {
    // 1. 写入签名和版本
    this.writeUint32(0x9AA2D903); // 签名1
    this.writeUint32(0xB54BFB67); // 签名2
    this.writeUint32(0x00040000); // KDBX 4.0版本

    // 2. 写入头部字段
    // 密码加密ID (AES-256)
    this.writeHeaderField(3, new Uint8Array([
      0x31, 0xC1, 0xF2, 0xE6, 0xBF, 0x71, 0x43, 0x50,
      0xBE, 0x58, 0x05, 0x21, 0x6A, 0xFC, 0x5A, 0xFF
    ]));

    // 压缩标志 (启用Gzip压缩)
    this.writeHeaderField(4, this.getUint32Buffer(1));

    // 主种子
    this.writeHeaderField(5, masterSeed);

    // 加密IV
    this.writeHeaderField(8, encryptionIV);

    // KDF参数
    this.writeHeaderField(12, this.serializeKdfParameters(kdfParameters));

    // 流起始字节
    this.writeHeaderField(10, streamStartBytes);

    // 内部随机流ID
    this.writeHeaderField(11, this.getUint32Buffer(innerRandomStreamID));

    // 保护流密钥
    this.writeHeaderField(9, protectedStreamKey);

    // 头部结束标记
    this.writeUint8(0);
    this.writeUint32(0);
  }

  /**
   * 写入头部字段
   */
  private writeHeaderField(fieldId: number, data: Uint8Array): void {
    this.writeUint8(fieldId);
    this.writeUint32(data.length);
    this.buffer.push(data);
  }

  /**
   * 创建KDF参数
   */
  private createKdfParameters(): Map<string, any> {
    const params = new Map<string, any>();

    // 使用Argon2id作为KDF
    params.set('$UUID', '9e298b19-56db-4773-b23d-fc3ec6f0a1e6');
    params.set('salt', KdbxUtils.generateRandom(new Uint8Array(32)));
    params.set('parallelism', 2);
    params.set('memory', 1024 * 1024); // 1MB
    params.set('iterations', 10);
    params.set('version', 0x13);

    return params;
  }

  /**
   * 序列化KDF参数
   */
  private serializeKdfParameters(params: Map<string, any>): Uint8Array {
    const buffers: Uint8Array[] = [];

    params.forEach((value, key) => {
      const nameBytes = new util.TextEncoder().encode(key);

      if (typeof value === 'number') {
        // UInt32
        buffers.push(new Uint8Array([0x04]));
        buffers.push(this.writeVarInt(nameBytes.length));
        buffers.push(nameBytes);
        buffers.push(this.writeVarInt(4));
        buffers.push(this.getUint32Buffer(value));
      } else if (typeof value === 'bigint') {
        // UInt64
        buffers.push(new Uint8Array([0x05]));
        buffers.push(this.writeVarInt(nameBytes.length));
        buffers.push(nameBytes);
        buffers.push(this.writeVarInt(8));
        buffers.push(this.getUint64Buffer(value));
      } else if (typeof value === 'boolean') {
        // Bool
        buffers.push(new Uint8Array([0x08]));
        buffers.push(this.writeVarInt(nameBytes.length));
        buffers.push(nameBytes);
        buffers.push(this.writeVarInt(1));
        buffers.push(new Uint8Array([value ? 1 : 0]));
      } else if (value instanceof Uint8Array) {
        // Binary
        buffers.push(new Uint8Array([0x0C]));
        buffers.push(this.writeVarInt(nameBytes.length));
        buffers.push(nameBytes);
        buffers.push(this.writeVarInt(value.length));
        buffers.push(value);
      } else if (typeof value === 'string') {
        // String
        const valueBytes = new util.TextEncoder().encode(value);
        buffers.push(new Uint8Array([0x0C]));
        buffers.push(this.writeVarInt(nameBytes.length));
        buffers.push(nameBytes);
        buffers.push(this.writeVarInt(valueBytes.length));
        buffers.push(valueBytes);
      }
    });

    return this.concatUint8Arrays(buffers);
  }

  /**
   * 写入可变长度整数
   */
  private writeVarInt(value: number): Uint8Array {
    const bytes: number[] = [];

    do {
      let byte = value & 0x7F;
      value >>= 7;
      if (value > 0) {
        byte |= 0x80;
      }
      bytes.push(byte);
    } while (value > 0);

    return new Uint8Array(bytes);
  }

  /**
   * 写入8位无符号整数
   */
  private writeUint8(value: number): void {
    this.buffer.push(new Uint8Array([value]));
  }

  /**
   * 写入32位无符号整数
   */
  private writeUint32(value: number): void {
    this.buffer.push(this.getUint32Buffer(value));
  }

  /**
   * 获取32位无符号整数的缓冲区
   */
  private getUint32Buffer(value: number): Uint8Array {
    const buffer = new ArrayBuffer(4);
    const view = new DataView(buffer);
    view.setUint32(0, value, this.littleEndian);
    return new Uint8Array(buffer);
  }

  /**
   * 获取64位无符号整数的缓冲区
   */
  private getUint64Buffer(value: bigint): Uint8Array {
    const buffer = new ArrayBuffer(8);
    const view = new DataView(buffer);
    view.setBigUint64(0, value, this.littleEndian);
    return new Uint8Array(buffer);
  }

  /**
   * 合并Uint8Array数组
   */
  private concatUint8Arrays(arrays: Uint8Array[]): Uint8Array {
    const totalLength = arrays.reduce((acc, arr) => acc + arr.length, 0);
    const result = new Uint8Array(totalLength);
    let offset = 0;

    for (const arr of arrays) {
      result.set(arr, offset);
      offset += arr.length;
    }

    return result;
  }

  /**
   * 准备XML内容
   * @param database 数据库对象
   * @param protectedStreamKey 保护流密钥
   * @param innerRandomStreamID 随机流ID
   * @returns 生成的XML数据
   */
  private async prepareXmlContent(
    database: object,
    protectedStreamKey: Binary,
    innerRandomStreamID: InnerRandomStreamID
  ): Promise<Uint8Array> {
    try {
      // 默认启用Gzip压缩
      const compress = true;

      // 使用XML处理器生成内容
      return await KdbxXmlProcessor.generateXml(
        database,
        compress,
        protectedStreamKey,
        innerRandomStreamID
      );
    } catch (error) {
      console.error('Failed to prepare XML content:', error);
      throw error;
    }
  }
}
