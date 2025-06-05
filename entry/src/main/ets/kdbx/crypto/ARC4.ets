import { KdbxUtils } from '../utils/KdbxUtils';

/**
 * ARC4变体加密算法实现
 * 包含额外的安全增强措施
 */
export class ARC4 {
  private S: Uint8Array;
  private i: number;
  private j: number;
  private dropN: number;

  /**
   * 初始化ARC4实例
   * @param key 加密密钥
   * @param dropN 丢弃的初始字节数（默认为3072以增加安全性）
   */
  constructor(key: Uint8Array, dropN: number = 3072) {
    if (!key || key.length < 1) {
      throw new Error('key must be provided and must be at least one byte long');
    }
    if (key.length > 256) {
      throw new Error('key must be 256 bytes or less');
    }

    this.S = new Uint8Array(256);
    this.i = 0;
    this.j = 0;
    this.dropN = dropN;

    // 初始化状态数组
    for (let i = 0; i < 256; i++) {
      this.S[i] = i;
    }

    // 密钥调度算法（KSA）
    let j = 0;
    for (let i = 0; i < 256; i++) {
      j = (j + this.S[i] + key[i % key.length]) & 0xff;
      // 交换S[i]和S[j]
      const temp = this.S[i];
      this.S[i] = this.S[j];
      this.S[j] = temp;
    }

    // 丢弃初始字节流以增加安全性
    this.drop(this.dropN);
  }

  /**
   * 丢弃指定数量的字节以增加安全性
   * @param n 要丢弃的字节数
   */
  private drop(n: number): void {
    for (let i = 0; i < n; i++) {
      this.i = (this.i + 1) & 0xff;
      this.j = (this.j + this.S[this.i]) & 0xff;
      // 交换S[this.i]和S[this.j]
      const temp = this.S[this.i];
      this.S[this.i] = this.S[this.j];
      this.S[this.j] = temp;
    }
  }

  /**
   * 加密/解密数据
   * @param data 要处理的数据
   * @param output 输出缓冲区（如果未提供则创建新的）
   * @returns 处理后的数据
   */
  process(data: Uint8Array, output: Uint8Array): Uint8Array {
    if (!output) {
      output = new Uint8Array(data.length);
    }

    if (output.length < data.length) {
      throw new Error('Output buffer too small');
    }

    let i = this.i;
    let j = this.j;
    const S = this.S;

    // 主加密循环
    for (let k = 0; k < data.length; k++) {
      i = (i + 1) & 0xff;
      j = (j + S[i]) & 0xff;
      // 交换S[i]和S[j]
      const temp = S[i];
      S[i] = S[j];
      S[j] = temp;
      const t = (S[i] + S[j]) & 0xff;
      output[k] = data[k] ^ S[t];
    }

    this.i = i;
    this.j = j;

    return output;
  }

  /**
   * 重置加密状态
   * @param key 新的加密密钥（可选）
   */
  reset(key?: Uint8Array): void {
    if (key) {
      // 如果提供了新密钥，重新初始化
      this.S = new Uint8Array(256);
      this.i = 0;
      this.j = 0;

      // 初始化状态数组
      for (let i = 0; i < 256; i++) {
        this.S[i] = i;
      }

      // 密钥调度算法（KSA）
      let j = 0;
      for (let i = 0; i < 256; i++) {
        j = (j + this.S[i] + key[i % key.length]) & 0xff;
        // 交换S[i]和S[j]
        const temp = this.S[i];
        this.S[i] = this.S[j];
        this.S[j] = temp;
      }

      // 丢弃初始字节流以增加安全性
      this.drop(this.dropN);
    } else {
      // 否则仅重置计数器
      this.i = 0;
      this.j = 0;
    }
  }

  /**
   * 清理内存中的敏感数据
   */
  clear(): void {
    // 使用随机数据覆盖状态数组
    KdbxUtils.fillRandom(this.S);
    // 然后用零覆盖
    this.S.fill(0);
    this.i = 0;
    this.j = 0;
  }
}
