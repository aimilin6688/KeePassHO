import { rcp } from '@kit.RemoteCommunicationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { util } from '@kit.ArkTS';
import { ByteUtils } from 'kdbxweb';
import { S3Bucket, S3Object, S3Result, MultipartUploadInit, UploadedPart, MultipartUploadProgress, ProgressCallback } from './S3Types';
import { S3SignatureV4 } from './S3SignatureV4';
import { S3XmlParser } from './S3XmlParser';
import { S3MultipartConfig } from './S3Config';

const DOMAIN = 0x0000;
const TAG = 'S3Client';

/**
 * 全局会话池，用于复用 rcp session
 * 避免频繁创建和销毁 session 导致资源耗尽
 */
class SessionPool {
  private static instance: SessionPool | null = null;
  private session: rcp.Session | null = null;
  private refCount: number = 0;
  private timeout: number = 30000;

  private constructor() {}

  public static getInstance(): SessionPool {
    if (!SessionPool.instance) {
      SessionPool.instance = new SessionPool();
    }
    return SessionPool.instance;
  }

  public acquire(timeout: number): rcp.Session | null {
    if (!this.session) {
      try {
        this.session = rcp.createSession({
          requestConfiguration: {
            transfer: {
              timeout: { connectMs: timeout }
            }
          }
        });
        this.timeout = timeout;
        hilog.info(DOMAIN, TAG, 'SessionPool: created session id=%{public}s', this.session?.id);
      } catch (error) {
        const err = error as Error;
        hilog.error(DOMAIN, TAG, 'SessionPool: failed to create session: %{public}s', err.message);
        return null;
      }
    }
    this.refCount++;
    return this.session;
  }

  public release(): void {
    this.refCount--;
    if (this.refCount <= 0) {
      this.refCount = 0;
    }
  }

  public forceClose(): void {
    if (this.session) {
      try {
        this.session.close();
        hilog.info(DOMAIN, TAG, 'SessionPool: closed session');
      } catch (error) {
        // ignore
      }
      this.session = null;
      this.refCount = 0;
    }
  }
}

interface ParsedUrl {
  protocol: string;
  host: string;
  port: string;
  path: string;
}

/**
 * S3 客户端配置选项接口
 * 注意：由于 ArkTS 不支持结构化类型，此接口仅用于类型文档，
 * 实际使用时应使用 S3ClientOptionsImpl 类
 */
export interface S3ClientOptions {
  endpoint: string;
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  pathStyle: boolean;
  timeout: number;
}

/**
 * S3 客户端配置选项实现类
 * ArkTS 要求使用类而非对象字面量实现接口
 */
export class S3ClientOptionsImpl {
  endpoint: string = '';
  accessKeyId: string = '';
  secretAccessKey: string = '';
  region: string = '';
  pathStyle: boolean = false;
  timeout: number = 30000;

  constructor(
    endpoint: string,
    accessKeyId: string,
    secretAccessKey: string,
    region: string,
    pathStyle: boolean,
    timeout: number
  ) {
    this.endpoint = endpoint;
    this.accessKeyId = accessKeyId;
    this.secretAccessKey = secretAccessKey;
    this.region = region;
    this.pathStyle = pathStyle;
    this.timeout = timeout;
  }
}

/**
 * S3 HTTP 客户端
 */
export class S3Client {
  private options: S3ClientOptionsImpl;
  private signer: S3SignatureV4;
  private parsedEndpoint: ParsedUrl;
  private sessionPool: SessionPool;

  constructor(options: S3ClientOptionsImpl) {
    this.options = options;
    this.signer = new S3SignatureV4(
      options.accessKeyId,
      options.secretAccessKey,
      options.region
    );
    this.parsedEndpoint = this.parseUrl(options.endpoint);
    this.sessionPool = SessionPool.getInstance();
  }

  private getSession(): rcp.Session | null {
    return this.sessionPool.acquire(this.options.timeout);
  }

