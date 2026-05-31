/**
 * 格式信息
 */
export interface FormatInfo {
  /**
   * 格式唯一标识
   */
  formatId: string;

  /**
   * 格式显示名称（用于 UI 显示）
   */
  formatName: string;

  /**
   * 支持的文件扩展名列表
   */
  extensions: string[];
}
