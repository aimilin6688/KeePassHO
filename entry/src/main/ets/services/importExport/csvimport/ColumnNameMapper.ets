import { CsvTargetField } from './CsvImportModels';

/**
 * 列名匹配结果：命中目标字段 + 命中同义词长度（同目标多列冲突时越长越优先）
 */
export interface ColumnMatch {
  target: CsvTargetField;
  matchedLength: number;
}

/**
 * 列名映射器
 * 同义词字典移植自 KeePass 2.x ImportUtil.MapNameToStandardField（精确匹配 + 模糊子串匹配），
 * 并扩展 KeePassXC CSV 导入目标字段（Group/TOTP/Tags/Icon/Expiry/Last Modified/Created）与中文同义词。
 * 匹配阶段：①精确同义词（KeePass 字典 + 中文同义词）
 *          ②包含子串（KeePass 2.x 顺序：password → username → url → notes）
 *          ③前缀匹配（「GROUP分组」「TITLE(标题)」「username用户名」等带注释表头，取最长命中同义词）
 */
export class ColumnNameMapper {
  // KeePass 2.x ImportUtil 同义词表 + 中文同义词
  private static readonly TITLES: string[] = [
    'title', 'account', 'item name', 'itemname', 'subject', 'service', 'type', '标题', '名称'
  ];
  private static readonly USERNAMES: string[] = [
    'user name', 'username', 'login', 'email', 'e-mail', 'user id', 'userid', 'name', 'user',
    '用户名', '账号', '帐号', '邮箱', '登录名', '登陆名'
  ];
  private static readonly PASSWORDS: string[] = [
    'password', 'passphrase', 'pass', 'pwd', 'pw', 'pin', 'secret', '密码', '口令'
  ];
  private static readonly URLS: string[] = [
    'url', 'hyper link', 'hyperlink', 'link', 'website', 'web site', 'site', 'hostname', 'server',
    '网址', '链接', '网站', '站点'
  ];
  private static readonly NOTES: string[] = [
    'notes', 'note', 'comment', 'comments', 'memo', 'description', '备注', '注释', '说明'
  ];

  // 扩展目标字段（KeePassXC CSV 导入）
  private static readonly GROUPS: string[] = ['group', 'grouping', 'folder', 'category', '分组', '文件夹', '类别'];
  private static readonly TOTPS: string[] = ['totp', 'otp', 'totp seed', '动态密码', '一次性密码'];
  private static readonly TAGS: string[] = ['tags', 'tag', '标签'];
  private static readonly ICONS: string[] = ['icon', '图标'];
  private static readonly EXPIRYS: string[] = ['expiry time', 'expires', 'expiration', 'expiry', '过期时间'];
  private static readonly LAST_MODIFIED: string[] = ['last modified', 'lastmodified', '修改时间', '更新时间'];
  private static readonly CREATED: string[] = ['created', 'created time', 'creation time', '创建时间'];

  /**
   * 将 CSV 表头名映射为目标字段（全阶段：精确 → 包含 → 前缀）
   * @param header 表头名
   * @returns 目标字段；无法识别时返回 undefined
   */
  static mapToTargetField(header: string): CsvTargetField | undefined {
    const match = ColumnNameMapper.mapWithSpecificity(header);
    return match !== undefined ? match.target : undefined;
  }

  /**
   * 精确同义词匹配（不含模糊阶段；引擎建议映射第一阶段使用）
   * @param header 表头名
   * @returns 目标字段；无法精确识别时返回 undefined
   */
  static mapExact(header: string): CsvTargetField | undefined {
    const normalized = ColumnNameMapper.normalize(header);
    if (normalized === '') {
      return undefined;
    }
    if (ColumnNameMapper.TITLES.indexOf(normalized) >= 0) {
      return CsvTargetField.TITLE;
    }
    if (ColumnNameMapper.USERNAMES.indexOf(normalized) >= 0) {
      return CsvTargetField.USERNAME;
    }
    if (ColumnNameMapper.PASSWORDS.indexOf(normalized) >= 0) {
      return CsvTargetField.PASSWORD;
    }
    if (ColumnNameMapper.URLS.indexOf(normalized) >= 0) {
      return CsvTargetField.URL;
    }
    if (ColumnNameMapper.NOTES.indexOf(normalized) >= 0) {
      return CsvTargetField.NOTES;
    }
    if (ColumnNameMapper.GROUPS.indexOf(normalized) >= 0) {
      return CsvTargetField.GROUP;
    }
    if (ColumnNameMapper.TOTPS.indexOf(normalized) >= 0) {
      return CsvTargetField.TOTP;
    }
    if (ColumnNameMapper.TAGS.indexOf(normalized) >= 0) {
      return CsvTargetField.TAGS;
    }
    if (ColumnNameMapper.ICONS.indexOf(normalized) >= 0) {
      return CsvTargetField.ICON;
    }
    if (ColumnNameMapper.EXPIRYS.indexOf(normalized) >= 0) {
      return CsvTargetField.EXPIRY_TIME;
    }
    if (ColumnNameMapper.LAST_MODIFIED.indexOf(normalized) >= 0) {
      return CsvTargetField.LAST_MODIFIED;
    }
    if (ColumnNameMapper.CREATED.indexOf(normalized) >= 0) {
      return CsvTargetField.CREATED;
    }
    return undefined;
  }

