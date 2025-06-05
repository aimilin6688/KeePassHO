import { KdbxDatabase } from './models/KdbxDatabase';
import { KdbxCredentials } from './KdbxCredentials';
import { KdbxHeader } from './KdbxHeader';
import { KdbxSerializer } from './KdbxSerializer';
import { KdbxError, KdbxErrorCode } from './KdbxError';
import { Binary } from './models/KdbxTypes';
import { KdbxGroup } from './models/KdbxGroup';
import { KdbxEntry } from './models/KdbxEntry';

/**
 * KDBX文件类
 */
export class KdbxFile {
  /**
   * 数据库
   */
  database: KdbxDatabase;
  /**
   * 头部信息
   */
  header: KdbxHeader;
  /**
   * 凭证
   */
  credentials: KdbxCredentials;

  /**
   * 构造函数
   * @param db 数据库
   * @param header 头部信息
   * @param credentials 凭证
   */
  constructor(db: KdbxDatabase, header: KdbxHeader, credentials: KdbxCredentials) {
    this.database = db;
    this.header = header;
    this.credentials = credentials;
  }

  /**
   * 创建新数据库
   * @param credentials 凭证
   * @returns KDBX文件
   */
  static createNew(credentials: KdbxCredentials): KdbxFile {
    const db = new KdbxDatabase();
    const header = new KdbxHeader();
    header.generateRandomFields();
    return new KdbxFile(db, header, credentials);
  }

  /**
   * 从二进制数据加载KDBX文件
   * @param data 二进制数据
   * @param credentials 凭证
   * @returns KDBX文件
   */
  static async loadFromBinary(data: Binary, credentials: KdbxCredentials): Promise<KdbxFile> {
    try {
      // 解析头部
      const header = new KdbxHeader();
      let offset = header.readFromBinary(data);

      // 验证凭证
      const compositeKey = await credentials.getCompositeKey();
      if (!compositeKey) {
        throw new KdbxError(
          KdbxErrorCode.INVALID_CREDENTIALS,
          '无效的凭证'
        );
      }

      // TODO: 解密文件内容
      // 这里需要实现解密逻辑

      // 解析XML内容
      const xmlData = new TextDecoder().decode(data.slice(offset));
      const serializer = new KdbxSerializer(
        header.protectedStreamKey,
        header.innerRandomStreamId
      );
      const db = serializer.deserializeFromXml(xmlData);

      return new KdbxFile(db, header, credentials);
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.FILE_CORRUPTED,
        '加载KDBX文件失败'
      );
    }
  }

  /**
   * 保存为二进制数据
   * @returns 二进制数据
   */
  async saveToBinary(): Promise<Binary> {
    try {
      // 序列化XML内容
      const serializer = new KdbxSerializer(
        this.header.protectedStreamKey,
        this.header.innerRandomStreamId
      );
      const xml = serializer.serializeToXml(this.database);

      // 生成头部数据
      const headerData = this.header.writeToBinary();

      // TODO: 加密文件内容
      // 这里需要实现加密逻辑

      // 合并头部和内容
      const result = new Uint8Array(headerData.length + xml.length);
      result.set(headerData, 0);
      result.set(new TextEncoder().encode(xml), headerData.length);

      return result;
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.FILE_CORRUPTED,
        '保存KDBX文件失败'
      );
    }
  }

  /**
   * 更改主密码
   * @param newCredentials 新凭证
   */
  async changeMasterKey(newCredentials: KdbxCredentials): Promise<void> {
    try {
      // 验证新凭证
      const newCompositeKey = await newCredentials.getCompositeKey();
      if (!newCompositeKey) {
        throw new KdbxError(
          KdbxErrorCode.INVALID_CREDENTIALS,
          '无效的新凭证'
        );
      }

      // 更新凭证
      this.credentials = newCredentials;

      // 更新头部信息
      this.header.masterSeed = KdbxUtils.generateRandom(new Uint8Array(32));
      this.header.masterKeyChanged = new Date();
    } catch (error) {
      throw KdbxError.wrap(
        error as Error,
        KdbxErrorCode.OPERATION_FAILED,
        '更改主密码失败'
      );
    }
  }

  /**
   * 获取数据库统计信息
   * @returns 统计信息
   */
  getStatistics() {
    return this.database.getStatistics();
  }

  /**
   * 搜索条目
   * @param query 搜索关键词
   * @param options 搜索选项
   * @returns 匹配的条目列表
   */
  searchEntries(query: string, options: {
    caseSensitive?: boolean;
    includeProtected?: boolean;
    fieldNames?: string[];
    searchInGroups?: Binary[];
    excludeGroups?: Binary[];
  } = {}) {
    return this.database.searchEntries(query, options);
  }

  /**
   * 创建新组
   * @param name 组名
   * @param parentGroup 父组
   * @returns 新创建的组
   */
  createGroup(name: string, parentGroup?: KdbxGroup) {
    return this.database.createGroup(name, parentGroup);
  }

  /**
   * 创建新条目
   * @param parentGroup 父组
   * @returns 新创建的条目
   */
  createEntry(parentGroup?: KdbxGroup) {
    return this.database.createEntry(parentGroup);
  }

  /**
   * 查找组
   * @param uuid 组UUID
   * @returns 找到的组或undefined
   */
  findGroup(uuid: Binary) {
    return this.database.findGroup(uuid);
  }

  /**
   * 查找条目
   * @param uuid 条目UUID
   * @returns 找到的条目或undefined
   */
  findEntry(uuid: Binary) {
    return this.database.findEntry(uuid);
  }

  /**
   * 移动组
   * @param group 要移动的组
   * @param newParent 新的父组
   * @returns 是否成功
   */
  moveGroup(group: KdbxGroup, newParent: KdbxGroup) {
    return this.database.moveGroup(group, newParent);
  }

  /**
   * 移动条目
   * @param entry 要移动的条目
   * @param newParent 新的父组
   * @returns 是否成功
   */
  moveEntry(entry: KdbxEntry, newParent: KdbxGroup) {
    return this.database.moveEntry(entry, newParent);
  }

  /**
   * 删除组
   * @param group 要删除的组
   * @param useRecycleBin 是否使用回收站
   * @returns 是否成功
   */
  deleteGroup(group: KdbxGroup, useRecycleBin: boolean = true) {
    return this.database.deleteGroup(group, useRecycleBin);
  }

  /**
   * 删除条目
   * @param entry 要删除的条目
   * @param useRecycleBin 是否使用回收站
   * @returns 是否成功
   */
  deleteEntry(entry: KdbxEntry, useRecycleBin: boolean = true) {
    return this.database.deleteEntry(entry, useRecycleBin);
  }

  /**
   * 清空回收站
   * @returns 是否成功
   */
  emptyRecycleBin() {
    return this.database.emptyRecycleBin();
  }
}