  private parseUrl(url: string): ParsedUrl {
    let protocol: string = 'https';
    let host: string = url;
    let port: string = '';
    let path: string = '/';

    // 提取协议
    if (url.startsWith('https://')) {
      protocol = 'https';
      host = url.substring(8);
    } else if (url.startsWith('http://')) {
      protocol = 'http';
      host = url.substring(7);
    }

    // 提取路径
    const slashIndex: number = host.indexOf('/');
    if (slashIndex > 0) {
      path = host.substring(slashIndex);
      host = host.substring(0, slashIndex);
    }

    // 提取端口
    const colonIndex: number = host.indexOf(':');
    if (colonIndex > 0) {
      port = host.substring(colonIndex + 1);
      host = host.substring(0, colonIndex);
    }

    const result: ParsedUrl = {
      protocol: protocol,
      host: host,
      port: port,
      path: path
    };
    return result;
  }

  private buildUrl(bucket: string, key: string): string {
    if (this.options.pathStyle) {
      if (key && key.length > 0) {
        return `${this.options.endpoint}/${bucket}/${key}`;
      } else {
        return `${this.options.endpoint}/${bucket}`;
      }
    } else {
      if (key && key.length > 0) {
        return `${this.parsedEndpoint.protocol}://${bucket}.${this.parsedEndpoint.host}/${key}`;
      } else {
        return `${this.parsedEndpoint.protocol}://${bucket}.${this.parsedEndpoint.host}/`;
      }
    }
  }

  private headersToRecord(headers: Map<string, string>): Record<string, string> {
    const record: Record<string, string> = {};
    headers.forEach((value: string, key: string) => {
      record[key] = value;
    });
    return record;
  }

  private async handleResponse<T>(response: rcp.Response | undefined, parseData?: (body: ArrayBuffer) => T): Promise<S3Result<T>> {
    if (!response) {
      const result: S3Result<T> = {
        success: false,
        statusCode: 500,
        message: 'No response from server'
      };
      return result;
    }

    const result: S3Result<T> = {
      success: response.statusCode >= 200 && response.statusCode < 300,
      statusCode: response.statusCode,
      headers: response.headers as Record<string, string>
    };

    if (result.success) {
      if (parseData && response.body) {
        result.data = parseData(response.body);
      }
    } else {
      if (response.body) {
        try {
          const xmlStr = ByteUtils.bytesToString(response.body);
          console.error(`[S3Client] Error response (${xmlStr.length} bytes): ${xmlStr}`);
          const error = S3XmlParser.parseError(xmlStr);
          result.message = error.message || `HTTP ${response.statusCode}`;
          hilog.error(DOMAIN, TAG, 'S3 error: code=%{public}s, message=%{public}s', error.code, error.message);
        } catch {
          result.message = `HTTP ${response.statusCode}`;
        }
      }
    }

    return result;
  }

  public close(): void {
    this.sessionPool.release();
  }

