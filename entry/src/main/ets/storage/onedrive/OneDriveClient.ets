import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils, KdbxError } from 'kdbxweb';
import { OAuth2Config, OAuth2Token } from '../../common/oauth2/OAuth2Types';
import axios, { AxiosError, AxiosInstance, AxiosRequestConfig, AxiosResponse } from '@ohos/axios';

const DOMAIN = 0x0000;
const TAG = 'OneDriveClient';

/**
 * OneDrive资源信息接口
 */
export interface OneDriveResource {
  /**
   * 资源ID
   */
  id: string;

  /**
   * 资源名称
   */
  name: string;

  /**
   * 资源类型：file 或 folder
   */
  type: string;

  /**
   * 文件大小
   */
  size: number;

  /**
   * 最后修改时间
   */
  lastModified: string;

  /**
   * 资源路径
   */
  path: string;

  /**
   * 下载URL
   */
  downloadUrl?: string;

  /**
   * 子节点数量（仅文件夹）
   */
  childrenCount?: number;

  /**
   * 文件MIME类型
   */
  mimeType?: string;
}

/**
 * OneDrive客户端配置选项接口
 */
export interface OneDriveClientOptions {
  /**
   * OneDrive API基础URL
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
 * OneDrive客户端类
 * 用于与Microsoft Graph API交互，操作OneDrive文件
 */
export class OneDriveClient {
  /**
   * Axios实例
   */
  private axiosInstance: AxiosInstance | null = null;
  /**
   * 客户端配置
   */
  private config: OneDriveClientOptions | null = null;
  /**
   * OAuth2配置
   */
  private oauth2Config: OAuth2Config | null = null;

