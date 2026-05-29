# S3 兼容存储功能设计文档

## 概述

为 KeePassHO 添加 S3 兼容存储支持，允许用户从 AWS S3、MinIO、阿里云 OSS、腾讯云 COS、华为云 OBS、Cloudflare R2 等 S3 兼容服务打开和保存 KeePass 数据库文件。

## 需求

### 功能需求

- 支持 S3 协议兼容的存储服务
- 支持基本文件操作：上传、下载、删除、列表
- 支持 Bucket 浏览功能
- 支持高级配置参数（区域、超时等）
- 支持连接测试功能
- 使用固定密钥认证（Access Key ID + Secret Access Key）

### 非功能需求

- 复用现有存储架构模式
- 使用 HarmonyOS 原生 API 实现签名算法
- 敏感信息加密存储
- 与现有存储类型保持一致的 UI 风格

## 架构设计

### 模块结构

```
entry/src/main/ets/storage/s3/
├── S3Config.ets          # 配置类（endpoint、accessKey、secretKey、region、bucket）
├── S3Storage.ets         # IFileStorage 实现
├── S3Client.ets          # S3 HTTP 客户端，封装 API 调用
├── S3SignatureV4.ets     # AWS Signature V4 签名算法实现
├── S3XmlParser.ets       # XML 响应解析器
├── S3Page.ets            # 配置页面
└── S3Types.ets           # 类型定义（S3Object、S3Bucket 等）
```

### 类职责

| 类名 | 职责 |
|------|------|
| `S3Storage` | 实现 `IFileStorage` 接口，协调各组件 |
| `S3Client` | 封装 HTTP 请求，管理 Session 连接 |
| `S3SignatureV4` | 生成 AWS SigV4 签名头 |
| `S3XmlParser` | 解析 S3 XML 响应 |
| `S3Config` | 存储配置信息，敏感字段加密 |
| `S3Page` | 用户配置界面 |

### 与现有架构的关系

- **复用**：`Sm4Utils`（敏感信息加密）、`StorageError`（错误处理）、`CacheStorage`（自动缓存装饰）
- **遵循**：`IFileStorage` 接口规范、`FileStorageFactory` 注册模式

## 详细设计

### 1. 类型定义 (S3Types.ets)

```typescript
// S3 对象信息
export interface S3Object {
  key: string;           // 对象键（路径）
  size: number;          // 大小（字节）
  lastModified: number;  // 最后修改时间戳
  etag: string;          // ETag
}

// S3 存储桶信息
export interface S3Bucket {
  name: string;
  creationDate: number;
}

// API 响应结果
export interface S3Result<T> {
  success: boolean;
  statusCode: number;
  message?: string;
  data?: T;
}
```

### 2. 配置类 (S3Config.ets)

```typescript
export interface S3ConfigOptions {
  region?: string;           // 区域，默认 us-east-1
  bucket?: string;           // 默认存储桶
  pathStyle?: boolean;       // 是否使用路径样式 URL，默认 false
  timeout?: number;          // 超时时间（毫秒）
}

export class S3StorageConfig implements StorageConfig {
  endpoint: string;          // 服务端点
  accessKeyId: string;       // 加密存储
  secretAccessKey: string;   // 加密存储
  region: string;
  bucket?: string;
  pathStyle: boolean;
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

  public getAccessKeyIdText(): string {
    return Sm4Utils.decryptWithPrefix(this.accessKeyId);
  }

  public getSecretAccessKeyText(): string {
    return Sm4Utils.decryptWithPrefix(this.secretAccessKey);
  }
}

export const S3PageConfig: PageConfig = {
  icon: $r('app.media.ic_s3'),
  title: $r('app.string.s3_button_title'),
  selectDesc: $r('app.string.s3_select_file'),
  saveDesc: $r('app.string.s3_save_file'),
  pageUrl: 'storage/s3/S3Page',
  storageType: StorageType.S3
};
```

### 3. 签名算法 (S3SignatureV4.ets)

AWS Signature Version 4 签名流程：

