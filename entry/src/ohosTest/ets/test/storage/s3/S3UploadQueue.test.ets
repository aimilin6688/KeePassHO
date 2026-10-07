import { describe, expect, it } from '@ohos/hypium';
import { S3UploadQueue } from '../../../../../main/ets/storage/s3/S3UploadQueue';
import { S3MultipartConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { UploadTask } from '../../../../../main/ets/storage/s3/S3Types';

class TestUploadTask implements UploadTask {
  partNumber: number;
  start: number;
  end: number;
  retryCount: number;

  constructor(partNumber: number, start: number, end: number, retryCount: number = 0) {
    this.partNumber = partNumber;
    this.start = start;
    this.end = end;
    this.retryCount = retryCount;
  }
}

export default function S3UploadQueueTest() {
  describe('S3UploadQueueTest', () => {

    describe('Construction', () => {
      it('should store totalBytes and totalParts in progress snapshot', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 10);
        const p = q.getProgress();
        expect(p.totalBytes).assertEqual(1000);
        expect(p.totalParts).assertEqual(10);
        expect(p.uploadedBytes).assertEqual(0);
        expect(p.currentPart).assertEqual(0);
      });

      it('should start with zero completed/failed counts', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 10);
        expect(q.getCompletedCount()).assertEqual(0);
        expect(q.getFailedCount()).assertEqual(0);
        expect(q.hasFailedTasks()).assertFalse();
      });
    });

    describe('FIFO', () => {
      it('getNextTask returns null on empty queue', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 10);
        expect(q.getNextTask()).assertNull();
      });

      it('should return tasks in FIFO order', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 3);
        const t1: TestUploadTask = new TestUploadTask(1, 0, 100);
        const t2: TestUploadTask = new TestUploadTask(2, 100, 200);
        const t3: TestUploadTask = new TestUploadTask(3, 200, 300);
        q.addTask(t1);
        q.addTask(t2);
        q.addTask(t3);

        expect(q.getNextTask()!.partNumber).assertEqual(1);
        expect(q.getNextTask()!.partNumber).assertEqual(2);
        expect(q.getNextTask()!.partNumber).assertEqual(3);
        expect(q.getNextTask()).assertNull();
      });

      it('addTask then getNextTask returns the same instance', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 1);
        const t: TestUploadTask = new TestUploadTask(7, 0, 10);
        q.addTask(t);
        const popped: UploadTask | null = q.getNextTask();
        expect(popped).not().assertNull();
        expect(popped as TestUploadTask).assertEqual(t);
      });
    });

    describe('markCompleted', () => {
      it('should increment completedCount and accumulate uploadedBytes', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 3);
        q.markCompleted(100);
        expect(q.getCompletedCount()).assertEqual(1);
        expect(q.getProgress().uploadedBytes).assertEqual(100);
        expect(q.getProgress().currentPart).assertEqual(1);

        q.markCompleted(200);
        expect(q.getCompletedCount()).assertEqual(2);
        expect(q.getProgress().uploadedBytes).assertEqual(300);
        expect(q.getProgress().currentPart).assertEqual(2);
      });

      it('should accept zero bytes', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 3);
        q.markCompleted(0);
        expect(q.getCompletedCount()).assertEqual(1);
        expect(q.getProgress().uploadedBytes).assertEqual(0);
      });

      it('currentPart should reflect completedCount', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 5);
        for (let i = 0; i < 4; i++) {
          q.markCompleted(10);
        }
        expect(q.getProgress().currentPart).assertEqual(4);
      });
    });

    describe('retryTask', () => {
      it('should re-enqueue task and return true when under retry limit', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 1);
        const t: TestUploadTask = new TestUploadTask(1, 0, 100, 0);
        const ok: boolean = q.retryTask(t);
        expect(ok).assertTrue();
        expect(t.retryCount).assertEqual(1);
        const popped: UploadTask | null = q.getNextTask();
        expect(popped).not().assertNull();
        expect(popped!.partNumber).assertEqual(1);
      });

      it('should return false and increment failedCount at retry limit', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 1);
        const t: TestUploadTask = new TestUploadTask(2, 0, 100, S3MultipartConfig.MAX_RETRY_COUNT);
        const ok: boolean = q.retryTask(t);
        expect(ok).assertFalse();
        expect(q.getFailedCount()).assertEqual(1);
        expect(q.hasFailedTasks()).assertTrue();
        expect(q.getNextTask()).assertNull();
      });

      it('should increment retryCount each retry up to the limit', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 1);
        const t: TestUploadTask = new TestUploadTask(3, 0, 100, 0);
        let result: boolean = q.retryTask(t);
        expect(result).assertTrue();
        expect(t.retryCount).assertEqual(1);
        result = q.retryTask(t);
        expect(result).assertTrue();
        expect(t.retryCount).assertEqual(2);
        result = q.retryTask(t);
        expect(result).assertTrue();
        expect(t.retryCount).assertEqual(3);
        result = q.retryTask(t);
        expect(result).assertFalse();
        expect(t.retryCount).assertEqual(3);
        expect(q.getFailedCount()).assertEqual(1);
      });

      it('should not increment failedCount while retries remain', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 1);
        const t: TestUploadTask = new TestUploadTask(4, 0, 100, 0);
        q.retryTask(t);
        q.retryTask(t);
        expect(q.getFailedCount()).assertEqual(0);
        expect(q.hasFailedTasks()).assertFalse();
      });

      it('failedCount should accumulate across multiple exhausted tasks', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(1000, 2);
        const t1: TestUploadTask = new TestUploadTask(1, 0, 100, S3MultipartConfig.MAX_RETRY_COUNT);
        const t2: TestUploadTask = new TestUploadTask(2, 100, 200, S3MultipartConfig.MAX_RETRY_COUNT);
        q.retryTask(t1);
        q.retryTask(t2);
        expect(q.getFailedCount()).assertEqual(2);
      });
    });

    describe('getProgress', () => {
      it('should snapshot current state without mutating', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(2000, 4);
        q.markCompleted(500);
        const p1 = q.getProgress();
        const p2 = q.getProgress();
        expect(p1.uploadedBytes).assertEqual(500);
        expect(p2.uploadedBytes).assertEqual(500);
        expect(p1.totalBytes).assertEqual(2000);
        expect(p1.totalParts).assertEqual(4);
        expect(p1.currentPart).assertEqual(1);
        expect(q.getCompletedCount()).assertEqual(1);
      });
    });

    describe('CombinedWorkflow', () => {
      it('should model a full upload lifecycle', 0, () => {
        const q: S3UploadQueue = new S3UploadQueue(300, 3);
        const t1: TestUploadTask = new TestUploadTask(1, 0, 100);
        const t2: TestUploadTask = new TestUploadTask(2, 100, 200);
        const t3: TestUploadTask = new TestUploadTask(3, 200, 300);
        q.addTask(t1);
        q.addTask(t2);
        q.addTask(t3);

        const popped1: UploadTask | null = q.getNextTask();
        q.markCompleted(100);

        const popped2: UploadTask | null = q.getNextTask();
        // part 2 fails and exhausts retries immediately
        popped2!.retryCount = S3MultipartConfig.MAX_RETRY_COUNT;
        const retried: boolean = q.retryTask(popped2!);
        expect(retried).assertFalse();

        const popped3: UploadTask | null = q.getNextTask();
        q.markCompleted(100);

        expect(popped1!.partNumber).assertEqual(1);
        expect(popped2!.partNumber).assertEqual(2);
        expect(popped3!.partNumber).assertEqual(3);
        expect(q.getCompletedCount()).assertEqual(2);
        expect(q.getFailedCount()).assertEqual(1);
        expect(q.hasFailedTasks()).assertTrue();
        expect(q.getProgress().uploadedBytes).assertEqual(200);
      });
    });
  });
}
