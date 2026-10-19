import { describe, expect, it } from '@ohos/hypium';
import { AutoOpenConfigRebuilder } from '../../../../../main/ets/services/autoopen/AutoOpenConfigRebuilder';
import { AutoOpenItem } from '../../../../../main/ets/services/autoopen/AutoOpenItem';
import { ChildTarget, SchemeMapper } from '../../../../../main/ets/services/autoopen/SchemeMapper';
import { LocalFileStorageConfig } from '../../../../../main/ets/storage/local/LocalFileConfig';
import { WebDAVStorageConfig } from '../../../../../main/ets/storage/webdav/WebDAVConfig';
import { FTPStorageConfig, ProtocolType } from '../../../../../main/ets/storage/ftp/FTPConfig';
import { S3StorageConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { StorageType } from '../../../../../main/ets/storage';

/**
 * 远端子库 storageConfig 重建测试（M6.3）
 */
export default function AutoOpenConfigRebuilderTest() {
  describe('AutoOpenConfigRebuilder', () => {
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
  });
}
