import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { ScanService, ScanResult } from '../../../../main/ets/services/ScanService';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { ResourceManager } from '../../../../main/ets/common/utils/ResourceManager';

export default function ScanServiceTest() {
  describe('ScanService', () => {
    let scanService: ScanService;

    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      ResourceManager.getInstance().init(appContext);
      await SettingsService.getInstance().init(appContext);
      // parseScanContent does not use the stored UIContext, so a stub is safe for unit testing.
      scanService = new ScanService({} as UIContext);
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    it('ScanResult.success sets success=true and content', 0, () => {
      const r = ScanResult.success('abc');
      expect(r.success).assertTrue();
      expect(r.content).assertEqual('abc');
      expect(r.error === undefined).assertTrue();
    });

    it('ScanResult.fail sets success=false and error', 0, () => {
      const r = ScanResult.fail('boom');
      expect(r.success).assertFalse();
      expect(r.error).assertEqual('boom');
      expect(r.content === undefined).assertTrue();
    });

    it('ScanResult constructor accepts all three args', 0, () => {
      const r = new ScanResult(true, 'c', undefined);
      expect(r.success).assertTrue();
      expect(r.content).assertEqual('c');
    });

    it('parseScanContent returns success for a valid TOTP URI', 0, () => {
      const uri = 'otpauth://totp/Example:alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example&algorithm=SHA1&digits=6&period=30';
      const r = scanService.parseScanContent(uri);
      expect(r.success).assertTrue();
      expect(r.content).assertEqual(uri);
    });

    it('parseScanContent returns success for a minimal TOTP URI', 0, () => {
      const uri = 'otpauth://totp/Test?secret=JBSWY3DPEHPK3PXP';
      const r = scanService.parseScanContent(uri);
      expect(r.success).assertTrue();
      expect(r.content).assertEqual(uri);
    });

    it('parseScanContent fails for non-otpauth content', 0, () => {
      const r = scanService.parseScanContent('https://example.com');
      expect(r.success).assertFalse();
      expect(r.error !== undefined && r.error.length > 0).assertTrue();
    });

    it('parseScanContent fails for empty string', 0, () => {
      const r = scanService.parseScanContent('');
      expect(r.success).assertFalse();
    });

    it('parseScanContent fails for a malformed otpauth URI (unparseable)', 0, () => {
      const r = scanService.parseScanContent('otpauth://totp/Test?secret=');
      expect(r.success).assertFalse();
      expect(r.error !== undefined && r.error.length > 0).assertTrue();
    });

    it('parseScanContent fails for hotp URI (not totp)', 0, () => {
      const r = scanService.parseScanContent('otpauth://hotp/Test?secret=JBSWY3DPEHPK3PXP&counter=1');
      expect(r.success).assertFalse();
    });
  });
}
