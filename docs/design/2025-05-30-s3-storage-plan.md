# S3 兼容存储功能实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 KeePassHO 添加 S3 兼容存储支持，允许用户从 AWS S3、MinIO、阿里云 OSS 等 S3 兼容服务打开和保存 KeePass 数据库文件。

**Architecture:** 遵循现有存储架构模式，创建 S3Types、S3Config、S3SignatureV4、S3XmlParser、S3Client、S3Storage、S3Page 七个模块，实现 IFileStorage 接口并注册到 FileStorageFactory。

**Tech Stack:** ArkTS、HarmonyOS rcp（HTTP 请求）、cryptoFramework（SHA256/HMAC-SHA256）、xml.XmlPullParser（XML 解析）、Sm4Utils（敏感信息加密）

---

## 文件结构

### 新增文件

| 文件路径 | 职责 |
|----------|------|
| `entry/src/main/ets/storage/s3/S3Types.ets` | S3 类型定义（S3Object、S3Bucket、S3Result） |
| `entry/src/main/ets/storage/s3/S3Config.ets` | 配置类和页面配置 |
| `entry/src/main/ets/storage/s3/S3SignatureV4.ets` | AWS Signature V4 签名算法 |
| `entry/src/main/ets/storage/s3/S3XmlParser.ets` | S3 XML 响应解析器 |
| `entry/src/main/ets/storage/s3/S3Client.ets` | S3 HTTP 客户端 |
| `entry/src/main/ets/storage/s3/S3Storage.ets` | IFileStorage 实现 |
| `entry/src/main/ets/storage/s3/S3Page.ets` | 配置页面 |
| `entry/src/main/resources/base/media/ic_s3.png` | S3 存储图标 |

### 修改文件

| 文件路径 | 修改内容 |
|----------|----------|
| `entry/src/main/ets/storage/StorageType.ets` | 添加 S3 枚举值 |
| `entry/src/main/ets/storage/FileStorageFactory.ets` | 注册 S3Storage |
| `entry/src/main/ets/storage/index.ets` | 导出 S3 模块 |
| `entry/src/main/resources/base/profile/main_pages.json` | 添加 S3Page 路由 |
| `entry/src/main/resources/base/element/string.json` | 添加 S3 相关字符串 |

---

## Task 1: 类型定义 (S3Types.ets)

**Files:**
- Create: `entry/src/main/ets/storage/s3/S3Types.ets`

- [ ] **Step 1: 创建 S3Types.ets 文件**

```typescript
/**
 * S3 对象信息
 */
export interface S3Object {
  /**
   * 对象键（路径）
   */
  key: string;

  /**
   * 大小（字节）
   */
  size: number;

  /**
   * 最后修改时间戳（毫秒）
   */
  lastModified: number;

  /**
   * ETag
   */
  etag: string;
}

/**
 * S3 存储桶信息
 */
export interface S3Bucket {
  /**
   * 存储桶名称
   */
  name: string;

  /**
   * 创建时间戳（毫秒）
   */
  creationDate: number;
}

/**
 * S3 API 响应结果
 */
export interface S3Result<T> {
  /**
   * 是否成功
   */
  success: boolean;

  /**
   * HTTP 状态码
   */
  statusCode: number;

  /**
   * 错误消息
   */
  message?: string;

  /**
   * 响应数据
   */
  data?: T;

  /**
   * 响应头
   */
  headers?: Record<string, string>;
}

/**
 * S3 错误信息
 */
export interface S3Error {
  code: string;
  message: string;
  resourceId?: string;
  resource?: string;
}
```

- [ ] **Step 2: 提交代码**

```bash
git add entry/src/main/ets/storage/s3/S3Types.ets
git commit -m "feat(s3): add S3 type definitions

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 2: 配置类 (S3Config.ets)

**Files:**
- Create: `entry/src/main/ets/storage/s3/S3Config.ets`

- [ ] **Step 1: 创建 S3Config.ets 文件**

```typescript
import { PageConfig, StorageConfig, StorageType } from '..';
import { Sm4Utils } from '../../common/utils/Sm4Utils';

/**
 * S3 存储配置选项
 */
export interface S3ConfigOptions {
  /**
   * 区域，默认 us-east-1
   */
  region?: string;

  /**
   * 默认存储桶
   */
  bucket?: string;

  /**
   * 是否使用路径样式 URL，默认 false
   */
  pathStyle?: boolean;

  /**
   * 超时时间（毫秒），默认 30000
   */
  timeout?: number;
}

/**
 * S3 存储配置类
 */
export class S3StorageConfig implements StorageConfig {
  /**
   * 服务端点，如 https://s3.amazonaws.com
   */
  endpoint: string;

  /**
   * Access Key ID，加密存储
   */
  accessKeyId: string;

  /**
   * Secret Access Key，加密存储
   */
  secretAccessKey: string;

  /**
   * 区域
   */
  region: string;

  /**
   * 默认存储桶
   */
  bucket?: string;

  /**
   * 是否使用路径样式 URL
   */
  pathStyle: boolean;

  /**
   * 超时时间（毫秒）
   */
  timeout: number;

  constructor(
    endpoint: string,
    accessKeyId: string,
    secretAccessKey: string,
    options?: S3ConfigOptions
  ) {
    this.endpoint = endpoint;
    this.accessKeyId = Sm4Utils.encryptWithPrefix(accessKeyId);
    this.secretAccessKey = Sm4Utils.encryptWithPrefix(secretAccessKey);
    this.region = options?.region || 'us-east-1';
    this.bucket = options?.bucket;
    this.pathStyle = options?.pathStyle ?? false;
    this.timeout = options?.timeout ?? 30000;
  }

  /**
   * 获取 Access Key ID（解密后）
   */
  public getAccessKeyIdText(): string {
    return Sm4Utils.decryptWithPrefix(this.accessKeyId);
  }

  /**
   * 获取 Secret Access Key（解密后）
   */
  public getSecretAccessKeyText(): string {
    return Sm4Utils.decryptWithPrefix(this.secretAccessKey);
  }
}

/**
 * S3 页面配置
 */
export const S3PageConfig: PageConfig = {
  icon: $r('app.media.ic_s3'),
  title: $r('app.string.s3_button_title'),
  selectDesc: $r('app.string.s3_select_file'),
  saveDesc: $r('app.string.s3_save_file'),
  pageUrl: 'storage/s3/S3Page',
  storageType: StorageType.S3
};
```

- [ ] **Step 2: 提交代码**

```bash
git add entry/src/main/ets/storage/s3/S3Config.ets
git commit -m "feat(s3): add S3 configuration class

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 3: AWS Signature V4 签名算法 (S3SignatureV4.ets)

