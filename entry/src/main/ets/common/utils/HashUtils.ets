import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'HashUtils';

/**
 * 哈希工具类
 */
export class HashUtils {

  /**
   * 流式文件 SHA256 读取分块大小（4MB，平衡内存与系统调用次数）
   */
  private static readonly FILE_HASH_CHUNK_SIZE: number = 4 * 1024 * 1024;

  /**
   * 计算数据的 SHA256 哈希值（十六进制小写）
   * @param data 待计算的数据
   * @returns 十六进制小写哈希字符串
   */
  public static sha256Hex(data: ArrayBuffer): string {
    // 空 ArrayBuffer：cryptoFramework 不支持空 update，返回已知空 SHA256
    if (data.byteLength === 0) {
      return 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
    }
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    md.updateSync({ data: new Uint8Array(data) });
    const digest: cryptoFramework.DataBlob = md.digestSync();
    return HashUtils.toHexString(digest.data);
  }

  /**
   * 计算数据的 MD5 哈希值（十六进制小写）
   * 仅供百度网盘开放平台协议使用（content-md5 / slice-md5 / 分片 block_list 上报约定），
   * 非安全用途，不用于密码学保护
   * @param data 待计算的数据
   * @returns 十六进制小写哈希字符串
   */
  public static md5Hex(data: ArrayBuffer): string {
    // 空 ArrayBuffer：cryptoFramework 不支持空 update，返回已知空 MD5
    if (data.byteLength === 0) {
      return 'd41d8cd98f00b204e9800998ecf8427e';
    }
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    md.updateSync({ data: new Uint8Array(data) });
    const digest: cryptoFramework.DataBlob = md.digestSync();
    return HashUtils.toHexString(digest.data);
  }

  /**
   * 计算本地文件的 SHA256 哈希值（增量喂入分块，避免整缓冲驻留内存）
   * 与 sha256Hex 结果一致，可用于流式冲突检测替代整缓冲哈希
   * @param filePath 本地文件路径
   * @returns 十六进制小写哈希字符串
   */
  public static async sha256HexFile(filePath: string): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('SHA256');
    let file: fs.File | null = null;
    try {
      file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      const totalSize: number = stat.size;
      const chunkSize: number = HashUtils.FILE_HASH_CHUNK_SIZE;
      const buffer: ArrayBuffer = new ArrayBuffer(chunkSize);
      let remaining: number = totalSize;
      // 空文件：cryptoFramework 不支持空 update，直接返回已知空 SHA256
      if (totalSize === 0) {
        return 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
      }
      while (remaining > 0) {
        const readLen: number = Math.min(chunkSize, remaining);
        const bytesRead = await fs.read(file.fd, buffer, { length: readLen });
        if (bytesRead <= 0) {
          break;
        }
        // 零拷贝视图：updateSync 同步处理，下次循环覆写 buffer 前已完成
        md.updateSync({ data: new Uint8Array(buffer, 0, bytesRead) });
        remaining -= bytesRead;
      }
      const digest: cryptoFramework.DataBlob = md.digestSync();
      return HashUtils.toHexString(digest.data);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'sha256HexFile failed: %{public}s', err.message);
      throw err;
    } finally {
      if (file !== null) {
        try {
          await fs.close(file.fd);
        } catch {
          // ignore
        }
      }
    }
  }

  /**
   * 计算本地文件的 MD5 哈希值（增量喂入分块，避免整缓冲驻留内存）
   * 与 md5Hex 结果一致；仅供百度网盘版本标识（内容 md5）等非安全用途
   * @param filePath 本地文件路径
   * @returns 十六进制小写哈希字符串
   */
  public static async md5HexFile(filePath: string): Promise<string> {
    const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
    let file: fs.File | null = null;
    try {
      file = await fs.open(filePath, fs.OpenMode.READ_ONLY);
      const stat = await fs.stat(file.fd);
      const totalSize: number = stat.size;
      const chunkSize: number = HashUtils.FILE_HASH_CHUNK_SIZE;
      const buffer: ArrayBuffer = new ArrayBuffer(chunkSize);
      let remaining: number = totalSize;
      // 空文件：cryptoFramework 不支持空 update，直接返回已知空 MD5
      if (totalSize === 0) {
        return 'd41d8cd98f00b204e9800998ecf8427e';
      }
      while (remaining > 0) {
        const readLen: number = Math.min(chunkSize, remaining);
        const bytesRead = await fs.read(file.fd, buffer, { length: readLen });
        if (bytesRead <= 0) {
          break;
        }
        // 零拷贝视图：updateSync 同步处理，下次循环覆写 buffer 前已完成
        md.updateSync({ data: new Uint8Array(buffer, 0, bytesRead) });
        remaining -= bytesRead;
      }
      const digest: cryptoFramework.DataBlob = md.digestSync();
      return HashUtils.toHexString(digest.data);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'md5HexFile failed: %{public}s', err.message);
      throw err;
    } finally {
      if (file !== null) {
        try {
          await fs.close(file.fd);
        } catch {
          // ignore
        }
      }
    }
  }

  /**
   * 字节数组转十六进制小写字符串
   * @param bytes 字节数组
   * @returns 十六进制字符串
   */
  private static toHexString(bytes: Uint8Array): string {
    let hex: string = '';
    for (let i = 0; i < bytes.length; i++) {
      const byte: string = bytes[i].toString(16);
      hex += byte.length === 1 ? '0' + byte : byte;
    }
    return hex;
  }
}
