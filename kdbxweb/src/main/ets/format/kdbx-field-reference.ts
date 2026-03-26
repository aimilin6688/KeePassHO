import { Kdbx, KdbxEntry, KdbxGroup, ProtectedValue } from '..';


export interface FieldReference {
  /** 要获取的字段代码 (T/U/P/A/N/I) */
  wantedField: string;

  /** 搜索字段代码 (T/U/P/A/N/I/O) */
  searchIn: string;

  /** 搜索文本 */
  searchText: string;
}

export class KdbxFieldReference {
  /** 标准字段名集合 */
  private static readonly STANDARD_FIELDS = new Set(['Title', 'UserName', 'Password', 'URL', 'Notes']);

  /** 字段引用正则表达式 - 支持嵌入引用 */
  private static readonly REF_REGEX = /\{REF:([A-Za-z])@([A-Za-z]):([^}]+)\}/gi;

  /** 本地占位符正则表达式 {S:FieldName} */
  private static readonly LOCAL_PLACEHOLDER_REGEX = /\{S:([^}]+)\}/gi;

  /**
   * 有效的WantedField代码列表
   * O不能作为WantedField
   */
  private static readonly ValidWantedFieldCodes = ['T', 'U', 'P', 'A', 'N', 'I'] as const;

  /**
   * 有效的SearchIn代码列表
   * 包含O，可用于搜索自定义字段
   */
  private static readonly ValidSearchInCodes = ['T', 'U', 'P', 'A', 'N', 'I', 'O'] as const;


  private static readonly FieldCodeToName: Readonly<Record<string, string>> = {
    'T': 'Title',
    'U': 'UserName',
    'P': 'Password',
    'A': 'URL',
    'N': 'Notes',
    'I': 'UUID'
  };

  /**
   * 检查代码是否可以作为WantedField
   * O代码不能用于获取值
   * @param code 字段代码
   * @returns 是否可作为WantedField
   */
  private static isValidWantedField(code: string): boolean {
    return this.ValidWantedFieldCodes.includes(code.toUpperCase() as typeof this.ValidWantedFieldCodes[number]);
  }

  /**
   * 检查代码是否可以作为SearchIn
   * @param code 字段代码
   * @returns 是否可作为SearchIn
   */
  private static isValidSearchIn(code: string): boolean {
    return this.ValidSearchInCodes.includes(code.toUpperCase() as typeof this.ValidSearchInCodes[number]);
  }

  /**
   * 字符串是否是-引用字符串
   * @param text 引用字符串
   * @returns  boolean
   */
  private static isFieldReferenceText(text: string): boolean {
    if (!text) {
      return false;
    }
    this.REF_REGEX.lastIndex = 0;
    return this.REF_REGEX.test(text);
  }


  /**
   * 检测文本是否包含本地占位符 {S:FieldName}
   * @param text 要检测的文本
   * @returns 是否包含本地占位符
   */
  private static isLocalPlaceholder(text: string): boolean {
    if (!text) {
      return false;
    }
    this.LOCAL_PLACEHOLDER_REGEX.lastIndex = 0;
    return this.LOCAL_PLACEHOLDER_REGEX.test(text);
  }

  /**
   * 解析字符串中所有引用并替换
   * 支持嵌入引用，如 "https://example.com?user={REF:U@T:MySite}"
   * 同时支持本地占位符 {S:FieldName}
   * @param text 包含引用的文本
   * @param kdbx Kdbx数据库
   * @param currentEntry 当前Entry
   * @param visitedStack 已访问的Entry UUID栈（用于循环检测）
   * @returns 解析后的文本
   */
  public static resolveFieldRefsInText(text: string, kdbx: Kdbx, currentEntry: KdbxEntry, visitedStack: Set<string> = new Set()): string {
    if (!text || typeof text !== 'string') {
      return text || '';
    }

    // 非引用字符串，直接返回
    if (!this.isFieldReferenceText(text) && !this.isLocalPlaceholder(text)) {
      return text;
    }

    // 先解析本地占位符
    let result = this.resolveLocalPlaceholders(text, currentEntry);

    // 再解析字段引用
    this.REF_REGEX.lastIndex = 0;
    result = result.replace(this.REF_REGEX, (match) => {
      const ref = this.parseFieldRef(match);
      if (!ref) {
        return match;
      }
      const resolved = this.resolveFieldRef(ref, kdbx, currentEntry, visitedStack);
      return resolved !== null ? resolved : match;
    });

    return result || text;
  }


  /**
   * 解析本地占位符 {S:FieldName}
   * @param text 包含占位符的文本
   * @param entry 当前Entry
   * @returns 解析后的文本
   */
  private static resolveLocalPlaceholders(text: string, entry: KdbxEntry): string {
    this.LOCAL_PLACEHOLDER_REGEX.lastIndex = 0;
    return text.replace(this.LOCAL_PLACEHOLDER_REGEX, (match, fieldName: string) => {
      const fieldValue = entry.fields.get(fieldName);
      if (!fieldValue) {
        return match;
      }
      if (fieldValue instanceof ProtectedValue) {
        return fieldValue.getText();
      }
      if (typeof fieldValue === 'string') {
        return fieldValue;
      }
      return match;
    });
  }

  /**
   * 解析字段引用字符串
   * @param text 要解析的文本
   * @returns FieldReference对象或null
   */
  private static parseFieldRef(text: string): FieldReference | null {
    if (!text || typeof text !== 'string') {
      return null;
    }

    // 重置正则表达式的lastIndex
    this.REF_REGEX.lastIndex = 0;
    const match = this.REF_REGEX.exec(text);

    if (!match) {
      return null;
    }

    const [_, wantedField, searchIn, searchText] = match;

    // 验证字段代码有效性
    if (!KdbxFieldReference.isValidWantedField(wantedField)) {
      return null;
    }

    if (!KdbxFieldReference.isValidSearchIn(searchIn)) {
      return null;
    }

    return {
      wantedField: wantedField.toUpperCase(),
      searchIn: searchIn.toUpperCase(),
      searchText: searchText
    };
  }

  /**
   * 解析字段引用为实际值
   * @param ref 字段引用对象
   * @param ctx Kdbx上下文
   * @param currentEntry 当前Entry（用于循环检测）
   * @param visitedStack 已访问的Entry UUID栈（用于循环检测）
   * @returns 解析后的值
   */
  private static resolveFieldRef(ref: FieldReference, kdbx: Kdbx, currentEntry?: KdbxEntry, visitedStack: Set<string> = new Set()): string {
    // 循环引用检测
    const currentUuid = currentEntry ? currentEntry.uuid.id : '';
    if (visitedStack.has(currentUuid)) {
      return null;
    }

    const newVisitedStack = new Set(visitedStack);
    newVisitedStack.add(currentUuid);

    try {
      // 查找目标Entry
      const targetEntry = this.findTargetEntry(ref, kdbx);
      if (!targetEntry) {
        return null;
      }
      // 获取字段值
      return this.getFieldValue(targetEntry, ref.wantedField, kdbx, newVisitedStack);
    } catch (e) {
      return null;
    }
  }


  /**
   * 获取字段值
   * @param entry 目标Entry
   * @param fieldCode 字段代码
   * @param ctx Kdbx上下文
   * @param visitedStack 已访问的Entry栈
   * @returns 字段值
   */
  private static getFieldValue(entry: KdbxEntry, fieldCode: string, kdbx: Kdbx, visitedStack: Set<string>): string {
    // 特殊处理UUID字段 - 返回UUID的base64编码字符串
    if (fieldCode === "I") {
      return entry.uuid.toString();
    }

    const fieldName = this.FieldCodeToName[fieldCode];
    if (!fieldName) {
      return '';
    }
    // 获取字段原始值
    const rawValue = entry.fields.get(fieldName);
    if (rawValue === undefined || rawValue === null) {
      return '';
    }
    // ProtectedValue
    if (rawValue instanceof ProtectedValue) {
      return rawValue.getText();
    }
    return this.resolveFieldRefsInText(rawValue, kdbx, entry, visitedStack);
  }

  /**
   * 标准引用字段查询方法
   * 支持所有KeePass字段引用类型的搜索，并缓存结果
   *
   * @param ctx Kdbx上下文
   * @param query 查询参数 {searchIn, searchText}
   * @returns 匹配的Entry或undefined
   *
   * 支持的searchIn代码：
   * - T: 通过Title搜索
   * - U: 通过UserName搜索
   * - P: 通过Password搜索
   * - A: 通过URL搜索
   * - N: 通过Notes搜索
   * - I: 通过UUID精确查找
   * - O: 通过自定义字段名搜索（查找包含该字段名的Entry）
   */
  private static findTargetEntry(ref: FieldReference, kdbx: Kdbx): KdbxEntry | null {
    const { searchIn, searchText } = ref;
    const code = searchIn.toUpperCase();
    // I代码：通过UUID精确查找
    if (code === "I") {
      return this.getEntryByUuidString(kdbx, searchText);
    }

    // O代码：通过自定义字段名搜索
    if (code === "O") {
      return this.findEntryByCustomFieldName(kdbx, searchText);
    }

    // 标准字段搜索
    const fieldName = this.FieldCodeToName[code];
    if (fieldName) {
      return this.findEntryByStandardField(kdbx, fieldName, searchText);
    }
    return null;
  }

  /**
   * 通过UUID查找Entry
   * @param uuid Entry UUID
   * @returns Entry对象或undefined
   */
  private static getEntryByUuidString(kdbx: Kdbx, searchText: string): KdbxEntry | undefined {
    for (const group of kdbx.groups) {
      const entry = KdbxFieldReference.searchInGroupByField(group, "I", searchText, 'UUID');
      if (entry) {
        return entry;
      }
    }
    return undefined;
  }

  /**
   * 通过自定义字段名搜索Entry
   * 查找包含指定名称自定义字段的Entry
   */
  private static findEntryByCustomFieldName(kdbx: Kdbx, customFieldName: string): KdbxEntry | undefined {
    for (const group of kdbx.groups) {
      const entry = KdbxFieldReference.searchInGroupByField(group, customFieldName, '', 'CustomField');
      if (entry) {
        return entry;
      }
    }
    return undefined;
  }

  /**
   * 通过标准字段值搜索Entry
   */
  private static findEntryByStandardField(kdbx: Kdbx,fieldName: string, searchText: string): KdbxEntry | undefined {
    for (const group of kdbx.groups) {
      const entry = KdbxFieldReference.searchInGroupByField(group, fieldName, searchText, 'StandardField');
      if (entry) {
        return entry;
      }
    }
    return undefined;
  }


  /**
   * 在Group中搜索Entry（统一搜索方法）
   * @param group Group对象
   * @param fieldName 字段名
   * @param searchText 搜索文本
   * @param isCustomField 是否为自定义字段搜索
   * @returns 匹配的Entry或undefined
   */
  private static searchInGroupByField(group: KdbxGroup, fieldName: string, searchText: string, matchType: string): KdbxEntry | undefined {
    for (const entry of group.entries) {
      let matched = null;
      if (matchType === 'UUID') {
        matched = this.matchUuid(entry, searchText);
      } else if (matchType === 'StandardField') {
        matched = this.matchStandardField(entry, fieldName, searchText);
      } else if (matchType === 'CustomField') {
        matched = this.matchCustomField(entry, fieldName);
      }
      if (matched) {
        return entry;
      }
    }

    // 递归检查子Group
    for (const subgroup of group.groups) {
      const found = this.searchInGroupByField(subgroup, fieldName, searchText, matchType);
      if (found) {
        return found;
      }
    }
    return undefined;
  }

  /**
   * 匹配UUID
   */
  private static matchUuid(entry: KdbxEntry, uuid: string): boolean {
    return entry.uuid.id === uuid;
  }

  /**
   * 匹配标准字段
   */
  private static matchStandardField(entry: KdbxEntry, fieldName: string, searchText: string): boolean {
    const fieldValue = entry.fields.get(fieldName);
    if (!fieldValue) {
      return false;
    }

    let value: string;
    if (fieldValue instanceof ProtectedValue) {
      value = fieldValue.getText();
    } else if (typeof fieldValue === 'string') {
      value = fieldValue;
    } else {
      return false;
    }

    return value === searchText;
  }

  /**
   * 匹配自定义字段
   * 检查Entry是否包含指定名称的自定义字段
   */
  private static matchCustomField(entry: KdbxEntry, customFieldName: string): boolean {
    for (const [fieldName] of entry.fields) {
      if (!KdbxFieldReference.STANDARD_FIELDS.has(fieldName) && fieldName === customFieldName) {
        return true;
      }
    }
    return false;
  }
}