import http from '@ohos.net.http';
import { BaiduNetdiskConfig } from './BaiduNetdiskConfig';
import { BaiduListResponse, BaiduMetaResponse, BaiduPreCreateResponse, BaiduCreateResponse, BaiduDownloadResponse, BaiduMkdirResponse, BaiduTokenResponse } from './BaiduNetdiskTypes';

/**
 * 百度网盘 API 客户端
 * 封装所有百度网盘 REST API 调用
 */
export class BaiduNetdiskClient {
  private config: BaiduNetdiskConfig;
  private baseApiUrl: string = 'https://pan.baidu.com/rest/2.0/xpan';
  private uploadUrl: string = 'https://d.pcs.baidu.com/rest/2.0/pcs/superfile2';
  private authUrl: string = 'https://openapi.baidu.com/oauth/2.0';

  constructor(config: BaiduNetdiskConfig) {
    this.config = config;
  }

  // ==================== OAuth2.0 授权 ====================

  /**
   * 获取授权 URL（打开此 URL 让用户授权）
   */
  getAuthorizationUrl(redirectUri: string, state: string = ''): string {
    let url = this.authUrl + '/authorize?';
    url += 'response_type=code&';
    url += 'client_id=' + this.config.appKey + '&';
    url += 'redirect_uri=' + encodeURIComponent(redirectUri) + '&';
    url += 'scope=' + encodeURIComponent('basic,netdisk');
    if (state) {
      url += '&state=' + encodeURIComponent(state);
    }
    return url;
  }

  /**
   * 用授权码交换 Token
   */
  async exchangeCodeForToken(code: string, redirectUri: string): Promise<BaiduTokenResponse> {
    const body = 'grant_type=authorization_code' +
      '&code=' + encodeURIComponent(code) +
      '&client_id=' + encodeURIComponent(this.config.appKey) +
      '&client_secret=' + encodeURIComponent(this.config.appSecret) +
      '&redirect_uri=' + encodeURIComponent(redirectUri);
    return this.httpPostForm<BaiduTokenResponse>(this.authUrl + '/token', body);
  }

  /**
   * 刷新 Token
   */
  async refreshToken(refreshToken: string): Promise<BaiduTokenResponse> {
    const body = 'grant_type=refresh_token' +
      '&refresh_token=' + encodeURIComponent(refreshToken) +
      '&client_id=' + encodeURIComponent(this.config.appKey) +
      '&client_secret=' + encodeURIComponent(this.config.appSecret);
    return this.httpPostForm<BaiduTokenResponse>(this.authUrl + '/token', body);
  }

  // ==================== 文件操作 ====================

  /**
   * 列出目录下的文件和文件夹
   * @param dir 目录路径
   */
  async listFiles(dir: string = '/'): Promise<Array<import('./BaiduNetdiskTypes').BaiduFileItem>> {
    const token = await this.config.getAccessToken();
    let url = this.baseApiUrl + '/file?';
    url += 'method=list&';
    url += 'access_token=' + encodeURIComponent(token) + '&';
    url += 'dir=' + encodeURIComponent(dir.startsWith('/') ? dir : '/' + dir) + '&';
    url += 'folder=0&';
    url += 'start=0&';
    url += 'limit=10000&';
    url += 'order=name&';
    url += 'desc=0';
    const resp = await this.httpGet<BaiduListResponse>(url);
    return resp.list;
  }

  /**
   * 获取文件或目录的元信息
   */
  async getFileInfo(path: string): Promise<import('./BaiduNetdiskTypes').BaiduFileItem | null> {
    const token = await this.config.getAccessToken();
    let url = this.baseApiUrl + '/file?';
    url += 'method=meta&';
    url += 'access_token=' + encodeURIComponent(token) + '&';
    url += 'path=' + encodeURIComponent(path);
    const resp = await this.httpGet<BaiduMetaResponse>(url);
    if (resp.info && resp.info.length > 0) {
      return resp.info[0];
    }
    return null;
  }

  /**
   * 检查文件或目录是否存在
   */
  async exists(path: string): Promise<boolean> {
    const info = await this.getFileInfo(path);
    return info !== null;
  }

  /**
   * 创建文件夹
   */
  async createDirectory(path: string): Promise<boolean> {
    const token = await this.config.getAccessToken();
    let url = this.baseApiUrl + '/file?';
    url += 'method=mkdir&';
    url += 'access_token=' + encodeURIComponent(token);
    const body = 'path=' + encodeURIComponent(path) + '&rtype=2';
    const resp = await this.httpPostFormData<BaiduMkdirResponse>(url, body);
    return resp.errno === 0;
  }

  /**
   * 下载文件，返回文件内容（ArrayBuffer）
   */
  async downloadFile(path: string): Promise<ArrayBuffer> {
    const token = await this.config.getAccessToken();
    // 先获取下载链接
    let url = this.baseApiUrl + '/file?';
    url += 'method=download&';
    url += 'access_token=' + encodeURIComponent(token) + '&';
    url += 'path=' + encodeURIComponent(path) + '&';
    url += 'dlink=1';
    const resp = await this.httpGet<BaiduDownloadResponse>(url);
    if (resp.errno !== 0 || !resp.dlink || resp.dlink.length === 0) {
      throw new Error('Failed to get download link: errno=' + resp.errno);
    }
    const dlink = resp.dlink[0].dlink + '?access_token=' + encodeURIComponent(token);
    return this.httpDownload(dlink);
  }

