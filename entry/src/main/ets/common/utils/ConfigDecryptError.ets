import { ResourceManager } from './ResourceManager';

/**
 * 配置解密失败提示的资源名（Worker 线程 message 的回退值，主线程按此识别该错误）
 */
export const STORAGE_CONFIG_DECRYPT_FAILED_RES: string = 'storage_config_decrypt_failed';

/**
 * 配置解密错误：存储配置中 SM4 加密的凭据（如 WebDAV/S3/OneDrive 的账号密码、Token）解密失败时抛出。
 * 语义：加密密钥已变更（升级换签名、换机迁移、恢复出厂等导致 Asset Kit 中 sm4_key 不可用/被重新生成）
 * 或密文损坏，存量密文不可恢复，需用户重新编辑该存储的连接配置。
 *
 * message 约定（跨线程错误展示契约）：
 * - 主线程（ResourceManager 已初始化）：直接为本地化友好文案，showToast(error.message) 即可展示；
 * - Worker 线程（无 ResourceManager 上下文）：回退为资源名 storage_config_decrypt_failed，
 *   经 kdbxErrorPayload → 主线程 ResourceManager.getMessage 按名本地化后展示。
 */
export class ConfigDecryptError extends Error {
  /** 底层原始错误信息（仅日志用途，不对外展示） */
  public readonly detail: string;

  constructor(cause?: Error) {
    const localized = ResourceManager.getString($r('app.string.storage_config_decrypt_failed'));
    super(localized !== '' ? localized : STORAGE_CONFIG_DECRYPT_FAILED_RES);
    this.name = 'ConfigDecryptError';
    this.detail = cause ? cause.message : '';
  }

  /**
   * 判断加载/保存回调收到的错误消息是否为配置解密失败
   * （Worker 抛出的本错误经错误通道回传时 message 为资源名）
   * @param message 错误消息（资源名或资源 ID）
   * @return true=配置解密失败
   */
  public static isDecryptFailedMessage(message: string | number): boolean {
    return message === STORAGE_CONFIG_DECRYPT_FAILED_RES;
  }
}
