import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';

/**
 * 测试夹具：读取 entry_test 模块 rawfile 中的真实 KDBX 数据库文件。
 *
 * unit-test.kdbx 是一个真实的 KeePass 数据库文件（KDBX4、AES-KDF），
 * 所有存储层测试统一用它做真实的文件读写数据，不使用任何 mock 数据。
 */
export class TestFixtures {
  private static kdbxBuffer: ArrayBuffer | null = null;

  /**
   * 加载真实 KDBX 数据库内容（进程内缓存，避免重复读取 rawfile）
   */
  public static async loadUnitTestKdbx(): Promise<ArrayBuffer> {
    if (TestFixtures.kdbxBuffer !== null) {
      return TestFixtures.kdbxBuffer;
    }
    const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
    let moduleContext: common.Context;
    try {
      moduleContext = appContext.createModuleContext('entry_test');
    } catch {
      moduleContext = appContext;
    }
    const content: Uint8Array = await moduleContext.resourceManager.getRawFileContent('unit-test.kdbx');
    const buffer: ArrayBuffer = new ArrayBuffer(content.byteLength);
    new Uint8Array(buffer).set(content);
    TestFixtures.kdbxBuffer = buffer;
    return buffer;
  }

  /**
   * KDBX 文件魔数（固定文件头前 4 字节：0x03 0xD9 0xA2 0x9A），用于内容真实性断言
   */
  public static readonly KDBX_MAGIC: number[] = [0x03, 0xD9, 0xA2, 0x9A];

  /**
   * 断言给定 buffer 为真实 KDBX 内容（校验文件头魔数）
   */
  public static assertKdbxMagic(buffer: ArrayBuffer): boolean {
    const view = new Uint8Array(buffer);
    if (view.length < 4) {
      return false;
    }
    for (let i = 0; i < 4; i++) {
      if (view[i] !== TestFixtures.KDBX_MAGIC[i]) {
        return false;
      }
    }
    return true;
  }
}