**Files:**
- Create: `entry/src/main/ets/storage/s3/S3SignatureV4.ets`

- [ ] **Step 1: 创建 S3SignatureV4.ets 文件 - 第一部分（辅助方法）**

```typescript
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'S3SignatureV4';

/**
 * AWS Signature Version 4 签名算法实现
 */
export class S3SignatureV4 {
  private static readonly ALGORITHM = 'AWS4-HMAC-SHA256';
  private static readonly SERVICE = 's3';
  private static readonly TERMINATOR = 'aws4_request';

  private accessKeyId: string;
  private secretAccessKey: string;
  private region: string;

  constructor(accessKeyId: string, secretAccessKey: string, region: string) {
    this.accessKeyId = accessKeyId;
    this.secretAccessKey = secretAccessKey;
    this.region = region;
  }

  /**
   * 计算 SHA256 哈希值（十六进制字符串）
   */
  private async sha256Hex(data: ArrayBuffer | Uint8Array | null): Promise<string> {
    if (data === null || data === undefined) {
      // 空数据的 SHA256
      data = new Uint8Array(0);
    }

    const md = cryptoFramework.createMd('SHA256');
    await md.update({ data: data instanceof Uint8Array ? data.buffer as ArrayBuffer : data });
    const result = await md.digest();
    return new util.HexHelper().encodeToStringSync(result.data);
  }

  /**
   * 计算 HMAC-SHA256
   */
  private async hmacSha256(key: Uint8Array, data: string): Promise<Uint8Array> {
    const mac = cryptoFramework.createMac('HMAC|SHA256');
    const symKey = await cryptoFramework.createSymKeyGenerator('HMAC|SHA256')
      .convertKey({ algName: 'HMAC', params: null, data: key });
    await mac.init(symKey);
    const encoder = new util.TextEncoder();
    await mac.update({ data: encoder.encodeInto(data).buffer as ArrayBuffer });
    const result = await mac.doFinal();
    return result.data;
  }

  /**
   * 格式化日期（YYYYMMDD）
   */
  private formatDate(date: Date): string {
    const year = date.getUTCFullYear();
    const month = String(date.getUTCMonth() + 1).padStart(2, '0');
    const day = String(date.getUTCDate()).padStart(2, '0');
    return `${year}${month}${day}`;
  }

  /**
   * 格式化日期时间（YYYYMMDDTHHMMSSZ）
   */
  private formatDateTime(date: Date): string {
    const dateStr = this.formatDate(date);
    const hours = String(date.getUTCHours()).padStart(2, '0');
    const minutes = String(date.getUTCMinutes()).padStart(2, '0');
    const seconds = String(date.getUTCSeconds()).padStart(2, '0');
    return `${dateStr}T${hours}${minutes}${seconds}Z`;
  }

  /**
   * URL 编码（S3 风格）
   */
  private uriEncode(value: string, encodeSlash: boolean = true): string {
    let result = '';
    for (let i = 0; i < value.length; i++) {
      const ch = value.charAt(i);
      if (
        (ch >= 'A' && ch <= 'Z') ||
        (ch >= 'a' && ch <= 'z') ||
        (ch >= '0' && ch <= '9') ||
        ch === '_' || ch === '-' || ch === '~' || ch === '.'
      ) {
        result += ch;
      } else if (ch === '/') {
        result += encodeSlash ? '%2F' : '/';
      } else {
        const encoder = new util.TextEncoder();
        const bytes = encoder.encodeInto(ch);
        for (const byte of bytes) {
          result += '%' + byte.toString(16).toUpperCase().padStart(2, '0');
        }
      }
    }
    return result;
  }
}
```

- [ ] **Step 2: 添加签名核心方法**

在 `S3SignatureV4` 类中添加以下方法：

```typescript
  /**
   * 创建规范请求
   */
  private createCanonicalRequest(
    method: string,
    uri: string,
    queryString: string,
    signedHeaders: string,
    canonicalHeaders: string,
    payloadHash: string
  ): string {
    return [
      method,
      uri,
      queryString,
      canonicalHeaders,
      '',
      signedHeaders,
      payloadHash
    ].join('\n');
  }

  /**
   * 创建待签名字符串
   */
  private createStringToSign(
    amzDate: string,
    dateStamp: string,
    credentialScope: string,
    canonicalRequestHash: string
  ): string {
    return [
      S3SignatureV4.ALGORITHM,
      amzDate,
      credentialScope,
      canonicalRequestHash
    ].join('\n');
  }

  /**
   * 创建凭证范围
   */
  private createCredentialScope(dateStamp: string): string {
    return `${dateStamp}/${this.region}/${S3SignatureV4.SERVICE}/${S3SignatureV4.TERMINATOR}`;
  }

  /**
   * 构建授权头
   */
  private buildAuthorizationHeader(
    dateStamp: string,
    signedHeaders: string,
    signature: string
  ): string {
    const credentialScope = this.createCredentialScope(dateStamp);
    return `${S3SignatureV4.ALGORITHM} Credential=${this.accessKeyId}/${credentialScope}, SignedHeaders=${signedHeaders}, Signature=${signature}`;
  }
```

- [ ] **Step 3: 添加主签名方法**

在 `S3SignatureV4` 类中添加以下主签名方法：

