import { describe, expect, it } from '@ohos/hypium';

import { ChildDbIocFields } from '../../../../main/ets/storage/ChildDbIocFields';
import { StorageConfig } from '../../../../main/ets/storage/StorageConfig';
import { WebDAVChildDbSupport } from '../../../../main/ets/storage/webdav/WebDAVChildDbSupport';
import { WebDAVStorage } from '../../../../main/ets/storage/webdav/WebDAVStorage';
import { CertValidationMode, WebDAVStorageConfig } from '../../../../main/ets/storage/webdav/WebDAVConfig';
import { FTPChildDbSupport } from '../../../../main/ets/storage/ftp/FTPChildDbSupport';
import { FTPStorageConfig } from '../../../../main/ets/storage/ftp/FTPConfig';
import { S3ChildDbSupport } from '../../../../main/ets/storage/s3/S3ChildDbSupport';
import { S3StorageConfig } from '../../../../main/ets/storage/s3/S3Config';

/**
 * M7 子库 Ioc 高级连接字段（kp2a IocKnownProperties）存储层单元测试：
 * - ChildDbIocFields 共享解析（超时/布尔/字符串）
 * - 各适配器写侧 extraFields（类实例与 Worker JSON plain 对象两分支、默认值省略）
 * - WebDAVStorage.parseConfig plain 对象全字段重建（Worker JSON 通道保真回归）
 */

/** Worker JSON 通道形状：类实例序列化往返为 plain 对象（instanceof 不成立） */
function toPlain(config: StorageConfig): StorageConfig {
  return JSON.parse(JSON.stringify(config)) as StorageConfig;
}

