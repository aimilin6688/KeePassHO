import cryptoFramework from '@ohos.security.cryptoFramework';

export class KdbxUtils {
  // 创建随机数生成器
  private static rand: cryptoFramework.Random = cryptoFramework.createRandom();

  /**
   * 生成随机数填充 Uint8Array
   * @param uint8Array
   * @returns
   */
  static generateRandom(uint8Array: Uint8Array): Uint8Array {
    KdbxUtils.fillRandom(uint8Array);
    return uint8Array;
  }

  /**
   * 生成随机数填充 Uint8Array
   * @param uint8Array
   * @returns
   */
  static fillRandom(uint8Array: Uint8Array): void {
    try {
      // 生成随机字节
      const dataBlob: cryptoFramework.DataBlob = KdbxUtils.rand.generateRandomSync(uint8Array.length);

      // 覆盖原始数组内容
      uint8Array.set(dataBlob.data);
      // 打印随机数
      console.log("Random data:", Array.from(uint8Array).map(b => b.toString(16).padStart(2, '0')).join(''));
    } catch (error) {
      console.error("Random generation failed:", error.code, error.message);
    }
  }
}