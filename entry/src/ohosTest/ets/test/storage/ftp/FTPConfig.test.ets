import { describe, expect, it } from '@ohos/hypium';
import { FTPPageConfig, FTPStorageConfig, ProtocolType, SecureType } from '../../../../../main/ets/storage/ftp/FTPConfig';
import { StorageType } from '../../../../../main/ets/storage/StorageType';

export default function FTPConfigTest() {
  describe('FTPConfigTest', () => {

    describe('ProtocolType', () => {
      it('FTP should equal FTP', 0, () => {
        expect(ProtocolType.FTP).assertEqual('FTP');
      });

      it('SFTP should equal SFTP', 0, () => {
        expect(ProtocolType.SFTP).assertEqual('SFTP');
      });

      it('should expose 2 members', 0, () => {
        expect(Object.keys(ProtocolType).length).assertEqual(2);
      });

      it('FTP and SFTP should differ', 0, () => {
        const ftpProto: string = ProtocolType.FTP;
        const sftpProto: string = ProtocolType.SFTP;
        expect(ftpProto !== sftpProto).assertTrue();
      });
    });

    describe('SecureType', () => {
      it('should accept boolean true', 0, () => {
        const s: SecureType = true;
        expect(s).assertTrue();
      });

      it('should accept boolean false', 0, () => {
        const s: SecureType = false;
        expect(s).assertFalse();
      });

      it('should accept implicit string', 0, () => {
        const s: SecureType = 'implicit';
        expect(s).assertEqual('implicit');
      });
    });

    describe('FTPStorageConfig_construction_defaults', () => {
      it('should default port to 21 for FTP', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('ftp.example.com', 'u', 'p');
        expect(cfg.port).assertEqual(21);
      });

      it('should default port to 22 for SFTP', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('sftp.example.com', 'u', 'p',
          { protocol: ProtocolType.SFTP });
        expect(cfg.port).assertEqual(22);
      });

      it('should default timeout to 30000', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p');
        expect(cfg.timeout).assertEqual(30000);
      });

      it('should default protocol to FTP', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p');
        expect(cfg.protocol).assertEqual(ProtocolType.FTP);
      });

      it('should default secure to undefined', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p');
        expect(cfg.secure).assertUndefined();
      });

      it('should store host as provided (plaintext)', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('ftp.example.com', 'u', 'p');
        expect(cfg.host).assertEqual('ftp.example.com');
      });

      it('should encrypt username/password and decrypt back', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'myuser', 'mypass');
        expect(cfg.getUserNameText()).assertEqual('myuser');
        expect(cfg.getPasswordText()).assertEqual('mypass');
      });

      it('should not store plaintext username/password', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'plainuser', 'plainpass');
        expect(cfg.username !== 'plainuser').assertTrue();
        expect(cfg.password !== 'plainpass').assertTrue();
      });
    });

    describe('FTPStorageConfig_options', () => {
      it('should accept custom port override', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p', { port: 2121 });
        expect(cfg.port).assertEqual(2121);
      });

      it('should accept custom timeout override', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p', { timeout: 60000 });
        expect(cfg.timeout).assertEqual(60000);
      });

      it('should accept secure=true', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p', { secure: true });
        expect(cfg.secure).assertTrue();
      });

      it('should accept secure=implicit', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p', { secure: 'implicit' });
        expect(cfg.secure).assertEqual('implicit');
      });

      it('should accept protocol=SFTP without port and default to 22', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p', { protocol: ProtocolType.SFTP });
        expect(cfg.protocol).assertEqual(ProtocolType.SFTP);
        expect(cfg.port).assertEqual(22);
      });

      it('should accept protocol=SFTP with explicit port override', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p',
          { protocol: ProtocolType.SFTP, port: 2222 });
        expect(cfg.port).assertEqual(2222);
        expect(cfg.protocol).assertEqual(ProtocolType.SFTP);
      });

      it('should accept all options together', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p',
          { port: 990, timeout: 15000, secure: 'implicit', protocol: ProtocolType.FTP });
        expect(cfg.port).assertEqual(990);
        expect(cfg.timeout).assertEqual(15000);
        expect(cfg.secure).assertEqual('implicit');
        expect(cfg.protocol).assertEqual(ProtocolType.FTP);
      });
    });

    describe('isSFTP', () => {
      it('should return false for FTP protocol', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p');
        expect(cfg.isSFTP()).assertFalse();
      });

      it('should return true for SFTP protocol', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p', { protocol: ProtocolType.SFTP });
        expect(cfg.isSFTP()).assertTrue();
      });

      it('should return false when protocol set explicitly to FTP', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', 'u', 'p', { protocol: ProtocolType.FTP });
        expect(cfg.isSFTP()).assertFalse();
      });
    });

    describe('Credentials_round_trip_edge_cases', () => {
      it('should support unicode username/password', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', '用户', '密码');
        expect(cfg.getUserNameText()).assertEqual('用户');
        expect(cfg.getPasswordText()).assertEqual('密码');
      });

      it('should support empty-string username/password', 0, () => {
        const cfg: FTPStorageConfig = new FTPStorageConfig('h', '', '');
        expect(cfg.getUserNameText()).assertEqual('');
        expect(cfg.getPasswordText()).assertEqual('');
      });
    });

    describe('FTPPageConfig', () => {
      it('should expose pageUrl', 0, () => {
        expect(FTPPageConfig.pageUrl).assertEqual('storage/ftp/FTPPage');
      });

      it('should map to FTP storage type', 0, () => {
        expect(FTPPageConfig.storageType).assertEqual(StorageType.FTP);
      });

      it('should expose icon resource', 0, () => {
        expect(FTPPageConfig.icon).not().assertUndefined();
      });

      it('should expose title resource', 0, () => {
        expect(FTPPageConfig.title).not().assertUndefined();
      });

      it('should expose selectDesc resource', 0, () => {
        expect(FTPPageConfig.selectDesc).not().assertUndefined();
      });

      it('should expose saveDesc resource', 0, () => {
        expect(FTPPageConfig.saveDesc).not().assertUndefined();
      });
    });
  });
}
