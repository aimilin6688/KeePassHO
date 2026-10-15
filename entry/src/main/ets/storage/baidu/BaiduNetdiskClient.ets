import { hilog } from '@kit.PerformanceAnalysisKit';
import { rcp } from '@kit.RemoteCommunicationKit';
import { ByteUtils } from 'kdbxweb';
import { StorageError, StorageErrorCodes } from '../StorageError';
import {
  BAIDU_RATE_LIMIT_ERRNOS,
  BAIDU_TOKEN_INVALID_ERRNOS,
  BAIDU_UPLOADID_EXPIRED_ERRNOS,
  BaiduApiError,
  BaiduFileMeta,
  BaiduNetdiskConstants,
  BaiduNetdiskParser,
  BaiduPrecreateResp
} from './BaiduNetdiskTypes';

const DOMAIN = 0x0000;
const TAG = 'BaiduNetdiskClient';

/**
 * superfile2 分片单次请求超时（毫秒）：非会员上行带宽受限，4MB 分片需较长传输时间
 */
const UPLOAD_SLICE_TIMEOUT_MS: number = 300000;

/**
 * JSON API 单次请求超时（毫秒）
 */
const API_TIMEOUT_MS: number = 60000;

/**
 * 下载整文件单次请求超时（毫秒）
 */
const DOWNLOAD_TIMEOUT_MS: number = 300000;

/**
 * superfile2 可重试业务错误码（当前分片重试）
 */
const SLICE_RETRYABLE_ERRNOS: number[] = [31081];

/**
 * uploadid 过期/失效错误（外层重新 precreate 全量重传）
 */
export class BaiduUploadIdExpiredError extends Error {
  readonly errno: number;

  constructor(errno: number, message: string) {
    super(`uploadid expired (errno=${errno}): ${message}`);
    this.name = 'BaiduUploadIdExpiredError';
    this.errno = errno;
  }
}

/**
 * 百度网盘 xpan/pcs API 客户端（设计文档 D2/D3/D5/D6/D11）
 * 请求层统一处理：access_token 失效刷新重试、频次限制退避、网络错误退避、
 * errno 体系（xpan errno / PCS error_code）到 BaiduApiError 的映射
 */
export class BaiduNetdiskClient {
  private accessToken: string;
  /**
   * 令牌刷新回调（由 Storage 注入，刷新成功返回新 access_token）
   */
  private readonly tokenRefresher: () => Promise<string>;

  constructor(accessToken: string, tokenRefresher: () => Promise<string>) {
    this.accessToken = accessToken;
    this.tokenRefresher = tokenRefresher;
  }

  /**
   * 更新访问令牌（token 刷新成功后由 Storage 调用）
   */
  public updateAccessToken(accessToken: string): void {
    this.accessToken = accessToken;
  }

