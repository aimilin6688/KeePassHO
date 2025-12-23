import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils } from 'kdbxweb';
import { OAuth2Config, OAuth2Token } from '../oauth2/OAuth2Types';
import { HttpUtils, HttpResponse, RcpRequestConfig } from '../../common/utils/HttpUtils';

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
 * OneDrive客户端类
 * 用于与Microsoft Graph API交互，操作OneDrive文件
 */
export class OneDriveClient {
  /**
   * HTTP工具类实例
   */
  private httpUtils: HttpUtils;
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
    this.httpUtils = new HttpUtils();
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
    this.httpUtils.close();
    this.httpUtils.initSession(options.apiBaseUrl, options.timeout);
    this.httpUtils.setHeaders({
      'Authorization': `Bearer ${options.accessToken}`
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
      this.httpUtils.setHeaders({
        'Authorization': `Bearer ${accessToken}`
      });
    }
  }

  /**
   * 关闭连接
   */
  public close(): void {
    this.httpUtils.close();
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

    try {
      const body: Record<string, string> = {
        'grant_type': 'refresh_token',
        'refresh_token': refreshToken,
        'client_id': this.oauth2Config.clientId,
        'client_secret': this.oauth2Config.clientSecret,
        'redirect_uri': this.oauth2Config.redirectUri
      };

      const url = this.oauth2Config.tokenEndpoint;
      const response: HttpResponse = await this.httpUtils.post(url, this.httpUtils.urlEncode(body), {
        'Content-Type': 'application/x-www-form-urlencoded'
      }, this.config?.timeout);

      if (response.success && response.body) {
        const result = response.body;
        const jsonStr = ByteUtils.bytesToString(result);
        return this.parseTokenResponse(JSON.parse(jsonStr));
      } else {
        throw new Error(`HTTP ${response.statusCode}: ${response.message}`);
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
    const requestConfig: RcpRequestConfig = new RcpRequestConfig('GET', '/me/drive/root');
    return await this.httpUtils.rcpRequest(requestConfig);
  }

  /**
   * 获取文件/文件夹信息
   * @param path 路径（相对路径）
   * @returns Promise<HttpResponse> 结果信息
   */
  public async getInfo(path: string = ''): Promise<HttpResponse> {
    let apiPath = path ? this.pathToApiPath(path) : '/me/drive/root';
    const requestConfig: RcpRequestConfig = new RcpRequestConfig('GET', apiPath);
    return await this.httpUtils.rcpRequest(requestConfig);
  }

  /**
   * 列出目录内容
   * @param path 目录路径（相对路径）
   * @param filter 过滤器：0-不过滤，1-只返回文件夹，2-只返回文件
   * @returns Promise<HttpResponse> 结果信息
   */
  public async list(path: string = '', filter: number = 0): Promise<HttpResponse> {
    let apiPath = path ? this.pathToApiPath(path) : '/me/drive/root';
    apiPath += '/children';
    const requestConfig: RcpRequestConfig = new RcpRequestConfig('GET', apiPath);
    return await this.httpUtils.rcpRequest(requestConfig);
  }

  /**
   * 获取文件内容
   * @param path 文件路径（相对路径）
   * @returns Promise<HttpResponse> 结果信息
   */
  public async get(path: string): Promise<HttpResponse> {
    let apiPath = this.pathToApiPath(path);
    apiPath += '/content';
    const requestConfig: RcpRequestConfig = new RcpRequestConfig('GET', apiPath);
    return await this.httpUtils.rcpRequest(requestConfig);
  }

  /**
   * 上传文件
   * @param remoteUri 远程URI
   * @param fileBuffer 文件内容
   * @returns Promise<HttpResponse> 结果信息
   */
  public async upload(remoteUri: string, fileBuffer: ArrayBuffer): Promise<HttpResponse> {
    hilog.info(DOMAIN, TAG, `File upload url: ${remoteUri}, size: ${fileBuffer.byteLength}`);
    const uploadHeaders: Record<string, string> = {
      'Content-Type': 'application/octet-stream'
    };
    const requestConfig: RcpRequestConfig = new RcpRequestConfig('PUT', remoteUri, uploadHeaders, fileBuffer);
    const rr = await this.httpUtils.rcpRequest(requestConfig);
    hilog.info(DOMAIN, TAG, 'File upload result: %{public}s', rr.message);
    return rr;
  }

  /**
   * 解析资源信息
   * @param data API响应数据
   * @returns OneDriveResource 资源信息
   */
  public parseResource(data: Record<string, Object>): OneDriveResource {
    const id = this.httpUtils.extractOptionalStringFromObject(data, 'id');
    const name = this.httpUtils.extractOptionalStringFromObject(data, 'name');
    const size = this.httpUtils.extractOptionalNumberFromObject(data, 'size') || 0;
    const lastModified = this.httpUtils.extractOptionalStringFromObject(data, 'lastModifiedDateTime');
    const path = this.extractPath(data);
    const downloadUrl = this.httpUtils.extractOptionalStringFromObject(data, '@microsoft.graph.downloadUrl');

    const isFolder = data['folder'] !== undefined && data['folder'] !== null;
    const childrenCount = isFolder ? this.httpUtils.extractOptionalNumberFromObject(data['folder'] as Record<string, Object>, 'childCount') || 0 : 0;
    const mimeType = isFolder ? undefined : this.httpUtils.extractOptionalStringFromObject(data['file'] as Record<string, Object>, 'mimeType');

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
    if (!path) {
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
    const accessToken = this.httpUtils.extractStringFromObject(response, 'access_token');
    const tokenType = this.httpUtils.extractStringFromObject(response, 'token_type', 'Bearer');
    const refreshToken = this.httpUtils.extractOptionalStringFromObject(response, 'refresh_token');
    const expiresIn = this.httpUtils.extractOptionalNumberFromObject(response, 'expires_in');
    const scope = this.httpUtils.extractOptionalStringFromObject(response, 'scope');

    if (!accessToken || accessToken.trim().length === 0) {
      const error = this.httpUtils.extractStringFromObject(response, 'error', 'Unknown error');
      const errorDescription = this.httpUtils.extractStringFromObject(response, 'error_description', '');
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
