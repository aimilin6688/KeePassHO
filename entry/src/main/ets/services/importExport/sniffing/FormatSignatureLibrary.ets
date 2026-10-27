import { CsvTargetField } from '../csvimport/CsvImportModels';

/**
 * CSV 格式签名（数据驱动）
 * 一条签名 = 必需表头 + 已知表头全集 + 预设映射（标准目标 + 自定义字段名 + 忽略列 + 收藏列）
 * 长尾格式只在此追加数据行，不新增 handler 类
 */
export class CsvFormatSignature {
  readonly formatId: string;
  readonly formatName: string;
  /** 必需表头（归一化小写；全部存在才视为候选） */
  readonly requiredHeaders: string[];
  /** 已知表头全集（归一化小写；文件表头是其子集时置信度 100） */
  readonly knownHeaders: string[];
  /** 标准目标字段预设映射（归一化表头 → 目标） */
  readonly headerMap: Record<string, CsvTargetField>;
  /** 自定义字段预设映射（归一化表头 → 自定义字段名） */
  readonly customHeaderMap: Record<string, string>;
  /** 显式忽略的表头（不导入） */
  readonly ignoredHeaders: string[];
  /** 收藏列表头：值 1/true → FAVORITE_TAG 标签 */
  readonly favoriteHeaders: string[];

  constructor(
    formatId: string,
    formatName: string,
    requiredHeaders: string[],
    knownHeaders: string[],
    headerMap: Record<string, CsvTargetField>,
    customHeaderMap: Record<string, string>,
    ignoredHeaders: string[],
    favoriteHeaders: string[]
  ) {
    this.formatId = formatId;
    this.formatName = formatName;
    this.requiredHeaders = requiredHeaders;
    this.knownHeaders = knownHeaders;
    this.headerMap = headerMap;
    this.customHeaderMap = customHeaderMap;
    this.ignoredHeaders = ignoredHeaders;
    this.favoriteHeaders = favoriteHeaders;
  }
}

/**
 * 签名匹配结果
 */
export class SignatureMatchResult {
  readonly formatId: string;
  readonly formatName: string;
  readonly score: number;

  constructor(formatId: string, formatName: string, score: number) {
    this.formatId = formatId;
    this.formatName = formatName;
    this.score = score;
  }
}

/**
 * 格式签名库
 * 置信度规则（§4.5）：全部必需表头存在 → 候选 70 分；
 * 文件表头为已知全集的子集（无未知列）→ 100 分；否则 0 分。
 * 例外：未声明可选列的签名（known == required，如 Norton 恰 5 列）出现未知列直接 0 分，
 * 防止本应用导出等超集表头被误认领。
 * 首批签名（参考库权威实现）：
 * - Norton Identity Safe CSV（KeePass NortonIdSafeCsv2013.cs，位置式 url,username,password,title,group）
 * - True Key CSV（KeePass TrueKeyCsv4.cs，特征列 tk_export_version）
 */
export class FormatSignatureLibrary {
  /** Norton Identity Safe CSV：表头 url,username,password,title,group（KeePass 权威） */
  private static readonly NORTON_IDSAFE: CsvFormatSignature = new CsvFormatSignature(
    'NORTON_IDSAFE_CSV',
    'Norton Identity Safe',
    ['url', 'username', 'password', 'title', 'group'],
    ['url', 'username', 'password', 'title', 'group'],
    {
      'url': CsvTargetField.URL,
      'username': CsvTargetField.USERNAME,
      'password': CsvTargetField.PASSWORD,
      'title': CsvTargetField.TITLE,
      'group': CsvTargetField.GROUP
    },
    {},
    [],
    []
  );

