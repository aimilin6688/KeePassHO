import { CsvParseResult } from './CsvImportModels';

const DEFAULT_SEPARATOR = ',';
const UTF8_BOM = '\uFEFF';

/**
 * CSV 解析器
 * 语义对齐 KeePassXC CsvParser（RFC4180 风格状态机）：
 * 1. 引号字段内的分隔符 / 换行原样保留
 * 2. 引号内 "" 转义为一个引号
 * 3. CRLF / CR 统一归一为 LF，剥离 UTF-8 BOM
 * 4. 全空行跳过；短行补齐到最大列数
 * 5. 未闭合引号置 isGood = false 但保留已解析内容；闭合引号后的杂字符宽松追加
 */
export class CsvParser {
  private readonly separator: string;

  constructor(separator: string = DEFAULT_SEPARATOR) {
    this.separator = separator;
  }

  /**
   * 解析 CSV 文本
   * @param text CSV 文本
   * @returns 解析结果
   */
  parse(text: string): CsvParseResult {
    const normalized = CsvParser.normalizeText(text);
    const rawRows: string[][] = [];
    let isGood = true;

    let currentRow: string[] = [];
    let currentField = '';
    let inQuotes = false;

    for (let i = 0; i < normalized.length; i++) {
      const ch = normalized[i];
      if (inQuotes) {
        if (ch === '"') {
          if (i + 1 < normalized.length && normalized[i + 1] === '"') {
            currentField += '"';
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          currentField += ch;
        }
      } else if (ch === '"') {
        inQuotes = true;
      } else if (ch === this.separator) {
        currentRow.push(currentField);
        currentField = '';
      } else if (ch === '\n') {
        currentRow.push(currentField);
        currentField = '';
        rawRows.push(currentRow);
        currentRow = [];
      } else {
        currentField += ch;
      }
    }

    if (inQuotes) {
      isGood = false;
    }
    if (currentField !== '' || currentRow.length > 0 || inQuotes) {
      currentRow.push(currentField);
      rawRows.push(currentRow);
      currentField = '';
      currentRow = [];
    }

    const rows: string[][] = [];
    let maxCols = 0;
    for (const row of rawRows) {
      if (CsvParser.isRowEmpty(row)) {
        continue;
      }
      if (row.length > maxCols) {
        maxCols = row.length;
      }
      rows.push(row);
    }
    for (const row of rows) {
      while (row.length < maxCols) {
        row.push('');
      }
    }

    const result: CsvParseResult = {
      rows: rows,
      columnCount: maxCols,
      isGood: isGood
    };
    return result;
  }

  /**
   * 解析文本中的第一条非空记录（用于格式嗅探）
   * @param text CSV 文本
   * @param separator 分隔符
   * @returns 首条记录；文本为空时返回 undefined
   */
  static parseFirstRecord(text: string, separator: string = DEFAULT_SEPARATOR): string[] | undefined {
    const parser = new CsvParser(separator);
    const result = parser.parse(text);
    if (result.rows.length === 0) {
      return undefined;
    }
    return result.rows[0];
  }

  /**
   * 归一化文本：剥离 UTF-8 BOM，CRLF / CR 统一为 LF
   */
  static normalizeText(text: string): string {
    let result = text;
    if (result.startsWith(UTF8_BOM)) {
      result = result.substring(UTF8_BOM.length);
    }
    result = result.replace(/\r\n/g, '\n');
    result = result.replace(/\r/g, '\n');
    return result;
  }

  /**
   * 判断一行是否全空（所有字段去除空白后均为空）
   */
  static isRowEmpty(row: string[]): boolean {
    for (const field of row) {
      if (field.trim() !== '') {
        return false;
      }
    }
    return true;
  }
}
