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
  V3_1 = 0x00030001,
  V4 = 0x00040000,
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

/**
 * KDF算法
 */
export enum KdfAlgorithm {
  AES_KDF = 'c9d9f39a-628a-4460-bf74-0d08c18a4fea',
  ARGON2 = 'ef636ddf-8c29-444b-91f7-a9a403e30a0c',
  ARGON2D = '9e298b19-56db-4773-b23d-fc3ec6f0a1e6',
  ARGON2ID = '3fa36bb2-34d6-4daf-bd3b-93bc219748c4'
}

