import { rcp } from '@kit.RemoteCommunicationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils } from 'kdbxweb';
import { S3Bucket, S3Object, S3Result } from './S3Types';
import { S3SignatureV4 } from './S3SignatureV4';
import { S3XmlParser } from './S3XmlParser';

const DOMAIN = 0x0000;
const TAG = 'S3Client';

/**
 * 简单 URL 解析结果
 */
interface ParsedUrl {
  protocol: string;
  host: string;
  port: string;
  path: string;
}

/**
 * S3 客户端配置选项
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
 * S3 HTTP 客户端
 */
export class S3Client {
  private session: rcp.Session | null = null;
  private options: S3ClientOptions;
  private signer: S3SignatureV4;
  private parsedEndpoint: ParsedUrl;

  constructor(options: S3ClientOptions) {
    this.options = options;
    this.signer = new S3SignatureV4(
      options.accessKeyId,
      options.secretAccessKey,
      options.region
    );
    this.parsedEndpoint = this.parseUrl(options.endpoint);
    this.initSession();
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

  private initSession(): void {
    this.session = rcp.createSession({
      requestConfiguration: {
        transfer: {
          timeout: { connectMs: this.options.timeout }
        }
      }
    });
  }

  private buildUrl(bucket: string, key: string): string {
    if (this.options.pathStyle) {
      const url: string = `${this.options.endpoint}/${bucket}/${key}`;
      return url;
    } else {
      const url: string = `${this.parsedEndpoint.protocol}://${bucket}.${this.parsedEndpoint.host}/${key}`;
      return url;
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
          const error = S3XmlParser.parseError(xmlStr);
          result.message = error.message || `HTTP ${response.statusCode}`;
        } catch {
          result.message = `HTTP ${response.statusCode}`;
        }
      }
    }

    return result;
  }

  public close(): void {
    this.session?.close();
    this.session = null;
  }

  public async listBuckets(): Promise<S3Result<S3Bucket[]>> {
    try {
      const headers = await this.signer.signListBuckets(this.options.endpoint, this.parsedEndpoint.host);
      const url: string = `${this.parsedEndpoint.protocol}://${this.parsedEndpoint.host}/`;
      const request = new rcp.Request(
        url,
        'GET',
        this.headersToRecord(headers)
      );

      const response = await this.session?.fetch(request);
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
      const response = await this.session?.fetch(request);
      return response?.statusCode === 200;
    } catch {
      return false;
    }
  }

  public async listObjects(bucket: string, prefix?: string): Promise<S3Result<S3Object[]>> {
    try {
      const headers = await this.signer.signRequest(
        'GET',
        this.options.endpoint,
        bucket,
        '',
        this.options.pathStyle
      );

      let url = this.buildUrl(bucket, '');
      if (prefix) {
        url += '?prefix=' + encodeURIComponent(prefix) + '&delimiter=/';
      } else {
        url += '?delimiter=/';
      }

      const request = new rcp.Request(url, 'GET', this.headersToRecord(headers));
      const response = await this.session?.fetch(request);

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
      const response = await this.session?.fetch(request);

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
      const response = await this.session?.fetch(request);

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
      const response = await this.session?.fetch(request);

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
      const response = await this.session?.fetch(request);

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
}
