import { Binary } from './models/KdbxTypes';
import { HeaderFieldID, CompressionFlags, InnerRandomStreamID, KdbxVersion } from './KdbxFormat';

/**
 * KDBX文件头部
 */
export class KdbxHeader {
  /**
   * 数据库版本
   */
  version: number;

  /**
   * 密码加密ID
   */
  cipherId: Binary;

  /**
   * 压缩标志
   */
  compressionFlags: CompressionFlags;

  /**
   * 主种子
   */
  masterSeed: Binary;

  /**
   * 转换种子（KDBX3.1）
   */
  transformSeed?: Binary;

  /**
   * 转换轮数（KDBX3.1）
   */
  transformRounds?: number;

  /**
   * 加密IV
   */
  encryptionIV: Binary;

  /**
   * 保护流密钥
   */
  protectedStreamKey?: Binary;

  /**
   * 流起始字节
   */
  streamStartBytes?: Binary;

  /**
   * 内部随机流ID
   */
  innerRandomStreamId?: InnerRandomStreamID;

  /**
   * KDF参数（KDBX4）
   */
  kdfParameters?: Map<string, any>;

  /**
   * 公共自定义数据
   */
  publicCustomData?: Map<string, any>;

  /**
   * 构造函数
   * @param version 数据库版本
   */
  constructor(version: number = KdbxVersion.V4) {
    this.version = version;
    this.cipherId = new Uint8Array(16);
    this.compressionFlags = CompressionFlags.GZIP;
    this.masterSeed = new Uint8Array(32);
    this.encryptionIV = new Uint8Array(16);

    if (this.isKdbx4()) {
      this.kdfParameters = new Map();
      this.innerRandomStreamId = InnerRandomStreamID.CHACHA20;
    } else {
      this.transformSeed = new Uint8Array(32);
      this.transformRounds = 100000;
      this.innerRandomStreamId = InnerRandomStreamID.SALSA20;
      this.protectedStreamKey = new Uint8Array(32);
      this.streamStartBytes = new Uint8Array(32);
    }
  }

  /**
   * 是否为KDBX4格式
   * @returns 是否为KDBX4
   */
  isKdbx4(): boolean {
    return this.version >= KdbxVersion.V4;
  }

  /**
   * 生成随机头部数据
   */
  generateRandomFields(): void {
    // 生成主种子
    crypto.getRandomValues(this.masterSeed);

    // 生成加密IV
    crypto.getRandomValues(this.encryptionIV);

    if (this.isKdbx4()) {
      // KDBX4特有字段
    } else {
      // KDBX3.1特有字段
      if (this.transformSeed) {
        crypto.getRandomValues(this.transformSeed);
      }

      if (this.protectedStreamKey) {
        crypto.getRandomValues(this.protectedStreamKey);
      }

      if (this.streamStartBytes) {
        crypto.getRandomValues(this.streamStartBytes);
      }
    }
  }

  /**
   * 从二进制数据读取头部
   * @param data 二进制数据
   * @param offset 偏移量
   * @returns 新的偏移量
   */
  readFromBinary(data: Binary, offset: number = 0): number {
    let pos = offset;

    // 读取头部字段
    while (pos < data.length) {
      const fieldId = data[pos++];

      // 结束标记
      if (fieldId === HeaderFieldID.END) {
        break;
      }

      // 读取字段大小
      const fieldSize = new DataView(data.buffer).getUint16(pos, true);
      pos += 2;

      // 读取字段数据
      const fieldData = data.slice(pos, pos + fieldSize);
      pos += fieldSize;

      // 处理字段
      this.processField(fieldId, fieldData);
    }

    return pos;
  }

  /**
   * 处理头部字段
   * @param fieldId 字段ID
   * @param data 字段数据
   */
  private processField(fieldId: number, data: Binary): void {
    switch (fieldId) {
      case HeaderFieldID.CIPHER_ID:
        this.cipherId = data;
        break;

      case HeaderFieldID.COMPRESSION_FLAGS:
        this.compressionFlags = new DataView(data.buffer).getUint32(0, true);
        break;

      case HeaderFieldID.MASTER_SEED:
        this.masterSeed = data;
        break;

      case HeaderFieldID.TRANSFORM_SEED:
        this.transformSeed = data;
        break;

      case HeaderFieldID.TRANSFORM_ROUNDS:
        this.transformRounds = new DataView(data.buffer).getUint64(0, true);
        break;

      case HeaderFieldID.ENCRYPTION_IV:
        this.encryptionIV = data;
        break;

      case HeaderFieldID.PROTECTED_STREAM_KEY:
        this.protectedStreamKey = data;
        break;

      case HeaderFieldID.STREAM_START_BYTES:
        this.streamStartBytes = data;
        break;

      case HeaderFieldID.INNER_RANDOM_STREAM_ID:
        this.innerRandomStreamId = new DataView(data.buffer).getUint32(0, true);
        break;

      case HeaderFieldID.KDF_PARAMETERS:
        this.kdfParameters = this.readVariantDictionary(data);
        break;

      case HeaderFieldID.PUBLIC_CUSTOM_DATA:
        this.publicCustomData = this.readVariantDictionary(data);
        break;
    }
  }

