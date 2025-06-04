/**
 * KDBX4 基础类型定义
 */

/**
 * UUID类型
 * 用于唯一标识数据库中的条目、组等对象
 */
export type UUID = string;

/**
 * 时间戳类型
 * 用于记录各种时间信息，如创建时间、修改时间等
 */
export type Timestamp = number;

/**
 * 二进制数据类型
 * 用于存储加密相关的二进制数据和附件
 */
export type Binary = ArrayBuffer;
