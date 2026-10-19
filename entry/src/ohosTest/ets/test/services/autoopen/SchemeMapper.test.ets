import { describe, expect, it } from '@ohos/hypium';
import { ChildTarget, SchemeMapper } from '../../../../../main/ets/services/autoopen/SchemeMapper';
import { FTPStorageConfig, ProtocolType } from '../../../../../main/ets/storage/ftp/FTPConfig';
import { S3StorageConfig } from '../../../../../main/ets/storage/s3/S3Config';
import { PCloudStorage } from '../../../../../main/ets/storage/pcloud/PCloudStorage';
import { FileStorageFactory } from '../../../../../main/ets/storage/FileStorageFactory';
import { StorageType } from '../../../../../main/ets/storage';

/**
 * SchemeMapper scheme → StorageType 映射测试（M6.1/M6.4，注册表驱动）
 */
export default function SchemeMapperTest() {
  describe('SchemeMapper', () => {
    // pCloud 在工厂构造中暂被注释停用；此处注册以验证
    // 「新存储注册即自动接入 scheme 映射，映射器零修改」的注册表驱动设计
    FileStorageFactory.registerStorage(StorageType.PCLOUD, new PCloudStorage());
    // ---------- parse：本地 ----------
    it('parse: bare path is LOCAL with path preserved', 0, () => {
      const target = SchemeMapper.parse('/docs/child.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.LOCAL);
      expect(target!.filePath).assertEqual('/docs/child.kdbx');
      expect(target!.isRemote()).assertFalse();
    });

    it('parse: empty url returns undefined', 0, () => {
      expect(SchemeMapper.parse('')).assertUndefined();
      expect(SchemeMapper.parse('   ')).assertUndefined();
    });

    it('parse: file uri stays LOCAL with original text', 0, () => {
      const target = SchemeMapper.parse('file://docs/child.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.LOCAL);
      expect(target!.filePath).assertEqual('file://docs/child.kdbx');
    });

    // ---------- parse：WebDAV ----------
    it('parse: webdav scheme upgrades to https WEBDAV', 0, () => {
      const target = SchemeMapper.parse('webdav://dav.example.com/dav/child.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.WEBDAV);
      expect(target!.filePath).assertEqual('https://dav.example.com/dav/child.kdbx');
    });

    it('parse: webdavs scheme upgrades to https WEBDAV', 0, () => {
      const target = SchemeMapper.parse('webdavs://dav.example.com/child.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.WEBDAV);
      expect(target!.filePath).assertEqual('https://dav.example.com/child.kdbx');
    });

    it('parse: http/https url is WEBDAV direct', 0, () => {
      const target = SchemeMapper.parse('https://dav.example.com/dav/child.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.WEBDAV);
      expect(target!.filePath).assertEqual('https://dav.example.com/dav/child.kdbx');
      const httpTarget = SchemeMapper.parse('http://dav.example.com/child.kdbx');
      expect(httpTarget !== undefined).assertTrue();
      expect(httpTarget!.storageType).assertEqual(StorageType.WEBDAV);
    });

    it('parse: webdav with empty rest returns undefined', 0, () => {
      expect(SchemeMapper.parse('webdav://')).assertUndefined();
      expect(SchemeMapper.parse('webdavs://')).assertUndefined();
    });

    // ---------- parse：FTP/SFTP ----------
    it('parse: ftp url with port and path', 0, () => {
      const target = SchemeMapper.parse('ftp://files.example.com:2121/remote/child.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.FTP);
      expect(target!.sftp).assertFalse();
      expect(target!.host).assertEqual('files.example.com');
      expect(target!.port).assertEqual(2121);
      expect(target!.filePath).assertEqual('/remote/child.kdbx');
    });

    it('parse: sftp url defaults port 0 and keeps leading slash', 0, () => {
      const target = SchemeMapper.parse('sftp://files.example.com/remote/child.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.FTP);
      expect(target!.sftp).assertTrue();
      expect(target!.port).assertEqual(0);
      expect(target!.filePath).assertEqual('/remote/child.kdbx');
    });

    it('parse: ftp without path normalizes filePath to root', 0, () => {
      const target = SchemeMapper.parse('ftp://files.example.com');
      expect(target !== undefined).assertTrue();
      expect(target!.host).assertEqual('files.example.com');
      expect(target!.filePath).assertEqual('/');
    });

    it('parse: ftp with empty rest or empty host returns undefined', 0, () => {
      expect(SchemeMapper.parse('ftp://')).assertUndefined();
      expect(SchemeMapper.parse('sftp://')).assertUndefined();
      expect(SchemeMapper.parse('ftp:///remote/child.kdbx')).assertUndefined();
    });

    // ---------- parse：S3 ----------
    it('parse: s3 url yields endpoint bucket and bucket/key path', 0, () => {
      const target = SchemeMapper.parse('s3://s3.amazonaws.com/mybucket/db/child.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.S3);
      expect(target!.endpoint).assertEqual('https://s3.amazonaws.com');
      expect(target!.bucket).assertEqual('mybucket');
      expect(target!.filePath).assertEqual('mybucket/db/child.kdbx');
    });

    it('parse: s3 with empty rest returns undefined', 0, () => {
      expect(SchemeMapper.parse('s3://')).assertUndefined();
    });

    // ---------- parse：OAuth 云盘 ----------
    it('parse: oauth cloud schemes map to storage types with rest preserved', 0, () => {
      const onedrive = SchemeMapper.parse('onedrive://root/child.kdbx');
      expect(onedrive !== undefined).assertTrue();
      expect(onedrive!.storageType).assertEqual(StorageType.ONEDRIVE);
      expect(onedrive!.filePath).assertEqual('root/child.kdbx');
      const huawei = SchemeMapper.parse('huawei-drive:///child.kdbx');
      expect(huawei !== undefined).assertTrue();
      expect(huawei!.storageType).assertEqual(StorageType.HUAWEI_DRIVE);
      expect(huawei!.filePath).assertEqual('/child.kdbx');
      const baidu = SchemeMapper.parse('baidu://apps/child.kdbx');
      expect(baidu !== undefined).assertTrue();
      expect(baidu!.storageType).assertEqual(StorageType.BAIDU_NETDISK);
      expect(baidu!.filePath).assertEqual('apps/child.kdbx');
      const pcloud = SchemeMapper.parse('pcloud://child.kdbx');
      expect(pcloud !== undefined).assertTrue();
      expect(pcloud!.storageType).assertEqual(StorageType.PCLOUD);
      expect(pcloud!.filePath).assertEqual('child.kdbx');
    });

    it('parse: unknown scheme returns undefined', 0, () => {
      expect(SchemeMapper.parse('foo://host/child.kdbx')).assertUndefined();
      expect(SchemeMapper.parse('webdavx://host/child.kdbx')).assertUndefined();
    });

    // ---------- resolveTarget：占位符 + scheme 组合 ----------
    it('resolveTarget: expands placeholders then parses scheme', 0, () => {
      const target = SchemeMapper.resolveTarget(
        '{DB_DIR}{ENV_DIRSEP}child.kdbx', '/docs/parent.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.LOCAL);
      expect(target!.filePath).assertEqual('/docs/child.kdbx');
    });

    it('resolveTarget: remote scheme url unaffected by parent path', 0, () => {
      const target = SchemeMapper.resolveTarget(
        'webdav://dav.example.com/dav/child.kdbx', '/docs/parent.kdbx');
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.WEBDAV);
      expect(target!.filePath).assertEqual('https://dav.example.com/dav/child.kdbx');
    });

    it('resolveTarget: empty url returns undefined', 0, () => {
      expect(SchemeMapper.resolveTarget('', '/docs/parent.kdbx')).assertUndefined();
    });

    // ---------- buildUrl：写侧反向映射 ----------
    it('buildUrl: WEBDAV returns filePath as-is', 0, () => {
      const url = 'https://dav.example.com/dav/child.kdbx';
      expect(SchemeMapper.buildUrl(StorageType.WEBDAV, url)).assertEqual(url);
    });

    it('buildUrl: FTP config yields ftp url with custom port', 0, () => {
      const config = new FTPStorageConfig('files.example.com', 'user', 'pass', { port: 2121 });
      const url = SchemeMapper.buildUrl(StorageType.FTP, '/remote/child.kdbx', config);
      expect(url).assertEqual('ftp://files.example.com:2121/remote/child.kdbx');
    });

    it('buildUrl: SFTP config omits default port 22', 0, () => {
      const config = new FTPStorageConfig('files.example.com', 'user', 'pass',
        { protocol: ProtocolType.SFTP });
      const url = SchemeMapper.buildUrl(StorageType.FTP, 'remote/child.kdbx', config);
      expect(url).assertEqual('sftp://files.example.com/remote/child.kdbx');
    });

    it('buildUrl: S3 config prefixes bucket when missing in path', 0, () => {
      const config = new S3StorageConfig('https://s3.amazonaws.com', 'ak', 'sk',
        { bucket: 'mybucket' });
      const url = SchemeMapper.buildUrl(StorageType.S3, 'db/child.kdbx', config);
      expect(url).assertEqual('s3://s3.amazonaws.com/mybucket/db/child.kdbx');
    });

    it('buildUrl: S3 path already containing bucket is not duplicated', 0, () => {
      const config = new S3StorageConfig('https://s3.amazonaws.com', 'ak', 'sk',
        { bucket: 'mybucket' });
      const url = SchemeMapper.buildUrl(StorageType.S3, 'mybucket/db/child.kdbx', config);
      expect(url).assertEqual('s3://s3.amazonaws.com/mybucket/db/child.kdbx');
    });

    it('buildUrl: oauth types prefix scheme', 0, () => {
      expect(SchemeMapper.buildUrl(StorageType.ONEDRIVE, 'root/child.kdbx'))
        .assertEqual('onedrive://root/child.kdbx');
      expect(SchemeMapper.buildUrl(StorageType.HUAWEI_DRIVE, 'child.kdbx'))
        .assertEqual('huawei-drive://child.kdbx');
      expect(SchemeMapper.buildUrl(StorageType.BAIDU_NETDISK, 'apps/child.kdbx'))
        .assertEqual('baidu://apps/child.kdbx');
      expect(SchemeMapper.buildUrl(StorageType.PCLOUD, 'child.kdbx'))
        .assertEqual('pcloud://child.kdbx');
    });

    it('buildUrl: LOCAL returns filePath as-is', 0, () => {
      expect(SchemeMapper.buildUrl(StorageType.LOCAL, '/docs/child.kdbx'))
        .assertEqual('/docs/child.kdbx');
    });

    // ---------- parse ↔ buildUrl 往返 ----------
    it('round-trip: FTP config build → parse restores connection facts', 0, () => {
      const config = new FTPStorageConfig('files.example.com', 'user', 'pass', { port: 2121 });
      const url = SchemeMapper.buildUrl(StorageType.FTP, '/remote/child.kdbx', config);
      const target = SchemeMapper.parse(url);
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.FTP);
      expect(target!.host).assertEqual('files.example.com');
      expect(target!.port).assertEqual(2121);
      expect(target!.filePath).assertEqual('/remote/child.kdbx');
    });

    it('round-trip: S3 config build → parse restores endpoint and path', 0, () => {
      const config = new S3StorageConfig('https://s3.amazonaws.com', 'ak', 'sk',
        { bucket: 'mybucket' });
      const url = SchemeMapper.buildUrl(StorageType.S3, 'db/child.kdbx', config);
      const target = SchemeMapper.parse(url);
      expect(target !== undefined).assertTrue();
      expect(target!.storageType).assertEqual(StorageType.S3);
      expect(target!.endpoint).assertEqual('https://s3.amazonaws.com');
      expect(target!.filePath).assertEqual('mybucket/db/child.kdbx');
    });

    it('ChildTarget: isRemote reflects storage type', 0, () => {
      const local = new ChildTarget();
      expect(local.isRemote()).assertFalse();
      const remote = new ChildTarget();
      remote.storageType = StorageType.WEBDAV;
      expect(remote.isRemote()).assertTrue();
    });
  });
}
