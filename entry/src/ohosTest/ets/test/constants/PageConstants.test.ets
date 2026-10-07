import { describe, expect, it } from '@ohos/hypium';
import { PageConstants } from '../../../../main/ets/common/constants/PageConstants';

export default function PageConstantsTest() {
  describe('PageConstants', () => {
    it('homeLayoutConstantsHaveExpectedValues', 0, () => {
      expect(PageConstants.HOME_PAGE_MAX_WIDTH).assertEqual(700);
      expect(PageConstants.HOME_PAGE_PADDING).assertEqual(16);
    });

    it('databaseLayoutConstantsHaveExpectedValues', 0, () => {
      expect(PageConstants.DATABASE_LIST_WIDTH).assertEqual(280);
      expect(PageConstants.DATABASE_LIST_MIN_WIDTH).assertEqual(240);
      expect(PageConstants.DATABASE_LIST_MAX_WIDTH).assertEqual(400);
      expect(PageConstants.DATABASE_PAGE_PADDING).assertEqual(16);
    });

    it('databaseListWidthRangeContainsDefaultWidth', 0, () => {
      expect(PageConstants.DATABASE_LIST_MIN_WIDTH <= PageConstants.DATABASE_LIST_WIDTH).assertTrue();
      expect(PageConstants.DATABASE_LIST_WIDTH <= PageConstants.DATABASE_LIST_MAX_WIDTH).assertTrue();
    });

    it('settingsLayoutConstantsHaveExpectedValues', 0, () => {
      expect(PageConstants.SETTINGS_LIST_WIDTH).assertEqual(280);
      expect(PageConstants.SETTINGS_PAGE_PADDING).assertEqual(0);
    });

    it('entryAndCommonLayoutConstantsHaveExpectedValues', 0, () => {
      expect(PageConstants.ENTRY_PAGE_PADDING).assertEqual(16);
      expect(PageConstants.TITLE_BAR_HEIGHT).assertEqual(44);
      expect(PageConstants.TITLE_FONT_SIZE).assertEqual(18);
    });

    it('homeRelatedPageNamesHaveExpectedValues', 0, () => {
      expect(PageConstants.PAGE_INDEX).assertEqual('Index');
      expect(PageConstants.PAGE_PASSWORD).assertEqual('Password');
      expect(PageConstants.PAGE_RECENT_FILES).assertEqual('RecentFiles');
      expect(PageConstants.PAGE_SELECT_LOCATION).assertEqual('SelectLocation');
      expect(PageConstants.PAGE_CREATE_DATABASE).assertEqual('CreateDatabase');
      expect(PageConstants.PAGE_UNLOCK_DATABASE).assertEqual('UnLockDatabase');
      expect(PageConstants.PAGE_CHANGE_PASSWORD).assertEqual('ChangePassword');
      expect(PageConstants.PAGE_OAUTH2_LOGIN).assertEqual('OAuth2Login');
      expect(PageConstants.PAGE_LOCAL_FILE).assertEqual('LocalFilePage');
      expect(PageConstants.PAGE_WEBDAV).assertEqual('WebDAVPage');
      expect(PageConstants.PAGE_ONEDRIVE).assertEqual('OneDrivePage');
      expect(PageConstants.PAGE_FTP).assertEqual('FTPPage');
      expect(PageConstants.PAGE_S3).assertEqual('S3Page');
      expect(PageConstants.PAGE_PCLOUD).assertEqual('PCloudPage');
      expect(PageConstants.PAGE_HUAWEI_DRIVE).assertEqual('HuaweiDrivePage');
    });

    it('cloudFileListPageNamesHaveExpectedValues', 0, () => {
      expect(PageConstants.PAGE_WEBDAV_FILE_LIST).assertEqual('WebDAVFileListPage');
      expect(PageConstants.PAGE_ONEDRIVE_FILE_LIST).assertEqual('OneDriveFileListPage');
      expect(PageConstants.PAGE_FTP_FILE_LIST).assertEqual('FTPFileListPage');
      expect(PageConstants.PAGE_S3_FILE_LIST).assertEqual('S3FileListPage');
      expect(PageConstants.PAGE_PCLOUD_FILE_LIST).assertEqual('PCloudFileListPage');
      expect(PageConstants.PAGE_HUAWEI_DRIVE_FILE_LIST).assertEqual('HuaweiDriveFileListPage');
    });

    it('databaseRelatedPageNamesHaveExpectedValues', 0, () => {
      expect(PageConstants.PAGE_DATABASE_VIEW).assertEqual('DatabaseView');
      expect(PageConstants.PAGE_ENTRY_VIEW).assertEqual('EntryView');
      expect(PageConstants.PAGE_ENTRY_EDIT).assertEqual('EntryEdit');
      expect(PageConstants.PAGE_TOTP_VIEW).assertEqual('TotpView');
      expect(PageConstants.PAGE_TEMPLATE_ENTRY_CREATE).assertEqual('TemplateEntryCreate');
    });

    it('settingsRelatedPageNamesHaveExpectedValues', 0, () => {
      expect(PageConstants.PAGE_SETTINGS).assertEqual('Settings');
      expect(PageConstants.PAGE_SETTING_SECURITY).assertEqual('SettingSecurity');
      expect(PageConstants.PAGE_SETTING_DATABASE).assertEqual('SettingDatabase');
      expect(PageConstants.PAGE_SETTING_APPLICATION).assertEqual('SettingApplication');
      expect(PageConstants.PAGE_SETTING_DATABASE_META).assertEqual('SettingDatabaseMeta');
      expect(PageConstants.PAGE_SETTING_DATABASE_KEY_FUNCTION).assertEqual('SettingDatabaseKeyFunction');
      expect(PageConstants.PAGE_SETTING_CUSTOM_ICONS).assertEqual('SettingCustomIcons');
      expect(PageConstants.PAGE_SETTING_DATABASE_PROTECTED_FIELD).assertEqual('SettingDatabaseProtectedFiled');
      expect(PageConstants.PAGE_SETTING_DATABASE_CLEAN).assertEqual('SettingDatabaseClean');
      expect(PageConstants.PAGE_ABOUT).assertEqual('About');
      expect(PageConstants.PAGE_SUPPORT).assertEqual('Support');
    });

    it('getHomePageNamesReturnsAllTwentyOnePagesInOrder', 0, () => {
      const expected: string[] = [
        'Index', 'Password', 'RecentFiles', 'SelectLocation', 'CreateDatabase',
        'UnLockDatabase', 'ChangePassword', 'OAuth2Login', 'LocalFilePage', 'WebDAVPage',
        'OneDrivePage', 'FTPPage', 'S3Page', 'PCloudPage', 'HuaweiDrivePage',
        'WebDAVFileListPage', 'OneDriveFileListPage', 'FTPFileListPage', 'S3FileListPage',
        'PCloudFileListPage', 'HuaweiDriveFileListPage'
      ];
      const actual: string[] = PageConstants.getHomePageNames();
      expect(actual.length).assertEqual(expected.length);
      for (let i = 0; i < expected.length; i++) {
        expect(actual[i]).assertEqual(expected[i]);
      }
    });

    it('getHomePageNamesReturnsNewArrayEachCall', 0, () => {
      const first: string[] = PageConstants.getHomePageNames();
      const second: string[] = PageConstants.getHomePageNames();
      expect(first === second).assertFalse();
      expect(first.length).assertEqual(second.length);
    });

    it('getHomePageNamesHaveNoDuplicates', 0, () => {
      const names: string[] = PageConstants.getHomePageNames();
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < names.length; i++) {
        unique.add(names[i]);
      }
      expect(unique.size).assertEqual(names.length);
    });

    it('getDatabasePageNamesReturnsAllFivePagesInOrder', 0, () => {
      const expected: string[] = [
        'DatabaseView', 'EntryView', 'EntryEdit', 'TotpView', 'TemplateEntryCreate'
      ];
      const actual: string[] = PageConstants.getDatabasePageNames();
      expect(actual.length).assertEqual(expected.length);
      for (let i = 0; i < expected.length; i++) {
        expect(actual[i]).assertEqual(expected[i]);
      }
    });

    it('getDatabasePageNamesReturnsNewArrayEachCall', 0, () => {
      const first: string[] = PageConstants.getDatabasePageNames();
      const second: string[] = PageConstants.getDatabasePageNames();
      expect(first === second).assertFalse();
      expect(first.length).assertEqual(second.length);
    });

    it('getDatabasePageNamesHaveNoDuplicates', 0, () => {
      const names: string[] = PageConstants.getDatabasePageNames();
      const unique: Set<string> = new Set<string>();
      for (let i = 0; i < names.length; i++) {
        unique.add(names[i]);
      }
      expect(unique.size).assertEqual(names.length);
    });

    it('homeAndDatabasePageGroupsAreDisjoint', 0, () => {
      const homeNames: string[] = PageConstants.getHomePageNames();
      const databaseNames: string[] = PageConstants.getDatabasePageNames();
      for (let i = 0; i < homeNames.length; i++) {
        expect(databaseNames.includes(homeNames[i])).assertFalse();
      }
      for (let i = 0; i < databaseNames.length; i++) {
        expect(homeNames.includes(databaseNames[i])).assertFalse();
      }
    });
  });
}
