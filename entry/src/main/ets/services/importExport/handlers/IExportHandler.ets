import { Kdbx } from 'kdbxweb';

/**
 * 导出处理器接口
 */
export interface IExportHandler {
  /**
   * 支持的文件扩展名
   */
  readonly supportedExtensions: string[];

  /**
   * 格式显示名称
   */
  readonly formatName: string;

  /**
   * 格式唯一标识
   */
  readonly formatId: string;

  /**
   * 默认文件名
   */
  readonly defaultFileName: string;

  /**
   * 判断是否能处理该格式
   */
  canHandle(formatId: string): boolean;

  /**
   * 执行导出
   * @param database 数据库对象
   * @returns 导出的文件内容
   * @throws ExportError 导出失败时抛出
   */
  export(database: Kdbx): Promise<ArrayBuffer>;
}
