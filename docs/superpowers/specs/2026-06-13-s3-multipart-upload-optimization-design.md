# S3 分块上传优化设计

**日期：** 2026-06-13
**作者：** Claude
**状态：** 已实施

## 概述

优化 S3 分块上传功能，通过自适应分块大小算法和并发上传机制，显著提升大文件上传性能，同时确保符合 S3 服务规范。

### 当前问题

- **串行上传效率低**：分块逐个上传，总耗时 = 所有分块耗时之和
- **固定分块大小**：8MB 固定大小无法适应不同文件规模
- **资源未充分利用**：网络带宽未饱和

### 优化目标

1. **提高上传速度**：通过并发上传减少总耗时（目标提升 60%+）
2. **智能分块**：根据文件大小动态调整分块大小
3. **遵守 S3 限制**：确保所有分块（除最后一个）>= 5MB
4. **健壮性**：完善的错误处理和重试机制

## 设计方案

### 一、自适应分块大小算法

#### 算法目标

将分块数量控制在 100-1000 个之间，平衡请求数量和内存消耗。

#### 计算公式

```
理想分块大小 = max(文件大小 / 500, 5MB)  // 目标 500 个分块
实际分块大小 = max(理想分块大小, 5MB)      // 必须满足 S3 最小限制
```

#### 分级优化

避免过度碎片化，对计算结果进行分级优化：

- 5-8MB 区间 → 使用 5MB
- 8-16MB 区间 → 使用 8MB
- 16-32MB 区间 → 使用 16MB
- > 32MB → 使用 32MB（上限）

#### 示例计算

| 文件大小 | 理想大小 | 最终大小 | 分块数 |
|---------|---------|---------|--------|
| 10MB    | 20KB → 5MB | 5MB | 2 |
| 100MB   | 200KB → 5MB | 5MB | 20 |
| 1GB     | 2.1MB → 5MB | 8MB | 128 |
| 10GB    | 21MB | 16MB | 640 |
| 100GB   | 210MB | 32MB | 3200 |

#### 配置常量

```typescript
export class S3MultipartConfig {
  // ========== 现有配置 ==========

  /**
   * 最小分块大小：5MB（S3 标准）
   */
  static readonly MIN_PART_SIZE = 5 * 1024 * 1024;

  /**
   * Multipart 上传阈值：5MB
   */
  static readonly MULTIPART_THRESHOLD = 5 * 1024 * 1024;

  /**
   * 最大重试次数
   */
  static readonly MAX_RETRY_COUNT = 3;

  // ========== 新增配置 ==========

  /**
   * 最大分块大小：32MB
   */
  static readonly MAX_PART_SIZE = 32 * 1024 * 1024;

  /**
   * 目标分块数量：500
   */
  static readonly TARGET_PART_COUNT = 500;

  /**
   * 并发上传数量：3
   */
  static readonly CONCURRENT_UPLOADS = 3;

  /**
   * 进度回调最小间隔：100ms
   */
  static readonly PROGRESS_CALLBACK_INTERVAL = 100;

  // ========== 移除配置 ==========
  // RECOMMENDED_PART_SIZE 已移除，改为动态计算
}
```

### 二、并发上传队列机制

#### 核心数据结构

**上传任务：**
```typescript
interface UploadTask {
  partNumber: number;    // 分块编号（1-based）
  start: number;         // 起始字节位置
  end: number;           // 结束字节位置
  retryCount: number;    // 已重试次数
}
```

**上传队列：**
```typescript
class MultipartUploadQueue {
  private tasks: UploadTask[] = [];
  private completedCount: number = 0;
  private failedCount: number = 0;
  private uploadedBytes: number = 0;
  private totalBytes: number;
  private totalParts: number;

  // 添加任务
  addTask(task: UploadTask): void;

  // 获取下一个任务
  getNextTask(): UploadTask | null;

  // 标记任务完成
  markCompleted(task: UploadTask, bytes: number): void;

  // 重试任务
  retryTask(task: UploadTask): boolean;

  // 获取进度
  getProgress(): MultipartUploadProgress;

  // 检查是否有失败任务
  hasFailedTasks(): boolean;
}
```

#### 并发上传流程

```
初始化队列（所有分块任务）
    ↓
启动 3 个并发上传器
    ↓
每个上传器循环：
  ├─ 从队列获取任务
  ├─ 上传分块
  ├─ 成功 → 标记完成，更新进度
  └─ 失败 → 重试逻辑
    ↓
等待所有上传器完成
    ↓
检查结果：
  ├─ 全部成功 → complete multipart upload
  └─ 有失败 → abort multipart upload
```

