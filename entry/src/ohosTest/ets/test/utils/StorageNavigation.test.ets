import { describe, expect, it } from '@ohos/hypium';
import { StorageConfig, StorageType } from '../../../../main/ets/storage';
import { OAuth2LoginParam, StorageNavigation } from '../../../../main/ets/common/utils/StorageNavigation';
import { NavigationManager } from '../../../../main/ets/common/utils/NavigationManager';
import { PageConstants } from '../../../../main/ets/common/constants/PageConstants';

class FakeOAuth2Config {
  public clientId: string = 'fake-client';
}

const TEST_ROOT = 'StorageNavTestRoot';

export default function StorageNavigationTest() {
  describe('StorageNavigation', () => {
    // ---------------- 文件列表页 ----------------
    it('file list page name constant is stable', 0, () => {
      expect(PageConstants.PAGE_FILE_LIST).assertEqual('FileListPage');
    });

    it('pushFileList with unsupported types does not navigate', 0, () => {
      const mgr = NavigationManager.getInstance();
      mgr.setCurrentNavPathStack(TEST_ROOT);
      mgr.clearNavPathStack(TEST_ROOT);
      const config: StorageConfig = {};
      StorageNavigation.pushFileList(StorageType.LOCAL, '/', config);
      StorageNavigation.pushFileList(StorageType.BAIDU_NETDISK, '/', config);
      expect(mgr.getNavPathStackByRoot(TEST_ROOT)?.size() ?? 0).assertEqual(0);
      mgr.removeNavPathStack(TEST_ROOT);
    });

    // ---------------- getStorageTitle ----------------
    it('getStorageTitle returns a resource for supported types', 0, () => {
      const types: StorageType[] = [
        StorageType.WEBDAV, StorageType.ONEDRIVE, StorageType.FTP,
        StorageType.S3, StorageType.HUAWEI_DRIVE
      ];
      for (const type of types) {
        const title: ResourceStr = StorageNavigation.getStorageTitle(type);
        expect(title).not().assertNull();
        expect(title === '').assertFalse();
      }
    });

    it('getStorageTitle returns empty string for unsupported types', 0, () => {
      expect(StorageNavigation.getStorageTitle(StorageType.PCLOUD)).assertEqual('');
      expect(StorageNavigation.getStorageTitle(StorageType.BAIDU_NETDISK)).assertEqual('');
    });

    // ---------------- pushFileList ----------------
    it('pushFileList with supported type pushes exactly one page', 0, () => {
      const mgr = NavigationManager.getInstance();
      mgr.setCurrentNavPathStack(TEST_ROOT);
      mgr.clearNavPathStack(TEST_ROOT);
      const config: StorageConfig = {};
      StorageNavigation.pushFileList(StorageType.WEBDAV, '/databases', config);
      const stack = mgr.getNavPathStackByRoot(TEST_ROOT);
      expect(stack).not().assertNull();
      expect(stack!.size()).assertEqual(1);
      expect(stack!.getAllPathName()[0]).assertEqual(PageConstants.PAGE_FILE_LIST);
      StorageNavigation.pop();
      expect(stack!.size()).assertEqual(0);
      mgr.removeNavPathStack(TEST_ROOT);
    });

    // ---------------- pushOAuth2Login ----------------
    it('pushOAuth2Login pushes the OAuth2 login page with params', 0, () => {
      const mgr = NavigationManager.getInstance();
      mgr.setCurrentNavPathStack(TEST_ROOT);
      mgr.clearNavPathStack(TEST_ROOT);
      StorageNavigation.pushOAuth2Login('https://login.example.com/auth', new FakeOAuth2Config(), 'Login');
      const stack = mgr.getNavPathStackByRoot(TEST_ROOT);
      expect(stack).not().assertNull();
      expect(stack!.size()).assertEqual(1);
      StorageNavigation.pop();
      mgr.removeNavPathStack(TEST_ROOT);
    });

    // ---------------- OAuth2LoginParam shape ----------------
    it('OAuth2LoginParam carries auth url, config and title', 0, () => {
      const oauth2Config = new FakeOAuth2Config();
      const param: OAuth2LoginParam = {
        authUrl: 'https://login.example.com/auth',
        oauth2Config: oauth2Config,
        pageTitle: 'Login'
      };
      expect(param.authUrl).assertEqual('https://login.example.com/auth');
      expect(param.oauth2Config === oauth2Config).assertTrue();
      expect(param.pageTitle).assertEqual('Login');
    });

    // ---------------- pop on empty stack ----------------
    it('pop on empty stack is a no-op', 0, () => {
      const mgr = NavigationManager.getInstance();
      mgr.setCurrentNavPathStack(TEST_ROOT);
      mgr.clearNavPathStack(TEST_ROOT);
      let noThrow = true;
      try {
        StorageNavigation.pop();
      } catch {
        noThrow = false;
      }
      expect(noThrow).assertTrue();
      mgr.removeNavPathStack(TEST_ROOT);
    });

    // ---------------- page name constant ----------------
    it('OAuth2 login page name constant is stable', 0, () => {
      expect(PageConstants.PAGE_OAUTH2_LOGIN).assertEqual('OAuth2Login');
    });
  });
}
