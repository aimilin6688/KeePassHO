import { describe, expect, it } from '@ohos/hypium';
import {
  MultipartUploadInit,
  MultipartUploadProgress,
  ProgressCallback,
  S3Bucket,
  S3Error,
  S3Object,
  S3Result,
  UploadTask,
  UploadWorkerResult,
  UploadedPart
} from '../../../../../main/ets/storage/s3/S3Types';

/**
 * S3Types.ets 是纯接口/类型声明，无运行时逻辑。
 * 此测试为结构回归保护：确保各 interface 的字段 shape 稳定，
 * 可被实现并正确读写（覆盖字段默认值、赋值、ProgressCallback 调用）。
 */
class S3ObjectImpl implements S3Object {
  key: string = '';
  size: number = 0;
  lastModified: number = 0;
  etag: string = '';
}

class S3BucketImpl implements S3Bucket {
  name: string = '';
  creationDate: number = 0;
}

class S3ErrorImpl implements S3Error {
  code: string = '';
  message: string = '';
  resourceId?: string;
  resource?: string;
}

class MultipartUploadInitImpl implements MultipartUploadInit {
  uploadId: string = '';
  key: string = '';
  bucket: string = '';
}

class UploadedPartImpl implements UploadedPart {
  partNumber: number = 0;
  etag: string = '';
  size: number = 0;
}

class UploadTaskImpl implements UploadTask {
  partNumber: number = 0;
  start: number = 0;
  end: number = 0;
  retryCount: number = 0;
}

class UploadWorkerResultImpl implements UploadWorkerResult {
  success: boolean = false;
  parts: UploadedPart[] = [];
  error?: string;
}

class MultipartUploadProgressImpl implements MultipartUploadProgress {
  uploadedBytes: number = 0;
  totalBytes: number = 0;
  currentPart: number = 0;
  totalParts: number = 0;
}

