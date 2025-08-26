import { Kdbx } from 'kdbxweb';
import { StorageType } from './kdbx/interfaces';
import { StorageConfig } from './kdbx/interfaces/StorageConfig';

/**
 * 凭证参数定义
 */
export interface CredentialsParam {
  /**
   * 密码
   */
  password: string;

  /**
   * 认证方式
   */
  authType: AuthTypeInfo;

  /**
   * 认证密码文件路径
   */
  keyFilePath?: string;
}

/**
 * kdbx文件定义
 */
export interface FileParam {
  /**
   * 文件路径
   */
  filePath: string;

  /**
   * 文件名
   */
  fileName: string;

  /**
   * 存储类型
   */
  storageType: StorageType;

  /**
   * 存储配置信息
   */
  storageConfig: StorageConfig;
}

/**
 * 数据库文件定义，只会存储在内容中
 */
export interface DbFileParam extends CredentialsParam{
  /**
   * 文件路径
   */
  filePath: string;

  /**
   * 文件名
   */
  fileName: string;

  /**
   * 密码
   */
  password: string;

  /**
   * 已解密的数据库对象
   */
  database: Kdbx;

  /**
   * 认证方式
   */
  authType: AuthTypeInfo;

  /**
   * 认证密码文件路径
   */
  keyFilePath?: string;

  /**
   * 存储类型
   */
  storageType: StorageType;

  /**
   * 存储配置信息
   */
  storageConfig: StorageConfig;

  /**
   * 最后修改时间,单位为毫秒
   */
  modifiedTime: number;

  /**
   * 新密码
   */
  newPassword?: string;
  /**
   * 新密钥文件路径
   */
  newKeyFilePath?: string;

  /**
   * 是否使用密钥文件
   */
  notUseKeyFile?: boolean;
}

/**
 * 导出的文件信息
 */
export class ExportFileParam{
  /**
   * 文件路径
   */
  fileName: string;
  /**
   * 文件内容
   */
  content: ArrayBuffer;

  constructor(fileName: string, content: ArrayBuffer) {
    this.fileName = fileName;
    this.content = content;
  }
}

/**
 * 认证方式接口
 */
export interface AuthTypeInfo {
  /**
   * 认证方式的唯一标识
   */
  type: string;

  /**
   * 认证方式的描述，用于UI显示
   */
  description: ResourceStr;
}

/**
 * 认证方式
 */
export class AuthType {
  /**
   * 仅使用密码认证
   */
  public static readonly PASSWORD: AuthTypeInfo = {
    type: 'password',
    description: $r('app.string.auth_type_password')
  };
  /**
   * 密码 + 密钥文件
   */
  public static readonly PASSWORD_KEYFILE: AuthTypeInfo = {
    type: 'password_keyfile',
    description: $r('app.string.auth_type_password_keyfile')
  };
  /**
   * 密码 + 一次性密码
   */
  public static readonly PASSWORD_OTP: AuthTypeInfo = {
    type: 'password_otp',
    description: $r('app.string.auth_type_password_otp')
  };
  /**
   * 密码 + 一次密码（恢复模式）
   */
  public static readonly PASSWORD_OTP_RECOVERY: AuthTypeInfo = {
    type: 'password_otp_recovery',
    description: $r('app.string.auth_type_password_otp_recovery')
  };
  /**
   * 密码 + 挑战-响应
   */
  public static readonly PASSWORD_CHALLENGE_RESPONSE: AuthTypeInfo = {
    type: 'password_challenge_response',
    description: $r('app.string.auth_type_password_challenge_response')
  };
  /**
   * 密码 + 挑战-响应（恢复模式）
   */
  public static readonly PASSWORD_CHALLENGE_RESPONSE_RECOVERY: AuthTypeInfo = {
    type: 'password_challenge_response_recovery',
    description: $r('app.string.auth_type_password_challenge_response_recovery')
  };
  /**
   * 密码 + 挑战-应答（Keepass XC）
   */
  public static readonly PASSWORD_CHALLENGE_RESPONSE_XC: AuthTypeInfo = {
    type: 'password_challenge_response_xc',
    description: $r('app.string.auth_type_password_challenge_response_xc')
  };
  /**
   * 密码 + 密钥文件 + 挑战应答（Keepass XC）
   */
  public static readonly PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC: AuthTypeInfo = {
    type: 'password_keyfile_challenge_response_xc',
    description: $r('app.string.auth_type_password_keyfile_challenge_response_xc')
  };

  /**
   * 获取所有认证方式
   */
  public static getAllTypes(): AuthTypeInfo[] {
    return [
      AuthType.PASSWORD,
      AuthType.PASSWORD_KEYFILE,
      AuthType.PASSWORD_OTP,
      AuthType.PASSWORD_OTP_RECOVERY,
      AuthType.PASSWORD_CHALLENGE_RESPONSE,
      AuthType.PASSWORD_CHALLENGE_RESPONSE_RECOVERY,
      AuthType.PASSWORD_CHALLENGE_RESPONSE_XC,
      AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC
    ];
  }

  /**
   * 根据类型获取认证方式信息
   * @param type 认证方式类型
   * @returns 认证方式信息，如果未找到则返回null
   */
  public static getByType(type: string): AuthTypeInfo | null {
    return AuthType.getAllTypes().find(item => item.type === type) || null;
  }