```
1. 创建规范请求
   ├── HTTP Method (GET/PUT/DELETE等)
   ├── URI (请求路径)
   ├── Query String (查询参数)
   ├── Headers (排序后的请求头)
   └── Payload Hash (请求体 SHA256 哈希)

2. 创建待签名字符串
   ├── Algorithm (AWS4-HMAC-SHA256)
   ├── Timestamp (当前时间 UTC)
   ├── Credential Scope (日期/区域/s3/aws4_request)
   └── Canonical Request Hash (规范请求的 SHA256)

3. 计算签名
   └── 使用 Secret Access Key 逐层 HMAC-SHA256
       ├── HMAC(SecretKey + Date)
       ├── HMAC(上一步结果 + Region)
       ├── HMAC(上一步结果 + "s3")
       ├── HMAC(上一步结果 + "aws4_request")
       └── HMAC(上一步结果 + StringToSign)
```

```typescript
export class S3SignatureV4 {
  private accessKeyId: string;
  private secretAccessKey: string;
  private region: string;

  constructor(accessKeyId: string, secretAccessKey: string, region: string) {
    this.accessKeyId = accessKeyId;
    this.secretAccessKey = secretAccessKey;
    this.region = region;
  }

  /**
   * 签名请求，返回需要添加的 Headers
   */
  public signRequest(
    method: string,
    uri: string,
    queryString: string,
    headers: Map<string, string>,
    payload: ArrayBuffer | null
  ): Map<string, string>;

  // 私有方法
  private sha256Hex(data: ArrayBuffer | null): string;
  private createCanonicalRequest(...): string;
  private createStringToSign(...): string;
  private calculateSignature(dateStamp: string, stringToSign: string): string;
  private hmacSha256(key: Uint8Array, data: string): Uint8Array;
  private buildAuthorizationHeader(dateStamp: string, headers: Map<string, string>, signature: string): string;
}
```

#### 依赖的加密能力

| 算法 | 用途 | HarmonyOS API |
|------|------|---------------|
| SHA-256 | 计算请求体哈希 | `cryptoFramework` |
| HMAC-SHA256 | 计算签名 | `cryptoFramework` |
| Hex 编码 | 输出十六进制 | `util.HexHelper` |

### 4. XML 解析器 (S3XmlParser.ets)

使用 `@kit.ArkTS` 的 `xml.XmlPullParser` 解析 S3 XML 响应：

```typescript
export class S3XmlParser {
  /**
   * 解析 ListBuckets 响应
   * <ListAllMyBucketsResult><Buckets><Bucket><Name><CreationDate>
   */
  public static parseListBuckets(xmlStr: string): S3Bucket[];

  /**
   * 解析 ListObjects 响应
   * <ListBucketResult><Contents><Key><Size><LastModified><ETag>
   */
  public static parseListObjects(xmlStr: string): S3Object[];

  /**
   * 解析错误响应
   * <Error><Code><Message>
   */
  public static parseError(xmlStr: string): { code: string; message: string };
}
```

### 5. S3 客户端 (S3Client.ets)

```typescript
export interface S3ClientOptions {
  endpoint: string;
  accessKeyId: string;
  secretAccessKey: string;
  region: string;
  pathStyle: boolean;
  timeout: number;
}

export class S3Client {
  private session: rcp.Session | null = null;
  private options: S3ClientOptions;
  private signer: S3SignatureV4;

  constructor(options: S3ClientOptions);

  // Bucket 操作
  public async listBuckets(): Promise<S3Result<S3Bucket[]>>;
  public async headBucket(bucket: string): Promise<boolean>;

  // Object 操作
  public async listObjects(bucket: string, prefix?: string): Promise<S3Result<S3Object[]>>;
  public async getObject(bucket: string, key: string): Promise<S3Result<ArrayBuffer>>;
  public async putObject(bucket: string, key: string, data: ArrayBuffer): Promise<S3Result<void>>;
  public async deleteObject(bucket: string, key: string): Promise<S3Result<void>>;
  public async headObject(bucket: string, key: string): Promise<S3Result<S3Object>>;

  // 连接管理
  public async testConnection(): Promise<S3Result<void>>;
  public close(): void;
}
```

#### URL 构建规则

| 样式 | URL 格式 | 适用场景 |
|------|----------|----------|
| **虚拟主机样式**（默认） | `https://{bucket}.{endpoint}/{key}` | AWS S3、大多数云服务 |
| **路径样式** | `https://{endpoint}/{bucket}/{key}` | MinIO、私有部署、DNS 限制时 |

