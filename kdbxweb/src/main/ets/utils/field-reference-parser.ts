import { FieldReference, FieldReferenceValue } from '../format/kdbx-field-reference';
import { KdbxContext } from '../format/kdbx-context';
import { KdbxEntry } from '../format/kdbx-entry';
import { KdbxUuid } from '../format/kdbx-uuid';
import { ProtectedValue } from '../crypto/protected-value';

/**
 * 字段引用解析器
 * 负责解析、格式化和解析KDBX字段引用
 */
export class FieldReferenceParser {
  /** 字段引用正则表达式 */
  private static readonly REF_REGEX = /^\{REF:([A-Za-z0-9_]+)@([^}]+)\}$/;

  /**
   * 解析字符串中的字段引用
   * @param text 要解析的文本
   * @returns FieldReference对象或null
   */
  static parseFieldRef(text: string): FieldReference | null {
    if (!text || typeof text !== 'string') {
      return null;
    }

    const match = text.match(this.REF_REGEX);
    if (!match) {
      return null;
    }

    const [_, field, entryUuid] = match;
    return { field, entryUuid };
  }

  /**
   * 检测文本是否为字段引用格式
   * @param text 要检测的文本
   * @returns 是否为字段引用
   */
  static isFieldReference(text: string | undefined | null): boolean {
    if (!text || typeof text !== 'string') {
      return false;
    }
    return this.REF_REGEX.test(text);
  }

  /**
   * 格式化字段引用为字符串
   * @param ref 字段引用对象
   * @returns 格式化的引用字符串
   */
  static formatFieldRef(ref: FieldReference): string {
    return `{REF:${ref.field}@${ref.entryUuid}}`;
  }

  /**
   * 解析字段引用为实际值
   * @param ref 字段引用对象
   * @param ctx Kdbx上下文
   * @param currentEntry 当前Entry（用于循环检测）
   * @param visitedStack 已访问的Entry UUID栈（用于循环检测）
   * @returns 解析后的值
   */
  static resolveFieldRef(
    ref: FieldReference,
    ctx: KdbxContext,
    currentEntry: KdbxEntry,
    visitedStack: Set<string> = new Set()
  ): string {
    // 1. 循环引用检测
    const currentUuid = currentEntry.uuid.id;
    if (visitedStack.has(currentUuid)) {
      // 检测到循环引用，返回空字符串
      return '';
    }
    visitedStack.add(currentUuid);

    try {
      // 2. 特殊标识符处理
      if (ref.entryUuid === 'T' || ref.entryUuid === 't') {
        // 模板引用 - 暂不实现
        return '';
      }

      // 3. 通过UUID查找Entry
      let entryUuid: KdbxUuid;
      try {
        entryUuid = new KdbxUuid(ref.entryUuid);
      } catch (e) {
        // 无效UUID格式，返回空字符串
        return '';
      }

      const referencedEntry = ctx.getEntryByUuid(entryUuid);

      if (!referencedEntry) {
        // 引用的Entry不存在
        return '';
      }

      // 4. 获取字段值
      const fieldValue = referencedEntry.getRawFieldValue(ref.field);

      if (fieldValue === undefined || fieldValue === null) {
        // 字段不存在
        return '';
      }

      // 5. 处理ProtectedValue
      if (fieldValue instanceof ProtectedValue) {
        return fieldValue.getText();
      }

      // 6. 处理嵌套引用
      if (typeof fieldValue === 'string' && this.isFieldReference(fieldValue)) {
        const nestedRef = this.parseFieldRef(fieldValue);
        if (nestedRef) {
          // 递归解析嵌套引用，传入新的visitedStack
          const newVisitedStack = new Set(visitedStack);
          return this.resolveFieldRef(nestedRef, ctx, referencedEntry, newVisitedStack);
        }
      }

      // 7. 处理FieldReferenceValue（已在内存中的引用对象）
      if (typeof fieldValue === 'object' && 'ref' in fieldValue) {
        const nestedRefValue = fieldValue as FieldReferenceValue;
        const newVisitedStack = new Set(visitedStack);
        return this.resolveFieldRef(nestedRefValue.ref, ctx, referencedEntry, newVisitedStack);
      }

      // 8. 普通字符串或其他类型
      if (typeof fieldValue === 'string') {
        return fieldValue;
      }

      // 9. 其他未知类型，返回空字符串
      return '';
    } catch (e) {
      // 解析失败，返回空字符串
      return '';
    }
  }

  /**
   * 解析字段引用为实际值（简化版，不处理循环检测）
   * @param ref 字段引用对象
   * @param ctx Kdbx上下文
   * @param currentEntry 当前Entry
   * @returns 解析后的值
   */
  static resolveFieldRefSimple(
    ref: FieldReference,
    ctx: KdbxContext,
    currentEntry: KdbxEntry
  ): string {
    return this.resolveFieldRef(ref, ctx, currentEntry);
  }

  /**
   * 批量解析Entry中的所有字段引用
   * @param entry 要解析的Entry
   * @param ctx Kdbx上下文
   * @returns 解析后的字段值映射
   */
  static resolveAllFieldRefs(
    entry: KdbxEntry,
    ctx: KdbxContext
  ): Map<string, string> {
    const resolvedMap = new Map<string, string>();

    for (const [fieldName, fieldValue] of entry.fields) {
      const resolvedValue = entry.getFieldValue(fieldName, ctx);
      if (resolvedValue !== undefined && resolvedValue !== null) {
        resolvedMap.set(fieldName, resolvedValue);
      }
    }

    return resolvedMap;
  }

  /**
   * 检测字段值是否包含引用
   * @param fieldValue 字段值
   * @returns 是否包含引用
   */
  static containsFieldReference(fieldValue: unknown): boolean {
    if (!fieldValue) {
      return false;
    }

    // 字符串中的引用格式
    if (typeof fieldValue === 'string') {
      return this.isFieldReference(fieldValue);
    }

    // 内存中的引用对象
    if (typeof fieldValue === 'object' && 'ref' in fieldValue) {
      return true;
    }

    return false;
  }

  /**
   * 获取字段引用的目标Entry UUID
   * @param fieldValue 字段值
   * @returns Entry UUID字符串或null
   */
  static getReferencedEntryUuid(fieldValue: unknown): string | null {
    if (!fieldValue) {
      return null;
    }

    // 从字符串中解析
    if (typeof fieldValue === 'string') {
      const ref = this.parseFieldRef(fieldValue);
      return ref ? ref.entryUuid : null;
    }

    // 从对象中获取
    if (typeof fieldValue === 'object' && 'ref' in fieldValue) {
      const refValue = fieldValue as FieldReferenceValue;
      return refValue.ref.entryUuid;
    }

    return null;
  }
}
