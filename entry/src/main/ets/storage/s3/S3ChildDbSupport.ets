import { ChildDbCredentials } from '../ChildDbCredentials';
import { ChildDbIocFields } from '../ChildDbIocFields';
import { ChildDbRebuildArgs, ChildDbSupport, ChildTarget, IocCredentials } from '../ChildDbSupport';
import { StorageConfig } from '../StorageConfig';
import { StorageType } from '../StorageType';
import { S3ConfigOptions, S3StorageConfig } from './S3Config';

/** S3 超时默认值（毫秒，与 S3StorageConfig 构造默认一致） */
const S3_TIMEOUT_DEFAULT_MS = 30000;

/**
 * S3 子库支持适配器（ChildDbSupport 端口）：
 * ENDPOINT_BUCKET 文法 `s3://endpoint权威/bucket/key`（filePath = `bucket/key`，
 * 与该存储 filePath 约定一致）；统一解析链②由条目 Ioc 凭据
 * （IocUserName=AccessKeyId / IocPassword=SecretAccessKey）+ endpoint/bucket
 * + S3Region/S3PathStyle/IocTimeout 自定义字符串（后两项可选）重建 Config；
 * 写侧提取 AK/SK 加密字段并产出微调字段。
 */
export class S3ChildDbSupport implements ChildDbSupport {
  readonly schemes: string[] = ['s3'];

  /** 打开侧：`s3://endpoint权威/bucket/key` → filePath = `bucket/key` */
  readonly parseTarget = (url: string): ChildTarget | undefined => {
    const parsed = S3ChildDbSupport.parseEndpointBucketUrl(url);
    if (parsed === undefined) {
      return undefined;
    }
    const target = new ChildTarget();
    target.storageType = StorageType.S3;
    target.filePath = parsed.objectPath;
    target.url = url;
    return target;
  };

  /** 写侧：`s3://endpoint权威/bucket/key`；filePath 未含 bucket 前缀时补上 */
  readonly buildUrl = (filePath: string, config?: StorageConfig): string => {
    let endpoint = '';
    let bucket = '';
    if (config !== undefined && config !== null) {
      const record = config as Record<string, Object>;
      endpoint = record['endpoint'] !== undefined ? String(record['endpoint']) : '';
      bucket = record['bucket'] !== undefined ? String(record['bucket']) : '';
    }
    let authority = endpoint.replace(/^https:\/\//, '').replace(/^http:\/\//, '');
    authority = authority.replace(/\/+$/, '');
    let objectPath = filePath.startsWith('/') ? filePath.substring(1) : filePath;
    if (bucket.length > 0 && !objectPath.startsWith(bucket + '/')) {
      objectPath = bucket + '/' + objectPath;
    }
    return 's3://' + authority + '/' + objectPath;
  };

  /** 统一解析链②：Ioc 凭据 + endpoint/bucket + 可选微调字段 → S3StorageConfig */
  readonly rebuildConfig = (args: ChildDbRebuildArgs, target: ChildTarget): StorageConfig | undefined => {
    const parsed = S3ChildDbSupport.parseEndpointBucketUrl(target.url);
    if (args.iocUserName.length === 0 || parsed === undefined || parsed.endpoint.length === 0) {
      return undefined;
    }
    const regionRaw = args.customStrings.get('S3Region') ?? '';
    const region = regionRaw.replace(/^\s+/, '').replace(/\s+$/, '');
    const pathStyleRaw = args.customStrings.get('S3PathStyle') ?? '';
    const options: S3ConfigOptions = {
      region: region.length > 0 ? region : undefined,
      bucket: parsed.bucket.length > 0 ? parsed.bucket : undefined,
      pathStyle: pathStyleRaw.toLowerCase() === 'true',
      timeout: ChildDbIocFields.parseTimeoutMs(args.customStrings)
    };
    return new S3StorageConfig(parsed.endpoint, args.iocUserName, args.iocPassword, options);
  };

  /** 写侧：从 storageConfig 解密提取 AK/SK（类实例与 plain JSON 同名字段） */
  readonly extractCredentials = (config: StorageConfig): IocCredentials | undefined =>
    ChildDbCredentials.fromEncryptedFields(config, 'accessKeyId', 'secretAccessKey');

  /** 写侧附加自定义字符串：非默认 region、开启 pathStyle 或非默认超时时产出微调字段
    *  （保持条目简洁，默认值不写） */
  readonly extraFields = (config: StorageConfig): Map<string, string> => {
    const fields = new Map<string, string>();
    let region = '';
    let pathStyle = false;
    let timeout: number | undefined = undefined;
    if (config instanceof S3StorageConfig) {
      region = config.region ?? '';
      pathStyle = config.pathStyle;
      timeout = config.timeout;
    } else {
      const record = config as Record<string, Object>;
      const regionValue: Object | undefined = record['region'];
      region = regionValue === undefined ? '' : String(regionValue);
      const pathStyleValue: Object | undefined = record['pathStyle'];
      pathStyle = pathStyleValue !== undefined && String(pathStyleValue) === 'true';
      const timeoutValue: Object | undefined = record['timeout'];
      timeout = timeoutValue === undefined ? undefined : Number(timeoutValue);
    }
    if (region.length > 0 && region !== 'us-east-1') {
      fields.set('S3Region', region);
    }
    if (pathStyle) {
      fields.set('S3PathStyle', 'True');
    }
    if (timeout !== undefined && !isNaN(timeout) && timeout > 0 && timeout !== S3_TIMEOUT_DEFAULT_MS) {
      fields.set(ChildDbIocFields.TIMEOUT, String(timeout));
    }
    return fields;
  };

  /**
   * ENDPOINT_BUCKET 文法解析（`s3://endpoint权威/bucket/key`）：
   * endpoint = `https://authority`；rest 为空返回 undefined；
   * 无路径段时 bucket/objectPath 为空串。
   */
  private static parseEndpointBucketUrl(url: string): S3UrlParts | undefined {
    const match = S3ChildDbSupport.SCHEME_PATTERN.exec(url);
    if (match === null) {
      return undefined;
    }
    const rest = match[2];
    if (rest.length === 0) {
      return undefined;
    }
    const parts = new S3UrlParts();
    const slashIdx = rest.indexOf('/');
    const authority = slashIdx >= 0 ? rest.substring(0, slashIdx) : rest;
    const pathPart = slashIdx >= 0 ? rest.substring(slashIdx + 1) : '';
    parts.endpoint = 'https://' + authority;
    if (pathPart.length > 0) {
      const keySlash = pathPart.indexOf('/');
      parts.bucket = keySlash >= 0 ? pathPart.substring(0, keySlash) : pathPart;
      parts.objectPath = pathPart;
    }
    return parts;
  }

  private static readonly SCHEME_PATTERN = /^([a-zA-Z][a-zA-Z0-9+.-]*):\/\/(.*)$/;
}

/**
 * ENDPOINT_BUCKET 文法解析中间结果（适配器内部使用，不外泄）
 */
class S3UrlParts {
  endpoint: string = '';
  bucket: string = '';
  objectPath: string = '';
}