  /**
   * 全阶段匹配并返回命中特异性：精确 → 包含（KeePass 2.x 顺序）→ 前缀（最长命中）。
   * 带注释表头（「GROUP分组」「TITLE(标题)」「username用户名」）由前缀阶段识别；
   * matchedLength 为命中同义词长度，同目标多列冲突时取最长（最具体）者。
   * @param header 表头名
   * @returns 匹配结果；无法识别时返回 undefined
   */
  static mapWithSpecificity(header: string): ColumnMatch | undefined {
    const normalized = ColumnNameMapper.normalize(header);
    if (normalized === '') {
      return undefined;
    }
    const exact = ColumnNameMapper.mapExact(header);
    if (exact !== undefined) {
      return { target: exact, matchedLength: normalized.length };
    }
    // 包含（KeePass 2.x 顺序：password → username → url → notes）
    let containsMatch: ColumnMatch | undefined = undefined;
    let matchedLength = ColumnNameMapper.matchContains(ColumnNameMapper.PASSWORDS, normalized);
    if (matchedLength > 0) {
      containsMatch = { target: CsvTargetField.PASSWORD, matchedLength: matchedLength };
    } else {
      matchedLength = ColumnNameMapper.matchContains(ColumnNameMapper.USERNAMES, normalized);
      if (matchedLength > 0) {
        containsMatch = { target: CsvTargetField.USERNAME, matchedLength: matchedLength };
      } else {
        matchedLength = ColumnNameMapper.matchContains(ColumnNameMapper.URLS, normalized);
        if (matchedLength > 0) {
          containsMatch = { target: CsvTargetField.URL, matchedLength: matchedLength };
        } else {
          matchedLength = ColumnNameMapper.matchContains(ColumnNameMapper.NOTES, normalized);
          if (matchedLength > 0) {
            containsMatch = { target: CsvTargetField.NOTES, matchedLength: matchedLength };
          }
        }
      }
    }
    // 前缀（全部目标字段，最长命中优先）。包含命中作为基准：仅当某前缀同义词严格更长时才覆盖
    // （「totp动态密码」按 totp 判 TOTP 而非按子串「密码」误判 PASSWORD）；
    // 同长时保持包含阶段优先（'user password' 仍判 PASSWORD 的 KeePass 2.x 顺序回归）。
    let best: ColumnMatch | undefined = containsMatch;
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.GROUPS, CsvTargetField.GROUP, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.TITLES, CsvTargetField.TITLE, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.USERNAMES, CsvTargetField.USERNAME, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.PASSWORDS, CsvTargetField.PASSWORD, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.URLS, CsvTargetField.URL, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.NOTES, CsvTargetField.NOTES, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.TOTPS, CsvTargetField.TOTP, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.TAGS, CsvTargetField.TAGS, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.ICONS, CsvTargetField.ICON, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.EXPIRYS, CsvTargetField.EXPIRY_TIME, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.LAST_MODIFIED, CsvTargetField.LAST_MODIFIED, normalized);
    best = ColumnNameMapper.matchPrefix(best, ColumnNameMapper.CREATED, CsvTargetField.CREATED, normalized);
    return best;
  }

  private static normalize(header: string): string {
    return header.trim().toLowerCase();
  }

  private static matchContains(candidates: string[], normalized: string): number {
    for (const candidate of candidates) {
      if (normalized.includes(candidate)) {
        return candidate.length;
      }
    }
    return 0;
  }

  private static matchPrefix(best: ColumnMatch | undefined, candidates: string[],
    target: CsvTargetField, normalized: string): ColumnMatch | undefined {
    let result: ColumnMatch | undefined = best;
    for (const candidate of candidates) {
      if (normalized.startsWith(candidate) && (result === undefined || candidate.length > result.matchedLength)) {
        result = { target: target, matchedLength: candidate.length };
      }
    }
    return result;
  }
}