export default function S3TypesTest() {
  describe('S3TypesTest', () => {

    describe('S3Object', () => {
      it('should round-trip all fields', 0, () => {
        const obj: S3ObjectImpl = new S3ObjectImpl();
        obj.key = 'path/to/file.kdbx';
        obj.size = 2048;
        obj.lastModified = 1700000000000;
        obj.etag = '"abc123"';
        expect(obj.key).assertEqual('path/to/file.kdbx');
        expect(obj.size).assertEqual(2048);
        expect(obj.lastModified).assertEqual(1700000000000);
        expect(obj.etag).assertEqual('"abc123"');
      });
    });

    describe('S3Bucket', () => {
      it('should round-trip all fields', 0, () => {
        const b: S3BucketImpl = new S3BucketImpl();
        b.name = 'keepassho';
        b.creationDate = 1690000000000;
        expect(b.name).assertEqual('keepassho');
        expect(b.creationDate).assertEqual(1690000000000);
      });
    });

    describe('S3Result', () => {
      it('should build a success result with data', 0, () => {
        const data: S3ObjectImpl = new S3ObjectImpl();
        data.key = 'a';
        const result: S3Result<S3Object> = {
          success: true,
          statusCode: 200,
          message: undefined,
          data: data,
          headers: undefined
        };
        expect(result.success).assertTrue();
        expect(result.statusCode).assertEqual(200);
        expect(result.data!.key).assertEqual('a');
      });

      it('should build a failure result without data', 0, () => {
        const result: S3Result<void> = {
          success: false,
          statusCode: 404,
          message: 'Not Found'
        };
        expect(result.success).assertFalse();
        expect(result.statusCode).assertEqual(404);
        expect(result.message).assertEqual('Not Found');
        expect(result.data).assertUndefined();
      });

      it('should carry headers map', 0, () => {
        const headers: Record<string, string> = { 'content-type': 'application/xml' };
        const result: S3Result<void> = {
          success: true,
          statusCode: 200,
          headers: headers
        };
        expect(result.headers!['content-type']).assertEqual('application/xml');
      });
    });

    describe('S3Error', () => {
      it('should round-trip required fields', 0, () => {
        const e: S3ErrorImpl = new S3ErrorImpl();
        e.code = 'NoSuchKey';
        e.message = 'The specified key does not exist';
        expect(e.code).assertEqual('NoSuchKey');
        expect(e.message).assertContain('not exist');
      });

      it('should have optional resource fields', 0, () => {
        const e: S3ErrorImpl = new S3ErrorImpl();
        e.code = 'AccessDenied';
        e.message = 'denied';
        e.resourceId = 'res-1';
        e.resource = 'bucket/key';
        expect(e.resourceId).assertEqual('res-1');
        expect(e.resource).assertEqual('bucket/key');
      });
    });

    describe('MultipartUploadInit', () => {
      it('should round-trip all fields', 0, () => {
        const init: MultipartUploadInitImpl = new MultipartUploadInitImpl();
        init.uploadId = 'upload-123';
        init.key = 'big.kdbx';
        init.bucket = 'keepass';
        expect(init.uploadId).assertEqual('upload-123');
        expect(init.key).assertEqual('big.kdbx');
        expect(init.bucket).assertEqual('keepass');
      });
    });

    describe('UploadedPart', () => {
      it('should round-trip all fields', 0, () => {
        const p: UploadedPartImpl = new UploadedPartImpl();
        p.partNumber = 5;
        p.etag = '"etag5"';
        p.size = 8 * 1024 * 1024;
        expect(p.partNumber).assertEqual(5);
        expect(p.etag).assertEqual('"etag5"');
        expect(p.size).assertEqual(8 * 1024 * 1024);
      });
    });

    describe('UploadTask', () => {
      it('should round-trip all fields including retryCount', 0, () => {
        const t: UploadTaskImpl = new UploadTaskImpl();
        t.partNumber = 2;
        t.start = 5242880;
        t.end = 10485760;
        t.retryCount = 1;
        expect(t.partNumber).assertEqual(2);
        expect(t.start).assertEqual(5242880);
        expect(t.end).assertEqual(10485760);
        expect(t.retryCount).assertEqual(1);
      });

      it('should default retryCount to 0', 0, () => {
        const t: UploadTaskImpl = new UploadTaskImpl();
        expect(t.retryCount).assertEqual(0);
      });

      it('should allow mutating retryCount', 0, () => {
        const t: UploadTaskImpl = new UploadTaskImpl();
        t.retryCount++;
        t.retryCount++;
        expect(t.retryCount).assertEqual(2);
      });
    });

    describe('UploadWorkerResult', () => {
      it('should round-trip success with parts', 0, () => {
        const r: UploadWorkerResultImpl = new UploadWorkerResultImpl();
        r.success = true;
        const p: UploadedPartImpl = new UploadedPartImpl();
        p.partNumber = 1;
        p.etag = '"e1"';
        p.size = 100;
        r.parts = [p];
        expect(r.success).assertTrue();
        expect(r.parts.length).assertEqual(1);
        expect(r.parts[0].partNumber).assertEqual(1);
      });

      it('should carry optional error', 0, () => {
        const r: UploadWorkerResultImpl = new UploadWorkerResultImpl();
        r.success = false;
        r.error = 'network reset';
        expect(r.success).assertFalse();
        expect(r.error).assertEqual('network reset');
      });
    });

    describe('MultipartUploadProgress', () => {
      it('should round-trip all fields', 0, () => {
        const p: MultipartUploadProgressImpl = new MultipartUploadProgressImpl();
        p.uploadedBytes = 10485760;
        p.totalBytes = 52428800;
        p.currentPart = 3;
        p.totalParts = 10;
        expect(p.uploadedBytes).assertEqual(10485760);
        expect(p.totalBytes).assertEqual(52428800);
        expect(p.currentPart).assertEqual(3);
        expect(p.totalParts).assertEqual(10);
      });
    });

    describe('ProgressCallback', () => {
      it('should invoke callback with progress payload', 0, () => {
        let captured: MultipartUploadProgress | null = null;
        const cb: ProgressCallback = (progress: MultipartUploadProgress): void => {
          captured = progress;
        };
        const progress: MultipartUploadProgressImpl = new MultipartUploadProgressImpl();
        progress.uploadedBytes = 50;
        progress.totalBytes = 100;
        progress.currentPart = 1;
        progress.totalParts = 2;
        cb(progress);
        expect(captured).not().assertNull();
        expect(captured!.uploadedBytes).assertEqual(50);
        expect(captured!.totalParts).assertEqual(2);
      });
    });
  });
}
