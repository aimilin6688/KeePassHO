import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { AutoOpenConfigRebuilder } from '../../../../../main/ets/services/autoopen/AutoOpenConfigRebuilder';
import { AutoOpenItem } from '../../../../../main/ets/services/autoopen/AutoOpenItem';
import { ChildTarget, SchemeMapper } from '../../../../../main/ets/services/autoopen/SchemeMapper';
import { RecentFile } from '../../../../../main/ets/services/TypeDefined';
import { LocalFileStorageConfig } from '../../../../../main/ets/storage/local/LocalFileConfig';
import { CertValidationMode, WebDAVStorageConfig } from '../../../../../main/ets/storage/webdav/WebDAVConfig';
import { WebDAVChildDbSupport } from '../../../../../main/ets/storage/webdav/WebDAVChildDbSupport';
import { FTPStorageConfig, ProtocolType } from '../../../../../main/ets/storage/ftp/FTPConfig';
import { S3StorageConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { OneDriveStorageConfig } from '../../../../../main/ets/storage/onedrive/OneDriveConfig';
import { PathChildDbSupport } from '../../../../../main/ets/storage';
import { StorageType } from '../../../../../main/ets/storage';
import { ResourceManager } from '../../../../../main/ets/common/utils';

/**
 * 构造带 Ioc 凭据的 AutoOpen 条目模型（customStrings 透传 S3 微调字段）
 */
function makeItem(iocUserName: string, iocPassword: string,
  s3Region: string = '', s3PathStyle: boolean = false): AutoOpenItem {
  const item = new AutoOpenItem();
  item.title = 'child';
  item.iocUserName = iocUserName;
  item.iocPassword = iocPassword;
  if (s3Region.length > 0) {
    item.customStrings.set('S3Region', s3Region);
  }
  if (s3PathStyle) {
    item.customStrings.set('S3PathStyle', 'True');
  }
  return item;
}

/**
 * 远端子库 storageConfig 重建测试（M6.3）
 */
export default function AutoOpenConfigRebuilderTest() {
  describe('AutoOpenConfigRebuilder', () => {
    beforeAll(() => {
      // 失败文案经 ResourceManager 本地化，测试环境需注入真实 context
      const appContext: common.Context = abilityDelegatorRegistry.getAbilityDelegator()
        .getAppContext().getApplicationContext();
      ResourceManager.getInstance().init(appContext as common.UIAbilityContext);
    });

    it('LOCAL builds LocalFileStorageConfig', 0, async () => {
      const target = SchemeMapper.parse('/docs/child.kdbx');
      expect(target !== undefined).assertTrue();
      const result = await AutoOpenConfigRebuilder.build(makeItem('', ''), target!);
      expect(result.config !== undefined).assertTrue();
      expect(result.config instanceof LocalFileStorageConfig).assertTrue();
      expect(result.failReason).assertEqual('');
    });

    it('WEBDAV builds config with origin url and Ioc credentials', 0, async () => {
      const target = SchemeMapper.parse('webdav://dav.example.com/dav/child.kdbx');
      expect(target !== undefined).assertTrue();
      const result = await AutoOpenConfigRebuilder.build(
        makeItem('davuser', 'davpass'), target!);
      expect(result.config !== undefined).assertTrue();
      const config = result.config as WebDAVStorageConfig;
      expect(config.url).assertEqual('https://dav.example.com');
      expect(config.getUserNameText()).assertEqual('davuser');
      expect(config.getPasswordText()).assertEqual('davpass');
      expect(result.failReason).assertEqual('');
    });

    it('WEBDAV without IocUserName fails with reason', 0, async () => {
      const target = SchemeMapper.parse('https://dav.example.com/dav/child.kdbx');
      expect(target !== undefined).assertTrue();
      const result = await AutoOpenConfigRebuilder.build(makeItem('', ''), target!);
      expect(result.config).assertUndefined();
      expect(result.failReason.length > 0).assertTrue();
    });

    it('FTP builds config with host port and credentials', 0, async () => {
      const target = SchemeMapper.parse('ftp://files.example.com:2121/remote/child.kdbx');
      expect(target !== undefined).assertTrue();
      const result = await AutoOpenConfigRebuilder.build(
        makeItem('ftpuser', 'ftppass'), target!);
      expect(result.config !== undefined).assertTrue();
      const config = result.config as FTPStorageConfig;
      expect(config.host).assertEqual('files.example.com');
      expect(config.port).assertEqual(2121);
      expect(config.protocol).assertEqual(ProtocolType.FTP);
      expect(config.getUserNameText()).assertEqual('ftpuser');
      expect(config.getPasswordText()).assertEqual('ftppass');
    });

    it('SFTP defaults port to 22 when unspecified', 0, async () => {
      const target = SchemeMapper.parse('sftp://files.example.com/remote/child.kdbx');
      expect(target !== undefined).assertTrue();
      const result = await AutoOpenConfigRebuilder.build(
        makeItem('sftpuser', 'sftppass'), target!);
      expect(result.config !== undefined).assertTrue();
      const config = result.config as FTPStorageConfig;
      expect(config.port).assertEqual(22);
      expect(config.isSFTP()).assertTrue();
    });

    it('FTP without Ioc credentials fails with reason', 0, async () => {
      const target = SchemeMapper.parse('ftp://files.example.com/remote/child.kdbx');
      expect(target !== undefined).assertTrue();
      const result = await AutoOpenConfigRebuilder.build(makeItem('', ''), target!);
      expect(result.config).assertUndefined();
      expect(result.failReason.length > 0).assertTrue();
    });

    it('S3 builds config with endpoint bucket and tuning fields', 0, async () => {
      const target = SchemeMapper.parse('s3://s3.example.com/mybucket/db/child.kdbx');
      expect(target !== undefined).assertTrue();
      const result = await AutoOpenConfigRebuilder.build(
        makeItem('AKID', 'SECRET', 'cn-north-1', true), target!);
      expect(result.config !== undefined).assertTrue();
      const config = result.config as S3StorageConfig;
      expect(config.endpoint).assertEqual('https://s3.example.com');
      expect(config.bucket).assertEqual('mybucket');
      expect(config.region).assertEqual('cn-north-1');
      expect(config.pathStyle).assertTrue();
      expect(config.getAccessKeyIdText()).assertEqual('AKID');
      expect(config.getSecretAccessKeyText()).assertEqual('SECRET');
    });

    it('S3 without Ioc credentials fails with reason', 0, async () => {
      const target = SchemeMapper.parse('s3://s3.example.com/mybucket/child.kdbx');
      expect(target !== undefined).assertTrue();
      const result = await AutoOpenConfigRebuilder.build(makeItem('', ''), target!);
      expect(result.config).assertUndefined();
      expect(result.failReason.length > 0).assertTrue();
    });

    it('OAuth type without matching recent file fails with reason', 0, async () => {
      const target = SchemeMapper.parse('onedrive://root/child.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.ONEDRIVE);
      // 测试环境 RecentFilesService 未 init（preferences 为空）→ 返回空列表 → 未命中
      const result = await AutoOpenConfigRebuilder.build(makeItem('', ''), target!);
      expect(result.config).assertUndefined();
      expect(result.failReason.length > 0).assertTrue();
    });

    it('ChildTarget isRemote distinguishes local from remote', 0, () => {
      const local = new ChildTarget();
      expect(local.isRemote()).assertFalse();
      const remote = new ChildTarget();
      remote.storageType = StorageType.S3;
      expect(remote.isRemote()).assertTrue();
    });

    // ==================== M6.9 统一解析链（resolve 纯函数链序） ====================

    it('resolve: RecentFiles hit takes precedence over rebuildConfig and keeps cert options', 0, () => {
      const target = SchemeMapper.parse('webdav://dav.example.com/dav/child.kdbx');
      expect(target !== undefined).assertTrue();
      // 链①数据源：带证书校验选项的完整配置（rebuildConfig 产不出的字段）
      const saved: RecentFile = {
        filePath: target!.filePath,
        fileName: 'child.kdbx',
        storageType: StorageType.WEBDAV,
        storageConfig: new WebDAVStorageConfig('https://dav.example.com', 'olduser', 'oldpass', {
          certValidationMode: CertValidationMode.CUSTOM_CA,
          customCaCertContent: '-----BEGIN CERTIFICATE-----'
        })
      };
      // 链②兜底可用（条目凭据有效）但链①命中优先
      const result = AutoOpenConfigRebuilder.resolve(
        makeItem('davuser', 'davpass'), target!, [saved], new WebDAVChildDbSupport());
      expect(result.config === saved.storageConfig).assertTrue();
      expect(result.failReason).assertEqual('');
      const config = result.config as WebDAVStorageConfig;
      expect(config.certValidationMode).assertEqual(CertValidationMode.CUSTOM_CA);
      expect(config.getUserNameText()).assertEqual('olduser');
    });

    it('resolve: RecentFiles miss falls back to rebuildConfig', 0, () => {
      const target = SchemeMapper.parse('webdav://dav.example.com/dav/child.kdbx');
      expect(target !== undefined).assertTrue();
      const result = AutoOpenConfigRebuilder.resolve(
        makeItem('davuser', 'davpass'), target!, [], new WebDAVChildDbSupport());
      expect(result.config !== undefined).assertTrue();
      expect(result.failReason).assertEqual('');
      const config = result.config as WebDAVStorageConfig;
      expect(config.url).assertEqual('https://dav.example.com');
      expect(config.getUserNameText()).assertEqual('davuser');
    });

    it('resolve: RecentFiles match requires storageType and filePath jointly', 0, () => {
      const target = SchemeMapper.parse('webdav://dav.example.com/dav/child.kdbx');
      expect(target !== undefined).assertTrue();
      // 同 filePath 不同存储类型 / 同存储类型不同 filePath：均不命中 → 走链②
      const wrongType: RecentFile = {
        filePath: target!.filePath,
        fileName: 'child.kdbx',
        storageType: StorageType.ONEDRIVE,
        storageConfig: new OneDriveStorageConfig('t', 'r', 0)
      };
      const wrongPath: RecentFile = {
        filePath: 'https://other.example.com/dav/child.kdbx',
        fileName: 'child.kdbx',
        storageType: StorageType.WEBDAV,
        storageConfig: new WebDAVStorageConfig('https://other.example.com', 'u', 'p')
      };
      const result = AutoOpenConfigRebuilder.resolve(
        makeItem('davuser', 'davpass'), target!, [wrongType, wrongPath], new WebDAVChildDbSupport());
      expect(result.config !== undefined).assertTrue();
      const config = result.config as WebDAVStorageConfig;
      expect(config.url).assertEqual('https://dav.example.com');
    });

    it('resolve: OAuth type with recent hit reuses config', 0, () => {
      const target = SchemeMapper.parse('onedrive://root/child.kdbx');
      expect(target !== undefined).assertTrue();
      const saved: RecentFile = {
        filePath: target!.filePath,
        fileName: 'child.kdbx',
        storageType: StorageType.ONEDRIVE,
        storageConfig: new OneDriveStorageConfig('token', 'refresh', 3600)
      };
      const result = AutoOpenConfigRebuilder.resolve(
        makeItem('', ''), target!, [saved], new PathChildDbSupport(StorageType.ONEDRIVE, 'onedrive'));
      expect(result.config === saved.storageConfig).assertTrue();
      expect(result.failReason).assertEqual('');
    });

    it('resolve: chain distinguishes credential-missing from not-opened reasons', 0, () => {
      const webdavTarget = SchemeMapper.parse('webdav://dav.example.com/dav/child.kdbx');
      expect(webdavTarget !== undefined).assertTrue();
      const credentialMissing = AutoOpenConfigRebuilder.resolve(
        makeItem('', ''), webdavTarget!, [], new WebDAVChildDbSupport());
      const oauthTarget = SchemeMapper.parse('onedrive://root/child.kdbx');
      expect(oauthTarget !== undefined).assertTrue();
      const notOpened = AutoOpenConfigRebuilder.resolve(
        makeItem('', ''), oauthTarget!, [], new PathChildDbSupport(StorageType.ONEDRIVE, 'onedrive'));
      expect(credentialMissing.config).assertUndefined();
      expect(notOpened.config).assertUndefined();
      expect(credentialMissing.failReason.length > 0).assertTrue();
      expect(notOpened.failReason.length > 0).assertTrue();
      expect(credentialMissing.failReason === notOpened.failReason).assertFalse();
    });

    it('resolve: LOCAL ignores recent files and childDb', 0, () => {
      const target = SchemeMapper.parse('/docs/child.kdbx');
      expect(target !== undefined).assertTrue();
      const result = AutoOpenConfigRebuilder.resolve(
        makeItem('', ''), target!, [], undefined);
      expect(result.config !== undefined).assertTrue();
      expect(result.config instanceof LocalFileStorageConfig).assertTrue();
      expect(result.failReason).assertEqual('');
    });
  });
}
