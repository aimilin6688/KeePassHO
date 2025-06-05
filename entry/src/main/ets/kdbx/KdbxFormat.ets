/**
 * KDBX文件格式定义
 */

/**
 * 头部字段ID
 */
export enum HeaderFieldID {
  END = 0,
  COMMENT = 1,
  CIPHER_ID = 2,
  COMPRESSION_FLAGS = 3,
  MASTER_SEED = 4,
  TRANSFORM_SEED = 5,
  TRANSFORM_ROUNDS = 6,
  ENCRYPTION_IV = 7,
  PROTECTED_STREAM_KEY = 8,
  STREAM_START_BYTES = 9,
  INNER_RANDOM_STREAM_ID = 10,
  KDF_PARAMETERS = 11,
  PUBLIC_CUSTOM_DATA = 12
}

/**
 * 压缩标志
 */
export enum CompressionFlags {
  NONE = 0,
  GZIP = 1
}

/**
 * 内部随机流ID
 */
export enum InnerRandomStreamID {
  NONE = 0,
  ARC4VARIANT = 1,
  SALSA20 = 2,
  CHACHA20 = 3
}

/**
 * KDBX版本
 */
export enum KdbxVersion {
  V3 = 0x00030001,
  V4 = 0x00040000
}

/**
 * 字段类型
 */
export enum FieldType {
  STANDARD = 0,
  CUSTOM = 1
}

/**
 * 字段保护类型
 */
export enum FieldProtection {
  NONE = 0,
  PROTECTED = 1
}


