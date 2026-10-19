import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { BusinessError } from '@kit.BasicServicesKit';
import { userAuth } from '@kit.UserAuthenticationKit';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import { AuthService, AuthServiceCallback } from '../../../../main/ets/services/AuthService';
import { FileService } from '../../../../main/ets/services/FileService';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { AuthType, DbFileParam } from '../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../main/ets/storage';

export default function AuthServiceTest() {
  describe('AuthService', () => {
    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
      FileService.init();
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('isFingerprintSupport returns a boolean without throwing', 0, () => {
      let result = false;
      let threw = false;
      try {
        result = AuthService.isFingerprintSupport();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(typeof result === 'boolean').assertTrue();
    });

    it('isFaceSupport returns a boolean without throwing', 0, () => {
      let result = false;
      let threw = false;
      try {
        result = AuthService.isFaceSupport();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
      expect(typeof result === 'boolean').assertTrue();
    });

    it('isFingerprintSupportAndEnabled is false when fingerprint login disabled by default', 0, () => {
      const v = AuthService.isFingerprintSupportAndEnabled();
      expect(v).assertFalse();
    });

    it('isFaceSupportAndEnabled is false when face login disabled by default', 0, () => {
      const v = AuthService.isFaceSupportAndEnabled();
      expect(v).assertFalse();
    });

    it('startFingerprintAuth does not invoke any callback when not enabled (graceful toast path)', 0, async () => {
      let success = 0;
      let fail = 0;
      let error = 0;
      const cb: AuthServiceCallback = {
        onSuccess: () => {
          success++;
        },
        onFail: () => {
          fail++;
        },
        onError: () => {
          error++;
        }
      };
      let threw = false;
      try {
        AuthService.startFingerprintAuth(cb);
      } catch (e) {
        threw = true;
      }
      await new Promise<void>(resolve => setTimeout(resolve, 50));
      expect(threw).assertFalse();
      expect(success).assertEqual(0);
      expect(fail).assertEqual(0);
      expect(error).assertEqual(0);
    });

    it('startFaceAuth does not invoke any callback when not enabled (graceful toast path)', 0, async () => {
      let success = 0;
      let fail = 0;
      let error = 0;
      const cb: AuthServiceCallback = {
        onSuccess: () => {
          success++;
        },
        onFail: () => {
          fail++;
        },
        onError: () => {
          error++;
        }
      };
      let threw = false;
      try {
        AuthService.startFaceAuth(cb);
      } catch (e) {
        threw = true;
      }
      await new Promise<void>(resolve => setTimeout(resolve, 50));
      expect(threw).assertFalse();
      expect(success).assertEqual(0);
      expect(fail).assertEqual(0);
      expect(error).assertEqual(0);
    });

    it('startPasswordAuth invokes onError with DATABASE_NOT_OPENED when no database loaded', 0, async () => {
      FileService.init();
      let errorObj: Record<string, Object> | null = null;
      let success = 0;
      const cb: AuthServiceCallback = {
        onSuccess: () => {
          success++;
        },
        onError: (err: BusinessError) => {
          const record: Record<string, Object> = {};
          record['code'] = err.code;
          errorObj = record;
        }
      };
      AuthService.startPasswordAuth(cb);
      await new Promise<void>(resolve => setTimeout(resolve, 50));
      expect(success).assertEqual(0);
      expect(errorObj !== null).assertTrue();
      expect((errorObj!['code'] as number) === 1001).assertTrue();
    });
  });

  /**
   * 空密码数据库的主密码验证路径：startPasswordAuth 对未设置主密码的数据库直接放行
   * （onSuccess 携带 UserAuthResultCode.SUCCESS，无需弹框）。非空密码路径依赖
   * DialogHelper.showTextInputDialog（UI 弹框），不在单元测试范围。
   * 本 describe 必须注册在既有 describe 之后：DATABASE_NOT_OPENED 用例依赖干净注册表。
   */
  describe('AuthServicePasswordAuth', () => {
    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
      FileService.init();
      const credentials = new KdbxCredentials(ProtectedValue.fromString('AuthService-Test-123'));
      const database = Kdbx.create(credentials, 'AuthServiceDb');
      const param: DbFileParam = {
        filePath: '/data/test/auth-service.kdbx',
        fileName: 'auth-service.kdbx',
        password: '',
        database: database,
        authType: AuthType.PASSWORD,
        storageType: StorageType.LOCAL,
        storageConfig: {},
        modifiedTime: 0
      };
      FileService.setDbFileParam(param);
    });

    afterAll(() => {
      FileService.init();
    });

    it('startPasswordAuth succeeds immediately for an empty-password database', 0, async () => {
      let successResult: number | null = null;
      let fail = 0;
      let error = 0;
      const cb: AuthServiceCallback = {
        onSuccess: (authResult: userAuth.UserAuthResult) => {
          successResult = authResult.result;
        },
        onFail: () => {
          fail++;
        },
        onError: () => {
          error++;
        }
      };
      AuthService.startPasswordAuth(cb);
      await new Promise<void>(resolve => setTimeout(resolve, 100));
      expect(fail).assertEqual(0);
      expect(error).assertEqual(0);
      expect(successResult !== null).assertTrue();
      expect(successResult).assertEqual(userAuth.UserAuthResultCode.SUCCESS);
    });
  });
}
