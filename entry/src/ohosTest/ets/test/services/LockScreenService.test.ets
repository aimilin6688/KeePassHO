import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { emitter } from '@kit.BasicServicesKit';
import { window } from '@kit.ArkUI';
import { TestContextHelper } from '../TestContextHelper';
import { LockScreenService } from '../../../../main/ets/services/LockScreenService';
import { EventBus } from '../../../../main/ets/services/EventBus';
import { SettingsService } from '../../../../main/ets/services/SettingsService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

function sleep(ms: number): Promise<void> {
  return new Promise<void>(resolve => setTimeout(resolve, ms));
}

export default function LockScreenServiceTest() {
  describe('LockScreenService', () => {
    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    beforeEach(() => {
    });

    afterEach(() => {
      LockScreenService.destroy();
      EventBus.off(LockScreenService.EVENT_LOCK_SCREEN);
    });

    afterAll(() => {
      LockScreenService.destroy();
    });

    it('exposes EVENT_LOCK_ACTION and EVENT_LOCK_SCREEN name constants', 0, () => {
      expect(LockScreenService.EVENT_LOCK_ACTION).assertEqual('lock_screen_action');
      expect(LockScreenService.EVENT_LOCK_SCREEN).assertEqual('lock_screen');
    });

    it('init registers listener and stores action callback (windowStage unused in body)', 0, () => {
      let threw = false;
      try {
        LockScreenService.init({} as window.WindowStage, () => {});
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('destroy is a no-op before init', 0, () => {
      let threw = false;
      try {
        LockScreenService.destroy();
        LockScreenService.destroy();
      } catch (e) {
        threw = true;
      }
      expect(threw).assertFalse();
    });

    it('showLockWindow emits lock_screen event and sets AppStorage lockIsManual=true', 0, async () => {
      let received: boolean | null = null;
      LockScreenService.init({} as window.WindowStage, () => {});
      EventBus.on(LockScreenService.EVENT_LOCK_SCREEN, (data: emitter.EventData) => {
        const raw: Object | undefined = data?.data;
        if (typeof raw === 'boolean') {
          received = raw;
        }
      });
      await LockScreenService.showLockWindow(true);
      await sleep(50);
      expect(received).assertTrue();
      expect(AppStorage.get<boolean>('lockIsManual')).assertTrue();
    });

    it('showLockWindow(false) carries isManual=false to subscribers', 0, async () => {
      let received: boolean | null = null;
      LockScreenService.init({} as window.WindowStage, () => {});
      EventBus.on(LockScreenService.EVENT_LOCK_SCREEN, (data: emitter.EventData) => {
        const raw: Object | undefined = data?.data;
        if (typeof raw === 'boolean') {
          received = raw;
        }
      });
      await LockScreenService.showLockWindow(false);
      await sleep(50);
      expect(received).assertFalse();
      expect(AppStorage.get<boolean>('lockIsManual')).assertFalse();
    });

    it('EVENT_LOCK_ACTION unlock invokes onAction callback with "unlock"', 0, async () => {
      let action = '';
      LockScreenService.init({} as window.WindowStage, (a: string) => {
        action = a;
      });
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await sleep(50);
      expect(action).assertEqual('unlock');
    });

    it('EVENT_LOCK_ACTION close_database invokes callback and clears lockIsManual', 0, async () => {
      let action = '';
      AppStorage.setOrCreate<boolean>('lockIsManual', true);
      LockScreenService.init({} as window.WindowStage, (a: string) => {
        action = a;
      });
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'close_database');
      await sleep(50);
      expect(action).assertEqual('close_database');
      expect(AppStorage.get<boolean>('lockIsManual') === undefined ||
        AppStorage.get<boolean>('lockIsManual') === false).assertTrue();
    });

    it('EVENT_LOCK_ACTION unlock clears isLocked and lockIsManual', 0, async () => {
      let action = '';
      AppStorage.setOrCreate<boolean>('lockIsManual', true);
      AppStorage.setOrCreate<boolean>('isLocked', true);
      LockScreenService.init({} as window.WindowStage, (a: string) => {
        action = a;
      });
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await sleep(50);
      expect(action).assertEqual('unlock');
      expect(AppStorage.get<boolean>('isLocked') === false).assertTrue();
      expect(AppStorage.get<boolean>('lockIsManual') === undefined).assertTrue();
    });

    it('EVENT_LOCK_ACTION with non-string data does not invoke callback', 0, async () => {
      let action = '';
      LockScreenService.init({} as window.WindowStage, (a: string) => {
        action = a;
      });
      EventBus.emit<number>(LockScreenService.EVENT_LOCK_ACTION, 42);
      await sleep(50);
      expect(action).assertEqual('');
    });

    it('after destroy, action callback is no longer invoked', 0, async () => {
      let action = '';
      LockScreenService.init({} as window.WindowStage, (a: string) => {
        action = a;
      });
      LockScreenService.destroy();
      EventBus.emit<string>(LockScreenService.EVENT_LOCK_ACTION, 'unlock');
      await sleep(50);
      expect(action).assertEqual('');
    });
  });
}
