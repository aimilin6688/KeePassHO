import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { BusinessError } from '@kit.BasicServicesKit';
import { SupportService } from '../../../../main/ets/services/SupportService';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

export default function SupportServiceTest() {
  describe('SupportService', () => {
    const KEY_INSTALL = SettingsService.KEY_APP_INSTALL_TIME;

    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    beforeEach(() => {
    });

    afterEach(() => {
      SettingsService.getInstance().deleteSync(KEY_INSTALL);
    });

    afterAll(() => {
      SettingsService.getInstance().deleteSync(KEY_INSTALL);
    });

    it('isCanHideSupport resolves to false when no install time recorded', 0, async () => {
      SettingsService.getInstance().deleteSync(KEY_INSTALL);
      const v = await SupportService.isCanHideSupport();
      expect(v).assertFalse();
    });

    it('initAppInstallTime records a positive install time when absent', 0, async () => {
      SettingsService.getInstance().deleteSync(KEY_INSTALL);
      expect(SettingsService.getSync<number>(KEY_INSTALL, -1)).assertEqual(-1);
      SupportService.initAppInstallTime();
      await new Promise<void>(resolve => setTimeout(resolve, 50));
      const t = SettingsService.getSync<number>(KEY_INSTALL, -1);
      expect(t > 0).assertTrue();
    });

    it('initAppInstallTime is idempotent when install time already set', 0, async () => {
      SettingsService.getInstance().deleteSync(KEY_INSTALL);
      SupportService.initAppInstallTime();
      await new Promise<void>(resolve => setTimeout(resolve, 50));
      const first = SettingsService.getSync<number>(KEY_INSTALL, -1);
      await new Promise<void>(resolve => setTimeout(resolve, 20));
      SupportService.initAppInstallTime();
      await new Promise<void>(resolve => setTimeout(resolve, 50));
      const second = SettingsService.getSync<number>(KEY_INSTALL, -1);
      expect(second).assertEqual(first);
    });

    it('isCanHideSupport resolves to a boolean after install time is set', 0, async () => {
      SupportService.initAppInstallTime();
      await new Promise<void>(resolve => setTimeout(resolve, 50));
      const v = await SupportService.isCanHideSupport();
      expect(typeof v === 'boolean').assertTrue();
    });

    it('finishPurchase calls onError for an invalid JSON payload', 0, async () => {
      let called = false;
      let receivedCode: number | undefined = undefined;
      await new Promise<void>(resolve => {
        SupportService.finishPurchase('not-valid-json', () => {
          called = true;
          resolve();
        }, (err: BusinessError) => {
          receivedCode = err.code;
          resolve();
        });
      });
      // JSON.parse throws -> onError path; onSuccess should NOT fire
      expect(called).assertFalse();
      expect(receivedCode !== undefined || called === false).assertTrue();
    });

    it('finishPurchase calls onError for a JSON missing jwsPurchaseOrder', 0, async () => {
      let success = false;
      let errored = false;
      await new Promise<void>(resolve => {
        SupportService.finishPurchase('{"type":1}', () => {
          success = true;
          resolve();
        }, () => {
          errored = true;
          resolve();
        });
      });
      expect(success).assertFalse();
      expect(errored).assertTrue();
    });

    // NOTE: showSupportDialog requires a UIContext (promptAction) and autoFinish/isSupported
    // require the IAP kit with a real account; these are not exercised here.
  });
}
