import { CsvTargetField } from './CsvImportModels';

/**
 * 列映射向导目标字段
 * 覆盖全部 CsvTargetField + 跳过（SKIP）/ 自定义（CUSTOM）
 */
export enum WizardTargetField {
  SKIP = 'SKIP',
  GROUP = 'GROUP',
  TITLE = 'TITLE',
  USERNAME = 'USERNAME',
  PASSWORD = 'PASSWORD',
  URL = 'URL',
  NOTES = 'NOTES',
  TOTP = 'TOTP',
  TAGS = 'TAGS',
  ICON = 'ICON',
  EXPIRY_TIME = 'EXPIRY_TIME',
  LAST_MODIFIED = 'LAST_MODIFIED',
  CREATED = 'CREATED',
  CUSTOM = 'CUSTOM'
}

/**
 * 单个源列的映射项（向导第 2 步一行）
 */
export class ColumnMappingItem {
  sourceColumnIndex: number;
  sourceColumnName: string;
  targetField: WizardTargetField;
  /** targetField == CUSTOM 时的自定义字段名（空则回退源列名） */
  customFieldName: string;

  constructor(
    sourceColumnIndex: number,
    sourceColumnName: string,
    targetField: WizardTargetField,
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

  constructor(items: ColumnMappingItem[], importTargetGroupName: string = '') {
    this.items = items;
    this.importTargetGroupName = importTargetGroupName;
  }

  /**
   * 校验：至少一个非 SKIP 列；标准目标字段重复映射记为冲突
   */
  validate(): WizardValidationResult {
    let mappedCount = 0;
    const standardBuckets = new Map<string, string[]>();
    const customBuckets = new Map<string, string[]>();

    for (const item of this.items) {
      if (item.targetField === WizardTargetField.SKIP) {
        continue;
      }
      mappedCount++;
      if (item.targetField === WizardTargetField.CUSTOM) {
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

  constructor(
    headers: string[],
    sampleRows: string[][],
    suggestedItems: ColumnMappingItem[],
    detectedFormatName: string,
    totalRowEstimate: number
  ) {
    this.headers = headers;
    this.sampleRows = sampleRows;
    this.suggestedItems = suggestedItems;
    this.detectedFormatName = detectedFormatName;
    this.totalRowEstimate = totalRowEstimate;
  }
}

/**
 * WizardTargetField 与 CsvTargetField 的双向转换
 * （两个枚举同名的标准字段一一对应；SKIP/CUSTOM 仅存在于向导侧）
 */
export class WizardTargetFieldConverter {
  static fromCsvTargetField(target: CsvTargetField): WizardTargetField {
    switch (target) {
      case CsvTargetField.GROUP:
        return WizardTargetField.GROUP;
      case CsvTargetField.TITLE:
        return WizardTargetField.TITLE;
      case CsvTargetField.USERNAME:
        return WizardTargetField.USERNAME;
      case CsvTargetField.PASSWORD:
        return WizardTargetField.PASSWORD;
      case CsvTargetField.URL:
        return WizardTargetField.URL;
      case CsvTargetField.NOTES:
        return WizardTargetField.NOTES;
      case CsvTargetField.TOTP:
        return WizardTargetField.TOTP;
      case CsvTargetField.TAGS:
        return WizardTargetField.TAGS;
      case CsvTargetField.ICON:
        return WizardTargetField.ICON;
      case CsvTargetField.EXPIRY_TIME:
        return WizardTargetField.EXPIRY_TIME;
      case CsvTargetField.LAST_MODIFIED:
        return WizardTargetField.LAST_MODIFIED;
      case CsvTargetField.CREATED:
        return WizardTargetField.CREATED;
      default:
        return WizardTargetField.SKIP;
    }
  }

  /**
   * 转回标准目标字段；SKIP/CUSTOM 返回 undefined
   */
  static toCsvTargetField(target: WizardTargetField): CsvTargetField | undefined {
    switch (target) {
      case WizardTargetField.GROUP:
        return CsvTargetField.GROUP;
      case WizardTargetField.TITLE:
        return CsvTargetField.TITLE;
      case WizardTargetField.USERNAME:
        return CsvTargetField.USERNAME;
      case WizardTargetField.PASSWORD:
        return CsvTargetField.PASSWORD;
      case WizardTargetField.URL:
        return CsvTargetField.URL;
      case WizardTargetField.NOTES:
        return CsvTargetField.NOTES;
      case WizardTargetField.TOTP:
        return CsvTargetField.TOTP;
      case WizardTargetField.TAGS:
        return CsvTargetField.TAGS;
      case WizardTargetField.ICON:
        return CsvTargetField.ICON;
      case WizardTargetField.EXPIRY_TIME:
        return CsvTargetField.EXPIRY_TIME;
      case WizardTargetField.LAST_MODIFIED:
        return CsvTargetField.LAST_MODIFIED;
      case WizardTargetField.CREATED:
        return CsvTargetField.CREATED;
      default:
        return undefined;
    }
  }
}
