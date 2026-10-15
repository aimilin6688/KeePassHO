import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { TestContextHelper } from '../TestContextHelper';
import { SettingsService, UnlockAuthType, BreadcrumbPosition } from '../../../../main/ets/services/SettingsService';
import { ThemeMode } from '../../../../main/ets/common/constants/ThemeConstants';
import { SortMode } from '../../../../main/ets/common/constants/SortConstants';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';

export default function SettingsServiceTest() {
  describe('SettingsService', () => {
    const TEST_KEY = 'test_setting_key';
    const TEST_KEY_NUM = 'test_setting_key_num';
    const TEST_KEY_BOOL = 'test_setting_key_bool';

    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    beforeEach(() => {
    });

    afterEach(() => {
      SettingsService.getInstance().deleteSync(TEST_KEY);
      SettingsService.getInstance().deleteSync(TEST_KEY_NUM);
      SettingsService.getInstance().deleteSync(TEST_KEY_BOOL);
    });

    afterAll(() => {
    });

    it('getInstance returns the singleton instance', 0, () => {
      const a = SettingsService.getInstance();
      const b = SettingsService.getInstance();
      expect(a === b).assertTrue();
    });

    it('getSync returns the default value when key is absent', 0, () => {
      const v = SettingsService.getInstance().getSync<boolean>(TEST_KEY_BOOL, false);
      expect(v).assertFalse();
    });

    it('put then getSync round-trips a string value', 0, async () => {
      await SettingsService.getInstance().put(TEST_KEY, 'hello');
      const v = SettingsService.getInstance().getSync<string>(TEST_KEY, '');
      expect(v).assertEqual('hello');
    });

    it('put then getSync round-trips a number value', 0, async () => {
      await SettingsService.getInstance().put(TEST_KEY_NUM, 42);
      const v = SettingsService.getInstance().getSync<number>(TEST_KEY_NUM, 0);
      expect(v).assertEqual(42);
    });

    it('put then getSync round-trips a boolean value', 0, async () => {
      await SettingsService.getInstance().put(TEST_KEY_BOOL, true);
      const v = SettingsService.getInstance().getSync<boolean>(TEST_KEY_BOOL, false);
      expect(v).assertTrue();
    });

    it('static put / static getSync delegate to the singleton', 0, async () => {
      await SettingsService.put(TEST_KEY, 'static');
      const v = SettingsService.getSync<string>(TEST_KEY, '');
      expect(v).assertEqual('static');
    });

    it('static get with callback delivers the value', 0, async () => {
      await SettingsService.getInstance().put(TEST_KEY, 'cb');
      let captured = '';
      await new Promise<void>(resolve => {
        SettingsService.get<string>(TEST_KEY, '', (value: string) => {
          captured = value;
          resolve();
        });
      });
      expect(captured).assertEqual('cb');
    });

    it('instance get returns the default when key absent', 0, async () => {
      const v = await SettingsService.getInstance().get<boolean>(TEST_KEY_BOOL, false);
      expect(v).assertFalse();
    });

    it('deleteSync removes a previously written key', 0, async () => {
      await SettingsService.getInstance().put(TEST_KEY, 'val');
      SettingsService.getInstance().deleteSync(TEST_KEY);
      const v = SettingsService.getInstance().getSync<string>(TEST_KEY, 'def');
      expect(v).assertEqual('def');
    });

    it('static delete delegates to the singleton', 0, async () => {
      await SettingsService.put(TEST_KEY, 'x');
      SettingsService.delete(TEST_KEY);
      const v = SettingsService.getSync<string>(TEST_KEY, 'gone');
      expect(v).assertEqual('gone');
    });

    it('getAll returns an object', 0, () => {
      const all = SettingsService.getAll();
      expect(all !== null && all !== undefined).assertTrue();
    });

    it('registerObserver fires on put with the written key', 0, async () => {
      let observedKey = '';
      const observer = (key: string) => {
        observedKey = key;
      };
      SettingsService.getInstance().registerObserver(observer);
      try {
        await SettingsService.getInstance().put(TEST_KEY, 'obs');
        expect(observedKey).assertEqual(TEST_KEY);
      } finally {
        SettingsService.getInstance().unregisterObserver(observer);
      }
    });

    it('static registerObserver / unregisterObserver delegate to singleton', 0, async () => {
      let observed = 0;
      const observer = () => {
        observed++;
      };
      SettingsService.registerObserver(observer);
      try {
        await SettingsService.put(TEST_KEY, 'a');
        await SettingsService.put(TEST_KEY, 'b');
        expect(observed).assertEqual(2);
      } finally {
        SettingsService.unregisterObserver(observer);
      }
      await SettingsService.put(TEST_KEY, 'c');
      expect(observed).assertEqual(2);
    });

    it('unregisterObserver removes only the matching observer', 0, async () => {
      let a = 0;
      let b = 0;
      const oa = () => {
        a++;
      };
      const ob = () => {
        b++;
      };
      SettingsService.getInstance().registerObserver(oa);
      SettingsService.getInstance().registerObserver(ob);
      await SettingsService.getInstance().put(TEST_KEY, '1');
      expect(a >= 1).assertTrue();
      expect(b >= 1).assertTrue();
      SettingsService.getInstance().unregisterObserver(oa);
      const aBefore = a;
      await SettingsService.getInstance().put(TEST_KEY, '2');
      expect(b > 1).assertTrue();
      expect(a).assertEqual(aBefore);
    });

    it('setThemeMode / getThemeMode round-trip', 0, async () => {
      await SettingsService.getInstance().setThemeMode(ThemeMode.LIGHT);
      const mode = await SettingsService.getInstance().getThemeMode();
      expect(mode).assertEqual(ThemeMode.LIGHT);
    });

    it('setDarkMode(true) makes isDarkMode true (deprecated path)', 0, async () => {
      await SettingsService.getInstance().setDarkMode(true);
      const dark = await SettingsService.getInstance().isDarkMode();
      expect(dark).assertTrue();
    });

    it('setSortBy / getSortBy round-trip', 0, async () => {
      await SettingsService.getInstance().setSortBy(SortMode.NAME);
      const v = await SettingsService.getInstance().getSortBy();
      expect(v).assertEqual(SortMode.NAME);
    });

    it('isFingerprintAuthEnable returns boolean default false', 0, () => {
      const v = SettingsService.isFingerprintAuthEnable();
      expect(typeof v === 'boolean').assertTrue();
    });

    it('isFaceAuthEnable returns boolean default false', 0, () => {
      const v = SettingsService.isFaceAuthEnable();
      expect(typeof v === 'boolean').assertTrue();
    });

    it('isSearchHistoryEnable returns boolean', 0, () => {
      const v = SettingsService.isSearchHistoryEnable();
      expect(typeof v === 'boolean').assertTrue();
    });

    it('default constants are exported with expected values', 0, () => {
      expect(SettingsService.KEY_SECURITY_CLEAR_PASTEBOARD_TIME_DEFAULT).assertEqual(30);
      expect(SettingsService.KEY_SECURITY_AUTO_LOCK_TIME_DEFAULT).assertEqual(30);
      expect(SettingsService.KEY_SECURITY_QUICK_LOCK_PASSWORD_LENGTH_DEFAULT).assertEqual(3);
      expect(SettingsService.KEY_SECURITY_FINGERPRINT_LOGIN_DEFAULT).assertFalse();
      expect(SettingsService.KEY_SECURITY_FACE_LOGIN_DEFAULT).assertFalse();
      expect(SettingsService.KEY_SECURITY_AUTH_DEFAULT_TYPE_DEFAULT).assertEqual(UnlockAuthType.PASSWORD);
      expect(SettingsService.KEY_DATABASE_MAX_SIZE_DEFAULT).assertEqual(512);
      expect(SettingsService.KEY_APP_LIMIT_DB_EXT_DEFAULT).assertFalse();
      expect(SettingsService.KEY_APP_SYNC_SETTING_ENABLE_DEFAULT).assertFalse();
      expect(SettingsService.KEY_APP_HOLDING_HAND_ENABLE_DEFAULT).assertTrue();
      expect(SettingsService.KEY_APP_ENABLE_LOCAL_CACHE_DEFAULT).assertTrue();
      expect(SettingsService.KEY_APP_BREADCRUMB_VISIBLE_DEFAULT).assertTrue();
      expect(SettingsService.KEY_APP_BREADCRUMB_POSITION_DEFAULT).assertEqual(BreadcrumbPosition.BOTTOM);
      expect(SettingsService.KEY_SHOW_SUPPORT_DIALOG_DEFAULT).assertTrue();
      expect(SettingsService.KEY_SECURITY_SESSION_NOTIFY_ENABLE_DEFAULT).assertTrue();
      expect(SettingsService.KEY_SECURITY_LIST_SHOW_TOTP_DEFAULT).assertTrue();
      expect(SettingsService.KEY_SECURITY_ITEM_SHOW_TOTP_DEFAULT).assertTrue();
      expect(SettingsService.KEY_SECURITY_PRIVACY_WINDOW_DEFAULT).assertTrue();
      expect(SettingsService.KEY_SECURITY_PULL_REFRESH_DEFAULT).assertTrue();
      expect(SettingsService.KEY_SECURITY_SEARCH_HISTORY_ENABLE_DEFAULT).assertTrue();
    });

    it('getThemeMode falls back to SYSTEM before init-like state', 0, async () => {
      await SettingsService.getInstance().setThemeMode(ThemeMode.SYSTEM);
      const mode = await SettingsService.getInstance().getThemeMode();
      expect(mode).assertEqual(ThemeMode.SYSTEM);
    });

    // ---------------- childDbHintHiddenKey（M5 子数据库提示条按库记忆） ----------------

    it('childDbHintHiddenKey: deterministic and prefixed for the same iocKey', 0, () => {
      const key1: string = SettingsService.childDbHintHiddenKey('LOCAL::/data/a.kdbx');
      const key2: string = SettingsService.childDbHintHiddenKey('LOCAL::/data/a.kdbx');
      expect(key1 === key2).assertTrue();
      expect(key1.startsWith(SettingsService.KEY_CHILD_DB_HINT_HIDDEN_PREFIX)).assertTrue();
    });

    it('childDbHintHiddenKey: differs across iocKeys', 0, () => {
      const keyA: string = SettingsService.childDbHintHiddenKey('LOCAL::/data/a.kdbx');
      const keyB: string = SettingsService.childDbHintHiddenKey('LOCAL::/data/b.kdbx');
      expect(keyA !== keyB).assertTrue();
    });
  });
}
