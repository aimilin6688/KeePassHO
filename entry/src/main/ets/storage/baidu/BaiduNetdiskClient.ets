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
 * 弱网下载失败自动重试次数（整段重下，指数退避 1s/2s/4s）
 * DownloadToFile keepLocal 默认 false（覆盖写），整段重下幂等安全
 */
const DOWNLOAD_MAX_RETRIES: number = 3;

/**
 * superfile2 可重试业务错误码（当前分片重试）
 */
const SLICE_RETRYABLE_ERRNOS: number[] = [31081];

/**
 * locateupload 上传域名缓存默认有效期（秒，响应未返回 expire 时）
 */
const UPLOAD_HOST_DEFAULT_TTL_SEC: number = 60;

/**
 * 上传域名缓存条目上限（超过后整体清空，避免长期运行膨胀）
 */
const UPLOAD_HOST_CACHE_MAX_ENTRIES: number = 16;

/**
 * 上传域名缓存条目（按 uploadid 维度）
 */
interface BaiduUploadHostCache {
  host: string;
  expiresAt: number;
}

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
  /**
   * 上传域名缓存（uploadid → locateupload 结果，短期缓存）
   */
  private uploadHostCache: Map<string, BaiduUploadHostCache> = new Map();

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
   * 逻辑路径 → 远端绝对路径（应用目录映射）
   * 权限与配额文档：第三方应用仅能操作 /apps/{应用名称} 下的文件，
   * 逻辑根 / 映射为应用目录；已含应用目录前缀的路径原样返回
   */
  public static toRemotePath(path: string): string {
    const normalized = BaiduNetdiskClient.normalizePath(path);
    const appDir = BaiduNetdiskConstants.APP_DIR;
    if (normalized === appDir || normalized.startsWith(appDir + '/')) {
      return normalized;
    }
    return normalized === '/' ? appDir : appDir + normalized;
  }

  /**
   * 远端绝对路径 → 逻辑路径（剥离应用目录前缀，UI/配置只见逻辑路径空间）
   */
  public static toLogicalPath(remotePath: string): string {
    const appDir = BaiduNetdiskConstants.APP_DIR;
    if (remotePath === appDir) {
      return '/';
    }
    if (remotePath.startsWith(appDir + '/')) {
      return remotePath.substring(appDir.length);
    }
    return remotePath;
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
    const remoteDir = BaiduNetdiskClient.toRemotePath(dir);
    const json = await this.requestJson(BaiduNetdiskConstants.PAN_BASE, '/xpan/file', 'GET', {
      'method': 'list',
      'access_token': this.accessToken,
      'dir': remoteDir,
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
    const remotePath = BaiduNetdiskClient.toRemotePath(path);
    if (remotePath === BaiduNetdiskConstants.APP_DIR) {
      // 应用目录视为恒存在：权限文档目录下首个文件上传时由百度自动创建
      return {
        fsId: 0,
        path: remotePath,
        serverFilename: BaiduNetdiskClient.lastSegment(remotePath),
        isdir: 1,
        size: 0,
        md5: '',
        dlink: '',
        serverCtime: 0,
        serverMtime: 0
      };
    }
    const lastSlash = remotePath.lastIndexOf('/');
    const parentDir = lastSlash === 0 ? '/' : remotePath.substring(0, lastSlash);
    const filename = remotePath.substring(lastSlash + 1);
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
   * 固定 UA + rcp 默认跟随 302（D3）；dlink 后追加 access_token；
   * 弱网失败指数退避整段重下（DOWNLOAD_MAX_RETRIES 次）
   */
  public async download(dlink: string): Promise<ArrayBuffer> {
    const url = this.appendAccessToken(dlink);
    let attempt = 0;
    while (true) {
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
      } catch (error) {
        if (attempt < DOWNLOAD_MAX_RETRIES) {
          attempt++;
          hilog.warn(DOMAIN, TAG, 'download failed, retry %{public}d/%{public}d: %{public}s',
            String(attempt), String(DOWNLOAD_MAX_RETRIES), (error as Error).message);
          await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
          continue;
        }
        throw error as Error;
      } finally {
        session.close();
      }
    }
  }

  /**
   * 流式下载到本地文件（readToFile 路径，响应体不驻留内存）
   * 弱网失败指数退避整段重下（DOWNLOAD_MAX_RETRIES 次，覆盖写幂等）；
   * 重试时进度从 0 重新上报（rcp onDownloadProgress 重新触发）
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
    let attempt = 0;
    while (true) {
      const session = rcp.createSession({
        headers: {
          'User-Agent': BaiduNetdiskConstants.DOWNLOAD_UA
        },
        requestConfiguration: configuration
      });
      try {
        await session.downloadToFile(url, { kind: 'file', file: destPath } as rcp.DownloadToFile);
        return;
      } catch (error) {
        if (attempt < DOWNLOAD_MAX_RETRIES) {
          attempt++;
          hilog.warn(DOMAIN, TAG, 'downloadToFile failed, retry %{public}d/%{public}d: %{public}s',
            String(attempt), String(DOWNLOAD_MAX_RETRIES), (error as Error).message);
          await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
          continue;
        }
        throw error as Error;
      } finally {
        session.close();
      }
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
    const remotePath = BaiduNetdiskClient.toRemotePath(path);
    // xpan 规范：method/access_token 走 URL query，业务参数走 form body（method 在 body 会报
    // error_code 3 "Unsupported open api"）
    const form = new rcp.Form({
      'path': remotePath,
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
      'method': 'precreate',
      'access_token': this.accessToken
    }, form);
    const resp = BaiduNetdiskParser.parsePrecreateResp(json);
    if (resp.errno !== 0) {
      throw new BaiduApiError(resp.errno, BaiduNetdiskParser.readString(json, 'error_msg'));
    }
    return resp;
  }

  /**
   * 分片上传（PCS superfile2，multipart 字段名 file）
   * 上传域名经 locateupload 动态获取（按 uploadid 短期缓存，域名不可用时重取）；
   * 上传成功后校验返回 md5 与预上传 block_list 对应分片 md5 一致（不一致退避重试）；
   * 请求级 tracing onUploadProgress 上报分片内实时字节进度（与其他存储的字节级进度口径一致）
   * @param remotePath 远端文件路径
   * @param uploadid 预上传任务 id
   * @param partSeq 分片序号（precreate 返回 block_list 中的待传序号）
   * @param data 分片内容
   * @param expectedMd5 预上传 block_list 中该分片的 md5
   * @param onSliceProgress 分片内字节进度回调（可选）：(sliceTransferred, sliceTotal)
   * @returns 分片 md5（百度返回，已校验与 expectedMd5 一致）
   * @throws BaiduUploadIdExpiredError uploadid 过期/任务不存在（外层重新 precreate）
   */
  public async uploadSlice(remotePath: string, uploadid: string, partSeq: number,
    data: ArrayBuffer, expectedMd5: string,
    onSliceProgress?: (sliceTransferred: number, sliceTotal: number) => void): Promise<string> {
    const remote = BaiduNetdiskClient.toRemotePath(remotePath);
    const form = new rcp.MultipartForm({
      'file': {
        contentType: 'application/octet-stream',
        remoteFileName: 'blob',
        contentOrPath: { content: data }
      }
    });
    // multipart 请求体含少量协议开销，按分片长度钳制，避免累计进度超出文件总大小
    const uploadProgressAdapter: ((totalSize: number, transferredSize: number) => void) | undefined =
      onSliceProgress ? (totalSize: number, transferredSize: number): void => {
        onSliceProgress(Math.min(transferredSize, data.byteLength), data.byteLength);
      } : undefined;
    let uploadHost: string = await this.getUploadHost(remote, uploadid);
    let hostRefetched = false;
    let attempt = 0;
    while (true) {
      const url = this.buildUrl(`${uploadHost}/rest/2.0`, '/pcs/superfile2', {
        'method': 'upload',
        'type': 'tmpfile',
        'access_token': this.accessToken,
        'path': remote,
        'uploadid': uploadid,
        'partseq': String(partSeq)
      });
      let json: Record<string, Object>;
      try {
        json = await this.fetchJson(url, 'POST', form, UPLOAD_SLICE_TIMEOUT_MS, uploadProgressAdapter);
      } catch (error) {
        const err: Error = error as Error;
        // 网络层瞬时错误退避重试；首次同时失效域名缓存并重取（上传域名不可用场景）
        if (!(err instanceof BaiduApiError) && !(err instanceof StorageError)
          && attempt < 3) {
          attempt++;
          if (!hostRefetched) {
            hostRefetched = true;
            this.uploadHostCache.delete(uploadid);
            uploadHost = await this.getUploadHost(remote, uploadid);
          }
          await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
          continue;
        }
        throw err;
      }
      const errno = this.extractErrno(json);
      if (errno !== 0) {
        const errorMsg = BaiduNetdiskParser.readString(json, 'error_msg');
        if (BAIDU_UPLOADID_EXPIRED_ERRNOS.indexOf(errno) >= 0) {
          this.uploadHostCache.delete(uploadid);
          throw new BaiduUploadIdExpiredError(errno, errorMsg);
        }
        const lowerMsg = errorMsg.toLowerCase();
        if (lowerMsg.includes('uploadid')
          && (lowerMsg.includes('expired') || lowerMsg.includes('invalid') || lowerMsg.includes('not found'))) {
          this.uploadHostCache.delete(uploadid);
          throw new BaiduUploadIdExpiredError(errno, errorMsg);
        }
        if (SLICE_RETRYABLE_ERRNOS.indexOf(errno) >= 0 && attempt < 3) {
          attempt++;
          await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
          continue;
        }
        throw new BaiduApiError(errno, errorMsg);
      }
      const md5 = BaiduNetdiskParser.readString(json, 'md5').toLowerCase();
      if (md5.length === 0) {
        if (attempt < 3) {
          attempt++;
          await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
          continue;
        }
        throw new BaiduApiError(errno, 'superfile2 response missing md5');
      }
      // 分片 md5 校验：superfile2 返回 md5 应与预上传 block_list 对应值一致
      if (expectedMd5.length > 0 && md5 !== expectedMd5.toLowerCase()) {
        if (attempt < 3) {
          attempt++;
          hilog.warn(DOMAIN, TAG, 'slice md5 mismatch, partseq=%{public}s attempt=%{public}s',
            String(partSeq), String(attempt));
          await BaiduNetdiskClient.sleep(1000 * Math.pow(2, attempt - 1));
          continue;
        }
        throw new BaiduApiError(errno,
          `slice md5 mismatch, partseq=${partSeq}, expected=${expectedMd5}, actual=${md5}`);
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
    const remotePath = BaiduNetdiskClient.toRemotePath(path);
    // 同 precreate：method/access_token 走 URL query，业务参数走 form body
    const form = new rcp.Form({
      'path': remotePath,
      'size': String(size),
      'isdir': '0',
      'uploadid': uploadid,
      'rtype': String(BaiduNetdiskConstants.RTYPE_OVERWRITE),
      'block_list': JSON.stringify(blockList),
      'local_ctime': String(localCtime),
      'local_mtime': String(localMtime)
    });
    const json = await this.requestJson(BaiduNetdiskConstants.PAN_BASE, '/xpan/file', 'POST', {
      'method': 'create',
      'access_token': this.accessToken
    }, form);
    const errno = this.extractErrno(json);
    if (errno !== 0) {
      throw new BaiduApiError(errno, BaiduNetdiskParser.readString(json, 'error_msg'));
    }
    return BaiduNetdiskParser.parseFileMeta(json);
  }

  /**
   * 获取可用上传域名（获取上传域名文档：locateupload 动态获取，生产代码不得固定写死）
   * 结果按 uploadid 短期缓存（响应 expire 秒，缺省 60 秒），过期后重取；
   * locateupload 失败或未返回可用 HTTPS 域名时兜底默认域名 d.pcs.baidu.com（告警降级）
   * @param remotePath 远端绝对路径（应用目录内）
   * @param uploadid 预上传任务 id
   */
  public async getUploadHost(remotePath: string, uploadid: string): Promise<string> {
    const cached: BaiduUploadHostCache | undefined = this.uploadHostCache.get(uploadid);
    if (cached !== undefined && cached.expiresAt > Date.now()) {
      return cached.host;
    }
    let host = '';
    let ttlSec = UPLOAD_HOST_DEFAULT_TTL_SEC;
    try {
      const json = await this.requestJson(BaiduNetdiskConstants.PCS_BASE, '/pcs/file', 'GET', {
        'method': 'locateupload',
        'appid': BaiduNetdiskConstants.LOCATEUPLOAD_APPID,
        'access_token': this.accessToken,
        'path': remotePath,
        'uploadid': uploadid,
        'upload_version': '2.0'
      });
      const errno = this.extractErrno(json);
      if (errno !== 0) {
        hilog.warn(DOMAIN, TAG, 'locateupload errno=%{public}s, fallback to default host', String(errno));
      } else {
        host = this.pickUploadHost(json);
        const expire = BaiduNetdiskParser.readNumber(json, 'expire');
        if (expire > 0) {
          ttlSec = expire;
        }
        if (host.length === 0) {
          hilog.warn(DOMAIN, TAG, 'locateupload response has no https server, fallback to default host');
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'locateupload failed: %{public}s, fallback to default host',
        (error as Error).message);
    }
    if (host.length === 0) {
      host = BaiduNetdiskConstants.DEFAULT_UPLOAD_HOST;
    }
    if (this.uploadHostCache.size >= UPLOAD_HOST_CACHE_MAX_ENTRIES) {
      this.uploadHostCache.clear();
    }
    const entry: BaiduUploadHostCache = {
      host: host,
      expiresAt: Date.now() + ttlSec * 1000
    };
    this.uploadHostCache.set(uploadid, entry);
    hilog.info(DOMAIN, TAG, 'upload host for uploadid=%{public}s: %{public}s (ttl=%{public}s)',
      uploadid, host, String(ttlSec));
    return host;
  }

  /**
   * 从 locateupload 响应中选取 HTTPS 上传域名：
   * 依次取 servers / bak_servers 数组条目的 server 字段（缺协议时补 https://，
   * 文档要求保持协议与域名不变且使用 HTTPS），最后兜底 host 字段
   */
  private pickUploadHost(json: Record<string, Object>): string {
    const groups: string[] = ['servers', 'bak_servers'];
    for (let g = 0; g < groups.length; g++) {
      const servers = BaiduNetdiskParser.readObjectArray(json, groups[g]);
      for (let i = 0; i < servers.length; i++) {
        let server = BaiduNetdiskParser.readString(servers[i], 'server');
        if (server.length === 0) {
          continue;
        }
        if (!server.startsWith('http://') && !server.startsWith('https://')) {
          server = 'https://' + server;
        }
        if (server.startsWith('https://')) {
          return server;
        }
      }
    }
    const hostName = BaiduNetdiskParser.readString(json, 'host');
    return hostName.length === 0 ? '' : 'https://' + hostName;
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
   * @param onUploadProgress 上传进度回调（可选）：请求级 tracing onUploadProgress 透传（分片内字节级）
   */
  private async fetchJson(url: string, method: rcp.HttpMethod, form: rcp.Form | rcp.MultipartForm | undefined,
    timeoutMs: number,
    onUploadProgress?: (totalSize: number, transferredSize: number) => void): Promise<Record<string, Object>> {
    const session = rcp.createSession();
    try {
      const request = new rcp.Request(url, method);
      if (form !== undefined) {
        request.content = form;
      }
      const configuration: rcp.Configuration = {
        transfer: {
          timeout: { connectMs: 30000, transferMs: timeoutMs }
        }
      };
      if (onUploadProgress) {
        const progressCallback = onUploadProgress;
        configuration.tracing = {
          httpEventsHandler: {
            onUploadProgress: (totalSize: number, transferredSize: number): void => {
              progressCallback(totalSize, transferredSize);
            }
          }
        };
      }
      request.configuration = configuration;
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
