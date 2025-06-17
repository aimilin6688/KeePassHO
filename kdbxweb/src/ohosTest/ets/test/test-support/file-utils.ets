/**
 * Utility class for file operations in tests
 */
import { ByteUtils } from '../../../../main/ets/index';
import { abilityDelegatorRegistry } from '@kit.TestKit';

const delegator = abilityDelegatorRegistry.getAbilityDelegator()
// 获取测试上下文
const context = delegator.getAppContext();


/**
 * Read file content as ArrayBuffer
 * @param filePath - Path to the file
 * @returns ArrayBuffer - File content as ArrayBuffer
 * @throws Error if file cannot be read
 */
export function readFileToBase64(fileName: string): ArrayBuffer {
  const content = readFileToBuffer(fileName);
  // 转换为base64
  const base64Str: string = ByteUtils.bytesToBase64(content);
  return ByteUtils.arrayToBuffer(ByteUtils.base64ToBytes(base64Str));
}

/**
 * Read file content as ArrayBuffer
 * @param filePath - Path to the file
 * @returns ArrayBuffer - File content as ArrayBuffer
 * @throws Error if file cannot be read
 */
export function readFileToString(fileName: string): String {
  return ByteUtils.bytesToString(readFileToBuffer(fileName));
}


/**
 * Read file content as ArrayBuffer
 * @param filePath - Path to the file
 * @returns ArrayBuffer - File content as ArrayBuffer
 * @throws Error if file cannot be read
 */
export function readFileToBuffer(fileName: string): ArrayBuffer {
  // 获取测试资源管理器
  const testResourceManager = context.resourceManager;
  // 读取文件内容
  const rawFile = testResourceManager.getRawFileContentSync(fileName);
  return rawFile.buffer.slice(0);
}