```typescript
  /**
   * 签名请求，返回需要添加的 Headers
   * @param method HTTP 方法
   * @param endpoint 端点 URL（如 https://s3.amazonaws.com）
   * @param bucket 存储桶名称
   * @param key 对象键
   * @param pathStyle 是否使用路径样式
   * @param additionalHeaders 额外的请求头
   * @param payload 请求体
   * @returns 签名后的请求头
   */
  public async signRequest(
    method: string,
    endpoint: string,
    bucket: string,
    key: string,
    pathStyle: boolean,
    additionalHeaders: Map<string, string> = new Map(),
    payload: ArrayBuffer | null = null
  ): Promise<Map<string, string>> {
    const now = new Date();
    const dateStamp = this.formatDate(now);
    const amzDate = this.formatDateTime(now);

    // 计算 payload 哈希
    const payloadHash = await this.sha256Hex(payload);

    // 解析端点获取 host
    const url = new URL(endpoint);
    let host: string;
    let uri: string;

    if (pathStyle) {
      host = url.host;
      uri = '/' + this.uriEncode(bucket) + '/' + this.uriEncode(key, false);
    } else {
      host = bucket + '.' + url.host;
      uri = '/' + this.uriEncode(key, false);
    }

    // 构建请求头
    const headers = new Map<string, string>();
    headers.set('host', host);
    headers.set('x-amz-date', amzDate);
    headers.set('x-amz-content-sha256', payloadHash);

    // 添加额外请求头
    additionalHeaders.forEach((value, key) => {
      headers.set(key.toLowerCase(), value);
    });

    // 排序请求头
    const sortedHeaders = Array.from(headers.entries()).sort((a, b) => a[0].localeCompare(b[0]));
    const signedHeaders = sortedHeaders.map(([k]) => k).join(';');
    const canonicalHeaders = sortedHeaders.map(([k, v]) => `${k}:${v.trim()}`).join('\n');

    // 创建规范请求
    const canonicalRequest = this.createCanonicalRequest(
      method,
      uri,
      '',
      signedHeaders,
      canonicalHeaders,
      payloadHash
    );

    // 计算规范请求哈希
    const encoder = new util.TextEncoder();
    const canonicalRequestHash = await this.sha256Hex(encoder.encodeInto(canonicalRequest).buffer as ArrayBuffer);

    // 创建凭证范围
    const credentialScope = this.createCredentialScope(dateStamp);

    // 创建待签名字符串
    const stringToSign = this.createStringToSign(
      amzDate,
      dateStamp,
      credentialScope,
      canonicalRequestHash
    );

    // 计算签名密钥
    const kSecret = encoder.encodeInto('AWS4' + this.secretAccessKey);
    const kDate = await this.hmacSha256(kSecret, dateStamp);
    const kRegion = await this.hmacSha256(kDate, this.region);
    const kService = await this.hmacSha256(kRegion, S3SignatureV4.SERVICE);
    const kSigning = await this.hmacSha256(kService, S3SignatureV4.TERMINATOR);

    // 计算签名
    const signature = await this.hmacSha256(kSigning, stringToSign);
    const signatureHex = new util.HexHelper().encodeToStringSync(signature);

    // 构建授权头
    const authorization = this.buildAuthorizationHeader(dateStamp, signedHeaders, signatureHex);
    headers.set('authorization', authorization);

    return headers;
  }

  /**
   * 签名 ListBuckets 请求
   */
  public async signListBuckets(endpoint: string): Promise<Map<string, string>> {
    const now = new Date();
    const dateStamp = this.formatDate(now);
    const amzDate = this.formatDateTime(now);

    const payloadHash = await this.sha256Hex(null);

    const url = new URL(endpoint);
    const host = url.host;

    const headers = new Map<string, string>();
    headers.set('host', host);
    headers.set('x-amz-date', amzDate);
    headers.set('x-amz-content-sha256', payloadHash);

    const sortedHeaders = Array.from(headers.entries()).sort((a, b) => a[0].localeCompare(b[0]));
    const signedHeaders = sortedHeaders.map(([k]) => k).join(';');
    const canonicalHeaders = sortedHeaders.map(([k, v]) => `${k}:${v.trim()}`).join('\n');

    const canonicalRequest = this.createCanonicalRequest(
      'GET',
      '/',
      '',
      signedHeaders,
      canonicalHeaders,
      payloadHash
    );

    const encoder = new util.TextEncoder();
    const canonicalRequestHash = await this.sha256Hex(encoder.encodeInto(canonicalRequest).buffer as ArrayBuffer);
    const credentialScope = this.createCredentialScope(dateStamp);
    const stringToSign = this.createStringToSign(amzDate, dateStamp, credentialScope, canonicalRequestHash);

    const kSecret = encoder.encodeInto('AWS4' + this.secretAccessKey);
    const kDate = await this.hmacSha256(kSecret, dateStamp);
    const kRegion = await this.hmacSha256(kDate, this.region);
    const kService = await this.hmacSha256(kRegion, S3SignatureV4.SERVICE);
    const kSigning = await this.hmacSha256(kService, S3SignatureV4.TERMINATOR);
    const signature = await this.hmacSha256(kSigning, stringToSign);
    const signatureHex = new util.HexHelper().encodeToStringSync(signature);

    const authorization = this.buildAuthorizationHeader(dateStamp, signedHeaders, signatureHex);
    headers.set('authorization', authorization);

    return headers;
  }
```

- [ ] **Step 4: 提交代码**

```bash
git add entry/src/main/ets/storage/s3/S3SignatureV4.ets
git commit -m "feat(s3): implement AWS Signature V4 signing algorithm

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 4: XML 解析器 (S3XmlParser.ets)

**Files:**
- Create: `entry/src/main/ets/storage/s3/S3XmlParser.ets`

- [ ] **Step 1: 创建 S3XmlParser.ets 文件**

```typescript
import { xml, util } from '@kit.ArkTS';
import { S3Bucket, S3Object, S3Error } from './S3Types';

/**
 * S3 XML 响应解析器
 */
export class S3XmlParser {
  /**
   * 解析 ListBuckets 响应
   */
  public static parseListBuckets(xmlStr: string): S3Bucket[] {
    const buckets: S3Bucket[] = [];
    const encoder = new util.TextEncoder();
    const arrBuffer = encoder.encodeInto(xmlStr);
    const parser = new xml.XmlPullParser(arrBuffer.buffer as ArrayBuffer, 'UTF-8');

    let currentBucket: Partial<S3Bucket> = {};
    let currentText = '';
    let inBucket = false;

    const options: xml.ParseOptions = {
      supportDoctype: true,
      ignoreNameSpace: true,
      tokenValueCallbackFunction: (eventType: xml.EventType, value: xml.ParseInfo) => {
        const nodeName = value.getName()?.toLowerCase() ?? '';

        if (eventType === xml.EventType.START_TAG) {
          if (nodeName === 'bucket') {
            inBucket = true;
            currentBucket = {};
          }
        } else if (eventType === xml.EventType.TEXT) {
          currentText = value.getText() ?? '';
        } else if (eventType === xml.EventType.END_TAG) {
          if (nodeName === 'bucket') {
            if (currentBucket.name) {
              buckets.push({
                name: currentBucket.name,
                creationDate: currentBucket.creationDate ?? 0
              });
            }
            inBucket = false;
            currentBucket = {};
          } else if (inBucket) {
            if (nodeName === 'name') {
              currentBucket.name = currentText;
            } else if (nodeName === 'creationdate') {
              currentBucket.creationDate = new Date(currentText).getTime();
            }
          }
        }
        return true;
      }
    };

    parser.parseXml(options);
    return buckets;
  }

