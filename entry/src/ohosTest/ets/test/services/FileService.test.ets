import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { FileService } from '../../../../main/ets/services/FileService';
import { DbFileParam } from '../../../../main/ets/services/TypeDefined';
import { LocationInfo, LocationMode } from '../../../../main/ets/services/beans/LocationParam';
import { StorageType } from '../../../../main/ets/storage';

export default function FileServiceTest() {
  describe('FileService', () => {
    let kdbx: Kdbx;

    beforeAll(() => {
      const credentials = new KdbxCredentials(ProtectedValue.fromString('test-password'));
      kdbx = Kdbx.create(credentials, 'test-db');
    });

    beforeEach(() => {
      FileService.init();
    });

    afterEach(() => {
      FileService.init();
    });

    afterAll(() => {
      FileService.init();
    });

    it('getInstance returns the singleton instance', 0, () => {
      const a = FileService.getInstance();
      const b = FileService.getInstance();
      expect(a === b).assertTrue();
    });

    it('init resets dbFileParam so isDatabaseValid is false', 0, () => {
      FileService.init();
      expect(FileService.isDatabaseValid()).assertFalse();
    });

    it('initDbFileParam resets the in-memory dbFileParam', 0, () => {
      FileService.getInstance().initDbFileParam();
      const param = FileService.getInstance().getDbFileParam();
      expect(param.database === undefined).assertTrue();
    });

    it('static close delegates to init (reset)', 0, () => {
      FileService.close();
      expect(FileService.isDatabaseValid()).assertFalse();
    });

    it('setDbFileParam / getDbFileParam round-trip', 0, () => {
      const param: DbFileParam = {
        password: 'p',
        authType: { type: 'password', value: $r('app.string.auth_type_password') },
        filePath: '/x/y.kdbx',
        fileName: 'y.kdbx',
        database: kdbx,
        storageType: 'LOCAL',
        storageConfig: {},
        modifiedTime: 0
      } as DbFileParam;
      FileService.getInstance().setDbFileParam(param);
      const got = FileService.getInstance().getDbFileParam();
      expect(got.filePath).assertEqual('/x/y.kdbx');
      expect(got.fileName).assertEqual('y.kdbx');
      expect(got.password).assertEqual('p');
    });

    it('static setDbFileParam / getDbFileParam delegate to singleton', 0, () => {
      const param: DbFileParam = {
        password: 'p2',
        authType: { type: 'password', value: $r('app.string.auth_type_password') },
        filePath: '/a/b.kdbx',
        fileName: 'b.kdbx',
        database: kdbx,
        storageType: 'LOCAL',
        storageConfig: {},
        modifiedTime: 1
      } as DbFileParam;
      FileService.setDbFileParam(param);
      expect(FileService.getDbFileParam().filePath).assertEqual('/a/b.kdbx');
    });

    it('getFilePath returns undefined after init (no filePath set)', 0, () => {
      FileService.init();
      expect(FileService.getFilePath() === undefined).assertTrue();
    });

    it('getDatabase returns undefined after init', 0, () => {
      FileService.init();
      expect(FileService.getDatabase() === undefined).assertTrue();
    });

    it('resetDbFileParam sets database, modifiedTime, version, contentHash', 0, () => {
      FileService.init();
      const param = FileService.resetDbFileParam(kdbx, 123456, 'v1', 'hash123');
      expect(param.database).assertEqual(kdbx);
      expect(param.modifiedTime).assertEqual(123456);
      expect(param.version).assertEqual('v1');
      expect(param.contentHash).assertEqual('hash123');
      expect(FileService.isDatabaseValid()).assertTrue();
      expect(FileService.getDatabase()).assertEqual(kdbx);
    });

    it('resetDbFileParam defaults version and contentHash to null when omitted', 0, () => {
      FileService.init();
      const param = FileService.resetDbFileParam(kdbx, 1);
      expect(param.version).assertNull();
      expect(param.contentHash).assertNull();
    });

    it('resetDbFileParam treats explicit null version/contentHash as null', 0, () => {
      FileService.init();
      const param = FileService.resetDbFileParam(kdbx, 1, null, null);
      expect(param.version).assertNull();
      expect(param.contentHash).assertNull();
    });

    it('isDatabaseValid is true only when database is set', 0, () => {
      FileService.init();
      expect(FileService.isDatabaseValid()).assertFalse();
      FileService.resetDbFileParam(kdbx, 0);
      expect(FileService.isDatabaseValid()).assertTrue();
      FileService.init();
      expect(FileService.isDatabaseValid()).assertFalse();
    });

    // ==================== clearPendingCredentialChanges（F1 改密字段残留回归） ====================

    it('clearPendingCredentialChanges clears transient credential fields only', 0, () => {
      FileService.init();
      const param = FileService.resetDbFileParam(kdbx, 42, 'v-clear', 'h-clear');
      // 模拟改密页发起保存前写入共享 param 的三个待应用字段
      param.password = 'OldPass';
      param.filePath = '/keep/session.kdbx';
      param.fileName = 'session.kdbx';
      param.newPassword = 'NewPass!23';
      const newKeyLocation: LocationInfo = {
        mode: LocationMode.SELECT,
        filePath: '/keep/e2e-test.keyx',
        fileName: 'e2e-test.keyx',
        storageType: StorageType.LOCAL,
        storageConfig: {}
      } as LocationInfo;
      param.newKeyLocation = newKeyLocation;
      param.notUseKeyFile = true;

      FileService.clearPendingCredentialChanges();

      // 待应用凭证字段被清理
      expect(param.newPassword).assertUndefined();
      expect(param.newKeyLocation).assertUndefined();
      expect(param.notUseKeyFile).assertFalse();
      // 会话字段不受影响：清理不得中断当前会话
      expect(param.database).assertEqual(kdbx);
      expect(param.password).assertEqual('OldPass');
      expect(param.filePath).assertEqual('/keep/session.kdbx');
      expect(param.fileName).assertEqual('session.kdbx');
      expect(param.modifiedTime).assertEqual(42);
      expect(param.version).assertEqual('v-clear');
      expect(param.contentHash).assertEqual('h-clear');
    });

    it('static clearPendingCredentialChanges delegates to singleton', 0, () => {
      FileService.init();
      const param = FileService.getDbFileParam();
      param.newPassword = 'NewPass!23';
      param.notUseKeyFile = true;
      FileService.clearPendingCredentialChanges();
      expect(param.newPassword).assertUndefined();
      expect(param.notUseKeyFile).assertFalse();
    });

    it('hasPendingCredentialChanges reflects pending state including keyfile-only', 0, () => {
      FileService.init();
      const param = FileService.getDbFileParam();
      // 空参数：无待应用改密
      expect(FileService.hasPendingCredentialChanges()).assertFalse();
      // 仅密钥文件模式：newPassword=''（移除密码意图）同样是待应用变更
      param.newPassword = '';
      expect(FileService.hasPendingCredentialChanges()).assertTrue();
      FileService.clearPendingCredentialChanges();
      expect(FileService.hasPendingCredentialChanges()).assertFalse();
      // newKeyLocation 待应用
      param.newKeyLocation = {
        mode: LocationMode.SELECT,
        filePath: '/keep/e2e-test.keyx',
        fileName: 'e2e-test.keyx',
        storageType: StorageType.LOCAL,
        storageConfig: {}
      } as LocationInfo;
      expect(FileService.hasPendingCredentialChanges()).assertTrue();
      FileService.clearPendingCredentialChanges();
      expect(FileService.hasPendingCredentialChanges()).assertFalse();
      // notUseKeyFile=true 待应用
      param.notUseKeyFile = true;
      expect(FileService.hasPendingCredentialChanges()).assertTrue();
      FileService.clearPendingCredentialChanges();
      expect(FileService.hasPendingCredentialChanges()).assertFalse();
    });
  });
}
