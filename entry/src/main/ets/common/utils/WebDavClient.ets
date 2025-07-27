import { rcp } from "@kit.RemoteCommunicationKit";
import { xml, util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from "./CommonUtils";
import { BusinessError, request } from "@kit.BasicServicesKit";
import ResourceManager from "../utils/ResourceManager";
import { ByteUtils } from "kdbxweb";

const DOMAIN = 0x0000;
const TAG = 'WebDavClient';

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

  public updateOptions(options: WebDavClientOptions) {
    this.config = options;
    this.close();
    this.session = rcp.createSession({
      baseAddress: this.config.url,
      headers: { "Accept": "text/plain,application/xml" },
      requestConfiguration: {
        transfer: {
          timeout: { connectMs: 3000 }
        },
        security: {
          serverAuthentication: {
            credential: {
              username: this.config.username,
              password: this.config.password
            },
            authenticationType: "basic"
          }
        }
      }
    });
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
      hilog.info(DOMAIN, TAG, "request return statusCode: %{public}d, headers: %{public}s", resp.statusCode,
        JSON.stringify(resp.headers));
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
        requestReturn.message = errorMessage ?? "";
      }
    } catch (err) {
      let errMsg: string = err.message ?? errorMessage ?? err.data ?? "";
      hilog.error(DOMAIN, TAG, "request error: %{public}s:%{public}s,  %{public}s", err.code, errMsg)
      requestReturn.statusCode = 500
      requestReturn.success = false;
      if (err.code === 1007900028) {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_request_timeout"));
      } else {
        requestReturn.message = ResourceManager.getString($r("app.string.webdav_error"), err.code ?? "", errMsg);
      }
    }
    return requestReturn;
  }

  /**
   * 验证服务器和验证方式是否可用
   * @returns
   */
  public async valid(): Promise<ResultInfo> {
    const req = new rcp.Request('/', "PROPFIND", { "Depth": "0" });
    return await this.request(req);
  }

  /**
   * 读取目录下的所有文件夹
   * filter: 0: 不过滤，1: 只返回文件夹，2: 只返回文件
   * @param path
   * @returns
   */
  public async list(path: string = '/', filter: number = 0): Promise<ResultInfo> {
    const body = `<?xml version="1.0"?>
      <d:propfind xmlns:d="DAV:">
        <d:prop>
          <d:resourcetype/>
          <d:displayname/>
          <d:getcontentlength/>
          <d:getlastmodified/>
        </d:prop>
      </d:propfind>`;
    const req = new rcp.Request(path, "PROPFIND", { "Depth": "1" }, body);
    const rr = await this.request(req);
    if (rr.statusCode === 200) {
      const items = this.parseXml(rr.body ? ByteUtils.bytesToString(rr.body) : "");
      if (items.length === 0) {
        rr.data = items;
      } else {
        const dirs: WebDavResource[] = [];
        for (let item of items) {
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
    const req = new rcp.Request(path, "PROPFIND", { "Depth": "0" });
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
    hilog.info(DOMAIN, TAG, `File upload url：${remoteUri}, size: ${fileBuffer.byteLength}`)
    const req = new rcp.Request(remoteUri, "PUT", {}, fileBuffer, {}, {},
      { tracing: { httpEventsHandler: customHttpEventsHandler } });
    const rr = await this.request(req);
    hilog.info(DOMAIN, TAG, "File upload success:" + (remoteUri) + ', ' + rr.statusCode);
    return rr
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
  parseXml(xmlStr: string | null): WebDavResource[] {
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
        let nodeName = value.getName().toLowerCase();
        if (eventType == xml.EventType.START_DOCUMENT || eventType == xml.EventType.END_DOCUMENT) {
          return true;
        }
        if (eventType == xml.EventType.START_TAG) {
          if (nodeName === "d:response") {
            curItem = new WebDavResource();
            return true;
          }
        }
        if (eventType == xml.EventType.TEXT) {
          preText = value.getText();
          return true;
        }
        if (eventType == xml.EventType.END_TAG) {
          if (nodeName === "d:response") {
            if (curItem.type === "") {
              curItem.type = "file"
            }
            items.push(curItem)
            return true;
          }
          if (nodeName === "d:href") {
            curItem.href = preText;
            return true;
          }
          if (nodeName === "d:displayname") {
            curItem.displayName = preText;
            return true;
          }
          if (nodeName === "d:collection") {
            curItem.type = "collection";
            return true;
          }
          if (nodeName === "d:getcontentlength") {
            curItem.contentLength = parseInt(preText);
            return true;
          }
          if (nodeName === "d:getlastmodified") {
            curItem.lastModified = preText;
            return true;
          }
          if (nodeName === "d:getetag") {
            curItem.etag = preText;
            return true;
          }
          if (nodeName === "d:getcontenttype") {
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
}