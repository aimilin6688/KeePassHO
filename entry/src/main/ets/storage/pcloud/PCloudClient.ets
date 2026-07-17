import { rcp } from '@kit.RemoteCommunicationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { ByteUtils } from 'kdbxweb';

const DOMAIN = 0x0000;
const TAG = 'PCloudClient';

/**
 * pCloud API 错误
 * result !== 0 时抛出
 */
export class PCloudError extends Error {
  public code: number;

  constructor(code: number, message?: string) {
    super(message ? ('pCloud error ' + code + ': ' + message) : ('pCloud error ' + code));
    this.name = 'PCloudError';
    this.code = code;
  }
}

/**
 * pCloud 文件/文件夹元数据
 */
export interface PCloudMetadata {
  fileid?: number;
  folderid?: number;
  name: string;
  path?: string;
  isfolder: boolean;
  size?: number;
  modified: string;
  created?: string;
  contenttype?: string;
  hash?: number;
  category?: number;
  parentfolderid?: number;
  ismine?: boolean;
  isshared?: boolean;
  thumb?: boolean;
  icon?: string;
  contents?: PCloudMetadata[];
}

/**
 * 下载链接响应结构
 */
export interface PCloudLinkResult {
  hosts: string[];
  path: string;
}

/**
 * pCloud HTTP API 客户端
 *
 * 基于 rcp (@kit.RemoteCommunicationKit) 实现
 * 所有请求通过 URL query parameter 传递 access_token
 * 响应检查 result === 0，非零抛出 PCloudError
 */
export class PCloudClient {
  private static readonly BASE_URL: string = 'https://api.pcloud.com';

  private session: rcp.Session | null = null;
  private accessToken: string = '';

  constructor() {
    this.session = rcp.createSession({
      requestConfiguration: {
        transfer: {
          timeout: { connectMs: 30000 }
        }
      }
    });
  }

  /**
   * 设置 access_token，后续所有请求自动附加
   */
  setAccessToken(token: string): void {
    this.accessToken = token;
  }

  /**
   * 构建完整 URL，附加 access_token 和查询参数
   */
  private buildUrl(path: string, params?: Record<string, string>): string {
    let queryParts: string[] = [];
    if (this.accessToken) {
      queryParts.push('access_token=' + encodeURIComponent(this.accessToken));
    }
    if (params) {
      const keys = Object.getOwnPropertyNames(params);
      for (let i = 0; i < keys.length; i++) {
        const key = keys[i];
        const value = params[key];
        queryParts.push(encodeURIComponent(key) + '=' + encodeURIComponent(value));
      }
    }
    if (queryParts.length > 0) {
      return path + '?' + queryParts.join('&');
    }
    return path;
  }

  /**
   * 检查 pCloud API JSON 响应中的 result 字段
   */
  private checkResponse(data: Record<string, Object>): void {
    const resultValue = data['result'];
    if (resultValue !== undefined && typeof resultValue === 'number' && resultValue !== 0) {
      const error = data['error'] as string | undefined;
      throw new PCloudError(resultValue, error);
    }
  }

  /**
   * 将 rcp.Response.body (ArrayBuffer) 解析为 JSON 对象
   */
  private responseToJson(response: rcp.Response): Record<string, Object> {
    const body = response.body;
    if (!body) {
      return {};
    }
    const str = ByteUtils.bytesToString(body);
    return JSON.parse(str) as Record<string, Object>;
  }

  /**
   * 执行 GET 请求，返回解析后的 JSON
   */
  private async getJson(path: string, params?: Record<string, string>): Promise<Record<string, Object>> {
    if (this.session === null) {
      throw new Error('PCloudClient session is closed');
    }
    const url = this.buildUrl(path, params);
    hilog.info(DOMAIN, TAG, 'GET ' + path);
    const req = new rcp.Request(url, 'GET');
    const resp = await this.session.fetch(req);
    const data = this.responseToJson(resp);
    this.checkResponse(data);
    return data;
  }

  /**
   * 列出文件夹内容
   * GET /listfolder?folderid={id}
   */
  async listFolder(folderId: string): Promise<PCloudMetadata[]> {
    const params: Record<string, string> = {};
    params['folderid'] = folderId;
    const data = await this.getJson('/listfolder', params);
    const metadata = data['metadata'] as Record<string, Object> | undefined;
    if (!metadata) {
      throw new PCloudError(-1, 'listFolder: missing metadata in response');
    }
    const contents = metadata['contents'] as PCloudMetadata[] | undefined;
    if (!contents) {
      return [];
    }
    return contents;
  }

  /**
   * 获取文件/文件夹详细信息
   * GET /stat?fileid={id}
   */
  async stat(fileId: string): Promise<PCloudMetadata> {
    const params: Record<string, string> = {};
    params['fileid'] = fileId;
    const data = await this.getJson('/stat', params);
    const metadata = data['metadata'] as PCloudMetadata | undefined;
    if (!metadata) {
      throw new PCloudError(-1, 'stat: missing metadata in response');
    }
    return metadata;
  }

