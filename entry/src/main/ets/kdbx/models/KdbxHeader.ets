import { Any, Binary, VariantDictionaryItem } from './KdbxTypes';

/**
 * KDBX文件头部模型
 */
export interface KdbxHeaderModel {
  // 通用字段
  version: number;
  cipherId: Binary;
  compressionFlags: number;
  masterSeed: Binary;
  encryptionIV: Binary;
  innerRandomStreamId: number;
  publicCustomData?: Map<string, VariantDictionaryItem>;

  // KDBX4特有字段
  kdfParameters?: KdfParameters;

  // KDBX3.1特有字段
  transformSeed?: Binary;
  transformRounds?: number;
  protectedStreamKey?: Binary;
  streamStartBytes?: Binary;
}

/*
 * KDBX4特有字段
 */
export interface KdfParameters{
  uuid: Binary;
  iterations: number;
  salt: Binary;
  memory?: number;
  parallelism?: number;
  version?: number;
  rounds?: number;
}

/**
 * KDBX头部字段类型
 */
export enum KdbxHeaderFieldType {
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
 * KDF参数类型
 */
export enum KdfParameterType {
  END = 0,
  UUID = 1,
  SALT = 2,
  PARALLELISM = 3,
  MEMORY = 4,
  ITERATIONS = 5,
  VERSION = 6,
  SECRET_KEY = 7
}