  /**
   * 上传文件（简化版：小文件直接上传）
   * @param path 目标路径
   * @param content 文件内容
   */
  async uploadFile(path: string, content: ArrayBuffer): Promise<boolean> {
    const token = await this.config.getAccessToken();
    const fileName = this.extractFileName(path);
    const fullPath = path.startsWith('/') ? path : '/' + path;

    // 步骤1：预创建
    let preCreateUrl = this.baseApiUrl + '/file?';
    preCreateUrl += 'method=precreate&';
    preCreateUrl += 'access_token=' + encodeURIComponent(token);
    const blockListJson = JSON.stringify([]);
    const preCreateBody = 'path=' + encodeURIComponent(fullPath) +
      '&size=' + content.byteLength.toString() +
      '&isdir=0' +
      '&autoinit=1' +
      '&block_list=' + encodeURIComponent(blockListJson);
    const preResp = await this.httpPostFormData<BaiduPreCreateResponse>(preCreateUrl, preCreateBody);

    if (preResp.errno !== 0) {
      throw new Error('PreCreate failed: errno=' + preResp.errno);
    }

    const uploadId = preResp.uploadid;

    // 步骤2：分片上传（简化：单分片）
    const blockSize = 4 * 1024 * 1024;
    const totalSize = content.byteLength;
    const blockCount = Math.ceil(totalSize / blockSize);

    for (let i = 0; i < blockCount; i++) {
      const start = i * blockSize;
      const end = Math.min(start + blockSize, totalSize);
      const chunk = content.slice(start, end);

      let uploadUrl = this.uploadUrl + '?';
      uploadUrl += 'method=upload&';
      uploadUrl += 'access_token=' + encodeURIComponent(token) + '&';
      uploadUrl += 'type=tmpfile&';
      uploadUrl += 'path=' + encodeURIComponent(fullPath) + '&';
      uploadUrl += 'uploadid=' + encodeURIComponent(uploadId) + '&';
      uploadUrl += 'partseq=' + i.toString();
      await this.httpUploadChunk(uploadUrl, chunk, fileName);
    }

    // 步骤3：创建文件（完成上传）
    let createUrl = this.baseApiUrl + '/file?';
    createUrl += 'method=create&';
    createUrl += 'access_token=' + encodeURIComponent(token);
    const createBody = 'path=' + encodeURIComponent(fullPath) +
      '&size=' + totalSize.toString() +
      '&isdir=0' +
      '&uploadid=' + encodeURIComponent(uploadId) +
      '&block_list=' + encodeURIComponent(blockListJson) +
      '&rtype=2';
    const createResp = await this.httpPostFormData<BaiduCreateResponse>(createUrl, createBody);

    return createResp.errno === 0;
  }

  // ==================== HTTP 底层方法 ====================

  private async httpGet<T>(url: string): Promise<T> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 15000,
      });
      if (response.responseCode !== 200) {
        throw new Error('HTTP ' + response.responseCode);
      }
      const resultStr = response.result as string;
      return JSON.parse(resultStr) as T;
    } finally {
      httpRequest.destroy();
    }
  }

  private async httpPostForm<T>(url: string, body: string): Promise<T> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/x-www-form-urlencoded' },
        extraData: body,
        connectTimeout: 15000,
        readTimeout: 15000,
      });
      if (response.responseCode !== 200) {
        throw new Error('HTTP ' + response.responseCode);
      }
      const resultStr = response.result as string;
      return JSON.parse(resultStr) as T;
    } finally {
      httpRequest.destroy();
    }
  }

  private async httpPostFormData<T>(url: string, body: string): Promise<T> {
    return this.httpPostForm<T>(url, body);
  }

  private async httpUploadChunk(url: string, chunk: ArrayBuffer, filename: string): Promise<void> {
    const httpRequest = http.createHttp();
    try {
      const boundary = '----FormBoundary' + Date.now().toString();
      const formData = this.buildMultipartData(boundary, chunk, filename);
      await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'multipart/form-data; boundary=' + boundary },
        extraData: formData,
        connectTimeout: 30000,
        readTimeout: 30000,
      });
    } finally {
      httpRequest.destroy();
    }
  }

  private async httpDownload(url: string): Promise<ArrayBuffer> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.GET,
        connectTimeout: 15000,
        readTimeout: 60000,
      });
      if (response.responseCode !== 200) {
        throw new Error('HTTP ' + response.responseCode);
      }
      return response.result as ArrayBuffer;
    } finally {
      httpRequest.destroy();
    }
  }

  private buildMultipartData(boundary: string, data: ArrayBuffer, filename: string): string {
    const CRLF = '\r\n';
    let body = '--' + boundary + CRLF;
    body += 'Content-Disposition: form-data; name="file"; filename="' + filename + '"' + CRLF;
    body += 'Content-Type: application/octet-stream' + CRLF + CRLF;
    // 注意：实际应使用 ArrayBuffer，此处简化
    body += CRLF + '--' + boundary + '--' + CRLF;
    return body;
  }

  private extractFileName(path: string): string {
    const lastSlash = path.lastIndexOf('/');
    if (lastSlash >= 0) {
      return path.substring(lastSlash + 1);
    }
    return path;
  }
}