  /**
   * 解析 ListObjects 响应
   */
  public static parseListObjects(xmlStr: string): S3Object[] {
    const objects: S3Object[] = [];
    const encoder = new util.TextEncoder();
    const arrBuffer = encoder.encodeInto(xmlStr);
    const parser = new xml.XmlPullParser(arrBuffer.buffer as ArrayBuffer, 'UTF-8');

    let currentObject: Partial<S3Object> = {};
    let currentText = '';
    let inContents = false;

    const options: xml.ParseOptions = {
      supportDoctype: true,
      ignoreNameSpace: true,
      tokenValueCallbackFunction: (eventType: xml.EventType, value: xml.ParseInfo) => {
        const nodeName = value.getName()?.toLowerCase() ?? '';

        if (eventType === xml.EventType.START_TAG) {
          if (nodeName === 'contents') {
            inContents = true;
            currentObject = {};
          }
        } else if (eventType === xml.EventType.TEXT) {
          currentText = value.getText() ?? '';
        } else if (eventType === xml.EventType.END_TAG) {
          if (nodeName === 'contents') {
            if (currentObject.key) {
              objects.push({
                key: currentObject.key,
                size: currentObject.size ?? 0,
                lastModified: currentObject.lastModified ?? 0,
                etag: currentObject.etag ?? ''
              });
            }
            inContents = false;
            currentObject = {};
          } else if (inContents) {
            if (nodeName === 'key') {
              currentObject.key = currentText;
            } else if (nodeName === 'size') {
              currentObject.size = parseInt(currentText, 10) || 0;
            } else if (nodeName === 'lastmodified') {
              currentObject.lastModified = new Date(currentText).getTime();
            } else if (nodeName === 'etag') {
              currentObject.etag = currentText.replace(/"/g, '');
            }
          }
        }
        return true;
      }
    };

    parser.parseXml(options);
    return objects;
  }

  /**
   * 解析错误响应
   */
  public static parseError(xmlStr: string): S3Error {
    const error: S3Error = { code: '', message: '' };
    const encoder = new util.TextEncoder();
    const arrBuffer = encoder.encodeInto(xmlStr);
    const parser = new xml.XmlPullParser(arrBuffer.buffer as ArrayBuffer, 'UTF-8');

    let currentText = '';

    const options: xml.ParseOptions = {
      supportDoctype: true,
      ignoreNameSpace: true,
      tokenValueCallbackFunction: (eventType: xml.EventType, value: xml.ParseInfo) => {
        const nodeName = value.getName()?.toLowerCase() ?? '';

        if (eventType === xml.EventType.TEXT) {
          currentText = value.getText() ?? '';
        } else if (eventType === xml.EventType.END_TAG) {
          if (nodeName === 'code') {
            error.code = currentText;
          } else if (nodeName === 'message') {
            error.message = currentText;
          } else if (nodeName === 'resourceid') {
            error.resourceId = currentText;
          } else if (nodeName === 'resource') {
            error.resource = currentText;
          }
        }
        return true;
      }
    };

    parser.parseXml(options);
    return error;
  }
}
```

- [ ] **Step 2: 提交代码**

```bash
git add entry/src/main/ets/storage/s3/S3XmlParser.ets
git commit -m "feat(s3): add S3 XML response parser

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 5: S3 客户端 (S3Client.ets)

**Files:**
- Create: `entry/src/main/ets/storage/s3/S3Client.ets`

- [ ] **Step 1: 创建 S3Client.ets 文件 - 第一部分（类型和构造函数）**

```typescript
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

  /**
   * 初始化 HTTP Session
   */
  private initSession(): void {
    this.session = rcp.createSession({
      requestConfiguration: {
        transfer: {
          timeout: { connectMs: this.options.timeout }
        }
      }
    });
  }

  /**
   * 构建请求 URL
   */
  private buildUrl(bucket: string, key: string): string {
    const endpoint = this.options.endpoint.endsWith('/')
      ? this.options.endpoint.slice(0, -1)
      : this.options.endpoint;

    if (this.options.pathStyle) {
      // 路径样式: https://endpoint/bucket/key
      return `${endpoint}/${bucket}/${key}`;
    } else {
      // 虚拟主机样式: https://bucket.endpoint/key
      const url = new URL(endpoint);
      return `${url.protocol}//${bucket}.${url.host}/${key}`;
    }
  }

  /**
   * 将 Map 转换为 rcp.Headers
   */
  private headersToRecord(headers: Map<string, string>): rcp.Headers {
    const record: rcp.Headers = {};
    headers.forEach((value, key) => {
      record[key] = value;
    });
    return record;
  }

  /**
   * 处理响应
   */
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
      // 解析错误信息
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

  /**
   * 关闭连接
   */
  public close(): void {
    this.session?.close();
    this.session = null;
  }
}
```

- [ ] **Step 2: 添加 Bucket 操作方法**

在 `S3Client` 类中添加以下方法：

```typescript
  /**
   * 列出所有存储桶
   */
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

  /**
   * 检查存储桶是否存在
   */
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
```

- [ ] **Step 3: 添加 Object 操作方法**

在 `S3Client` 类中添加以下方法：

```typescript
  /**
   * 列出存储桶内的对象
   */
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

  /**
   * 获取对象（下载）
   */
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

  /**
   * 上传对象
   */
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

  /**
   * 删除对象
   */
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

  /**
   * 获取对象元数据
   */
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

  /**
   * 测试连接
   */
  public async testConnection(): Promise<S3Result<void>> {
    return this.listBuckets().then(result => {
      if (result.success) {
        return { success: true, statusCode: 200 };
      }
      return { success: false, statusCode: result.statusCode, message: result.message };
    });
  }
```

- [ ] **Step 4: 提交代码**

```bash
git add entry/src/main/ets/storage/s3/S3Client.ets
git commit -m "feat(s3): implement S3 HTTP client

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 6: S3 存储实现 (S3Storage.ets)

**Files:**
- Create: `entry/src/main/ets/storage/s3/S3Storage.ets`

