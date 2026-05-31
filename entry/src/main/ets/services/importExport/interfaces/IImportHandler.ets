import { KdbxGroup } from 'kdbxweb';
import { FileContentInfo } from '../../../storage';

/**
 * 导入处理器接口
 */
export interface IImportHandler {
  /**
   * 支持的文件扩展名（含点，如 '.csv'）
   */
  readonly supportedExtensions: string[];

  /**
   * 格式显示名称（用于 UI）
   */
  readonly formatName: string;

  /**
   * 格式唯一标识
   */
  readonly formatId: string;

  /**
   * 判断是否能处理该文件
   * @param extension 文件扩展名
   */
  canHandle(extension: string): boolean;

  /**
   * 执行导入
   * @param fileContent 文件内容
   * @returns 解析后的 KdbxGroup
   * @throws ImportError 导入失败时抛出
   */
  import(fileContent: FileContentInfo): Promise<KdbxGroup>;
}
