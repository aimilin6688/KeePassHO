import { Binary, DatabaseStatistics, DeletedObject, GroupSearchFieldOptions, Meta, UUID } from './KdbxTypes';
import { KdbxGroup } from './KdbxGroup';
import { KdbxEntry } from './KdbxEntry';
import { InnerRandomStreamID } from '../KdbxFormat';
import { KdbxUtils } from '../utils/KdbxUtils';

/**
 * KeePass数据库
 */
export class KdbxDatabase {
  /**
   * 数据库元数据
   */
  meta: Meta;
  /**
   * 根组
   */
  root: KdbxGroup;
  /**
   * 已删除对象列表
   */
  deletedObjects: DeletedObject[] = [];
  /**
   * 数据库版本
   */
  version: number;
  /**
   * 内部随机流ID
   */
  innerRandomStreamId: InnerRandomStreamID;
  /**
   * 保护流密钥
   */
  protectedStreamKey: Binary;

  /**
   * 构造函数
   * @param version 数据库版本
   */
  constructor(version: number = 0x00040000) {
    this.version = version;
    this.innerRandomStreamId = InnerRandomStreamID.CHACHA20;
    this.protectedStreamKey = KdbxUtils.generateRandom(new Uint8Array(32));

    // 创建根组
    const rootUuid = KdbxUtils.generateRandom(new Uint8Array(16));
    this.root = new KdbxGroup(KdbxUtils.bytesToStr(rootUuid), 'Root');

    // 初始化元数据
    this.meta = {
      databaseName: '新数据库',
      databaseDescription: '',
      defaultUserName: '',
      historyMaxItems: 10,
      historyMaxSize: 6 * 1024 * 1024, // 6MB
      recycleBinEnabled: true,
      recycleBinUUID: KdbxUtils.bytesToStr(KdbxUtils.generateRandom(new Uint8Array(16))),
      recycleBinChanged: new Date(),
      masterKeyChanged: new Date(),
      memoryProtection: {
        protectTitle: false,
        protectUserName: false,
        protectPassword: true,
        protectUrl: false,
        protectNotes: false
      },
      customIcons: new Map()
    };

    // 创建回收站
    if (this.meta.recycleBinEnabled && this.meta.recycleBinUUID) {
      const recycleBin = new KdbxGroup(this.meta.recycleBinUUID, '回收站');
      recycleBin.icon = { id: 43 }; // 回收站图标
      this.root.addGroup(recycleBin);
    }
  }

  /**
   * 创建新组
   * @param name 组名
   * @param parentGroup 父组
   * @returns 新创建的组
   */
  createGroup(name: string, parentGroup: KdbxGroup = this.root): KdbxGroup {
    const uuid = KdbxUtils.bytesToStr(KdbxUtils.generateRandom(new Uint8Array(16)));
    const group = new KdbxGroup(uuid, name);
    parentGroup.addGroup(group);
    return group;
  }

  /**
   * 创建新条目
   * @param parentGroup 父组
   * @returns 新创建的条目
   */
  createEntry(parentGroup: KdbxGroup = this.root): KdbxEntry {
    const uuid = KdbxUtils.bytesToStr(KdbxUtils.generateRandom(new Uint8Array(16)));
    const entry = new KdbxEntry(uuid, parentGroup.uuid);
    parentGroup.addEntry(entry);
    return entry;
  }

  /**
   * 查找组
   * @param uuid 组UUID
   * @returns 找到的组或undefined
   */
  findGroup(uuid: UUID): KdbxGroup | undefined {
    return this.root.findGroup(uuid);
  }

  /**
   * 查找条目
   * @param uuid 条目UUID
   * @returns 找到的条目或undefined
   */
  findEntry(uuid: UUID): KdbxEntry | undefined {
    return this.root.findEntry(uuid);
  }

  /**
   * 移动组到新的父组
   * @param group 要移动的组
   * @param newParent 新的父组
   * @returns 是否成功
   */
  moveGroup(group: KdbxGroup, newParent: KdbxGroup): boolean {
    if (!group || !newParent) {
      return false;
    }

    // 不能移动到自己或子组中
    if (group.uuid === newParent.uuid || newParent.findGroup(group.uuid)) {
      return false;
    }

    if (group.parentGroup === undefined) {
      return false;
    }

    // 找到当前父组
    const oldParent = this.findGroup(group.parentGroup);
    if (!oldParent) {
      return false;
    }

    // 从旧父组中移除
    oldParent.removeGroup(group.uuid);

    // 添加到新父组
    newParent.addGroup(group);
    group.parentGroup = newParent.uuid;

    return true;
  }

  /**
   * 移动条目到新的父组
   * @param entry 要移动的条目
   * @param newParent 新的父组
   * @returns 是否成功
   */
  moveEntry(entry: KdbxEntry, newParent: KdbxGroup): boolean {
    if (!entry || !newParent) {
      return false;
    }

    // 找到当前父组
    const oldParent = this.findGroup(entry.parentGroup);
    if (!oldParent) {
      return false;
    }

    // 从旧父组中移除
    oldParent.removeEntry(entry.uuid);

    // 添加到新父组
    newParent.addEntry(entry);
    entry.parentGroup = newParent.uuid;

    return true;
  }