  /** True Key CSV：特征列 tk_export_version（KeePass TrueKeyCsv4.cs 权威） */
  private static readonly TRUE_KEY: CsvFormatSignature = new CsvFormatSignature(
    'TRUEKEY_CSV',
    'True Key',
    ['tk_export_version', 'name', 'login', 'password'],
    [
      'name', 'title', 'cardholder', 'email', 'login', 'password', 'url', 'website',
      'document_content', 'memo', 'note', 'city', 'company', 'country', 'number',
      'state', 'street', 'telephone', 'deliveryplace', 'firstname', 'lastname',
      'memberid', 'phonenumber', 'streetnumber', 'zipcode', 'dateofbirth',
      'expirationdate', 'expirydate', 'favorite', 'gender', 'hexcolor',
      'issuedate', 'issueddate', 'membersince', 'kind', 'autologin',
      'protectedwithpassword', 'subdomainonly', 'type', 'tk_export_version'
    ],
    {
      'name': CsvTargetField.TITLE,
      'title': CsvTargetField.TITLE,
      'cardholder': CsvTargetField.USERNAME,
      'email': CsvTargetField.USERNAME,
      'login': CsvTargetField.USERNAME,
      'password': CsvTargetField.PASSWORD,
      'url': CsvTargetField.URL,
      'website': CsvTargetField.URL,
      'document_content': CsvTargetField.NOTES,
      'memo': CsvTargetField.NOTES,
      'note': CsvTargetField.NOTES,
      'expirationdate': CsvTargetField.EXPIRY_TIME,
      'expirydate': CsvTargetField.EXPIRY_TIME
    },
    {
      'city': 'City',
      'company': 'Company',
      'country': 'Country',
      'number': 'Number',
      'state': 'State',
      'street': 'Street',
      'telephone': 'Telephone',
      'deliveryplace': 'Delivery Place',
      'firstname': 'First Name',
      'lastname': 'Last Name',
      'memberid': 'Member ID',
      'phonenumber': 'Phone Number',
      'streetnumber': 'Street Number',
      'zipcode': 'ZIP Code',
      'dateofbirth': 'Date of Birth',
      'issuedate': 'Issue Date',
      'issueddate': 'Issue Date',
      'membersince': 'Member Since'
    },
    ['autologin', 'protectedwithpassword', 'subdomainonly', 'type', 'kind', 'gender', 'hexcolor', 'tk_export_version'],
    ['favorite']
  );

  private static readonly SIGNATURES: CsvFormatSignature[] = [
    FormatSignatureLibrary.NORTON_IDSAFE,
    FormatSignatureLibrary.TRUE_KEY
  ];

  /**
   * 全部签名按序匹配，取最高分
   * @returns 最佳匹配；全部 0 分时返回 null
   */
  static matchCsvHeaders(headers: string[]): SignatureMatchResult | null {
    let best: SignatureMatchResult | null = null;
    for (const signature of FormatSignatureLibrary.SIGNATURES) {
      const score = FormatSignatureLibrary.scoreSignature(signature, headers);
      if (score > 0 && (best === null || score > best.score)) {
        best = new SignatureMatchResult(signature.formatId, signature.formatName, score);
      }
    }
    return best;
  }

  /**
   * 单签名评分：必需表头缺失 0 分；全部存在 70 分；且文件表头 ⊆ 已知全集 100 分。
   * 例外：未声明可选列的签名（knownHeaders 与 requiredHeaders 等长）出现未知列直接 0 分，
   * 防止他格式超集误认领（如 Norton 5 列签名 vs 本应用导出 Group,Title,UserName,Password,URL,Notes）。
   */
  static scoreSignature(signature: CsvFormatSignature, headers: string[]): number {
    const normalized = FormatSignatureLibrary.normalizeHeaders(headers);
    for (const required of signature.requiredHeaders) {
      if (normalized.indexOf(required) < 0) {
        return 0;
      }
    }
    const strict = signature.knownHeaders.length === signature.requiredHeaders.length;
    for (const header of normalized) {
      if (signature.knownHeaders.indexOf(header) < 0) {
        return strict ? 0 : 70;
      }
    }
    return 100;
  }

  /**
   * 按格式标识取签名
   */
  static getSignature(formatId: string): CsvFormatSignature | null {
    for (const signature of FormatSignatureLibrary.SIGNATURES) {
      if (signature.formatId === formatId) {
        return signature;
      }
    }
    return null;
  }

  static getAllSignatures(): CsvFormatSignature[] {
    return FormatSignatureLibrary.SIGNATURES;
  }

  private static normalizeHeaders(headers: string[]): string[] {
    const normalized: string[] = [];
    for (const header of headers) {
      normalized.push(header.trim().toLowerCase());
    }
    return normalized;
  }
}
