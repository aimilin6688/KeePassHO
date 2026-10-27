import { CsvTargetField } from './CsvImportModels';

/**
 * 单个源列的映射项（向导第 2 步一行）
 */
export class ColumnMappingItem {
  sourceColumnIndex: number;
  sourceColumnName: string;
  targetField: CsvTargetField;
  /** targetField == CUSTOM 时的自定义字段名（空则回退源列名） */
  customFieldName: string;

  constructor(
    sourceColumnIndex: number,
    sourceColumnName: string,
    targetField: CsvTargetField,
    customFieldName: string = ''
  ) {
    this.sourceColumnIndex = sourceColumnIndex;
    this.sourceColumnName = sourceColumnName;
    this.targetField = targetField;
    this.customFieldName = customFieldName;
  }
}

/**
 * 同一目标字段被多个源列映射的冲突描述
 */
export class WizardMappingConflict {
  /** 冲突目标（CUSTOM 时为自定义字段名） */
  readonly targetLabel: string;
  readonly columnNames: string[];

  constructor(targetLabel: string, columnNames: string[]) {
    this.targetLabel = targetLabel;
    this.columnNames = columnNames;
  }
}

/**
 * 向导档案校验结果
 */
export class WizardValidationResult {
  /** 是否存在至少一个有效映射列 */
  readonly hasMappedColumn: boolean;
  readonly conflicts: WizardMappingConflict[];

  constructor(hasMappedColumn: boolean, conflicts: WizardMappingConflict[]) {
    this.hasMappedColumn = hasMappedColumn;
    this.conflicts = conflicts;
  }

  get isValid(): boolean {
    return this.hasMappedColumn;
  }
}

/**
 * 向导确认后的完整列映射档案（Step 4 resolve 的产物）
 */
export class ColumnMappingProfile {
  readonly items: ColumnMappingItem[];
  /** 导入到指定分组名（空 = 根分组） */
  importTargetGroupName: string;
  /** 用户指定的 CSV 文本编码（CsvEncoding；空 = 自动检测，不重新解码） */
  encoding: string;

  constructor(
    items: ColumnMappingItem[],
    importTargetGroupName: string = '',
    encoding: string = ''
  ) {
    this.items = items;
    this.importTargetGroupName = importTargetGroupName;
    this.encoding = encoding;
  }

  /**
   * 校验：至少一个非 SKIP 列；标准目标字段重复映射记为冲突
   */
  validate(): WizardValidationResult {
    let mappedCount = 0;
    const standardBuckets = new Map<string, string[]>();
    const customBuckets = new Map<string, string[]>();

    for (const item of this.items) {
      if (item.targetField === CsvTargetField.SKIP) {
        continue;
      }
      mappedCount++;
      if (item.targetField === CsvTargetField.CUSTOM) {
        const label = item.customFieldName.trim() !== '' ? item.customFieldName.trim() : item.sourceColumnName;
        this.addToBucket(customBuckets, label, item.sourceColumnName);
      } else {
        this.addToBucket(standardBuckets, item.targetField, item.sourceColumnName);
      }
    }

    const conflicts: WizardMappingConflict[] = [];
    for (const entry of standardBuckets) {
      if (entry[1].length > 1) {
        conflicts.push(new WizardMappingConflict(entry[0], entry[1]));
      }
    }
    for (const entry of customBuckets) {
      if (entry[1].length > 1) {
        conflicts.push(new WizardMappingConflict(entry[0], entry[1]));
      }
    }
    return new WizardValidationResult(mappedCount > 0, conflicts);
  }

  private addToBucket(buckets: Map<string, string[]>, key: string, columnName: string): void {
    const existing = buckets.get(key);
    if (existing !== undefined) {
      existing.push(columnName);
    } else {
      buckets.set(key, [columnName]);
    }
  }
}

/**
 * 向导预览数据（Step 1 展示）
 */
export class CsvMappingPreview {
  headers: string[];
  /** 采样数据行（不含表头，最多 20 行） */
  sampleRows: string[][];
  /** 建议映射（同义词字典 + 启发式） */
  suggestedItems: ColumnMappingItem[];
  /** 嗅探识别的格式名（空 = 未识别） */
  detectedFormatName: string;
  totalRowEstimate: number;
  /** 原始文件字节（向导内切换编码时重新解码用） */
  sourceContent: ArrayBuffer;
  /** 自动检测出的编码（CsvEncoding；空 = 调用方未提供） */
  detectedEncoding: string;

  constructor(
    headers: string[],
    sampleRows: string[][],
    suggestedItems: ColumnMappingItem[],
    detectedFormatName: string,
    totalRowEstimate: number,
    sourceContent: ArrayBuffer = new ArrayBuffer(0),
    detectedEncoding: string = ''
  ) {
    this.headers = headers;
    this.sampleRows = sampleRows;
    this.suggestedItems = suggestedItems;
    this.detectedFormatName = detectedFormatName;
    this.totalRowEstimate = totalRowEstimate;
    this.sourceContent = sourceContent;
    this.detectedEncoding = detectedEncoding;
  }
}