export default function ChildDbIocFieldsTest() {
  describe('ChildDbIocFieldsParser', () => {
    const fields = new Map<string, string>();

    it('parseTimeoutMs: parses positive integer milliseconds', 0, () => {
      fields.clear();
      fields.set('IocTimeout', '15000');
      expect(ChildDbIocFields.parseTimeoutMs(fields)).assertEqual(15000);
    });

    it('parseTimeoutMs: trims surrounding whitespace', 0, () => {
      fields.clear();
      fields.set('IocTimeout', '  8000 \t');
      expect(ChildDbIocFields.parseTimeoutMs(fields)).assertEqual(8000);
    });

    it('parseTimeoutMs: truncates decimal value', 0, () => {
      fields.clear();
      fields.set('IocTimeout', '12345.9');
      expect(ChildDbIocFields.parseTimeoutMs(fields)).assertEqual(12345);
    });

    it('parseTimeoutMs: rejects non-numeric value', 0, () => {
      fields.clear();
      fields.set('IocTimeout', 'abc');
      expect(ChildDbIocFields.parseTimeoutMs(fields)).assertUndefined();
    });

    it('parseTimeoutMs: rejects zero and negative value', 0, () => {
      fields.clear();
      fields.set('IocTimeout', '0');
      expect(ChildDbIocFields.parseTimeoutMs(fields)).assertUndefined();
      fields.set('IocTimeout', '-5000');
      expect(ChildDbIocFields.parseTimeoutMs(fields)).assertUndefined();
    });

    it('parseTimeoutMs: treats missing empty and blank as unset', 0, () => {
      fields.clear();
      expect(ChildDbIocFields.parseTimeoutMs(fields)).assertUndefined();
      fields.set('IocTimeout', '');
      expect(ChildDbIocFields.parseTimeoutMs(fields)).assertUndefined();
      fields.set('IocTimeout', '   ');
      expect(ChildDbIocFields.parseTimeoutMs(fields)).assertUndefined();
    });

    it('parseBool: case-insensitive true/false with trimming', 0, () => {
      fields.clear();
      fields.set('IocPreAuth', 'True');
      expect(ChildDbIocFields.parseBool(fields, 'IocPreAuth')).assertTrue();
      fields.set('IocPreAuth', 'TRUE');
      expect(ChildDbIocFields.parseBool(fields, 'IocPreAuth')).assertTrue();
      fields.set('IocPreAuth', ' false ');
      expect(ChildDbIocFields.parseBool(fields, 'IocPreAuth')).assertFalse();
    });

    it('parseBool: unset for missing or unrecognized value', 0, () => {
      fields.clear();
      expect(ChildDbIocFields.parseBool(fields, 'IocPreAuth')).assertUndefined();
      fields.set('IocPreAuth', 'yes');
      expect(ChildDbIocFields.parseBool(fields, 'IocPreAuth')).assertUndefined();
    });

    it('parseString: returns trimmed value and empty for unset', 0, () => {
      fields.clear();
      expect(ChildDbIocFields.parseString(fields, 'IocUserAgent')).assertEqual('');
      fields.set('IocUserAgent', ' KeePassHO/1.0 ');
      expect(ChildDbIocFields.parseString(fields, 'IocUserAgent')).assertEqual('KeePassHO/1.0');
    });
  });

  describe('ChildDbIocAdapterExtraFields', () => {
    it('WEBDAV extraFields emits non-default advanced fields from config instance', 0, () => {
      const adapter = new WebDAVChildDbSupport();
      const config = new WebDAVStorageConfig('https://dav.example.com', 'davuser', 'davpass', {
        timeout: 12345,
        userAgent: 'KeePassHO/1.0',
        preAuth: true,
        expect100Continue: true
      });
      const result = adapter.extraFields(config);
      expect(result.get(ChildDbIocFields.TIMEOUT)).assertEqual('12345');
      expect(result.get(ChildDbIocFields.USER_AGENT)).assertEqual('KeePassHO/1.0');
      expect(result.get(ChildDbIocFields.PRE_AUTH)).assertEqual('True');
      expect(result.get(ChildDbIocFields.EXPECT_100_CONTINUE)).assertEqual('True');
    });

    it('WEBDAV extraFields omits defaults (keeps entry concise)', 0, () => {
      const adapter = new WebDAVChildDbSupport();
      const config = new WebDAVStorageConfig('https://dav.example.com', 'davuser', 'davpass');
      expect(adapter.extraFields(config).size).assertEqual(0);
    });

    it('WEBDAV extraFields reads plain worker JSON config', 0, () => {
      const adapter = new WebDAVChildDbSupport();
      const config = new WebDAVStorageConfig('https://dav.example.com', 'davuser', 'davpass', {
        timeout: 12345,
        userAgent: 'KeePassHO/1.0',
        preAuth: true,
        expect100Continue: true
      });
      const result = adapter.extraFields(toPlain(config));
      expect(result.get(ChildDbIocFields.TIMEOUT)).assertEqual('12345');
      expect(result.get(ChildDbIocFields.USER_AGENT)).assertEqual('KeePassHO/1.0');
      expect(result.get(ChildDbIocFields.PRE_AUTH)).assertEqual('True');
      expect(result.get(ChildDbIocFields.EXPECT_100_CONTINUE)).assertEqual('True');
    });

    it('FTP extraFields emits non-default timeout from instance and plain config', 0, () => {
      const adapter = new FTPChildDbSupport();
      const custom = new FTPStorageConfig('files.example.com', 'ftpuser', 'ftppass', { timeout: 45000 });
      expect(adapter.extraFields(custom).get(ChildDbIocFields.TIMEOUT)).assertEqual('45000');
      const customPlain = adapter.extraFields(toPlain(custom));
      expect(customPlain.get(ChildDbIocFields.TIMEOUT)).assertEqual('45000');
    });

    it('FTP extraFields omits default timeout 30000', 0, () => {
      const adapter = new FTPChildDbSupport();
      const defaultConfig = new FTPStorageConfig('files.example.com', 'ftpuser', 'ftppass');
      expect(adapter.extraFields(defaultConfig).size).assertEqual(0);
      expect(adapter.extraFields(toPlain(defaultConfig)).size).assertEqual(0);
    });

    it('S3 extraFields emits non-default timeout from instance and plain config', 0, () => {
      const adapter = new S3ChildDbSupport();
      const custom = new S3StorageConfig('https://s3.example.com', 'AKID', 'SECRET', {
        region: 'cn-north-1',
        pathStyle: true,
        timeout: 60000
      });
      const result = adapter.extraFields(custom);
      expect(result.get('S3Region')).assertEqual('cn-north-1');
      expect(result.get('S3PathStyle')).assertEqual('True');
      expect(result.get(ChildDbIocFields.TIMEOUT)).assertEqual('60000');
      const plainResult = adapter.extraFields(toPlain(custom));
      expect(plainResult.get(ChildDbIocFields.TIMEOUT)).assertEqual('60000');
      expect(plainResult.get('S3Region')).assertEqual('cn-north-1');
    });

    it('S3 extraFields omits defaults (region us-east-1 / pathStyle false / timeout 30000)', 0, () => {
      const adapter = new S3ChildDbSupport();
      const defaultConfig = new S3StorageConfig('https://s3.example.com', 'AKID', 'SECRET');
      expect(adapter.extraFields(defaultConfig).size).assertEqual(0);
      expect(adapter.extraFields(toPlain(defaultConfig)).size).assertEqual(0);
    });
  });

  describe('WebDAVStorageParseConfig', () => {
    it('parseConfig rebuilds all connection fields from plain worker JSON config', 0, () => {
      const full = new WebDAVStorageConfig('https://dav.example.com', 'davuser', 'davpass', {
        timeout: 12345,
        certValidationMode: CertValidationMode.CUSTOM_CA,
        customCaCertContent: '-----BEGIN CERTIFICATE-----',
        userAgent: 'KeePassHO/1.0',
        preAuth: true,
        expect100Continue: true
      });
      // Worker JSON 通道：字符串化往返后为 plain 对象（instanceof 不成立、SM4 凭据保留前缀）
      const plain = JSON.parse(JSON.stringify(full)) as WebDAVStorageConfig;
      expect(plain instanceof WebDAVStorageConfig).assertFalse();
      const storage = new WebDAVStorage();
      const parsed = storage.parseConfig(plain);
      expect(parsed instanceof WebDAVStorageConfig).assertTrue();
      expect(parsed.url).assertEqual('https://dav.example.com');
      expect(parsed.getUserNameText()).assertEqual('davuser');
      expect(parsed.getPasswordText()).assertEqual('davpass');
      expect(parsed.timeout).assertEqual(12345);
      expect(parsed.certValidationMode).assertEqual(CertValidationMode.CUSTOM_CA);
      expect(parsed.customCaCertContent).assertEqual('-----BEGIN CERTIFICATE-----');
      expect(parsed.userAgent).assertEqual('KeePassHO/1.0');
      expect(parsed.preAuth).assertTrue();
      expect(parsed.expect100Continue).assertTrue();
    });

    it('parseConfig keeps instance config as-is (reference passthrough)', 0, () => {
      const config = new WebDAVStorageConfig('https://dav.example.com', 'davuser', 'davpass');
      const storage = new WebDAVStorage();
      expect(storage.parseConfig(config) === config).assertTrue();
    });
  });
}
