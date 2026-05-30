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