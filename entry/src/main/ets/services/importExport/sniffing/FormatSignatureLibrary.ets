import { CsvTargetField } from '../csvimport/CsvImportModels';
import { ColumnNameMapper } from '../csvimport/ColumnNameMapper';

/**
 * CSV 格式签名（数据驱动）
 * 一条签名 = 必需表头 + 特征表头 + 已知表头全集 + 预设映射（标准目标 + 自定义字段名 + 忽略列 + 收藏列 + 分组分隔符）
 * 纯数据格式（Chrome/Firefox/LastPass/Dashlane/1Password/Norton/True Key）只在此追加数据行，不新增 handler 类；
 * 有特殊行处理逻辑的格式（Bitwarden/Proton/Keeper/Enpass）仍用独立 handler 类。
 */
export class CsvFormatSignature {
  readonly formatId: string;
  readonly formatName: string;
  /** 必需表头（归一化小写；全部存在才视为候选） */
  readonly requiredHeaders: string[];
  /** 已知表头全集（归一化小写；不在此内的未知列须完全不可识别） */
  readonly knownHeaders: string[];
  /** 标准目标字段预设映射（归一化表头 → 目标） */
  readonly headerMap: Record<string, CsvTargetField>;
  /** 自定义字段预设映射（归一化表头 → 自定义字段名） */
  readonly customHeaderMap: Record<string, string>;
  /** 显式忽略的表头（不导入） */
  readonly ignoredHeaders: string[];
  /** 收藏列表头：值 1/true → FAVORITE_TAG 标签 */
  readonly favoriteHeaders: string[];
  /** 特征表头（归一化小写；非空时任一存在才认领，与最小公共集区分） */
  readonly distinguishers: string[];
  /** 分组路径 '\' 分隔符归一化为 '/'（LastPass 语义） */
  readonly slashGroupPath: boolean;

