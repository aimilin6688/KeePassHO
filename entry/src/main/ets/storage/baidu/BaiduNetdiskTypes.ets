import { StorageType } from '..';

/**
 * 百度网盘 API errno：access_token 失效（刷新后重试 1 次，仍失败 AUTH_EXPIRED）
 */
export const BAIDU_TOKEN_INVALID_ERRNOS: number[] = [-6, 111, 20016];

/**
 * 百度网盘 API errno：频次限制（指数退避重试）
 * 20012：未审核应用超过频次/次数控制（权限与配额文档）
 */
export const BAIDU_RATE_LIMIT_ERRNOS: number[] = [31034, 31064, 20012];

/**
 * 百度网盘 API errno：文件或目录不存在
 */
export const BAIDU_NOT_FOUND_ERRNOS: number[] = [-9, 50002, 42212];

/**
 * 百度网盘 API errno：uploadid 过期/失效（需重新 precreate）
 */
export const BAIDU_UPLOADID_EXPIRED_ERRNOS: number[] = [31363, 36016];

/**
 * 百度网盘开放平台常量（设计文档 D2/D3/D6/D11）
 */
export class BaiduNetdiskConstants {
  /**
   * xpan 文件 API 基地址
   */
  static readonly PAN_BASE: string = 'https://pan.baidu.com/rest/2.0';
  /**
   * 百度网盘开放平台基地址（无 rest/2.0 前缀的接口，如 api/quota 容量查询）
   */
  static readonly PAN_OPEN_BASE: string = 'https://pan.baidu.com';
  /**
   * PCS API 基地址（locateupload 获取上传域名端点，固定域名）
   */
  static readonly PCS_BASE: string = 'https://d.pcs.baidu.com/rest/2.0';
  /**
   * 应用目录（权限与配额文档：第三方应用仅能操作 /apps/{应用名称} 下的文件，
   * 应用名称与百度控制台登记一致）
   */
  static readonly APP_DIR: string = '/apps/KeePassHO';
  /**
   * locateupload 固定 appid（获取上传域名文档）
   */
  static readonly LOCATEUPLOAD_APPID: string = '250528';
  /**
   * locateupload 失败/未返回可用域名时的兜底上传域名（告警降级，正常流程必须动态获取）
   */
  static readonly DEFAULT_UPLOAD_HOST: string = 'https://d.pcs.baidu.com';
  /**
   * superfile2 分片大小（4MB，全会员类型合法值，D6）
   */
  static readonly SLICE_SIZE: number = 4 * 1024 * 1024;
  /**
   * slice-md5 取前 256KB
   */
  static readonly RAPID_SLICE_MD5_SIZE: number = 256 * 1024;
  /**
   * 下载/预授权 dlink 请求固定 UA（非该 UA 返回 403）
   */
  static readonly DOWNLOAD_UA: string = 'pan.baidu.com';
  /**
   * list 分页大小
   */
  static readonly LIST_PAGE_SIZE: number = 200;
  /**
   * create 覆盖语义（已存在则覆盖）
   */
  static readonly RTYPE_OVERWRITE: number = 3;
}

/**
 * 百度网盘 API 业务错误（errno 体系）
 */
export class BaiduApiError extends Error {
  /**
   * 百度 errno / error_code
   */
  readonly errno: number;
  /**
   * 百度 error_msg / 显示文案
   */
  readonly errorMsg: string;

  constructor(errno: number, errorMsg: string) {
    super(`Baidu API errno=${errno}: ${errorMsg}`);
    this.name = 'BaiduApiError';
    this.errno = errno;
    this.errorMsg = errorMsg;
  }
}

/**
 * 判断错误是否为「文件或目录不存在」
 * @param error 待判断错误
 */
export function isBaiduNotFoundError(error: Object): boolean {
  return error instanceof BaiduApiError && BAIDU_NOT_FOUND_ERRNOS.indexOf(error.errno) >= 0;
}

/**
 * 百度网盘文件元信息（list / filemetas 条目显式拷贝模型）
 */
