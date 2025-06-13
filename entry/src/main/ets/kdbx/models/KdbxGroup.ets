import { UUID, TimeStamp, Icon } from './KdbxTypes';
import { KdbxEntry } from './KdbxEntry';
import { ByteUtils } from '../utils/ByteUtils';

/**
 * 数据库分组
 */
export class KdbxGroup {
  /**
   * 组UUID
   */
  uuid: UUID;
  /**
   * 组名
   */
  name: string;
  /**
   * 图标
   */
  icon: Icon;
  /**
   * 创建时间
   */
  creationTime: TimeStamp;
  /**
   * 最后修改时间
   */
  lastModifiedTime: TimeStamp;
  /**
   * 最后访问时间
   */
  lastAccessTime: TimeStamp;
  /**
   * 过期时间
   */
  expiryTime?: TimeStamp;
  /**
   * 是否过期
   */
  expires: boolean = false;
  /**
   * 父组UUID
   */
  parentGroup?: UUID;
  /**
   * 子组列表
   */
  groups: KdbxGroup[] = [];
  /**
   * 条目列表
   */
  entries: KdbxEntry[] = [];
  /**
   * 是否默认展开
   */
  isExpanded: boolean = false;
  /**
   * 是否默认选中
   */
  isSelected: boolean = false;

  /**
   * 构造函数
   * @param uuid 组UUID
   * @param name 组名
   */
  constructor(uuid: UUID | Uint8Array, name: string) {
    this.uuid = uuid instanceof  Uint8Array ? ByteUtils.bytesToString(uuid) : uuid;
    this.name = name;
    this.creationTime = new Date();
    this.lastModifiedTime = new Date();
    this.lastAccessTime = new Date();
    this.icon = { id: 0 };
  }


  /**
   * 添加子组
   * @param group 子组
   */
  addGroup(group: KdbxGroup): void {
    group.parentGroup = this.uuid;
    this.groups.push(group);
    this.lastModifiedTime = new Date();
  }

  /**
   * 删除子组
   * @param uuid 子组UUID
   */
  removeGroup(uuid: UUID): void {
    const index = this.groups.findIndex(g => g.uuid === uuid);
    if (index >= 0) {
      this.groups.splice(index, 1);
      this.lastModifiedTime = new Date();
    }
  }

  /**
   * 添加条目
   * @param entry 条目
   */
  addEntry(entry: KdbxEntry): void {
    entry.parentGroup = this.uuid;
    this.entries.push(entry);
    this.lastModifiedTime = new Date();
  }

  /**
   * 删除条目
   * @param uuid 条目UUID
   */
  removeEntry(uuid: UUID): void {
    const index = this.entries.findIndex(e => e.uuid === uuid);
    if (index >= 0) {
      this.entries.splice(index, 1);
      this.lastModifiedTime = new Date();
    }
  }

  /**
   * 查找子组
   * @param uuid 组UUID
   * @returns 找到的组或undefined
   */
  findGroup(uuid: UUID): KdbxGroup | undefined {
    if (this.uuid === uuid) {
      return this;
    }
    for (const group of this.groups) {
      const found = group.findGroup(uuid);
      if (found) {
        return found;
      }
    }
    return undefined;
  }

  /**
   * 查找条目
   * @param uuid 条目UUID
   * @returns 找到的条目或undefined
   */
  findEntry(uuid: UUID): KdbxEntry | undefined {
    const entry = this.entries.find(e => e.uuid === uuid);
    if (entry) {
      return entry;
    }
    for (const group of this.groups) {
      const found = group.findEntry(uuid);
      if (found) {
        return found;
      }
    }
    return undefined;
  }

  /**
   * 递归遍历所有组
   * @param callback 回调函数
   */
  traverseGroups(callback: (group: KdbxGroup) => void): void {
    callback(this);
    for (const group of this.groups) {
      group.traverseGroups(callback);
    }
  }

  /**
   * 递归遍历所有条目
   * @param callback 回调函数
   */
  traverseEntries(callback: (entry: KdbxEntry) => void): void {
    for (const entry of this.entries) {
      callback(entry);
    }
    for (const group of this.groups) {
      group.traverseEntries(callback);
    }
  }

  /**
   * 更新访问时间
   */
  touch(): void {
    this.lastAccessTime = new Date();
  }

  /**
   * 检查是否过期
   * @returns 是否过期
   */
  isExpired(): boolean {
    return this.expires && this.expiryTime !== undefined && this.expiryTime <= new Date();
  }
}
