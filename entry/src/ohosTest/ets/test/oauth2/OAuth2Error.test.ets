import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { OAuth2Error, OAuth2ErrorCodes } from '../../../../main/ets/common/oauth2/OAuth2Error';

export default function OAuth2ErrorTest() {
  describe('OAuth2ErrorTest', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('constructor sets name, code and a formatted message with detail', 0, () => {
      const err = new OAuth2Error(OAuth2ErrorCodes.TOKEN_EXPIRED, 'token expired at 0');
      expect(err.name).assertEqual('OAuth2Error');
      expect(err.code).assertEqual('TOKEN_EXPIRED');
      expect(err.message).assertEqual('OAuth2Error TOKEN_EXPIRED: token expired at 0');
    });

    it('constructor with only code omits the message suffix', 0, () => {
      const err = new OAuth2Error(OAuth2ErrorCodes.NETWORK_ERROR);
      expect(err.code).assertEqual('NETWORK_ERROR');
      expect(err.message).assertEqual('OAuth2Error NETWORK_ERROR');
    });

    it('constructor with empty string message omits the suffix', 0, () => {
      const err = new OAuth2Error('EMPTY_MSG', '');
      expect(err.code).assertEqual('EMPTY_MSG');
      expect(err.message).assertEqual('OAuth2Error EMPTY_MSG');
    });

    it('is an instance of Error and OAuth2Error', 0, () => {
      const err = new OAuth2Error('E1', 'm');
      expect(err instanceof Error).assertTrue();
      expect(err instanceof OAuth2Error).assertTrue();
    });

    it('can be thrown and caught preserving code and message', 0, () => {
      let caught: OAuth2Error | null = null;
      try {
        throw new OAuth2Error(OAuth2ErrorCodes.STATE_MISMATCH, 'csrf suspected');
      } catch (error) {
        if (error instanceof OAuth2Error) {
          caught = error;
        }
      }
      expect(caught !== null).assertTrue();
      expect(caught!.code).assertEqual('STATE_MISMATCH');
      expect(caught!.message).assertContain('csrf suspected');
    });

    it('can be caught as a generic Error', 0, () => {
      let caughtAsError = false;
      try {
        throw new OAuth2Error('THROWN2');
      } catch (error) {
        if (error instanceof Error) {
          caughtAsError = true;
        }
      }
      expect(caughtAsError).assertTrue();
    });

    it('two errors with the same code are distinct instances', 0, () => {
      const a = new OAuth2Error('SAME');
      const b = new OAuth2Error('SAME');
      expect(a.code).assertEqual(b.code);
      expect(a === b).assertFalse();
    });

    it('exposes every documented error code', 0, () => {
      expect(OAuth2ErrorCodes.CONFIG_ERROR).assertEqual('CONFIG_ERROR');
      expect(OAuth2ErrorCodes.AUTHORIZATION_FAILED).assertEqual('AUTHORIZATION_FAILED');
      expect(OAuth2ErrorCodes.TOKEN_FETCH_FAILED).assertEqual('TOKEN_FETCH_FAILED');
      expect(OAuth2ErrorCodes.TOKEN_REFRESH_FAILED).assertEqual('TOKEN_REFRESH_FAILED');
      expect(OAuth2ErrorCodes.TOKEN_INVALID).assertEqual('TOKEN_INVALID');
      expect(OAuth2ErrorCodes.TOKEN_EXPIRED).assertEqual('TOKEN_EXPIRED');
      expect(OAuth2ErrorCodes.USER_INFO_FETCH_FAILED).assertEqual('USER_INFO_FETCH_FAILED');
      expect(OAuth2ErrorCodes.TOKEN_REVOKE_FAILED).assertEqual('TOKEN_REVOKE_FAILED');
      expect(OAuth2ErrorCodes.NETWORK_ERROR).assertEqual('NETWORK_ERROR');
      expect(OAuth2ErrorCodes.PROVIDER_NOT_SUPPORTED).assertEqual('PROVIDER_NOT_SUPPORTED');
      expect(OAuth2ErrorCodes.INVALID_PARAMETERS).assertEqual('INVALID_PARAMETERS');
      expect(OAuth2ErrorCodes.STATE_MISMATCH).assertEqual('STATE_MISMATCH');
      expect(OAuth2ErrorCodes.ACCESS_DENIED).assertEqual('ACCESS_DENIED');
    });
  });
}
