import { Binary, UUID } from './models/KdbxTypes';
import { KdbxHeader } from './models/KdbxHeader';
import { KdbxMeta } from './models/KdbxMeta';
import { KeePassDatabase } from './models/KeePassDatabase';
import { PwEntry } from './models/PwEntry';
import { PwGroup } from './models/PwGroup';
import { KdbxReader } from './KdbxReader';
import { KdbxWriter } from './KdbxWriter';
import { CompressionAlgorithm, KDBX_VERSION_4, InnerRandomStreamID } from './KdbxFormat';

/**
 * KDBX4数据库管理器
 * 提供创建、打开、保存KDBX4数据库的功能
 */
export class KdbxManager {
  /**
   * 打开KDBX4数据库
   * @param data 数据库文件数据
   * @param password 密码
   * @param keyFile 密钥文件（可选）
   * @returns KeePass数据库对象
   */
  static async open(data: ArrayBuffer, password: string, keyFile?: Binary): Promise<KeePassDatabase> {
    const reader = new KdbxReader(data);
    return await reader.read(password, keyFile);
  }

  /**
   * 保存KDBX4数据库
   * @param database 数据库对象
   * @param password 密码
   * @param keyFile 密钥文件（可选）
   * @returns 数据库文件数据
   */
  static async save(database: KeePassDatabase, password: string, keyFile?: Binary): Promise<ArrayBuffer> {
    const writer = new KdbxWriter(database);
    return await writer.write(password, keyFile);
  }

  /**
   * 创建新的KDBX4数据库
   * @param name 数据库名称
   * @param password 密码
   * @param keyFile 密钥文件（可选）
   * @returns 新的KeePass数据库对象
   */
  static async create(name: string, password: string, keyFile?: Binary): Promise<KeePassDatabase> {
    // 创建默认头部
    const header: KdbxHeader = {
      version: KDBX_VERSION_4,
      masterSeed: new Uint8Array(0), // 将在保存时生成
      transformSeed: new Uint8Array(0), // 将在保存时生成
      transformRounds: 60000,
      encryptionIV: new Uint8Array(0), // 将在保存时生成
      protectedStreamKey: new Uint8Array(0), // 将在保存时生成
      streamStartBytes: new Uint8Array(0), // 将在保存时生成
      innerRandomStreamID: InnerRandomStreamID.CHACHA20,
      kdfParameters: new Map([
        ['rounds', 60000],
        ['memory', 32 * 1024 * 1024], // 32MB
        ['parallelism', 2]
      ]),
      compressionFlags: CompressionAlgorithm.GZIP
    };

    // 创建元数据
    const now = new Date();
    const meta: KdbxMeta = {
      generator: 'KeePassHO',
      databaseName: name,
      databaseNameChanged: now,
      databaseDescription: '',
      databaseDescriptionChanged: now,
      defaultUserName: '',
      defaultUserNameChanged: now,
      maintenanceHistoryDays: 365,
      color: '',
      masterKeyChanged: now,
      masterKeyChangeRec: 90,
      masterKeyChangeForce: -1,
      recycleBinEnabled: true,
      recycleBinUUID: crypto.getRandomValues(new Uint8Array(16)),
      recycleBinChanged: now,
      entryTemplatesGroup: new Uint8Array(0),
      entryTemplatesGroupChanged: now,
      historyMaxItems: 10,
      historyMaxSize: 6 * 1024 * 1024, // 6MB
      lastSelectedGroup: new Uint8Array(0),
      lastTopVisibleGroup: new Uint8Array(0),
      memoryProtection: {
        protectTitle: false,
        protectUserName: false,
        protectPassword: true,
        protectURL: false,
        protectNotes: false
      },
      customIcons: new Map(),
      customData: new Map()
    };

    // 创建根组
    const rootGroup: PwGroup = {
      uuid: crypto.getRandomValues(new Uint8Array(16)),
      name: 'Root',
      notes: '',
      iconId: 48,
      times: {
        creationTime: now,
        lastModificationTime: now,
        lastAccessTime: now,
        expiryTime: new Date(0),
        expires: false,
        usageCount: 0,
        locationChanged: now
      },
      isExpanded: true,
      defaultAutoTypeSequence: '',
      enableAutoType: null,
      enableSearching: null,
      lastTopVisibleEntry: new Uint8Array(0),
      groups: [],
      entries: []
    };

    // 创建回收站
    const recycleBin: PwGroup = {
      uuid: meta.recycleBinUUID,
      name: 'Recycle Bin',
      notes: '',
      iconId: 43,
      times: {
        creationTime: now,
        lastModificationTime: now,
        lastAccessTime: now,
        expiryTime: new Date(0),
        expires: false,
        usageCount: 0,
        locationChanged: now
      },
      isExpanded: false,
      defaultAutoTypeSequence: '',
      enableAutoType: null,
      enableSearching: null,
      lastTopVisibleEntry: new Uint8Array(0),
      groups: [],
      entries: []
    };

    // 添加回收站到根组
    rootGroup.groups.push(recycleBin);

    // 创建数据库对象
    const database: KeePassDatabase = {
      header,
      meta,
      root: rootGroup
    };

    return database;
  }

