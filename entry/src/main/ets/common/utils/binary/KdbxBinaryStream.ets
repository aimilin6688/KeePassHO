import { BinaryStream, KdbxTimes, KdbxUuid } from 'kdbxweb';
import util from '@ohos.util';

/**
 * Kdbx格式专用的二进制序列化工具类
 */
export class KdbxBinaryStream extends BinaryStream {
  /**
   * 写入UUID
   * @param uuid 要写入的UUID对象
   */
  writeUuid(uuid: KdbxUuid): void {
    this.writeBytes(uuid.bytes);
  }

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
    times.creationTime = this.getDates();
    times.lastModTime = this.getDates();
    times.lastAccessTime = this.getDates();
    times.expiryTime = this.getDates();
    times.expires = this.getUint32(true) !== 0;
    times.usageCount = this.getUint32(true);
    times.locationChanged = this.getDates();
    return times;
  }

  /**
   * 读取日期格式
   * @returns
   */
  private getDates(): Date | undefined {
    const date = this.getUint64(true);
    return date !== 0 ? new Date(date) : undefined;
  }


  /**
   * 写入字符串
   * @param str 要写入的字符串
   */
  private writeString(str: string): void {
    const bytes = new util.TextEncoder().encodeInto(str);
    this.setUint32(bytes.length, true);
    this.writeBytes(bytes);
  }
}