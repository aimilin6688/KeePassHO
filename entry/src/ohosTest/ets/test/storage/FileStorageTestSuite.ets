import { beforeEach, expect, it } from '@ohos/hypium';
import { IFileStorage, FileInfo, FileType } from '../../../../main/ets/storage/IFileStorage';
import { util } from '@kit.ArkTS';
import { StorageConfig } from '../../../../main/ets/storage/StorageConfig';
import { StorageType } from '../../../../main/ets/storage/StorageType';

export interface FileStorageTestOptions {
  storageType: StorageType;
  pageUrl: string;
  createStorage: () => IFileStorage;
  createConfig: () => StorageConfig;
  /** listDir 路径（必须能列出文件） */
  listDirPath: string;
  /** 写入文件的目标目录路径 */
  writeDir: string;
  /** 确定不存在的路径 */
  nonExistentPath: string;
  specificTests?: () => void;
}

/**
 * IFileStorage 接口实现验证套件
 *
 * 所有测试都基于真实 API 调用：
 * 1. listDir 获取真实文件列表
 * 2. 从列表中取文件验证 read / exists / getInfo
 * 3. 写入临时文件验证 write → exists → read 完整生命周期
 * 4. 不存在的路径验证正确的错误处理
 *
 * ⚠️ 注意：此函数内部不调用 describe()，必须由调用方在 describe 回调中调用。
 * 因 Hypium 的 beforeEach 不向上级联，所有 it 必须是扁平的（无嵌套 describe）。
 */
export function runFileStorageTests(options: FileStorageTestOptions): void {
  // ==================== 共享状态 ====================
  let storage: IFileStorage = options.createStorage();
  let realFiles: FileInfo[] = [];
  let listDirFailed: boolean = false;

  beforeEach(() => {
    storage = options.createStorage();
    storage.init(options.createConfig());
    if (realFiles.length === 0 && !listDirFailed) {
      storage.listDir(options.listDirPath).then((files: FileInfo[]) => {
        realFiles = files;
      }).catch(() => {
        listDirFailed = true;
      });
    }
  });

  // ==================== 1. 创建 ====================
  it('should create instance and config', 0, () => {
    const s = options.createStorage();
    const config = options.createConfig();
    expect(s).not().assertUndefined();
    expect(config).not().assertUndefined();
  });

  // ==================== 2. PageConfig ====================
  it('should return correct storageType and pageUrl', 0, () => {
    const cfg = options.createStorage().getPageConfig();
    expect(cfg.storageType).assertEqual(options.storageType);
    expect(cfg.pageUrl).assertEqual(options.pageUrl);
    expect(cfg.icon).not().assertUndefined();
  });

  // ==================== 3. 真实 API 操作 ====================

  it('listDir: should list files', 0, () => {
    expect(listDirFailed).assertFalse();
    expect(Array.isArray(realFiles)).assertTrue();
  });

  it('exists: should return true for real file', 0, async () => {
    expect(listDirFailed).assertFalse();
    expect(realFiles.length).assertLarger(0);
    const result = await storage.exists(realFiles[0].path);
    expect(result).assertTrue();
  });

  it('exists: should return false for non-existent path', 0, async () => {
    const result = await storage.exists(options.nonExistentPath);
    expect(result).assertFalse();
  });

  it('getInfo: should return FileInfo for real file', 0, async () => {
    expect(listDirFailed).assertFalse();
    expect(realFiles.length).assertLarger(0);
    const info = await storage.getInfo(realFiles[0].path);
    expect(info).not().assertUndefined();
    expect(info.name).assertEqual(realFiles[0].name);
    expect(info.path).assertEqual(realFiles[0].path);
    expect(info.type).assertEqual(realFiles[0].type);
  });

  it('getInfo: should throw for non-existent path', 0, async () => {
    try {
      await storage.getInfo(options.nonExistentPath);
      expect(true).assertFalse();
    } catch (error) {
      expect(error).not().assertUndefined();
    }
  });

  it('read: should read content of real file', 0, async () => {
    expect(listDirFailed).assertFalse();
    const fileItems: FileInfo[] = realFiles.filter(
      (f: FileInfo): boolean => f.type === FileType.FILE
    );
    expect(fileItems.length).assertLarger(0);
    const content = await storage.read(fileItems[0].path);
    expect(content).not().assertUndefined();
    expect(content.byteLength).assertLarger(0);
  });

  it('read: should throw for non-existent path', 0, async () => {
    try {
      await storage.read(options.nonExistentPath);
      expect(true).assertFalse();
    } catch (error) {
      expect(error).not().assertUndefined();
    }
  });

  it('writeAndRead: should write temp file, verify and read back', 0, async () => {
    const encoder = new util.TextEncoder();
    const testName = 'pcommon-test-' + Date.now() + '.txt';
    const testContent = 'IFileStorage common test write/read at ' + Date.now();
    const testPath = options.writeDir + testName;
    const data = encoder.encodeInto(testContent);

    // 写入
    await storage.write(testPath, data.buffer as ArrayBuffer);

    // 验证存在
    const existsResult = await storage.exists(testPath);
    expect(existsResult).assertTrue();

    // 读取并验证内容
    const readContent = await storage.read(testPath);
    const bytes = new Uint8Array(readContent);
    const decoder = new util.TextDecoder();
    const text = decoder.decodeToString(bytes);
    expect(text).assertEqual(testContent);
  });

  // ==================== 4. 未初始化保护 ====================
  it('UninitializedGuard: all methods throw when not initialized', 0, async () => {
    const s = options.createStorage();
    try { await s.read(options.nonExistentPath); expect(true).assertFalse(); }
    catch (e) { expect(e).not().assertUndefined(); }
    try { await s.write(options.nonExistentPath, new ArrayBuffer(0)); expect(true).assertFalse(); }
    catch (e) { expect(e).not().assertUndefined(); }
    try { await s.listDir(options.nonExistentPath); expect(true).assertFalse(); }
    catch (e) { expect(e).not().assertUndefined(); }
  });

  // ==================== 5. 后端特有测试 ====================
  const fn = options.specificTests;
  if (fn) {
    fn();
  }
}
