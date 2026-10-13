import { describe, expect, it } from '@ohos/hypium';
import { PageConfigManager } from '../../../../main/ets/common/utils/PageConfigManager';
import { NavigationModeType } from '../../../../main/ets/common/constants/PageConfig';
import { PageConstants } from '../../../../main/ets/common/constants/PageConstants';
import { NavigationConstants } from '../../../../main/ets/common/constants/NavigationConstants';

export default function PageConfigManagerTest() {
  describe('PageConfigManager', () => {
    // ---------------- singleton ----------------
    it('getInstance returns the same instance', 0, () => {
      expect(PageConfigManager.getInstance() === PageConfigManager.getInstance()).assertTrue();
    });

    // ---------------- home pages config ----------------
    it('home pages use EXCLUSIVE mode with max width and padding', 0, () => {
      const mgr = PageConfigManager.getInstance();
      const homePages: string[] = [
        PageConstants.PAGE_INDEX,
        PageConstants.PAGE_PASSWORD,
        PageConstants.PAGE_RECENT_FILES,
        PageConstants.PAGE_SELECT_LOCATION,
        PageConstants.PAGE_CREATE_DATABASE,
        PageConstants.PAGE_UNLOCK_DATABASE,
        PageConstants.PAGE_CHANGE_PASSWORD,
        PageConstants.PAGE_OAUTH2_LOGIN,
        // 存储相关页面由 FileStorageFactory 注册的存储 PageConfig 提供
        // （pCloud 当前在工厂中被禁用，华为云盘已注册）
        'LocalFilePage',
        'WebDAVPage',
        'OneDrivePage',
        'FTPPage',
        'S3Page',
        'HuaweiDrivePage'
      ];
      for (const name of homePages) {
        const config = mgr.getPageConfig(name);
        expect(config).not().assertNull();
        expect(config!.name).assertEqual(name);
        expect(config!.navigationMode).assertEqual(NavigationModeType.EXCLUSIVE);
        expect(config!.constrainMaxWidth).assertTrue();
        expect(config!.maxWidth).assertEqual(PageConstants.HOME_PAGE_MAX_WIDTH);
        expect(config!.padding).assertEqual(PageConstants.HOME_PAGE_PADDING);
      }
    });

    // ---------------- database pages config ----------------
    it('database pages use SPLIT mode without width constraint', 0, () => {
      const mgr = PageConfigManager.getInstance();
      const databasePages: string[] = [
        PageConstants.PAGE_DATABASE_VIEW,
        PageConstants.PAGE_ENTRY_VIEW,
        PageConstants.PAGE_ENTRY_EDIT,
        PageConstants.PAGE_TOTP_VIEW,
        PageConstants.PAGE_TEMPLATE_ENTRY_CREATE
      ];
      for (const name of databasePages) {
        const config = mgr.getPageConfig(name);
        expect(config).not().assertNull();
        expect(config!.name).assertEqual(name);
        expect(config!.navigationMode).assertEqual(NavigationModeType.SPLIT);
        expect(config!.constrainMaxWidth).assertFalse();
        // DatabaseView intentionally uses zero padding; the other database
        // pages use ENTRY_PAGE_PADDING (16).
        const expectedPadding = name === PageConstants.PAGE_DATABASE_VIEW ? 0 : PageConstants.ENTRY_PAGE_PADDING;
        expect(config!.padding).assertEqual(expectedPadding);
      }
    });

    it('DatabaseView uses zero padding', 0, () => {
      const config = PageConfigManager.getInstance().getPageConfig(PageConstants.PAGE_DATABASE_VIEW);
      expect(config).not().assertNull();
      expect(config!.padding).assertEqual(0);
    });

    // ---------------- settings page config ----------------
    it('Settings page uses SPLIT mode with zero padding', 0, () => {
      const config = PageConfigManager.getInstance().getPageConfig(PageConstants.PAGE_SETTINGS);
      expect(config).not().assertNull();
      expect(config!.name).assertEqual(PageConstants.PAGE_SETTINGS);
      expect(config!.navigationMode).assertEqual(NavigationModeType.SPLIT);
      expect(config!.constrainMaxWidth).assertFalse();
      expect(config!.padding).assertEqual(PageConstants.SETTINGS_PAGE_PADDING);
    });

    // ---------------- unknown page ----------------
    it('getPageConfig returns undefined for unknown page', 0, () => {
      expect(PageConfigManager.getInstance().getPageConfig('PCMUnknownPage')).assertUndefined();
    });

    // ---------------- navigation stack config cache ----------------
    it('setNavigationStackConfig stores and returns the root config', 0, () => {
      const mgr = PageConfigManager.getInstance();
      const rootConfig = mgr.getPageConfig(PageConstants.PAGE_INDEX)!;
      expect(mgr.getNavigationStackConfig('PCMCacheRoot')).assertUndefined();
      mgr.setNavigationStackConfig('PCMCacheRoot', rootConfig);
      expect(mgr.getNavigationStackConfig('PCMCacheRoot') === rootConfig).assertTrue();
    });

    // ---------------- getEffectivePageConfig ----------------
    it('getEffectivePageConfig returns default config for unknown page and root', 0, () => {
      const config = PageConfigManager.getInstance().getEffectivePageConfig('PCMUnknown', 'PCMUnknownRoot');
      expect(config.name).assertEqual('PCMUnknown');
      expect(config.navigationMode).assertEqual(NavigationModeType.EXCLUSIVE);
      expect(config.constrainMaxWidth).assertTrue();
      expect(config.maxWidth).assertEqual(PageConstants.HOME_PAGE_MAX_WIDTH);
      expect(config.padding).assertEqual(PageConstants.HOME_PAGE_PADDING);
    });

    it('getEffectivePageConfig returns own config when no root config cached', 0, () => {
      const mgr = PageConfigManager.getInstance();
      const config = mgr.getEffectivePageConfig(PageConstants.PAGE_ENTRY_VIEW, 'PCMNoRootConfig');
      expect(config.name).assertEqual(PageConstants.PAGE_ENTRY_VIEW);
      expect(config.navigationMode).assertEqual(NavigationModeType.SPLIT);
      expect(config.constrainMaxWidth).assertFalse();
    });

    it('getEffectivePageConfig merges page config over root config', 0, () => {
      const mgr = PageConfigManager.getInstance();
      const rootConfig = mgr.getPageConfig(PageConstants.PAGE_INDEX)!;
      mgr.setNavigationStackConfig(PageConstants.PAGE_INDEX, rootConfig);
      const config = mgr.getEffectivePageConfig(PageConstants.PAGE_ENTRY_VIEW, PageConstants.PAGE_INDEX);
      expect(config.name).assertEqual(PageConstants.PAGE_ENTRY_VIEW);
      // page's own navigation mode wins over root's
      expect(config.navigationMode).assertEqual(NavigationModeType.SPLIT);
      expect(config.constrainMaxWidth).assertFalse();
      // missing fields are inherited from the root config
      expect(config.maxWidth).assertEqual(PageConstants.HOME_PAGE_MAX_WIDTH);
      expect(config.padding).assertEqual(PageConstants.ENTRY_PAGE_PADDING);
    });

    // ---------------- isRootPage ----------------
    it('isRootPage matches NavigationConstants ROOT_PAGES', 0, () => {
      const mgr = PageConfigManager.getInstance();
      for (const root of NavigationConstants.ROOT_PAGES) {
        expect(mgr.isRootPage(root)).assertTrue();
      }
      expect(mgr.isRootPage(PageConstants.PAGE_ENTRY_VIEW)).assertFalse();
      expect(mgr.isRootPage(PageConstants.PAGE_SETTINGS)).assertTrue();
      expect(mgr.isRootPage('')).assertFalse();
    });
  });
}
