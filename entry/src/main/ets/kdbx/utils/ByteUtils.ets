/**
 * KdbxUtils.ets
 *
 * KDBX文件处理的工具函数
 */

import { Binary } from '../models/KdbxTypes';
import util from '@ohos.util';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

/**
 * 连接两个或多个字节数组
 * @param arrays 要连接的字节数组
 * @returns 连接后的新字节数组
 */
const rand: cryptoFramework.Random = cryptoFramework.createRandom();


export function concatBytes(...arrays: Binary[]): Binary {
  // 计算总长度
  let totalLength = 0;
  for (const arr of arrays) {
    totalLength += arr.length;
  }

  // 创建新数组
  const result = new Uint8Array(totalLength);

  // 复制数据
  let offset = 0;
  for (const arr of arrays) {
    result.set(arr, offset);
    offset += arr.length;
  }

  return result;
}

/**
 * 将字符串转换为UTF-8编码的字节数组
 * @param str 输入字符串
 * @returns UTF-8编码的字节数组
 */
export function stringToBytes(str: string): Binary {
  const encoder = new util.TextEncoder();
  return encoder.encodeInto(str);
}

/**
 * 将UTF-8编码的字节数组转换为字符串
 * @param bytes UTF-8编码的字节数组
 * @returns 解码后的字符串
 */
export function bytesToString(bytes: Binary): string {
  const decoder = new util.TextDecoder();
  return decoder.decodeToString(bytes);
}

/**
 * 比较两个字节数组是否相等
 * @param a 第一个字节数组
 * @param b 第二个字节数组
 * @returns 如果两个数组内容相同则返回true，否则返回false
 */
export function bytesEqual(a: Binary, b: Binary): boolean {
  if (a.length !== b.length) {
    return false;
  }

  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }

  return true;
}

/**
 * 将十六进制字符串转换为字节数组
 * @param hex 十六进制字符串
 * @returns 字节数组
 */
export function hexToBytes(hex: string): Binary {
  if (hex.length % 2 !== 0) {
    throw new Error('十六进制字符串长度必须为偶数');
  }

  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }

  return bytes;
}

/**
 * 将字节数组转换为十六进制字符串
 * @param bytes 字节数组
 * @returns 十六进制字符串
 */
export function bytesToHex(bytes: Binary): string {
  return Array.from(bytes)
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

/**
 * 比较两个ArrayBuffer是否相等
 * @param a 第一个ArrayBuffer
 * @param b 第二个ArrayBuffer
 * @returns 如果两个ArrayBuffer内容相同则返回true，否则返回false
 */
export function arrayBufferEquals(a: ArrayBuffer, b: ArrayBuffer): boolean {
  if (a === b) {
    return true;
  }

  if (a.byteLength !== b.byteLength) {
    return false;
  }

  const viewA = new Uint8Array(a);
  const viewB = new Uint8Array(b);

  for (let i = 0; i < viewA.length; i++) {
    if (viewA[i] !== viewB[i]) {
      return false;
    }
  }

  return true;
}

/**
 * 将Base64字符串转换为字节数组
 * @param base64 Base64字符串
 * @returns 字节数组
 */
export function base64ToBytes(base64: string): Binary {
  let base64Helper = new util.Base64Helper();
  return base64Helper.decodeSync(base64);
}

/**
 * 将字节数组转换为Base64字符串
 * @param bytes 字节数组
 * @returns Base64字符串
 */
export function bytesToBase64(bytes: Binary): string {
  let base64Helper = new util.Base64Helper();
  return base64Helper.encodeToStringSync(bytes);
}

/**
 * 将字节数组转换为32位无符号整数
 * @param bytes 字节数组（小端序）
 * @param offset 起始偏移量，默认为0
 * @returns 32位无符号整数
 */
export function bytesToUint32(bytes: Binary, offset: number = 0): number {
  return (bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24)) >>> 0;
}

/**
 * 将32位无符号整数转换为字节数组（小端序）
 * @param value 32位无符号整数
 * @returns 字节数组
 */
export function uint32ToBytes(value: number): Binary {
  const bytes = new Uint8Array(4);
  bytes[0] = value & 0xFF;
  bytes[1] = (value >> 8) & 0xFF;
  bytes[2] = (value >> 16) & 0xFF;
  bytes[3] = (value >> 24) & 0xFF;
  return bytes;
}

/**
 * 将字节数组转换为64位无符号整数
 * @param bytes 字节数组（小端序）
 * @param offset 起始偏移量，默认为0
 * @returns 64位无符号整数的字符串表示（因为JavaScript不能准确表示64位整数）
 */
export function bytesToUint64(bytes: Binary, offset: number = 0): string {
  const low = bytesToUint32(bytes, offset);
  const high = bytesToUint32(bytes, offset + 4);
  // 使用字符串表示64位整数，避免精度损失
  return (BigInt(high) * BigInt(0x100000000) + BigInt(low)).toString();
}

/**
 * 将64位无符号整数转换为字节数组（小端序）
 * @param value 64位无符号整数的字符串表示或BigInt
 * @returns 字节数组
 */
export function uint64ToBytes(value: string | bigint): Binary {
  const bigIntValue = typeof value === 'string' ? BigInt(value) : value;
  const bytes = new Uint8Array(8);

  const low = Number(bigIntValue & BigInt(0xFFFFFFFF));
  const high = Number((bigIntValue >> BigInt(32)) & BigInt(0xFFFFFFFF));

  const lowBytes = uint32ToBytes(low);
  const highBytes = uint32ToBytes(high);

  bytes.set(lowBytes, 0);
  bytes.set(highBytes, 4);

  return bytes;
}

/**
 * 生成指定长度的随机字节数组
 * @param length 字节数组长度
 * @returns 随机字节数组
 */
export function randomBytes(length: number): Binary {
  const uint8Array: Uint8Array = new Uint8Array(length);
  const dataBlob: cryptoFramework.DataBlob = rand.generateRandomSync(length);
  uint8Array.set(dataBlob.data);
  return uint8Array;
}

/**
 * 将缓冲区填充为零
 * @param buffer 要填充的缓冲区
 */
export function zeroBuffer(buffer: Binary): void {
  for (let i = 0; i < buffer.length; i++) {
    buffer[i] = 0;
  }
}
