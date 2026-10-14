import kdbxNative from 'libkdbxweb_native.so';
import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * S5 流式压缩（设计文档 §5）：NDK zlib 原生模块包装。
 *
 * `@ohos/flate2` 为整缓冲 Rust 绑定、`@ohos/zlib` 仅 zip 归档，均无法流式
 * 处理 KDBX 的单成员 gzip 载荷；此处走 sysroot zlib 的 inflate/deflate 流式
 * 原语，内存窗口固定 1MB in / 4MB out，与文件大小解耦。
 */

/** gzip 流式解压文件；resolve 解压后字节数 */
export function inflateFile(inPath: string, outPath: string): Promise<number> {
    return kdbxNative.inflateFile(inPath, outPath);
}

/** gzip 流式压缩文件；resolve 压缩后字节数 */
export function deflateFile(inPath: string, outPath: string, level?: number): Promise<number> {
    return kdbxNative.deflateFile(inPath, outPath, level);
}

/**
 * 读取 gzip 文件尾部 ISIZE（小端 u32，解压后大小 mod 2^32），
 * 用于 CP2' 解压前预判（设计文档 §9）：超大文本库在 inflate 之前即拒绝，
 * 避免解压本身的磁盘/时间浪费。读取失败返回 undefined（fail-open）。
 */
export function readGzipIsize(path: string): Promise<number | undefined> {
    const TAIL = 8; // CRC32(4) + ISIZE(4)
    return fs.open(path, fs.OpenMode.READ_ONLY).then((file) => {
        return fs.stat(file.fd).then((stat) => {
            if (stat.size < TAIL) {
                return undefined;
            }
            const buf = new ArrayBuffer(TAIL);
            return fs.read(file.fd, buf, { offset: stat.size - TAIL }).then((read) => {
                if (read !== TAIL) {
                    return undefined;
                }
                return new DataView(buf).getUint32(4, true);
            });
        }).then((isize) => {
            return fs.close(file.fd).then(() => isize, () => isize);
        });
    }).catch(() => undefined);
}