### 6. 存储实现 (S3Storage.ets)

```typescript
export class S3Storage implements IFileStorage {
  private config: S3StorageConfig | undefined;
  private client: S3Client | undefined;
  private currentBucket: string | undefined;

  constructor(config?: S3StorageConfig);

  // IFileStorage 接口实现
  public getPageConfig(): PageConfig;
  public init(config: S3StorageConfig): void;
  public read(path: string): Promise<ArrayBuffer>;
  public write(path: string, content: ArrayBuffer): Promise<void>;
  public exists(path: string): Promise<boolean>;
  public getInfo(path: string): Promise<FileInfo>;
  public listDir(path: string): Promise<FileInfo[]>;
}
```

#### 路径格式约定

| 格式 | 示例 | 说明 |
|------|------|------|
| 带 Bucket 路径 | `my-bucket/folder/file.kdbx` | 完整路径 |
| 仅 Key 路径 | `folder/file.kdbx` | 使用默认 Bucket |

### 7. 配置页面 (S3Page.ets)

```
┌─────────────────────────────────────────┐
│  S3 存储配置                             │
├─────────────────────────────────────────┤
│  服务端点 *                              │
│  ┌─────────────────────────────────────┐│
│  │ https://s3.amazonaws.com            ││
│  └─────────────────────────────────────┘│
│  提示: 支持 AWS S3、MinIO、阿里云 OSS 等  │
├─────────────────────────────────────────┤
│  Access Key ID *                        │
│  ┌─────────────────────────────────────┐│
│  │                                      ││
│  └─────────────────────────────────────┘│
├─────────────────────────────────────────┤
│  Secret Access Key *                    │
│  ┌─────────────────────────────────────┐│
│  │ ••••••••••••              👁        ││
│  └─────────────────────────────────────┘│
├─────────────────────────────────────────┤
│  ▼ 高级设置                              │
│  ┌─────────────────────────────────────┐│
│  │ 区域        [us-east-1        ▼]   ││
│  │ 默认存储桶  [                   ]   ││
│  │ URL 样式    ○ 虚拟主机  ● 路径样式   ││
│  │ 超时时间    [30000        ] ms      ││
│  └─────────────────────────────────────┘│
├─────────────────────────────────────────┤
│       [测试连接]        [保存]          │
└─────────────────────────────────────────┘
```

#### 页面字段

| 字段 | 必填 | 默认值 | 说明 |
|------|------|--------|------|
| 服务端点 | 是 | - | S3 服务地址 |
| Access Key ID | 是 | - | 访问密钥 |
| Secret Access Key | 是 | - | 密钥（密码样式显示） |
| 区域 | 否 | us-east-1 | AWS 区域标识 |
| 默认存储桶 | 否 | - | 预设的存储桶名称 |
| URL 样式 | 否 | 虚拟主机 | 路径样式适合 MinIO |
| 超时时间 | 否 | 30000 | 请求超时（毫秒） |

#### 常用端点预设

| 服务商 | 端点示例 |
|--------|----------|
| AWS S3 | `https://s3.amazonaws.com` |
| 阿里云 OSS | `https://oss-cn-hangzhou.aliyuncs.com` |
| 腾讯云 COS | `https://cos.ap-guangzhou.myqcloud.com` |
| 华为云 OBS | `https://obs.cn-north-4.myhuaweicloud.com` |
| MinIO | `http://localhost:9000` |
| Cloudflare R2 | `https://<account-id>.r2.cloudflarestorage.com` |

## 错误处理

### S3 错误码映射

| S3 错误码 | HTTP 状态码 | StorageErrorCodes | 用户提示 |
|-----------|-------------|-------------------|----------|
| `NoSuchBucket` | 404 | FILE_READ_ERROR | 存储桶不存在 |
| `NoSuchKey` | 404 | FILE_READ_ERROR | 文件不存在 |
| `AccessDenied` | 403 | CONNECT_ERROR | 无访问权限，请检查密钥 |
| `InvalidAccessKeyId` | 403 | CONNECT_ERROR | Access Key ID 无效 |
| `SignatureDoesNotMatch` | 403 | CONNECT_ERROR | 签名错误，请检查 Secret Key |
| `EntityTooLarge` | 400 | FILE_WRITE_ERROR | 文件超出大小限制 |
| `BucketAlreadyExists` | 409 | FILE_WRITE_ERROR | 存储桶已存在 |
| `ServiceUnavailable` | 503 | CONNECT_ERROR | 服务暂不可用 |

