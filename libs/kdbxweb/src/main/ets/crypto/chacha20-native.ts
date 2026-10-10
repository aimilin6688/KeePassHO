import zlibStream from 'libkdbxweb_zlib.so';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'chacha20-native';

let enabled = true;
let availability: boolean | undefined = undefined;

/**
 * ChaCha20 原生模块包装（libkdbxweb_zlib.so 内的 chacha20Xor，见 chacha20.cpp）。
 *
 * 无状态设计：调用方通过 (counter, blockOffset) 精确重建流位置，
 * 支持 xorInPlace 分块流式续解密；data 就地 XOR，不分配内存。
 */
export function nativeChaCha20Available(): boolean {
    if (!enabled) {
        return false;
    }
    if (availability === undefined) {
        try {
            availability = typeof zlibStream.chacha20Xor === 'function';
        } catch (e) {
            availability = false;
        }
        if (!availability) {
            hilog.warn(DOMAIN, TAG, 'native chacha20Xor unavailable, fallback to js');
        }
    }
    return availability;
}

export function chacha20XorNative(
    data: Uint8Array,
    key: Uint8Array,
    nonce: Uint8Array,
    counter: number,
    blockOffset: number
): void {
    zlibStream.chacha20Xor(data, key, nonce, counter, blockOffset);
}

/** 测试用：禁用后新构造的 ChaCha20 实例全部走纯 JS 路径 */
export function setNativeChaCha20Enabled(v: boolean): void {
    enabled = v;
}
