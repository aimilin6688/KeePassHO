import { http } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { rcp } from '@kit.RemoteCommunicationKit';

const DOMAIN = 0x0000;
const TAG = 'HttpUtils';

/**
 * HTTP请求方法枚举
 */
export enum HttpMethod {
  /**
   * GET请求
   */
  GET = 'GET',
  /**
   * POST请求
   */
  POST = 'POST',
  /**
   * PUT请求
   */
  PUT = 'PUT',
  /**
   * DELETE请求
   */
  DELETE = 'DELETE',
  /**
   * PATCH请求
   */
  PATCH = 'PATCH'
}

/**
 * HTTP请求头记录类型
 */
export type HttpHeaders = Record<string, string>;

/**
 * HTTP请求配置类
 */
export class HttpRequestConfig {
  /**
   * 请求头
   */
  headers?: HttpHeaders;
  /**
   * 超时时间（毫秒）
   */
  timeout?: number;
  /**
   * 基础地址
   */
  baseAddress?: string;
}

/**
 * HTTP响应类
 */
export class HttpResponse {
  /**
   * 是否成功
   */
  success: boolean = true;
  /**
   * HTTP状态码
   */
  statusCode: number = 200;
  /**
   * 错误消息
   */
  message: string = '';
  /**
   * 响应头
   */
  headers: rcp.ResponseHeaders = {} as rcp.ResponseHeaders;
  /**
   * 响应体
   */
  body?: ArrayBuffer = undefined;

  constructor(success: boolean, statusCode: number, message: string, headers: rcp.ResponseHeaders, body?: ArrayBuffer) {
    this.success = success;
    this.statusCode = statusCode;
    this.message = message;
    this.headers = headers;
    this.body = body;
  }
}

/**
 * RCP会话配置类
 */
export class SessionConfig {
  /**
   * 基础地址
   */
  baseAddress: string;
  /**
   * 请求头
   */
  headers?: HttpHeaders;
  /**
   * 连接超时时间（毫秒）
   */
  connectTimeout?: number;

  constructor(baseAddress: string, headers?: HttpHeaders, connectTimeout?: number) {
    this.baseAddress = baseAddress;
    this.headers = headers;
    this.connectTimeout = connectTimeout;
  }
}

/**
 * RCP请求配置类
 */
export class RcpRequestConfig {
  /**
   * 方法
   */
  method: string;
  /**
   * URL
   */
  url: string;
  /**
   * 头部
   */
  headers?: HttpHeaders;
  /**
   * 请求体
   */
  body?: ArrayBuffer | string;

  constructor(method: string, url: string, headers?: HttpHeaders, body?: ArrayBuffer | string) {
    this.method = method;
    this.url = url;
    this.headers = headers;
    this.body = body;
  }
}

/**
 * HTTP工具类
 * 提供通用的HTTP请求功能
 */
export class HttpUtils {
  /**
   * RCP会话
   */
  private session: rcp.Session | null = null;

  /**
   * 基础配置
   */
  private config: HttpRequestConfig = new HttpRequestConfig();

