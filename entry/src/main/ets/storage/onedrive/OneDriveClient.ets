import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { ByteUtils } from 'kdbxweb';
import { OAuth2Config, OAuth2Token } from '../oauth2/OAuth2Types';
import { OneDriveStorageConfig } from './OneDriveConfig';
import { ResourceManager } from '../../common/utils';

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
 * OneDrive客户端结果信息类
 */
export class OneDriveResultInfo {
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
  message: string = "";
  /**
   * 响应头
   */
  headers: rcp.ResponseHeaders = {};
  /**
   * 响应数据
   */
  data?: OneDriveResource[] = [];
  /**
   * 响应体
   */
  body?: ArrayBuffer = undefined;
}

/**
 * OneDrive客户端类
 * 用于与Microsoft Graph API交互，操作OneDrive文件
 */
export class OneDriveClient {
  /**
   * HTTP会话
   */
  public session: rcp.Session | null = null;
  /**
   * 客户端配置
   */
  public config: OneDriveClientOptions | null = null;
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
    this.close();
    this.session = rcp.createSession({
      baseAddress: this.config.apiBaseUrl,
      headers: {
        "Accept": "application/json",
        "Content-Type": "application/json"
      },
      requestConfiguration: {
        transfer: {
          timeout: { connectMs: this.config.timeout || 30000 }
        }
      }
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
    if (this.config) {
      this.config.accessToken = accessToken;
    }
  }

  /**
   * 关闭连接
   */
  public close(): void {
    this.session?.close();
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
   * 刷新访问令牌
   * @param refreshToken 刷新令牌
   * @returns Promise<OAuth2Token> 新的令牌信息
   */
  public async refreshToken(refreshToken: string): Promise<OAuth2Token> {
    if (!this.oauth2Config) {
      throw new Error('OAuth2 config not set');
    }

    const httpRequest = http.createHttp();
    try {
      const body: Record<string, string> = {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': this.oauth2Config.clientId,
        'client_secret': this.oauth2Config.clientSecret,
        'redirect_uri': this.oauth2Config.redirectUri
      };

      const url = this.oauth2Config.tokenEndpoint;
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        connectTimeout: this.config?.timeout || 30000,
        readTimeout: this.config?.timeout || 30000,
        header: {
          'Content-Type': 'application/x-www-form-urlencoded'
        },
        extraData: this.urlEncode(body)
      };

      const response = await httpRequest.request(url, options);
      const responseCode = response.responseCode as number;

      if (responseCode >= 200 && responseCode < 300) {
        const result = response.result;
        if (typeof result === 'string') {
          return this.parseTokenResponse(JSON.parse(result));
        }
        if (result && typeof result === 'object') {
          return this.parseTokenResponse(result as Record<string, Object>);
        }
        throw new Error('Invalid response type');
      } else {
        throw new Error(`HTTP ${responseCode}: ${response.result}`);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Refresh token failed: %{public}s', (error as Error).message);
      throw new Error(`Refresh token failed: ${(error as Error).message}`);
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 发送HTTP请求
   * @param req 请求对象
   * @returns Promise<OneDriveResultInfo> 响应结果
   */
  public async request(req: rcp.Request): Promise<OneDriveResultInfo> {
    const requestReturn: OneDriveResultInfo = new OneDriveResultInfo();
    let errorMessage: string | undefined = undefined;

    try {
      const resp = await this.session?.fetch(req);
      errorMessage = resp?.toString() ?? undefined;

      if (resp === undefined) {
        requestReturn.statusCode = 500;
        requestReturn.success = false;
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_request_error"));
        return requestReturn;
      }

      hilog.debug(DOMAIN, TAG, "request return statusCode: %{public}d, headers: %{public}s",
        resp.statusCode, JSON.stringify(resp.headers));

      requestReturn.statusCode = resp.statusCode;
      requestReturn.headers = resp.headers;

      if (resp.statusCode === 401) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_auth_failed"));
        requestReturn.success = false;
        return requestReturn;
      }
      if (resp.statusCode === 404) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_not_found"));
        requestReturn.success = false;
        return requestReturn;
      }
      if (resp.statusCode === 403) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_no_permission"));
        requestReturn.success = false;
        return requestReturn;
      }
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        requestReturn.statusCode = 200;
        requestReturn.body = resp.body;
        requestReturn.success = true;
      } else {
        requestReturn.success = false;
        requestReturn.message = this.toErrorMsg(errorMessage) || '';
      }
    } catch (err) {
      let errMsg: string = err.message ?? errorMessage ?? err.data ?? "";
      hilog.error(DOMAIN, TAG, "request error: %{public}s:%{public}s", err.code, errMsg);
      requestReturn.statusCode = 500;
      requestReturn.success = false;
      if (err.code === 1007900028) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_request_timeout"));
      } else {
        requestReturn.message = `${err.code}:${errMsg}`;
      }
    }

