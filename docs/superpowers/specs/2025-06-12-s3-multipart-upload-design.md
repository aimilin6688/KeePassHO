# S3 Multipart Upload 设计文档

**日期**: 2025-06-12
**版本**: 1.0
**作者**: Claude Code

## 1. 概述

### 1.1 背景

KeePassHO 是一个 HarmonyOS 密码管理器应用，支持 S3 协议的云存储同步。当前 S3 存储实现存在以下问题：

1. **内存风险**：一次性加载整个文件到内存，大文件（>20MB）可能导致内存峰值过高
2. **网络可靠性**：上传/下载失败后需要完全重传
3. **用户体验**：无进度回调，用户无法了解传输进度

### 1.2 目标

实现 S3 Multipart Upload 功能，支持：

- 大文件（≥5MB）自动分块上传/下载
- 内存峰值控制在 10MB 以内
- 支持进度回调
- 原子性写入，保证数据安全
- 支持失败重试（最多 3 次）

### 1.3 使用场景

- KeePass 数据库文件（通常 < 10MB）
- 数据库附件（图片、文档等，20-50MB）

## 2. 架构设计

### 2.1 整体架构

```
┌─────────────────────────────────────────────────────────────┐
│                      S3Storage Layer                        │
│  (现有接口: read/write/exists/getInfo/listDir)              │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   S3Client (扩展)                            │
│  - putObject() [小文件，现有逻辑]                             │
│  - putObjectSmart() [智能上传，新增]                          │
│  - createMultipartUpload()                                   │
│  - uploadPart()                                              │
│  - completeMultipartUpload()                                 │
│  - abortMultipartUpload()                                    │
│  - getObject() [小文件，现有逻辑]                              │
│  - getObjectChunked() [大文件下载，新增]                       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              S3SignatureV4 (扩展)                            │
│  - 支持 Multipart Upload 相关 API 的签名                      │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 核心组件

```
新增/修改文件列表：
├── S3Types.ets (扩展)
│   ├── MultipartUploadInit
│   ├── UploadedPart
│   ├── MultipartUploadProgress
│   └── ProgressCallback
│
├── S3MultipartConfig.ets (新增)
│   ├── MIN_PART_SIZE = 5MB
│   ├── RECOMMENDED_PART_SIZE = 8MB
│   ├── MULTIPART_THRESHOLD = 5MB
│   └── MAX_RETRY_COUNT = 3
│
├── S3Client.ets (扩展)
│   ├── putObjectSmart() - 智能上传
│   ├── createMultipartUpload() - 初始化分块上传
│   ├── uploadPart() - 上传单个分块
│   ├── completeMultipartUpload() - 完成分块上传
│   ├── abortMultipartUpload() - 取消分块上传
│   └── getObjectChunked() - 分块下载
│
├── S3Storage.ets (扩展)
│   ├── writeSafe() - 原子性写入（临时文件策略）
│   ├── write() - 自动判断是否分块上传
│   ├── read() - 自动判断是否分块下载
│   ├── rename() - 重命名文件（新增）
│   ├── delete() - 删除文件（新增）
│   └── setProgressCallback() - 设置进度回调
│
└── S3SignatureV4.ets (扩展)
    └── 支持 Multipart Upload 相关 API 的签名
```

## 3. 数据结构设计

### 3.1 S3Types.ets 新增类型

```typescript
/**
 * Multipart Upload 初始化响应
 */
export interface MultipartUploadInit {
  /**
   * Upload ID，用于后续操作
   */
  uploadId: string;

  /**
   * 对象键
   */
  key: string;

  /**
   * 存储桶名称
   */
  bucket: string;
}

/**
 * 已上传的 Part 信息
 */
export interface UploadedPart {
  /**
   * Part 编号（1-10000）
   */
  partNumber: number;

  /**
   * Part 的 ETag，用于完成上传
   */
  etag: string;

  /**
   * Part 大小（字节）
   */
  size: number;
}

/**
 * Multipart Upload 上传进度回调
 */
export interface MultipartUploadProgress {
  /**
   * 已上传字节数
   */
  uploadedBytes: number;

  /**
   * 总字节数
   */
  totalBytes: number;

  /**
   * 当前 Part 编号
   */
  currentPart: number;

  /**
   * 总 Part 数量
   */
  totalParts: number;
}

/**
 * 上传进度回调函数类型
 */
export type ProgressCallback = (progress: MultipartUploadProgress) => void;
```

### 3.2 S3MultipartConfig.ets 配置常量

```typescript
/**
 * S3 Multipart Upload 配置常量
 */
export class S3MultipartConfig {
  /**
   * 最小分块大小：5MB（S3 标准）
   * 所有非最后一个 part 必须至少 5MB
   */
  static readonly MIN_PART_SIZE = 5 * 1024 * 1024; // 5MB

  /**
   * 推荐分块大小：8MB
   * - 平衡内存占用和网络效率
   * - 适合移动设备网络环境
   */
  static readonly RECOMMENDED_PART_SIZE = 8 * 1024 * 1024; // 8MB