  constructor(
    formatId: string,
    formatName: string,
    requiredHeaders: string[],
    knownHeaders: string[],
    headerMap: Record<string, CsvTargetField>,
    customHeaderMap: Record<string, string>,
    ignoredHeaders: string[],
    favoriteHeaders: string[],
    distinguishers: string[] = [],
    slashGroupPath: boolean = false
  ) {
    this.formatId = formatId;
    this.formatName = formatName;
    this.requiredHeaders = requiredHeaders;
    this.knownHeaders = knownHeaders;
    this.headerMap = headerMap;
    this.customHeaderMap = customHeaderMap;
    this.ignoredHeaders = ignoredHeaders;
    this.favoriteHeaders = favoriteHeaders;
    this.distinguishers = distinguishers;
    this.slashGroupPath = slashGroupPath;
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
 * 统一评分规则（对齐 BaseCsvImportHandler.matchesHeadersClaimable v3 语义）：
 * 1. 必需表头缺失 → 0 分（格式无法成立，走列映射向导）；
 * 2. 特征表头（distinguishers）非空时全部缺失 → 0 分（与最小公共集区分）；
 * 3. 未知列（不在已知全集）须完全不可识别（ColumnNameMapper.mapWithSpecificity === undefined）：
 *    可识别的未知列 → 0 分（走向导预填全部列映射）；不可识别的杂列 → 忽略照导；
 * 4. 满足全部条件 → 90 分（SNIFF_CONFIDENCE）。
 * 顺序即优先级：先匹配的签名在同分时胜出（matchCsvHeaders 取首个最高分）。
 * 签名数据参考权威实现：KeePass 2.x（Norton TrueKey）、keeweb/kdbxweb（LastPass Chrome Firefox）、
 * Dashlane/1Password 官方导出格式。
 */
export class FormatSignatureLibrary {
  /** LastPass CSV：url,username,password,extra,name,grouping[,fav][,totp]；grouping 支持 '\' 分隔 */
  private static readonly LASTPASS: CsvFormatSignature = new CsvFormatSignature(
    'LASTPASS_CSV',
    'LastPass CSV',
    ['url', 'username', 'password', 'extra', 'name', 'grouping'],
    ['url', 'username', 'password', 'extra', 'name', 'grouping', 'fav', 'totp'],
    {
      'url': CsvTargetField.URL,
      'username': CsvTargetField.USERNAME,
      'password': CsvTargetField.PASSWORD,
      'extra': CsvTargetField.NOTES,
      'name': CsvTargetField.TITLE,
      'grouping': CsvTargetField.GROUP,
      'totp': CsvTargetField.TOTP
    },
    {},
    [],
    [],
    [],
    true
  );

  /** Dashlane 6+ CSV：title,url,username,password,note,category,otpSecret,lastModified */
  private static readonly DASHLANE: CsvFormatSignature = new CsvFormatSignature(
    'DASHLANE_CSV',
    'Dashlane CSV',
    ['title', 'url', 'username', 'password'],
    ['title', 'url', 'username', 'password', 'note', 'category', 'otpsecret', 'lastmodified'],
    {
      'title': CsvTargetField.TITLE,
      'url': CsvTargetField.URL,
      'username': CsvTargetField.USERNAME,
      'password': CsvTargetField.PASSWORD,
      'note': CsvTargetField.NOTES,
      'category': CsvTargetField.GROUP,
      'otpsecret': CsvTargetField.TOTP,
      'lastmodified': CsvTargetField.LAST_MODIFIED
    },
    {},
    [],
    [],
    ['category', 'otpsecret', 'lastmodified']
  );

  /** 1Password 8 CSV：Title,Url,Username,Password,OTPAuth,Notes */
  private static readonly ONEPASSWORD: CsvFormatSignature = new CsvFormatSignature(
    'ONEPASSWORD_CSV',
    '1Password CSV',
    ['title', 'url', 'username', 'password'],
    ['title', 'url', 'username', 'password', 'otpauth', 'notes'],
    {
      'title': CsvTargetField.TITLE,
      'url': CsvTargetField.URL,
      'username': CsvTargetField.USERNAME,
      'password': CsvTargetField.PASSWORD,
      'otpauth': CsvTargetField.TOTP,
      'notes': CsvTargetField.NOTES
    },
    {},
    [],
    [],
    ['otpauth']
  );

  /** Firefox about:logins CSV：url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged */
  private static readonly FIREFOX: CsvFormatSignature = new CsvFormatSignature(
    'FIREFOX_CSV',
    'Firefox CSV',
    ['url', 'username', 'password'],
    [
      'url', 'username', 'password', 'httprealm', 'formactionorigin',
      'guid', 'timecreated', 'timelastused', 'timepasswordchanged'
    ],
    {
      'url': CsvTargetField.URL,
      'username': CsvTargetField.USERNAME,
      'password': CsvTargetField.PASSWORD,
      'httprealm': CsvTargetField.NOTES,
      'timecreated': CsvTargetField.CREATED,
      'timepasswordchanged': CsvTargetField.LAST_MODIFIED
    },
    {},
    [],
    [],
    ['httprealm', 'formactionorigin', 'guid', 'timecreated', 'timelastused', 'timepasswordchanged']
  );

  /** Chrome/Edge/Brave/Opera/Vivaldi CSV：name,url,username,password[,note]（Safari iOS 导出无 note） */
  private static readonly CHROME: CsvFormatSignature = new CsvFormatSignature(
    'CHROME_CSV',
    'Chrome CSV',
    ['name', 'url', 'username', 'password'],
    ['name', 'url', 'username', 'password', 'note'],
    {
      'name': CsvTargetField.TITLE,
      'url': CsvTargetField.URL,
      'username': CsvTargetField.USERNAME,
      'password': CsvTargetField.PASSWORD,
      'note': CsvTargetField.NOTES
    },
    {},
    [],
    []
  );

  /** Norton Identity Safe CSV：表头 url,username,password,title,group（KeePass NortonIdSafeCsv2013.cs，位置式） */
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
    FormatSignatureLibrary.LASTPASS,
    FormatSignatureLibrary.DASHLANE,
    FormatSignatureLibrary.ONEPASSWORD,
    FormatSignatureLibrary.FIREFOX,
    FormatSignatureLibrary.CHROME,
    FormatSignatureLibrary.NORTON_IDSAFE,
    FormatSignatureLibrary.TRUE_KEY
  ];

  /**
   * 全部签名按序匹配，取最高分（同分时先匹配者胜出）
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
   * 单签名统一评分（matchesHeadersClaimable v3 语义 + 特征列判定）：
   * 1. 必需表头缺失 → 0；
   * 2. 特征表头非空且全部缺失 → 0；
   * 3. 未知列（不在已知全集）可识别（mapWithSpecificity 非 undefined）→ 0（走向导预填），
   *    完全不可识别 → 忽略照导（KeePass 2.x 按名映射语义）；
   * 4. 满足全部条件 → 90（SNIFF_CONFIDENCE）。
   */
  static scoreSignature(signature: CsvFormatSignature, headers: string[]): number {
    const normalized = FormatSignatureLibrary.normalizeHeaders(headers);
    for (const required of signature.requiredHeaders) {
      if (normalized.indexOf(required) < 0) {
        return 0;
      }
    }
    if (signature.distinguishers.length > 0) {
      let hasDistinguisher = false;
      for (const distinguisher of signature.distinguishers) {
        if (normalized.indexOf(distinguisher) >= 0) {
          hasDistinguisher = true;
          break;
        }
      }
      if (!hasDistinguisher) {
        return 0;
      }
    }
    for (const header of normalized) {
      if (signature.knownHeaders.indexOf(header) >= 0) {
        continue;
      }
      if (ColumnNameMapper.mapWithSpecificity(header) !== undefined) {
        return 0;
      }
    }
    return 90;
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
