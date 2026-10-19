import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils } from 'kdbxweb';
import { ResourceManager } from '../../common/utils';
import { KdbxFileManager } from '../kdbx/KdbxFileManager';
import { CredentialsParam } from '../TypeDefined';

const DOMAIN = 0x0000;
const TAG = 'KeyFileReader';

/** KDBX 文件第一签名（LE u32，正式版 / 预发布版 / 旧版 KDB 相同） */
const KDBX_SIGNATURE_1 = 0x9AA2D903;

/** KDBX 文件第二签名集合（LE u32）：KDBX 4.x / 预发布版 / KeePass 1.x KDB */
const KDBX_SIGNATURE_2_SET: number[] = [0xB54BFB67, 0xB54BFB66, 0xB54BFB65];

/**
 * 判断文件内容是否为 KDBX/KDB 数据库（前 8 字节签名比对）
 * 对齐 KeePass 桌面版 KcpKeyFile(bThrowIfDbFile) 防误选行为
 */
export function isKdbxDatabaseBytes(content: ArrayBuffer): boolean {
  if (content.byteLength < 8) {
    return false;
  }
  const view = new DataView(content);
  const sig1 = view.getUint32(0, true);
  const sig2 = view.getUint32(4, true);
  if (sig1 !== KDBX_SIGNATURE_1) {
    return false;
  }
  for (const sig of KDBX_SIGNATURE_2_SET) {
    if (sig2 === sig) {
      return true;
    }
  }
  return false;
}

/**
 * 密钥文件读取工具
 */
export class KeyFileReader {
  /**
   * 校验密钥文件路径并读取内容
   * （内联 KeyFile.bin 附件内容优先：AutoOpen 子库无 UserName 密钥路径时
   * 的密钥来源，随任务消息以 base64 传入，不落盘不持久化）
   * @param param 凭证参数
   * @param scenario 日志场景标识
   * @throws Error 密钥文件路径缺失 / 误选数据库文件时抛出
   */
  public static async requireAndRead(param: CredentialsParam, scenario: string): Promise<ArrayBuffer> {
    const inlineBase64: string | undefined = param.keyFileDataBase64;
    if (inlineBase64 !== undefined && inlineBase64.length > 0) {
      const inline: ArrayBuffer = ByteUtils.arrayToBuffer(ByteUtils.base64ToBytes(inlineBase64));
      if (isKdbxDatabaseBytes(inline)) {
        hilog.warn(DOMAIN, TAG,
          'Inline key file is a database file, rejected (%{public}s)', scenario);
        throw new Error(ResourceManager.getString($r('app.string.error_keyfile_is_database')));
      }
      hilog.info(DOMAIN, TAG, 'Load inline key file content success (%{public}s)', scenario);
      return inline;
    }
    if (param.keyLocation === undefined) {
      throw new Error(ResourceManager.getString($r('app.string.error_keyfile_not_found')));
    }
    const keyFile = await KdbxFileManager.of(param.keyLocation).read(param.keyLocation.filePath);
    if (isKdbxDatabaseBytes(keyFile.content)) {
      hilog.warn(DOMAIN, TAG,
        'Selected key file is a database file, rejected (%{public}s), keyFilePath: %{public}s',
        scenario, param.keyLocation.filePath);
      throw new Error(ResourceManager.getString($r('app.string.error_keyfile_is_database')));
    }
    hilog.info(DOMAIN, TAG, 'Load key file content success (%{public}s), keyFilePath: %{public}s',
      scenario, param.keyLocation.filePath);
    return keyFile.content;
  }
}
