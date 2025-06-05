import util from '@ohos.util';

import { cryptoFramework } from '@kit.CryptoArchitectureKit';

class CryptoHelper {
  static async getRandomValues(array: Uint8Array): Promise<Uint8Array> {
    let rand = cryptoFramework.createRandom();
    let randomData = await rand.generateRandom(array.length);
    array.set(randomData.data);
    return array;
  }
}


/**
 * 二进制数据类型
 */
export type Binary = Uint8Array;

/**
 * UUID类型
 */
export type UUID = Binary;

/**
 * 时间戳类型
 */
export type TimeStamp = Date;

/**
 * 保护字段类型
 */
export class ProtectedValue {
  private readonly encryptedValue: Binary;
  private readonly salt: Binary;

  constructor(value: string | Binary, salt: Binary) {
    if (typeof value === 'string') {
      this.encryptedValue = new util.TextEncoder().encodeInto(value);
    } else {
      this.encryptedValue = value;
    }
    this.salt = salt;
  }

  /**
   * 获取加密值
   */
  getEncrypted(): Binary {
    return this.encryptedValue;
  }

  /**
   * 获取盐值
   */
  getSalt(): Binary {
    return this.salt;
  }

  /**
   * 创建一个新的受保护值
   * @param value 原始值
   * @returns 受保护的值
   */
  static async create(value: string): Promise<ProtectedValue> {
    const salt = await CryptoHelper.getRandomValues(new Uint8Array(32));
    return new ProtectedValue(value, salt);
  }
}

/**
 * 图标类型
 */
export interface Icon {
  /**
   * 图标ID
   */
  id: number;

  /**
   * 自定义图标UUID
   */
  uuid?: UUID;

  /**
   * 自定义图标数据
   */
  data?: Binary;
}

/**
 * 字段类型
 */
export interface Field {
  /**
   * 字段名
   */
  name: string;

  /**
   * 字段值
   */
  value: string | ProtectedValue;

  /**
   * 是否受保护
   */
  protected?: boolean;
}

/**
 * 二进制附件
 */
export interface BinaryAttachment {
  /**
   * 附件名称
   */
  name: string;

  /**
   * 附件数据
   */
  data: Binary;

  /**
   * 附件引用
   */
  ref?: string;

  /**
   * 附件大小（字节）
   */
  size?: number;
}

/**
 * 自动类型关联
 */
export interface AutoTypeAssociation {
  window: string;
  keystrokeSequence: string;
}

/**
 * 自动类型设置
 */
export interface AutoTypeSettings {
  enabled: boolean;
  defaultSequence: string;
  associations: AutoTypeAssociation[];
}

/**
 * 密码生成器设置
 */
export interface PasswordGeneratorSettings {
  /**
   * 密码长度
   */
  length?: number;

  /**
   * 使用大写字母
   */
  upperCase?: boolean;

  /**
   * 使用小写字母
   */
  lowerCase?: boolean;

  /**
   * 使用数字
   */
  digits?: boolean;

  /**
   * 使用特殊字符
   */
  special?: boolean;

  /**
   * 排除相似字符
   */
  excludeLookAlike?: boolean;

  /**
   * 确保每种字符至少出现一次
   */
  ensureEveryCharType?: boolean;
}

/**
 * 内存保护设置
 */
export interface MemoryProtectionSettings {
  /**
   * 保护标题
   */
  protectTitle?: boolean;

  /**
   * 保护用户名
   */
  protectUserName?: boolean;

  /**
   * 保护密码
   */
  protectPassword?: boolean;

  /**
   * 保护URL
   */
  protectUrl?: boolean;

  /**
   * 保护备注
   */
  protectNotes?: boolean;
}

/**
 * 变体字典项
 */
export interface VariantDictionaryItem {
  type: number;
  value: string | number | boolean | Binary;
}

/**
 * 变体字典
 */
export type VariantDictionary = Map<string, VariantDictionaryItem>;

/**
 * 自定义数据
 */
export interface CustomData {
  /**
   * 数据键
   */
  key: string;

  /**
   * 数据值
   */
  value: string;

  /**
   * 最后修改时间
   */
  lastModified?: TimeStamp;
}

/**
 * 删除对象
 */
export interface DeletedObject {
  /**
   * 对象UUID
   */
  uuid: UUID;

  /**
   * 删除时间
   */
  deletionTime: TimeStamp;
}

/**
 * 元数据
 */
export interface Meta {
  /**
   * 数据库名称
   */
  databaseName?: string;

  /**
   * 数据库描述
   */
  databaseDescription?: string;

  /**
   * 默认用户名
   */
  defaultUserName?: string;

  /**
   * 维护历史条目的最大数量
   */
  historyMaxItems?: number;

  /**
   * 历史条目的最大大小（字节）
   */
  historyMaxSize?: number;

  /**
   * 密码生成器设置
   */
  passwordGenerator?: PasswordGeneratorSettings;

  /**
   * 主密钥更改时间
   */
  masterKeyChanged?: TimeStamp;

  /**
   * 主密钥更改强制间隔（天）
   */
  masterKeyChangeRec?: number;

  /**
   * 主密钥更改强制间隔（天）
   */
  masterKeyChangeForce?: number;

  /**
   * 内存保护设置
   */
  memoryProtection?: MemoryProtectionSettings;

  /**
   * 自定义图标
   */
  customIcons?: Map<UUID, Icon>;

  /**
   * 最后选择的组
   */
  lastSelectedGroup?: UUID;

  /**
   * 最后顶层可见组
   */
  lastTopVisibleGroup?: UUID;

  /**
   * 回收站启用状态
   */
  recycleBinEnabled?: boolean;

  /**
   * 回收站UUID
   */
  recycleBinUUID?: UUID;

  /**
   * 回收站更改时间
   */
  recycleBinChanged?: TimeStamp;

  /**
   * 条目模板组UUID
   */
  entryTemplatesGroup?: UUID;

  /**
   * 条目模板组更改时间
   */
  entryTemplatesGroupChanged?: TimeStamp;

  /**
   * 数据库名称更改时间
   */
  nameChanged?: TimeStamp;

  /**
   * 默认用户名更改时间
   */
  defaultUserNameChanged?: TimeStamp;

  /**
   * 设置更改时间
   */
  settingsChanged?: TimeStamp;

  /**
   * 数据库描述更改时间
   */
  descriptionChanged?: TimeStamp;

  /**
   * 自定义数据
   */
  customData?: CustomData[];

  /**
   * 颜色（RGB格式）
   */
  color?: string;
}
