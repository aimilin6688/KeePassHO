import { UUID, Binary } from './KdbxTypes';

/**
 * KDBX4 文件头部实体定义
 * 包含数据库文件的基本信息和加密参数
 */
export interface KdbxHeader {
  /**
   * 文件签名1
   * 用于标识文件格式
   */
  signature1: number;

  /**
   * 文件签名2
   * 用于标识文件格式
   */
  signature2: number;

  /**
   * 版本号
   * 标识KDBX文件格式的版本
   */
  version: number;

  /**
   * 加密算法ID
   * 用于标识使用的加密算法
   */
  cipherID: UUID;

  /**
   * 压缩标志
   * 指示是否使用压缩以及使用的压缩算法
   */
  compressionFlags: number;

  /**
   * 主种子
   * 用于密钥派生
   */
  masterSeed: Binary;

  /**
   * 转换种子
   * 用于密钥转换
   */
  transformSeed: Binary;

  /**
   * 转换轮数
   * 密钥转换的迭代次数
   */
  transformRounds: number;

  /**
   * 加密IV
   * 初始化向量，用于加密
   */
  encryptionIV: Binary;

  /**
   * 受保护流密钥
   * 用于保护敏感字段
   */
  protectedStreamKey: Binary;

  /**
   * 流起始字节
   * 用于验证解密是否成功
   */
  streamStartBytes: Binary;

  /**
   * 内部随机流ID
   * 用于标识内部随机流的类型
   */
  innerRandomStreamID: number;
}
