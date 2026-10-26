/**
 * 可嗅探的导入格式接口
 * 供 CSV 格式族调度器根据表头判断具体格式
 */
export interface ISniffableImport {
  /**
   * 根据表头行与采样数据行评估格式匹配置信度
   * @param headerRow 表头行
   * @param sampleRows 采样数据行（可为空数组）
   * @returns 置信度（0-100）
   */
  sniff(headerRow: string[], sampleRows: string[][]): number;
}
