/**
 * KDBX4格式常量定义
 */

// KDBX4文件签名
export const KDBX_IDENTIFIER = 0x9AA2D903;
export const KDBX_VERSION_4 = 0x00040000;

// KDBX4文件头字段ID
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

// 压缩算法
export enum CompressionAlgorithm {
  NONE = 0,
  GZIP = 1
}

// 内部随机流ID
export enum InnerRandomStreamID {
  NONE = 0,
  ARC4_VARIANT = 1,
  SALSA20 = 2,
  CHACHA20 = 3
}

// KDF算法UUID
export const KDF_AES = new Uint8Array([
  0x7C, 0x02, 0xBB, 0x82, 0x79, 0xA7, 0x4A, 0xC0,
  0x92, 0x7D, 0x11, 0x4A, 0x00, 0x64, 0x82, 0x38
]);

export const KDF_ARGON2D = new Uint8Array([
  0xEF, 0x63, 0x6D, 0xDF, 0x8C, 0x29, 0x44, 0x4B,
  0x91, 0xF7, 0xA9, 0xA4, 0x03, 0xE3, 0x0A, 0x0C
]);

export const KDF_ARGON2ID = new Uint8Array([
  0x9E, 0x29, 0x8B, 0x19, 0x56, 0xDB, 0x47, 0x73,
  0xB2, 0x3D, 0xFC, 0x3E, 0xC6, 0xF0, 0xA1, 0xE6
]);

// KDF参数键名
export enum KdfParamName {
  UUID = '$UUID',
  SALT = 'S',
  ROUNDS = 'R',
  MEMORY = 'M',
  PARALLELISM = 'P',
  VERSION = 'V',
  SECRET_KEY = 'K'
}

// 错误码
export enum KdbxError {
  INVALID_HEADER = 'Invalid header',
  INVALID_SIGNATURE = 'Invalid signature',
  UNSUPPORTED_VERSION = 'Unsupported version',
  UNSUPPORTED_CIPHER = 'Unsupported cipher',
  CORRUPTED_FILE = 'Corrupted file',
  INVALID_KEY = 'Invalid key',
  DECRYPTION_FAILED = 'Decryption failed'
}
