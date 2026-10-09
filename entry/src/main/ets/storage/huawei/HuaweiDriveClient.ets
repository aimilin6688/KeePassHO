import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { http } from '@kit.NetworkKit';
import { ByteUtils, KdbxError } from 'kdbxweb';
import { OAuth2Config, OAuth2Token } from '../../common/oauth2/OAuth2Types';
import axios, { AxiosError, AxiosInstance, AxiosProgressEvent, AxiosRequestConfig, AxiosResponse } from '@ohos/axios';
import { StringUtils, UrlUtils } from '../../common/utils';
import { TransferProgressCallback } from '../index';

const DOMAIN = 0x0000;
const TAG = 'HuaweiDriveClient';

/**
 * 华为云盘文件夹 MIME 类型
 * 统一常量，避免各处字符串不一致导致文件夹类型误判
 */
export const HUAWEI_DRIVE_FOLDER_MIME_TYPE = 'application/vnd.huawei-apps.folder';

/**
 * 华为云盘 about 接口返回的用户信息
 */
export interface HuaweiDriveAboutUser {
  /**
   * 用户ID
   */
  id: string;
  /**
   * 显示名称
   */
  displayName: string;
}

/**
 * 华为云盘 about 接口返回的空间信息（单位：字节）
 */
export interface HuaweiDriveAboutSpace {
  /**
   * 总容量（字节）
   */
  totalSpace: number;
  /**
   * 已用容量（字节）
   */
  usedSpace: number;
}

/**
 * 华为云盘 about 接口返回的汇总信息
 */
export interface HuaweiDriveAbout {
  /**
   * 用户信息
   */
  user: HuaweiDriveAboutUser;
  /**
   * 空间信息
   */
  space: HuaweiDriveAboutSpace;
}

/**
 * 父文件夹信息
 */
export interface ParentFolder {
  /**
   * 文件夹ID
   */
  id: string;
}

/**
 * 文件能力信息
 */
export interface FileCapabilities {
  /**
   * 下载权限
   */
  downloadPermission: boolean;
  /**
   * 编辑权限
   */
  editPermission: boolean;
  /**
   * 删除权限
   */
  deletePermission: boolean;
}

/**
 * 上传文件数据接口
 */
interface UploadFileData {
  fileName: string;
  parentFolder: ParentFolder[];
  content: number[];
}

/**
 * 华为云盘文件信息接口
 */
export interface HuaweiDriveFile {
  /**
   * 文件ID
   */
  id: string;

  /**
   * 文件名称
   */
  fileName: string;

  /**
   * 文件类型
   */
  mimeType: string;

  /**
   * 文件大小
   */
  size: number;

  /**
   * 创建时间
   */
  createdTime: string;

  /**
   * 编辑时间
   */
  editedTime: string;

  /**
   * 父文件夹
   */
  parentFolder: ParentFolder[];

  /**
   * 下载链接
   */
  contentDownloadLink?: string;

  /**
   * 文件能力
   */
  capabilities?: FileCapabilities;
}

/**
 * 华为云盘客户端配置选项接口
 */
export interface HuaweiDriveClientOptions {
  /**
   * API基础URL
   */
  apiBaseUrl: string;

  /**
   * 访问令牌
   */
  accessToken: string;

  /**
   * 超时时间（毫秒）
   */
  timeout?: number;
}

/**
 * HTTP响应类（兼容原有接口）
 */
export class HttpResponse {
  /**
   * 是否成功
   */
  success: boolean = true;
  /**
   * HTTP状态码
   */
  statusCode: number = 200;
  /**
   * 错误消息
   */
  message: string = '';
  /**
   * 响应头
   */
  headers: Record<string, string> = {};
  /**
   * 响应体
   */
  body?: ArrayBuffer = undefined;

  constructor(success: boolean, statusCode: number, message: string, headers: Record<string, string>, body?: ArrayBuffer) {
    this.success = success;
    this.statusCode = statusCode;
    this.message = message;
    this.headers = headers;
    this.body = body;
  }
}

/**
 * 断点续传会话（Files.update.resume 初始化产物）
 */
interface ResumeUploadSession {
  /**
   * 续传地址（响应头 Location，含 serverId 与 uploadId），分片 PUT 的目标
   */
  location: string;
  /**
   * 服务端建议的单个分片大小（字节）
   */
  sliceSize: number;
}

/**
 * 文件级下载进度聚合器：多个分块（串行/并行交错）写入的字节数累加后统一上报
 * dataReceive 热路径仅做加法+回调（限频由上层 DatabaseLoad 的 ProgressThrottler 承担）；
 * JS 单线程事件循环下并行分块无需加锁
 */
export class DownloadProgressAggregator {
  private readonly totalBytes: number;
  private readonly onProgress: TransferProgressCallback;
  private transferred: number = 0;

  constructor(totalBytes: number, onProgress: TransferProgressCallback) {
    this.totalBytes = totalBytes;
    this.onProgress = onProgress;
  }

  /**
   * 累加新写入字节数并上报 (transferredBytes, totalBytes)
   */
  add(bytes: number): void {
    this.transferred += bytes;
    this.onProgress(this.transferred, this.totalBytes);
  }
}

/**
 * 单块流式下载写盘器（弱网诊断）
 * dataReceive 网络包按分块起始偏移直写文件（分块间互不重叠，单块内顺序追加），
 * 跟踪已收字节数、写盘错误与最近网络包时间（停滞看门狗依据）；
 * 进度由实收字节驱动限频打印（间隔 ≥2s 或进度增幅 ≥10% 一条）
 * 注：dataReceiveProgress 事件在 requestInStream 场景实测不触发，故不依赖该事件
 */
class ChunkDownloadWriter {
  private readonly fd: number;
  private readonly rangeStart: number;
  private readonly chunkIndex: number;
  private readonly chunkCount: number;
  private readonly expectedSize: number;
  private readonly progress: DownloadProgressAggregator | undefined;
  private lastProgressLogTime: number = 0;
  private lastLoggedPercent: number = -1;
  /**
   * 已接收（并写入）字节数
   */
  received: number = 0;
  /**
   * 写盘错误描述（非空表示写盘失败，后续数据丢弃，请求结束后统一抛错）
   */
  writeError: string = '';
  /**
   * 最近一个网络包到达时间戳（任何 dataReceive 包都会重置，停滞看门狗据此判定连接是否存活）
   */
  lastDataTime: number = Date.now();

  constructor(fd: number, rangeStart: number, expectedSize: number, chunkIndex: number, chunkCount: number,
    progress?: DownloadProgressAggregator) {
    this.fd = fd;
    this.rangeStart = rangeStart;
    this.expectedSize = expectedSize;
    this.chunkIndex = chunkIndex;
    this.chunkCount = chunkCount;
    this.progress = progress;
  }

  /**
   * dataReceive 回调：网络包写入文件偏移并打印进度
   */
  writeChunkData(data: ArrayBuffer): void {
    this.lastDataTime = Date.now();
    if (this.writeError !== '') {
      // 写盘已失败：丢弃后续数据，请求结束后统一抛错
      return;
    }
    try {
      fs.writeSync(this.fd, data, { offset: this.rangeStart + this.received });
      this.received += data.byteLength;
      this.progress?.add(data.byteLength);
      if(hilog.isLoggable(DOMAIN, TAG, hilog.LogLevel.DEBUG)){
        this.logProgress();
      }
    } catch (error) {
      this.writeError = `write file failed at offset ${this.rangeStart + this.received}: ${(error as Error).message}`;
      hilog.error(DOMAIN, TAG, 'download chunk %{public}d write error: %{public}s', this.chunkIndex + 1, this.writeError);
    }
  }

  /**
   * 限频打印字节级下载进度（百分比相对分块期望字节数；整内容回退时可能大于 100%，本身即是诊断信号）
   */
  private logProgress(): void {
    const now = Date.now();
    const percent = this.expectedSize > 0 ? Math.floor(this.received * 100 / this.expectedSize) : -1;
    if (now - this.lastProgressLogTime >= 2000 || percent - this.lastLoggedPercent >= 10) {
      this.lastProgressLogTime = now;
      this.lastLoggedPercent = percent;
      hilog.info(DOMAIN, TAG,
        'download progress: chunk %{public}d/%{public}d, %{public}d/%{public}d bytes (%{public}d%%)',
        this.chunkIndex + 1, this.chunkCount, this.received, this.expectedSize, percent);
    }
  }
}

