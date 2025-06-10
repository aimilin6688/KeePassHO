import { Any, Binary, VariantDictionaryItem } from './models/KdbxTypes';
import { KdbxHeaderModel, KdbxHeaderFieldType, KdfParameterType } from './models/KdbxHeader';
import { RandomUtils } from './utils/RandomUtils';
import { ByteUtils } from './utils/ByteUtils';

/**
 * KDBX文件头部处理类
 */
export class KdbxHeader {
  private model: KdbxHeaderModel;

  /**
   * 构造函数
   * @param version KDBX版本号，默认为4
   */
  constructor(version: number = 4) {
    this.model = {
      version: version,
      cipherId: new Uint8Array(16),
      compressionFlags: 0,
      masterSeed: new Uint8Array(32),
      encryptionIV: new Uint8Array(16),
      innerRandomStreamId: 0
    };

    if (version >= 4) {
      this.model.kdfParameters = {
        uuid: new Uint8Array(16),
        iterations: 0,
        salt: new Uint8Array(32)
      };
    } else {
      this.model.transformSeed = new Uint8Array(32);
      this.model.transformRounds = 0;
      this.model.protectedStreamKey = new Uint8Array(32);
      this.model.streamStartBytes = new Uint8Array(32);
    }
  }

  /**
   * 生成随机字段
   */
  public generateRandomFields(): void {
    // 生成通用字段的随机值
    this.model.masterSeed = RandomUtils.getRandomBytes(32);
    this.model.encryptionIV = RandomUtils.getRandomBytes(16);

    if (this.model.version >= 4) {
      // KDBX4特有字段
      if (this.model.kdfParameters) {
        this.model.kdfParameters.salt = RandomUtils.getRandomBytes(32);
      }
    } else {
      // KDBX3.1特有字段
      if (this.model.transformSeed) {
        this.model.transformSeed = RandomUtils.getRandomBytes(32);
      }
      if (this.model.protectedStreamKey) {
        this.model.protectedStreamKey = RandomUtils.getRandomBytes(32);
      }
      if (this.model.streamStartBytes) {
        this.model.streamStartBytes = RandomUtils.getRandomBytes(32);
      }
    }
  }

  /**
   * 从二进制数据读取头部信息
   * @param data 二进制数据
   * @returns 读取的字节数
   */
  public readFromBinary(data: Binary): number {
    let offset = 0;

    while (offset < data.length) {
      const fieldType = data[offset++];
      if (fieldType === KdbxHeaderFieldType.END) {
        break;
      }

      const fieldSize = ByteUtils.readInt16LE(data, offset);
      offset += 2;

      const fieldData = data.slice(offset, offset + fieldSize);
      offset += fieldSize;

      this.processField(fieldType, fieldData);
    }

    return offset;
  }

  /**
   * 处理单个字段
   * @param fieldType 字段类型
   * @param fieldData 字段数据
   */
  private processField(fieldType: KdbxHeaderFieldType, fieldData: Binary): void {
    switch (fieldType) {
      case KdbxHeaderFieldType.CIPHER_ID:
        this.model.cipherId = fieldData;
        break;
      case KdbxHeaderFieldType.COMPRESSION_FLAGS:
        this.model.compressionFlags = ByteUtils.readInt32LE(fieldData, 0);
        break;
      case KdbxHeaderFieldType.MASTER_SEED:
        this.model.masterSeed = fieldData;
        break;
      case KdbxHeaderFieldType.ENCRYPTION_IV:
        this.model.encryptionIV = fieldData;
        break;
      case KdbxHeaderFieldType.INNER_RANDOM_STREAM_ID:
        this.model.innerRandomStreamId = ByteUtils.readInt32LE(fieldData, 0);
        break;
      case KdbxHeaderFieldType.KDF_PARAMETERS:
        if (this.model.version >= 4) {
          this.processKdfParameters(fieldData);
        }
        break;
      case KdbxHeaderFieldType.PUBLIC_CUSTOM_DATA:
        this.processPublicCustomData(fieldData);
        break;
      // KDBX3.1特有字段
      case KdbxHeaderFieldType.TRANSFORM_SEED:
        if (this.model.version < 4) {
          this.model.transformSeed = fieldData;
        }
        break;
      case KdbxHeaderFieldType.TRANSFORM_ROUNDS:
        if (this.model.version < 4) {
          this.model.transformRounds = ByteUtils.readInt64LE(fieldData, 0);
        }
        break;
      case KdbxHeaderFieldType.PROTECTED_STREAM_KEY:
        if (this.model.version < 4) {
          this.model.protectedStreamKey = fieldData;
        }
        break;
      case KdbxHeaderFieldType.STREAM_START_BYTES:
        if (this.model.version < 4) {
          this.model.streamStartBytes = fieldData;
        }
        break;
    }
  }

