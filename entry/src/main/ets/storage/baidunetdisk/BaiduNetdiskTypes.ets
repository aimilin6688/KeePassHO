/**
 * 百度网盘 API 响应接口定义
 */

/** 百度网盘 API 通用响应 */
export interface BaiduApiResponse {
  /** 错误码，0 表示成功 */
  errno: number;
  /** 请求 ID */
  request_id?: number;
  /** 错误信息（当 errno 非 0 时） */
  error_msg?: string;
}

/** 文件信息 */
export interface BaiduFileItem {
  /** 文件 ID */
  fs_id: number;
  /** 文件路径 */
  path: string;
  /** 文件名 */
  server_filename: string;
  /** 文件大小（字节） */
  size: number;
  /** 服务器修改时间（秒时间戳） */
  server_mtime: number;
  /** 服务器创建时间（秒时间戳） */
  server_ctime: number;
  /** 是否为目录，0=文件，1=目录 */
  isdir: 0 | 1;
}

/** 文件列表响应 */
export interface BaiduListResponse extends BaiduApiResponse {
  list: BaiduFileItem[];
  /** 是否有更多 */
  has_more?: number;
}

/** 文件元信息响应 */
export interface BaiduMetaResponse extends BaiduApiResponse {
  info: BaiduFileItem[];
}

/** 上传预创建响应 */
export interface BaiduPreCreateResponse extends BaiduApiResponse {
  /** 返回类型：1=成功，2=已存在 */
  return_type: number;
  /** 上传 ID */
  uploadid: string;
  /** 需要上传的分片序号数组 */
  block_list: number[];
}

/** 分片上传响应 */
export interface BaiduUploadResponse extends BaiduApiResponse {
  /** 分片 MD5 */
  md5: string;
  /** 分片序号 */
  partseq: number;
}

/** 上传完成（创建文件）响应 */
export interface BaiduCreateResponse extends BaiduApiResponse {
  /** 创建的文件路径 */
  path: string;
  /** 文件 ID */
  fs_id: number;
}

/** 下载链接响应 */
export interface BaiduDownloadResponse extends BaiduApiResponse {
  dlink: Array<{
    dlink: string;
    fs_id: number;
  }>;
}

/** 创建文件夹响应 */
export interface BaiduMkdirResponse extends BaiduApiResponse {
  path: string;
  fs_id: number;
}

/** OAuth2.0 Token 响应 */
export interface BaiduTokenResponse {
  access_token: string;
  expires_in: number;
  refresh_token: string;
  scope: string;
  session_key?: string;
  session_secret?: string;
}