## 集成步骤

### 1. StorageType 枚举扩展

```typescript
// StorageType.ets
export enum StorageType {
  LOCAL = 'LOCAL',
  WEBDAV = 'WEBDAV',
  FTP = 'FTP',
  ONEDRIVE = 'ONEDRIVE',
  S3 = 'S3'  // 新增
}
```

### 2. 工厂注册

```typescript
// FileStorageFactory.ets
import { S3Storage } from './s3/S3Storage';

private constructor() {
  this.registerStorage(StorageType.LOCAL, new LocalFileStorage());
  this.registerStorage(StorageType.WEBDAV, new WebDAVStorage());
  this.registerStorage(StorageType.ONEDRIVE, new OneDriveStorage());
  this.registerStorage(StorageType.FTP, new FTPStorage());
  this.registerStorage(StorageType.S3, new S3Storage());  // 新增
}
```

### 3. 模块导出

```typescript
// storage/index.ets
export * from './s3/S3Storage';
export * from './s3/S3Config';
export * from './s3/S3Types';
```

### 4. 页面路由注册

```json
// main_pages.json
{
  "src": [
    "pages/Index",
    "storage/local/LocalFilePage",
    "storage/webdav/WebDAVPage",
    "storage/onedrive/OneDrivePage",
    "storage/ftp/FTPPage",
    "storage/s3/S3Page"
  ]
}
```

## 资源文件

### 图标

| 路径 | 说明 |
|------|------|
| `resources/base/media/ic_s3.png` | S3 存储图标 |

### 字符串资源

| Key | 中文 | 英文 |
|-----|------|------|
| `s3_button_title` | S3 存储 | S3 Storage |
| `s3_select_file` | 从 S3 存储选择文件 | Select file from S3 Storage |
| `s3_save_file` | 保存到 S3 存储 | Save to S3 Storage |
| `s3_endpoint` | 服务端点 | Endpoint |
| `s3_access_key_id` | Access Key ID | Access Key ID |
| `s3_secret_access_key` | Secret Access Key | Secret Access Key |
| `s3_region` | 区域 | Region |
| `s3_bucket` | 存储桶 | Bucket |
| `s3_path_style` | 路径样式 URL | Path-Style URL |
| `s3_test_connection` | 测试连接 | Test Connection |
| `s3_connection_success` | 连接成功 | Connection successful |
| `s3_connection_failed` | 连接失败 | Connection failed |
| `s3_endpoint_hint` | 支持 AWS S3、MinIO、阿里云 OSS 等 | Supports AWS S3, MinIO, Alibaba OSS, etc. |
| `s3_advanced_settings` | 高级设置 | Advanced Settings |
| `s3_timeout` | 超时时间 | Timeout |
| `s3_url_style` | URL 样式 | URL Style |
| `s3_virtual_host_style` | 虚拟主机 | Virtual Host |
| `s3_path_style_url` | 路径样式 | Path Style |
| `s3_default_bucket` | 默认存储桶 | Default Bucket |

## 测试计划

### 单元测试

- S3SignatureV4 签名算法正确性测试
- S3XmlParser XML 解析测试
- S3Config 配置加密/解密测试

### 集成测试

- 连接测试功能验证
- 文件上传/下载测试
- Bucket 列表获取测试
- 错误处理测试

### 兼容性测试

| 服务 | 测试内容 |
|------|----------|
| AWS S3 | 基本功能、虚拟主机样式 |
| MinIO | 基本功能、路径样式 |
| 阿里云 OSS | 基本功能 |
| 华为云 OBS | 基本功能 |

## 风险与缓解

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| 签名算法实现复杂 | 中 | 参考 AWS 官方文档，编写完善的单元测试 |
| 不同服务商兼容性差异 | 中 | 提供路径样式选项，测试主流服务商 |
| 大文件传输性能 | 低 | 利用现有 CacheStorage 缓存机制 |