  /**
   * 处理KDF参数
   * @param data KDF参数数据
   */
  private processKdfParameters(data: Binary): void {
    let offset = 0;
    while (offset < data.length) {
      const paramType = data[offset++];
      if (paramType === KdfParameterType.END) {
        break;
      }

      const paramSize = ByteUtils.readInt32LE(data, offset);
      offset += 4;

      const paramData = data.slice(offset, offset + paramSize);
      offset += paramSize;

      if (this.model.kdfParameters) {
        switch (paramType) {
          case KdfParameterType.UUID:
            this.model.kdfParameters.uuid = paramData;
            break;
          case KdfParameterType.SALT:
            this.model.kdfParameters.salt = paramData;
            break;
          case KdfParameterType.PARALLELISM:
            this.model.kdfParameters.parallelism = ByteUtils.readInt32LE(paramData, 0);
            break;
          case KdfParameterType.MEMORY:
            this.model.kdfParameters.memory = ByteUtils.readInt64LE(paramData, 0);
            break;
          case KdfParameterType.ITERATIONS:
            this.model.kdfParameters.iterations = ByteUtils.readInt64LE(paramData, 0);
            break;
          case KdfParameterType.VERSION:
            this.model.kdfParameters.version = ByteUtils.readInt32LE(paramData, 0);
            break;
        }
      }
    }
  }

  /**
   * 处理公共自定义数据
   * @param data 自定义数据
   */
  public processPublicCustomData(data: Binary): void {
    const customData = new Map<string, VariantDictionaryItem>();
    let offset = 0;

    while (offset < data.length) {
      // 读取键的长度
      const keyLength = ByteUtils.readInt32LE(data, offset);
      offset += 4;

      // 读取键
      const keyBytes = data.slice(offset, offset + keyLength);
      const key = ByteUtils.bytesToString(keyBytes);
      offset += keyLength;

      // 读取值的类型
      const valueType = data[offset++];

      // 读取值的长度
      const valueLength = ByteUtils.readInt32LE(data, offset);
      offset += 4;

      // 读取值
      const valueBytes = data.slice(offset, offset + valueLength);
      offset += valueLength;

      // 根据类型解析值
      let value: Any;
      switch (valueType) {
        case 0x00: // UInt32
          value = ByteUtils.readInt32LE(valueBytes, 0);
          break;
        case 0x01: // UInt64
          value = ByteUtils.readInt64LE(valueBytes, 0);
          break;
        case 0x02: // Bool
          value = valueBytes[0] !== 0;
          break;
        case 0x03: // Int32
          value = ByteUtils.readInt32LE(valueBytes, 0);
          break;
        case 0x04: // Int64
          value = ByteUtils.readInt64LE(valueBytes, 0);
          break;
        case 0x05: // String
          value = ByteUtils.bytesToString(valueBytes);
          break;
        case 0x06: // ByteArray
          value = valueBytes;
          break;
        default:
          console.error(`Unknown value type: ${valueType}`);
          continue;
      }

      customData.set(key, {
        type: valueType,
        value: value
      });
    }

    this.model.publicCustomData = customData;
  }

  /**
   * 将头部信息写入二进制数据
   * @returns 二进制数据
   */
  public writeToBinary(): Binary {
    const chunks: Binary[] = [];

    // 写入通用字段
    this.writeField(chunks, KdbxHeaderFieldType.CIPHER_ID, this.model.cipherId);
    this.writeField(chunks, KdbxHeaderFieldType.COMPRESSION_FLAGS, ByteUtils.writeInt32LE(this.model.compressionFlags));
    this.writeField(chunks, KdbxHeaderFieldType.MASTER_SEED, this.model.masterSeed);
    this.writeField(chunks, KdbxHeaderFieldType.ENCRYPTION_IV, this.model.encryptionIV);
    this.writeField(chunks, KdbxHeaderFieldType.INNER_RANDOM_STREAM_ID, ByteUtils.writeInt32LE(this.model.innerRandomStreamId));

    if (this.model.version >= 4) {
      // 写入KDBX4特有字段
      if (this.model.kdfParameters) {
        const kdfData = this.writeKdfParameters();
        this.writeField(chunks, KdbxHeaderFieldType.KDF_PARAMETERS, kdfData);
      }
    } else {
      // 写入KDBX3.1特有字段
      if (this.model.transformSeed) {
        this.writeField(chunks, KdbxHeaderFieldType.TRANSFORM_SEED, this.model.transformSeed);
      }
      if (this.model.transformRounds !== undefined) {
        this.writeField(chunks, KdbxHeaderFieldType.TRANSFORM_ROUNDS, ByteUtils.writeInt64LE(this.model.transformRounds));
      }
      if (this.model.protectedStreamKey) {
        this.writeField(chunks, KdbxHeaderFieldType.PROTECTED_STREAM_KEY, this.model.protectedStreamKey);
      }
      if (this.model.streamStartBytes) {
        this.writeField(chunks, KdbxHeaderFieldType.STREAM_START_BYTES, this.model.streamStartBytes);
      }
    }

    // 写入公共自定义数据
    if (this.model.publicCustomData) {
      const customData = this.writePublicCustomData();
      this.writeField(chunks, KdbxHeaderFieldType.PUBLIC_CUSTOM_DATA, customData);
    }

    // 写入结束标记
    chunks.push(new Uint8Array([KdbxHeaderFieldType.END]));

    // 合并所有数据块
    return ByteUtils.concat(...chunks);
  }

