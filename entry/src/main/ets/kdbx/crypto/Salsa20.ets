/**
 * Salsa20流密码实现
 * 基于Daniel J. Bernstein的规范
 */

/**
 * 四分之一轮函数
 * @param state 状态数组
 * @param y0 索引y0
 * @param y1 索引y1
 * @param y2 索引y2
 * @param y3 索引y3
 */
function quarterRound(state: Uint32Array, y0: number, y1: number, y2: number, y3: number): void {
  // Salsa20的四分之一轮函数与ChaCha20略有不同
  let t = state[y3] += state[y0];
  state[y1] = (state[y1] ^ ((t << 7) | (t >>> 25)));

  t = state[y0] += state[y1];
  state[y2] = (state[y2] ^ ((t << 9) | (t >>> 23)));

  t = state[y1] += state[y2];
  state[y3] = (state[y3] ^ ((t << 13) | (t >>> 19)));

  t = state[y2] += state[y3];
  state[y0] = (state[y0] ^ ((t << 18) | (t >>> 14)));
}

/**
 * Salsa20加密器
 */
export class Salsa20 {
  private static readonly SIGMA = new Uint8Array([
    0x65, 0x78, 0x70, 0x61, // "expa"
    0x6e, 0x64, 0x20, 0x33, // "nd 3"
    0x32, 0x2d, 0x62, 0x79, // "2-by"
    0x74, 0x65, 0x20, 0x6b  // "te k"
  ]);

  private readonly state: Uint32Array;
  private readonly buffer: Uint8Array;
  private bufferOffset: number;

  /**
   * 创建Salsa20加密器
   * @param key 32字节密钥
   * @param nonce 8字节随机数（可选，默认为0）
   * @param counter 初始计数器值（可选，默认为0）
   */
  constructor(key: Uint8Array, nonce: Uint8Array = new Uint8Array(8), counter: number = 0) {
    if (key.length !== 32) {
      throw new Error('Salsa20 key must be 32 bytes');
    }
    if (nonce.length !== 8) {
      throw new Error('Salsa20 nonce must be 8 bytes');
    }

    // 初始化状态
    this.state = new Uint32Array(16);
    this.buffer = new Uint8Array(64);
    this.bufferOffset = 64; // 强制第一次更新

    // 设置常量（"expand 32-byte k"）
    this.state[0] = this.getUint32(Salsa20.SIGMA, 0);
    this.state[5] = this.getUint32(Salsa20.SIGMA, 4);
    this.state[10] = this.getUint32(Salsa20.SIGMA, 8);
    this.state[15] = this.getUint32(Salsa20.SIGMA, 12);

    // 设置密钥（Salsa20的密钥布局与ChaCha20不同）
    this.state[1] = this.getUint32(key, 0);
    this.state[2] = this.getUint32(key, 4);
    this.state[3] = this.getUint32(key, 8);
    this.state[4] = this.getUint32(key, 12);
    this.state[11] = this.getUint32(key, 16);
    this.state[12] = this.getUint32(key, 20);
    this.state[13] = this.getUint32(key, 24);
    this.state[14] = this.getUint32(key, 28);

    // 设置随机数和计数器
    this.state[6] = counter & 0xffffffff;
    this.state[7] = counter >>> 32;
    this.state[8] = this.getUint32(nonce, 0);
    this.state[9] = this.getUint32(nonce, 4);
  }

  /**
   * 加密/解密数据
   * @param data 输入数据
   * @returns 加密/解密后的数据
   */
  process(data: Uint8Array): Uint8Array {
    const output = new Uint8Array(data.length);
    let offset = 0;

    while (offset < data.length) {
      // 如果需要新的密钥流，生成它
      if (this.bufferOffset === 64) {
        this.generateKeyStream();
        this.bufferOffset = 0;
      }

      // 计算这一轮可以处理的字节数
      const count = Math.min(data.length - offset, 64 - this.bufferOffset);

      // 对数据进行异或操作
      for (let i = 0; i < count; i++) {
        output[offset + i] = data[offset + i] ^ this.buffer[this.bufferOffset + i];
      }

      offset += count;
      this.bufferOffset += count;
    }

    return output;
  }

  /**
   * 生成新的密钥流
   */
  private generateKeyStream(): void {
    // 复制状态
    const working = new Uint32Array(16);
    working.set(this.state);

    // 应用20轮（10次双轮）
    for (let i = 0; i < 10; i++) {
      // 行轮
      quarterRound(working, 0, 1, 2, 3);
      quarterRound(working, 5, 6, 7, 4);
      quarterRound(working, 10, 11, 8, 9);
      quarterRound(working, 15, 12, 13, 14);

      // 列轮
      quarterRound(working, 0, 4, 8, 12);
      quarterRound(working, 5, 9, 13, 1);
      quarterRound(working, 10, 14, 2, 6);
      quarterRound(working, 15, 3, 7, 11);
    }

    // 将结果添加到初始状态
    for (let i = 0; i < 16; i++) {
      working[i] += this.state[i];
    }

    // 转换为字节数组
    for (let i = 0; i < 16; i++) {
      this.putUint32(this.buffer, working[i], i * 4);
    }

    // 增加计数器
    this.state[6]++;
    if (this.state[6] === 0) {
      // 处理计数器溢出
      this.state[7]++;
    }
  }

  /**
   * 从字节数组中读取32位整数（小端序）
   */
  private getUint32(data: Uint8Array, offset: number): number {
    return (
      data[offset] |
      (data[offset + 1] << 8) |
      (data[offset + 2] << 16) |
      (data[offset + 3] << 24)
    );
  }

  /**
   * 将32位整数写入字节数组（小端序）
   */
  private putUint32(data: Uint8Array, value: number, offset: number): void {
    data[offset] = value & 0xff;
    data[offset + 1] = (value >>> 8) & 0xff;
    data[offset + 2] = (value >>> 16) & 0xff;
    data[offset + 3] = (value >>> 24) & 0xff;
  }
}
