import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { FileContentInfo, FileType, FileInfoImpl } from '../../../../main/ets/storage/IFileStorage';

/**
 * 导入格式真实文件夹具：读取 entry_test 模块 rawfile/import/ 下的真实导出文件。
 *
 * 夹具为各密码管理器（Chrome/Firefox/LastPass/Bitwarden/1Password/Dashlane/
 * Proton Pass/Keeper/Enpass/Norton/True Key/本应用 KeePass 导出）的真实导出形态文件，
 * 供导入链路端到端测试使用，不使用内联字符串拼凑格式。
 */
export class ImportFixtures {
  private static cache: Map<string, Uint8Array> = new Map<string, Uint8Array>();

  /**
   * 加载 rawfile/import/ 下的夹具文件为 FileContentInfo（字节进程内缓存，buffer 每次新建）
   * @param fileName 夹具文件名（如 'chrome.csv'）
   */
  public static async loadFixture(fileName: string): Promise<FileContentInfo> {
    let bytes = ImportFixtures.cache.get(fileName);
    if (bytes === undefined) {
      const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      let moduleContext: common.Context;
      try {
        moduleContext = appContext.createModuleContext('entry_test');
      } catch {
        moduleContext = appContext;
      }
      const content: Uint8Array =
        await moduleContext.resourceManager.getRawFileContent(`import/${fileName}`);
      ImportFixtures.cache.set(fileName, content);
      bytes = content;
    }
    const buffer: ArrayBuffer = new ArrayBuffer(bytes.byteLength);
    new Uint8Array(buffer).set(bytes);
    const fileInfo = new FileInfoImpl();
    fileInfo.name = fileName;
    fileInfo.size = buffer.byteLength;
    fileInfo.modifiedTime = Date.now();
    fileInfo.path = fileName;
    fileInfo.type = FileType.FILE;
    fileInfo.childrenCount = 0;
    return new FileContentInfo(fileInfo, buffer);
  }
}