- [ ] **Step 1: 创建 S3Storage.ets 文件**

```typescript
import { FileInfo, FileType, IFileStorage, PageConfig, StorageConfig } from '..';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { StorageError, StorageErrorCodes } from '../StorageError';
import { S3StorageConfig, S3PageConfig } from './S3Config';
import { S3Client } from './S3Client';
import { FilenameUtils } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'S3Storage';

/**
 * S3 存储实现
 */
export class S3Storage implements IFileStorage {
  private config: S3StorageConfig | undefined;
  private client: S3Client | undefined;

  constructor(config?: S3StorageConfig) {
    if (config) {
      this.init(config);
    }
  }

  /**
   * 获取页面配置
   */
  public getPageConfig(): PageConfig {
    return S3PageConfig;
  }

  /**
   * 初始化存储配置
   */
  public init(config: StorageConfig): void {
    this.config = this.parseConfig(config);
    this.client = new S3Client({
      endpoint: this.config.endpoint,
      accessKeyId: this.config.getAccessKeyIdText(),
      secretAccessKey: this.config.getSecretAccessKeyText(),
      region: this.config.region,
      pathStyle: this.config.pathStyle,
      timeout: this.config.timeout
    });
  }

  /**
   * 解析配置
   */
  private parseConfig(config: StorageConfig): S3StorageConfig {
    if (config instanceof S3StorageConfig) {
      return config;
    }
    const inputConfig = config as Record<string, Object>;
    return new S3StorageConfig(
      inputConfig['endpoint'] as string,
      inputConfig['accessKeyId'] as string,
      inputConfig['secretAccessKey'] as string,
      {
        region: inputConfig['region'] as string | undefined,
        bucket: inputConfig['bucket'] as string | undefined,
        pathStyle: inputConfig['pathStyle'] as boolean | undefined,
        timeout: inputConfig['timeout'] as number | undefined
      }
    );
  }

  /**
   * 解析路径，返回 bucket 和 key
   */
  private parsePath(path: string): { bucket: string; key: string } {
    // 路径格式: bucket/key 或 key（使用默认 bucket）
    const parts = path.split('/').filter(p => p.length > 0);

    if (this.config?.bucket) {
      // 有默认 bucket，整个 path 作为 key
      return {
        bucket: this.config.bucket,
        key: path.startsWith('/') ? path.substring(1) : path
      };
    }

    // 无默认 bucket，第一部分是 bucket
    if (parts.length < 2) {
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, 'Invalid path format');
    }

    return {
      bucket: parts[0],
      key: parts.slice(1).join('/')
    };
  }

  /**
   * 获取文件名
   */
  private getFileName(key: string): string {
    const parts = key.split('/');
    return parts[parts.length - 1] || key;
  }

  /**
   * 读取文件内容
   */
  public async read(path: string): Promise<ArrayBuffer> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const { bucket, key } = this.parsePath(path);
    const result = await this.client.getObject(bucket, key);

    if (!result.success || !result.data) {
      throw new StorageError(StorageErrorCodes.FILE_READ_ERROR, result.message);
    }

    return result.data;
  }

  /**
   * 写入文件内容
   */
  public async write(path: string, content: ArrayBuffer): Promise<void> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const { bucket, key } = this.parsePath(path);
    const result = await this.client.putObject(bucket, key, content);

    if (!result.success) {
      throw new StorageError(StorageErrorCodes.FILE_WRITE_ERROR, result.message);
    }
  }

  /**
   * 检查文件是否存在
   */
  public async exists(path: string): Promise<boolean> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    try {
      const { bucket, key } = this.parsePath(path);
      const result = await this.client.headObject(bucket, key);
      return result.success;
    } catch {
      return false;
    }
  }

  /**
   * 获取文件信息
   */
  public async getInfo(path: string): Promise<FileInfo> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const { bucket, key } = this.parsePath(path);
    const result = await this.client.headObject(bucket, key);

    if (!result.success || !result.data) {
      throw new StorageError(StorageErrorCodes.FILE_INFO_ERROR, result.message);
    }

    return {
      name: this.getFileName(key),
      size: result.data.size,
      modifiedTime: result.data.lastModified,
      path: path,
      type: FileType.FILE,
      childrenCount: 0
    };
  }

  /**
   * 获取目录内容
   */
  public async listDir(path: string): Promise<FileInfo[]> {
    if (!this.client) {
      throw new StorageError(StorageErrorCodes.CLIENT_UNDEFINED, 'S3 not initialized');
    }

    const { bucket, key: prefix } = this.parsePath(path);
    const result = await this.client.listObjects(bucket, prefix);

    if (!result.success || !result.data) {
      throw new StorageError(StorageErrorCodes.NOT_IMPLEMENTED, result.message);
    }

    // 转换 S3Object 为 FileInfo
    const files: FileInfo[] = [];
    for (const obj of result.data) {
      // 过滤掉目录本身
      if (obj.key === prefix || obj.key === prefix + '/') {
        continue;
      }

      files.push({
        name: this.getFileName(obj.key),
        size: obj.size,
        modifiedTime: obj.lastModified,
        path: `${bucket}/${obj.key}`,
        type: obj.key.endsWith('/') ? FileType.DIR : FileType.FILE,
        childrenCount: 0
      });
    }

    return files;
  }
}
```

- [ ] **Step 2: 提交代码**

```bash
git add entry/src/main/ets/storage/s3/S3Storage.ets
git commit -m "feat(s3): implement S3Storage with IFileStorage interface

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 7: 配置页面 (S3Page.ets)

**Files:**
- Create: `entry/src/main/ets/storage/s3/S3Page.ets`

- [ ] **Step 1: 创建 S3Page.ets 文件 - 第一部分（状态和初始化）**

```typescript
import { Router } from '@kit.ArkUI';
import { StorageConfig, StorageType, FileType } from '..';
import { S3StorageConfig } from './S3Config';
import { S3Storage } from './S3Storage';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { CommonUtils, FilenameUtils, ResourceManager, WindowUtils } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FileService } from '../../services/FileService';
import { LocationParam } from '../../services/beans/LocationParam';
import { common } from '@kit.AbilityKit';

const DOMAIN = 0x0000;
const TAG = 'S3Page';