  /**
   * Multipart 上传阈值：5MB
   * 文件 >= 5MB 时启用 multipart upload
   */
  static readonly MULTIPART_THRESHOLD = 5 * 1024 * 1024; // 5MB

  /**
   * 最大重试次数
   */
  static readonly MAX_RETRY_COUNT = 3;
}
```

## 4. 核心流程设计

### 4.1 Multipart Upload 上传流程

```
┌─────────────────────────────────────────────────────────────┐
│                    putObjectSmart()                         │
│  1. 判断文件大小                                             │
│     - < 5MB: 调用现有 putObject()                            │
│     - >= 5MB: 执行 Multipart Upload 流程                     │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼ [>= 5MB]
┌─────────────────────────────────────────────────────────────┐
│            Step 1: createMultipartUpload()                  │
│  - 发送 POST 请求到 /{bucket}/{key}?uploads                  │
│  - 获取 uploadId                                             │
│  - 返回: { uploadId, bucket, key }                           │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│            Step 2: uploadPart() [循环]                       │
│  - 将文件切分为多个 part (每 part 8MB)                        │
│  - 逐个上传 part:                                            │
│    PUT /{bucket}/{key}?partNumber={N}&uploadId={id}         │
│  - 收集每个 part 的 ETag                                     │
│  - 支持进度回调                                              │
│  - 失败重试: 最多重试 3 次                                    │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│         Step 3: completeMultipartUpload()                   │
│  - 发送 POST 请求，包含所有 part 的 ETag 列表                 │
│  - S3 组装所有 part 为完整对象                                │
│  - 清理临时资源                                              │
└─────────────────────────────────────────────────────────────┘
                          │
                          ▼
                     [上传完成]
```

### 4.2 分块下载流程

```
┌─────────────────────────────────────────────────────────────┐
│               getObjectChunked() 流程                        │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. headObject() 获取文件大小                                │
│  2. 计算分块数量 (每块 8MB)                                   │
│  3. 循环下载每个块:                                           │
│     - 设置 Range 请求头: "bytes=start-end"                   │
│     - GET /{bucket}/{key}                                    │
│     - 拼接到最终 ArrayBuffer                                  │
│  4. 支持进度回调                                              │
│  5. 返回完整文件数据                                          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 4.3 原子性写入流程（临时文件策略）

```
┌─────────────────────────────────────────────────────────────┐
│                  writeSafe() 流程                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. 上传文件到临时路径: {path}.tmp                            │
│     - 使用 write() 方法（自动选择分块上传）                   │
│  2. 验证上传（可选）                                          │
│  3. 删除旧文件: {path}                                        │
│  4. 重命名临时文件: {path}.tmp → {path}                       │
│  5. 完成                                                      │
│                                                              │
│  失败处理：                                                   │
│  - 任何步骤失败，清理临时文件                                 │
│  - 抛出异常，原文件保持不变                                   │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## 5. 错误处理设计

### 5.1 错误处理策略

```
┌─────────────────────────────────────────────────────────────┐
│                    错误处理策略                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Part 上传失败:                                           │
│     - 重试该 part（最多 3 次）                                │
│     - 如果仍失败，执行 abortMultipartUpload()                │
│                                                              │
│  2. 网络中断:                                                │
│     - 用户可重新调用，提供 uploadId 恢复上传                  │
│     - 需要持久化 uploadId 和已上传的 parts                   │
│                                                              │
│  3. 用户取消上传:                                            │
│     - 调用 abortMultipartUpload()                            │
│     - 清理已上传的 part                                      │
│                                                              │
│  4. 超时处理:                                                │
│     - Part 上传超时: 重试                                    │
│     - 整体超时: abort 并抛出异常                              │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 原子性保证

- 上传失败后原文件完整保留
- 临时文件被正确清理
- 无数据丢失风险

## 6. 测试设计

### 6.1 测试文件结构

```
entry/src/ohosTest/ets/test/storage/s3/
├── S3ClientMultipartTest.ets       # Multipart Upload 方法测试
├── S3StorageIntegrationTest.ets    # S3Storage 集成测试
├── S3MultipartConfigTest.ets       # 配置测试
└── MockS3Server.ets                # Mock S3 服务器（用于测试）
```

### 6.2 测试覆盖范围

#### S3Client 方法测试

1. createMultipartUpload 成功场景
2. createMultipartUpload 失败场景（无效 bucket）
3. uploadPart 成功场景
4. uploadPart 失败重试场景
5. uploadPart 失败后超过最大重试次数
6. completeMultipartUpload 成功场景
7. completeMultipartUpload 失败（缺少 part）
8. abortMultipartUpload 成功场景
9. putObjectSmart 小文件（< 5MB）
10. putObjectSmart 大文件（>= 5MB）
11. putObjectSmart 边界值（5MB）
12. getObjectChunked 分块下载
13. getObjectChunked 失败重试

