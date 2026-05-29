import { rcp } from '@kit.RemoteCommunicationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils } from 'kdbxweb';
import { S3Bucket, S3Object, S3Result } from './S3Types';
import { S3SignatureV4 } from './S3SignatureV4';
import { S3XmlParser } from './S3XmlParser';

const DOMAIN = 0x0000;
const TAG = 'S3Client';

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

  constructor(options: S3ClientOptions) {
    this.options = options;
    this.signer = new S3SignatureV4(
      options.accessKeyId,
      options.secretAccessKey,
      options.region
    );
    this.initSession();
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
    const endpoint = this.options.endpoint.endsWith('/')
      ? this.options.endpoint.slice(0, -1)
      : this.options.endpoint;

    if (this.options.pathStyle) {
      return `${endpoint}/${bucket}/${key}`;
    } else {
      const url = new URL(endpoint);
      return `${url.protocol}//${bucket}.${url.host}/${key}`;
    }
  }

  private headersToRecord(headers: Map<string, string>): rcp.Headers {
    const record: rcp.Headers = {};
    headers.forEach((value, key) => {
      record[key] = value;
    });
    return record;
  }

  private async handleResponse<T>(response: rcp.Response | undefined, parseData?: (body: ArrayBuffer) => T): Promise<S3Result<T>> {
    if (!response) {
      return {
        success: false,
        statusCode: 500,
        message: 'No response from server'
      };
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
      const headers = await this.signer.signListBuckets(this.options.endpoint);
      const url = new URL(this.options.endpoint);
      const request = new rcp.Request(
        `${url.protocol}//${url.host}/`,
        'GET',
        this.headersToRecord(headers)
      );

      const response = await this.session?.fetch(request);
      return this.handleResponse<S3Bucket[]>(response, (body) => {
        const xmlStr = ByteUtils.bytesToString(body);
        return S3XmlParser.parseListBuckets(xmlStr);
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'listBuckets error: %{public}s', (error as Error).message);
      return {
        success: false,
        statusCode: 500,
        message: (error as Error).message
      };
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

      return this.handleResponse<S3Object[]>(response, (body) => {
        const xmlStr = ByteUtils.bytesToString(body);
        return S3XmlParser.parseListObjects(xmlStr);
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'listObjects error: %{public}s', (error as Error).message);
      return {
        success: false,
        statusCode: 500,
        message: (error as Error).message
      };
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
        return {
          success: true,
          statusCode: response.statusCode,
          data: response.body,
          headers: response.headers as Record<string, string>
        };
      }

      return this.handleResponse<ArrayBuffer>(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'getObject error: %{public}s', (error as Error).message);
      return {
        success: false,
        statusCode: 500,
        message: (error as Error).message
      };
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
      hilog.error(DOMAIN, TAG, 'putObject error: %{public}s', (error as Error).message);
      return {
        success: false,
        statusCode: 500,
        message: (error as Error).message
      };
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
      hilog.error(DOMAIN, TAG, 'deleteObject error: %{public}s', (error as Error).message);
      return {
        success: false,
        statusCode: 500,
        message: (error as Error).message
      };
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
        return {
          success: true,
          statusCode: 200,
          data: {
            key: key,
            size: parseInt(respHeaders['content-length'] || '0', 10),
            lastModified: new Date(respHeaders['last-modified'] || '').getTime(),
            etag: (respHeaders['etag'] || '').replace(/"/g, '')
          }
        };
      }

      return this.handleResponse<S3Object>(response);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'headObject error: %{public}s', (error as Error).message);
      return {
        success: false,
        statusCode: 500,
        message: (error as Error).message
      };
    }
  }

  public async testConnection(): Promise<S3Result<void>> {
    return this.listBuckets().then(result => {
      if (result.success) {
        return { success: true, statusCode: 200 };
      }
      return { success: false, statusCode: result.statusCode, message: result.message };
    });
  }
}
