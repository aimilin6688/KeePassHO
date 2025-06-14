import util from '@ohos.util';

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
