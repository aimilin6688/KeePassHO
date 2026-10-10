import { rcp } from '@kit.RemoteCommunicationKit';
import { util, xml } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError, request } from '@kit.BasicServicesKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ByteUtils } from 'kdbxweb';
import { CommonUtils, ResourceManager, StringUtils } from '../../common/utils';
import { CertValidationMode } from './WebDAVConfig';

const DOMAIN = 0x0000;
const TAG = 'WebDavClient';

// 连接超时（毫秒）：建连上限，同时作为连接检查类请求的整体上限；读取超时（transferMs）保持 rcp 默认 60s
const CONNECT_TIMEOUT_MS = 3000;

export interface DavResource {
  // URL地址
  href: string
  // 文件名称
  displayName: string,

  // 类型：collection - 文件夹， file - 文件
  type: string
  // 文件最后修改时间
  lastModified: string
  // 文件版本
  etag?: string
  // 文件类型
  contentType?: string
  // 文件大小
  contentLength?: number
}

export class WebDavResource implements DavResource {
  href: string = "";
  displayName: string = "";
  type: string = "";
  lastModified: string = "";
  etag: string | undefined = undefined;
  contentType?: string | undefined = undefined;
  contentLength?: number | undefined = undefined;
}

export class ResultInfo {
  success: boolean = true;
  statusCode: number = 200;
  message: string = "";
  headers: rcp.ResponseHeaders = {}
  data?: DavResource[] = [];
  body?: ArrayBuffer = undefined;
}

export interface WebDavClientOptions {
  url: string;
  username: string;
  password: string;
  /** SSL 证书验证模式 */
  certValidationMode?: CertValidationMode;
  /** 自定义 CA 证书内容（PEM 格式） */
  customCaCertContent?: string;
}


export class WebDavClient {
  public session: rcp.Session | null = null;
  public config: WebDavClientOptions | null = null;
  private static _instance: WebDavClient | null = null;

  public static getInstance() {
    if (WebDavClient._instance === null) {
      WebDavClient._instance = new WebDavClient();
    }
    return WebDavClient._instance;
  }

  constructor(options?: WebDavClientOptions) {
    if (options !== undefined) {
      this.updateOptions(options)
    }
  }

  /**
   * 构建安全配置
   * @returns rcp 安全配置
   */
  private buildSecurityConfig(): rcp.SecurityConfiguration {
    const mode = this.config?.certValidationMode || CertValidationMode.SYSTEM;

    let remoteValidation: 'system' | 'skip' | rcp.CertificateAuthority;

    switch (mode) {
      case CertValidationMode.SKIP:
        remoteValidation = 'skip';
        break;
      case CertValidationMode.CUSTOM_CA:
        if (this.config?.customCaCertContent) {
          remoteValidation = {
            content: this.config.customCaCertContent
          } as rcp.CertificateAuthority;
        } else {
          // 未提供证书时回退到系统验证
          remoteValidation = 'system';
        }
        break;
      case CertValidationMode.SYSTEM:
      default:
        remoteValidation = 'system';
        break;
    }

    return {
      remoteValidation: remoteValidation,
      serverAuthentication: {
        credential: {
          username: this.config?.username ?? '',
          password: this.config?.password ?? ''
        },
        authenticationType: "basic"
      }
    };
  }

  /**
   * 连接检查类请求（valid/exists/单文件元数据 PROPFIND）的请求级配置：
   * 建连与等待响应均以 CONNECT_TIMEOUT_MS 快速失败，不占用读取类请求（下载/上传/目录浏览）的 60s 读取超时
   */
  private buildCheckRequestConfiguration(): rcp.Configuration {
    return {
      transfer: {
        timeout: { connectMs: CONNECT_TIMEOUT_MS, transferMs: CONNECT_TIMEOUT_MS }
      },
      security: this.buildSecurityConfig()
    };
  }