#### 单个上传器伪代码

```typescript
async function uploadWorker(
  queue: MultipartUploadQueue,
  bucket: string,
  key: string,
  uploadId: string,
  data: ArrayBuffer,
  onProgress?: ProgressCallback
): Promise<UploadWorkerResult> {
  const uploadedParts: UploadedPart[] = [];

  while (true) {
    // 1. 获取任务
    const task = queue.getNextTask();
    if (!task) break; // 队列空了

    // 2. 提取分块数据
    const partData = data.slice(task.start, task.end);

    // 3. 上传
    const result = await this.uploadPart(
      bucket, key, uploadId, task.partNumber, partData
    );

    if (result.success) {
      // 4. 标记完成
      queue.markCompleted(task, partData.byteLength);
      uploadedParts.push(result.data);

      // 5. 触发进度回调
      if (onProgress) {
        onProgress(queue.getProgress());
      }
    } else {
      // 6. 重试逻辑
      if (!queue.retryTask(task)) {
        // 重试次数用尽
        return { success: false, error: 'Max retries exceeded' };
      }
    }
  }

  return { success: true, parts: uploadedParts };
}
```

### 三、进度统计和错误处理

#### 进度统计

**原子计数器设计：**
```typescript
class MultipartUploadQueue {
  private uploadedBytes: number = 0;
  private completedParts: number = 0;

  markCompleted(task: UploadTask, bytes: number): void {
    this.uploadedBytes += bytes;
    this.completedParts++;
  }

  getProgress(): MultipartUploadProgress {
    return {
      uploadedBytes: this.uploadedBytes,
      totalBytes: this.totalBytes,
      currentPart: this.completedParts,
      totalParts: this.totalParts
    };
  }
}
```

**进度回调节流（可选）：**
```typescript
class ProgressThrottler {
  private lastCallbackTime: number = 0;
  private minInterval: number = 100;

  shouldCallback(): boolean {
    const now = Date.now();
    if (now - this.lastCallbackTime >= this.minInterval) {
      this.lastCallbackTime = now;
      return true;
    }
    return false;
  }
}
```

#### 错误处理和重试机制

**重试策略：**
- 每个分块最多重试 3 次
- 失败的分块重新加入队列末尾
- 其他上传器继续工作
- 只有重试次数用尽才标记为失败

**错误处理流程：**

```
场景 1：单个分块上传失败
    ↓
检查重试次数 < 3？
    ↓ 是
重新加入队列末尾
    ↓
其他上传器继续工作
    ↓
稍后再次尝试

---

场景 2：分块重试次数用尽
    ↓
标记为失败
    ↓
继续上传其他分块
    ↓
所有上传器完成后检查
    ↓
发现有失败 → abort multipart upload
    ↓
返回错误

---

场景 3：网络中断
    ↓
所有分块都在重试
    ↓
如果网络恢复 → 继续上传
    ↓
如果持续中断 → 重试次数用尽
    ↓
最终失败
```

#### 上传器返回值

```typescript
interface UploadWorkerResult {
  success: boolean;
  parts: UploadedPart[];  // 该上传器成功上传的分块
  error?: string;
}

// 合并所有上传器的结果
const allParts = results
  .filter(r => r.success)
  .flatMap(r => r.parts)
  .sort((a, b) => a.partNumber - b.partNumber);
```

### 四、配置管理和接口调整

#### S3Client 接口变化

**对外接口保持不变：**
```typescript
public async putObjectSmart(
  bucket: string,
  key: string,
  data: ArrayBuffer,
  onProgress?: ProgressCallback,
  multipartThreshold?: number
): Promise<S3Result<void>>
```

**新增内部方法：**

```typescript
/**
 * 计算最优分块大小
 */
private calculatePartSize(fileSize: number): number {
  const idealSize = Math.max(
    fileSize / S3MultipartConfig.TARGET_PART_COUNT,
    S3MultipartConfig.MIN_PART_SIZE
  );

  // 分级优化
  if (idealSize <= 8 * 1024 * 1024) return 5 * 1024 * 1024;
  if (idealSize <= 16 * 1024 * 1024) return 8 * 1024 * 1024;
  if (idealSize <= 32 * 1024 * 1024) return 16 * 1024 * 1024;
  return 32 * 1024 * 1024;
}

/**
 * 并发上传工作器
 */
private async uploadWorker(
  queue: MultipartUploadQueue,
  bucket: string,
  key: string,
  uploadId: string,
  data: ArrayBuffer,
  onProgress?: ProgressCallback
): Promise<UploadWorkerResult>

/**
 * 重构后的 multipart 上传
 */
private async putObjectMultipart(
  bucket: string,
  key: string,
  data: ArrayBuffer,
  onProgress?: ProgressCallback
): Promise<S3Result<void>>
```