/**
 * 华为云盘客户端类
 * 用于与华为Drive API交互，操作云盘文件
 */
export class HuaweiDriveClient {
  /**
   * Axios实例
   */
  private axiosInstance: AxiosInstance | null = null;
  /**
   * 客户端配置
   */
  private config: HuaweiDriveClientOptions | null = null;
  /**
   * OAuth2配置
   */
  private oauth2Config: OAuth2Config | null = null;
  /**
   * rcp 会话（S7 流式上传专用，懒创建复用）
   */
  private rcpSession: rcp.Session | null = null;
  /**
   * content 方式简单上传大小上限（官方文档：超过 20M 的文件用 Files.update.resume 接口）
   */
  private static readonly SIMPLE_UPLOAD_MAX_BYTES: number = 20 * 1024 * 1024;
  /**
   * 单个分片上传大小上限（官方文档：单次上传大小限制为 64M）
   */
  private static readonly RESUME_SLICE_MAX_BYTES: number = 64 * 1024 * 1024;
  /**
   * 服务端未返回 sliceSize 时的默认分片大小（官方示例为 4M）
   */
  private static readonly RESUME_SLICE_DEFAULT_BYTES: number = 4 * 1024 * 1024;
  /**
   * 单个分片（含断点查询）最大尝试次数：失败自动重试，重试前重新读取分片
   */
  private static readonly RESUME_CHUNK_MAX_ATTEMPTS: number = 3;
  /**
   * 流式下载分块大小（Range GET 请求粒度）
   */
  private static readonly DOWNLOAD_CHUNK_SIZE: number = 8 * 1024 * 1024;
  /**
   * 并发下载分块数阈值：分块数低于该值走串行路径，避免并发开销
   */
  private static readonly DOWNLOAD_PARALLEL_THRESHOLD: number = 2;
  /**
   * 并发下载路数（连接窗口 = 并发数 × 分块大小）
   */
  private static readonly DOWNLOAD_PARALLELISM: number = 3;
  /**
   * 下载停滞判定时长：连续无任何网络包超过该值视为连接已静默断开，中止请求防挂死；
   * 慢速涓流不受影响（任何 dataReceive 包都会重置计时）
   */
  private static readonly DOWNLOAD_STALL_TIMEOUT_MS: number = 60000;
  /**
   * 下载停滞看门狗检查间隔
   */
  private static readonly DOWNLOAD_STALL_CHECK_INTERVAL_MS: number = 5000;

  /**
   * 构造函数
   * @param options 客户端配置选项
   * @param oauth2Config OAuth2配置（用于刷新令牌）
   */
  constructor(options?: HuaweiDriveClientOptions, oauth2Config?: OAuth2Config) {
    if (options !== undefined) {
      this.updateOptions(options);
    }
    if (oauth2Config !== undefined) {
      this.oauth2Config = oauth2Config;
    }
  }

  /**
   * 更新客户端配置
   * @param options 客户端配置选项
   */
  public updateOptions(options: HuaweiDriveClientOptions): void {
    this.config = options;
    const headers: Record<string, string> = {
      'Accept': 'application/json',
      'Content-Type': 'application/json'
    };
    if (options.accessToken) {
      headers['Authorization'] = `Bearer ${options.accessToken}`;
    }
    hilog.info(DOMAIN, TAG, `updateOptions: baseURL=${options.apiBaseUrl}, accessToken length=${options.accessToken.length}`);
    this.axiosInstance = axios.create({
      baseURL: options.apiBaseUrl,
      timeout: options.timeout || 30000,
      headers: headers
    });
  }

  /**
   * 设置OAuth2配置
   * @param config OAuth2配置
   */
  public setOAuth2Config(config: OAuth2Config): void {
    this.oauth2Config = config;
  }

  /**
   * 更新访问令牌
   * @param accessToken 访问令牌
   */
  public updateAccessToken(accessToken: string): void {
    if (this.config && this.axiosInstance) {
      this.config.accessToken = accessToken;
      this.axiosInstance.defaults.headers['Authorization'] = `Bearer ${accessToken}`;
    }
  }

  /**
   * 关闭连接
   */
  public close(): void {
    this.axiosInstance = null;
  }

  /**
   * 重新获取连接
   */
  public connection(): void {
    if (this.config != null) {
      this.updateOptions(this.config);
    }
  }

  /**
   * URL编码
   * @param data 要编码的数据
   * @returns 编码后的字符串
   */
  private urlEncode(data: Record<string, string>): string {
    const params: string[] = [];
    const entries: Array<[string, string]> = Object.entries(data);
    for (let i = 0; i < entries.length; i++) {
      const key = entries[i][0];
      const value = entries[i][1];
      params.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    }
    return params.join('&');
  }

  /**
   * 从对象中提取字符串值
   * @param obj 对象
   * @param key 键
   * @param defaultValue 默认值
   * @returns 字符串值
   */
  private extractStringFromObject(obj: Record<string, Object>, key: string, defaultValue?: string): string {
    const value = obj[key];
    if (value !== undefined && value !== null && typeof value === 'string') {
      return value;
    }
    if (defaultValue !== undefined) {
      return defaultValue;
    }
    throw new Error(`Missing required field: ${key}`);
  }

  /**
   * 从对象中提取可选字符串值
   * @param obj 对象
   * @param key 键
   * @returns 字符串值或undefined
   */
  private extractOptionalStringFromObject(obj: Record<string, Object>, key: string): string {
    const value = obj[key];
    if (value !== undefined && value !== null && typeof value === 'string') {
      return value;
    }
    return '';
  }

  /**
   * 从对象中提取可选数字值
   * @param obj 对象
   * @param key 键
   * @returns 数字值或undefined
   */
  private extractOptionalNumberFromObject(obj: Record<string, Object>, key: string): number | undefined {
    const value = obj[key];
    if (value !== undefined && value !== null && typeof value === 'number') {
      return value;
    }
    return undefined;
  }

  /**
   * 转换Axios响应为HttpResponse
   * @param response Axios响应
   * @returns HttpResponse
   */
  private convertAxiosResponse(response: AxiosResponse): HttpResponse {
    const headers: Record<string, string> = {};
    if (response.headers) {
      const headerEntries = Object.entries(response.headers) as Array<[string, string]>;
      for (let i = 0; i < headerEntries.length; i++) {
        const key = headerEntries[i][0];
        const value = headerEntries[i][1];
        headers[key] = value;
      }
    }

    let body: ArrayBuffer | undefined = undefined;
    if (response.data) {
      if (response.data instanceof ArrayBuffer) {
        body = response.data;
      } else if (typeof response.data === 'object') {
        const jsonStr = JSON.stringify(response.data);
        body = ByteUtils.stringToBytes(jsonStr);
      } else if (typeof response.data === 'string') {
        body = ByteUtils.stringToBytes(response.data);
      }
    }

    return new HttpResponse(
      true,
      response.status,
      response.statusText || '',
      headers,
      body
    );
  }

  /**
   * 转换Axios错误为HttpResponse
   * @param error Axios错误
   * @returns HttpResponse
   */
  private convertAxiosError(error: AxiosError): HttpResponse {
    hilog.error(DOMAIN, TAG, `AxiosError: error=${error.message}`);
    const headers: Record<string, string> = {};
    if (error.response?.headers) {
      const headerEntries = Object.entries(error.response.headers) as Array<[string, string]>;
      for (let i = 0; i < headerEntries.length; i++) {
        const key = headerEntries[i][0];
        const value = headerEntries[i][1];
        headers[key] = value;
      }
    }

    let errorData: ArrayBuffer | undefined = undefined;
    let errorMessage = error.message || 'Unknown error';
    let errorCode = error.response?.status || 0;

    // 尝试从响应数据中提取详细错误信息
    if (error.response?.data) {
      if (error.response.data instanceof ArrayBuffer) {
        errorData = error.response.data;
        try {
          const errorText = ByteUtils.bytesToString(errorData);
          hilog.error(DOMAIN, TAG, `Response error data: ${errorText}`);
          const errorJson = JSON.parse(errorText) as Record<string, Object>;
          const errorInfo = this.parseHuaweiDriveError(errorJson);
          if (errorInfo.message) {
            errorMessage = errorInfo.message;
          }
          if (errorInfo.code) {
            hilog.error(DOMAIN, TAG, `Huawei Drive Error Code: ${errorInfo.code}`);
          }
        } catch (e) {
          hilog.error(DOMAIN, TAG, `Failed to parse error response: ${(e as Error).message}`);
        }
      } else if (typeof error.response.data === 'object') {
        const errorObj = error.response.data as Record<string, Object>;
        const errorInfo = this.parseHuaweiDriveError(errorObj);
        if (errorInfo.message) {
          errorMessage = errorInfo.message;
        }
        if (errorInfo.code) {
          hilog.error(DOMAIN, TAG, `Huawei Drive Error Code: ${errorInfo.code}`);
        }
      }
    }

    return new HttpResponse(
      false,
      errorCode,
      errorMessage,
      headers,
      errorData
    );
  }