@Entry
@Component
struct S3Page {
  @State endpoint: string = '';
  @State accessKeyId: string = '';
  @State secretAccessKey: string = '';
  @State region: string = 'us-east-1';
  @State bucket: string = '';
  @State pathStyle: boolean = false;
  @State timeout: string = '30000';
  @State filePath: string = '';
  @State showAdvanced: boolean = false;
  @State isLoading: boolean = false;
  @State isConnecting: boolean = false;
  @State connectionStatus: string = '';
  @State isErrorStatus: boolean = false;

  private fileManager: KdbxFileManager = new KdbxFileManager(StorageType.S3);
  private router: Router = this.getUIContext().getRouter();

  aboutToAppear(): void {
    this.initSaveParam();
  }

  onPageShow(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
    this.connectionStatus = '';
  }

  // 导出数据初始化
  private initSaveParam() {
    if (!LocationParam.isSaveMode()) {
      return;
    }
    const dbFileParam = FileService.getDbFileParam();
    if (!(dbFileParam.storageType === StorageType.S3)) {
      this.filePath = LocationParam.getFileName();
      return;
    }
    const storageConfig = dbFileParam.storageConfig as S3StorageConfig;
    if (storageConfig) {
      this.endpoint = storageConfig.endpoint;
      this.accessKeyId = storageConfig.getAccessKeyIdText();
      this.secretAccessKey = storageConfig.getSecretAccessKeyText();
      this.region = storageConfig.region || 'us-east-1';
      this.bucket = storageConfig.bucket || '';
      this.pathStyle = storageConfig.pathStyle;
      this.timeout = storageConfig.timeout?.toString() || '30000';
      this.filePath = FilenameUtils.replaceFileName(dbFileParam.filePath, LocationParam.getFileName());
    }
  }
```

- [ ] **Step 2: 添加交互方法**

在 `S3Page` 组件中添加以下方法：

```typescript
  // 参数校验
  private checkParam(): boolean {
    if (!this.endpoint) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.s3_endpoint_empty')) });
      return false;
    }
    if (!this.accessKeyId) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.s3_access_key_empty')) });
      return false;
    }
    if (!this.secretAccessKey) {
      CommonUtils.showToast({ message: ResourceManager.getString($r('app.string.s3_secret_key_empty')) });
      return false;
    }
    return true;
  }

  // 获取存储配置
  private getStorageConfig(): S3StorageConfig {
    return new S3StorageConfig(
      this.endpoint,
      this.accessKeyId,
      this.secretAccessKey,
      {
        region: this.region,
        bucket: this.bucket || undefined,
        pathStyle: this.pathStyle,
        timeout: parseInt(this.timeout, 10) || 30000
      }
    );
  }

  // 测试连接
  private async testConnection() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      const storageConfig = this.getStorageConfig();
      const storage = new S3Storage(storageConfig);
      // 测试：尝试列出存储桶
      const exists = await storage.exists('/');
      this.connectionStatus = ResourceManager.getString($r('app.string.connection_success'));
      this.isErrorStatus = false;
    } catch (error) {
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
      hilog.error(DOMAIN, TAG, 'S3 connection error: %{public}s', this.connectionStatus);
    } finally {
      this.isConnecting = false;
    }
  }

  // 处理确认事件
  private handleConfirm() {
    if (LocationParam.isSaveMode()) {
      this.selectDir();
    } else {
      this.selectFile();
    }
  }

  // 跳转到文件列表页面
  private toFileList() {
    if (!this.checkParam()) {
      return;
    }
    CommonUtils.pushUrl({
      url: 'pages/open/FileList',
      params: {
        mode: LocationParam.getMode(),
        filePath: this.filePath,
        fileSuffix: LocationParam.getFileSuffix(),
        fileName: LocationParam.getFileName(),
        storageType: StorageType.S3,
        storageConfig: this.getStorageConfig()
      }
    });
  }

  // 选择文件（导入模式）
  private async selectFile() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      const storageConfig = this.getStorageConfig();
      const fileInfo = await this.fileManager.init(storageConfig).getInfo(this.filePath);

      if (fileInfo.type === FileType.DIR) {
        this.toFileList();
      } else {
        LocationParam.callOnLocation({
          mode: LocationParam.getMode(),
          filePath: this.filePath,
          fileName: fileInfo.name,
          fileSuffix: LocationParam.getFileSuffix(),
          storageType: StorageType.S3,
          storageConfig: storageConfig
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load file: %{public}s', error.message);
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
      CommonUtils.showToast({ message: error.message });
    } finally {
      this.isConnecting = false;
    }
  }

  // 保存文件（导出模式）
  private async selectDir() {
    if (!this.checkParam()) {
      return;
    }
    this.isConnecting = true;
    this.connectionStatus = ResourceManager.getString($r('app.string.connecting'));
    this.isErrorStatus = false;

    try {
      const storageConfig = this.getStorageConfig();
      this.fileManager.init(storageConfig);
      const existsFile = await this.fileManager.exists(this.filePath);

      if (existsFile) {
        const fileInfo = await this.fileManager.getInfo(this.filePath);
        if (fileInfo.type === FileType.DIR) {
          this.toFileList();
          return;
        }
      }

      LocationParam.callOnLocation({
        mode: LocationParam.getMode(),
        filePath: this.filePath,
        fileName: FilenameUtils.getFileName(this.filePath),
        fileSuffix: LocationParam.getFileSuffix(),
        storageType: StorageType.S3,
        storageConfig: storageConfig
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to export file: %{public}s', error.message);
      this.connectionStatus = error.message;
      this.isErrorStatus = true;
    } finally {
      this.isConnecting = false;
    }
  }
```

- [ ] **Step 3: 添加 UI 构建方法**

在 `S3Page` 组件中添加 build 方法：

```typescript
  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r('app.media.ic_angle_left'))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back();
          })

        Text($r('app.string.s3_button_title'))
          .fontSize(18)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)

      // 主要内容区域
      Scroll() {
        Column() {
          // 服务端点
          Row() {
            Text('*').fontColor($r('app.color.required'))
            Text($r('app.string.s3_endpoint'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            TextInput({ text: this.endpoint, placeholder: 'https://s3.amazonaws.com' })
              .height(40)
              .width('60%')
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.card_bg'))
              .onChange((value: string) => {
                this.endpoint = value;
              })
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          Text($r('app.string.s3_endpoint_hint'))
            .fontSize(12)
            .fontColor($r('app.color.text_secondary'))
            .width('100%')
            .margin({ top: 4 })

          // Access Key ID
          Row() {
            Text('*').fontColor($r('app.color.required'))
            Text($r('app.string.s3_access_key_id'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            TextInput({ text: this.accessKeyId })
              .height(40)
              .width('60%')
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.card_bg'))
              .onChange((value: string) => {
                this.accessKeyId = value;
              })
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          // Secret Access Key
          Row() {
            Text('*').fontColor($r('app.color.required'))
            Text($r('app.string.s3_secret_access_key'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            TextInput({ text: this.secretAccessKey })
              .height(40)
              .width('60%')
              .type(InputType.Password)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.card_bg'))
              .onChange((value: string) => {
                this.secretAccessKey = value;
              })
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          // 文件路径
          Row() {
            Text($r('app.string.file_path'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            TextArea({ text: this.filePath })
              .minLines(1)
              .maxLines(3)
              .padding({ top: 12, bottom: 12 })
              .width('60%')
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r('app.color.card_bg'))
              .onChange((value: string) => {
                this.filePath = value;
              })
          }
          .width('100%')
          .height('auto')
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          // 高级设置
          Row() {
            Text($r('app.string.s3_advanced_settings'))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Blank()
            Toggle({ type: ToggleType.Switch, isOn: this.showAdvanced })
              .onChange((isOn: boolean) => {
                this.showAdvanced = isOn;
              })
          }
          .width('100%')
          .height(40)
          .margin({ top: 20 })
          .alignItems(VerticalAlign.Center)

          // 高级设置内容
          if (this.showAdvanced) {
            Column() {
              // 区域
              Row() {
                Text($r('app.string.s3_region'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                TextInput({ text: this.region })
                  .height(36)
                  .width('60%')
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.card_bg'))
                  .onChange((value: string) => {
                    this.region = value;
                  })
              }
              .width('100%')
              .height(36)
              .margin({ top: 12 })
              .alignItems(VerticalAlign.Center)

              // 默认存储桶
              Row() {
                Text($r('app.string.s3_default_bucket'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                TextInput({ text: this.bucket })
                  .height(36)
                  .width('60%')
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.card_bg'))
                  .onChange((value: string) => {
                    this.bucket = value;
                  })
              }
              .width('100%')
              .height(36)
              .margin({ top: 12 })
              .alignItems(VerticalAlign.Center)

              // URL 样式
              Row() {
                Text($r('app.string.s3_url_style'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                Row() {
                  Radio({ value: 'virtual', group: 'urlStyle' })
                    .checked(!this.pathStyle)
                    .onChange((isChecked: boolean) => {
                      if (isChecked) this.pathStyle = false;
                    })
                  Text($r('app.string.s3_virtual_host_style'))
                    .fontSize(12)
                    .margin({ right: 16 })

                  Radio({ value: 'path', group: 'urlStyle' })
                    .checked(this.pathStyle)
                    .onChange((isChecked: boolean) => {
                      if (isChecked) this.pathStyle = true;
                    })
                  Text($r('app.string.s3_path_style_url'))
                    .fontSize(12)
                }
              }
              .width('100%')
              .height(36)
              .margin({ top: 12 })
              .alignItems(VerticalAlign.Center)

              // 超时时间
              Row() {
                Text($r('app.string.s3_timeout'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_primary'))
                Blank()
                TextInput({ text: this.timeout })
                  .height(36)
                  .width('60%')
                  .type(InputType.Number)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.card_bg'))
                  .onChange((value: string) => {
                    this.timeout = value;
                  })
              }
              .width('100%')
              .height(36)
              .margin({ top: 12 })
              .alignItems(VerticalAlign.Center)
            }
            .width('100%')
            .padding(12)
            .backgroundColor($r('app.color.card_bg'))
            .borderRadius(8)
            .margin({ top: 8 })
          }

          // 连接状态
          if (this.connectionStatus) {
            Text(this.connectionStatus)
              .fontSize(14)
              .margin({ top: 10 })
              .fontColor(this.isErrorStatus ? $r('app.color.error') : $r('app.color.success'))
          }

          // 加载中状态
          if (this.isConnecting) {
            Row() {
              LoadingProgress()
                .width(50)
                .height(50)
                .color($r('app.color.text_primary'))
              Text($r('app.string.connecting'))
                .fontSize(16)
                .margin({ left: 16 })
                .fontColor($r('app.color.text_primary'))
            }
            .width('100%')
            .justifyContent(FlexAlign.Center)
            .margin({ top: 20 })
          }

          // 按钮
          Row() {
            Button($r('app.string.test_connection'))
              .height(40)
              .backgroundColor(Color.Gray)
              .fontColor(Color.White)
              .enabled(!this.isConnecting)
              .onClick(() => {
                this.testConnection();
              })
            Blank()
            Button($r('app.string.confirm_button_text'))
              .height(40)
              .backgroundColor($r('app.color.button_bg_blue'))
              .fontColor($r('app.color.button_text_blue'))
              .onClick(() => {
                this.handleConfirm();
              })
          }
          .width('100%')
          .margin({ top: 20 })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })
        .alignItems(HorizontalAlign.Start)
      }
      .width('100%')
      .layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
```

- [ ] **Step 4: 提交代码**

```bash
git add entry/src/main/ets/storage/s3/S3Page.ets
git commit -m "feat(s3): add S3 configuration page

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 8: 集成到存储系统

**Files:**
- Modify: `entry/src/main/ets/storage/StorageType.ets`
- Modify: `entry/src/main/ets/storage/FileStorageFactory.ets`
- Modify: `entry/src/main/ets/storage/index.ets`
- Modify: `entry/src/main/resources/base/profile/main_pages.json`

- [ ] **Step 1: 添加 S3 到 StorageType 枚举**

修改 `entry/src/main/ets/storage/StorageType.ets`：

```typescript
/**
 * 存储类型枚举
 * 定义了支持的文件存储类型
 */
export enum StorageType {
  /**
   * 本地文件存储
   */
  LOCAL = 'LOCAL',

  /**
   * WebDAV存储
   */
  WEBDAV = 'WEBDAV',

  /**
   * FTP存储
   */
  FTP = 'FTP',

  /**
   * Microsoft OneDrive存储
   */
  ONEDRIVE = 'ONEDRIVE',

  /**
   * S3兼容存储
   */
  S3 = 'S3'
}
```

- [ ] **Step 2: 注册 S3Storage 到工厂**

修改 `entry/src/main/ets/storage/FileStorageFactory.ets`，添加导入和注册：

在文件顶部添加导入：
```typescript
import { S3Storage } from './s3/S3Storage';
```

在构造函数中添加注册：
```typescript
private constructor() {
  this.registerStorage(StorageType.LOCAL, new LocalFileStorage());
  this.registerStorage(StorageType.WEBDAV, new WebDAVStorage());
  this.registerStorage(StorageType.ONEDRIVE, new OneDriveStorage());
  this.registerStorage(StorageType.FTP, new FTPStorage());
  this.registerStorage(StorageType.S3, new S3Storage());
}
```

- [ ] **Step 3: 导出 S3 模块**

修改 `entry/src/main/ets/storage/index.ets`，添加导出：

```typescript
export * from './IFileStorage';

export * from './StorageType';

export * from './FileStorageFactory';

export * from './StorageConfig';
export * from './local/LocalFileStorage';
export * from './local/LocalFileConfig';
export * from './cache/CacheConstants';

// S3 存储
export * from './s3/S3Types';
export * from './s3/S3Config';
export * from './s3/S3Storage';
```

- [ ] **Step 4: 添加页面路由**

修改 `entry/src/main/resources/base/profile/main_pages.json`：

```json
{
  "src": [
    "pages/Index",
    "pages/DatabaseView",
    "pages/setting/Settings",
    "pages/setting/SettingSecurity",
    "pages/setting/SettingDatabase",
    "pages/setting/SettingDatabaseMeta",
    "pages/setting/SettingCustomIcons",
    "pages/setting/SettingDatabaseKeyFunction",
    "pages/setting/SettingDatabaseProtectedFiled",
    "pages/setting/SettingApplication",
    "pages/Password",
    "pages/RecentFiles",
    "pages/EntryEdit",
    "pages/EntryView",
    "pages/TotpView",
    "pages/TemplateEntryCreate",
    "pages/about/About",
    "pages/about/Support",
    "pages/UnLockDatabase",
    "pages/ChangePassword",
    "pages/open/SelectLocation",
    "pages/open/FileList",
    "pages/open/CreateDatabase",
    "storage/local/LocalFilePage",
    "storage/webdav/WebDAVPage",
    "storage/onedrive/OneDrivePage",
    "storage/ftp/FTPPage",
    "storage/s3/S3Page",
    "pages/OAuth2Login"
  ]
}
```

- [ ] **Step 5: 提交代码**

```bash
git add entry/src/main/ets/storage/StorageType.ets \
        entry/src/main/ets/storage/FileStorageFactory.ets \
        entry/src/main/ets/storage/index.ets \
        entry/src/main/resources/base/profile/main_pages.json
git commit -m "feat(s3): integrate S3 storage into storage system

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 9: 添加资源文件

**Files:**
- Modify: `entry/src/main/resources/base/element/string.json`
- Create: `entry/src/main/resources/base/media/ic_s3.png`

- [ ] **Step 1: 添加字符串资源**

在 `entry/src/main/resources/base/element/string.json` 中添加以下字符串：

```json
{
  "name": "s3_button_title",
  "value": "S3 存储"
},
{
  "name": "s3_select_file",
  "value": "从 S3 存储选择文件"
},
{
  "name": "s3_save_file",
  "value": "保存到 S3 存储"
},
{
  "name": "s3_endpoint",
  "value": "服务端点"
},
{
  "name": "s3_endpoint_hint",
  "value": "支持 AWS S3、MinIO、阿里云 OSS 等"
},
{
  "name": "s3_endpoint_empty",
  "value": "请输入服务端点"
},
{
  "name": "s3_access_key_id",
  "value": "Access Key ID"
},
{
  "name": "s3_access_key_empty",
  "value": "请输入 Access Key ID"
},
{
  "name": "s3_secret_access_key",
  "value": "Secret Access Key"
},
{
  "name": "s3_secret_key_empty",
  "value": "请输入 Secret Access Key"
},
{
  "name": "s3_region",
  "value": "区域"
},
{
  "name": "s3_default_bucket",
  "value": "默认存储桶"
},
{
  "name": "s3_url_style",
  "value": "URL 样式"
},
{
  "name": "s3_virtual_host_style",
  "value": "虚拟主机"
},
{
  "name": "s3_path_style_url",
  "value": "路径样式"
},
{
  "name": "s3_timeout",
  "value": "超时时间"
},
{
  "name": "s3_advanced_settings",
  "value": "高级设置"
}
```

- [ ] **Step 2: 添加图标资源**

将 S3 图标文件 `ic_s3.png` 放置到 `entry/src/main/resources/base/media/` 目录。

如果暂时没有图标，可以复制现有图标作为占位符：
```bash
cp entry/src/main/resources/base/media/ic_ftp.png entry/src/main/resources/base/media/ic_s3.png
```

- [ ] **Step 3: 提交代码**

```bash
git add entry/src/main/resources/base/element/string.json \
        entry/src/main/resources/base/media/ic_s3.png
git commit -m "feat(s3): add S3 storage resources (strings and icon)

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## Task 10: 构建验证

**Files:**
- 无文件修改，仅验证

- [ ] **Step 1: 运行构建命令**

```bash
cd D:\workspace\harmonyos\kee-pass-ho
hvigorw --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
```

预期结果：构建成功，无编译错误。

- [ ] **Step 2: 修复任何编译错误**

如果构建失败，根据错误信息修复代码，然后重新构建。

- [ ] **Step 3: 最终提交（如有修复）**

如果有任何修复，提交修复：

```bash
git add .
git commit -m "fix(s3): fix build errors

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

---

## 自检清单

完成实现后，检查以下内容：

- [ ] S3Types.ets 包含所有必要的类型定义
- [ ] S3Config.ets 正确加密存储敏感信息
- [ ] S3SignatureV4.ets 实现完整的 AWS SigV4 签名算法
- [ ] S3XmlParser.ets 能正确解析 ListBuckets、ListObjects 和错误响应
- [ ] S3Client.ets 实现所有必要的 API 操作
- [ ] S3Storage.ets 正确实现 IFileStorage 接口
- [ ] S3Page.ets UI 与其他存储页面风格一致
- [ ] StorageType.S3 已添加到枚举
- [ ] S3Storage 已注册到 FileStorageFactory
- [ ] S3Page 路由已添加到 main_pages.json
- [ ] 所有字符串资源已添加
- [ ] 构建成功无错误
