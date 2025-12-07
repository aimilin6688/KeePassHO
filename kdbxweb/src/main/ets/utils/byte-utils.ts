import util from '@ohos.util';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';

const textEncoder = new util.TextEncoder();
const textDecoder = new util.TextDecoder();
const base64 = new util.Base64Helper();

type ArrayBufferOrArray = ArrayBuffer | Uint8Array;

export function arrayBufferEquals(ab1: ArrayBuffer, ab2: ArrayBuffer): boolean {
  if (ab1.byteLength !== ab2.byteLength) {
    return false;
  }
  const arr1 = new Uint8Array(ab1);
  const arr2 = new Uint8Array(ab2);
  for (let i = 0, len = arr1.length; i < len; i++) {
    if (arr1[i] !== arr2[i]) {
      return false;
    }
  }
  return true;
}

export function bytesToString(arr: ArrayBufferOrArray): string {
  let bytes: Uint8Array = arr instanceof ArrayBuffer ? new Uint8Array(arr) : arr;
  return textDecoder.decodeToString(bytes);
}

export function stringToBytes(str: string): Uint8Array {
  if (str === null || str.length === 0) {
    return new Uint8Array(0);
  }
  return textEncoder.encodeInto(str);
}

export function base64ToBytes(str: string): Uint8Array {
  if (str === null || str.length === 0) {
    return new Uint8Array(0);
  }
  // 如果字符串长度不是4的整数倍，则在字符串末尾追加 =
  if (str.length % 4 !== 0) {
    str += '='.repeat(4 - str.length % 4);
  }
  return base64.decodeSync(str);
}

export function stringToBase64(str: string): string {
  if (str === null || str.length === 0) {
    return '';
  }
  return bytesToString(base64.encodeSync(textEncoder.encodeInto(str)));
}

export function base64ToString(str: string): string {
  if (str === null || str.length === 0) {
    return '';
  }
  // 如果字符串长度不是4的整数倍，则在字符串末尾追加 =
  if (str.length % 4 !== 0) {
    str += '='.repeat(4 - str.length % 4);
  }
  return textDecoder.decodeToString(base64.decodeSync(str));
}


export function bytesToBase64(arr: ArrayBufferOrArray): string {
  const intArr = arr instanceof ArrayBuffer ? new Uint8Array(arr) : arr;
  if (intArr.length === 0) {
    return '';
  }
  return bytesToString(base64.encodeSync(intArr));
}

export function hexToBytes(hex: string): Uint8Array {
  const arr = new Uint8Array(Math.ceil(hex.length / 2));
  for (let i = 0; i < arr.length; i++) {
    arr[i] = parseInt(hex.substr(i * 2, 2), 16);
  }
  return arr;
}

export function bytesToHex(arr: ArrayBufferOrArray): string {
  const intArr = arr instanceof ArrayBuffer ? new Uint8Array(arr) : arr;
  let str = '';
  for (let i = 0; i < intArr.length; i++) {
    const byte = intArr[i].toString(16);
    if (byte.length === 1) {
      str += '0';
    }
    str += byte;
  }
  return str;
}

export function bytesToBuffer(arr: ArrayBufferOrArray): ArrayBuffer {
  return arrayToBuffer(arr);
}

export function bufferToBytes(arr: ArrayBufferOrArray): Uint8Array {
  if (arr instanceof Uint8Array) {
    return arr;
  }
  return new Uint8Array(arr);
}

export function arrayToBuffer(arr: ArrayBufferOrArray): ArrayBuffer {
  if (arr instanceof ArrayBuffer) {
    return arr;
  }
  const ab = arr.buffer;
  if (arr.byteOffset === 0 && arr.byteLength === ab.byteLength) {
    return ab;
  }
  return arr.buffer.slice(arr.byteOffset, arr.byteOffset + arr.byteLength);
}

export function stringToBuffer(str: string): ArrayBuffer {
  return stringToBytes(str).buffer;
}

export function zeroBuffer(arr: ArrayBufferOrArray): void {
  const intArr = arr instanceof ArrayBuffer ? new Uint8Array(arr) : arr;
  intArr.fill(0);
}

export function randomData(length: number): Uint8Array {
  try {
    return cryptoFramework.createRandom().generateRandomSync(length).data;
  } catch (error) {
    const arr = new Uint8Array(length);
    for (let i = 0; i < length; i++) {
      arr[i] = Math.floor(Math.random() * 256);
    }
    return arr;
  }
}