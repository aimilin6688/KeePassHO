import { UploadTask, MultipartUploadProgress } from './S3Types';
import { S3MultipartConfig } from './S3Config';

/**
 * Multipart Upload 任务队列管理器
 */
export class MultipartUploadQueue {
  private tasks: UploadTask[] = [];
  private completedCount: number = 0;
  private failedCount: number = 0;
  private uploadedBytes: number = 0;
  private totalBytes: number;
  private totalParts: number;

  constructor(totalBytes: number, totalParts: number) {
    this.totalBytes = totalBytes;
    this.totalParts = totalParts;
  }

  /**
   * 添加任务到队列
   * @param task 上传任务
   */
  public addTask(task: UploadTask): void {
    this.tasks.push(task);
  }

  /**
   * 获取下一个待处理的任务
   * @returns UploadTask 或 null（队列已空）
   */
  public getNextTask(): UploadTask | null {
    const task = this.tasks.shift();
    return task ?? null;
  }

  /**
   * 标记任务完成
   * @param bytes 上传的字节数
   */
  public markCompleted(bytes: number): void {
    this.completedCount++;
    this.uploadedBytes += bytes;
  }

  /**
   * 重试任务
   * @param task 需要重试的任务
   * @returns 是否可以重试
   */
  public retryTask(task: UploadTask): boolean {
    if (task.retryCount >= S3MultipartConfig.MAX_RETRY_COUNT) {
      this.failedCount++;
      return false;
    }

    // 增加重试计数
    task.retryCount++;

    // 重新加入队列末尾
    this.tasks.push(task);
    return true;
  }

  /**
   * 获取当前上传进度
   * @returns 上传进度信息
   */
  public getProgress(): MultipartUploadProgress {
    return {
      uploadedBytes: this.uploadedBytes,
      totalBytes: this.totalBytes,
      currentPart: this.completedCount,
      totalParts: this.totalParts
    };
  }

  /**
   * 检查是否有失败的任务
   * @returns 是否有失败任务
   */
  public hasFailedTasks(): boolean {
    return this.failedCount > 0;
  }

  /**
   * 获取已完成的任务数
   * @returns 已完成任务数
   */
  public getCompletedCount(): number {
    return this.completedCount;
  }

  /**
   * 获取失败的任务数
   * @returns 失败任务数
   */
  public getFailedCount(): number {
    return this.failedCount;
  }
}
