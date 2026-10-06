import { ProtectedValue } from "../crypto/protected-value";

declare module '@xmldom/xmldom' {
  /**
   * The DOM implementation.
   */
  interface Node {
    protectedValue: ProtectedValue | undefined;
  }
}

declare module 'libkdbxweb_zlib.so' {
  /**
   * S5 流式压缩：NDK zlib 流式原语（src/main/cpp/zlib_stream.cpp）。
   * 1MB in / 4MB out 固定窗口，内存占用与文件大小解耦；gzip 单成员模式。
   */
  export interface ZlibStream {
    /** gzip 流式解压；resolve 解压后字节数，失败时输出文件已删除 */
    inflateFile(inPath: string, outPath: string): Promise<number>;
    /** gzip 流式压缩；resolve 压缩后字节数，level 0-9 默认 6 */
    deflateFile(inPath: string, outPath: string, level?: number): Promise<number>;
  }
  const zlibStream: ZlibStream;
  export default zlibStream;
}

export * from '../index';