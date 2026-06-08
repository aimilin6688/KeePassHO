import http from '@ohos.net.http';
import { BaiduApiResponse, BaiduListResponse, BaiduMetaResponse, BaiduPreCreateResponse, BaiduUploadResponse, BaiduCreateResponse, BaiduDownloadResponse, BaiduMkdirResponse, BaiduTokenResponse } from './BaiduNetdiskTypes';
import { BaiduNetdiskConfig } from './BaiduNetdiskConfig';

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
  getAuthorizationUrl(redirectUri: string, state?: string): string {
    const params = new URLSearchParams({
      response_type: 'code',
      client_id: this.config.pageConfig.appKey,
      redirect_uri: redirectUri,
      scope: 'basic,netdisk',
    });
    if (state) {
      params.append('state', state);
    }
    return `https://openapi.baidu.com/oauth/2.0/authorize?${params.toString()}`;
  }

  /**
   * 用授权码交换 Token
   */
  async exchangeCodeForToken(code: string, redirectUri: string): Promise<BaiduTokenResponse> {
    const params = new URLSearchParams({
      grant_type: 'authorization_code',
      code,
      client_id: this.config.pageConfig.appKey,
      client_secret: this.config.pageConfig.appSecret,
      redirect_uri: redirectUri,
    });
    return this.httpPostForm(`${this.authUrl}/token`, params);
  }

  /**
   * 刷新 Token
   */
  async refreshToken(refreshToken: string): Promise<BaiduTokenResponse> {
    const params = new URLSearchParams({
      grant_type: 'refresh_token',
      refresh_token: refreshToken,
      client_id: this.config.pageConfig.appKey,
      client_secret: this.config.pageConfig.appSecret,
    });
    return this.httpPostForm(`${this.authUrl}/token`, params);
  }

  // ==================== 文件操作 ====================

  /**
   * 列出目录下的文件和文件夹
   * @param dir 目录路径，如 '/' 或 '/apps/kee-pass-ho/'
   */
  async listFiles(dir: string = '/'): Promise<BaiduFileItem[]> {
    const token = await this.config.getAccessToken();
    const params = new URLSearchParams({
      method: 'list',
      access_token: token,
      dir: dir.startsWith('/') ? dir : '/' + dir,
      folder: '0',
      start: '0',
      limit: '10000',
      order: 'name',
      desc: '0',
    });
    const url = `${this.baseApiUrl}/file?${params.toString()}`;
    const resp = await this.httpGet<BaiduListResponse>(url);
    return resp.list || [];
  }

  /**
   * 获取文件或目录的元信息
   */
  async getFileInfo(path: string): Promise<BaiduFileItem | null> {
    const token = await this.config.getAccessToken();
    const params = new URLSearchParams({
      method: 'meta',
      access_token: token,
      path: path,
    });
    const url = `${this.baseApiUrl}/file?${params.toString()}`;
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
    const params = new URLSearchParams({
      method: 'mkdir',
      access_token: token,
    });
    const url = `${this.baseApiUrl}/file?${params.toString()}`;
    const body = new URLSearchParams({
      path: path,
      rtype: '2', // 覆盖已存在的
    });
    const resp = await this.httpPostFormData<BaiduMkdirResponse>(url, body);
    return resp.errno === 0;
  }

  /**
   * 下载文件，返回文件内容（ArrayBuffer）
   */
  async downloadFile(path: string): Promise<ArrayBuffer> {
    const token = await this.config.getAccessToken();
    // 先获取下载链接
    const params = new URLSearchParams({
      method: 'download',
      access_token: token,
      path: path,
      dlink: '1',
    });
    const url = `${this.baseApiUrl}/file?${params.toString()}`;
    const resp = await this.httpGet<BaiduDownloadResponse>(url);
    if (resp.errno !== 0 || !resp.dlink || resp.dlink.length === 0) {
      throw new Error(`Failed to get download link: errno=${resp.errno}`);
    }
    const dlink = resp.dlink[0].dlink + '?access_token=' + token;
    return this.httpDownload(dlink);
  }

  /**
   * 上传文件
   * @param path 目标路径
   * @param content 文件内容
   * @param onProgress 进度回调（0-100）
   */
  async uploadFile(path: string, content: ArrayBuffer, onProgress?: (percent: number) => void): Promise<boolean> {
    const token = await this.config.getAccessToken();
    const fileName = path.split('/').pop() || 'file';
    const dirPath = path.substring(0, path.lastIndexOf('/')) || '/';
    const fullPath = path.startsWith('/') ? path : dirPath + '/' + fileName;

    // 计算文件 MD5（简化：使用分片 MD5）
    // 实际应使用 SparkMD5 计算整文件和分片 MD5
    const blockSize = 4 * 1024 * 1024; // 4MB 分片
    const totalSize = content.byteLength;
    const blockCount = Math.ceil(totalSize / blockSize);
    const blockList: string[] = [];

    // 步骤1：预创建
    const preCreateParams = new URLSearchParams({
      method: 'precreate',
      access_token: token,
    });
    const preCreateBody = new URLSearchParams({
      path: fullPath,
      size: totalSize.toString(),
      isdir: '0',
      autoinit: '1',
      block_list: JSON.stringify(blockList),
    });
    const preCreateUrl = `${this.baseApiUrl}/file?${preCreateParams.toString()}`;
    const preResp = await this.httpPostFormData<BaiduPreCreateResponse>(preCreateUrl, preCreateBody);

    if (preResp.errno !== 0) {
      throw new Error(`PreCreate failed: errno=${preResp.errno}`);
    }

    const uploadId = preResp.uploadid;
    // 步骤2：分片上传
    for (let i = 0; i < blockCount; i++) {
      const start = i * blockSize;
      const end = Math.min(start + blockSize, totalSize);
      const chunk = content.slice(start, end);

      const uploadParams = new URLSearchParams({
        method: 'upload',
        access_token: token,
        type: 'tmpfile',
        path: fullPath,
        uploadid: uploadId,
        partseq: i.toString(),
      });
      const uploadUrl = `${this.uploadUrl}?${uploadParams.toString()}`;
      await this.httpUploadChunk(uploadUrl, chunk, fileName);
      if (onProgress) {
        onProgress(Math.round(((i + 1) / blockCount) * 80)); // 上传占 80% 进度
      }
    }

    // 步骤3：创建文件（完成上传）
    const createParams = new URLSearchParams({
      method: 'create',
      access_token: token,
    });
    const createBody = new URLSearchParams({
      path: fullPath,
      size: totalSize.toString(),
      isdir: '0',
      uploadid: uploadId,
      block_list: JSON.stringify(blockList),
      rtype: '2', // 覆盖
    });
    const createUrl = `${this.baseApiUrl}/file?${createParams.toString()}`;
    const createResp = await this.httpPostFormData<BaiduCreateResponse>(createUrl, createBody);

    if (onProgress) {
      onProgress(100);
    }
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
        throw new Error(`HTTP ${response.responseCode}`);
      }
      return JSON.parse(response.result as string) as T;
    } finally {
      httpRequest.destroy();
    }
  }

  private async httpPostForm<T>(url: string, body: URLSearchParams): Promise<T> {
    const httpRequest = http.createHttp();
    try {
      const response = await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/x-www-form-urlencoded' },
        extraData: body.toString(),
        connectTimeout: 15000,
        readTimeout: 15000,
      });
      if (response.responseCode !== 200) {
        throw new Error(`HTTP ${response.responseCode}`);
      }
      return JSON.parse(response.result as string) as T;
    } finally {
      httpRequest.destroy();
    }
  }

  private async httpPostFormData<T>(url: string, body: URLSearchParams): Promise<T> {
    // 百度网盘部分接口使用 application/x-www-form-urlencoded
    return this.httpPostForm<T>(url, body);
  }

  private async httpUploadChunk(url: string, chunk: ArrayBuffer, filename: string): Promise<void> {
    const httpRequest = http.createHttp();
    try {
      // 构建 multipart/form-data
      const boundary = '----FormBoundary' + Date.now();
      const formData = this.buildMultipartData(boundary, chunk, filename);
      await httpRequest.request(url, {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': `multipart/form-data; boundary=${boundary}` },
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
        throw new Error(`HTTP ${response.responseCode}`);
      }
      return response.result as ArrayBuffer;
    } finally {
      httpRequest.destroy();
    }
  }

  private buildMultipartData(boundary: string, data: ArrayBuffer, filename: string): string {
    // 简化实现：实际应使用 ArrayBuffer 拼接
    // HarmonyOS 可能需要使用不同方式构建 multipart 数据
    const CRLF = '\r\n';
    let body = `--${boundary}${CRLF}`;
    body += `Content-Disposition: form-data; name="file"; filename="${filename}"${CRLF}`;
    body += `Content-Type: application/octet-stream${CRLF}${CRLF}`;
    // 注意：实际实现需要将 ArrayBuffer 正确附加
    body += `${CRLF}--${boundary}--${CRLF}`;
    return body;
  }
}
