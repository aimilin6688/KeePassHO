import kdbxNative from 'libkdbxweb_native.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'salsa20-native';

let enabled = true;
let availability: boolean | undefined = undefined;

/**
 * Salsa20 原生模块包装（libkdbxweb_native.so 内的 salsa20Xor，见 salsa20.cpp）。
 *
 * 无状态设计：调用方通过 (counter, blockOffset) 精确重建流位置，
 * 支持分块流式续解密；data 就地 XOR，不分配内存。
 * counter 为 64 位块计数器（低 32 位进位语义与 TS incrementCounter 一致）。
 */
export function nativeSalsa20Available(): boolean {
    if (!enabled) {
        return false;
    }
    if (availability === undefined) {
        try {
            availability = typeof kdbxNative.salsa20Xor === 'function';
        } catch (e) {
            availability = false;
        }
        if (!availability) {
            hilog.warn(DOMAIN, TAG, 'native salsa20Xor unavailable, fallback to js');
        }
    }
    return availability;
}

export function salsa20XorNative(
    data: Uint8Array,
    key: Uint8Array,
    nonce: Uint8Array,
    counter: number,
    blockOffset: number
): void {
    kdbxNative.salsa20Xor(data, key, nonce, counter, blockOffset);
}

/** 测试用：禁用后新构造的 Salsa20 实例全部走纯 JS 路径 */
export function setNativeSalsa20Enabled(v: boolean): void {
    enabled = v;
}
