import util from '@ohos.util';
import { CryptoJS } from '@ohos/crypto-js';

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
    let bytes:Uint8Array = arr instanceof ArrayBuffer ? new Uint8Array(arr) : arr;
    return textDecoder.decodeToString(bytes);
}

export function stringToBytes(str: string): Uint8Array {
    return textEncoder.encodeInto(str);
}

export function base64ToBytes(str: string): Uint8Array {
    return base64.decodeSync(str);
}

export function bytesToBase64(arr: ArrayBufferOrArray): string {
    const intArr = arr instanceof ArrayBuffer ? new Uint8Array(arr) : arr;
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

/**
 * 工具函数：ArrayBuffer 转 CryptoJS WordArray
 * @param buffer 输入的 ArrayBuffer
 * @returns CryptoJS WordArray 对象
 */
export function arrayBufferToWordArray(buffer: ArrayBuffer): CryptoJS.lib.WordArray {
    const u8 = new Uint8Array(buffer);
    const len = u8.length;
    const words: number[] = [];

    for (let i = 0; i < len; i++) {
        words[i >>> 2] |= u8[i] << (24 - (i % 4) * 8);
    }

    return CryptoJS.lib.WordArray.create(words, len);
}

/**
 * 工具函数：CryptoJS WordArray 转 ArrayBuffer
 * @param wordArray 输入的 WordArray
 * @returns ArrayBuffer 对象
 */
export function wordArrayToArrayBuffer(wordArray: CryptoJS.lib.WordArray): ArrayBuffer {
    const words = wordArray.words;
    const sigBytes = wordArray.sigBytes;
    const u8 = new Uint8Array(sigBytes);

    for (let i = 0; i < sigBytes; i++) {
        u8[i] = (words[i >>> 2] >>> (24 - (i % 4) * 8)) & 0xff;
    }

    return u8.buffer;
}