  public updateOptions(options: WebDavClientOptions) {
    this.config = options;
    this.close();
    try {
      this.session = rcp.createSession({
        baseAddress: this.config.url,
        headers: { "Accept": "text/plain,application/xml" },
        requestConfiguration: {
          transfer: {
            timeout: { connectMs: CONNECT_TIMEOUT_MS }
          },
          security: this.buildSecurityConfig()
        }
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, "createSession error: %{public}s", error.message);
      CommonUtils.showToast(error.message);
    }
  }

  /**
   * 重新获取连接
   */
  public connection() {
    if (this.config != null) {
      this.updateOptions(this.config);
    }
  }

  /**
   * 关闭连接
   */
  public close() {
    this.session?.close();
  }

  /**
   * 发送请求
   * @param req
   * @returns
   */
  public async request(req: rcp.Request): Promise<ResultInfo> {
    const requestReturn: ResultInfo = new ResultInfo();
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
      hilog.debug(DOMAIN, TAG, "request return statusCode: %{public}d, headers: %{public}s", resp.statusCode, JSON.stringify(resp.headers));
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
      if (resp.statusCode === 405) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_file_exists"));
        requestReturn.success = false;
        return requestReturn;
      }
      if (resp.statusCode === 407) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_dir_not_exists"));
        requestReturn.success = false;
        return requestReturn;
      }
      if (resp.statusCode === 429) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_rate_limited"));
        requestReturn.success = false;
        return requestReturn;
      }
      if (resp.statusCode === 409) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_no_permission"));
        requestReturn.success = false;
        return requestReturn;
      }
      if (resp.statusCode === 500) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_server_error"));
        requestReturn.success = false;
        return requestReturn;
      }
      if (resp.statusCode === 507) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_server_full"));
        requestReturn.success = false;
        return requestReturn;
      }
      if (requestReturn.statusCode >= 200 && requestReturn.statusCode < 300) {
        // 正常
        requestReturn.statusCode = 200
        requestReturn.body = resp.body;
        requestReturn.success = true;
      } else {
        requestReturn.success = false;
        requestReturn.message = this.toErrorMsg(errorMessage) || '';
      }
    } catch (err) {
      let errMsg: string = err.message ?? errorMessage ?? err.data ?? "";
      hilog.error(DOMAIN, TAG, "request error: %{public}s:%{public}s,  %{public}s", err.code, errMsg)
      requestReturn.statusCode = 500
      requestReturn.success = false;
      if (err.code === 1007900028) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_request_timeout"));
      } else {
        requestReturn.message = `${err.code}:${errMsg}`;
      }
    }
    return requestReturn;
  }

  private toErrorMsg(errorMessage?: string): string | undefined {
    if (!errorMessage) {
      return errorMessage;
    }
    try {
      return StringUtils.getTagContent(errorMessage, "s:exception") + ": " + StringUtils.getTagContent(errorMessage, "s:message");
    } catch (e) {
      return errorMessage;
    }
  }

  /**
   * 验证服务器和验证方式是否可用
   * @returns
   */
  public async valid(): Promise<ResultInfo> {
    const req = new rcp.Request('/', "PROPFIND", { "Depth": "0" }, undefined, {}, {}, this.buildCheckRequestConfiguration());
    return await this.request(req);
  }

  /**
   * 读取目录下的所有文件夹
   * filter: 0: 不过滤，1: 只返回文件夹，2: 只返回文件
   * quickCheck: true 时为连接检查类请求（单文件元数据），按 CONNECT_TIMEOUT_MS 快速失败
   * @param path
   * @returns
   */
  public async list(path: string = '/', filter: number = 0, quickCheck: boolean = false): Promise<ResultInfo> {
    const body = `<?xml version="1.0"?>
      <d:propfind xmlns:d="DAV:">
        <d:prop>
          <d:resourcetype/>
          <d:displayname/>
          <d:getcontentlength/>
          <d:getlastmodified/>
          <d:getetag/>
        </d:prop>
      </d:propfind>`;
    const req = new rcp.Request(path, "PROPFIND", { "Depth": "1" }, body, {}, {}, quickCheck ? this.buildCheckRequestConfiguration() : undefined);
    const rr = await this.request(req);
    if (rr.statusCode === 200) {
      const items = this.parseXml(rr.body ? ByteUtils.bytesToString(rr.body) : "");
      if (items.length === 0) {
        rr.data = items;
      } else {
        const dirs: WebDavResource[] = [];
        for (let i = 0; i < items.length; i++) {
          let item = items[i];
          if (filter == 0) {
            dirs.push(item);
            continue;
          }
          // 文件夹
          if (item.type === 'collection' && filter === 1) {
            dirs.push(item);
            continue;
          }
          // 文件
          if (item.type === 'file' && filter === 2) {
            dirs.push(item);
          }
        }
        rr.data = dirs;
      }
    } else {
      hilog.info(DOMAIN, TAG, `get dir, return : ${JSON.stringify(rr)}`);
    }
    return rr;
  }

  /**
   * 判断路径是否存在
   * 0: 不存在
   * 1: 存在
   * 2: 存在，但大小不一致
   * @param path
   * @param size
   * @returns
   */
  public async exists(path: string): Promise<boolean> {
    hilog.info(DOMAIN, TAG, `Query path exists: ${path}`);
    const req = new rcp.Request(path, "PROPFIND", { "Depth": "0" }, undefined, {}, {}, this.buildCheckRequestConfiguration());
    const rr = await this.request(req);
    // 不存在
    if (!rr.success) {
      hilog.info(DOMAIN, TAG, `Query path exists error，code: ${rr.statusCode}, msg: ${rr.message}`)
      return false;
    }
    return true;
  }

  /**
   * 创建文件夹
   * @param path
   * @returns
   */
  public async mkDir(path: string): Promise<ResultInfo> {
    if (!path.endsWith('/')) {
      path = path + '/';
    }
    // 查询是否存在
    const exists = await this.exists(path);
    if (exists) {
      const requestReturn: ResultInfo = new ResultInfo();
      requestReturn.success = true;
      requestReturn.statusCode = 200
      requestReturn.message = "";
      return requestReturn;
    }
    const req = new rcp.Request(path, "MKCOL");
    return await this.request(req);
  }

  // 删除文件
  public async delete(path: string): Promise<ResultInfo> {
    const req = new rcp.Request(path, "DELETE");
    return await this.request(req);
  }

  /**
   * 获取文件内容
   * @param path 路径
   * @returns 结果
   */
  public async get(path: string): Promise<ResultInfo> {
    const req = new rcp.Request(path, "GET", { "Depth": "0" });
    const rr = await this.request(req);
    if (!rr.success) {
      return Promise.reject(rr);
    }
    return rr;
  }

  /**
   * 流式下载文件到本地路径（rcp.downloadToFile，响应体不驻留内存）
   * @param path 远端路径
   * @param destPath 本地目标路径
   * @param progressCallback 下载进度回调（可选）：rcp onDownloadProgress (totalSize, transferredSize) 透传；
   *        无回调时走共享 session；有回调时创建一次性 session（downloadToFile 无请求级配置入口，
   *        进度只能经 session 级 tracing 下发），复用 baseAddress/鉴权/超时配置，用后即关
   * @returns 结果（含 statusCode/headers，body 为空）
   */
  public async downloadToFile(path: string, destPath: string,
    progressCallback?: (totalSize: number, transferredSize: number) => void): Promise<ResultInfo> {
    const requestReturn: ResultInfo = new ResultInfo();
    if (!this.session || !this.config) {
      requestReturn.success = false;
      requestReturn.statusCode = 500;
      requestReturn.message = ResourceManager.getString($r("app.string.webdav_not_init"));
      return requestReturn;
    }
    if (progressCallback) {
      // const 快照规避闭包内可变参数的窄化丢失（ArkTS 流分析）
      const cb: (totalSize: number, transferredSize: number) => void = progressCallback;
      let progressSession: rcp.Session | null = null;
      try {
        progressSession = rcp.createSession({
          baseAddress: this.config.url,
          headers: { "Accept": "text/plain,application/xml" },
          requestConfiguration: {
            transfer: {
              timeout: { connectMs: CONNECT_TIMEOUT_MS }
            },
            security: this.buildSecurityConfig(),
            tracing: {
              httpEventsHandler: {
                onDownloadProgress: (totalSize: number, transferredSize: number): void => {
                  cb(totalSize, transferredSize);
                }
              }
            }
          }
        });
        const resp = await progressSession.downloadToFile(path, { kind: 'file', file: destPath } as rcp.DownloadToFile);
        this.fillDownloadResult(requestReturn, resp);
        return requestReturn;
      } catch (error) {
        hilog.error(DOMAIN, TAG, "downloadToFile error: %{public}s", error.message);
        requestReturn.success = false;
        requestReturn.statusCode = 500;
        requestReturn.message = error.message;
        return requestReturn;
      } finally {
        progressSession?.close();
      }
    }
    try {
      const resp = await this.session.downloadToFile(path, { kind: 'file', file: destPath } as rcp.DownloadToFile);
      this.fillDownloadResult(requestReturn, resp);
      return requestReturn;
    } catch (error) {
      hilog.error(DOMAIN, TAG, "downloadToFile error: %{public}s", error.message);
      requestReturn.success = false;
      requestReturn.statusCode = 500;
      requestReturn.message = error.message;
      return requestReturn;
    }
  }

  /**
   * 填充下载响应结果（downloadToFile 两个分支共用）
   */
  private fillDownloadResult(requestReturn: ResultInfo, resp: rcp.Response | undefined): void {
    requestReturn.statusCode = resp?.statusCode ?? 0;
    requestReturn.headers = resp?.headers ?? {};
    requestReturn.success = resp !== undefined && resp.statusCode >= 200 && resp.statusCode < 300;
    if (!requestReturn.success) {
      requestReturn.message = `Download failed: ${requestReturn.statusCode}`;
    }
  }

  /**
   * 认证头字符串
   * @returns
   */
  private getBase64Auth(): string {
    return CommonUtils.base64Encode(`${this.config?.username}:${this.config?.password}`)
  }

  /**
   * 上传文件
   * @param remoteUri
   * @param fileBuffer
   * @param progressCallback
   * @returns
   */
  async upload(remoteUri: string, fileBuffer: ArrayBuffer,
    progressCallback?: (totalSize: number, transferredSize: number) => void): Promise<ResultInfo> {
    // 读取文件
    const customHttpEventsHandler: rcp.HttpEventsHandler = {
      onUploadProgress: (totalSize: number, transferredSize: number) => {
        if (progressCallback) {
          progressCallback(totalSize, transferredSize);
        }
      }
    };
    hilog.debug(DOMAIN, TAG, `File upload url：${remoteUri}, size: ${fileBuffer.byteLength}`)
    const req = new rcp.Request(remoteUri, "PUT", {}, fileBuffer, {}, {},
      { tracing: { httpEventsHandler: customHttpEventsHandler } });
    const rr = await this.request(req);
    if (!rr.success) {
      hilog.error(DOMAIN, TAG, "File upload failed, url: %{public}s, statusCode: %{public}d, message: %{public}s", remoteUri, rr.statusCode, rr.message);
      return Promise.reject(rr);
    }
    hilog.info(DOMAIN, TAG, "File upload success:" + (remoteUri) + ', ' + rr.statusCode);
    return rr
  }

  /**
   * 流式上传本地文件（S7：rcp.Request + UploadFromFile，请求体不驻内存）
   * PUT 方法 + Basic 认证头；内存窗口 = rcp 内部分块，与文件大小解耦（解除 CP-UP 100MB 约束）
   * 进度说明：tracing 的 onUploadProgress 对文件请求体不触发，改用 rcp.ReadFile 适配器——
   * RCP 按内部块大小回调 read 拉取数据，每次拉取即上报真实已读字节（transferred 单调递增至 totalSize）
   * @param remoteUri 远端路径（相对 session baseAddress）
   * @param srcPath 本地源文件路径
   * @param progressCallback 上传进度回调（可选）：(totalSize, transferredSize)
   * @returns
   */
  async uploadFromFile(remoteUri: string, srcPath: string,
    progressCallback?: (totalSize: number, transferredSize: number) => void): Promise<ResultInfo> {
    const headers: Record<string, string> = {};
    headers['Authorization'] = 'Basic ' + this.getBase64Auth();
    headers['Content-Type'] = 'application/octet-stream';

    let file: fs.File | null = null;
    let uploadedBytes: number = 0;
    let totalBytes: number = 0;
    let srcEof: boolean = false;
    const readFileAdapter: rcp.ReadFile = {
      read: async (buffer: ArrayBuffer): Promise<number> => {
        if (srcEof || file === null) {
          return 0;
        }
        const readBytes: number = fs.readSync(file.fd, buffer);
        if (readBytes <= 0) {
          srcEof = true;
          return 0;
        }
        uploadedBytes += readBytes;
        if (progressCallback) {
          progressCallback(totalBytes, uploadedBytes);
        }
        return readBytes;
      }
    };

    try {
      totalBytes = fs.statSync(srcPath).size;
      file = fs.openSync(srcPath, fs.OpenMode.READ_ONLY);
      const req = new rcp.Request(remoteUri, 'PUT', headers, new rcp.UploadFromFile(readFileAdapter));
      const rr = await this.request(req);
      if (!rr.success) {
        hilog.error(DOMAIN, TAG, "uploadFromFile failed, url: %{public}s, statusCode: %{public}d, message: %{public}s",
          remoteUri, rr.statusCode, rr.message);
        return Promise.reject(rr);
      }
      hilog.info(DOMAIN, TAG, "uploadFromFile success: %{public}s, %{public}d", remoteUri, rr.statusCode);
      return rr;
    } finally {
      if (file !== null) {
        try {
          fs.closeSync(file);
        } catch {
          // 关闭失败忽略
        }
      }
    }
  }


  /**
   * 使用系统上传方上传
   * @param context 上下文环境
   * @param name 文件名称
   * @param remoteUri 远端Uri地址
   * @param filePath 文件路径
   * @param progressCallback 上传进度回调
   * @returns
   */
  public uploadByFilePath(context: Context, name: string, remoteUri: string, filePath: string,
    progressCallback: (transferredSize: number) => void): Promise<ResultInfo> {
    return new Promise(async (resolve) => {
      filePath = filePath.replace(context.cacheDir, 'internal://cache')
      // 上传任务配置项
      let files: Array<request.File> = [
        {
          filename: name,
          name: 'file',
          uri: filePath,
          type: CommonUtils.getMimeTypeFromExtension(name)
        }
      ]
      let data: Array<request.RequestData> = [];
      let uploadConfig: request.UploadConfig = {
        url: remoteUri,
        header: {
          'Authorization': 'Basic ' + this.getBase64Auth()
        },
        method: 'PUT',
        files: files,
        data: data
      }

      // 将本地应用文件上传至网络服务器
      try {
        const uploadTask: request.UploadTask = await request.uploadFile(context, uploadConfig);
        uploadTask.on('complete', (taskStates: Array<request.TaskState>) => {
          for (let i = 0; i < taskStates.length; i++) {
            let rr: ResultInfo = {
              statusCode: 500,
              success: false,
              message: "",
              headers: {}
            };
            if (taskStates[i].responseCode === 0) {
              rr.success = true;
              rr.statusCode = 200;
            } else {
              rr.success = false;
              rr.statusCode = taskStates[i].responseCode;
              rr.message = taskStates[i].message;
            }
            uploadTask.delete().then()
            resolve(rr);
          }
        });
        uploadTask.on("progress", (uploadedSize: number, totalSize: number) => {
          progressCallback(uploadedSize);
        })
      } catch (error) {
        let err: BusinessError = error as BusinessError;
        hilog.error(DOMAIN, TAG, `Invoke uploadFile failed, code is ${err.code}, message is ${err.message}`);
        let rr: ResultInfo = {
          statusCode: err.code,
          success: false,
          message: err.message,
          headers: {}
        };
        resolve(rr);
      }
    });
  }


  /**
   * 解析dav xml
   * @param xmlStr
   * @returns
   */
  private parseXml(xmlStr: string | null): WebDavResource[] {
    let textEncoder: util.TextEncoder = new util.TextEncoder();
    let arrBuffer: Uint8Array = textEncoder.encodeInto(xmlStr); // 对数据编码，防止包含中文字符乱码
    let that: xml.XmlPullParser = new xml.XmlPullParser(arrBuffer.buffer as object as ArrayBuffer, 'UTF-8');
    let items: WebDavResource[] = []
    let curItem: WebDavResource = new WebDavResource()
    let preText: string = "";

    let options: xml.ParseOptions = {
      supportDoctype: true,
      ignoreNameSpace: true,
      tokenValueCallbackFunction: (eventType: xml.EventType, value: xml.ParseInfo) => {
        // 节点匹配采用"最后一个冒号后的本地名再小写"，兼容 D:/d:/lp1:/无前缀等任意命名空间前缀
        let nodeName = WebDavClient.toLocalName(value.getName()).toLowerCase();
        if (eventType == xml.EventType.START_DOCUMENT || eventType == xml.EventType.END_DOCUMENT) {
          return true;
        }
        if (eventType == xml.EventType.START_TAG) {
          // 进入新元素时清空文本缓存：遇到自闭合空元素（如 Apache mod_dav 的 <g0:displayname/>）时，
          // END_TAG 处读到的是空串而非上一元素残留文本（如 status "HTTP/1.1 200 OK"），避免名称/大小被污染
          preText = "";
          if (nodeName === "response") {
            curItem = new WebDavResource();
            return true;
          }
        }
        if (eventType == xml.EventType.TEXT) {
          preText = value.getText();
          return true;
        }
        if (eventType == xml.EventType.END_TAG) {
          if (nodeName === "response") {
            if (curItem.type === "") {
              curItem.type = "file"
            }
            // displayName 缺失时以 href 末段解码兜底
            if (!curItem.displayName) {
              curItem.displayName = WebDavClient.displayNameFromHref(curItem.href);
            }
            items.push(curItem)
            return true;
          }
          if (nodeName === "href") {
            curItem.href = preText;
            return true;
          }
          if (nodeName === "displayname") {
            // 服务器返回空 displayname（如 Apache 对未请求属性返回空元素/404 propstat）时不采纳，
            // 保持空串以便 response 结束时走 href 末段兜底
            const name: string = preText.trim();
            if (name) {
              curItem.displayName = name;
            }
            return true;
          }
          if (nodeName === "collection") {
            curItem.type = "collection";
            return true;
          }
          if (nodeName === "getcontentlength") {
            // 集合（目录）的 getcontentlength 为空元素，解析失败时保持 undefined，避免 NaN 透传到 UI
            const length: number = parseInt(preText);
            if (!Number.isNaN(length)) {
              curItem.contentLength = length;
            }
            return true;
          }
          if (nodeName === "getlastmodified") {
            curItem.lastModified = preText;
            return true;
          }
          if (nodeName === "getetag") {
            curItem.etag = preText;
            return true;
          }
          if (nodeName === "getcontenttype") {
            curItem.contentType = preText;
            return true;
          }
        }
        return true;
      },
    };
    that.parseXml(options);
    return items;
  }

  /**
   * 取节点名的本地名（最后一个冒号之后的部分），无前缀时原样返回
   */
  private static toLocalName(nodeName: string): string {
    const colonIndex: number = nodeName.lastIndexOf(':');
    return colonIndex >= 0 ? nodeName.substring(colonIndex + 1) : nodeName;
  }

  /**
   * 以 href 末段解码作为显示名兜底
   */
  private static displayNameFromHref(href: string): string {
    if (!href) {
      return '';
    }
    const trimmed: string = href.endsWith('/') ? href.substring(0, href.length - 1) : href;
    const lastSlashIndex: number = trimmed.lastIndexOf('/');
    const lastSegment: string = lastSlashIndex >= 0 ? trimmed.substring(lastSlashIndex + 1) : trimmed;
    if (!lastSegment) {
      return '';
    }
    try {
      return decodeURIComponent(lastSegment);
    } catch (error) {
      // 含非法百分号序列时原样返回
      return lastSegment;
    }
  }
}