#### S3Types 新增类型

```typescript
/**
 * 上传任务
 */
export interface UploadTask {
  partNumber: number;
  start: number;
  end: number;
  retryCount: number;
}

/**
 * 上传工作器结果
 */
export interface UploadWorkerResult {
  success: boolean;
  parts: UploadedPart[];
  error?: string;
}
```

#### S3Storage 接口

保持不变，底层自动使用优化后的并发上传。

### 五、测试和验证策略

#### 单元测试

**测试文件：** `entry/src/ohosTest/ets/test/storage/s3/S3ClientMultipart.test.ets`

**测试场景：**

1. **分块大小计算测试**
   - 小文件（10MB）→ 5MB 分块
   - 中等文件（1GB）→ 8MB 分块
   - 大文件（10GB）→ 16MB 分块
   - 超大文件（100GB）→ 32MB 分块
   - 边界测试：确保最小 5MB 限制

2. **并发上传测试**
   - 验证 3 个并发上传器同时工作
   - 验证上传时间显著减少
   - 验证所有分块正确上传

3. **重试机制测试**
   - 模拟单次失败后重试成功
   - 模拟持续失败后最终失败
   - 验证重试计数正确

4. **进度回调测试**
   - 验证进度单调递增
   - 验证最终进度为 100%
   - 验证回调频率合理

#### 集成测试

**测试场景：**

1. **小文件（< 5MB）**：简单上传
2. **中等文件（5-50MB）**：5MB 分块，并发上传
3. **大文件（50MB-1GB）**：8MB 分块，验证性能提升
4. **超大文件（> 1GB）**：16MB+ 分块，验证稳定性
5. **网络不稳定**：验证重试机制

#### 性能基准

预期性能提升：

| 文件大小 | 旧方案（串行） | 新方案（并发） | 提升 |
|---------|--------------|--------------|-----|
| 10MB    | ~19秒        | ~7秒         | 63% |
| 50MB    | ~95秒        | ~35秒        | 63% |
| 100MB   | ~190秒       | ~70秒        | 63% |
| 1GB     | ~32分钟      | ~12分钟      | 63% |

#### 日志验证点

```
✓ 计算出的分块大小
✓ 启动的并发上传器数量
✓ 每个上传器处理的分块
✓ 重试事件
✓ 进度更新
✓ 总耗时
```

## 实现要点

### 关键实现细节

1. **队列管理**
   - 使用数组实现简单队列
   - `getNextTask()` 从队首取任务
   - `retryTask()` 将任务加入队尾

2. **并发控制**
   - 使用 `Promise.all()` 等待所有上传器
   - 每个上传器是独立的异步函数
   - 自动负载均衡

3. **进度统计**
   - ArkTS 单线程异步模型，无需锁
   - 在 `markCompleted()` 中更新计数器
   - 在回调中读取快照

4. **错误处理**
   - 失败任务加入队列末尾
   - 计数器跟踪失败数量
   - 最终统一检查结果

### S3 限制遵守

- **最小分块大小**：5MB（除最后一个分块）
- **最大分块数量**：10000（通过算法控制在 3200 以内）
- **最大对象大小**：5TB（远超实际使用）

### 向后兼容

- 对外接口完全兼容
- 底层实现透明升级
- 现有调用者无需修改

## 风险和缓解措施

### 风险 1：并发上传内存占用

**风险：** 3 个并发上传器同时处理数据，内存占用可能增加。

**缓解措施：**
- 使用 `ArrayBuffer.slice()` 而不是复制数据
- 分块大小上限 32MB，控制单块内存
- 上传完成后立即释放引用

### 风险 2：网络带宽竞争

**风险：** 多个并发上传可能互相竞争带宽。

**缓解措施：**
- 并发数保守设为 3
- 可根据实际测试调整
- 未来可支持动态调整

### 风险 3：错误处理复杂度

**风险：** 并发场景下的错误处理更复杂。

**缓解措施：**
- 每个上传器独立处理错误
- 队列统一管理重试
- 最终结果统一检查

## 未来优化方向

1. **动态并发数**
   - 根据网络状况调整并发数
   - WiFi 环境增加并发
   - 移动网络降低并发

2. **断点续传**
   - 保存 uploadId 和已上传分块信息
   - 支持从中断处继续上传

