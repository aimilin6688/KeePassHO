import {
  BinaryStream,
  ByteUtils,
  KdbxBinary,
  KdbxBinaryWithHash,
  KdbxContext,
  KdbxCustomDataItem,
  KdbxCustomDataMap,
  KdbxHeader,
  KdbxTimes,
  KdbxUuid,
  ProtectedValue,
  VarDictionary
} from 'kdbxweb';
import util from '@ohos.util';

/**
 * Kdbx格式专用的二进制序列化工具类
 */
export class KdbxBinaryStream extends BinaryStream {
  /**
   * 写入时间信息
   * @param times 要写入的时间对象
   */
  writeTimes(times: KdbxTimes): void {
    this.setUint64(times.creationTime?.getTime() ?? 0, true);
    this.setUint64(times.lastModTime?.getTime() ?? 0, true);
    this.setUint64(times.lastAccessTime?.getTime() ?? 0, true);
    this.setUint64(times.expiryTime?.getTime() ?? 0, true);
    this.setUint32(times.expires ? 1 : 0, true);
    this.setUint32(times.usageCount, true);
    this.setUint64(times.locationChanged?.getTime() ?? 0, true);
  }

  /**
   * 读取时间信息
   * @returns 读取到的时间对象
   */
  readTimes(): KdbxTimes {
    const times = new KdbxTimes();
    times.creationTime = this.readDate();
    times.lastModTime = this.readDate();
    times.lastAccessTime = this.readDate();
    times.expiryTime = this.readDate();
    times.expires = this.getUint32(true) !== 0;
    times.usageCount = this.getUint32(true);
    times.locationChanged = this.readDate();
    return times;
  }

  /**
   * 读取日期格式
   * @returns
   */
  writeDate(date: Date | undefined): void {
    this.setUint64(date?.getTime() ?? 0, true);
  }

  /**
   * 读取日期格式
   * @returns
   */
  readDate(): Date | undefined {
    const date = this.getUint64(true);
    return date !== 0 ? new Date(date) : undefined;
  }


  /**
   * 写入UUID
   * @param uuid 要写入的UUID对象
   */
  writeUuid(uuid: KdbxUuid): void {
    this.writeBytes(uuid.bytes);
  }

  /**
   * 读取UUID
   * @returns 读取到的UUID对象
   */
  readUuid(): KdbxUuid {
    const bytes = this.readBytes(16);
    return new KdbxUuid(bytes);
  }

  /**
   * 读取字符串
   * @returns 读取到的字符串
   */
  readString(): string {
    const length = this.getUint32(true);
    const bytes = this.readBytes(length);
    return new util.TextDecoder().decodeToString(new Uint8Array(bytes));
  }

  /**
   * 写入字符串
   * @param str 要写入的字符串
   */
  writeString(str: string): void {
    const bytes = new util.TextEncoder().encodeInto(str);
    this.setUint32(bytes.length, true);
    this.writeBytes(bytes);
  }

  /**
   * 写入VarDictionary
   * @param dict 要写入的VarDictionary对象
   */
  writeVarDictionary(dict: VarDictionary): void {
    dict.write(this);
  }

  /**
   * 读取VarDictionary
   * @returns 读取到的VarDictionary对象
   */
  readVarDictionary(): VarDictionary {
    return VarDictionary.read(this);
  }

  /**
   * 写入KdbxHeader
   * @param header
   */
  writeHeader(header: KdbxHeader) {
    header.write(this);
  }

  /**
   * 读取KdbxHeader
   * @param ctx
   * @returns
   */
  readHeader(ctx: KdbxContext): KdbxHeader {
    return KdbxHeader.read(this, ctx);
  }

  writeStrings(strings: string[]): void {
    this.setUint32(strings.length, true);
    for (const str of strings) {
      this.writeString(str);
    }
  }

  readStrings(): string[] {
    const count = this.getUint32(true);
    const strings: string[] = [];
    for (let i = 0; i < count; i++) {
      strings.push(this.readString());
    }
    return strings;
  }

  writeProtectedValue(value: ProtectedValue): void {
    const bytes = value.getBinary();
    this.setUint32(bytes.length, true);
    this.writeBytes(bytes);
  }

  readProtectedValue(): ProtectedValue {
    const length = this.getUint32(true);
    const bytes = this.readBytes(length);
    return ProtectedValue.fromBinary(bytes);
  }

  writeBinaries(binaries: Map<string, KdbxBinary | KdbxBinaryWithHash>) {
    this.setUint32(binaries.size, true);
    for (const binary of binaries) {
      const key = binary[0];
      const value = binary[1];
      this.writeString(key);
      if (value instanceof ProtectedValue || value instanceof ArrayBuffer) {
        this.writeBinary(value);
      } else if (value.hash) {
        this.setUint8(2); // 标记为带哈希的引用
        this.writeString(value.hash);
        this.writeBinary(value.value);
      }
    }
  }

  readBinaries(): Map<string, KdbxBinary | KdbxBinaryWithHash> {
    const count = this.getUint32(true);
    const binaries = new Map<string, KdbxBinary | KdbxBinaryWithHash>();
    for (let i = 0; i < count; i++) {
      const key = this.readString();
      const binaryType = this.getUint8();
      if (binaryType === 0 || binaryType === 1) {
        binaries.set(key, this.readBinary());
      } else if (binaryType === 2) {
        const hash = this.readString();
        const value = this.readBinary();
        binaries.set(key, { 'hash': hash, 'value': value } as KdbxBinaryWithHash);
      }
    }
    return binaries;
  }

  writeBinary(value: KdbxBinary) {
    if (value instanceof ProtectedValue) {
      this.setUint8(0); // 标记为直接值
      this.writeProtectedValue(value);
    } else if (value instanceof ArrayBuffer) {
      this.setUint8(1); // 标记为直接值
      this.setUint32(value.byteLength, true);
      this.writeBytes(value);
    }
  }

  readBinary(): KdbxBinary {
    const binaryType = this.getUint8();
    if (binaryType === 0) {
      return this.readProtectedValue();
    } else {
      const length = this.getUint32(true);
      return ByteUtils.bytesToBuffer(this.readBytes(length));
    }
  }


  writeCustomData(customData: KdbxCustomDataMap | undefined): void {
    if (!customData) {
      this.setUint32(0, true);
      return;
    }

    this.setUint32(Object.keys(customData).length, true);
    for (const entry of customData) {
      const key = entry[0];
      const value = entry[1] as KdbxCustomDataItem;
      this.writeString(key);
      this.setUint8(value.value ? 1 : 0); // 标记为带哈希的引用
      if (value.value) {
        this.writeString(value.value);
        this.writeDate(value.lastModified);
      }
    }
  }

  readCustomData(): KdbxCustomDataMap | undefined {
    const count = this.getUint32(true);
    if (count === 0) {
      return undefined;
    }

    const customData: KdbxCustomDataMap = new Map<string, KdbxCustomDataItem>();
    for (let i = 0; i < count; i++) {
      const key = this.readString();
      const exists = this.getUint8();
      if (exists) {
        customData[key] = { 'value': this.readString(), 'lastModified': this.readDate() };
      }
    }
    return customData;
  }
}