#### S3Storage 集成测试

1. write() 自动选择分块上传
2. read() 自动选择分块下载
3. writeSafe() 原子性写入成功
4. writeSafe() 上传失败不覆盖原文件
5. writeSafe() 失败后清理临时文件
6. rename() 重命名文件
7. delete() 删除文件
8. 进度回调准确性
9. 小文件使用单次上传
10. 并发上传（可选）

### 6.3 测试覆盖率目标

```
单元测试覆盖率目标：
├── S3Client.ets: ≥ 85%
│   ├── createMultipartUpload: 100%
│   ├── uploadPart: 100%
│   ├── completeMultipartUpload: 100%
│   ├── abortMultipartUpload: 100%
│   ├── putObjectSmart: 100%
│   └── getObjectChunked: 100%
│
├── S3Storage.ets: ≥ 90%
│   ├── write (自动选择): 100%
│   ├── read (自动选择): 100%
│   ├── writeSafe: 100%
│   ├── rename: 100%
│   └── delete: 100%
│
└── S3MultipartConfig.ets: 100%

测试类型分布：
├── 正常场景测试: 60%
├── 边界值测试: 20%
├── 异常场景测试: 15%
└── 性能测试: 5%
```

## 7. 实施计划

### 7.1 Phase 1: 核心功能实现（3-4天）

```
Day 1: 数据结构和配置
├── 1. 扩展 S3Types.ets
├── 2. 创建 S3MultipartConfig.ets
└── 3. 扩展 S3SignatureV4.ets

Day 2: Multipart Upload 核心方法
├── 1. 实现 createMultipartUpload()
├── 2. 实现 uploadPart()
├── 3. 实现 completeMultipartUpload()
└── 4. 实现 abortMultipartUpload()

Day 3: 智能上传和分块下载
├── 1. 实现 putObjectSmart()
├── 2. 实现 getObjectChunked()
└── 3. 单元测试

Day 4: S3Storage 集成
├── 1. 扩展 write() 方法
├── 2. 扩展 read() 方法
├── 3. 实现 writeSafe() 原子性写入
├── 4. 实现 rename() 和 delete() 辅助方法
└── 5. 集成测试
```

### 7.2 Phase 2: 测试和优化（2天）

```
Day 5: 测试
├── 1. 单元测试完善
├── 2. 集成测试（真实 S3 环境）
├── 3. 性能测试（内存峰值验证）
└── 4. 兼容性测试（MinIO/阿里云 OSS）

Day 6: 优化和文档
├── 1. 性能优化
├── 2. 错误处理优化
├── 3. 代码审查
└── 4. 文档更新
```

## 8. 验收标准

### 8.1 功能验收

- ✅ 支持上传 >= 5MB 的文件，自动使用 Multipart Upload
- ✅ 支持下载 >= 5MB 的文件，自动使用分块下载
- ✅ 上传过程中内存峰值 < 10MB
- ✅ 上传失败不覆盖原文件（原子性保证）
- ✅ 支持进度回调
- ✅ 支持失败重试（最多 3 次）
- ✅ 兼容 AWS S3、MinIO、阿里云 OSS

### 8.2 性能验收

- ✅ 50MB 文件上传内存峰值 < 10MB
- ✅ 50MB 文件下载内存峰值 < 10MB
- ✅ 上传速度不低于现有单次上传方案

### 8.3 安全验收

- ✅ 上传失败后原文件完整保留
- ✅ 临时文件被正确清理
- ✅ 无内存泄漏

## 9. 风险和缓解措施

| 风险 | 影响 | 缓解措施 |
|------|------|----------|
| S3 兼容存储不支持 Multipart | 上传失败 | 提供降级方案，自动回退到普通上传 |
| 网络中断导致 uploadId 丢失 | 无法续传 | Phase 1 暂不实现续传，Phase 2 可扩展 |
| Part 上传失败率较高 | 用户体验差 | 实现自动重试机制（最多 3 次） |
| 内存峰值超过预期 | 移动设备卡顿 | 严格限制分块大小，监控内存使用 |

## 10. 后续扩展能力

```
未来可能的扩展功能（不在当前范围内）:
├── 1. 断点续传
│   └── 持久化 uploadId 和已上传 parts
├── 2. 并发上传
│   └── 同时上传多个 part（提升速度）
├── 3. 后台传输
│   └── 使用 HarmonyOS 后台任务 API
└── 4. 上传/下载暂停/恢复
    └── 用户可控的传输管理
```

## 11. 参考资料

- [AWS S3 Multipart Upload API](https://docs.aws.amazon.com/AmazonS3/latest/userguide/mpuoverview.html)
- [S3 API Reference - UploadPart](https://docs.aws.amazon.com/AmazonS3/latest/API/API_UploadPart.html)
- [项目现有 SFTPHandler 分块实现](../../entry/src/main/ets/storage/ftp/SFTPHandler.ets)
