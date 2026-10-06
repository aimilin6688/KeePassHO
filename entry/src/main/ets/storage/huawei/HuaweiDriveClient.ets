import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ByteUtils, KdbxError } from 'kdbxweb';
import { OAuth2Config, OAuth2Token } from '../../common/oauth2/OAuth2Types';
import axios, { AxiosError, AxiosInstance, AxiosRequestConfig, AxiosResponse } from '@ohos/axios';
import { StringUtils, UrlUtils } from '../../common/utils';

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
   * 流式分块下载文件到本地文件（S7：华为 Drive form=content 端点支持 Range GET）
   * 内存窗口 = 单块（8MB），与文件大小解耦；首块若返回 200（Range 不支持）退化为整缓冲
   * @param fileId 文件 ID
   * @param destPath 本地目标文件路径（调用方管理生命周期）
   * @returns 下载字节数
   */
  public async downloadRangeToFile(fileId: string, destPath: string): Promise<number> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    // 取文件大小
    const infoResp = await this.getInfo(fileId);
    if (!infoResp.success || !infoResp.body) {
      throw new Error(infoResp.message || 'downloadRangeToFile: failed to get file info');
    }
    const infoJson = ByteUtils.bytesToString(infoResp.body);
    const infoData: Record<string, Object> = JSON.parse(infoJson);
    const fileSize = Number(infoData['size']) || 0;
    if (fileSize === 0) {
      const empty = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.close(empty.fd);
      return 0;
    }
    const CHUNK_SIZE = 8 * 1024 * 1024;
    let downloaded = 0;
    let firstChunk = true;
    const apiPath = `/files/${fileId}?form=content`;
    const file = await fs.open(destPath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      while (downloaded < fileSize) {
        const end = Math.min(downloaded + CHUNK_SIZE - 1, fileSize - 1);
        const rangeHeader = `bytes=${downloaded}-${end}`;
        const config: AxiosRequestConfig = {
          responseType: 'array_buffer',
          headers: { 'Range': rangeHeader }
        };
        const response: AxiosResponse = await this.axiosInstance.get(apiPath, config);
        if (firstChunk && response.status === 200) {
          // Range 不支持：整内容返回，写全部
          const body = response.data as ArrayBuffer;
          await fs.write(file.fd, body);
          downloaded = fileSize;
          break;
        }
        firstChunk = false;
        if (response.status !== 206) {
          throw new Error(`downloadRangeToFile: HTTP ${response.status}, expected 206`);
        }
        const body = response.data as ArrayBuffer;
        await fs.write(file.fd, body);
        downloaded += body.byteLength;
      }
      await fs.fsync(file.fd);
    } finally {
      await fs.close(file.fd);
    }
    return downloaded;
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
   * @returns Promise<HttpResponse> 结果信息
   */
  public async upload(parentFolderId: string, fileName: string, fileBuffer: ArrayBuffer): Promise<HttpResponse> {
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

      // 第二步：上传文件内容
      // 使用专门的 upload 端点
      const uploadBase = this.config?.apiBaseUrl?.replace('/drive/v1', '/upload/drive/v1') ||
        'https://driveapis.cloud.huawei.com.cn/upload/drive/v1';

      const uploadConfig: AxiosRequestConfig = {
        method: 'PATCH',
        url: `${uploadBase}/files/${fileId}?fields=*&uploadType=content`,
        data: fileBuffer,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Authorization': `Bearer ${this.config?.accessToken}`
        },
        responseType: 'string'
      };

      const uploadResponse: AxiosResponse = await axios.request(uploadConfig);
      const result = this.convertAxiosResponse(uploadResponse);
      hilog.info(DOMAIN, TAG, 'upload result: %{public}s', result.message);
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `upload error: fileName=${fileName}, error=${(error as Error).message}`);
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 更新文件内容
   * 华为云盘更新文件内容需要使用专门的 upload 端点，PATCH 方法
   * @param fileId 文件ID
   * @param fileBuffer 文件内容
   * @returns Promise<HttpResponse> 结果信息
   */
  public async update(fileId: string, fileBuffer: ArrayBuffer): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      // 使用专门的 upload 端点
      const uploadBase = this.config?.apiBaseUrl?.replace('/drive/v1', '/upload/drive/v1') ||
        'https://driveapis.cloud.huawei.com.cn/upload/drive/v1';

      hilog.info(DOMAIN, TAG, `update: fileId=${fileId}, size: ${fileBuffer.byteLength}`);

      const config: AxiosRequestConfig = {
        method: 'PATCH',
        url: `${uploadBase}/files/${fileId}?fields=*&uploadType=content`,
        data: fileBuffer,
        headers: {
          'Content-Type': 'application/octet-stream',
          'Authorization': `Bearer ${this.config?.accessToken}`
        },
        responseType: 'string'
      };
      const response: AxiosResponse = await axios.request(config);
      const result = this.convertAxiosResponse(response);
      hilog.info(DOMAIN, TAG, 'update result: %{public}s', result.message);
      return result;
    } catch (error) {
      hilog.error(DOMAIN, TAG, `update error: fileId=${fileId}, error=${(error as Error).message}`);
      return this.convertAxiosError(error as AxiosError);
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
