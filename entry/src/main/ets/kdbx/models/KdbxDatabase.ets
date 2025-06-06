import { Binary, DatabaseStatistics, DeletedObject, GroupSearchFieldOptions, Meta, UUID } from './KdbxTypes';
import { KdbxGroup } from './KdbxGroup';
import { KdbxEntry } from './KdbxEntry';
import { InnerRandomStreamID } from '../KdbxFormat';
import { KdbxUtils } from '../utils/KdbxUtils';


/**
 * 回收站状态
 */
interface RecycleBinStatus {
  isInRecycleBin: boolean;
  isRecycleBinRoot: boolean
}


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
    this.root = new KdbxGroup(KdbxUtils.createUUID(), 'Root');

    // 初始化元数据
    this.meta = {
      databaseName: '新数据库',
      databaseDescription: '',
      defaultUserName: '',
      historyMaxItems: 10,
      historyMaxSize: 6 * 1024 * 1024, // 6MB
      recycleBinEnabled: true,
      recycleBinUUID: KdbxUtils.createUUID(),
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
    const uuid = KdbxUtils.createUUID();
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
    const uuid = KdbxUtils.createUUID();
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
  /**
   * 移动组到新的父组
   * @param group 要移动的组
   * @param newParent 新的父组
   * @returns 是否成功
   */
  moveGroup(group: KdbxGroup, newParent: KdbxGroup): boolean {
    // 基本验证
    if (!group || !newParent || !group.parentGroup) {
      return false;
    }

    // 不能移动到自己或子组中
    if (group.uuid === newParent.uuid || group.findGroup(newParent.uuid) !== undefined || this.findGroup(newParent.uuid) === undefined) {
      return false;
    }

    // 找到当前父组
    const oldParent = this.findGroup(group.parentGroup);
    if (!oldParent) {
      return false;
    }

    // 检查回收站相关状态
    const sourceStatus = this.checkRecycleBinTarget(oldParent);
    const targetStatus = this.checkRecycleBinTarget(newParent);

    // 不能移动回收站到其他组
    if (group.uuid === this.meta.recycleBinUUID) {
      return false;
    }

    // 回收站移动规则检查
    if (!this.validateRecycleBinMove(sourceStatus, targetStatus, oldParent)) {
      return false;
    }

    // 执行移动操作
    oldParent.removeGroup(group.uuid);
    newParent.addGroup(group);
    group.parentGroup = newParent.uuid;

    // 更新时间戳
    const now = new Date();
    group.lastModifiedTime = now;
    // 更新回收站状态
    this.updateRecycleBinStatus(oldParent, newParent);

    return true;
  }

  /**
   * 移动条目到新的父组
   * @param entry 要移动的条目
   * @param newParent 新的父组
   * @returns 是否成功
   */
  moveEntry(entry: KdbxEntry, newParent: KdbxGroup): boolean {
    if (!entry || !newParent || this.findGroup(newParent.uuid) === undefined) {
      return false;
    }

    // 找到当前父组
    const oldParent = this.findGroup(entry.parentGroup);
    if (!oldParent) {
      return false;
    }

    // 检查是否在回收站中
    let isInRecycleBin = this.isInRecycleBin(oldParent.uuid, oldParent.parentGroup);
    // 检查目标组是否在回收站中
    let isTargetInRecycleBin = this.isInRecycleBin(newParent.uuid, newParent.parentGroup);

    // 如果源条目不在回收站但目标组在回收站中，只允许直接移动到回收站根目录
    if (!isInRecycleBin && isTargetInRecycleBin) {
      if (newParent.uuid !== this.meta.recycleBinUUID) {
        return false;
      }
    }

    // 如果源条目在回收站中，不允许移动到回收站外（除非是恢复操作）
    if (isInRecycleBin && !isTargetInRecycleBin) {
      // 允许从回收站恢复
      const recycleBin = this.findGroup(this.meta.recycleBinUUID!);
      if (recycleBin && oldParent.uuid === recycleBin.uuid) {
        // 从回收站根目录恢复是允许的
      } else {
        return false;
      }
    }

    // 从旧父组中移除
    oldParent.removeEntry(entry.uuid);

    // 添加到新父组
    newParent.addEntry(entry);
    entry.parentGroup = newParent.uuid;

    // 如果是移动到回收站或从回收站移出，更新回收站修改时间
    if (this.meta.recycleBinEnabled && this.meta.recycleBinUUID &&
      (newParent.uuid === this.meta.recycleBinUUID || oldParent.uuid === this.meta.recycleBinUUID)) {
      this.meta.recycleBinChanged = new Date();
    }

    return true;
  }

  /**
   * 删除组
   * @param group 要删除的组
   * @param useRecycleBin 是否使用回收站
   * @returns 是否成功
   */
  deleteGroup(group: KdbxGroup, useRecycleBin: boolean = true): boolean {
    // 不能删除根组
    if (!group || group.uuid === this.root.uuid || group.parentGroup === undefined) {
      return false;
    }

    // 查找组的父组
    const parent = this.findGroup(group.parentGroup);
    if (!parent) {
      return false;
    }

    // 检查是否是回收站本身
    if (this.meta.recycleBinEnabled && this.meta.recycleBinUUID &&
      group.uuid === this.meta.recycleBinUUID) {
      // 如果是回收站本身，先清空回收站内容
      this.emptyRecycleBin();
      // 然后删除回收站并重置回收站UUID
      parent.removeGroup(group.uuid);
      this.deletedObjects.push({
        uuid: group.uuid,
        deletionTime: new Date()
      });
      this.meta.recycleBinUUID = KdbxUtils.createUUID();
      return true;
    }

    // 检查组是否在回收站中
    const inRecycleBin = this.isInRecycleBin(group.uuid, group.parentGroup);

    // 如果组已经在回收站中，或者不使用回收站，或者回收站被禁用，则直接删除
    if (inRecycleBin || !useRecycleBin || !this.meta.recycleBinEnabled) {
      const now = new Date();

      // 递归添加所有子组和条目到已删除对象列表
      const addToDeletedObjects = (g: KdbxGroup) => {
        // 先递归处理子组
        for (const subGroup of [...g.groups]) {
          addToDeletedObjects(subGroup);
        }

        // 处理当前组的所有条目
        for (const entry of [...g.entries]) {
          this.deletedObjects.push({
            uuid: entry.uuid,
            deletionTime: now
          });
        }

        // 添加组本身到已删除对象列表
        this.deletedObjects.push({
          uuid: g.uuid,
          deletionTime: now
        });
      };

      // 递归删除所有内容
      addToDeletedObjects(group);

      // 从父组中移除
      parent.removeGroup(group.uuid);
      return true;
    }

    // 确保回收站存在
    const recycleBin = this.ensureRecycleBin();
    if (!recycleBin) {
      return false;
    }

    // 移动到回收站
    const moveResult = this.moveGroup(group, recycleBin);
    if (moveResult) {
      this.meta.recycleBinChanged = new Date();
    }
    return moveResult;
  }

  /**
   * 确保回收站存在
   * @returns 回收站组
   */
  private ensureRecycleBin(): KdbxGroup | null {
    if (!this.meta.recycleBinEnabled) {
      return null;
    }

    // 检查回收站是否存在
    let recycleBin: KdbxGroup | undefined;
    if (this.meta.recycleBinUUID) {
      recycleBin = this.findGroup(this.meta.recycleBinUUID);
    }

    // 如果回收站不存在，创建一个新的
    if (!recycleBin) {
      const now = new Date();
      this.meta.recycleBinUUID = KdbxUtils.createUUID();
      recycleBin = new KdbxGroup(this.meta.recycleBinUUID, '回收站');

      // 设置回收站的基本属性
      recycleBin.icon = { id: 43 }; // 回收站图标
      // 设置时间戳
      recycleBin.creationTime = now;
      recycleBin.lastModifiedTime = now;
      recycleBin.lastAccessTime = now;

      // 添加到根组
      this.root.addGroup(recycleBin);
      recycleBin.parentGroup = this.root.uuid;

      // 更新回收站状态
      this.meta.recycleBinChanged = now;
    }

    return recycleBin;
  }

  /**
   * 删除条目
   * @param entry 要删除的条目
   * @param useRecycleBin 是否使用回收站
   * @returns 是否成功
   */
  deleteEntry(entry: KdbxEntry, useRecycleBin: boolean = true): boolean {
    if (!entry || this.findEntry(entry.uuid) === undefined) {
      return false;
    }

    const parent = this.findGroup(entry.parentGroup);
    if (!parent) {
      return false;
    }

    // 检查条目是否在回收站中
    const inRecycleBin = this.isInRecycleBin(entry.uuid, entry.parentGroup);

    // 如果条目已经在回收站中，或者不使用回收站，或者回收站被禁用，则直接删除
    if (inRecycleBin || !useRecycleBin || !this.meta.recycleBinEnabled) {
      // 从父组中移除条目
      parent.removeEntry(entry.uuid);

      // 添加到已删除对象列表
      this.deletedObjects.push({
        uuid: entry.uuid,
        deletionTime: new Date()
      });

      return true;
    }

    // 确保回收站存在
    const recycleBin = this.ensureRecycleBin();
    if (!recycleBin) {
      return false;
    }

    // 移动到回收站
    const moveResult = this.moveEntry(entry, recycleBin);
    if (moveResult) {
      // 更新回收站修改时间
      this.meta.recycleBinChanged = new Date();

      // 更新条目的修改时间
      entry.lastModifiedTime = new Date();
    }
    return moveResult;
  }

  /**
   * 检查目标组是否在回收站中
   * @param group 要检查的组
   * @returns 是否在回收站中，以及是否是回收站根目录
   */
  private checkRecycleBinTarget(group: KdbxGroup): RecycleBinStatus {
    if (!this.meta.recycleBinEnabled || !this.meta.recycleBinUUID) {
      return { isInRecycleBin: false, isRecycleBinRoot: false };
    }

    const isRecycleBinRoot = group.uuid === this.meta.recycleBinUUID;
    if (isRecycleBinRoot) {
      return { isInRecycleBin: true, isRecycleBinRoot: true };
    }

    return {
      isInRecycleBin: this.isInRecycleBin(group.uuid, group.parentGroup),
      isRecycleBinRoot: false
    };
  }


  /**
   * 验证与回收站相关的移动操作是否合法
   * @param sourceStatus 源位置的回收站状态
   * @param targetStatus 目标位置的回收站状态
   * @param oldParent 原父组
   * @returns 移动操作是否合法
   */
  private validateRecycleBinMove( sourceStatus: RecycleBinStatus, targetStatus: RecycleBinStatus, oldParent: KdbxGroup ): boolean {
    // 如果回收站未启用，允许任何移动
    if (!this.meta.recycleBinEnabled || !this.meta.recycleBinUUID) {
      return true;
    }

    // 如果源不在回收站但目标在回收站中，只允许直接移动到回收站根目录
    if (!sourceStatus.isInRecycleBin && targetStatus.isInRecycleBin) {
      return targetStatus.isRecycleBinRoot;
    }

    // 如果源在回收站中，不允许移动到回收站外（除非是从回收站根目录恢复）
    if (sourceStatus.isInRecycleBin && !targetStatus.isInRecycleBin) {
      return oldParent.uuid === this.meta.recycleBinUUID;
    }

    return true;
  }

  /**
   * 更新回收站状态
   * @param oldParent 原父组
   * @param newParent 新父组
   */
  private updateRecycleBinStatus(oldParent: KdbxGroup, newParent: KdbxGroup): void {
    if (this.meta.recycleBinEnabled && this.meta.recycleBinUUID &&
      (newParent.uuid === this.meta.recycleBinUUID || oldParent.uuid === this.meta.recycleBinUUID)) {
      this.meta.recycleBinChanged = new Date();
    }
  }

  /**
   * 添加对象到已删除列表
   * @param uuid 对象UUID
   * @param deletionTime 删除时间，默认为当前时间
   */
  private addToDeletedObjects(uuid: string, deletionTime: Date = new Date()): void {
    this.deletedObjects.push({
      uuid: uuid,
      deletionTime: deletionTime
    });
  }

  /**
   * 检查指定的组或其父组是否在回收站中
   * @param uuid 要检查的组或条目的UUID
   * @param parentGroupUUID 父组的UUID
   * @returns 是否在回收站中
   */
  private isInRecycleBin(uuid: string, parentGroupUUID: string | undefined): boolean {
    if (!this.meta.recycleBinEnabled || !this.meta.recycleBinUUID) {
      return false;
    }

    // 如果是回收站本身，返回false
    if (uuid === this.meta.recycleBinUUID) {
      return false;
    }

    if (parentGroupUUID === undefined) {
      return false;
    }
    // 从父组开始向上查找，直到找到回收站或到达根组
    let currentGroup: KdbxGroup | undefined = this.findGroup(parentGroupUUID);
    while (currentGroup && currentGroup.uuid !== this.root.uuid) {
      if (currentGroup.uuid === this.meta.recycleBinUUID) {
        return true;
      }
      currentGroup = currentGroup.parentGroup ? this.findGroup(currentGroup.parentGroup) : undefined;
    }

    return false;
  }

  /**
   * 设置回收站的启用状态
   * @param enabled 是否启用回收站
   * @returns 操作是否成功
   */
  setRecycleBinEnabled(enabled: boolean): boolean {
    // 如果状态没有改变，直接返回true
    if (this.meta.recycleBinEnabled === enabled) {
      return true;
    }

    if (enabled) {
      // 启用回收站
      this.meta.recycleBinEnabled = true;
      // 确保回收站存在
      return this.ensureRecycleBin() !== null;
    } else {
      // 禁用回收站前先清空回收站
      if (this.meta.recycleBinUUID) {
        const recycleBin = this.findGroup(this.meta.recycleBinUUID);
        if (recycleBin) {
          // 清空回收站内容
          this.emptyRecycleBin();
          // 从根组中移除回收站
          this.root.removeGroup(recycleBin.uuid);
          // 添加回收站本身到已删除对象列表
          this.deletedObjects.push({
            uuid: recycleBin.uuid,
            deletionTime: new Date()
          });
        }
      }

      // 禁用回收站
      this.meta.recycleBinEnabled = false;
      this.meta.recycleBinUUID = undefined;
      return true;
    }
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

    const now = new Date();

    // 递归删除所有组和条目
    const deleteGroupContents = (group: KdbxGroup) => {
      // 先递归处理子组
      for (const subGroup of [...group.groups]) {
        // 递归处理子组的内容
        deleteGroupContents(subGroup);

        // 从当前组中移除子组
        group.removeGroup(subGroup.uuid);
      }

      // 处理当前组的所有条目
      for (const entry of [...group.entries]) {
        // 添加到已删除对象列表
        this.deletedObjects.push({
          uuid: entry.uuid,
          deletionTime: now
        });

        // 从当前组中移除条目
        group.removeEntry(entry.uuid);
      }

      // 如果不是回收站本身，则添加组到已删除对象列表
      if (group.uuid !== this.meta.recycleBinUUID) {
        this.deletedObjects.push({
          uuid: group.uuid,
          deletionTime: now
        });
      }
    };

    // 清空回收站内容
    deleteGroupContents(recycleBin);

    // 确保回收站中的组和条目列表为空
    recycleBin.groups = [];
    recycleBin.entries = [];

    // 更新回收站状态
    this.meta.recycleBinChanged = now;
    recycleBin.lastModifiedTime = now;

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
      fieldNames = options?.fieldNames || undefined,
      searchInGroups = options?.searchInGroups || undefined,
      excludeGroups = options?.excludeGroups || undefined;

    const results: KdbxEntry[] = [];

    // 递归搜索组
    const searchGroup = (group: KdbxGroup) => {
      // 如果在排除列表中，跳过该组及其子组
      if (excludeGroups?.includes(group.uuid)) {
        return;
      }

      // 搜索当前组中的条目
      for (const entry of group.entries) {
        const matchingFields = entry.searchFields(query, {
          caseSensitive,
          includeProtected,
          fieldNames
        });
        if (matchingFields.length > 0) {
          results.push(entry);
        }
      }

      // 递归搜索子组
      for (const subGroup of group.groups) {
        searchGroup(subGroup);
      }
    };

    // 如果指定了搜索组，只在这些组中搜索
    if (searchInGroups && searchInGroups.length > 0) {
      for (const groupUuid of searchInGroups) {
        const group = this.findGroup(groupUuid);
        if (group) {
          searchGroup(group);
        }
      }
    } else {
      // 如果没有指定搜索组，则搜索所有组
      searchGroup(this.root);
    }

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