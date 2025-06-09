import { Binary, KdfParameters, VariantDictionaryValue } from './models/KdbxTypes';
import { CompressionFlags, HeaderFieldID, InnerRandomStreamID, KdbxVersion } from './KdbxFormat';
import { KdbxUtils } from './utils/KdbxUtils';

// KDBX 头部常量
const KDBX_SIGNATURE_1 = 0x9AA2D903;
const KDBX_SIGNATURE_2 = 0xB54BFB67;
const KDBX_VERSION_32 = 0x00030001;
const KDBX_VERSION_CRITICAL_MASK = 0xFFFF0000;
const KDBX_HEADER_END_BYTES = [0x0D, 0x0A, 0x0D, 0x0A];

// 变长字典类型
enum VariantDictionaryType {
  KdfParameters = 0,
  PublicCustomData = 1
}

// KDF 参数字段类型
enum KdfParameterType {
  UUID = 0x01,
  Rounds = 0x02,
  Salt = 0x03,
  Parallelism = 0x04,
  Memory = 0x05,
  Version = 0x06,
  SecretKey = 0x07,
  AssocData = 0x08
}

/**
 * 字段读取
 */
interface ReadField {
  fieldType: number;
  fieldSize: number;
  newPos: number
}

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
  kdfParameters?: KdfParameters;
  /**
   * 公共自定义数据
   */
  publicCustomData?: Map<string, ESObject>;

  /**
   * 构造函数
   * @param version 数据库版本
   */
  constructor(version: number = KdbxVersion.V4) {
    if (version !== KdbxVersion.V3_1 && version !== KdbxVersion.V4) {
      throw new Error('Invalid version');
    }
    this.version = version;
    this.cipherId = new Uint8Array(16);
    this.compressionFlags = CompressionFlags.GZIP;
    this.masterSeed = new Uint8Array(32);
    this.encryptionIV = new Uint8Array(16).fill(0x03);

    if (this.isKdbx4()) {
      this.kdfParameters = {} as KdfParameters;
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
    KdbxUtils.fillRandom(this.masterSeed);

    // 生成随机加密IV
    KdbxUtils.fillRandom(this.encryptionIV);

    if (this.isKdbx4()) {
      // KDBX4特有字段
      if (this.kdfParameters) {
        this.kdfParameters.uuid = new Uint8Array(16);
        KdbxUtils.fillRandom(this.kdfParameters.uuid);

        if (!this.kdfParameters.salt) {
          this.kdfParameters.salt = new Uint8Array(32);
        }
        KdbxUtils.fillRandom(this.kdfParameters.salt);
      }
    } else {
      // KDBX3.1特有字段
      if (this.transformSeed) {
        KdbxUtils.fillRandom(this.transformSeed);
      }

      if (this.protectedStreamKey) {
        KdbxUtils.fillRandom(this.protectedStreamKey);
      }

      if (this.streamStartBytes) {
        KdbxUtils.fillRandom(this.streamStartBytes);
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
    if (!data || data.length === 0) {
      throw new Error('Invalid header: Empty data');
    }

    let pos = offset;

    // 检查偏移量是否有效
    if (pos < 0 || pos >= data.length) {
      throw new Error(`Invalid header: Offset ${pos} out of bounds (0-${data.length - 1})`);
    }

    // 读取头部字段
    while (pos < data.length) {
      // 检查是否有足够空间读取字段ID
      if (pos + 1 > data.length) {
        throw new Error('Invalid header: Incomplete field ID');
      }

      const fieldId = data[pos++];

      // 结束标记
      if (fieldId === HeaderFieldID.END) {
        break;
      }

      // 检查是否有足够的空间读取字段大小
      if (pos + 2 > data.length) {
        throw new Error('Invalid header: Incomplete field size');
      }

      // 读取字段大小
      const fieldSize = new DataView(data.buffer).getUint16(pos, true);
      pos += 2;

      // 检查字段大小是否有效
      if (fieldSize < 0 || pos + fieldSize > data.length) {
        throw new Error(`Invalid header: Field size ${fieldSize} at offset ${pos} exceeds data length ${data.length}`);
      }

      // 读取字段数据
      const fieldData = data.slice(pos, pos + fieldSize);
      pos += fieldSize;

      try {
        // 处理字段
        this.processField(fieldId, fieldData);
      } catch (e) {
        throw new Error(`Invalid header field ${fieldId}: ${e.message}`);
      }
    }

    // 验证是否读取了必要的字段
    if (!this.cipherId || !this.masterSeed || !this.encryptionIV) {
      throw new Error('Invalid header: Missing required fields');
    }

    return pos;
  }

  /**
   * 处理头部字段
   * @param fieldId 字段ID
   * @param data 字段数据
   */
  private processField(fieldId: number, data: Binary): void {
    // 验证字段ID是否有效
    if (fieldId < 0 || fieldId > HeaderFieldID.PUBLIC_CUSTOM_DATA) {
      throw new Error(`Invalid header field ID: ${fieldId}`);
    }

    // 验证数据是否有效
    if (!data || data.length === 0) {
      throw new Error(`Empty data for field ID: ${fieldId}`);
    }

    try {
      switch (fieldId) {
        case HeaderFieldID.CIPHER_ID:
          if (data.length !== 16) {
            throw new Error('Data length mismatch: CipherID expected 16 bytes');
          }
          this.cipherId = data;
          break;

        case HeaderFieldID.COMPRESSION_FLAGS:
          if (data.length !== 4) {
            throw new Error('Data length mismatch: CompressionFlags expected 4 bytes');
          }
          this.compressionFlags = new DataView(data.buffer).getUint32(0, true);
          break;

        case HeaderFieldID.MASTER_SEED:
          if (data.length !== 32) {
            throw new Error('Data length mismatch: MasterSeed expected 32 bytes');
          }
          this.masterSeed = data;
          break;

        case HeaderFieldID.TRANSFORM_SEED:
          if (data.length !== 32) {
            throw new Error('Data length mismatch: TransformSeed expected 32 bytes');
          }
          this.transformSeed = data;
          break;

        case HeaderFieldID.TRANSFORM_ROUNDS:
          if (data.length !== 8) {
            throw new Error('Data length mismatch: TransformRounds expected 8 bytes');
          }
          this.transformRounds = Number(new DataView(data.buffer).getBigUint64(0, true));
          break;

        case HeaderFieldID.ENCRYPTION_IV:
          if (data.length !== 16) {
            throw new Error('Data length mismatch: EncryptionIV expected 16 bytes');
          }
          this.encryptionIV = data;
          break;

        case HeaderFieldID.PROTECTED_STREAM_KEY:
          if (data.length !== 32) {
            throw new Error('Data length mismatch: ProtectedStreamKey expected 32 bytes');
          }
          this.protectedStreamKey = data;
          break;

        case HeaderFieldID.STREAM_START_BYTES:
          if (data.length !== 32) {
            throw new Error('Data length mismatch: StreamStartBytes expected 32 bytes');
          }
          this.streamStartBytes = data;
          break;

        case HeaderFieldID.INNER_RANDOM_STREAM_ID:
          if (data.length !== 4) {
            throw new Error('Data length mismatch: InnerRandomStreamID expected 4 bytes');
          }
          this.innerRandomStreamId = new DataView(data.buffer).getUint32(0, true);
          break;

        case HeaderFieldID.KDF_PARAMETERS:
          if (data.length < 4) {
            throw new Error('Invalid header: KDF parameters too short');
          }
          this.kdfParameters = this.readVariantDictionary(data);
          break;

        case HeaderFieldID.PUBLIC_CUSTOM_DATA:
          if (data.length < 4) {
            throw new Error('Invalid header: Public custom data too short');
          }
          this.publicCustomData = this.readVariantDictionary(data);
          break;

        default:
          throw new Error(`Invalid header: Unknown field ID ${fieldId}`);
      }
    } catch (e) {
      throw new Error(`Invalid header: ${e.message}`);
    }
  }

  /**
   * 读取变体字典
   * @param data 二进制数据
   * @param type 字典类型 (KDF参数或公共自定义数据)
   * @returns 解析后的字典数据
   * @throws 如果数据格式无效或缺少必要字段
   */
  private readVariantDictionary<T = Map<string, VariantDictionaryValue> | KdfParameters>(
    data: Binary,
    type: VariantDictionaryType = VariantDictionaryType.KdfParameters
  ): T {
    const dataView = new DataView(data.buffer);
    let pos = 0;

    // 验证输入数据
    if (!data || data.length < 4) {
      throw new Error(`Invalid variant dictionary: data too short (${data?.length ?? 0} bytes)`);
    }

    // 读取变体字典项数量
    const count = dataView.getUint32(pos, true);
    pos += 4;

    // 验证项数量
    if (count < 0 || count > 100) {
      throw new Error(`Invalid variant dictionary: invalid item count ${count}`);
    }

    if (type === VariantDictionaryType.KdfParameters) {
      return this.readKdfParameters(data, dataView, pos, count) as T;
    } else {
      return this.readPublicCustomData(data, dataView, pos, count) as T;
    }
  }

  /**
   * 读取KDF参数
   * @param data 二进制数据
   * @param dataView DataView对象
   * @param pos 当前读取位置
   * @param count 参数项数量
   * @returns 解析后的KDF参数
   * @throws 如果数据格式无效或缺少必要字段
   */
  private readKdfParameters(
    data: Binary,
    dataView: DataView,
    pos: number,
    count: number
  ): KdfParameters {
    const kdfParameters: KdfParameters = {
      uuid: new Uint8Array(16),
      rounds: 100000,
      salt: new Uint8Array(32),
      parallelism: 2,
      memory: 1024 * 1024,
      version: 19,
      secretKey: new Uint8Array(0),
      assocData: new Uint8Array(0)
    };

    for (let i = 0; i < count; i++) {
      // 读取字段类型和大小
      const fieldHeader: ReadField = this.readFieldHeader(data, dataView, pos);
      const fieldType = fieldHeader.fieldType;
      const fieldSize = fieldHeader.fieldSize;
      const newPos = fieldHeader.newPos;
      pos = newPos;

      // 读取字段值
      const fieldValue = data.slice(pos, pos + fieldSize);
      pos += fieldSize;

      try {
        switch (fieldType) {
          case KdfParameterType.UUID:
            this.validateFieldSize(fieldSize, 16, 'UUID');
            kdfParameters.uuid = fieldValue;
            break;

          case KdfParameterType.Rounds:
            this.validateFieldSize(fieldSize, 4, 'rounds');
            const rounds = dataView.getUint32(pos - fieldSize, true);
            this.validatePositiveNumber(rounds, 'rounds');
            kdfParameters.rounds = rounds;
            break;

          case KdfParameterType.Salt:
            this.validateFieldSize(fieldSize, 32, 'salt');
            kdfParameters.salt = fieldValue;
            break;

          case KdfParameterType.Parallelism:
            this.validateFieldSize(fieldSize, 4, 'parallelism');
            const parallelism = dataView.getUint32(pos - fieldSize, true);
            this.validatePositiveNumber(parallelism, 'parallelism');
            kdfParameters.parallelism = parallelism;
            break;

          case KdfParameterType.Memory:
            this.validateFieldSize(fieldSize, 8, 'memory');
            const memory = Number(dataView.getBigUint64(pos - fieldSize, true));
            this.validatePositiveNumber(memory, 'memory', 1024);
            kdfParameters.memory = memory;
            break;

          case KdfParameterType.Version:
            this.validateFieldSize(fieldSize, 4, 'version');
            const version = dataView.getUint32(pos - fieldSize, true);
            if (version < 19) {
              throw new Error(`Invalid KDF version ${version}, minimum is 19`);
            }
            kdfParameters.version = version;
            break;

          case KdfParameterType.SecretKey:
            kdfParameters.secretKey = fieldValue;
            break;

          case KdfParameterType.AssocData:
            kdfParameters.assocData = fieldValue;
            break;

          default:
            throw new Error(`Unknown KDF parameter type 0x${fieldType.toString(16)}`);
        }
      } catch (e) {
        throw new Error(`Error processing KDF parameter type 0x${fieldType.toString(16)}: ${e.message}`);
      }
    }

    // 验证必要字段
    if (!kdfParameters.uuid || kdfParameters.uuid.length !== 16) {
      throw new Error('Missing or invalid required KDF parameter: UUID');
    }
    if (!kdfParameters.salt || kdfParameters.salt.length !== 32) {
      throw new Error('Missing or invalid required KDF parameter: salt');
    }

    return kdfParameters;
  }

  /**
   * 读取公共自定义数据
   * @param data 二进制数据
   * @param dataView DataView对象
   * @param pos 当前读取位置
   * @param count 数据项数量
   * @returns 解析后的公共自定义数据
   * @throws 如果数据格式无效
   */
  private readPublicCustomData(
    data: Binary,
    dataView: DataView,
    pos: number,
    count: number
  ): Map<string, VariantDictionaryValue> {
    const customData = new Map<string, VariantDictionaryValue>();

    for (let i = 0; i < count; i++) {
      // 读取key长度
      if (pos + 4 > data.length) {
        throw new Error('Incomplete public custom data: missing key length');
      }
      const keyLength = dataView.getUint32(pos, true);
      pos += 4;

      // 读取key
      if (pos + keyLength > data.length) {
        throw new Error('Incomplete public custom data: missing key data');
      }
      const key = KdbxUtils.bytesToStr(data.slice(pos, pos + keyLength));
      pos += keyLength;

      // 读取value类型和大小
      const fieldHeader:ReadField = this.readFieldHeader(data, dataView, pos);
      const fieldType = fieldHeader.fieldType;
      const fieldSize = fieldHeader.fieldSize;
      const newPos = fieldHeader.newPos;
      pos = newPos;

      // 读取value
      if (pos + fieldSize > data.length) {
        throw new Error('Incomplete public custom data: missing value data');
      }
      const valueData = data.slice(pos, pos + fieldSize);
      pos += fieldSize;

      // 处理value
      switch (fieldType) {
        case 0x01: // 二进制数据
          customData.set(key, valueData);
          break;
        case 0x02: // 字符串
          customData.set(key, KdbxUtils.bytesToStr(valueData));
          break;
        case 0x03: // 数字
          if (fieldSize !== 8) {
            throw new Error(`Invalid number size ${fieldSize}, expected 8 bytes`);
          }
          customData.set(key, dataView.getFloat64(pos - fieldSize, true));
          break;
        case 0x04: // 布尔值
          if (fieldSize !== 1) {
            throw new Error(`Invalid boolean size ${fieldSize}, expected 1 byte`);
          }
          customData.set(key, dataView.getUint8(pos - fieldSize) !== 0);
          break;
        default:
          throw new Error(`Unknown public custom data type 0x${fieldType.toString(16)}`);
      }
    }

    return customData;
  }

  /**
   * 读取字段头部信息
   * @param data 二进制数据
   * @param dataView DataView对象
   * @param pos 当前读取位置
   * @returns 字段类型、字段大小和新的读取位置
   * @throws 如果数据不完整
   */
  private readFieldHeader(data: Binary, dataView: DataView, pos: number): ReadField {
    if (pos + 5 > data.length) {
      throw new Error('Incomplete field header');
    }

    const fieldType = dataView.getUint8(pos++);
    const fieldSize = dataView.getUint32(pos, true);
    pos += 4;

    if (fieldSize < 0 || pos + fieldSize > data.length) {
      throw new Error(`Invalid field size ${fieldSize} at position ${pos}`);
    }

    return { fieldType:fieldType ,fieldSize:fieldSize, newPos:pos };
  }

  /**
   * 验证字段大小
   * @param actual 实际大小
   * @param expected 预期大小
   * @param fieldName 字段名称
   * @throws 如果大小不匹配
   */
  private validateFieldSize(actual: number, expected: number, fieldName: string): void {
    if (actual !== expected) {
      throw new Error(`Invalid ${fieldName} size ${actual}, expected ${expected}`);
    }
  }

  /**
   * 验证正数
   * @param value 要验证的值
   * @param fieldName 字段名称
   * @param min 最小值 (默认为1)
   * @throws 如果值无效
   */
  private validatePositiveNumber(value: number, fieldName: string, min: number = 1): void {
    if (value < min) {
      throw new Error(`Invalid ${fieldName} value ${value}, minimum is ${min}`);
    }
  }

  /**
   * 写入二进制数据
   * @returns 二进制数据
   */
  writeToBinary(): Binary {
    // 验证必要字段是否存在
    if (!this.cipherId || !this.masterSeed || !this.encryptionIV) {
      throw new Error('Cannot write header: Missing required fields');
    }

    // 计算总大小
    let size = 0;

    // 每个字段需要1字节ID + 2字节大小 + 字段数据
    size += 3 + this.cipherId.length; // cipherId
    size += 3 + 4; // compressionFlags
    size += 3 + this.masterSeed.length; // masterSeed
    size += 3 + this.encryptionIV.length; // encryptionIV

    if (!this.isKdbx4()) {
      // KDBX3.1特有字段
      if (this.transformSeed) {
        size += 3 + this.transformSeed.length;
      }
      if (this.transformRounds !== undefined) {
        size += 3 + 8;
      }
      if (this.protectedStreamKey) {
        size += 3 + this.protectedStreamKey.length;
      }
      if (this.streamStartBytes) {
        size += 3 + this.streamStartBytes.length;
      }
    } else {
      // KDBX4特有字段
      if (this.kdfParameters) {
        size += 3 + this.calculateKdfSize();
      }
    }

    if (this.innerRandomStreamId !== undefined) {
      size += 3 + 4;
    }

    if (this.publicCustomData) {
      size += 3 + this.calculateCustomDataSize();
    }

    // 结束标记
    size += 1;

    // 创建缓冲区
    const buffer = new Uint8Array(size);
    let pos = 0;

    // 写入必要字段
    pos = this.writeField(buffer, pos, HeaderFieldID.CIPHER_ID, this.cipherId);

    const compressionBuffer = new Uint8Array(4);
    new DataView(compressionBuffer.buffer).setUint32(0, this.compressionFlags, true);
    pos = this.writeField(buffer, pos, HeaderFieldID.COMPRESSION_FLAGS, compressionBuffer);

    pos = this.writeField(buffer, pos, HeaderFieldID.MASTER_SEED, this.masterSeed);

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
        const kdfData = this.serializeKdfParameters();
        pos = this.writeField(buffer, pos, HeaderFieldID.KDF_PARAMETERS, kdfData);
      }
    }

    // 写入加密IV
    pos = this.writeField(buffer, pos, HeaderFieldID.ENCRYPTION_IV, this.encryptionIV);

    if (this.innerRandomStreamId !== undefined) {
      const streamIdBuffer = new Uint8Array(4);
      new DataView(streamIdBuffer.buffer).setUint32(0, this.innerRandomStreamId, true);
      pos = this.writeField(buffer, pos, HeaderFieldID.INNER_RANDOM_STREAM_ID, streamIdBuffer);
    }

    if (this.publicCustomData) {
      const customData = this.serializeCustomData();
      pos = this.writeField(buffer, pos, HeaderFieldID.PUBLIC_CUSTOM_DATA, customData);
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

  /**
   * 计算KDF参数的大小
   * @returns KDF参数的大小
   */
  private calculateKdfSize(): number {
    if (!this.kdfParameters) {
      return 0;
    }

    let size = 4; // 项数量字段

    // UUID (类型+长度+数据)
    size += 1 + 4 + 16;

    // rounds (类型+长度+数据)
    size += 1 + 4 + 4;

    // salt (类型+长度+数据)
    size += 1 + 4 + (this.kdfParameters.salt?.length || 32);

    // parallelism (类型+长度+数据)
    size += 1 + 4 + 4;

    // memory (类型+长度+数据)
    size += 1 + 4 + 8;

    // version (类型+长度+数据)
    size += 1 + 4 + 4;

    // secretKey (类型+长度+数据)
    size += 1 + 4 + (this.kdfParameters.secretKey?.length || 0);

    // assocData (类型+长度+数据)
    size += 1 + 4 + (this.kdfParameters.assocData?.length || 0);

    return size;
  }

  /**
   * 计算公共自定义数据的大小
   * @returns 公共自定义数据的大小
   */
  private calculateCustomDataSize(): number {
    if (!this.publicCustomData || this.publicCustomData.size === 0) {
      return 0;
    }

    let size = 4; // 项数量字段

    this.publicCustomData.forEach((value: Uint8Array | string | number | boolean, key: string) => {
      size += 4; // key长度字段
      size += key.length; // key数据
      size += 1; // value类型字段
      size += 4; // value长度字段

      if (value instanceof Uint8Array) {
        size += value.length; // 二进制数据
      } else if (typeof value === 'string') {
        size += KdbxUtils.strToBytes(value).length; // 字符串数据
      } else if (typeof value === 'number') {
        size += 8; // 数字数据
      } else if (typeof value === 'boolean') {
        size += 1; // 布尔数据
      }
    });

    return size;
  }

  /**
   * 序列化KDF参数
   * @returns 二进制数据
   */
  private serializeKdfParameters(): Binary {
    if (!this.kdfParameters) {
      return new Uint8Array(0);
    }

    // 计算总大小
    const size = this.calculateKdfSize();
    const buffer = new Uint8Array(size);
    const dataView = new DataView(buffer.buffer);
    let pos = 0;

    // 写入项数量
    dataView.setUint32(pos, 7, true); // 7个KDF参数项
    pos += 4;

    // 写入UUID (类型0x01)
    buffer[pos++] = 0x01;
    dataView.setUint32(pos, 16, true);
    pos += 4;
    buffer.set(this.kdfParameters.uuid ?? new Uint8Array(16), pos);
    pos += 16;

    // 写入rounds (类型0x02)
    buffer[pos++] = 0x02;
    dataView.setUint32(pos, 4, true);
    pos += 4;
    dataView.setUint32(pos, this.kdfParameters.rounds ?? 100000, true);
    pos += 4;

    // 写入salt (类型0x03)
    buffer[pos++] = 0x03;
    const salt = this.kdfParameters.salt ?? new Uint8Array(32);
    dataView.setUint32(pos, salt.length, true);
    pos += 4;
    buffer.set(salt, pos);
    pos += salt.length;

    // 写入parallelism (类型0x04)
    buffer[pos++] = 0x04;
    dataView.setUint32(pos, 4, true);
    pos += 4;
    dataView.setUint32(pos, this.kdfParameters.parallelism ?? 2, true);
    pos += 4;

    // 写入memory (类型0x05)
    buffer[pos++] = 0x05;
    dataView.setUint32(pos, 8, true);
    pos += 4;
    dataView.setBigUint64(pos, BigInt(this.kdfParameters.memory ?? 1024 * 1024), true);
    pos += 8;

    // 写入version (类型0x06)
    buffer[pos++] = 0x06;
    dataView.setUint32(pos, 4, true);
    pos += 4;
    dataView.setUint32(pos, this.kdfParameters.version ?? 19, true);
    pos += 4;

    // 写入secretKey (类型0x07)
    buffer[pos++] = 0x07;
    const secretKey = this.kdfParameters.secretKey ?? new Uint8Array(0);
    dataView.setUint32(pos, secretKey.length, true);
    pos += 4;
    buffer.set(secretKey, pos);
    pos += secretKey.length;

    // 写入assocData (类型0x08)
    buffer[pos++] = 0x08;
    const assocData = this.kdfParameters.assocData ?? new Uint8Array(0);
    dataView.setUint32(pos, assocData.length, true);
    pos += 4;
    buffer.set(assocData, pos);
    pos += assocData.length;

    // 验证写入的数据大小是否匹配
    if (pos !== size) {
      throw new Error(`KDF parameters serialization size mismatch (expected: ${size}, actual: ${pos})`);
    }

    return buffer;
  }

  /**
   * 序列化公共自定义数据
   * @returns 二进制数据
   */
  private serializeCustomData(): Binary {
    if (!this.publicCustomData || this.publicCustomData.size === 0) {
      return new Uint8Array(0);
    }

    // 计算总大小
    const size = this.calculateCustomDataSize();
    const buffer = new Uint8Array(size);
    const dataView = new DataView(buffer.buffer);
    let pos = 0;

    // 写入项数量
    dataView.setUint32(pos, this.publicCustomData.size, true);
    pos += 4;

    // 写入每个键值对
    this.publicCustomData.forEach((value: Uint8Array | string | number | boolean, key: string) => {
      // 写入key长度
      dataView.setUint32(pos, key.length, true);
      pos += 4;

      // 写入key
      const keyBytes = KdbxUtils.strToBytes(key);
      buffer.set(keyBytes, pos);
      pos += key.length;

      // 写入value类型
      if (value instanceof Uint8Array) {
        buffer[pos++] = 0x01; // 二进制类型
      } else if (typeof value === 'string') {
        buffer[pos++] = 0x02; // 字符串类型
      } else if (typeof value === 'number') {
        buffer[pos++] = 0x03; // 数字类型
      } else if (typeof value === 'boolean') {
        buffer[pos++] = 0x04; // 布尔类型
      }

      // 写入value长度和value
      if (value instanceof Uint8Array) {
        dataView.setUint32(pos, value.length, true);
        pos += 4;
        buffer.set(value, pos);
        pos += value.length;
      } else if (typeof value === 'string') {
        const valueBytes = KdbxUtils.strToBytes(value);
        dataView.setUint32(pos, valueBytes.length, true);
        pos += 4;
        buffer.set(valueBytes, pos);
        pos += valueBytes.length;
      } else if (typeof value === 'number') {
        dataView.setUint32(pos, 8, true);
        pos += 4;
        dataView.setFloat64(pos, value, true);
        pos += 8;
      } else if (typeof value === 'boolean') {
        dataView.setUint32(pos, 1, true);
        pos += 4;
        buffer[pos++] = value ? 1 : 0;
      }
    });

    // 验证写入的数据大小是否匹配
    if (pos !== size) {
      throw new Error('Custom data serialization size mismatch');
    }

    return buffer;
  }
}