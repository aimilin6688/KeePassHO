import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { BusinessError } from '@kit.BasicServicesKit';
import { AuthService, AuthServiceCallback } from '../../../../main/ets/services/AuthService';
import { FileService } from '../../../../main/ets/services/FileService';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

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
}