  /**
   * 规范化远端路径：保证以 / 开头、去除末尾多余 /、根目录为 /
   */
  public static normalizePath(path: string): string {
    if (!path || path.trim().length === 0) {
      return '/';
    }
    let normalized = path.trim();
    if (!normalized.startsWith('/')) {
      normalized = '/' + normalized;
    }
    while (normalized.length > 1 && normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  /**
   * 取路径末段文件名（根目录返回空串）
   */
  public static lastSegment(path: string): string {
    const normalized = BaiduNetdiskClient.normalizePath(path);
    if (normalized === '/') {
      return '';
    }
    const lastSlash = normalized.lastIndexOf('/');
    return normalized.substring(lastSlash + 1);
  }

  /**
   * 获取用户信息（xpan uinfo）
   */
  public async getUinfo(): Promise<Record<string, Object>> {
    return await this.requestJson(BaiduNetdiskConstants.PAN_BASE, '/xpan/nas', 'GET', {
      'method': 'uinfo',
      'access_token': this.accessToken
    });
  }

  /**
   * 列出目录内容（单页，xpan list）
   * @param dir 目录绝对路径
   * @param start 起始位置
   * @param limit 单页条数
   * @throws BaiduApiError errno!==0（含 -9 目录不存在）
   */
  public async listDir(dir: string, start: number, limit: number): Promise<Array<BaiduFileMeta>> {
    const json = await this.requestJson(BaiduNetdiskConstants.PAN_BASE, '/xpan/file', 'GET', {
      'method': 'list',
      'access_token': this.accessToken,
      'dir': dir,
      'order': 'name',
      'desc': '0',
      'start': String(start),
      'limit': String(limit),
      'web': '1',
      'folder': '0'
    });
    const errno = this.extractErrno(json);
    if (errno !== 0) {
      throw new BaiduApiError(errno, BaiduNetdiskParser.readString(json, 'error_msg'));
    }
    const rawList = BaiduNetdiskParser.readObjectArray(json, 'list');
    const result: BaiduFileMeta[] = [];
    for (let i = 0; i < rawList.length; i++) {
      result.push(BaiduNetdiskParser.parseFileMeta(rawList[i]));
    }
    return result;
  }

  /**
   * 按路径解析文件/目录元信息（百度无按路径取元信息 API，list 父目录分页 + 精确匹配）
   * @param path 文件/目录绝对路径
   * @returns 元信息；父目录不存在（-9/50002 等）或未命中返回 null；其余异常上抛
   */
  public async resolveFileInfo(path: string): Promise<BaiduFileMeta | null> {
    const normalized = BaiduNetdiskClient.normalizePath(path);
    if (normalized === '/') {
      // 根目录恒存在，合成目录元信息
      return {
        fsId: 0,
        path: '/',
        serverFilename: '',
        isdir: 1,
        size: 0,
        md5: '',
        dlink: '',
        serverCtime: 0,
        serverMtime: 0
      };
    }
    const lastSlash = normalized.lastIndexOf('/');
    const parentDir = lastSlash === 0 ? '/' : normalized.substring(0, lastSlash);
    const filename = normalized.substring(lastSlash + 1);
    let start = 0;
    while (true) {
      let metas: Array<BaiduFileMeta>;
      try {
        metas = await this.listDir(parentDir, start, BaiduNetdiskConstants.LIST_PAGE_SIZE);
      } catch (error) {
        const err: Error = error as Error;
        // 父目录不存在 → 文件确定不存在
        if (err instanceof BaiduApiError
          && BAIDU_TOKEN_INVALID_ERRNOS.indexOf(err.errno) < 0
          && BAIDU_RATE_LIMIT_ERRNOS.indexOf(err.errno) < 0
          && this.isNotFoundErrno(err.errno)) {
          return null;
        }
        throw err;
      }
      for (let i = 0; i < metas.length; i++) {
        if (metas[i].serverFilename === filename) {
          return metas[i];
        }
      }
      if (metas.length < BaiduNetdiskConstants.LIST_PAGE_SIZE) {
        return null;
      }
      start += metas.length;
    }
  }

  /**
   * 获取文件元信息（含 dlink 预授权下载链接，filemetas）
   */
  public async getFileMetaWithDlink(fsId: number): Promise<BaiduFileMeta> {
    const json = await this.requestJson(BaiduNetdiskConstants.PAN_BASE, '/xpan/multimedia', 'GET', {
      'method': 'filemetas',
      'access_token': this.accessToken,
      'fsids': JSON.stringify([fsId]),
      'dlink': '1',
      'thumb': '0'
    });
    const errno = this.extractErrno(json);
    if (errno !== 0) {
      throw new BaiduApiError(errno, BaiduNetdiskParser.readString(json, 'error_msg'));
    }
    const rawList = BaiduNetdiskParser.readObjectArray(json, 'list');
    if (rawList.length === 0) {
      throw new BaiduApiError(errno, 'filemetas response missing list');
    }
    return BaiduNetdiskParser.parseFileMeta(rawList[0]);
  }

  /**
   * 下载文件到内存（小文件 read 路径）
   * 固定 UA + rcp 默认跟随 302（D3）；dlink 后追加 access_token
   */
  public async download(dlink: string): Promise<ArrayBuffer> {
    const url = this.appendAccessToken(dlink);
    const session = rcp.createSession({
      headers: {
        'User-Agent': BaiduNetdiskConstants.DOWNLOAD_UA
      }
    });
    try {
      const request = new rcp.Request(url, 'GET');
      request.configuration = {
        transfer: {
          timeout: { connectMs: 30000, transferMs: DOWNLOAD_TIMEOUT_MS }
        }
      };
      const response = await session.fetch(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw new BaiduApiError(response.statusCode,
          `download failed, status=${response.statusCode}`);
      }
      if (!response.body) {
        throw new BaiduApiError(response.statusCode, 'download empty body');
      }
      return response.body;
    } finally {
      session.close();
    }
  }

  /**
   * 流式下载到本地文件（readToFile 路径，响应体不驻留内存）
   * @param dlink 预授权下载链接
   * @param destPath 本地目标文件路径
   * @param onProgress 下载进度回调（可选）：rcp onDownloadProgress 透传
   */
  public async downloadToFile(dlink: string, destPath: string,
    onProgress?: (totalSize: number, transferredSize: number) => void): Promise<void> {
    const url = this.appendAccessToken(dlink);
    const configuration: rcp.Configuration = {
      transfer: {
        timeout: { connectMs: 30000, transferMs: DOWNLOAD_TIMEOUT_MS }
      }
    };
    if (onProgress) {
      const progressCallback = onProgress;
      configuration.tracing = {
        httpEventsHandler: {
          onDownloadProgress: (totalSize: number, transferredSize: number): void => {
            progressCallback(totalSize, transferredSize);
          }
        }
      };
    }
    const session = rcp.createSession({
      headers: {
        'User-Agent': BaiduNetdiskConstants.DOWNLOAD_UA
      },
      requestConfiguration: configuration
    });
    try {
      await session.downloadToFile(url, { kind: 'file', file: destPath } as rcp.DownloadToFile);
    } finally {
      session.close();
    }
  }

  /**
   * 预上传（precreate，rtype=3 覆盖 + 秒传三元组，D5）
   * @param path 远端绝对路径
   * @param size 文件大小（字节）
   * @param blockList 4MB 分片 md5 数组
   * @param contentMd5 整文件 md5
   * @param sliceMd5 前 256KB md5
   * @param localCtime 本地创建时间（秒）
   * @param localMtime 本地修改时间（秒）
   */
  public async precreate(path: string, size: number, blockList: Array<string>, contentMd5: string,
    sliceMd5: string, localCtime: number, localMtime: number): Promise<BaiduPrecreateResp> {
    const form = new rcp.Form({
      'method': 'precreate',
      'path': path,
      'size': String(size),
      'isdir': '0',
      'autoinit': '1',
      'rtype': String(BaiduNetdiskConstants.RTYPE_OVERWRITE),
      'block_list': JSON.stringify(blockList),
      'content-md5': contentMd5,
      'slice-md5': sliceMd5,
      'local_ctime': String(localCtime),
      'local_mtime': String(localMtime)
    });
    const json = await this.requestJson(BaiduNetdiskConstants.PAN_BASE, '/xpan/file', 'POST', {
      'access_token': this.accessToken
    }, form);
    const resp = BaiduNetdiskParser.parsePrecreateResp(json);
    if (resp.errno !== 0) {
      throw new BaiduApiError(resp.errno, BaiduNetdiskParser.readString(json, 'error_msg'));
    }
    return resp;
  }

  /**
   * 分片上传（PCS superfile2，multipart 字段名 file，固定域名 d.pcs.baidu.com，D11）
   * @returns 分片 md5（百度返回）
   * @throws BaiduUploadIdExpiredError uploadid 过期/任务不存在（外层重新 precreate）
   */
  public async uploadSlice(remotePath: string, uploadid: string, partSeq: number,
    data: ArrayBuffer): Promise<string> {
    const url = this.buildUrl(BaiduNetdiskConstants.PCS_BASE, '/pcs/superfile2', {
      'method': 'upload',
      'type': 'tmpfile',
      'access_token': this.accessToken,
      'path': remotePath,
      'uploadid': uploadid,
      'partseq': String(partSeq)
    });
    const form = new rcp.MultipartForm({
      'file': {
        contentType: 'application/octet-stream',
        remoteFileName: 'blob',
        contentOrPath: { content: data }
      }
    });
    let attempt = 0;
    while (true) {
      let json: Record<string, Object>;
      try {
        json = await this.fetchJson(url, 'POST', form, UPLOAD_SLICE_TIMEOUT_MS);
      } catch (error) {
        const err: Error = error as Error;
        // 网络层瞬时错误退避重试
        if (!(err instanceof BaiduApiError) && !(err instanceof StorageError)
          && attempt < 3) {
          attempt++;
          await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
          continue;
        }
        throw err;
      }
      const errno = this.extractErrno(json);
      if (errno !== 0) {
        const errorMsg = BaiduNetdiskParser.readString(json, 'error_msg');
        if (BAIDU_UPLOADID_EXPIRED_ERRNOS.indexOf(errno) >= 0) {
          throw new BaiduUploadIdExpiredError(errno, errorMsg);
        }
        const lowerMsg = errorMsg.toLowerCase();
        if (lowerMsg.includes('uploadid')
          && (lowerMsg.includes('expired') || lowerMsg.includes('invalid') || lowerMsg.includes('not found'))) {
          throw new BaiduUploadIdExpiredError(errno, errorMsg);
        }
        if (SLICE_RETRYABLE_ERRNOS.indexOf(errno) >= 0 && attempt < 3) {
          attempt++;
          await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
          continue;
        }
        throw new BaiduApiError(errno, errorMsg);
      }
      const md5 = BaiduNetdiskParser.readString(json, 'md5');
      if (md5.length === 0) {
        if (attempt < 3) {
          attempt++;
          await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
          continue;
        }
        throw new BaiduApiError(errno, 'superfile2 response missing md5');
      }
      return md5;
    }
  }

  /**
   * 创建文件（create，完整 block_list + uploadid + rtype=3）
   * @returns 远端文件元信息（注意 R6：时间字段为服务器当前时间，展示需谨慎使用）
   */
  public async createFile(path: string, size: number, uploadid: string, blockList: Array<string>,
    localCtime: number, localMtime: number): Promise<BaiduFileMeta> {
    const form = new rcp.Form({
      'method': 'create',
      'path': path,
      'size': String(size),
      'isdir': '0',
      'uploadid': uploadid,
      'rtype': String(BaiduNetdiskConstants.RTYPE_OVERWRITE),
      'block_list': JSON.stringify(blockList),
      'local_ctime': String(localCtime),
      'local_mtime': String(localMtime)
    });
    const json = await this.requestJson(BaiduNetdiskConstants.PAN_BASE, '/xpan/file', 'POST', {
      'access_token': this.accessToken
    }, form);
    const errno = this.extractErrno(json);
    if (errno !== 0) {
      throw new BaiduApiError(errno, BaiduNetdiskParser.readString(json, 'error_msg'));
    }
    return BaiduNetdiskParser.parseFileMeta(json);
  }

  /**
   * 统一 JSON 请求层：
   * - access_token 失效（-6/111/20016）：经 tokenRefresher 刷新后重试 1 次，仍失败 AUTH_EXPIRED
   * - 频次限制（31034/31064）：指数退避 1s/2s/4s 重试 3 次
   * - 网络层错误：指数退避重试 3 次
   * - 其余（含调用方语义 errno）原样返回由调用方解释
   */
  private async requestJson(baseUrl: string, apiPath: string, method: rcp.HttpMethod,
    queryParams: Record<string, string>, form?: rcp.Form): Promise<Record<string, Object>> {
    let url = this.buildUrl(baseUrl, apiPath, queryParams);
    let tokenRefreshed = false;
    let attempt = 0;
    while (true) {
      let json: Record<string, Object>;
      try {
        json = await this.fetchJson(url, method, form, API_TIMEOUT_MS);
      } catch (error) {
        const err: Error = error as Error;
        if (!(err instanceof BaiduApiError) && !(err instanceof StorageError) && attempt < 3) {
          attempt++;
          await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
          continue;
        }
        throw err;
      }
      const errno = this.extractErrno(json);
      if (BAIDU_TOKEN_INVALID_ERRNOS.indexOf(errno) >= 0) {
        if (tokenRefreshed) {
          throw new StorageError(StorageErrorCodes.AUTH_EXPIRED, `Baidu access token invalid, errno=${errno}`);
        }
        tokenRefreshed = true;
        const newToken = await this.tokenRefresher();
        this.updateAccessToken(newToken);
        queryParams['access_token'] = newToken;
        url = this.buildUrl(baseUrl, apiPath, queryParams);
        continue;
      }
      if (BAIDU_RATE_LIMIT_ERRNOS.indexOf(errno) >= 0 && attempt < 3) {
        attempt++;
        await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
        continue;
      }
      return json;
    }
  }

  /**
   * 单次 HTTP 请求并解析 JSON（不含重试语义）
   */
  private async fetchJson(url: string, method: rcp.HttpMethod, form: rcp.Form | rcp.MultipartForm | undefined,
    timeoutMs: number): Promise<Record<string, Object>> {
    const session = rcp.createSession();
    try {
      const request = new rcp.Request(url, method);
      if (form !== undefined) {
        request.content = form;
      }
      request.configuration = {
        transfer: {
          timeout: { connectMs: 30000, transferMs: timeoutMs }
        }
      };
      const response = await session.fetch(request);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        const text = response.body ? ByteUtils.bytesToString(response.body) : '';
        throw new BaiduApiError(response.statusCode, `HTTP ${response.statusCode}: ${text}`);
      }
      if (!response.body) {
        throw new BaiduApiError(response.statusCode, 'empty response body');
      }
      const text = ByteUtils.bytesToString(response.body);
      return JSON.parse(text) as Record<string, Object>;
    } finally {
      session.close();
    }
  }

  /**
   * dlink 后追加 access_token（已含时不重复追加）
   */
  private appendAccessToken(dlink: string): string {
    if (dlink.indexOf('access_token=') >= 0) {
      return dlink;
    }
    return dlink + (dlink.indexOf('?') >= 0 ? '&' : '?')
      + 'access_token=' + encodeURIComponent(this.accessToken);
  }

  /**
   * 提取业务错误码（xpan 用 errno，PCS superfile2 用 error_code）
   */
  private extractErrno(json: Record<string, Object>): number {
    const errno = json['errno'];
    if (errno !== undefined && errno !== null && typeof errno === 'number') {
      return errno;
    }
    const errorCode = json['error_code'];
    if (errorCode !== undefined && errorCode !== null && typeof errorCode === 'number') {
      return errorCode;
    }
    return 0;
  }

  private isNotFoundErrno(errno: number): boolean {
    return errno === -9 || errno === 50002 || errno === 42212;
  }

  /**
   * 拼装 URL（encodeURIComponent 编码查询参数）
   */
  private buildUrl(baseUrl: string, apiPath: string, params: Record<string, string>): string {
    const pairs: string[] = [];
    const entries = Object.entries(params);
    for (let i = 0; i < entries.length; i++) {
      const key = entries[i][0];
      const value = entries[i][1];
      if (value === undefined || value === null) {
        continue;
      }
      pairs.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    }
    const query = pairs.join('&');
    return query.length > 0 ? `${baseUrl}${apiPath}?${query}` : `${baseUrl}${apiPath}`;
  }

  private static sleep(ms: number): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(resolve, ms);
    });
  }
}