    return requestReturn;
  }

  /**
   * 验证连接
   * @returns Promise<OneDriveResultInfo> 验证结果
   */
  public async valid(): Promise<OneDriveResultInfo> {
    const req = new rcp.Request('/me/drive/root', "GET");
    return await this.request(req);
  }

  /**
   * 获取文件/文件夹信息
   * @param path 路径（相对路径）
   * @returns Promise<OneDriveResultInfo> 结果信息
   */
  public async getInfo(path: string = ''): Promise<OneDriveResultInfo> {
    let apiPath = path ? this.pathToApiPath(path) : '/me/drive/root';
    const req = new rcp.Request(apiPath, "GET");
    const result = await this.request(req);

    if (result.success && result.body) {
      const jsonStr = ByteUtils.bytesToString(result.body);
      const data: Record<string, Object> = JSON.parse(jsonStr);
      result.data = [this.parseResource(data)];
    }

    return result;
  }

  /**
   * 列出目录内容
   * @param path 目录路径（相对路径）
   * @param filter 过滤器：0-不过滤，1-只返回文件夹，2-只返回文件
   * @returns Promise<OneDriveResultInfo> 结果信息
   */
  public async list(path: string = '', filter: number = 0): Promise<OneDriveResultInfo> {
    let apiPath = path ? this.pathToApiPath(path) : '/me/drive/root';
    apiPath += '/children';

    const req = new rcp.Request(apiPath, "GET");
    const result = await this.request(req);

    if (result.success && result.body) {
      const jsonStr = ByteUtils.bytesToString(result.body);
      const data: Record<string, Object> = JSON.parse(jsonStr);
      const resources: OneDriveResource[] = [];

      const value = data['value'];
      if (value && Array.isArray(value)) {
        for (const item of value as Array<Object>) {
          const itemData = item as Record<string, Object>;
          const resource = this.parseResource(itemData);
          if (filter === 0) {
            resources.push(resource);
          } else if (filter === 1 && resource.type === 'folder') {
            resources.push(resource);
          } else if (filter === 2 && resource.type === 'file') {
            resources.push(resource);
          }
        }
        result.data = resources;
      } else {
        result.data = [];
      }
    }

    return result;
  }

  /**
   * 检查路径是否存在
   * @param path 路径（相对路径）
   * @returns Promise<boolean> 是否存在
   */
  public async exists(path: string): Promise<boolean> {
    hilog.info(DOMAIN, TAG, `Query path exists: ${path}`);
    const result = await this.getInfo(path);
    return result.success;
  }

  /**
   * 获取文件内容
   * @param path 文件路径（相对路径）
   * @returns Promise<OneDriveResultInfo> 结果信息
   */
  public async get(path: string): Promise<OneDriveResultInfo> {
    let apiPath = this.pathToApiPath(path);
    apiPath += '/content';

    const req = new rcp.Request(apiPath, "GET");
    return await this.request(req);
  }

  /**
   * 上传文件
   * @param remoteUri 远程URI
   * @param fileBuffer 文件内容
   * @returns Promise<OneDriveResultInfo> 结果信息
   */
  public async upload(remoteUri: string, fileBuffer: ArrayBuffer): Promise<OneDriveResultInfo> {
    const req = new rcp.Request(remoteUri, "PUT", {}, fileBuffer, {
      "Content-Type": "application/octet-stream"
    });
    hilog.info(DOMAIN, TAG, `File upload url：${remoteUri}, size: ${fileBuffer.byteLength}`);
    const rr = await this.request(req);
    hilog.info(DOMAIN, TAG, "File upload result: %{public}s", rr.message);
    return rr;
  }

  /**
   * 将路径转换为API路径
   * @param path 路径
   * @returns API路径
   */
  private pathToApiPath(path: string): string {
    if (!path) {
      return '/me/drive/root';
    }
    // 移除开头的斜杠
    path = path.startsWith('/') ? path.substring(1) : path;
    return `/me/drive/root:/${path}`;
  }

  /**
   * 解析资源信息
   * @param data API响应数据
   * @returns OneDriveResource 资源信息
   */
  private parseResource(data: Record<string, Object>): OneDriveResource {
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
   * 从数据中提取路径
   * @param data API响应数据
   * @returns 路径
   */
  private extractPath(data: Record<string, Object>): string {
    const webUrl = data['webUrl'];
    if (webUrl && typeof webUrl === 'string') {
      // 从webUrl中提取路径部分
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

  /**
   * URL编码对象
   * @param data 数据对象
   * @returns URL编码字符串
   */
  private urlEncode(data: Record<string, string>): string {
    const pairs: string[] = [];
    const entries = Object.entries(data);
    for (const entry of entries) {
      const key = entry[0];
      const value = entry[1];
      pairs.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    }
    return pairs.join('&');
  }

  /**
   * 从对象中提取字符串值
   * @param obj 对象
   * @param key 键
   * @param defaultValue 默认值
   * @returns 字符串值
   */
  private extractStringFromObject(obj: Record<string, Object>, key: string, defaultValue: string = ''): string {
    const value = obj[key];
    if (value === undefined || value === null) {
      return defaultValue;
    }
    return String(value);
  }

  /**
   * 从对象中提取可选字符串值
   * @param obj 对象
   * @param key 键
   * @returns 字符串值或undefined
   */
  private extractOptionalStringFromObject(obj: Record<string, Object>, key: string): string | undefined {
    const value = obj[key];
    if (value === undefined || value === null) {
      return undefined;
    }
    return String(value);
  }

  /**
   * 从对象中提取可选数字值
   * @param obj 对象
   * @param key 键
   * @returns 数字值或undefined
   */
  private extractOptionalNumberFromObject(obj: Record<string, Object>, key: string): number | undefined {
    const value = obj[key];
    if (value === undefined || value === null) {
      return undefined;
    }
    const num = Number(value);
    return isNaN(num) ? undefined : num;
  }

  /**
   * 将错误消息转换为友好提示
   * @param errorMessage 错误消息
   * @returns 友好提示
   */
  private toErrorMsg(errorMessage?: string): string | undefined {
    if (!errorMessage) {
      return undefined;
    }
    try {
      const errorObj: Record<string, Object> = JSON.parse(errorMessage);
      const errorDetail = errorObj['error'] as Record<string, Object> | undefined;
      if (errorDetail && errorDetail['message']) {
        return String(errorDetail['message']);
      }
    } catch (e) {
      // 忽略解析错误
    }
    return errorMessage;
  }
}
