import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { CredentialsService } from '../../../../main/ets/services/CredentialsService';
import { AuthTypeInfo, AuthType, CredentialsParam } from '../../../../main/ets/services/TypeDefined';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { ResourceManager } from '../../../../main/ets/common/utils/ResourceManager';

function nullishAuthType(): AuthTypeInfo | null {
  return null;
}

export default function CredentialsServiceTest() {
  describe('CredentialsService', () => {
    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      ResourceManager.getInstance().init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('createKdbxCredentials builds credentials for password-only auth type', 0, async () => {
      const param: CredentialsParam = {
        password: 'secret123',
        authType: AuthType.PASSWORD
      };
      const credentials = await CredentialsService.createKdbxCredentials(param);
      expect(credentials !== null && credentials !== undefined).assertTrue();
    });

    it('createKdbxCredentials builds credentials with empty password for password-only', 0, async () => {
      const param: CredentialsParam = {
        password: '',
        authType: AuthType.PASSWORD
      };
      const credentials = await CredentialsService.createKdbxCredentials(param);
      expect(credentials !== null && credentials !== undefined).assertTrue();
    });

    it('createKdbxCredentials throws when keyfile-only auth missing keyLocation', 0, async () => {
      const param: CredentialsParam = {
        password: '',
        authType: AuthType.KEYFILE
      };
      let threw = false;
      let errMsg = '';
      try {
        await CredentialsService.createKdbxCredentials(param);
      } catch (e) {
        threw = true;
        errMsg = (e as Error).message;
      }
      expect(threw).assertTrue();
      expect(errMsg.length > 0).assertTrue();
    });

    it('createKdbxCredentials throws when password+keyfile auth missing keyLocation', 0, async () => {
      const param: CredentialsParam = {
        password: 'pw',
        authType: AuthType.PASSWORD_KEYFILE
      };
      let threw = false;
      try {
        await CredentialsService.createKdbxCredentials(param);
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('AuthType.useKeyAuth is true for PASSWORD_KEYFILE and KEYFILE', 0, () => {
      expect(AuthType.useKeyAuth(AuthType.PASSWORD_KEYFILE)).assertTrue();
      expect(AuthType.useKeyAuth(AuthType.KEYFILE)).assertTrue();
    });

    it('AuthType.useKeyAuth is false for PASSWORD', 0, () => {
      expect(AuthType.useKeyAuth(AuthType.PASSWORD)).assertFalse();
    });

    it('AuthType.isKeyfileOnly is true only for KEYFILE', 0, () => {
      expect(AuthType.isKeyfileOnly(AuthType.KEYFILE)).assertTrue();
      expect(AuthType.isKeyfileOnly(AuthType.PASSWORD)).assertFalse();
      expect(AuthType.isKeyfileOnly(AuthType.PASSWORD_KEYFILE)).assertFalse();
    });

    it('AuthType.isKeyfileOnly returns false for a nullish authType', 0, () => {
      expect(AuthType.isKeyfileOnly(nullishAuthType() as AuthTypeInfo)).assertFalse();
    });

    it('AuthType.useKeyAuth returns false for a nullish authType', 0, () => {
      expect(AuthType.useKeyAuth(nullishAuthType() as AuthTypeInfo)).assertFalse();
    });
  });
}