  /**
   * 创建新的密码条目
   * @param title 标题
   * @param username 用户名
   * @param password 密码
   * @param url URL
   * @param notes 备注
   * @returns 新的密码条目
   */
  static createEntry(title: string, username: string, password: string, url: string = '', notes: string = ''): PwEntry {
    const now = new Date();
    const entry: PwEntry = {
      uuid: crypto.getRandomValues(new Uint8Array(16)),
      iconId: 0,
      fields: new Map([
        ['Title', title],
        ['UserName', username],
        ['Password', password],
        ['URL', url],
        ['Notes', notes]
      ]),
      binaries: new Map(),
      times: {
        creationTime: now,
        lastModificationTime: now,
        lastAccessTime: now,
        expiryTime: new Date(0),
        expires: false,
        usageCount: 0,
        locationChanged: now
      },
      autoType: {
        enabled: true,
        obfuscation: 0,
        defaultSequence: '',
        associations: []
      }
    };

    return entry;
  }

  /**
   * 创建新的密码组
   * @param name 组名
   * @param notes 备注
   * @returns 新的密码组
   */
  static createGroup(name: string, notes: string = ''): PwGroup {
    const now = new Date();
    const group: PwGroup = {
      uuid: crypto.getRandomValues(new Uint8Array(16)),
      name: name,
      notes: notes,
      iconId: 0,
      times: {
        creationTime: now,
        lastModificationTime: now,
        lastAccessTime: now,
        expiryTime: new Date(0),
        expires: false,
        usageCount: 0,
        locationChanged: now
      },
      isExpanded: true,
      defaultAutoTypeSequence: '',
      enableAutoType: null,
      enableSearching: null,
      lastTopVisibleEntry: new Uint8Array(0),
      groups: [],
      entries: []
    };

    return group;
  }

  /**
   * 添加条目到组
   * @param group 目标组
   * @param entry 要添加的条目
   */
  static addEntryToGroup(group: PwGroup, entry: PwEntry): void {
    if (!group.entries) {
      group.entries = [];
    }
    group.entries.push(entry);
    group.times.lastModificationTime = new Date();
  }

  /**
   * 添加子组到父组
   * @param parentGroup 父组
   * @param childGroup 子组
   */
  static addGroupToGroup(parentGroup: PwGroup, childGroup: PwGroup): void {
    if (!parentGroup.groups) {
      parentGroup.groups = [];
    }
    parentGroup.groups.push(childGroup);
    parentGroup.times.lastModificationTime = new Date();
  }

  /**
   * 查找组（根据UUID）
   * @param root 根组
   * @param uuid 要查找的UUID
   * @returns 找到的组或undefined
   */
  static findGroupByUUID(root: PwGroup, uuid: UUID): PwGroup | undefined {
    // 检查当前组
    if (this.compareUUID(root.uuid, uuid)) {
      return root;
    }

    // 递归检查子组
    if (root.groups) {
      for (const group of root.groups) {
        const found = this.findGroupByUUID(group, uuid);
        if (found) {
          return found;
        }
      }
    }

    return undefined;
  }

  /**
   * 查找条目（根据UUID）
   * @param root 根组
   * @param uuid 要查找的UUID
   * @returns 找到的条目或undefined
   */
  static findEntryByUUID(root: PwGroup, uuid: UUID): PwEntry | undefined {
    // 检查当前组的条目
    if (root.entries) {
      for (const entry of root.entries) {
        if (this.compareUUID(entry.uuid, uuid)) {
          return entry;
        }
      }
    }

    // 递归检查子组
    if (root.groups) {
      for (const group of root.groups) {
        const found = this.findEntryByUUID(group, uuid);
        if (found) {
          return found;
        }
      }
    }

    return undefined;
  }

  /**
   * 比较两个UUID是否相同
   * @param uuid1 第一个UUID
   * @param uuid2 第二个UUID
   * @returns 是否相同
   */
  private static compareUUID(uuid1: UUID, uuid2: UUID): boolean {
    if (uuid1.length !== uuid2.length) {
      return false;
    }

    for (let i = 0; i < uuid1.length; i++) {
      if (uuid1[i] !== uuid2[i]) {
        return false;
      }
    }

    return true;
  }
}
