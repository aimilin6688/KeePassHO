import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils } from 'kdbxweb';

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
  private async sha256Hex(data: Uint8Array | null): Promise<string> {
    let inputData: Uint8Array;
    if (data === null || data === undefined) {
      inputData = new Uint8Array(0);
    } else {
      inputData = data;
    }

    const md = cryptoFramework.createMd('SHA256');
    const dataBlob: cryptoFramework.DataBlob = { data: inputData };
    await md.update(dataBlob);
    const result = await md.digest();
    return ByteUtils.bytesToHex(result.data);
  }

  /**
   * 计算 HMAC-SHA256
   */
  private async hmacSha256(key: Uint8Array, data: string): Promise<Uint8Array> {
    const mac = cryptoFramework.createMac('HMAC|SHA256');
    const symKeyGenerator = cryptoFramework.createSymKeyGenerator('HMAC|SHA256');
    const keyBlob: cryptoFramework.DataBlob = { data: key };
    const symKey = await symKeyGenerator.convertKey(keyBlob);
    await mac.init(symKey);
    const encoder = new util.TextEncoder();
    const dataBlob: cryptoFramework.DataBlob = { data: encoder.encodeInto(data) };
    await mac.update(dataBlob);
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
        for (let j = 0; j < bytes.length; j++) {
          const byte = bytes[j];
          result += '%' + byte.toString(16).toUpperCase().padStart(2, '0');
        }
      }
    }
    return result;
  }

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

  /**
   * 签名请求，返回需要添加的 Headers
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

    const encoder = new util.TextEncoder();
    let payloadBytes: Uint8Array | null = null;
    if (payload !== null) {
      payloadBytes = new Uint8Array(payload);
    }
    const payloadHash = await this.sha256Hex(payloadBytes);

    // 解析 endpoint 获取 host
    let host: string = endpoint;
    if (endpoint.startsWith('https://')) {
      host = endpoint.substring(8);
    } else if (endpoint.startsWith('http://')) {
      host = endpoint.substring(7);
    }
    // 移除路径部分
    const slashIndex: number = host.indexOf('/');
    if (slashIndex > 0) {
      host = host.substring(0, slashIndex);
    }
    // 移除端口部分
    const colonIndex: number = host.indexOf(':');
    if (colonIndex > 0) {
      host = host.substring(0, colonIndex);
    }

    let uri: string = '';
    if (pathStyle) {
      uri = '/' + this.uriEncode(bucket) + '/' + this.uriEncode(key, false);
    } else {
      host = bucket + '.' + host;
      uri = '/' + this.uriEncode(key, false);
    }

    const headers = new Map<string, string>();
    headers.set('host', host);
    headers.set('x-amz-date', amzDate);
    headers.set('x-amz-content-sha256', payloadHash);

    additionalHeaders.forEach((value: string, keyStr: string) => {
      headers.set(keyStr.toLowerCase(), value);
    });

    const entries: [string, string][] = [];
    headers.forEach((value: string, keyStr: string) => {
      entries.push([keyStr, value]);
    });
    entries.sort((a: [string, string], b: [string, string]): number => a[0].localeCompare(b[0]));

    let signedHeaders = '';
    let canonicalHeaders = '';
    for (let i = 0; i < entries.length; i++) {
      if (i > 0) {
        signedHeaders += ';';
      }
      signedHeaders += entries[i][0];
      canonicalHeaders += `${entries[i][0]}:${entries[i][1].trim()}\n`;
    }

    const canonicalRequest = this.createCanonicalRequest(
      method,
      uri,
      '',
      signedHeaders,
      canonicalHeaders,
      payloadHash
    );

    const canonicalRequestHash = await this.sha256Hex(encoder.encodeInto(canonicalRequest));

    const credentialScope = this.createCredentialScope(dateStamp);

    const stringToSign = this.createStringToSign(
      amzDate,
      dateStamp,
      credentialScope,
      canonicalRequestHash
    );

    const kSecret = encoder.encodeInto('AWS4' + this.secretAccessKey);
    const kDate = await this.hmacSha256(kSecret, dateStamp);
    const kRegion = await this.hmacSha256(kDate, this.region);
    const kService = await this.hmacSha256(kRegion, S3SignatureV4.SERVICE);
    const kSigning = await this.hmacSha256(kService, S3SignatureV4.TERMINATOR);

    const signature = await this.hmacSha256(kSigning, stringToSign);
    const signatureHex = ByteUtils.bytesToHex(signature);

    const authorization = this.buildAuthorizationHeader(dateStamp, signedHeaders, signatureHex);
    headers.set('authorization', authorization);

    return headers;
  }

  /**
   * 签名 ListBuckets 请求
   */
  public async signListBuckets(endpoint: string, host: string): Promise<Map<string, string>> {
    const now = new Date();
    const dateStamp = this.formatDate(now);
    const amzDate = this.formatDateTime(now);

    const payloadHash = await this.sha256Hex(null);

    const headers = new Map<string, string>();
    headers.set('host', host);
    headers.set('x-amz-date', amzDate);
    headers.set('x-amz-content-sha256', payloadHash);

    const entries: [string, string][] = [];
    headers.forEach((value: string, keyStr: string) => {
      entries.push([keyStr, value]);
    });
    entries.sort((a: [string, string], b: [string, string]): number => a[0].localeCompare(b[0]));

    let signedHeaders = '';
    let canonicalHeaders = '';
    for (let i = 0; i < entries.length; i++) {
      if (i > 0) {
        signedHeaders += ';';
      }
      signedHeaders += entries[i][0];
      canonicalHeaders += `${entries[i][0]}:${entries[i][1].trim()}\n`;
    }

    const canonicalRequest = this.createCanonicalRequest(
      'GET',
      '/',
      '',
      signedHeaders,
      canonicalHeaders,
      payloadHash
    );

    const encoder = new util.TextEncoder();
    const canonicalRequestHash = await this.sha256Hex(encoder.encodeInto(canonicalRequest));
    const credentialScope = this.createCredentialScope(dateStamp);
    const stringToSign = this.createStringToSign(amzDate, dateStamp, credentialScope, canonicalRequestHash);

    const kSecret = encoder.encodeInto('AWS4' + this.secretAccessKey);
    const kDate = await this.hmacSha256(kSecret, dateStamp);
    const kRegion = await this.hmacSha256(kDate, this.region);
    const kService = await this.hmacSha256(kRegion, S3SignatureV4.SERVICE);
    const kSigning = await this.hmacSha256(kService, S3SignatureV4.TERMINATOR);
    const signature = await this.hmacSha256(kSigning, stringToSign);
    const signatureHex = ByteUtils.bytesToHex(signature);

    const authorization = this.buildAuthorizationHeader(dateStamp, signedHeaders, signatureHex);
    headers.set('authorization', authorization);

    return headers;
  }
}
