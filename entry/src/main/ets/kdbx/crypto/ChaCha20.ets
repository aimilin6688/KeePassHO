/**
 * ChaCha20流密码实现
 * 基于RFC 8439规范
 */

/**
 * 四分之一轮函数
 * @param state 状态数组
 * @param a 索引a
 * @param b 索引b
 * @param c 索引c
 * @param d 索引d
 */
function quarterRound(state: Uint32Array, a: number, b: number, c: number, d: number): void {
  state[a] += state[b];
  state[d] ^= state[a];
  state[d] = (state[d] << 16) | (state[d] >>> 16);

  state[c] += state[d];
  state[b] ^= state[c];
  state[b] = (state[b] << 12) | (state[b] >>> 20);

  state[a] += state[b];
  state[d] ^= state[a];
  state[d] = (state[d] << 8) | (state[d] >>> 24);

  state[c] += state[d];
  state[b] ^= state[c];
  state[b] = (state[b] << 7) | (state[b] >>> 25);
}

/**
 * ChaCha20加密器
 */
export class ChaCha20 {
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
   * 创建ChaCha20加密器
   * @param key 32字节密钥
   * @param nonce 12字节随机数（可选，默认为0）
   * @param counter 初始计数器值（可选，默认为0）
   */
  constructor(key: Uint8Array, nonce: Uint8Array = new Uint8Array(12), counter: number = 0) {
    if (key.length !== 32) {
      throw new Error('ChaCha20 key must be 32 bytes');
    }
    if (nonce.length !== 12) {
      throw new Error('ChaCha20 nonce must be 12 bytes');
    }

    // 初始化状态
    this.state = new Uint32Array(16);
    this.buffer = new Uint8Array(64);
    this.bufferOffset = 64; // 强制第一次更新

    // 设置常量（"expand 32-byte k"）
    this.state[0] = this.getUint32(ChaCha20.SIGMA, 0);
    this.state[1] = this.getUint32(ChaCha20.SIGMA, 4);
    this.state[2] = this.getUint32(ChaCha20.SIGMA, 8);
    this.state[3] = this.getUint32(ChaCha20.SIGMA, 12);

    // 设置密钥
    for (let i = 0; i < 8; i++) {
      this.state[4 + i] = this.getUint32(key, i * 4);
    }

    // 设置计数器
    this.state[12] = counter;

    // 设置随机数
    this.state[13] = this.getUint32(nonce, 0);
    this.state[14] = this.getUint32(nonce, 4);
    this.state[15] = this.getUint32(nonce, 8);
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
      // 列轮
      quarterRound(working, 0, 4, 8, 12);
      quarterRound(working, 1, 5, 9, 13);
      quarterRound(working, 2, 6, 10, 14);
      quarterRound(working, 3, 7, 11, 15);

      // 对角轮
      quarterRound(working, 0, 5, 10, 15);
      quarterRound(working, 1, 6, 11, 12);
      quarterRound(working, 2, 7, 8, 13);
      quarterRound(working, 3, 4, 9, 14);
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
    this.state[12]++;
    if (this.state[12] === 0) {
      // 处理计数器溢出
      this.state[13]++;
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