export interface BaiduFileMeta {
  /**
   * 文件 fs_id
   */
  fsId: number;
  /**
   * 绝对路径（以 / 开头）
   */
  path: string;
  /**
   * 服务端文件名（server_filename）
   */
  serverFilename: string;
  /**
   * 是否目录：1-目录 0-文件
   */
  isdir: number;
  /**
   * 大小（字节，目录为 0）
   */
  size: number;
  /**
   * 内容 md5（可能为混淆值，需 decryptBaiduMd5 还原；目录为空串）
   */
  md5: string;
  /**
   * 预授权下载链接（filemetas dlink=1 时返回，8 小时有效）
   */
  dlink: string;
  /**
   * 服务端创建时间（秒）
   */
  serverCtime: number;
  /**
   * 服务端修改时间（秒）
   */
  serverMtime: number;
}

/**
 * precreate 响应（显式拷贝模型）
 */
export interface BaiduPrecreateResp {
  errno: number;
  /**
   * 1=需要上传分片（携带 uploadid 与待传分片序号）；2=秒传成功
   */
  returnType: number;
  uploadid: string;
  /**
   * 待上传分片序号列表
   */
  blockList: number[];
}

/**
 * 百度网盘用户信息（xpan/nas uinfo 显式拷贝模型）
 */
export interface BaiduUserInfo {
  /**
   * 百度账号名
   */
  baiduName: string;
  /**
   * 网盘账号名
   */
  netdiskName: string;
  /**
   * 头像地址
   */
  avatarUrl: string;
  /**
   * 会员类型（vip_version=v2 语义）：0-普通用户 1-会员用户 2-超级会员用户
   */
  vipType: number;
}

/**
 * 百度网盘容量信息（api/quota 显式拷贝模型）
 */
export interface BaiduNetdiskQuota {
  /**
   * 总空间（字节）
   */
  total: number;
  /**
   * 已用空间（字节）
   */
  used: number;
  /**
   * 剩余空间（字节）
   */
  free: number;
}

/**
 * 百度网盘响应解析工具（JSON.parse 后按显式字段拷贝，禁止动态取键）
 */
export class BaiduNetdiskParser {

  /**
   * 解析 list / filemetas 中的文件条目
   * @param raw JSON 原始对象
   */
  public static parseFileMeta(raw: Record<string, Object>): BaiduFileMeta {
    const meta: BaiduFileMeta = {
      fsId: BaiduNetdiskParser.readNumber(raw, 'fs_id'),
      path: BaiduNetdiskParser.readString(raw, 'path'),
      serverFilename: BaiduNetdiskParser.readString(raw, 'server_filename'),
      isdir: BaiduNetdiskParser.readNumber(raw, 'isdir'),
      size: BaiduNetdiskParser.readNumber(raw, 'size'),
      md5: BaiduNetdiskParser.readString(raw, 'md5').toLowerCase(),
      dlink: BaiduNetdiskParser.readString(raw, 'dlink'),
      serverCtime: BaiduNetdiskParser.readNumber(raw, 'server_ctime'),
      serverMtime: BaiduNetdiskParser.readNumber(raw, 'server_mtime')
    };
    return meta;
  }

  /**
   * 解析 precreate 响应
   * @param raw JSON 原始对象
   */
  public static parsePrecreateResp(raw: Record<string, Object>): BaiduPrecreateResp {
    const resp: BaiduPrecreateResp = {
      errno: BaiduNetdiskParser.readNumber(raw, 'errno'),
      returnType: BaiduNetdiskParser.readNumber(raw, 'return_type'),
      uploadid: BaiduNetdiskParser.readString(raw, 'uploadid'),
      blockList: []
    };
    const blockListRaw = raw['block_list'];
    if (blockListRaw !== undefined && blockListRaw !== null && Array.isArray(blockListRaw)) {
      const arr = blockListRaw as Array<Object>;
      for (let i = 0; i < arr.length; i++) {
        const item = arr[i];
        if (typeof item === 'number') {
          resp.blockList.push(item);
        }
      }
    }
    return resp;
  }