  /**
   * 读取变体字典
   * @param data 二进制数据
   * @returns 字典
   */
  private readVariantDictionary(data: Binary): Map<string, object> {
    const result = new Map<string, object>();
    // 实际实现需要解析KDBX的变体字典格式
    // 这里只是一个占位符
    return result;
  }

  /**
   * 写入二进制数据
   * @returns 二进制数据
   */
  writeToBinary(): Binary {
    // 计算总大小
    let size = 0;

    // 每个字段需要1字节ID + 2字节大小 + 字段数据
    if (this.cipherId) size += 3 + this.cipherId.length;
    size += 3 + 4; // 压缩标志
    if (this.masterSeed) size += 3 + this.masterSeed.length;
    if (!this.isKdbx4() && this.transformSeed) size += 3 + this.transformSeed.length;
    if (!this.isKdbx4() && this.transformRounds !== undefined) size += 3 + 8;
    if (this.encryptionIV) size += 3 + this.encryptionIV.length;
    if (!this.isKdbx4() && this.protectedStreamKey) size += 3 + this.protectedStreamKey.length;
    if (!this.isKdbx4() && this.streamStartBytes) size += 3 + this.streamStartBytes.length;
    if (this.innerRandomStreamId !== undefined) size += 3 + 4;

    // KDBX4特有字段
    if (this.isKdbx4() && this.kdfParameters) {
      // 这里需要计算KDF参数的大小
      // 暂时使用一个占位符
      size += 3 + 100;
    }

    if (this.publicCustomData) {
      // 这里需要计算公共自定义数据的大小
      // 暂时使用一个占位符
      size += 3 + 100;
    }

    // 结束标记
    size += 1;

    // 创建缓冲区
    const buffer = new Uint8Array(size);
    let pos = 0;

    // 写入字段
    if (this.cipherId) {
      pos = this.writeField(buffer, pos, HeaderFieldID.CIPHER_ID, this.cipherId);
    }

    // 写入压缩标志
    const compressionBuffer = new Uint8Array(4);
    new DataView(compressionBuffer.buffer).setUint32(0, this.compressionFlags, true);
    pos = this.writeField(buffer, pos, HeaderFieldID.COMPRESSION_FLAGS, compressionBuffer);

    if (this.masterSeed) {
      pos = this.writeField(buffer, pos, HeaderFieldID.MASTER_SEED, this.masterSeed);
    }

    if (!this.isKdbx4()) {
      // KDBX3.1特有字段
      if (this.transformSeed) {
        pos = this.writeField(buffer, pos, HeaderFieldID.TRANSFORM_SEED, this.transformSeed);
      }

      if (this.transformRounds !== undefined) {
        const roundsBuffer = new Uint8Array(8);
        new DataView(roundsBuffer.buffer).setBigUint64(0, BigInt(this.transformRounds), true);
        pos = this.writeField(buffer, pos, HeaderFieldID.TRANSFORM_ROUNDS, roundsBuffer);
      }

      if (this.protectedStreamKey) {
        pos = this.writeField(buffer, pos, HeaderFieldID.PROTECTED_STREAM_KEY, this.protectedStreamKey);
      }

      if (this.streamStartBytes) {
        pos = this.writeField(buffer, pos, HeaderFieldID.STREAM_START_BYTES, this.streamStartBytes);
      }
    } else {
      // KDBX4特有字段
      if (this.kdfParameters) {
        // 这里需要实现KDF参数的序列化
        // 暂时使用一个占位符
        const kdfBuffer = new Uint8Array(100);
        pos = this.writeField(buffer, pos, HeaderFieldID.KDF_PARAMETERS, kdfBuffer);
      }
    }

    if (this.innerRandomStreamId !== undefined) {
      const streamIdBuffer = new Uint8Array(4);
      new DataView(streamIdBuffer.buffer).setUint32(0, this.innerRandomStreamId, true);
      pos = this.writeField(buffer, pos, HeaderFieldID.INNER_RANDOM_STREAM_ID, streamIdBuffer);
    }

    if (this.publicCustomData) {
      // 这里需要实现公共自定义数据的序列化
      // 暂时使用一个占位符
      const customDataBuffer = new Uint8Array(100);
      pos = this.writeField(buffer, pos, HeaderFieldID.PUBLIC_CUSTOM_DATA, customDataBuffer);
    }

    // 写入结束标记
    buffer[pos++] = HeaderFieldID.END;

    return buffer.slice(0, pos);
  }

  /**
   * 写入字段
   * @param buffer 缓冲区
   * @param offset 偏移量
   * @param fieldId 字段ID
   * @param data 字段数据
   * @returns 新的偏移量
   */
  private writeField(buffer: Binary, offset: number, fieldId: number, data: Binary): number {
    let pos = offset;

    // 写入字段ID
    buffer[pos++] = fieldId;

    // 写入字段大小
    new DataView(buffer.buffer).setUint16(pos, data.length, true);
    pos += 2;

    // 写入字段数据
    buffer.set(data, pos);
    pos += data.length;

    return pos;
  }
}
