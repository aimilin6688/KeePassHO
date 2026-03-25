import { KdbxUuid } from './kdbx-uuid';

/**
 * 字段引用结构
 * 表示一个Entry字段到另一个Entry字段的引用
 */
export interface FieldReference {
    /** 引用的字段名（如：Title, UserName, Password, URL, Notes等） */
    field: string;
    /** 引用的Entry UUID（Base64编码字符串） */
    entryUuid: string;
}

/**
 * 字段引用值
 * 包装字段引用和可选的解析结果
 */
export interface FieldReferenceValue {
    /** 字段引用信息 */
    ref: FieldReference;
    /** 可选的解析值（缓存） */
    resolvedValue?: string;
}

/**
 * 检查值是否为字段引用
 * @param value 要检查的值
 * @returns 是否为字段引用
 */
export function isFieldReferenceValue(value: unknown): value is FieldReferenceValue {
    return typeof value === 'object' && value !== null && 'ref' in value;
}

/**
 * 检查值是否为字段引用对象
 * @param value 要检查的值
 * @returns 是否为字段引用对象
 */
export function isFieldReference(value: unknown): value is FieldReference {
    return typeof value === 'object' && value !== null &&
        'field' in value && 'entryUuid' in value &&
        typeof (value as FieldReference).field === 'string' &&
        typeof (value as FieldReference).entryUuid === 'string';
}

/**
 * 创建字段引用值
 * @param field 字段名
 * @param entryUuid Entry UUID字符串
 * @returns 字段引用值
 */
export function createFieldReferenceValue(field: string, entryUuid: string): FieldReferenceValue {
    return {
        ref: { field, entryUuid }
    };
}

/**
 * 创建字段引用值（使用KdbxUuid）
 * @param field 字段名
 * @param uuid Entry UUID
 * @returns 字段引用值
 */
export function createFieldReferenceValueFromUuid(field: string, uuid: KdbxUuid): FieldReferenceValue {
    return {
        ref: { field, entryUuid: uuid.id }
    };
}