  public async listBuckets(): Promise<S3Result<S3Bucket[]>> {
    try {
      const headers = await this.signer.signListBuckets(this.options.endpoint, this.parsedEndpoint.host);
      const url: string = `${this.parsedEndpoint.protocol}://${this.parsedEndpoint.host}/`;
      const request = new rcp.Request(url, 'GET', this.headersToRecord(headers));

      const session = this.getSession();
      const response = await session?.fetch(request);

      return this.handleResponse<S3Bucket[]>(response, (body: ArrayBuffer) => {
        const xmlStr = ByteUtils.bytesToString(body);
        return S3XmlParser.parseListBuckets(xmlStr);
      });
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'listBuckets error: %{public}s', err.message);
      const result: S3Result<S3Bucket[]> = {
        success: false,
        statusCode: 500,
        message: err.message
      };
      return result;
    }
  }

  public async headBucket(bucket: string): Promise<boolean> {
    try {
      const headers = await this.signer.signRequest(
        'HEAD',
        this.options.endpoint,
        bucket,
        '',
        this.options.pathStyle
      );
      const url = this.buildUrl(bucket, '');
      const request = new rcp.Request(url, 'HEAD', this.headersToRecord(headers));
      const response = await this.getSession()?.fetch(request);
      return response?.statusCode === 200;
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'headBucket error: %{public}s', err.message);
      return false;
    }
  }

  public async listObjects(bucket: string, prefix?: string): Promise<S3Result<S3Object[]>> {
    try {
      let queryString: string;
      if (prefix) {
        queryString = 'delimiter=%2F&prefix=' + encodeURIComponent(prefix);
      } else {
        queryString = 'delimiter=%2F';
      }

      const headers = await this.signer.signRequest(
        'GET',
        this.options.endpoint,
        bucket,
        '',
        this.options.pathStyle,
        new Map(),
        null,
        queryString
      );

      const url = this.buildUrl(bucket, '') + '?' + queryString;
      const request = new rcp.Request(url, 'GET', this.headersToRecord(headers));
      const response = await this.getSession()?.fetch(request);

      return this.handleResponse<S3Object[]>(response, (body: ArrayBuffer) => {
        const xmlStr = ByteUtils.bytesToString(body);
        return S3XmlParser.parseListObjects(xmlStr);
      });
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'listObjects error: %{public}s', err.message);
      const result: S3Result<S3Object[]> = {
        success: false,
        statusCode: 500,
        message: err.message
      };
      return result;
    }
  }

  public async getObject(bucket: string, key: string): Promise<S3Result<ArrayBuffer>> {
    try {
      const headers = await this.signer.signRequest(
        'GET',
        this.options.endpoint,
        bucket,
        key,
        this.options.pathStyle
      );

      const url = this.buildUrl(bucket, key);
      const request = new rcp.Request(url, 'GET', this.headersToRecord(headers));
      const response = await this.getSession()?.fetch(request);

      if (response && response.statusCode >= 200 && response.statusCode < 300) {
        const result: S3Result<ArrayBuffer> = {
          success: true,
          statusCode: response.statusCode,
          data: response.body,
          headers: response.headers as Record<string, string>
        };
        return result;
      }

      return this.handleResponse<ArrayBuffer>(response);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'getObject error: %{public}s', err.message);
      const result: S3Result<ArrayBuffer> = {
        success: false,
        statusCode: 500,
        message: err.message
      };
      return result;
    }
  }

  public async putObject(bucket: string, key: string, data: ArrayBuffer): Promise<S3Result<void>> {
    try {
      const fileSizeMB = (data.byteLength / (1024 * 1024)).toFixed(2);
      hilog.info(DOMAIN, TAG, 'putObject: bucket=%{public}s, key=%{public}s, size=%{public}s MB',
        bucket, key, fileSizeMB);

      const headers = await this.signer.signRequest(
        'PUT',
        this.options.endpoint,
        bucket,
        key,
        this.options.pathStyle,
        new Map([['content-type', 'application/octet-stream']]),
        data
      );

      const url = this.buildUrl(bucket, key);
      const request = new rcp.Request(url, 'PUT', this.headersToRecord(headers), data);
      const response = await this.getSession()?.fetch(request);

      if (response && response.statusCode >= 200 && response.statusCode < 300) {
        hilog.info(DOMAIN, TAG, 'putObject: upload successful, statusCode=%{public}d', response.statusCode);
      } else {
        hilog.error(DOMAIN, TAG, 'putObject: upload failed, statusCode=%{public}d', response?.statusCode || 0);
      }

      return this.handleResponse<void>(response);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'putObject error: %{public}s', err.message);
      const result: S3Result<void> = {
        success: false,
        statusCode: 500,
        message: err.message
      };
      return result;
    }
  }

  public async deleteObject(bucket: string, key: string): Promise<S3Result<void>> {
    try {
      const headers = await this.signer.signRequest(
        'DELETE',
        this.options.endpoint,
        bucket,
        key,
        this.options.pathStyle
      );

      const url = this.buildUrl(bucket, key);
      const request = new rcp.Request(url, 'DELETE', this.headersToRecord(headers));
      const response = await this.getSession()?.fetch(request);

      return this.handleResponse<void>(response);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'deleteObject error: %{public}s', err.message);
      const result: S3Result<void> = {
        success: false,
        statusCode: 500,
        message: err.message
      };
      return result;
    }
  }

  public async headObject(bucket: string, key: string): Promise<S3Result<S3Object>> {
    try {
      const headers = await this.signer.signRequest(
        'HEAD',
        this.options.endpoint,
        bucket,
        key,
        this.options.pathStyle
      );

      const url = this.buildUrl(bucket, key);
      const request = new rcp.Request(url, 'HEAD', this.headersToRecord(headers));
      const response = await this.getSession()?.fetch(request);

      if (response && response.statusCode === 200) {
        const respHeaders = response.headers as Record<string, string>;
        const obj: S3Object = {
          key: key,
          size: parseInt(respHeaders['content-length'] || '0', 10),
          lastModified: new Date(respHeaders['last-modified'] || '').getTime(),
          etag: (respHeaders['etag'] || '').replace(/"/g, '')
        };
        const result: S3Result<S3Object> = {
          success: true,
          statusCode: 200,
          data: obj
        };
        return result;
      }

      return this.handleResponse<S3Object>(response);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'headObject error: %{public}s', err.message);
      const result: S3Result<S3Object> = {
        success: false,
        statusCode: 500,
        message: err.message
      };
      return result;
    }
  }

  public async testConnection(): Promise<S3Result<void>> {
    const bucketResult = await this.listBuckets();
    if (bucketResult.success) {
      const result: S3Result<void> = { success: true, statusCode: 200 };
      return result;
    }
    const result: S3Result<void> = {
      success: false,
      statusCode: bucketResult.statusCode,
      message: bucketResult.message
    };
    return result;
  }

  /**
   * 初始化 Multipart Upload
   * @param bucket 存储桶名称
   * @param key 对象键
   * @returns S3Result<MultipartUploadInit>
   */
  public async createMultipartUpload(
    bucket: string,
    key: string
  ): Promise<S3Result<MultipartUploadInit>> {
    try {
      // 查询字符串: ?uploads
      // 注意：签名时查询字符串需要包含 '=' 符号，即 'uploads='
      const queryString = 'uploads=';

      const headers = await this.signer.signRequest(
        'POST',
        this.options.endpoint,
        bucket,
        key,
        this.options.pathStyle,
        new Map(),
        null,
        queryString
      );

      // URL 仍然使用 ?uploads（无等号）
      const url = this.buildUrl(bucket, key) + '?uploads';
      const request = new rcp.Request(url, 'POST', this.headersToRecord(headers));
      const response = await this.getSession()?.fetch(request);

      if (response && response.statusCode >= 200 && response.statusCode < 300 && response.body) {
        // 解析 XML 响应获取 uploadId
        const xmlStr = ByteUtils.bytesToString(response.body);
        const uploadId = this.parseUploadId(xmlStr);

        const init: MultipartUploadInit = {
          uploadId: uploadId,
          key: key,
          bucket: bucket
        };

        const result: S3Result<MultipartUploadInit> = {
          success: true,
          statusCode: response.statusCode,
          data: init,
          headers: response.headers as Record<string, string>
        };

        return result;
      }

      return this.handleResponse<MultipartUploadInit>(response);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'createMultipartUpload error: %{public}s', err.message);
      const result: S3Result<MultipartUploadInit> = {
        success: false,
        statusCode: 500,
        message: err.message
      };
      return result;
    }
  }

  /**
   * 解析 uploadId 从 XML 响应
   */
  private parseUploadId(xmlStr: string): string {
    // S3 响应格式:
    // <InitiateMultipartUploadResult>
    //   <Bucket>bucket</Bucket>
    //   <Key>key</Key>
    //   <UploadId>uploadId</UploadId>
    // </InitiateMultipartUploadResult>

    const uploadIdMatch = xmlStr.match(/<UploadId>([^<]+)<\/UploadId>/);
    if (uploadIdMatch && uploadIdMatch[1]) {
      return uploadIdMatch[1];
    }

    throw new Error('Failed to parse uploadId from response');
  }

  /**
   * 上传单个 Part
   * @param bucket 存储桶名称
   * @param key 对象键
   * @param uploadId Upload ID
   * @param partNumber Part 编号（1-10000）
   * @param data Part 数据
   * @returns S3Result<UploadedPart>
   */
  public async uploadPart(
    bucket: string,
    key: string,
    uploadId: string,
    partNumber: number,
    data: ArrayBuffer
  ): Promise<S3Result<UploadedPart>> {
    let retryCount = 0;

    while (retryCount < S3MultipartConfig.MAX_RETRY_COUNT) {
      try {
        // 查询字符串: ?partNumber={N}&uploadId={id}
        const queryString = `partNumber=${partNumber}&uploadId=${encodeURIComponent(uploadId)}`;

        const headers = await this.signer.signRequest(
          'PUT',
          this.options.endpoint,
          bucket,
          key,
          this.options.pathStyle,
          new Map([['content-type', 'application/octet-stream']]),
          data,
          queryString
        );

        const url = this.buildUrl(bucket, key) + '?' + queryString;
        const request = new rcp.Request(url, 'PUT', this.headersToRecord(headers), data);
        const response = await this.getSession()?.fetch(request);

        if (response && response.statusCode >= 200 && response.statusCode < 300) {
          // 从响应头获取 ETag
          const respHeaders = response.headers as Record<string, string>;
          const etag = (respHeaders['etag'] || respHeaders['ETag'] || '').replace(/"/g, '');

          const part: UploadedPart = {
            partNumber: partNumber,
            etag: etag,
            size: data.byteLength
          };

          const result: S3Result<UploadedPart> = {
            success: true,
            statusCode: response.statusCode,
            data: part,
            headers: respHeaders
          };

          return result;
        }

        // 非 2xx 响应，重试
        retryCount++;
        hilog.warn(DOMAIN, TAG, 'uploadPart failed with status %{public}d, retry %{public}d/%{public}d',
          response?.statusCode, retryCount, S3MultipartConfig.MAX_RETRY_COUNT);

      } catch (error) {
        const err = error as Error;
        retryCount++;
        hilog.error(DOMAIN, TAG, 'uploadPart error: %{public}s, retry %{public}d/%{public}d',
          err.message, retryCount, S3MultipartConfig.MAX_RETRY_COUNT);
      }
    }

    // 超过最大重试次数
    const result: S3Result<UploadedPart> = {
      success: false,
      statusCode: 500,
      message: `uploadPart failed after ${S3MultipartConfig.MAX_RETRY_COUNT} retries`
    };
    return result;
  }

  /**
   * 取消 Multipart Upload
   * @param bucket 存储桶名称
   * @param key 对象键
   * @param uploadId 上传ID
   * @returns S3Result<void>
   */
  public async abortMultipartUpload(
    bucket: string,
    key: string,
    uploadId: string
  ): Promise<S3Result<void>> {
    try {
      // 查询字符串: ?uploadId=xxx
      const queryString = 'uploadId=' + encodeURIComponent(uploadId);

      const headers = await this.signer.signRequest(
        'DELETE',
        this.options.endpoint,
        bucket,
        key,
        this.options.pathStyle,
        new Map(),
        null,
        queryString
      );

      const url = this.buildUrl(bucket, key) + '?' + queryString;
      const request = new rcp.Request(url, 'DELETE', this.headersToRecord(headers));
      const response = await this.getSession()?.fetch(request);

      return this.handleResponse<void>(response);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'abortMultipartUpload error: %{public}s', err.message);
      const result: S3Result<void> = {
        success: false,
        statusCode: 500,
        message: err.message
      };
      return result;
    }
  }

  /**
   * 完成 Multipart Upload
   * @param bucket 存储桶名称
   * @param key 对象键
   * @param uploadId Upload ID
   * @param parts 所有已上传的 Part 信息
   * @returns S3Result<void>
   */
  public async completeMultipartUpload(
    bucket: string,
    key: string,
    uploadId: string,
    parts: UploadedPart[]
  ): Promise<S3Result<void>> {
    try {
      // 构建 CompleteMultipartUpload XML
      const partsXml = parts
        .sort((a: UploadedPart, b: UploadedPart): number => a.partNumber - b.partNumber)
        .map((part: UploadedPart): string => `  <Part>
    <PartNumber>${part.partNumber}</PartNumber>
    <ETag>"${part.etag}"</ETag>
  </Part>`)
        .join('\n');

      const xmlBody = `<CompleteMultipartUpload>
${partsXml}
</CompleteMultipartUpload>`;

      const encoder = new util.TextEncoder();
      const payload = encoder.encodeInto(xmlBody).buffer as ArrayBuffer;

      // 查询字符串: ?uploadId={id}
      const queryString = 'uploadId=' + encodeURIComponent(uploadId);

      const headers = await this.signer.signRequest(
        'POST',
        this.options.endpoint,
        bucket,
        key,
        this.options.pathStyle,
        new Map([['content-type', 'application/xml']]),
        payload,
        queryString
      );

      const url = this.buildUrl(bucket, key) + '?' + queryString;
      const request = new rcp.Request(url, 'POST', this.headersToRecord(headers), payload);
      const response = await this.getSession()?.fetch(request);

      return this.handleResponse<void>(response);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'completeMultipartUpload error: %{public}s', err.message);
      const result: S3Result<void> = {
        success: false,
        statusCode: 500,
        message: err.message
      };
      return result;
    }
  }

  /**
   * 智能上传文件（自动判断是否使用 Multipart）
   * @param bucket 存储桶名称
   * @param key 对象键
   * @param data 文件数据
   * @param onProgress 进度回调（可选）
   * @param multipartThreshold 分块阈值，默认 5MB
   * @returns S3Result<void>
   */
  public async putObjectSmart(
    bucket: string,
    key: string,
    data: ArrayBuffer,
    onProgress?: ProgressCallback,
    multipartThreshold: number = S3MultipartConfig.MULTIPART_THRESHOLD
  ): Promise<S3Result<void>> {
    const fileSizeMB = (data.byteLength / (1024 * 1024)).toFixed(2);
    const thresholdMB = (multipartThreshold / (1024 * 1024)).toFixed(2);

    hilog.debug(DOMAIN, TAG,
      'putObjectSmart: bucket=%{public}s, key=%{public}s, size=%{public}s MB, threshold=%{public}s MB',
      bucket, key, fileSizeMB, thresholdMB);

    // 判断文件大小
    if (data.byteLength < multipartThreshold) {
      // 小文件：使用现有 putObject
      hilog.debug(DOMAIN, TAG, 'putObjectSmart: using simple putObject (file < threshold)');
      return this.putObject(bucket, key, data);
    }

    // 大文件：使用 Multipart Upload
    hilog.debug(DOMAIN, TAG, 'putObjectSmart: using multipart upload (file >= threshold)');
    return this.putObjectMultipart(bucket, key, data, onProgress);
  }

  /**
   * 使用 Multipart Upload 上传大文件
   * @param bucket 存储桶名称
   * @param key 对象键
   * @param data 文件数据
   * @param onProgress 进度回调（可选）
   * @returns S3Result<void>
   */
  private async putObjectMultipart(
    bucket: string,
    key: string,
    data: ArrayBuffer,
    onProgress?: ProgressCallback
  ): Promise<S3Result<void>> {
    hilog.debug(DOMAIN, TAG, 'putObjectMultipart: starting multipart upload for bucket=%{public}s, key=%{public}s',
      bucket, key);

    // 1. 初始化 Multipart Upload
    const initResult = await this.createMultipartUpload(bucket, key);

    if (!initResult.success || !initResult.data) {
      hilog.error(DOMAIN, TAG, 'putObjectMultipart: failed to initialize multipart upload: %{public}s',
        initResult.message || 'unknown error');
      return {
        success: false,
        statusCode: initResult.statusCode,
        message: initResult.message || 'Failed to initialize multipart upload'
      };
    }

    const uploadId = initResult.data.uploadId;
    hilog.debug(DOMAIN, TAG, 'putObjectMultipart: created upload with uploadId=%{public}s', uploadId);

    const uploadedParts: UploadedPart[] = [];

    try {
      // 2. 分块上传
      const totalSize = data.byteLength;
      const partSize = S3MultipartConfig.RECOMMENDED_PART_SIZE;
      const totalParts = Math.ceil(totalSize / partSize);

      hilog.debug(DOMAIN, TAG,
        'putObjectMultipart: totalSize=%{public}d bytes, partSize=%{public}d bytes, totalParts=%{public}d',
        totalSize, partSize, totalParts);

      for (let partNumber = 1; partNumber <= totalParts; partNumber++) {
        const start = (partNumber - 1) * partSize;
        const end = Math.min(start + partSize, totalSize);
        const partData = data.slice(start, end);

        hilog.debug(DOMAIN, TAG,
          'putObjectMultipart: uploading part %{public}d/%{public}d, bytes %{public}d-%{public}d, size=%{public}d bytes',
          partNumber, totalParts, start, end - 1, partData.byteLength);

        // 上传单个 Part
        const partResult = await this.uploadPart(bucket, key, uploadId, partNumber, partData);

        if (!partResult.success || !partResult.data) {
          // 上传失败，取消 Multipart Upload
          hilog.error(DOMAIN, TAG, 'putObjectMultipart: failed to upload part %{public}d: %{public}s',
            partNumber, partResult.message || 'unknown error');
          await this.abortMultipartUpload(bucket, key, uploadId);

          return {
            success: false,
            statusCode: partResult.statusCode,
            message: partResult.message || `Failed to upload part ${partNumber}`
          };
        }

        uploadedParts.push(partResult.data);
        hilog.debug(DOMAIN, TAG, 'putObjectMultipart: uploaded part %{public}d successfully, etag=%{public}s',
          partNumber, partResult.data.etag);

        // 进度回调
        if (onProgress) {
          const progress: MultipartUploadProgress = {
            uploadedBytes: end,
            totalBytes: totalSize,
            currentPart: partNumber,
            totalParts: totalParts
          };
          onProgress(progress);
        }
      }

      // 3. 完成 Multipart Upload
      hilog.debug(DOMAIN, TAG, 'putObjectMultipart: completing multipart upload with %{public}d parts',
        uploadedParts.length);
      const completeResult = await this.completeMultipartUpload(bucket, key, uploadId, uploadedParts);

      if (completeResult.success) {
        hilog.info(DOMAIN, TAG, 'putObjectMultipart: multipart upload completed successfully');
      } else {
        hilog.error(DOMAIN, TAG, 'putObjectMultipart: failed to complete multipart upload: %{public}s',
          completeResult.message || 'unknown error');
      }

      return completeResult;

    } catch (error) {
      // 发生异常，取消 Multipart Upload
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'putObjectMultipart: exception during upload: %{public}s', err.message);
      await this.abortMultipartUpload(bucket, key, uploadId);

      return {
        success: false,
        statusCode: 500,
        message: err.message
      };
    }
  }

  /**
   * 复制对象
   * @param bucket 目标存储桶名称
   * @param key 目标对象键
   * @param copyHeaders 复制请求头（包含 x-amz-copy-source）
   * @returns S3Result<void>
   */
  public async copyObject(
    bucket: string,
    key: string,
    copyHeaders: Map<string, string>
  ): Promise<S3Result<void>> {
    try {
      const headers = await this.signer.signRequest(
        'PUT',
        this.options.endpoint,
        bucket,
        key,
        this.options.pathStyle,
        copyHeaders
      );

      const url = this.buildUrl(bucket, key);
      const request = new rcp.Request(url, 'PUT', this.headersToRecord(headers));
      const response = await this.getSession()?.fetch(request);

      return this.handleResponse<void>(response);
    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'copyObject error: %{public}s', err.message);
      const result: S3Result<void> = {
        success: false,
        statusCode: 500,
        message: err.message
      };
      return result;
    }
  }

  /**
   * 分块下载对象（支持大文件）
   * @param bucket 存储桶名称
   * @param key 对象键
   * @param chunkSize 分块大小，默认 8MB
   * @param onProgress 进度回调（可选）
   */
  public async getObjectChunked(
    bucket: string,
    key: string,
    chunkSize: number = S3MultipartConfig.RECOMMENDED_PART_SIZE,
    onProgress?: ProgressCallback
  ): Promise<S3Result<ArrayBuffer>> {
    try {
      // 1. 获取文件大小
      const headResult = await this.headObject(bucket, key);

      if (!headResult.success || !headResult.data) {
        return {
          success: false,
          statusCode: headResult.statusCode,
          message: headResult.message || 'Failed to get object info'
        };
      }

      const totalSize = headResult.data.size;

      // 小文件直接下载
      if (totalSize <= chunkSize) {
        return this.getObject(bucket, key);
      }

      // 2. 分块下载
      const totalChunks = Math.ceil(totalSize / chunkSize);
      const chunks: ArrayBuffer[] = [];
      let downloadedBytes = 0;

      for (let chunkIndex = 0; chunkIndex < totalChunks; chunkIndex++) {
        const start = chunkIndex * chunkSize;
        const end = Math.min(start + chunkSize - 1, totalSize - 1);

        // 设置 Range 请求头
        const rangeHeader = `bytes=${start}-${end}`;

        const headers = await this.signer.signRequest(
          'GET',
          this.options.endpoint,
          bucket,
          key,
          this.options.pathStyle,
          new Map([['range', rangeHeader]])
        );

        const url = this.buildUrl(bucket, key);
        const request = new rcp.Request(url, 'GET', this.headersToRecord(headers));
        const response = await this.getSession()?.fetch(request);

        if (!response || response.statusCode < 200 || response.statusCode >= 300 || !response.body) {
          return {
            success: false,
            statusCode: response?.statusCode || 500,
            message: `Failed to download chunk ${chunkIndex + 1}`
          };
        }

        chunks.push(response.body);
        downloadedBytes += response.body.byteLength;

        // 进度回调
        if (onProgress) {
          const progress: MultipartUploadProgress = {
            uploadedBytes: downloadedBytes,
            totalBytes: totalSize,
            currentPart: chunkIndex + 1,
            totalParts: totalChunks
          };
          onProgress(progress);
        }
      }

      // 3. 合并所有块
      const result = new ArrayBuffer(totalSize);
      const resultView = new Uint8Array(result);
      let offset = 0;

      for (const chunk of chunks) {
        const chunkView = new Uint8Array(chunk);
        resultView.set(chunkView, offset);
        offset += chunk.byteLength;
      }

      return {
        success: true,
        statusCode: 200,
        data: result
      };

    } catch (error) {
      const err = error as Error;
      hilog.error(DOMAIN, TAG, 'getObjectChunked error: %{public}s', err.message);

      return {
        success: false,
        statusCode: 500,
        message: err.message
      };
    }
  }
}