  /**
   * 写入单个字段
   * @param chunks 数据块数组
   * @param fieldType 字段类型
   * @param fieldData 字段数据
   */
  private writeField(chunks: Binary[], fieldType: number, fieldData: Binary): void {
    chunks.push(new Uint8Array([fieldType]));
    chunks.push(ByteUtils.writeInt16LE(fieldData.length));
    chunks.push(fieldData);
  }

  /**
   * 写入KDF参数
   * @returns KDF参数的二进制数据
   */
  private writeKdfParameters(): Binary {
    const chunks: Binary[] = [];
    const kdf = this.model.kdfParameters;

    if (kdf) {
      if (kdf.uuid) {
        this.writeKdfParameter(chunks, KdfParameterType.UUID, kdf.uuid);
      }
      if (kdf.salt) {
        this.writeKdfParameter(chunks, KdfParameterType.SALT, kdf.salt);
      }
      if (kdf.parallelism !== undefined) {
        this.writeKdfParameter(chunks, KdfParameterType.PARALLELISM, ByteUtils.writeInt32LE(kdf.parallelism));
      }
      if (kdf.memory !== undefined) {
        this.writeKdfParameter(chunks, KdfParameterType.MEMORY, ByteUtils.writeInt64LE(kdf.memory));
      }
      if (kdf.iterations !== undefined) {
        this.writeKdfParameter(chunks, KdfParameterType.ITERATIONS, ByteUtils.writeInt64LE(kdf.iterations));
      }
      if (kdf.version !== undefined) {
        this.writeKdfParameter(chunks, KdfParameterType.VERSION, ByteUtils.writeInt32LE(kdf.version));
      }
    }

    chunks.push(new Uint8Array([KdfParameterType.END]));
    return ByteUtils.concat(...chunks);
  }

  /**
   * 写入单个KDF参数
   * @param chunks 数据块数组
   * @param paramType 参数类型
   * @param paramData 参数数据
   */
  private writeKdfParameter(chunks: Binary[], paramType: number, paramData: Binary): void {
    chunks.push(new Uint8Array([paramType]));
    chunks.push(ByteUtils.writeInt32LE(paramData.length));
    chunks.push(paramData);
  }

  /**
   * 写入公共自定义数据
   * @returns 自定义数据的二进制数据
   */
  public writePublicCustomData(): Binary {
    const chunks: Binary[] = [];

    if (this.model.publicCustomData) {
      this.model.publicCustomData.forEach((value, key) => {
        // 写入键的长度和键的值
        const keyBytes = ByteUtils.stringToBytes(key);
        chunks.push(ByteUtils.writeInt32LE(keyBytes.length));
        chunks.push(keyBytes);

        // 获取值的类型和实际值
        const item = value as VariantDictionaryItem;
        chunks.push(new Uint8Array([item.type]));

        // 根据类型序列化值
        let valueBytes: Binary;
        switch (item.type) {
          case 0x00: // UInt32
          case 0x03: // Int32
            valueBytes = ByteUtils.writeInt32LE(item.value as number);
            break;
          case 0x01: // UInt64
          case 0x04: // Int64
            valueBytes = ByteUtils.writeInt64LE(item.value as number);
            break;
          case 0x02: // Bool
            valueBytes = new Uint8Array([item.value ? 1 : 0]);
            break;
          case 0x05: // String
            valueBytes = ByteUtils.stringToBytes(item.value as string);
            break;
          case 0x06: // ByteArray
            valueBytes = item.value as Binary;
            break;
          default:
            console.error(`Unknown value type: ${item.type}`);
            return;
        }

        // 写入值的长度和值
        chunks.push(ByteUtils.writeInt32LE(valueBytes.length));
        chunks.push(valueBytes);
      });
    }

    return ByteUtils.concat(...chunks);
  }

  /**
   * 获取头部模型
   */
  public getModel(): KdbxHeaderModel {
    return this.model;
  }

  /**
   * 设置头部模型
   * @param model 头部模型
   */
  public setModel(model: KdbxHeaderModel): void {
    this.model = model;
  }
}