  /**
   * 判断认证方式是否使用密钥文件
   * @param authType 认证方式
   * @returns 是否使用密钥文件
   */
  public static useKeyAuth(authType: AuthTypeInfo): boolean {
    return authType && (authType.type === AuthType.PASSWORD_KEYFILE.type || authType.type === AuthType.PASSWORD_KEYFILE_CHALLENGE_RESPONSE_XC.type);
  }
}

/**
 * 最近打开文件定义
 */
export interface RecentFile {
  /**
   * 文件路径
   */
  filePath: string;

  /**
   * 文件名
   */
  fileName: string;

  /**
   * 认证方式
   */
  authType?: AuthTypeInfo;

  /**
   * 认证密钥文件路径
   */
  keyFilePath?: string;

  /**
   * 存储类型
   */
  storageType: StorageType;

  /**
   * 存储类型
   */
  storageConfig: StorageConfig;

  /**
   * 加密密码信息
   */
  password?: string;

  /**
   * 搜索历史
   */
  searchHistory?: Array<string>;
}

/**
 * 数据库显示参数定义
 */
export interface DatabaseShowParam {
  groupId?: string;
}

/**
 * 数据库显示参数定义
 */
export interface EntryParam {
  groupId?: string;
  entryId?: string;
  historyIndex?: number;
}


/**
 * 移动条目参数定义
 */
export class MoveParam {
  private static instance: MoveParam | undefined = undefined;
  groupId: string;
  entryId?: string;
  isMoving: boolean;

  constructor(groupId: string, entryId?: string) {
    this.groupId = groupId;
    this.entryId = entryId;
    this.isMoving = true;
    MoveParam.instance = this;
  }

  public static getInstance(): MoveParam | undefined {
    return MoveParam.instance;
  }

  public static clearInstance() {
    MoveParam.instance = undefined;
  }

  /**
   * 判断是否是需要移动的条目
   * @param itemId
   * @returns
   */
  public isMoveItem(itemId: string): boolean {
    if (this.isMoveEntry) {
      return this.entryId === itemId;
    }
    return this.groupId === itemId;
  }

  get isMoveGroup(): boolean {
    return this.entryId === undefined;
  }

  get isMoveEntry(): boolean {
    return this.entryId !== undefined;
  }
}

/**
 * 图标资源定义
 */
export interface IconResource {
  id: number | string,
  resource: ResourceStr;
}


export class Icons {
  public static readonly Key: number = 0;
  public static readonly World: number = 1;
  public static readonly Warning: number = 2;
  public static readonly NetworkServer: number = 3;
  public static readonly MarkedDirectory: number = 4;
  public static readonly UserCommunication: number = 5;
  public static readonly Parts: number = 6;
  public static readonly Notepad: number = 7;
  public static readonly WorldSocket: number = 8;
  public static readonly Identity: number = 9;
  public static readonly PaperReady: number = 10;
  public static readonly Digicam: number = 11;
  public static readonly IRCommunication: number = 12;
  public static readonly MultiKeys: number = 13;
  public static readonly Energy: number = 14;
  public static readonly Scanner: number = 15;
  public static readonly WorldStar: number = 16;
  public static readonly CDRom: number = 17;
  public static readonly Monitor: number = 18;
  public static readonly EMail: number = 19;
  public static readonly Configuration: number = 20;
  public static readonly ClipboardReady: number = 21;
  public static readonly PaperNew: number = 22;
  public static readonly Screen: number = 23;
  public static readonly EnergyCareful: number = 24;
  public static readonly EMailBox: number = 25;
  public static readonly Disk: number = 26;
  public static readonly Drive: number = 27;
  public static readonly PaperQ: number = 28;
  public static readonly TerminalEncrypted: number = 29;
  public static readonly Console: number = 30;
  public static readonly Printer: number = 31;
  public static readonly ProgramIcons: number = 32;
  public static readonly Run: number = 33;
  public static readonly Settings: number = 34;
  public static readonly WorldComputer: number = 35;
  public static readonly Archive: number = 36;
  public static readonly Homebanking: number = 37;
  public static readonly DriveWindows: number = 38;
  public static readonly Clock: number = 39;
  public static readonly EMailSearch: number = 40;
  public static readonly PaperFlag: number = 41;
  public static readonly Memory: number = 42;
  public static readonly TrashBin: number = 43;
  public static readonly Note: number = 44;
  public static readonly Expired: number = 45;
  public static readonly Info: number = 46;
  public static readonly Package: number = 47;
  public static readonly Folder: number = 48;
  public static readonly FolderOpen: number = 49;
  public static readonly FolderPackage: number = 50;
  public static readonly LockOpen: number = 51;
  public static readonly PaperLocked: number = 52;
  public static readonly Checked: number = 53;
  public static readonly Pen: number = 54;
  public static readonly Thumbnail: number = 55;
  public static readonly Book: number = 56;
  public static readonly List: number = 57;
  public static readonly UserKey: number = 58;
  public static readonly Tool: number = 59;
  public static readonly Home: number = 60;
  public static readonly Star: number = 61;
  public static readonly Tux: number = 62;
  public static readonly Feather: number = 63;
  public static readonly Apple: number = 64;
  public static readonly Wiki: number = 65;
  public static readonly Money: number = 66;
  public static readonly Certificate: number = 67;
  public static readonly BlackBerry: number = 68;
}

/**
 * 自定义字段接口
 */
export interface CustomField {
  key: string;
  value: string;
  isProtected: boolean;
}