  /**
   * 解析 uinfo 用户信息响应
   * @param raw JSON 原始对象
   */
  public static parseUserInfo(raw: Record<string, Object>): BaiduUserInfo {
    const info: BaiduUserInfo = {
      baiduName: BaiduNetdiskParser.readString(raw, 'baidu_name'),
      netdiskName: BaiduNetdiskParser.readString(raw, 'netdisk_name'),
      avatarUrl: BaiduNetdiskParser.readString(raw, 'avatar_url'),
      vipType: BaiduNetdiskParser.readNumber(raw, 'vip_type')
    };
    return info;
  }

  /**
   * 解析 quota 容量信息响应
   * 剩余空间按 total-used 计算：服务端 free 字段为「免费容量」语义（实测等于 total，非剩余空间）
   * @param raw JSON 原始对象
   */
  public static parseQuota(raw: Record<string, Object>): BaiduNetdiskQuota {
    const total: number = BaiduNetdiskParser.readNumber(raw, 'total');
    const used: number = BaiduNetdiskParser.readNumber(raw, 'used');
    const quota: BaiduNetdiskQuota = {
      total: total,
      used: used,
      free: total >= used ? total - used : 0
    };
    return quota;
  }

  /**
   * 读取 JSON 数字字段（缺失返回 0）
   */
  public static readNumber(raw: Record<string, Object>, key: string): number {
    const value = raw[key];
    if (value !== undefined && value !== null && typeof value === 'number') {
      return value;
    }
    return 0;
  }

  /**
   * 读取 JSON 字符串字段（缺失返回空串）
   */
  public static readString(raw: Record<string, Object>, key: string): string {
    const value = raw[key];
    if (value !== undefined && value !== null && typeof value === 'string') {
      return value;
    }
    return '';
  }

  /**
   * 读取 JSON 对象数组字段（非数组返回空数组）
   */
  public static readObjectArray(raw: Record<string, Object>, key: string): Array<Record<string, Object>> {
    const value = raw[key];
    const result: Array<Record<string, Object>> = [];
    if (value !== undefined && value !== null && Array.isArray(value)) {
      const arr = value as Array<Object>;
      for (let i = 0; i < arr.length; i++) {
        const item = arr[i];
        if (item !== undefined && item !== null && typeof item === 'object') {
          result.push(item as Record<string, Object>);
        }
      }
    }
    return result;
  }

  /**
   * 还原百度混淆 md5（设计文档附录 C，来自 Alist drivers/baidu_netdisk util.go）
   * list/filemetas 返回的 md5 部分情况为混淆值（含 g~z 等非 hex 字符），
   * 需逐位解码并重排后才是真实内容 md5：
   * 1. 合法 32 位 hex 直接返回（未混淆）；
   * 2. 第 10 位（i==9）为非 hex 字符时按 char-'g' 映射，其余按 hex 解析；
   * 3. 每位与 (15 & i) 异或后取 hex；
   * 4. 4 段 8 字符重排：[8:16]+[0:8]+[24:32]+[16:24]。
   * 无法解析（非 32 位/含无法解码字符）时原样返回，由调用方视为无版本。
   * @param mixed 服务端返回的（可能混淆的）md5 字符串
   * @returns 还原后的真实 md5；无法还原时原样返回
   */
  public static decryptBaiduMd5(mixed: string): string {
    if (!mixed || mixed.length !== 32) {
      return mixed;
    }
    // 合法 hex（未混淆）直接返回
    if (/^[0-9a-f]{32}$/.test(mixed)) {
      return mixed;
    }
    let decoded = '';
    for (let i = 0; i < mixed.length; i++) {
      const c = mixed.charAt(i);
      let n: number;
      if (c >= '0' && c <= '9' || c >= 'a' && c <= 'f') {
        n = parseInt(c, 16);
      } else if (i === 9 && c >= 'g' && c <= 'v') {
        n = c.charCodeAt(0) - 'g'.charCodeAt(0);
      } else {
        // 无法解码的混淆串：原样返回
        return mixed;
      }
      decoded += (n ^ (15 & i)).toString(16);
    }
    return decoded.substring(8, 16) + decoded.substring(0, 8)
      + decoded.substring(24, 32) + decoded.substring(16, 24);
  }
}

/**
 * 本存储在 StorageType 中的枚举（供 Client/Storage 内部引用，避免循环依赖）
 */
export const BAIDU_NETDISK_STORAGE_TYPE: StorageType = StorageType.BAIDU_NETDISK;
