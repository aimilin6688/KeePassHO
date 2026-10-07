import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { CopyEventService } from '../../../../main/ets/services/CopyEventService';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

export default function CopyEventServiceTest() {
  describe('CopyEventService', () => {
    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    beforeEach(() => {
    });

    afterEach(() => {
      CopyEventService.getInstance().destroy();
    });

    afterAll(() => {
      CopyEventService.getInstance().destroy();
    });

    it('getInstance returns the singleton instance', 0, () => {
      const a = CopyEventService.getInstance();
      const b = CopyEventService.getInstance();
      expect(a === b).assertTrue();
    });

    it('destroy before init is a no-op without throwing', 0, () => {
      let threw = false;
      try {
        CopyEventService.getInstance().destroy();
        CopyEventService.getInstance().destroy();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('init subscribes to copy field events without throwing', 0, async () => {
      let threw = false;
      try {
        await CopyEventService.getInstance().init();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('calling init twice is idempotent (second call returns early)', 0, async () => {
      await CopyEventService.getInstance().init();
      let threw = false;
      try {
        await CopyEventService.getInstance().init();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('destroy after init clears the subscriber (idempotent re-destroy)', 0, async () => {
      await CopyEventService.getInstance().init();
      let threw = false;
      try {
        CopyEventService.getInstance().destroy();
        CopyEventService.getInstance().destroy();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('init can be called again after destroy', 0, async () => {
      await CopyEventService.getInstance().init();
      CopyEventService.getInstance().destroy();
      let threw = false;
      try {
        await CopyEventService.getInstance().init();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });
  });
}