  /**
   * 删除组
   * @param group 要删除的组
   * @param useRecycleBin 是否使用回收站
   * @returns 是否成功
   */
  deleteGroup(group: KdbxGroup, useRecycleBin: boolean = true): boolean {
    if (!group) {
      return false;
    }

    // 不能删除根组
    if (group.uuid === this.root.uuid) {
      return false;
    }

    if (group.parentGroup === undefined) {
      return false;
    }

    // 找到父组
    const parent = this.findGroup(group.parentGroup);
    if (!parent) {
      return false;
    }

    // 如果使用回收站且回收站已启用
    if (useRecycleBin && this.meta.recycleBinEnabled && this.meta.recycleBinUUID) {
      const recycleBin = this.findGroup(this.meta.recycleBinUUID);
      if (recycleBin && group.uuid !== this.meta.recycleBinUUID) {
        return this.moveGroup(group, recycleBin);
      }
    }

    // 直接删除
    parent.removeGroup(group.uuid);

    // 添加到已删除对象列表
    this.deletedObjects.push({
      uuid: group.uuid,
      deletionTime: new Date()
    });

    return true;
  }

  /**
   * 删除条目
   * @param entry 要删除的条目
   * @param useRecycleBin 是否使用回收站
   * @returns 是否成功
   */
  deleteEntry(entry: KdbxEntry, useRecycleBin: boolean = true): boolean {
    if (!entry) {
      return false;
    }

    // 找到父组
    const parent = this.findGroup(entry.parentGroup);
    if (!parent) {
      return false;
    }

    // 如果使用回收站且回收站已启用
    if (useRecycleBin && this.meta.recycleBinEnabled && this.meta.recycleBinUUID) {
      const recycleBin = this.findGroup(this.meta.recycleBinUUID);
      if (recycleBin) {
        return this.moveEntry(entry, recycleBin);
      }
    }

    // 直接删除
    parent.removeEntry(entry.uuid);

    // 添加到已删除对象列表
    this.deletedObjects.push({
      uuid: entry.uuid,
      deletionTime: new Date()
    });

    return true;
  }

  /**
   * 清空回收站
   * @returns 是否成功
   */
  emptyRecycleBin(): boolean {
    if (!this.meta.recycleBinEnabled || !this.meta.recycleBinUUID) {
      return false;
    }

    const recycleBin = this.findGroup(this.meta.recycleBinUUID);
    if (!recycleBin) {
      return false;
    }

    // 将回收站中的所有组和条目添加到已删除对象列表
    recycleBin.traverseGroups(group => {
      if (group.uuid !== this.meta.recycleBinUUID) {
        this.deletedObjects.push({
          uuid: group.uuid,
          deletionTime: new Date()
        });
      }
    });

    recycleBin.traverseEntries(entry => {
      this.deletedObjects.push({
        uuid: entry.uuid,
        deletionTime: new Date()
      });
    });

    // 清空回收站
    recycleBin.groups = [];
    recycleBin.entries = [];

    return true;
  }

  /**
   * 搜索条目
   * @param query 搜索关键词
   * @param options 搜索选项
   * @returns 匹配的条目列表
   */
  searchEntries(query: string, options?: GroupSearchFieldOptions): KdbxEntry[] {
    if (!query) {
      return [];
    }

    const caseSensitive = options?.caseSensitive || false,
      includeProtected = options?.includeProtected || false,
      fieldNames = options?.includeProtected || undefined,
      searchInGroups = options?.searchInGroups || undefined,
      excludeGroups = options?.excludeGroups || undefined;

    const searchQuery = caseSensitive ? query : query.toLowerCase();
    const results: KdbxEntry[] = [];

    // 递归搜索组
    const searchGroup = (group: KdbxGroup) => {
      // 如果指定了搜索组且当前组不在其中，跳过
      if (searchInGroups && !searchInGroups.some(uuid => uuid === group.uuid)) {
        return;
      }

      // 如果指定了排除组且当前组在其中，跳过
      if (excludeGroups && excludeGroups.some(uuid => uuid === group.uuid)) {
        return;
      }

      // 搜索当前组中的条目
      for (const entry of group.entries) {
        const matchingFields = entry.searchFields(query, options);
        if (matchingFields.length > 0) {
          results.push(entry);
        }
      }

      // 递归搜索子组
      for (const subGroup of group.groups) {
        searchGroup(subGroup);
      }
    };

    searchGroup(this.root);
    return results;
  }

  /**
   * 获取数据库统计信息
   * @returns 统计信息
   */
  getStatistics(): DatabaseStatistics {
    let groupCount = 0;
    let entryCount = 0;
    let attachmentCount = 0;
    let attachmentSize = 0;
    let passwordCount = 0;
    let expiredEntryCount = 0;

    // 统计组数量
    this.root.traverseGroups(() => {
      groupCount++;
    });

    // 统计条目信息
    this.root.traverseEntries(entry => {
      entryCount++;

      // 统计附件
      attachmentCount += entry.attachments.length;
      attachmentSize += entry.attachments.reduce((sum, att) => sum + att.data.length, 0);

      // 统计密码
      if (entry.password) {
        passwordCount++;
      }

      // 统计过期条目
      if (entry.isExpired()) {
        expiredEntryCount++;
      }
    });

    return {
      groupCount: groupCount - 1, // 减去根组
      entryCount,
      attachmentCount,
      attachmentSize,
      passwordCount,
      expiredEntryCount
    };
  }
}