  /**
   * 构造函数
   * @param config 请求配置
   */
  constructor(config?: HttpRequestConfig) {
    if (config) {
      if (config.headers !== undefined) {
        this.config.headers = config.headers;
      }
      if (config.timeout !== undefined) {
        this.config.timeout = config.timeout;
      }
      if (config.baseAddress !== undefined) {
        this.config.baseAddress = config.baseAddress;
      }
    }
    if (this.config.headers === undefined) {
      this.config.headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json'
      };
    }
  }

  /**
   * 初始化RCP会话
   * @param baseAddress 基础地址
   * @param timeout 超时时间（毫秒）
   */
  public initSession(baseAddress: string, timeout?: number): void {
    this.close();
    const sessionConfig: rcp.SessionConfiguration = {
      baseAddress: baseAddress,
      headers: this.config.headers,
      requestConfiguration: {
        transfer: {
          timeout: { connectMs: timeout || this.config.timeout || 30000 }
        }
      }
    };
    this.session = rcp.createSession(sessionConfig);
  }

  /**
   * 设置请求头
   * @param headers 请求头
   */
  public setHeaders(headers: HttpHeaders): void {
    if (this.config.headers === undefined) {
      this.config.headers = {};
    }
    const mergedHeaders: Record<string, string> = {};
    // 复制现有headers
    const keys1 = Object.keys(this.config.headers);
    for (let i = 0; i < keys1.length; i++) {
      const key = keys1[i];
      mergedHeaders[key] = this.config.headers[key];
    }
    // 合并新headers
    const keys2 = Object.keys(headers);
    for (let i = 0; i < keys2.length; i++) {
      const key = keys2[i];
      mergedHeaders[key] = headers[key];
    }
    this.config.headers = mergedHeaders;
  }

  /**
   * 获取请求头
   * @returns 请求头
   */
  public getHeaders(): HttpHeaders {
    return this.config.headers || {};
  }

  /**
   * 关闭连接
   */
  public close(): void {
    if (this.session) {
      this.session.close();
      this.session = null;
    }
  }

  /**
   * 发送GET请求（使用http模块）
   * @param url 请求URL
   * @param headers 请求头
   * @param timeout 超时时间（毫秒）
   * @returns Promise<HttpResponse> 响应结果
   */
  public async get(url: string, headers?: HttpHeaders, timeout?: number): Promise<HttpResponse> {
    const httpRequest = http.createHttp();
    try {
      const mergedHeaders: Record<string, string> = this.mergeHeaders(headers);

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.GET,
        connectTimeout: timeout || this.config.timeout || 30000,
        readTimeout: timeout || this.config.timeout || 30000,
        header: mergedHeaders
      };

      const response = await httpRequest.request(url, options);
      const responseCode = response.responseCode as number;

      return new HttpResponse(
        responseCode >= 200 && responseCode < 300,
        responseCode,
        '',
        {} as rcp.ResponseHeaders,
        response.result as ArrayBuffer
      );
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'GET request failed: %{public}s', (error as Error).message);
      return new HttpResponse(
        false,
        500,
        (error as Error).message,
        {} as rcp.ResponseHeaders,
        undefined
      );
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 发送POST请求（使用http模块）
   * @param url 请求URL
   * @param data 请求数据
   * @param headers 请求头
   * @param timeout 超时时间（毫秒）
   * @returns Promise<HttpResponse> 响应结果
   */
  public async post(url: string, data?: string | ArrayBuffer, headers?: HttpHeaders, timeout?: number): Promise<HttpResponse> {
    const httpRequest = http.createHttp();
    try {
      const mergedHeaders: Record<string, string> = this.mergeHeaders(headers);

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        connectTimeout: timeout || this.config.timeout || 30000,
        readTimeout: timeout || this.config.timeout || 30000,
        header: mergedHeaders,
        extraData: data
      };

      const response = await httpRequest.request(url, options);
      const responseCode = response.responseCode as number;

      return new HttpResponse(
        responseCode >= 200 && responseCode < 300,
        responseCode,
        '',
        {} as rcp.ResponseHeaders,
        response.result as ArrayBuffer
      );
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'POST request failed: %{public}s', (error as Error).message);
      return new HttpResponse(
        false,
        500,
        (error as Error).message,
        {} as rcp.ResponseHeaders,
        undefined
      );
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 发送PUT请求（使用http模块）
   * @param url 请求URL
   * @param data 请求数据
   * @param headers 请求头
   * @param timeout 超时时间（毫秒）
   * @returns Promise<HttpResponse> 响应结果
   */
  public async put(url: string, data?: string | ArrayBuffer, headers?: HttpHeaders, timeout?: number): Promise<HttpResponse> {
    const httpRequest = http.createHttp();
    try {
      const mergedHeaders: Record<string, string> = this.mergeHeaders(headers);

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.PUT,
        connectTimeout: timeout || this.config.timeout || 30000,
        readTimeout: timeout || this.config.timeout || 30000,
        header: mergedHeaders,
        extraData: data
      };

      const response = await httpRequest.request(url, options);
      const responseCode = response.responseCode as number;

      return new HttpResponse(
        responseCode >= 200 && responseCode < 300,
        responseCode,
        '',
        {} as rcp.ResponseHeaders,
        response.result as ArrayBuffer
      );
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'PUT request failed: %{public}s', (error as Error).message);
      return new HttpResponse(
        false,
        500,
        (error as Error).message,
        {} as rcp.ResponseHeaders,
        undefined
      );
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 发送DELETE请求（使用http模块）
   * @param url 请求URL
   * @param headers 请求头
   * @param timeout 超时时间（毫秒）
   * @returns Promise<HttpResponse> 响应结果
   */
  public async delete(url: string, headers?: HttpHeaders, timeout?: number): Promise<HttpResponse> {
    const httpRequest = http.createHttp();
    try {
      const mergedHeaders: Record<string, string> = this.mergeHeaders(headers);

      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.DELETE,
        connectTimeout: timeout || this.config.timeout || 30000,
        readTimeout: timeout || this.config.timeout || 30000,
        header: mergedHeaders
      };

      const response = await httpRequest.request(url, options);
      const responseCode = response.responseCode as number;

      return new HttpResponse(
        responseCode >= 200 && responseCode < 300,
        responseCode,
        '',
        {} as rcp.ResponseHeaders,
        response.result as ArrayBuffer
      );
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'DELETE request failed: %{public}s', (error as Error).message);
      return new HttpResponse(
        false,
        500,
        (error as Error).message,
        {} as rcp.ResponseHeaders,
        undefined
      );
    } finally {
      httpRequest.destroy();
    }
  }

  /**
   * 发送RCP请求
   * @param requestConfig 请求配置
   * @returns Promise<HttpResponse> 响应结果
   */
  public async rcpRequest(requestConfig: RcpRequestConfig): Promise<HttpResponse> {
    let responseReturn: HttpResponse = new HttpResponse(true, 200, '', {} as rcp.ResponseHeaders, undefined);

    if (!this.session) {
      return new HttpResponse(false, 500, 'Session not initialized', {} as rcp.ResponseHeaders, undefined);
    }

    let errorMessage: string | undefined = undefined;

    try {
      const req = new rcp.Request(requestConfig.url, requestConfig.method, requestConfig.headers, requestConfig.body);
      const resp = await this.session.fetch(req);
      errorMessage = resp?.toString() ?? undefined;

      if (resp === undefined) {
        return new HttpResponse(false, 500, 'Request failed', {} as rcp.ResponseHeaders, undefined);
      }

      hilog.debug(DOMAIN, TAG, 'RCP request return statusCode: %{public}d, headers: %{public}s',
        resp.statusCode, JSON.stringify(resp.headers));

      responseReturn.statusCode = resp.statusCode;
      responseReturn.headers = resp.headers;

      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        responseReturn.body = resp.body;
        responseReturn.success = true;
      } else {
        responseReturn.success = false;
        responseReturn.message = this.toErrorMsg(errorMessage) || '';
      }
    } catch (err) {
      let errMsg: string = err.message ?? errorMessage ?? err.data ?? '';
      hilog.error(DOMAIN, TAG, 'RCP request error: %{public}s:%{public}s', err.code, errMsg);
      responseReturn.statusCode = 500;
      responseReturn.success = false;
      responseReturn.message = `${err.code}:${errMsg}`;
    }

    return responseReturn;
  }

  /**
   * 合并请求头
   * @param headers 要合并的请求头
   * @returns 合并后的请求头
   */
  private mergeHeaders(headers?: HttpHeaders): Record<string, string> {
    const mergedHeaders: Record<string, string> = {};
    if (this.config.headers) {
      const keys1 = Object.keys(this.config.headers);
      for (let i = 0; i < keys1.length; i++) {
        const key = keys1[i];
        mergedHeaders[key] = this.config.headers[key];
      }
    }
    if (headers) {
      const keys2 = Object.keys(headers);
      for (let i = 0; i < keys2.length; i++) {
        const key = keys2[i];
        mergedHeaders[key] = headers[key];
      }
    }
    return mergedHeaders;
  }

  /**
   * URL编码对象
   * @param data 数据对象
   * @returns URL编码字符串
   */
  public urlEncode(data: Record<string, string>): string {
    const pairs: string[] = [];
    const entries = Object.entries(data);
    for (let i = 0; i < entries.length; i++) {
      const entry = entries[i];
      const key = entry[0];
      const value = entry[1];
      pairs.push(`${encodeURIComponent(key)}=${encodeURIComponent(value)}`);
    }
    return pairs.join('&');
  }

  /**
   * 从对象中提取字符串值
   * @param obj 对象
   * @param key 键
   * @param defaultValue 默认值
   * @returns 字符串值
   */
  public extractStringFromObject(obj: Record<string, Object>, key: string, defaultValue: string = ''): string {
    const value = obj[key];
    if (value === undefined || value === null) {
      return defaultValue;
    }
    return String(value);
  }

  /**
   * 从对象中提取可选字符串值
   * @param obj 对象
   * @param key 键
   * @returns 字符串值或undefined
   */
  public extractOptionalStringFromObject(obj: Record<string, Object>, key: string): string | undefined {
    const value = obj[key];
    if (value === undefined || value === null) {
      return undefined;
    }
    return String(value);
  }

  /**
   * 从对象中提取可选数字值
   * @param obj 对象
   * @param key 键
   * @returns 数字值或undefined
   */
  public extractOptionalNumberFromObject(obj: Record<string, Object>, key: string): number | undefined {
    const value = obj[key];
    if (value === undefined || value === null) {
      return undefined;
    }
    const num = Number(value);
    return isNaN(num) ? undefined : num;
  }

  /**
   * 将错误消息转换为友好提示
   * @param errorMessage 错误消息
   * @returns 友好提示
   */
  private toErrorMsg(errorMessage?: string): string | undefined {
    if (!errorMessage) {
      return undefined;
    }
    try {
      const errorObj: Record<string, Object> = JSON.parse(errorMessage);
      const errorDetail = errorObj['error'] as Record<string, Object> | undefined;
      if (errorDetail && errorDetail['message']) {
        return String(errorDetail['message']);
      }
    } catch (e) {
      // 忽略解析错误
    }
    return errorMessage;
  }
}