  /**
   * 获取文件下载链接
   * GET /getfilelink?fileid={id}
   */
  async getFileLink(fileId: string): Promise<PCloudLinkResult> {
    const params: Record<string, string> = {};
    params['fileid'] = fileId;
    const data = await this.getJson('/getfilelink', params);
    const hosts = data['hosts'] as string[] | undefined;
    const path = data['path'] as string | undefined;
    if (!hosts || !path || hosts.length === 0) {
      throw new PCloudError(-1, 'getFileLink: invalid response');
    }
    const result: PCloudLinkResult = {
      hosts: hosts,
      path: path
    };
    return result;
  }

  /**
   * 下载文件
   * 两步：getfilelink → hosts[0] + path → HTTP GET ArrayBuffer
   */
  async downloadFile(fileId: string): Promise<ArrayBuffer> {
    if (this.session === null) {
      throw new Error('PCloudClient session is closed');
    }
    const link = await this.getFileLink(fileId);
    const downloadUrl = link.hosts[0] + link.path;
    hilog.info(DOMAIN, TAG, 'downloadFile: ' + downloadUrl);
    const req = new rcp.Request(downloadUrl, 'GET');
    const resp = await this.session.fetch(req);
    if (resp.statusCode !== 200) {
      throw new PCloudError(resp.statusCode, 'downloadFile: HTTP ' + resp.statusCode);
    }
    const body = resp.body;
    if (!body) {
      throw new PCloudError(-1, 'downloadFile: empty response body');
    }
    return body;
  }

  /**
   * 上传文件
   * POST /uploadfile multipart/form-data
   *
   * 使用 rcp MultipartForm，按 pCloud 要求先添加 folderid/filename 参数，再添加文件数据
   */
  async uploadFile(folderId: string, name: string, data: ArrayBuffer): Promise<PCloudMetadata> {
    if (this.session === null) {
      throw new Error('PCloudClient session is closed');
    }
    const url = this.buildUrl('/uploadfile');
    // 使用文本编码器手动构建 multipart body
    const boundary = '----PCloudBoundary' + Date.now();
    const encoder = new util.TextEncoder();
    const crlf = '\r\n';
    
    // 构建 multipart body 各部分
    const parts: Uint8Array[] = [];

    // 参数部分：folderid
    let partStr = '--' + boundary + crlf;
    partStr += 'Content-Disposition: form-data; name="folderid"' + crlf + crlf;
    partStr += folderId + crlf;
    parts.push(encoder.encode(partStr));

    // 参数部分：filename
    partStr = '--' + boundary + crlf;
    partStr += 'Content-Disposition: form-data; name="filename"' + crlf + crlf;
    partStr += name + crlf;
    parts.push(encoder.encode(partStr));

    // 文件数据部分
    partStr = '--' + boundary + crlf;
    partStr += 'Content-Disposition: form-data; name="file"; filename="' + name + '"' + crlf;
    partStr += 'Content-Type: application/octet-stream' + crlf + crlf;
    parts.push(encoder.encode(partStr));

    // 文件二进制数据
    parts.push(new Uint8Array(data));

    // 结束部分
    parts.push(encoder.encode(crlf + '--' + boundary + '--' + crlf));

    // 合并所有部分
    let totalLength = 0;
    for (let i = 0; i < parts.length; i++) {
      totalLength += parts[i].length;
    }
    const merged = new Uint8Array(totalLength);
    let offset = 0;
    for (let i = 0; i < parts.length; i++) {
      merged.set(parts[i], offset);
      offset += parts[i].length;
    }

    const headers: Record<string, string> = {};
    headers['Content-Type'] = 'multipart/form-data; boundary=' + boundary;
    const req = new rcp.Request(url, 'POST', headers, merged.buffer);
    const resp = await this.session.fetch(req);
    const jsonData = this.responseToJson(resp);
    this.checkResponse(jsonData);
    const metadata = jsonData['metadata'] as PCloudMetadata[] | undefined;
    if (metadata && metadata.length > 0) {
      return metadata[0];
    }
    throw new PCloudError(-1, 'uploadFile: missing metadata in response');
  }

  /**
   * 创建文件夹
   * GET /createfolder?folderid={id}&name={name}
   */
  async createFolder(parentId: string, name: string): Promise<PCloudMetadata> {
    const params: Record<string, string> = {};
    params['folderid'] = parentId;
    params['name'] = name;
    const data = await this.getJson('/createfolder', params);
    const metadata = data['metadata'] as PCloudMetadata | undefined;
    if (!metadata) {
      throw new PCloudError(-1, 'createFolder: missing metadata in response');
    }
    return metadata;
  }

  /**
   * 删除文件
   * GET /deletefile?fileid={id}
   */
  async deleteFile(fileId: string): Promise<void> {
    const params: Record<string, string> = {};
    params['fileid'] = fileId;
    await this.getJson('/deletefile', params);
  }

  /**
   * 重命名文件
   * GET /renamefile?fileid={id}&toname={name}
   */
  async renameFile(fileId: string, toName: string): Promise<void> {
    const params: Record<string, string> = {};
    params['fileid'] = fileId;
    params['toname'] = toName;
    await this.getJson('/renamefile', params);
  }

  /**
   * 获取用户信息
   * GET /userinfo
   */
  async userInfo(): Promise<Record<string, Object>> {
    return await this.getJson('/userinfo');
  }

  /**
   * 关闭会话
   */
  close(): void {
    if (this.session) {
      this.session.close();
      this.session = null;
    }
  }
}