  /**
   * 解析华为云盘API错误响应
   * @param errorJson 错误JSON对象
   * @returns 错误信息（code 和 message）
   */
  private parseHuaweiDriveError(errorJson: Record<string, Object>): KdbxError {
    let r_code = '';
    let r_message = '';
    if (errorJson.error) {
      const errorObj = errorJson.error as Record<string, Object>;
      // 提取错误代码
      const code = this.extractOptionalStringFromObject(errorObj, 'code');
      if (code) {
        r_code = code;
        r_message = errorObj ? this.extractOptionalStringFromObject(errorObj, 'message') : '';
      }
    } else if (errorJson.errorCode) {
      r_code = this.extractOptionalStringFromObject(errorJson, 'errorCode');
      r_message = this.extractOptionalStringFromObject(errorJson, 'errorMsg');
    }
    return new KdbxError(r_code, r_message);
  }

  /**
   * 刷新访问令牌
   * @param refreshToken 刷新令牌
   * @returns Promise<OAuth2Token> 新的令牌信息
   */
  public async refreshToken(refreshToken: string): Promise<OAuth2Token> {
    if (!this.oauth2Config) {
      throw new Error('OAuth2 config not set');
    }

    try {
      // 华为账号服务「刷新用户级凭证」接口要求必传 client_secret（机密客户端），
      // 否则返回 HTTP 400 (sub_error=12304, error_description=invalid client_secret)。
      // redirect_uri 仅 authorization_code 模式需要，刷新接口不要求，此处移除以与文档对齐。
      const body: Record<string, string> = {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': this.oauth2Config.clientId,
        'client_secret': this.oauth2Config.clientSecret
      };

      const url = this.oauth2Config.tokenEndpoint;

      const config: AxiosRequestConfig = {
        timeout: this.config?.timeout || 30000,
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        }
      };
      const response: AxiosResponse = await axios.post(url, this.urlEncode(body), config);

      const httpResponse = this.convertAxiosResponse(response);
      if (httpResponse.success && httpResponse.body) {
        const jsonStr = ByteUtils.bytesToString(httpResponse.body);
        return this.parseTokenResponse(JSON.parse(jsonStr));
      } else {
        throw new Error(`HTTP ${httpResponse.statusCode}: ${httpResponse.message}`);
      }
    } catch (error) {
      // 解析华为返回的详细错误（sub_error / error_description），便于定位 400 根因
      const err: Error = error as Error;
      const axiosErr: AxiosError = error as AxiosError;
      let detail: string = err.message;
      // axios 的 response.data 类型为 unknown，需显式 cast 为 Object，避免触发 arkts-no-any-unknown
      const respData: Object | undefined = axiosErr.response?.data as Object | undefined;
      if (respData) {
        try {
          if (respData instanceof ArrayBuffer) {
            detail = ByteUtils.bytesToString(respData);
          } else if (typeof respData === 'object') {
            detail = JSON.stringify(respData);
          } else {
            detail = String(respData);
          }
        } catch {
          // 解析失败则保留原始 message
        }
      }
      hilog.error(DOMAIN, TAG, 'Refresh token failed: %{public}s, response: %{public}s', err.message, detail);
      throw new Error(`Refresh token failed: ${err.message}`);
    }
  }

  /**
   * 验证连接
   * @returns Promise<HttpResponse> 验证结果
   */
  public async valid(): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      // 华为云盘 API 要求 fields 参数
      const response: AxiosResponse = await this.axiosInstance.get('/about?fields=*');
      return this.convertAxiosResponse(response);
    } catch (error) {
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 获取云盘汇总信息（用户显示名、总容量、已用容量）
   * GET /about?fields=*
   * @returns Promise<HttpResponse> 响应
   */
  public async getAbout(): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      const response: AxiosResponse = await this.axiosInstance.get('/about?fields=*');
      return this.convertAxiosResponse(response);
    } catch (error) {
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 解析 about 接口返回的汇总信息
   * 实际返回结构：
   * {
   *   "user": { "displayName": "xxx", "permissionId": "xxx", "category": "drive#user" },
   *   "storageQuota": { "usedSpace": "1458200675", "userCapacity": "5368709120" },
   *   "category": "drive#about",
   *   ...
   * }
   * @param data API 响应数据
   * @returns HuaweiDriveAbout 汇总信息
   */
  public parseAbout(data: Record<string, Object>): HuaweiDriveAbout {
    // 解析用户信息：data.user.displayName / data.user.permissionId
    let userId = '';
    let displayName = '';
    const userObj = data['user'];
    if (userObj && typeof userObj === 'object') {
      const user = userObj as Record<string, Object>;
      userId = this.extractOptionalStringFromObject(user, 'permissionId');
      displayName = this.extractOptionalStringFromObject(user, 'displayName');
    }

    // 解析空间信息：data.storageQuota.userCapacity / data.storageQuota.usedSpace
    // 注意：usedSpace 和 userCapacity 均为字符串类型，需转换为数字
    let totalSpace = 0;
    let usedSpace = 0;
    const quotaObj = data['storageQuota'];
    if (quotaObj && typeof quotaObj === 'object') {
      const quota = quotaObj as Record<string, Object>;
      const userCapacityStr = this.extractOptionalStringFromObject(quota, 'userCapacity');
      const usedSpaceStr = this.extractOptionalStringFromObject(quota, 'usedSpace');
      if (userCapacityStr) {
        totalSpace = Number(userCapacityStr) || 0;
      }
      if (usedSpaceStr) {
        usedSpace = Number(usedSpaceStr) || 0;
      }
    }

    const user: HuaweiDriveAboutUser = { id: userId, displayName: displayName };
    const space: HuaweiDriveAboutSpace = { totalSpace: totalSpace, usedSpace: usedSpace };
    return { user: user, space: space };
  }

  /**
   * 获取文件/文件夹信息
   * @param fileId 文件ID，不传则获取根目录
   * @returns Promise<HttpResponse> 结果信息
   */
  public async getInfo(fileId: string = 'root'): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      // 华为云盘 API 要求 fields 参数，使用 * 表示获取所有字段
      const apiPath = `/files/${fileId}?fields=*`;
      hilog.info(DOMAIN, TAG, `getInfo: fileId=${fileId}, apiPath=${apiPath}`);
      const response: AxiosResponse = await this.axiosInstance.get(apiPath);
      return this.convertAxiosResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `getInfo error: fileId=${fileId}, error=${(error as Error).message}`);
      if ((error as AxiosError).response?.data) {
        hilog.error(DOMAIN, TAG, `Response data: %{public}s`, JSON.stringify((error as AxiosError).response?.data));
      }
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 列出目录内容
   * 根据华为云盘 API 文档，使用 GET /files 接口，通过 queryParam 过滤：
   * - recycled=false：排除回收站文件
   * - '{folderId}' in parentFolder：只返回指定父目录下的文件
   * @param folderId 文件夹ID，'root' 表示根目录
   * @param cursor 分页游标（可选）
   * @returns Promise<HttpResponse> 结果信息
   */
  public async list(folderId: string = 'root', cursor?: string): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      // 构建华为 API queryParam 查询语句：recycled=false and '{folderId}' in parentFolder
      const queryParamStmt = `recycled=false and '${folderId}' in parentFolder`;
      const params: string[] = [
        'fields=*',
        `queryParam=${encodeURIComponent(queryParamStmt)}`
      ];
      if (cursor) {
        params.push(`cursor=${encodeURIComponent(cursor)}`);
      }
      const apiPath = `/files?${params.join('&')}`;
      hilog.info(DOMAIN, TAG, `list: folderId=${folderId}, apiPath=${apiPath}`);

      const response: AxiosResponse = await this.axiosInstance.get(apiPath);
      return this.convertAxiosResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `list error: folderId=${folderId}, error=${(error as Error).message}`);
      if ((error as AxiosError).response?.data) {
        hilog.error(DOMAIN, TAG, `Response data: %{public}s`, JSON.stringify((error as AxiosError).response?.data));
      }
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 下载文件
   * 根据华为云盘 API 文档，下载文件需要使用 form=content 参数
   * @param fileId 文件ID
   * @returns Promise<HttpResponse> 结果信息
   */
  public async download(fileId: string): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      // 华为云盘 API: GET /files/{fileId}?form=content
      const apiPath = `/files/${fileId}?form=content`;
      hilog.info(DOMAIN, TAG, `download: fileId=${fileId}, apiPath=${apiPath}`);

      const config: AxiosRequestConfig = {
        responseType: 'array_buffer'
      };
      const response: AxiosResponse = await this.axiosInstance.get(apiPath, config);
      return this.convertAxiosResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `download error: fileId=${fileId}, error=${(error as Error).message}`);
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 将 http 栈错误码转换为可读原因（2300000 + libcurl 错误码，弱网诊断用）
   * 2300018：对端（网关/CDN/NAT）在 body 传完前关闭连接，收到的字节数不足 Content-Length
   * @param code http 栈回调错误码（0 表示非网络错误）
   * @returns 可读原因描述
   */
  private static describeHttpErrorCode(code: number): string {
    if (code === 2300018) {
      return 'connection closed by peer before full body received (partial file, common on weak network)';
    }
    if (code === 2300028) {
      return 'operation timed out';
    }
    if (code === 2300056) {
      return 'failure receiving network data';
    }
    if (code === 2300007) {
      return 'failed to connect to host';
    }
    if (code === 2300006) {
      return 'could not resolve host';
    }
    if (code === 2300035) {
      return 'SSL/TLS connect error';
    }
    return 'see error detail';
  }

  /**
   * 错误详情文本：http 栈错误（BusinessError）序列化保留 extendInfo 诊断字段；本地错误仅取 message
   */
  private static chunkErrorDetail(error: BusinessError): string {
    return typeof error.code === 'number' ? JSON.stringify(error) : error.message;
  }

  /**
   * 打印分块下载失败详情：失败分块、Range、已收/期望字节数、耗时、错误码与可读原因
   */
  private static logChunkFailure(chunkIndex: number, chunkCount: number, rangeHeader: string,
    received: number, expected: number, elapsedMs: number, error: BusinessError): void {
    const errorCode: number = typeof error.code === 'number' ? error.code : 0;
    hilog.error(DOMAIN, TAG,
      'download chunk %{public}d/%{public}d failed: range=%{public}s, received=%{public}d/%{public}d bytes, elapsed=%{public}dms, code=%{public}d, cause=%{public}s',
      chunkIndex + 1, chunkCount, rangeHeader, received, expected, elapsedMs, errorCode,
      HuaweiDriveClient.describeHttpErrorCode(errorCode));
    hilog.error(DOMAIN, TAG, 'download chunk error detail: %{public}s',
      HuaweiDriveClient.chunkErrorDetail(error));
  }

  /**
   * 流式分块下载文件到本地文件（S7：华为 Drive form=content 端点支持 Range GET）
   * requestInStream + dataReceive 网络包直写盘：内存窗口 = 单个网络包，与文件/分块大小解耦；
   * 首块若返回 200（Range 不支持）退化为整内容；分块数少走串行，多块按并发窗口下载（各块独立偏移写盘）
   * 弱网诊断：按块打印字节级下载进度，失败时记录失败分块、已收/期望字节数、耗时、错误码与可读原因
   * @param fileId 文件 ID
   * @param destPath 本地目标文件路径（调用方管理生命周期）
   * @param knownSize 已知文件大小（findFileByPath 已取得时透传，免内部二次 getInfo；缺省时自行 getInfo）
   * @param onProgress 下载进度回调（可选）：分块写盘字节实时累加上报，未传入时行为不变
   * @returns 下载字节数
   */
  public async downloadRangeToFile(fileId: string, destPath: string, knownSize?: number,
    onProgress?: TransferProgressCallback): Promise<number> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    const config: HuaweiDriveClientOptions | null = this.config;
    if (!config) {
      throw new Error('Client config not initialized');
    }
    const fileSize: number = await this.resolveDownloadFileSize(fileId, knownSize);
    if (fileSize === 0) {
      const empty = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.close(empty.fd);
      return 0;
    }
    const chunkRanges: Array<number[]> = HuaweiDriveClient.buildChunkRanges(fileSize);
    hilog.info(DOMAIN, TAG, 'download start: fileId=%{public}s, fileSize=%{public}d, chunks=%{public}d, chunkSize=%{public}d',
      fileId, fileSize, chunkRanges.length, HuaweiDriveClient.DOWNLOAD_CHUNK_SIZE);

    const file = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    const startTime = Date.now();
    // 进度聚合器：未提供回调时不构造（零开销），提供时分块写盘路径实时累加
    const progress: DownloadProgressAggregator | undefined = onProgress
      ? new DownloadProgressAggregator(fileSize, onProgress)
      : undefined;
    try {
      const url = `${config.apiBaseUrl.replace(/\/+$/, '')}/files/${fileId}?form=content`;
      let downloaded: number;
      if (chunkRanges.length < HuaweiDriveClient.DOWNLOAD_PARALLEL_THRESHOLD) {
        downloaded = await this.downloadChunksSerial(config, url, fileSize, chunkRanges, file, progress);
      } else {
        await this.downloadChunksParallel(config, url, fileSize, chunkRanges, file, progress);
        downloaded = fileSize;
      }
      await fs.fsync(file.fd);
      hilog.info(DOMAIN, TAG, 'download complete: fileId=%{public}s, %{public}d bytes, %{public}d chunks, elapsed=%{public}dms',
        fileId, downloaded, chunkRanges.length, Date.now() - startTime);
      return downloaded;
    } finally {
      await fs.close(file.fd);
    }
  }

  /**
   * 解析下载文件大小（已透传时直接返回，缺省时 getInfo 查询，消除一次冗余请求）
   */
  private async resolveDownloadFileSize(fileId: string, knownSize?: number): Promise<number> {
    if (knownSize && knownSize > 0) {
      return knownSize;
    }
    const infoResp = await this.getInfo(fileId);
    if (!infoResp.success || !infoResp.body) {
      throw new Error(infoResp.message || 'downloadRangeToFile: failed to get file info');
    }
    const infoJson = ByteUtils.bytesToString(infoResp.body);
    const infoData: Record<string, Object> = JSON.parse(infoJson);
    return Number(infoData['size']) || 0;
  }

  /**
   * 切分下载分块（DOWNLOAD_CHUNK_SIZE/块，最后一块为余量）
   */
  private static buildChunkRanges(fileSize: number): Array<number[]> {
    const chunkRanges: Array<number[]> = [];
    for (let start = 0; start < fileSize; start += HuaweiDriveClient.DOWNLOAD_CHUNK_SIZE) {
      chunkRanges.push([start, Math.min(start + HuaweiDriveClient.DOWNLOAD_CHUNK_SIZE - 1, fileSize - 1)]);
    }
    return chunkRanges;
  }

  /**
   * 串行分块下载（单块/双块路径；首块兼容 200 整内容返回）
   * @returns 下载字节数
   */
  private async downloadChunksSerial(config: HuaweiDriveClientOptions, url: string, fileSize: number,
    chunkRanges: Array<number[]>, file: fs.File, progress?: DownloadProgressAggregator): Promise<number> {
    let downloaded = 0;
    for (let i = 0; i < chunkRanges.length; i++) {
      downloaded += await this.downloadChunk(config, url, chunkRanges, i, file, i === 0, fileSize, progress);
      if (downloaded >= fileSize) {
        break;
      }
    }
    return downloaded;
  }

  /**
   * 并发分块下载（窗口 = 并发数 × 块大小，逐块独立偏移写盘保证顺序无关）
   * 任一分块失败即停止后续批次，统一抛错
   */
  private async downloadChunksParallel(config: HuaweiDriveClientOptions, url: string, fileSize: number,
    chunkRanges: Array<number[]>, file: fs.File, progress?: DownloadProgressAggregator): Promise<void> {
    // 失败标记用 string（闭包内赋值，Error|null 的收窄对编译器不可靠）
    let failedMessage: string = '';
    for (let i = 0; i < chunkRanges.length && failedMessage === ''; i += HuaweiDriveClient.DOWNLOAD_PARALLELISM) {
      const batch: Array<Promise<void>> = [];
      for (let j = i; j < Math.min(i + HuaweiDriveClient.DOWNLOAD_PARALLELISM, chunkRanges.length); j++) {
        const task: Promise<void> = this.downloadChunk(config, url, chunkRanges, j, file, false, fileSize, progress)
          .then((_bytes: number): void => {
          })
          .catch((error: BusinessError): void => {
            if (failedMessage === '') {
              failedMessage = error.message ?? 'parallel chunk download failed';
            }
          });
        batch.push(task);
      }
      await Promise.all(batch);
    }
    if (failedMessage !== '') {
      throw new Error(failedMessage);
    }
  }

  /**
   * 单块流式下载（requestInStream + dataReceive 网络包直写盘）
   * @returns 实际写入字节数；首块响应 200（Range 不支持）时返回整文件字节数
   */
  private async downloadChunk(config: HuaweiDriveClientOptions, url: string, chunkRanges: Array<number[]>,
    chunkIndex: number, file: fs.File, allowWholeFile: boolean, fileSize: number,
    progress?: DownloadProgressAggregator): Promise<number> {
    const range: Array<number> = chunkRanges[chunkIndex];
    const expected: number = range[1] - range[0] + 1;
    const rangeHeader = `bytes=${range[0]}-${range[1]}`;
    const chunkCount: number = chunkRanges.length;
    const chunkStart = Date.now();
    const httpRequest = http.createHttp();
    const writer = new ChunkDownloadWriter(file.fd, range[0], expected, chunkIndex, chunkCount, progress);
    try {
      hilog.info(DOMAIN, TAG, 'download chunk %{public}d/%{public}d start: range=%{public}s',
        chunkIndex + 1, chunkCount, rangeHeader);
      httpRequest.on('dataReceive', (data: ArrayBuffer) => {
        writer.writeChunkData(data);
      });
      const statusCode: number = await HuaweiDriveClient.requestChunkStatus(httpRequest, config, url, rangeHeader, writer);
      if (writer.writeError !== '') {
        throw new Error(writer.writeError);
      }
      if (statusCode === 200 && allowWholeFile) {
        // Range 不支持：整内容返回（首块从 0 写入即完整文件）
        hilog.warn(DOMAIN, TAG,
          'download chunk %{public}d: server ignored Range, whole file received=%{public}d, elapsed=%{public}dms',
          chunkIndex + 1, writer.received, Date.now() - chunkStart);
        if (writer.received !== fileSize) {
          throw new Error(`downloadRangeToFile: whole-file fallback incomplete, received ${writer.received}, expected ${fileSize}, status ${statusCode}`);
        }
        return writer.received;
      }
      HuaweiDriveClient.validateChunkResponse(statusCode, writer.received, expected, chunkIndex, chunkCount);
      hilog.info(DOMAIN, TAG, 'download chunk %{public}d/%{public}d done: %{public}d bytes, elapsed=%{public}dms',
        chunkIndex + 1, chunkCount, writer.received, Date.now() - chunkStart);
      return writer.received;
    } catch (error) {
      const err = error as BusinessError;
      HuaweiDriveClient.logChunkFailure(chunkIndex, chunkCount, rangeHeader, writer.received, expected,
        Date.now() - chunkStart, err);
      throw new Error(`download chunk ${chunkIndex + 1}/${chunkCount} failed (${rangeHeader}): ${HuaweiDriveClient.chunkErrorDetail(err)}`);
    } finally {
      httpRequest.off('dataReceive');
      httpRequest.destroy();
    }
  }

  /**
   * 发起单块 Range GET（requestInStream 流式响应），等待响应状态码
   * readTimeout 置 0（不限时）：requestInStream 的 readTimeout 是整体传输时长上限而非空闲超时，
   * 30s 级配置会把弱网慢速传输（8MB 分块需数分钟）整体误杀（错误码 2300028）；
   * 挂死防护改由停滞看门狗承担：连续 DOWNLOAD_STALL_TIMEOUT_MS 无任何网络包即中止请求
   */
  private static requestChunkStatus(httpRequest: http.HttpRequest, config: HuaweiDriveClientOptions,
    url: string, rangeHeader: string, writer: ChunkDownloadWriter): Promise<number> {
    const chunkHeader: Record<string, string> = {
      'Authorization': `Bearer ${config.accessToken}`,
      'Range': rangeHeader
    };
    const requestOptions: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: chunkHeader,
      readTimeout: 0,
      maxLimit: -1
    };
    return new Promise<number>((resolve, reject) => {
      let watchdogTimerId = -1;
      httpRequest.requestInStream(url, requestOptions, (error: BusinessError, code: number) => {
        if (watchdogTimerId !== -1) {
          clearInterval(watchdogTimerId);
        }
        if (error) {
          reject(error);
        } else {
          resolve(code);
        }
      });
      // 停滞看门狗：不限整体时长后，静默断连（无 FIN/RST）会使请求无限挂起，
      // 周期检查距最近一个网络包的间隔，超时即携带已收字节数 reject 并销毁请求
      watchdogTimerId = setInterval(() => {
        if (Date.now() - writer.lastDataTime >= HuaweiDriveClient.DOWNLOAD_STALL_TIMEOUT_MS) {
          clearInterval(watchdogTimerId);
          reject(new Error(`download stalled: no data received for ${HuaweiDriveClient.DOWNLOAD_STALL_TIMEOUT_MS}ms, received ${writer.received} bytes`));
          httpRequest.destroy();
        }
      }, HuaweiDriveClient.DOWNLOAD_STALL_CHECK_INTERVAL_MS);
    });
  }

  /**
   * 校验单块响应：期望 206 且实收字节数与分块一致
   */
  private static validateChunkResponse(statusCode: number, received: number, expected: number,
    chunkIndex: number, chunkCount: number): void {
    if (statusCode !== 206) {
      throw new Error(`downloadRangeToFile: HTTP ${statusCode}, expected 206, received ${received} bytes`);
    }
    if (received !== expected) {
      throw new Error(`downloadRangeToFile: chunk ${chunkIndex + 1}/${chunkCount} incomplete, received ${received} of ${expected} bytes, status ${statusCode}`);
    }
  }

  /**
   * 上传文件
   * 华为云盘上传文件需要两步：
   * 1. 创建文件元数据
   * 2. 上传文件内容（需要使用专门的 upload 端点）
    * 当前实现：先创建文件，然后通过 update 方法上传内容
    * @param parentFolderId 父文件夹ID
    * @param fileName 文件名
    * @param fileBuffer 文件内容
    * @param onProgress 上传进度回调（可选）：透传给 update 按上传方式上报
    * @returns Promise<HttpResponse> 结果信息
    */
  public async upload(parentFolderId: string, fileName: string, fileBuffer: ArrayBuffer,
    onProgress?: TransferProgressCallback): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      // 第一步：创建文件元数据
      // 注意：华为云盘 Files.create 当前仅支持创建目录
      // 对于文件，需要使用专门的 upload 端点
      const createPath = `/files?fields=*`;
      hilog.info(DOMAIN, TAG, `upload: parentFolderId=${parentFolderId}, fileName=${fileName}, size: ${fileBuffer.byteLength}`);

      // 创建文件元数据
      interface CreateFileData {
        fileName: string;
        mimeType: string;
        parentFolder: string[];
      }
      const createData: CreateFileData = {
        fileName: fileName,
        mimeType: 'application/octet-stream',
        parentFolder: [parentFolderId]
      };

      const config: AxiosRequestConfig = {
        headers: {
          'Content-Type': 'application/json'
        }
      };

      const createResponse: AxiosResponse = await this.axiosInstance.post(createPath, createData, config);

      // axios 默认仅 2xx 才 resolve（非 2xx 走 catch 返回失败），此处状态码必为创建成功
      // 兼容响应体为 JSON 字符串或已解析对象两种形式，提取文件ID
      let responseData: Record<string, Object>;
      if (typeof createResponse.data === 'string') {
        responseData = JSON.parse(createResponse.data) as Record<string, Object>;
      } else {
        responseData = createResponse.data as Record<string, Object>;
      }
      const fileId = responseData.id as string;

      if (!fileId) {
        // 创建成功但未返回文件ID，无法继续上传内容，必须视为失败，避免假成功导致内容丢失
        return new HttpResponse(false, createResponse.status, 'Created file has no id', {});
      }

      hilog.info(DOMAIN, TAG, `File created with ID: ${fileId}, now uploading content...`);

      // 第二步：上传文件内容（update 内部按大小自动选择 content / resume 断点续传）
      const result = await this.update(fileId, fileBuffer, onProgress);
      hilog.info(DOMAIN, TAG, 'upload result: %{public}s', result.message);
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `upload error: fileName=${fileName}, error=${(error as Error).message}`);
      if (error instanceof AxiosError) {
        return this.convertAxiosError(error);
      }
      return new HttpResponse(false, 0, (error as Error).message, {});
    }
  }

  /**
    * 更新文件内容
    * 按文件大小自动选择上传方式（官方文档约束）：
    * content 方式仅支持 20M 以内；超过 20M 走 Files.update.resume 断点续传分片上传
    * @param fileId 文件ID
    * @param fileBuffer 文件内容
    * @param onProgress 上传进度回调（可选）：content 方式按 axios 上传字节上报；
    *        resume 方式每个分片被服务端确认后按确认字节上报
    * @returns Promise<HttpResponse> 结果信息
    */
  public async update(fileId: string, fileBuffer: ArrayBuffer,
    onProgress?: TransferProgressCallback): Promise<HttpResponse> {
    try {
      hilog.info(DOMAIN, TAG, `update: fileId=${fileId}, size: ${fileBuffer.byteLength}`);
      if (fileBuffer.byteLength > HuaweiDriveClient.SIMPLE_UPLOAD_MAX_BYTES) {
        return await this.updateByResume(fileId, fileBuffer, onProgress);
      }
      const uploadBase = this.config?.apiBaseUrl?.replace('/drive/v1', '/upload/drive/v1') ||
        'https://driveapis.cloud.huawei.com.cn/upload/drive/v1';
      const url = `${uploadBase}/files/${fileId}?fields=*&uploadType=content`;
      onProgress?.(0, fileBuffer.byteLength);
      const headers: Record<string, string> = {};
      headers['Content-Type'] = 'application/octet-stream';
      headers['Authorization'] = `Bearer ${this.config?.accessToken}`;
      const req = HuaweiDriveClient.buildBufferUploadRequest(url, headers, fileBuffer, onProgress);
      const resp = await this.getRcpSession().fetch(req);
      const result = this.convertRcpResponse(resp);
      if (onProgress && result.success) {
        onProgress(fileBuffer.byteLength, fileBuffer.byteLength);
      }
      hilog.info(DOMAIN, TAG, 'update result: %{public}s, status=%{public}d', result.message, resp.statusCode);
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `update error: fileId=${fileId}, error=${(error as Error).message}`);
      throw new Error((error as Error).message);
    }
  }

  /**
    * 断点续传更新文件内容（Files.update.resume + Files.resume 分片 PUT，内存基线为单个分片）
    * @param fileId 文件ID
    * @param fileBuffer 文件内容
    * @param onProgress 上传进度回调（可选）：透传给分片循环按确认字节上报
    * @returns Promise<HttpResponse> 结果信息（成功时 body 为文件资源 JSON）
    */
  private async updateByResume(fileId: string, fileBuffer: ArrayBuffer,
    onProgress?: TransferProgressCallback): Promise<HttpResponse> {
    const session = await this.initResumeUpload(fileId, fileBuffer.byteLength);
    const readChunk = (offset: number, length: number): Promise<ArrayBuffer> => {
      return Promise.resolve(fileBuffer.slice(offset, offset + length));
    };
    return await this.uploadResumeChunks(session.location, fileBuffer.byteLength, session.sliceSize, readChunk,
      onProgress);
  }

  /**
   * 断点续传初始化（Files.update.resume）
   * PATCH {uploadBase}/files/{fileId}?uploadType=resume&fields=*，请求头携带总长度；
   * 响应头 Location 为续传地址，响应体 sliceSize 为服务端建议分片大小
   * @param fileId 文件ID
   * @param totalBytes 待上传文件总大小
   * @returns ResumeUploadSession 续传会话
   * @throws Error 初始化失败或响应缺少 Location
   */
  private async initResumeUpload(fileId: string, totalBytes: number): Promise<ResumeUploadSession> {
    const uploadBase = this.config?.apiBaseUrl?.replace('/drive/v1', '/upload/drive/v1') ||
      'https://driveapis.cloud.huawei.com.cn/upload/drive/v1';
    hilog.info(DOMAIN, TAG, `initResumeUpload: fileId=${fileId}, totalBytes=${totalBytes}`);
    const config: AxiosRequestConfig = {
      method: 'PATCH',
      url: `${uploadBase}/files/${fileId}?uploadType=resume&fields=*`,
      // request body 仅支持 json 或为空：发送最小 JSON 对象（PATCH 增量更新不改动元数据），
      // 规避空 body + Content-Length: 0 触发服务端 500
      data: '{}',
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'no-cache',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': `${totalBytes}`,
        'Authorization': `Bearer ${this.config?.accessToken}`
      },
      responseType: 'string'
    };
    const response: AxiosResponse = await axios.request(config);
    // axios 响应头非 Record 类型，须遍历 entries 大小写不敏感提取 Location
    let location = '';
    if (response.headers) {
      const headerEntries = Object.entries(response.headers) as Array<[string, string]>;
      for (let i = 0; i < headerEntries.length; i++) {
        if (headerEntries[i][0].toLowerCase() === 'location') {
          location = `${headerEntries[i][1] ?? ''}`;
          break;
        }
      }
    }
    if (!location) {
      throw new Error(`resume init: missing Location header, status=${response.status}`);
    }
    let sliceSize = HuaweiDriveClient.RESUME_SLICE_DEFAULT_BYTES;
    const rawBody = typeof response.data === 'string' ? response.data : JSON.stringify(response.data);
    try {
      const parsed = JSON.parse(rawBody) as Record<string, Object>;
      const rawSliceSize = parsed['sliceSize'];
      if (typeof rawSliceSize === 'number' && rawSliceSize > 0) {
        sliceSize = Math.min(rawSliceSize, HuaweiDriveClient.RESUME_SLICE_MAX_BYTES);
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, `resume init: parse sliceSize failed, use default: ${(error as Error).message}`);
    }
    return { location: location, sliceSize: sliceSize };
  }

  /**
   * 分片循环上传（Files.resume）：PUT 到续传地址，Content-Range: bytes start-end/total；
   * 308=已接收继续传，200/201=完成；全部分片发送后服务端仍返回 308 时，
   * 再触发一次空 body PUT（查询断点状态）获取文件元数据。
   * 单个分片失败自动重试（重试前重新读取分片，规避 http 栈对请求体的瞬时异常）
   * @param location 续传地址（initResumeUpload 返回的 Location）
   * @param totalBytes 文件总大小
   * @param sliceSize 单个分片大小
   * @param readChunk 分片读取器：从 offset 起读取 length 字节，返回实际内容
   * @param onProgress 上传进度回调（可选）：每个分片被服务端确认（308/200）后按确认字节上报
   * @returns Promise<HttpResponse> 结果信息（成功时 body 为文件资源 JSON）
   */
  private async uploadResumeChunks(location: string, totalBytes: number, sliceSize: number,
    readChunk: (offset: number, length: number) => Promise<ArrayBuffer>,
    onProgress?: TransferProgressCallback): Promise<HttpResponse> {
    const chunkSize = Math.min(sliceSize, HuaweiDriveClient.RESUME_SLICE_MAX_BYTES);
    const maxAttempts = HuaweiDriveClient.RESUME_CHUNK_MAX_ATTEMPTS;
    const session = this.getRcpSession();
    let offset = 0;
    while (offset < totalBytes) {
      const wantLen = Math.min(chunkSize, totalBytes - offset);
      let chunk = await readChunk(offset, wantLen);
      let accepted = -1;
      for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        const chunkLen = chunk.byteLength;
        if (chunkLen <= 0) {
          return new HttpResponse(false, 0, 'resume upload: unexpected empty chunk', {});
        }
        const headers: Record<string, string> = {};
        headers['Content-Type'] = 'application/octet-stream';
        headers['Content-Range'] = `bytes ${offset}-${offset + chunkLen - 1}/${totalBytes}`;
        headers['Authorization'] = `Bearer ${this.config?.accessToken}`;
        const chunkOnProgress: TransferProgressCallback | undefined = onProgress
          ? (transferred: number, _total: number): void => {
              onProgress(offset + transferred, totalBytes);
            }
          : undefined;
        const req = HuaweiDriveClient.buildBufferUploadRequest(location, headers, chunk, chunkOnProgress, 'PUT');
        try {
          hilog.info(DOMAIN, TAG, 'resume PUT: offset=%{public}d, len=%{public}d, attempt=%{public}d/%{public}d',
            offset, chunkLen, attempt, maxAttempts);
          const resp = await session.fetch(req);
          const statusCode = resp.statusCode;
          if (statusCode === 200 || statusCode === 201) {
            if (onProgress) {
              onProgress(offset + chunkLen, totalBytes);
            }
            return this.convertRcpResponse(resp);
          }
          if (statusCode !== 308) {
            hilog.error(DOMAIN, TAG, 'resume PUT rejected: status=%{public}d, offset=%{public}d',
              statusCode, offset);
            return this.convertRcpResponse(resp);
          }
          accepted = chunkLen;
          break;
        } catch (error) {
          hilog.error(DOMAIN, TAG, 'resume PUT attempt %{public}d/%{public}d failed: offset=%{public}d, ' +
            'len=%{public}d, error=%{public}s', attempt, maxAttempts, offset, chunkLen, (error as Error).message);
          if (attempt < maxAttempts) {
            chunk = await readChunk(offset, wantLen);
          }
        }
      }
      if (accepted < 0) {
        return new HttpResponse(false, 0,
          `resume upload: chunk failed after ${maxAttempts} attempts, offset=${offset}`, {});
      }
      offset += accepted;
      if (onProgress) {
        onProgress(offset, totalBytes);
      }
    }
    for (let attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        hilog.info(DOMAIN, TAG, 'resume query: attempt=%{public}d/%{public}d', attempt, maxAttempts);
        const queryHeaders: Record<string, string> = {};
        queryHeaders['Authorization'] = `Bearer ${this.config?.accessToken}`;
        queryHeaders['Content-Length'] = '0';
        const queryRequest = new rcp.Request(location, 'PUT', queryHeaders);
        const queryResponse = await session.fetch(queryRequest);
        const queryOk = queryResponse.statusCode === 200 || queryResponse.statusCode === 201;
        if (!queryOk) {
          hilog.error(DOMAIN, TAG, 'resume query failed: status=%{public}d, body=%{public}s',
            queryResponse.statusCode, queryResponse.toString());
        }
        return this.convertRcpResponse(queryResponse);
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'resume query attempt %{public}d/%{public}d failed: error=%{public}s',
          attempt, maxAttempts, (error as Error).message);
      }
    }
    return new HttpResponse(false, 0,
      `resume upload: breakpoint query failed after ${maxAttempts} attempts`, {});
  }

  /**
   * 获取/创建 rcp 会话（S7 流式上传专用，懒创建实例级复用）
   */
  private getRcpSession(): rcp.Session {
    if (!this.rcpSession) {
      this.rcpSession = rcp.createSession({
        requestConfiguration: {
          transfer: {
            timeout: { connectMs: 30000 }
          }
        }
      });
    }
    return this.rcpSession;
  }

  /**
   * rcp.Response → HttpResponse 转换（S7 流式上传）
   */
  private convertRcpResponse(resp: rcp.Response): HttpResponse {
    const ok = resp.statusCode >= 200 && resp.statusCode < 300;
    const headers: Record<string, string> = {};
    let body: ArrayBuffer | undefined = undefined;
    const bodyText = resp.toString();
    if (bodyText) {
      body = ByteUtils.stringToBytes(bodyText);
    }
    return new HttpResponse(ok, resp.statusCode, ok ? 'success' : `HTTP ${resp.statusCode}`, headers, body);
  }

  /**
   * 流式更新文件内容（S7：rcp Request + UploadFromFile，PATCH 请求体不驻内存）
   * 内存窗口 = rcp 内部分块，与文件大小解耦（解除 CP-UP 约束）
   * 按文件大小自动选择上传方式：content 方式仅支持 20M 以内，超过 20M 走 resume 断点续传分片上传
   * @param fileId 文件ID
   * @param srcPath 本地源文件路径
   * @param onProgress 上传进度回调（可选）：>20MB 走续传按片字节精确上报；
   *        ≤20MB 单次 PUT 尝试 rcp tracing onUploadProgress（对文件体未验证），
   *        并以首条 0% 与成功末条 100% 粗粒度兜底，未传入时行为不变
   * @returns Promise<HttpResponse> 结果信息
   */
  public async updateFromFile(fileId: string, srcPath: string,
    onProgress?: TransferProgressCallback): Promise<HttpResponse> {
    const uploadBase = this.config?.apiBaseUrl?.replace('/drive/v1', '/upload/drive/v1') ||
      'https://driveapis.cloud.huawei.com.cn/upload/drive/v1';
    const url = `${uploadBase}/files/${fileId}?fields=*&uploadType=content`;
    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'application/octet-stream';
    headers['Authorization'] = `Bearer ${this.config?.accessToken}`;
    try {
      hilog.info(DOMAIN, TAG, `updateFromFile: fileId=${fileId}, srcPath=${srcPath}`);
      const totalBytes = fs.statSync(srcPath).size;
      if (totalBytes > HuaweiDriveClient.SIMPLE_UPLOAD_MAX_BYTES) {
        return await this.updateFromFileByResume(fileId, srcPath, onProgress);
      }
      onProgress?.(0, totalBytes);
      const file = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
      let fileBuffer: ArrayBuffer;
      try {
        fileBuffer = new ArrayBuffer(totalBytes);
        const readLen = fs.readSync(file.fd, fileBuffer);
        if (readLen < totalBytes) {
          fileBuffer = fileBuffer.slice(0, readLen);
        }
      } finally {
        fs.closeSync(file.fd);
      }
      const req = HuaweiDriveClient.buildBufferUploadRequest(url, headers, fileBuffer, onProgress);
      const resp = await this.getRcpSession().fetch(req);
      const result = this.convertRcpResponse(resp);
      if (onProgress && result.success) {
        onProgress(totalBytes, totalBytes);
      }
      hilog.info(DOMAIN, TAG, 'updateFromFile result: %{public}s, status=%{public}d', result.message, resp.statusCode);
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `updateFromFile error: fileId=${fileId}, error=${(error as Error).message}`);
      throw new Error((error as Error).message);
    }
  }

  private static buildBufferUploadRequest(url: string, headers: Record<string, string>, fileBuffer: ArrayBuffer,
    onProgress?: TransferProgressCallback, method: string = 'PATCH'): rcp.Request {
    if (!onProgress) {
      return new rcp.Request(url, method, headers, fileBuffer);
    }
    const configuration: rcp.Configuration = {
      tracing: {
        httpEventsHandler: {
          onUploadProgress: (totalSize: number, transferredSize: number): void => {
            onProgress(transferredSize, totalSize);
          }
        }
      }
    };
    return new rcp.Request(url, method, headers, fileBuffer, undefined, undefined, configuration);
  }

  /**
   * 断点续传流式更新文件内容（Files.update.resume 初始化 + Files.resume 分片 PUT）
   * 分片按需读自本地文件，内存基线为单个分片大小，与文件总大小解耦
   * @param fileId 文件ID
   * @param srcPath 本地源文件路径
   * @param onProgress 上传进度回调（可选），透传给分片循环按片上报
   * @returns Promise<HttpResponse> 结果信息（成功时 body 为文件资源 JSON）
   */
  private async updateFromFileByResume(fileId: string, srcPath: string,
    onProgress?: TransferProgressCallback): Promise<HttpResponse> {
    const totalBytes = fs.statSync(srcPath).size;
    const session = await this.initResumeUpload(fileId, totalBytes);
    const file = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
    try {
      const readChunk = (offset: number, length: number): Promise<ArrayBuffer> => {
        const buffer = new ArrayBuffer(length);
        const readLen = fs.readSync(file.fd, buffer, { offset: offset, length: length });
        return Promise.resolve(readLen === length ? buffer : buffer.slice(0, readLen));
      };
      return await this.uploadResumeChunks(session.location, totalBytes, session.sliceSize, readChunk, onProgress);
    } finally {
      fs.closeSync(file.fd);
    }
  }

  /**
   * 流式上传新文件（S7）：创建文件元数据（axios 小 JSON）→ PATCH 内容（rcp UploadFromFile 流式）
   * @param parentFolderId 父文件夹ID
   * @param fileName 文件名
   * @param srcPath 本地源文件路径
   * @param onProgress 上传进度回调（可选），透传给内容上传阶段
   * @returns Promise<HttpResponse> 结果信息
   */
  public async uploadFromFile(parentFolderId: string, fileName: string, srcPath: string,
    onProgress?: TransferProgressCallback): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      const createPath = `/files?fields=*`;
      hilog.info(DOMAIN, TAG, `uploadFromFile: parentFolderId=${parentFolderId}, fileName=${fileName}`);

      interface CreateFileData {
        fileName: string;
        mimeType: string;
        parentFolder: string[];
      }
      const createData: CreateFileData = {
        fileName: fileName,
        mimeType: 'application/octet-stream',
        parentFolder: [parentFolderId]
      };

      const config: AxiosRequestConfig = {
        headers: {
          'Content-Type': 'application/json'
        }
      };

      const createResponse: AxiosResponse = await this.axiosInstance.post(createPath, createData, config);

      let responseData: Record<string, Object>;
      if (typeof createResponse.data === 'string') {
        responseData = JSON.parse(createResponse.data) as Record<string, Object>;
      } else {
        responseData = createResponse.data as Record<string, Object>;
      }
      const fileId = responseData.id as string;

      if (!fileId) {
        return new HttpResponse(false, createResponse.status, 'Created file has no id', {});
      }

      hilog.info(DOMAIN, TAG, `File created with ID: ${fileId}, now uploading content from file...`);
      return await this.updateFromFile(fileId, srcPath, onProgress);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `uploadFromFile error: fileName=${fileName}, error=${(error as Error).message}`);
      throw new Error((error as Error).message);
    }
  }

  /**
   * 创建文件夹
   * @param parentFolderId 父文件夹ID
   * @param folderName 文件夹名称
   * @returns Promise<HttpResponse> 结果信息
   */
  public async createFolder(parentFolderId: string, folderName: string): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      const createPath = `/files?fields=*`;
      hilog.info(DOMAIN, TAG, `createFolder: parentFolderId=${parentFolderId}, folderName=${folderName}`);

      interface CreateFolderData {
        fileName: string;
        mimeType: string;
        parentFolder: string[];
      }
      const createData: CreateFolderData = {
        fileName: folderName,
        mimeType: HUAWEI_DRIVE_FOLDER_MIME_TYPE,
        parentFolder: [parentFolderId]
      };

      const config: AxiosRequestConfig = {
        headers: {
          'Content-Type': 'application/json'
        }
      };

      const response: AxiosResponse = await this.axiosInstance.post(createPath, createData, config);
      return this.convertAxiosResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `createFolder error: folderName=${folderName}, error=${(error as Error).message}`);
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 删除文件
   * @param fileId 文件ID
   * @returns Promise<HttpResponse> 结果信息
   */
  public async delete(fileId: string): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      const apiPath = `/files/${fileId}`;
      hilog.info(DOMAIN, TAG, `delete: fileId=${fileId}, apiPath=${apiPath}`);

      const response: AxiosResponse = await this.axiosInstance.delete(apiPath);
      return this.convertAxiosResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `delete error: fileId=${fileId}, error=${(error as Error).message}`);
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 解析文件信息
   * @param data API响应数据
   * @returns HuaweiDriveFile 文件信息
   */
  public parseFile(data: Record<string, Object>): HuaweiDriveFile {
    try {
      const id = this.extractStringFromObject(data, 'id');
      const fileName = this.extractStringFromObject(data, 'fileName');
      const mimeType = this.extractOptionalStringFromObject(data, 'mimeType');
      const size = this.extractOptionalNumberFromObject(data, 'size') || 0;
      const createdTime = this.extractOptionalStringFromObject(data, 'createdTime');
      const editedTime = this.extractOptionalStringFromObject(data, 'editedTime');
      const contentDownloadLink = this.extractOptionalStringFromObject(data, 'contentDownloadLink');

      // 解析父文件夹（兼容字符串数组 ["id"] 和对象数组 [{id:"id"}] 两种形式）
      const parentFolder: ParentFolder[] = [];
      const parentFolderData = data['parentFolder'];
      if (parentFolderData && Array.isArray(parentFolderData)) {
        for (const parent of parentFolderData as Object[]) {
          if (typeof parent === 'string') {
            const folderItem: ParentFolder = { id: parent };
            parentFolder.push(folderItem);
          } else {
            const parentObj = parent as Record<string, Object>;
            const parentId = this.extractOptionalStringFromObject(parentObj, 'id');
            if (parentId) {
              const folderItem: ParentFolder = { id: parentId };
              parentFolder.push(folderItem);
            }
          }
        }
      }

      // 解析能力
      let capabilities: FileCapabilities | undefined = undefined;
      const capabilitiesData = data['capabilities'];
      if (capabilitiesData && typeof capabilitiesData === 'object') {
        const capObj = capabilitiesData as Record<string, Object>;
        const cap: FileCapabilities = {
          downloadPermission: this.extractOptionalNumberFromObject(capObj, 'downloadPermission') === 1,
          editPermission: this.extractOptionalNumberFromObject(capObj, 'editPermission') === 1,
          deletePermission: this.extractOptionalNumberFromObject(capObj, 'deletePermission') === 1
        };
        capabilities = cap;
      }

      return {
        id,
        fileName,
        mimeType,
        size,
        createdTime,
        editedTime,
        parentFolder,
        contentDownloadLink,
        capabilities
      };
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to parse file: ${(error as Error).message}, data: ${JSON.stringify(data)}`);
      // 返回一个默认的文件对象
      return {
        id: this.extractOptionalStringFromObject(data, 'id') || '',
        fileName: this.extractOptionalStringFromObject(data, 'fileName') || 'Unknown',
        mimeType: this.extractOptionalStringFromObject(data, 'mimeType') || 'application/octet-stream',
        size: this.extractOptionalNumberFromObject(data, 'size') || 0,
        createdTime: this.extractOptionalStringFromObject(data, 'createdTime') || '',
        editedTime: this.extractOptionalStringFromObject(data, 'editedTime') || '',
        parentFolder: []
      };
    }
  }

  /**
   * 解析文件列表信息
   * @param data API响应数据（包含 files 数组）
   * @returns HuaweiDriveFile[] 文件信息列表
   */
  public parseFileList(data: Record<string, Object>): HuaweiDriveFile[] {
    const files: HuaweiDriveFile[] = [];

    try {
      // 检查是否有 files 数组
      const filesData = data['files'];
      if (filesData && Array.isArray(filesData)) {
        for (const item of filesData as Object[]) {
          const itemData = item as Record<string, Object>;
          const file = this.parseFile(itemData);
          files.push(file);
        }
      } else {
        hilog.warn(DOMAIN, TAG, 'Response does not contain files array');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to parse file list: ${(error as Error).message}, data: ${JSON.stringify(data)}`);
    }

    return files;
  }

  /**
   * 解析令牌响应
   * @param response 响应数据
   * @returns OAuth2Token 令牌信息
   */
  private parseTokenResponse(response: Record<string, Object>): OAuth2Token {
    const accessToken = this.extractStringFromObject(response, 'access_token');
    const tokenType = this.extractStringFromObject(response, 'token_type', 'Bearer');
    const refreshToken = this.extractOptionalStringFromObject(response, 'refresh_token');
    const expiresIn = this.extractOptionalNumberFromObject(response, 'expires_in');
    const scope = this.extractOptionalStringFromObject(response, 'scope');

    if (!accessToken || accessToken.trim().length === 0) {
      const error = this.extractStringFromObject(response, 'error', 'Unknown error');
      const errorDescription = this.extractStringFromObject(response, 'error_description', '');
      throw new Error(`${error}: ${errorDescription}`);
    }

    const token: OAuth2Token = {
      accessToken: accessToken,
      tokenType: tokenType,
      refreshToken: refreshToken,
      scope: scope
    };

    if (expiresIn && expiresIn > 0) {
      token.expiresAt = Date.now() + expiresIn * 1000;
    }

    hilog.info(DOMAIN, TAG, 'Token obtained successfully, expires at: %{public}s', token.expiresAt?.toString());
    return token;
  }
}
