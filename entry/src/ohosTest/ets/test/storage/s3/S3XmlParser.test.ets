import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { S3XmlParser } from '../../../../../main/ets/storage/s3/S3XmlParser';
import { S3Bucket, S3Object, S3Error } from '../../../../../main/ets/storage/s3/S3Types';


export default function S3XmlParserTest() {
  describe('S3XmlParser', () => {
    /**
     * 测试 ListBuckets 响应解析
     */
    describe('parseListBuckets', () => {
      it('should parse valid ListBuckets response', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Owner>
              <ID>owner-id</ID>
              <DisplayName>owner-name</DisplayName>
            </Owner>
            <Buckets>
              <Bucket>
                <Name>my-bucket-1</Name>
                <CreationDate>2024-01-15T10:30:00.000Z</CreationDate>
              </Bucket>
              <Bucket>
                <Name>my-bucket-2</Name>
                <CreationDate>2024-02-20T15:45:00.000Z</CreationDate>
              </Bucket>
            </Buckets>
          </ListAllMyBucketsResult>`;

        const buckets: S3Bucket[] = S3XmlParser.parseListBuckets(xmlStr);

        expect(buckets.length).assertEqual(2);
        expect(buckets[0].name).assertEqual('my-bucket-1');
        expect(buckets[1].name).assertEqual('my-bucket-2');
      });

      it('should parse empty ListBuckets response', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Owner>
              <ID>owner-id</ID>
            </Owner>
            <Buckets>
            </Buckets>
          </ListAllMyBucketsResult>`;

        const buckets: S3Bucket[] = S3XmlParser.parseListBuckets(xmlStr);

        expect(buckets.length).assertEqual(0);
      });

      it('should handle missing creation date', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Buckets>
              <Bucket>
                <Name>bucket-without-date</Name>
              </Bucket>
            </Buckets>
          </ListAllMyBucketsResult>`;

        const buckets: S3Bucket[] = S3XmlParser.parseListBuckets(xmlStr);

        expect(buckets.length).assertEqual(1);
        expect(buckets[0].name).assertEqual('bucket-without-date');
        expect(buckets[0].creationDate).assertEqual(0);
      });

      it('should parse bucket with special characters in name', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Buckets>
              <Bucket>
                <Name>my-special-bucket-2024</Name>
                <CreationDate>2024-03-01T00:00:00.000Z</CreationDate>
              </Bucket>
            </Buckets>
          </ListAllMyBucketsResult>`;

        const buckets: S3Bucket[] = S3XmlParser.parseListBuckets(xmlStr);

        expect(buckets[0].name).assertEqual('my-special-bucket-2024');
      });
    });

    /**
     * 测试 ListObjects 响应解析
     */
    describe('parseListObjects', () => {
      it('should parse valid ListObjects response', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Name>my-bucket</Name>
            <Prefix></Prefix>
            <MaxKeys>1000</MaxKeys>
            <IsTruncated>false</IsTruncated>
            <Contents>
              <Key>folder/file1.txt</Key>
              <LastModified>2024-01-15T10:30:00.000Z</LastModified>
              <ETag>"d41d8cd98f00b204e9800998ecf8427e"</ETag>
              <Size>1024</Size>
            </Contents>
            <Contents>
              <Key>folder/file2.txt</Key>
              <LastModified>2024-02-20T15:45:00.000Z</LastModified>
              <ETag>"098f6bcd4621d373cade4e832627b4f6"</ETag>
              <Size>2048</Size>
            </Contents>
          </ListBucketResult>`;

        const objects: S3Object[] = S3XmlParser.parseListObjects(xmlStr);

        expect(objects.length).assertEqual(2);
        expect(objects[0].key).assertEqual('folder/file1.txt');
        expect(objects[0].size).assertEqual(1024);
        expect(objects[0].etag).assertEqual('d41d8cd98f00b204e9800998ecf8427e');
        expect(objects[1].key).assertEqual('folder/file2.txt');
        expect(objects[1].size).assertEqual(2048);
      });

      it('should parse empty ListObjects response', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Name>empty-bucket</Name>
            <Prefix></Prefix>
            <MaxKeys>1000</MaxKeys>
            <IsTruncated>false</IsTruncated>
          </ListBucketResult>`;

        const objects: S3Object[] = S3XmlParser.parseListObjects(xmlStr);

        expect(objects.length).assertEqual(0);
      });

      it('should remove quotes from ETag', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Name>my-bucket</Name>
            <Contents>
              <Key>file.txt</Key>
              <LastModified>2024-01-15T10:30:00.000Z</LastModified>
              <ETag>"abc123def456"</ETag>
              <Size>100</Size>
            </Contents>
          </ListBucketResult>`;

        const objects: S3Object[] = S3XmlParser.parseListObjects(xmlStr);

        expect(objects[0].etag).assertEqual('abc123def456');
        expect(objects[0].etag.includes('"')).assertFalse();
      });

      it('should handle zero-size objects', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Name>my-bucket</Name>
            <Contents>
              <Key>empty-file.txt</Key>
              <LastModified>2024-01-15T10:30:00.000Z</LastModified>
              <ETag>"d41d8cd98f00b204e9800998ecf8427e"</ETag>
              <Size>0</Size>
            </Contents>
          </ListBucketResult>`;

        const objects: S3Object[] = S3XmlParser.parseListObjects(xmlStr);

        expect(objects[0].size).assertEqual(0);
      });

      it('should parse objects with nested paths', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
            <Name>my-bucket</Name>
            <Contents>
              <Key>deep/nested/path/to/file.kdbx</Key>
              <LastModified>2024-01-15T10:30:00.000Z</LastModified>
              <ETag>"etag-value"</ETag>
              <Size>5000</Size>
            </Contents>
          </ListBucketResult>`;

        const objects: S3Object[] = S3XmlParser.parseListObjects(xmlStr);

        expect(objects[0].key).assertEqual('deep/nested/path/to/file.kdbx');
      });
    });

    /**
     * 测试错误响应解析
     */
    describe('parseError', () => {
      it('should parse error response correctly', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <Error>
            <Code>NoSuchBucket</Code>
            <Message>The specified bucket does not exist</Message>
            <Resource>/my-bucket</Resource>
            <RequestId>ABC123</RequestId>
          </Error>`;

        const error: S3Error = S3XmlParser.parseError(xmlStr);

        expect(error.code).assertEqual('NoSuchBucket');
        expect(error.message).assertEqual('The specified bucket does not exist');
        expect(error.resource).assertEqual('/my-bucket');
      });

      it('should parse AccessDenied error', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <Error>
            <Code>AccessDenied</Code>
            <Message>Access Denied</Message>
            <ResourceId>bucket-name</ResourceId>
          </Error>`;

        const error: S3Error = S3XmlParser.parseError(xmlStr);

        expect(error.code).assertEqual('AccessDenied');
        expect(error.message).assertEqual('Access Denied');
        expect(error.resourceId).assertEqual('bucket-name');
      });

      it('should handle missing optional fields', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <Error>
            <Code>InternalError</Code>
            <Message>We encountered an internal error</Message>
          </Error>`;

        const error: S3Error = S3XmlParser.parseError(xmlStr);

        expect(error.code).assertEqual('InternalError');
        expect(error.message).assertEqual('We encountered an internal error');
        expect(error.resource).assertUndefined();
        expect(error.resourceId).assertUndefined();
      });

      it('should parse NoSuchKey error', 0, () => {
        const xmlStr: string = `<?xml version="1.0" encoding="UTF-8"?>
          <Error>
            <Code>NoSuchKey</Code>
            <Message>The specified key does not exist.</Message>
            <Key>path/to/missing/file.kdbx</Key>
          </Error>`;

        const error: S3Error = S3XmlParser.parseError(xmlStr);

        expect(error.code).assertEqual('NoSuchKey');
        expect(error.message).assertEqual('The specified key does not exist.');
      });
    });
  });
}
