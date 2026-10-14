/**
 * 测试用 PNG 图片程序化生成器（仅存在于 ohosTest，不进入主应用）。
 *
 * 生成最小合法 PNG：8 字节签名 + IHDR + IDAT + IEND，
 * 颜色类型 RGB（colorType=2）、位深 8、无隔行。
 * IDAT 内 zlib 流使用 stored（不压缩）deflate 块：单块最大 65535 字节，
 * 超出自动分块，仅末块置 BFINAL；流尾附加 Adler-32（大端）。
 * 每个 chunk 的 CRC32（表驱动）覆盖 type + data。
 */

export class TestPngBuilder {
  private static crcTable: number[] | null = null;

  private static buildCrcTable(): number[] {
    const table: number[] = [];
    for (let n = 0; n < 256; n++) {
      let c = n;
      for (let k = 0; k < 8; k++) {
        if ((c & 1) !== 0) {
          c = 0xEDB88320 ^ (c >>> 1);
        } else {
          c = c >>> 1;
        }
      }
      table.push(c);
    }
    return table;
  }

  private static ensureCrcTable(): number[] {
    let table = TestPngBuilder.crcTable;
    if (table === null) {
      table = TestPngBuilder.buildCrcTable();
      TestPngBuilder.crcTable = table;
    }
    return table;
  }

  private static crc32(bytes: Uint8Array): number {
    const table = TestPngBuilder.ensureCrcTable();
    let crc = 0xFFFFFFFF;
    for (let i = 0; i < bytes.length; i++) {
      crc = table[(crc ^ bytes[i]) & 0xFF] ^ (crc >>> 8);
    }
    return (crc ^ 0xFFFFFFFF) >>> 0;
  }

  private static adler32(bytes: Uint8Array): number {
    let a = 1;
    let b = 0;
    for (let i = 0; i < bytes.length; i++) {
      a = (a + bytes[i]) % 65521;
      b = (b + a) % 65521;
    }
    return (((b << 16) | a) >>> 0);
  }

  /** 构造 zlib 流：header 0x78 0x01 + stored deflate 块（≤65535/块，仅末块 BFINAL）+ Adler-32 */
  private static buildZlibStoredStream(raw: Uint8Array): Uint8Array {
    const maxBlock = 65535;
    let blockCount = Math.ceil(raw.length / maxBlock);
    if (blockCount === 0) {
      blockCount = 1;
    }
    const out = new Uint8Array(2 + blockCount * 5 + raw.length + 4);
    let pos = 0;
    out[pos++] = 0x78;
    out[pos++] = 0x01;
    let offset = 0;
    while (true) {
      const remaining = raw.length - offset;
      const chunkLength = remaining > maxBlock ? maxBlock : remaining;
      const isLast = offset + chunkLength >= raw.length;
      out[pos++] = isLast ? 1 : 0;
      out[pos++] = chunkLength & 0xFF;
      out[pos++] = (chunkLength >>> 8) & 0xFF;
      const nlen = (~chunkLength) & 0xFFFF;
      out[pos++] = nlen & 0xFF;
      out[pos++] = (nlen >>> 8) & 0xFF;
      for (let i = 0; i < chunkLength; i++) {
        out[pos++] = raw[offset + i];
      }
      offset += chunkLength;
      if (isLast) {
        break;
      }
    }
    const adler = TestPngBuilder.adler32(raw);
    out[pos++] = (adler >>> 24) & 0xFF;
    out[pos++] = (adler >>> 16) & 0xFF;
    out[pos++] = (adler >>> 8) & 0xFF;
    out[pos++] = adler & 0xFF;
    return out;
  }

  /** 追加 PNG chunk：length(BE) + type + data + CRC32(type+data)(BE) */
  private static appendChunk(bytes: number[], type: string, data: Uint8Array): void {
    bytes.push((data.length >>> 24) & 0xFF);
    bytes.push((data.length >>> 16) & 0xFF);
    bytes.push((data.length >>> 8) & 0xFF);
    bytes.push(data.length & 0xFF);
    const typeAndData = new Uint8Array(4 + data.length);
    for (let i = 0; i < 4; i++) {
      typeAndData[i] = type.charCodeAt(i);
    }
    for (let i = 0; i < data.length; i++) {
      typeAndData[4 + i] = data[i];
    }
    for (let i = 0; i < typeAndData.length; i++) {
      bytes.push(typeAndData[i]);
    }
    const crc = TestPngBuilder.crc32(typeAndData);
    bytes.push((crc >>> 24) & 0xFF);
    bytes.push((crc >>> 16) & 0xFF);
    bytes.push((crc >>> 8) & 0xFF);
    bytes.push(crc & 0xFF);
  }

  private static buildPng(width: number, height: number, rawPixels: Uint8Array): ArrayBuffer {
    const bytes: number[] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    const ihdr = new Uint8Array(13);
    ihdr[0] = (width >>> 24) & 0xFF;
    ihdr[1] = (width >>> 16) & 0xFF;
    ihdr[2] = (width >>> 8) & 0xFF;
    ihdr[3] = width & 0xFF;
    ihdr[4] = (height >>> 24) & 0xFF;
    ihdr[5] = (height >>> 16) & 0xFF;
    ihdr[6] = (height >>> 8) & 0xFF;
    ihdr[7] = height & 0xFF;
    ihdr[8] = 8;
    ihdr[9] = 2;
    ihdr[10] = 0;
    ihdr[11] = 0;
    ihdr[12] = 0;
    TestPngBuilder.appendChunk(bytes, 'IHDR', ihdr);
    TestPngBuilder.appendChunk(bytes, 'IDAT', TestPngBuilder.buildZlibStoredStream(rawPixels));
    TestPngBuilder.appendChunk(bytes, 'IEND', new Uint8Array(0));
    const out = new Uint8Array(bytes.length);
    for (let i = 0; i < bytes.length; i++) {
      out[i] = bytes[i];
    }
    return out.buffer;
  }

  /** 生成纯色 RGB PNG */
  public static buildSolidPng(width: number, height: number, r: number, g: number, b: number): ArrayBuffer {
    const raw = new Uint8Array(height * (1 + width * 3));
    let pos = 0;
    for (let y = 0; y < height; y++) {
      raw[pos++] = 0;
      for (let x = 0; x < width; x++) {
        raw[pos++] = r;
        raw[pos++] = g;
        raw[pos++] = b;
      }
    }
    return TestPngBuilder.buildPng(width, height, raw);
  }

  /** 生成红绿渐变 PNG（R 随 x、G 随 y 变化，肉眼可辨识） */
  public static buildGradientPng(width: number, height: number): ArrayBuffer {
    const raw = new Uint8Array(height * (1 + width * 3));
    const maxX = width > 1 ? width - 1 : 1;
    const maxY = height > 1 ? height - 1 : 1;
    let pos = 0;
    for (let y = 0; y < height; y++) {
      raw[pos++] = 0;
      for (let x = 0; x < width; x++) {
        raw[pos++] = Math.round(255 * x / maxX);
        raw[pos++] = Math.round(255 * y / maxY);
        raw[pos++] = 160;
      }
    }
    return TestPngBuilder.buildPng(width, height, raw);
  }
}
