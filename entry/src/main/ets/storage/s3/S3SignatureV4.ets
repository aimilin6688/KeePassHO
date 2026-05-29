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

    const payloadHash = await this.sha256Hex(payload);

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

    const headers = new Map<string, string>();
    headers.set('host', host);
    headers.set('x-amz-date', amzDate);
    headers.set('x-amz-content-sha256', payloadHash);

    additionalHeaders.forEach((value, key) => {
      headers.set(key.toLowerCase(), value);
    });

    const sortedHeaders = Array.from(headers.entries()).sort((a, b) => a[0].localeCompare(b[0]));
    const signedHeaders = sortedHeaders.map(([k]) => k).join(';');
    const canonicalHeaders = sortedHeaders.map(([k, v]) => `${k}:${v.trim()}`).join('\n');

    const canonicalRequest = this.createCanonicalRequest(
      method,
      uri,
      '',
      signedHeaders,
      canonicalHeaders,
      payloadHash
    );

    const encoder = new util.TextEncoder();
    const canonicalRequestHash = await this.sha256Hex(encoder.encodeInto(canonicalRequest).buffer as ArrayBuffer);

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
    const signatureHex = new util.HexHelper().encodeToStringSync(signature);

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
}