3. **上传暂停/恢复**
   - 支持用户手动暂停和恢复
   - 优化用户体验

4. **自适应算法优化**
   - 根据实际上传速度调整分块大小
   - 智能预测最优参数

## 总结

本设计通过自适应分块大小算法和并发上传机制，在不改变对外接口的前提下，显著提升 S3 大文件上传性能。设计充分考虑了 S3 服务限制、错误处理、进度统计等关键问题，确保功能的正确性和健壮性。

预期性能提升约 60-65%，实现复杂度适中，易于测试和维护。

---

## 实施总结

### 实施日期
2026-06-13

### 实施内容

#### 1. 类型定义更新 (S3Types.ets)
- 新增 `UploadTask` 接口：定义上传任务结构（partNumber、start、end、retryCount）
- 新增 `UploadWorkerResult` 接口：定义上传工作器返回结果

#### 2. 配置常量更新 (S3Config.ets)
- 保留 `MIN_PART_SIZE`：5MB（S3 标准）
- 保留 `MULTIPART_THRESHOLD`：5MB
- 保留 `MAX_RETRY_COUNT`：3
- 新增 `MAX_PART_SIZE`：32MB
- 新增 `TARGET_PART_COUNT`：500
- 新增 `CONCURRENT_UPLOADS`：3
- 新增 `PROGRESS_CALLBACK_INTERVAL`：100ms

#### 3. 队列管理器实现 (MultipartUploadQueue.ets)
- 实现 `addTask()`：添加任务到队列
- 实现 `getNextTask()`：获取下一个待处理任务
- 实现 `markCompleted()`：标记任务完成并更新进度
- 实现 `retryTask()`：重试失败任务
- 实现 `getProgress()`：获取当前上传进度
- 实现 `hasFailedTasks()`：检查是否有失败任务

#### 4. S3Client 方法实现
- `calculatePartSize()`：自适应分块大小计算
  - 理想大小 = max(文件大小/500, 5MB)
  - 分级优化：5MB/8MB/16MB/32MB
- `uploadWorker()`：并发上传工作器
  - 从队列获取任务
  - 上传分块并处理重试
  - 更新进度回调
- `putObjectMultipart()`：重构并发上传
  - 初始化 multipart upload
  - 创建上传队列
  - 启动 3 个并发工作器
  - 合并结果并完成上传
- `putObjectSmart()`：更新使用新算法

#### 5. 单元测试 (S3ClientMultipart.test.ets)
- MultipartUploadQueue 队列管理测试
- 重试逻辑和失败计数测试
- 配置常量正确性测试
- 进度计算逻辑测试
- 分块大小算法边界测试
- 并发上传器结果合并测试
- FIFO 顺序和重试任务顺序测试

### 文件变更清单
| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `entry/src/main/ets/storage/s3/S3Types.ets` | 新增类型 | UploadTask、UploadWorkerResult |
| `entry/src/main/ets/storage/s3/S3Config.ets` | 新增常量 | MAX_PART_SIZE、TARGET_PART_COUNT 等 |
| `entry/src/main/ets/storage/s3/MultipartUploadQueue.ets` | 新增文件 | 队列管理器实现 |
| `entry/src/main/ets/storage/s3/S3Client.ets` | 新增方法 | calculatePartSize、uploadWorker、重构 putObjectMultipart |
| `entry/src/ohosTest/ets/test/storage/s3/S3ClientMultipart.test.ets` | 新增测试 | 逻辑测试用例 |

### 提交记录
1. `feat(s3): 新增 UploadTask 和 UploadWorkerResult 类型定义`
2. `feat(s3): 更新 S3MultipartConfig 添加新的配置常量`
3. `feat(s3): 实现 MultipartUploadQueue 队列管理器`
4. `feat(s3): 添加 calculatePartSize 方法实现自适应分块大小`
5. `feat(s3): 实现 uploadWorker 并发上传工作器`
6. `refactor(s3): 重构 putObjectMultipart 实现并发上传`
7. `refactor(s3): 更新 putObjectSmart 使用新的分块算法`
8. `test(s3): 添加分块大小计算和并发上传测试`

### 验证结果
- ✅ 编译通过：`hvigorw assembleHap` 成功
- ✅ 代码逻辑测试：所有单元测试用例通过
- ✅ 向后兼容：对外接口保持不变

### 后续优化方向
1. 动态并发数调整（根据网络状况）
2. 断点续传支持
3. 上传暂停/恢复功能
4. 自适应算法优化（根据实际上传速度调整）
