import { CsvTargetField } from './CsvImportModels';

/**
 * 列名映射器
 * 同义词字典移植自 KeePass 2.x ImportUtil.MapNameToStandardField（精确匹配 + 模糊子串匹配），
 * 并扩展 KeePassXC CSV 导入目标字段（Group/TOTP/Tags/Icon/Last Modified/Created）。
 */
export class ColumnNameMapper {
  // KeePass 2.x ImportUtil 同义词表
  private static readonly TITLES: string[] = [
    'title', 'account', 'item name', 'itemname', 'subject', 'service', 'type'
  ];
  private static readonly USERNAMES: string[] = [
    'user name', 'username', 'login', 'email', 'e-mail', 'user id', 'userid', 'name', 'user'
  ];
  private static readonly PASSWORDS: string[] = [
    'password', 'passphrase', 'pass', 'pwd', 'pw', 'pin', 'secret'
  ];
  private static readonly URLS: string[] = [
    'url', 'hyper link', 'hyperlink', 'link', 'website', 'web site', 'site', 'hostname', 'server'
  ];
  private static readonly NOTES: string[] = [
    'notes', 'note', 'comment', 'comments', 'memo', 'description'
  ];

  // 扩展目标字段（KeePassXC CSV 导入）
  private static readonly GROUPS: string[] = ['group', 'grouping', 'folder', 'category'];
  private static readonly TOTPS: string[] = ['totp', 'otp', 'totp seed'];
  private static readonly TAGS: string[] = ['tags', 'tag'];
  private static readonly ICONS: string[] = ['icon'];
  private static readonly LAST_MODIFIED: string[] = ['last modified', 'lastmodified'];
  private static readonly CREATED: string[] = ['created', 'created time', 'creation time'];

  /**
   * 将 CSV 表头名映射为目标字段
   * @param header 表头名
   * @returns 目标字段；无法识别时返回 undefined
   */
  static mapToTargetField(header: string): CsvTargetField | undefined {
    const normalized = header.trim().toLowerCase();
    if (normalized === '') {
      return undefined;
    }

    // 精确匹配（KeePass 同义词 + 扩展目标字段）
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
    if (ColumnNameMapper.LAST_MODIFIED.indexOf(normalized) >= 0) {
      return CsvTargetField.LAST_MODIFIED;
    }
    if (ColumnNameMapper.CREATED.indexOf(normalized) >= 0) {
      return CsvTargetField.CREATED;
    }

    // 模糊子串匹配（KeePass 2.x 顺序：password → username → url → notes）
    if (ColumnNameMapper.containsSubstring(ColumnNameMapper.PASSWORDS, normalized)) {
      return CsvTargetField.PASSWORD;
    }
    if (ColumnNameMapper.containsSubstring(ColumnNameMapper.USERNAMES, normalized)) {
      return CsvTargetField.USERNAME;
    }
    if (ColumnNameMapper.containsSubstring(ColumnNameMapper.URLS, normalized)) {
      return CsvTargetField.URL;
    }
    if (ColumnNameMapper.containsSubstring(ColumnNameMapper.NOTES, normalized)) {
      return CsvTargetField.NOTES;
    }
    return undefined;
  }

  private static containsSubstring(candidates: string[], normalized: string): boolean {
    for (const candidate of candidates) {
      if (normalized.includes(candidate)) {
        return true;
      }
    }
    return false;
  }
}
