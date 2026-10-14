import { ProtectedValue } from "../crypto/protected-value";

declare module '@xmldom/xmldom' {
  /**
   * The DOM implementation.
   */
  interface Node {
    protectedValue: ProtectedValue | undefined;
  }
}

declare module 'libkdbxweb_native.so' {
  /**
   * kdbxweb 原生支持库（src/main/cpp/，经 native_entry.cpp 统一注册）。
   */
  export interface KdbxNativeModule {
    /**
     * S5 流式压缩：NDK zlib 流式原语（zlib_stream.cpp）。
     * 1MB in / 4MB out 固定窗口，内存占用与文件大小解耦；gzip 单成员模式。
     */
    /** gzip 流式解压；resolve 解压后字节数，失败时输出文件已删除 */
    inflateFile(inPath: string, outPath: string): Promise<number>;
    /** gzip 流式压缩；resolve 压缩后字节数，level 0-9 默认 6 */
    deflateFile(inPath: string, outPath: string, level?: number): Promise<number>;
    /**
     * ChaCha20 就地 XOR 密钥流（chacha20.cpp），
     * 语义与 crypto/chacha20.ts 的 xorInPlace 一致：
     * data 支持 Uint8Array view；counter 为起始块计数器；
     * blockOffset 为首块内已消耗偏移 0..63（流式跨调用续解密）。
     */
    chacha20Xor(data: Uint8Array, key: Uint8Array, nonce: Uint8Array, counter: number, blockOffset: number): void;
    /**
     * Salsa20 就地 XOR 密钥流（salsa20.cpp），
     * 语义与 crypto/salsa20.ts 的 getBytes 一致：
     * key 32 字节、nonce 8 字节（支持 view）；counter 为 64 位块计数器
     * （低 32 位对应块计数低字，进位进入高 32 位）；
     * blockOffset 为首块内已消耗偏移 0..63（流式跨调用续解密）。
     */
    salsa20Xor(data: Uint8Array, key: Uint8Array, nonce: Uint8Array, counter: number, blockOffset: number): void;
  }
  const kdbxNative: KdbxNativeModule;
  export default kdbxNative;
}

export * from '../index';