  /**
   * 构造函数
   * @param options 客户端配置选项
   * @param oauth2Config OAuth2配置（用于刷新令牌）
   */
  constructor(options?: OneDriveClientOptions, oauth2Config?: OAuth2Config) {
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
  public updateOptions(options: OneDriveClientOptions): void {
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
  private extractOptionalStringFromObject(obj: Record<string, Object>, key: string): string  {
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
          const errorInfo = this.parseMicrosoftGraphError(errorJson);
          if (errorInfo.message) {
            errorMessage = errorInfo.message;
          }
          if (errorInfo.code) {
            hilog.error(DOMAIN, TAG, `Microsoft Graph Error Code: ${errorInfo.code}`);
          }
        } catch (e) {
          hilog.error(DOMAIN, TAG, `Failed to parse error response: ${(e as Error).message}`);
        }
      } else if (typeof error.response.data === 'object') {
        const errorObj = error.response.data as Record<string, Object>;
        const errorInfo = this.parseMicrosoftGraphError(errorObj);
        if (errorInfo.message) {
          errorMessage = errorInfo.message;
        }
        if (errorInfo.code) {
          hilog.error(DOMAIN, TAG, `Microsoft Graph Error Code: ${errorInfo.code}`);
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
   * 解析 Microsoft Graph API 错误响应
   * @param errorJson 错误JSON对象
   * @returns 错误信息（code 和 message）
   */
  private parseMicrosoftGraphError(errorJson: Record<string, Object>): KdbxError {
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
      const body: Record<string, string> = {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': this.oauth2Config.clientId,
        'client_secret': this.oauth2Config.clientSecret,
        'redirect_uri': this.oauth2Config.redirectUri
      };

      const url = this.oauth2Config.tokenEndpoint;
      const axiosInstance = axios.create({
        timeout: this.config?.timeout || 30000
      });

      const config: AxiosRequestConfig = {
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded'
        }
      };
      const response: AxiosResponse = await axiosInstance.post(url, this.urlEncode(body), config);

      const httpResponse = this.convertAxiosResponse(response);
      if (httpResponse.success && httpResponse.body) {
        const jsonStr = ByteUtils.bytesToString(httpResponse.body);
        return this.parseTokenResponse(JSON.parse(jsonStr));
      } else {
        throw new Error(`HTTP ${httpResponse.statusCode}: ${httpResponse.message}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Refresh token failed: %{public}s', (error as Error).message);
      throw new Error(`Refresh token failed: ${(error as Error).message}`);
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
      const response: AxiosResponse = await this.axiosInstance.get('/me/drive/root');
      return this.convertAxiosResponse(response);
    } catch (error) {
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 获取文件/文件夹信息
   * @param path 路径（相对路径）
   * @returns Promise<HttpResponse> 结果信息
   */
  public async getInfo(path: string = ''): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      let apiPath = path ? this.pathToApiPath(path) : '/me/drive/root';
      hilog.info(DOMAIN, TAG, `getInfo: path=${path}, apiPath=${apiPath}`);
      const response: AxiosResponse = await this.axiosInstance.get(apiPath);
      return this.convertAxiosResponse(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `getInfo error: path=${path}, error=${(error as Error).message}`);
      if ((error as AxiosError).response?.data) {
        hilog.error(DOMAIN, TAG, `Response data: %{public}s`, JSON.stringify((error as AxiosError).response?.data));
      }
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 列出目录内容
   * @param path 目录路径（相对路径）
   * @param filter 过滤器：0-不过滤，1-只返回文件夹，2-只返回文件
   * @returns Promise<HttpResponse> 结果信息
   */
  public async list(path: string = '', filter: number = 0): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      let apiPath = path ? this.pathToApiPath(path) : '/me/drive/root';
      apiPath += '/children';
      const response: AxiosResponse = await this.axiosInstance.get(apiPath);
      return this.convertAxiosResponse(response);
    } catch (error) {
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 获取文件内容
   * @param path 文件路径（相对路径）
   * @returns Promise<HttpResponse> 结果信息
   */
  public async get(path: string): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      let apiPath = this.pathToApiPath(path);
      apiPath += '/content';
      const response: AxiosResponse = await this.axiosInstance.get(apiPath);
      return this.convertAxiosResponse(response);
    } catch (error) {
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 上传文件
   * @param remoteUri 远程URI
   * @param fileBuffer 文件内容
   * @returns Promise<HttpResponse> 结果信息
   */
  public async upload(remoteUri: string, fileBuffer: ArrayBuffer): Promise<HttpResponse> {
    if (!this.axiosInstance) {
      throw new Error('Axios instance not initialized');
    }
    try {
      hilog.info(DOMAIN, TAG, `File upload url: ${remoteUri}, size: ${fileBuffer.byteLength}`);
      const config: AxiosRequestConfig = {
        headers: {
          'Content-Type': 'application/octet-stream'
        }
      };
      const response: AxiosResponse = await this.axiosInstance.put(remoteUri, fileBuffer, config);
      const result = this.convertAxiosResponse(response);
      hilog.info(DOMAIN, TAG, 'File upload result: %{public}s', result.message);
      return result;
    } catch (error) {
      return this.convertAxiosError(error as AxiosError);
    }
  }

  /**
   * 解析资源信息
   * @param data API响应数据
   * @returns OneDriveResource 资源信息
   */
  public parseResource(data: Record<string, Object>): OneDriveResource {
    const id = this.extractOptionalStringFromObject(data, 'id');
    const name = this.extractOptionalStringFromObject(data, 'name');
    const size = this.extractOptionalNumberFromObject(data, 'size') || 0;
    const lastModified = this.extractOptionalStringFromObject(data, 'lastModifiedDateTime');
    const path = this.extractPath(data);
    const downloadUrl = this.extractOptionalStringFromObject(data, '@microsoft.graph.downloadUrl');

    const isFolder = data['folder'] !== undefined && data['folder'] !== null;
    const childrenCount = isFolder ? this.extractOptionalNumberFromObject(data['folder'] as Record<string, Object>, 'childCount') || 0 : 0;
    const mimeType = isFolder ? undefined : this.extractOptionalStringFromObject(data['file'] as Record<string, Object>, 'mimeType');

    return {
      id: id || '',
      name: name || '',
      type: isFolder ? 'folder' : 'file',
      size: size,
      lastModified: lastModified || '',
      path: path || '',
      downloadUrl: downloadUrl,
      childrenCount: childrenCount,
      mimeType: mimeType
    };
  }

  /**
   * 将路径转换为API路径
   * @param path 路径
   * @returns API路径
   */
  private pathToApiPath(path: string): string {
    if (!path || path === '/') {
      return '/me/drive/root';
    }
    path = path.startsWith('/') ? path.substring(1) : path;
    return `/me/drive/root:/${path}`;
  }

  /**
   * 从数据中提取路径
   * @param data API响应数据
   * @returns 路径
   */
  private extractPath(data: Record<string, Object>): string {
    const webUrl = data['webUrl'];
    if (webUrl && typeof webUrl === 'string') {
      const urlParts = webUrl.split('/');
      const oneDriveIndex = urlParts.findIndex((part: string): boolean => part.toLowerCase().includes('onedrive'));
      if (oneDriveIndex !== -1 && oneDriveIndex + 2 < urlParts.length) {
        return urlParts.slice(oneDriveIndex + 2).join('/');
      }
    }
    const name = data['name'];
    if (name && typeof name === 'string') {
      return name;
    }
    return '';
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

    hilog.info(DOMAIN, TAG, 'Token obtained successfully, expires at: %{public}s', token.expiresAt);
    return token;
  }
}
