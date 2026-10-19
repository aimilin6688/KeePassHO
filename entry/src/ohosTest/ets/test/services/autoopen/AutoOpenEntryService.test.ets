import { describe, expect, it } from '@ohos/hypium';
import { Kdbx, KdbxEntry, KdbxGroup, ProtectedValue } from 'kdbxweb';

import { AutoOpenEntryService } from '../../../../../main/ets/services/autoopen/AutoOpenEntryService';
import { AutoOpenFieldName } from '../../../../../main/ets/services/autoopen/AutoOpenConstants';
import { AutoOpenPathResolver } from '../../../../../main/ets/services/autoopen/AutoOpenPathResolver';
import { IfDeviceParser } from '../../../../../main/ets/services/autoopen/IfDeviceParser';
import { AutoOpenService } from '../../../../../main/ets/services/autoopen/AutoOpenService';
import { AuthType, DbFileParam } from '../../../../../main/ets/services/TypeDefined';
import { StorageType } from '../../../../../main/ets/storage';
import { WebDAVStorageConfig } from '../../../../../main/ets/storage/webdav/WebDAVConfig';
import { OneDriveStorageConfig } from '../../../../../main/ets/storage/onedrive/OneDriveConfig';
import { LocationInfo, LocationMode } from '../../../../../main/ets/services/beans/LocationParam';
import { TestUtils } from '../../importExport/TestUtils';

/** 构造子库文件参数（registry 形态；database 仅占位，条目生成不读取） */
function makeChildParam(filePath: string, fileName: string, password: string, database: Kdbx,
  keyFilePath: string = ''): DbFileParam {
  let keyLocation: LocationInfo | undefined = undefined;
  if (keyFilePath.length > 0) {
    keyLocation = {
      mode: LocationMode.SELECT,
      filePath: keyFilePath,
      fileName: 'key.key',
      storageType: StorageType.LOCAL,
      storageConfig: {}
    };
  }
  return {
    password: password,
    authType: AuthType.PASSWORD,
    filePath: filePath,
    fileName: fileName,
    database: database,
    keyLocation: keyLocation,
    storageType: StorageType.LOCAL,
    storageConfig: {},
    modifiedTime: 0
  } as DbFileParam;
}

/** 读取条目字符串字段 */
function fieldString(entry: KdbxEntry, key: string): string {
  const value = entry.fields.get(key);
  if (value === undefined || value === null) {
    return '';
  }
  if (value instanceof ProtectedValue) {
    return value.getText();
  }
  return String(value);
}

/**
 * AutoOpen 子库条目写服务单元测试（M4）
 * 语义对齐 kp2a ConfigureChildDatabasesActivity / KeeAutoExec：
 * 仅本设备启用默认、{DB_DIR} 相对化、ProtectedValue 密码、副本克隆语义
 */
export default function AutoOpenEntryServiceTest() {
  describe('AutoOpenEntryService', () => {
    const DEVICE_ID = 'HUAWEI Test (uuid-1)';

    it('addEntryForOpenedChild: creates AutoOpen group and entry with relative URL', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const childDb = await TestUtils.createTestDatabase('Child');
      const child = makeChildParam('/data/parent/child.kdbx', 'child.kdbx', 'child-pass', childDb);
      const entry = AutoOpenEntryService.addEntryForOpenedChild(parent,
        '/data/parent/parent.kdbx', child, DEVICE_ID);
      expect(entry !== undefined).assertTrue();
      expect(fieldString(entry!, 'Title')).assertEqual('child.kdbx');
      expect(fieldString(entry!, 'URL')).assertEqual('{DB_DIR}{ENV_DIRSEP}child.kdbx');
      // 密码写入为内存保护字段
      const passwordValue = entry!.fields.get('Password');
      expect(passwordValue instanceof ProtectedValue).assertTrue();
      expect(fieldString(entry!, 'Password')).assertEqual('child-pass');
      // IfDevice = 仅本设备启用
      expect(fieldString(entry!, 'IfDevice')).assertEqual(DEVICE_ID);
      expect(IfDeviceParser.isEnabled(fieldString(entry!, 'IfDevice'), DEVICE_ID).enabled).assertTrue();
      // 条目位于新建的 AutoOpen 组
      const group: KdbxGroup | undefined = AutoOpenService.findOrCreateAutoOpenGroup(parent, false);
      expect(group !== undefined).assertTrue();
      expect(group!.entries.length).assertEqual(1);
      expect(group!.entries[0] === entry).assertTrue();
    });

    it('addEntryForOpenedChild: keeps absolute URL when child is in another directory', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const childDb = await TestUtils.createTestDatabase('Child');
      const child = makeChildParam('/data/other/child.kdbx', 'child.kdbx', 'p', childDb);
      const entry = AutoOpenEntryService.addEntryForOpenedChild(parent,
        '/data/parent/parent.kdbx', child, DEVICE_ID);
      expect(fieldString(entry!, 'URL')).assertEqual('/data/other/child.kdbx');
    });

    it('addEntryForOpenedChild: writes relative key file path to UserName', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const childDb = await TestUtils.createTestDatabase('Child');
      const child = makeChildParam('/data/parent/child.kdbx', 'child.kdbx', 'p', childDb, '/data/parent/keys.key');
      const entry = AutoOpenEntryService.addEntryForOpenedChild(parent,
        '/data/parent/parent.kdbx', child, DEVICE_ID);
      expect(fieldString(entry!, 'UserName')).assertEqual('{DB_DIR}{ENV_DIRSEP}keys.key');
    });

    it('addEntryForOpenedChild: omits UserName when child has no key file', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const childDb = await TestUtils.createTestDatabase('Child');
      const child = makeChildParam('/data/parent/child.kdbx', 'child.kdbx', 'p', childDb);
      const entry = AutoOpenEntryService.addEntryForOpenedChild(parent,
        '/data/parent/parent.kdbx', child, DEVICE_ID);
      // createEntry 预置空 UserName，未写密钥路径时应保持为空
      expect(fieldString(entry!, 'UserName')).assertEqual('');
    });

    it('setEntryDeviceEnabled: disable writes exclusion and enable restores whitelist', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const childDb = await TestUtils.createTestDatabase('Child');
      const child = makeChildParam('/data/parent/child.kdbx', 'child.kdbx', 'p', childDb);
      const entry = AutoOpenEntryService.addEntryForOpenedChild(parent,
        '/data/parent/parent.kdbx', child, DEVICE_ID);
      // 停用：白名单中唯一设备转排除 → 列表仍保留该设备（显式禁用）
      AutoOpenEntryService.setEntryDeviceEnabled(entry!, DEVICE_ID, false);
      const rawDisabled: string = fieldString(entry!, 'IfDevice');
      expect(rawDisabled).assertEqual('!' + DEVICE_ID);
      expect(IfDeviceParser.isEnabled(rawDisabled, DEVICE_ID).enabled).assertFalse();
      // 重新启用
      AutoOpenEntryService.setEntryDeviceEnabled(entry!, DEVICE_ID, true);
      const rawEnabled: string = fieldString(entry!, 'IfDevice');
      expect(rawEnabled).assertEqual(DEVICE_ID);
      expect(IfDeviceParser.isEnabled(rawEnabled, DEVICE_ID).enabled).assertTrue();
    });

    it('setEntryDeviceEnabled: omits unlisted disabled device when whitelist exists', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const root = parent.getDefaultGroup();
      const entry = TestUtils.createTestEntry(parent, root, 'e', 'u', 'p', 'child.kdbx');
      // 未配置设备时启用本设备：原字段为空，setDeviceEnabled 后仅本设备 → 白名单保留
      AutoOpenEntryService.setEntryDeviceEnabled(entry, DEVICE_ID, true);
      expect(fieldString(entry, 'IfDevice')).assertEqual(DEVICE_ID);
      // 白名单存在时禁用未列出设备：KeeAutoExec 序列化省略禁用项（白名单已隐式禁用其余设备）
      AutoOpenEntryService.setEntryDeviceEnabled(entry, 'OTHER', false);
      expect(fieldString(entry, 'IfDevice')).assertEqual(DEVICE_ID);
      expect(IfDeviceParser.isEnabled(fieldString(entry, 'IfDevice'), 'OTHER').enabled).assertFalse();
    });

    it('copyEntryForDevice: original disabled on device, clone whitelisted with suffix', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const root = parent.getDefaultGroup();
      const autoOpen = TestUtils.createTestGroup(parent, root, 'AutoOpen');
      const original = TestUtils.createTestEntry(parent, autoOpen, 'child', 'u', 'p', 'child.kdbx');
      original.fields.set('Priority', '5');
      const clone = AutoOpenEntryService.copyEntryForDevice(parent, original, DEVICE_ID, 'Mate 60');
      expect(clone !== undefined).assertTrue();
      // 原条目：本设备置停用
      expect(IfDeviceParser.isEnabled(fieldString(original, 'IfDevice'), DEVICE_ID).enabled).assertFalse();
      // 副本：新 UUID、同组、Title 追加型号、仅本设备启用、其余字段复制
      expect(clone!.uuid.equals(original.uuid)).assertFalse();
      expect(clone!.parentGroup === autoOpen).assertTrue();
      expect(fieldString(clone!, 'Title')).assertEqual('child (Mate 60)');
      expect(fieldString(clone!, 'IfDevice')).assertEqual(DEVICE_ID);
      expect(IfDeviceParser.isEnabled(fieldString(clone!, 'IfDevice'), DEVICE_ID).enabled).assertTrue();
      expect(fieldString(clone!, 'URL')).assertEqual('child.kdbx');
      expect(fieldString(clone!, 'Priority')).assertEqual('5');
      expect(clone!.history.length).assertEqual(0);
    });

    it('copyEntryForDevice: returns undefined and keeps original when entry has no group', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const orphan = new KdbxEntry();
      orphan.fields.set('Title', 'orphan');
      orphan.fields.set('URL', 'child.kdbx');
      const clone = AutoOpenEntryService.copyEntryForDevice(parent, orphan, DEVICE_ID, 'Mate 60');
      expect(clone).assertUndefined();
      expect(orphan.fields.has('IfDevice')).assertFalse();
    });

    it('makeRelative round-trip: entry URL resolves back to child path', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const childDb = await TestUtils.createTestDatabase('Child');
      const child = makeChildParam('/data/parent/sub/child.kdbx', 'child.kdbx', 'p', childDb);
      const entry = AutoOpenEntryService.addEntryForOpenedChild(parent,
        '/data/parent/parent.kdbx', child, DEVICE_ID);
      const resolved = AutoOpenPathResolver.resolveUrl(fieldString(entry!, 'URL'), '/data/parent/parent.kdbx');
      expect(resolved).assertEqual('/data/parent/sub/child.kdbx');
    });

    // ==================== M6.9 远端子库写侧（经 childDb 端口） ====================

    it('addEntryForOpenedChild: WEBDAV child writes scheme URL with Ioc credentials', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const childDb = await TestUtils.createTestDatabase('Child');
      const child: DbFileParam = {
        password: 'p',
        authType: AuthType.PASSWORD,
        filePath: 'https://dav.example.com/dav/child.kdbx',
        fileName: 'child.kdbx',
        database: childDb,
        storageType: StorageType.WEBDAV,
        storageConfig: new WebDAVStorageConfig('https://dav.example.com', 'davuser', 'davpass'),
        modifiedTime: 0
      } as DbFileParam;
      const entry = AutoOpenEntryService.addEntryForOpenedChild(parent,
        '/data/parent/parent.kdbx', child, DEVICE_ID);
      expect(entry !== undefined).assertTrue();
      // URL 文法：filePath 即完整 URL，原样写入（不相对化）
      expect(fieldString(entry!, 'URL')).assertEqual('https://dav.example.com/dav/child.kdbx');
      // 凭据型适配器 extractCredentials → IocUserName / IocPassword
      expect(fieldString(entry!, AutoOpenFieldName.IOC_USER_NAME)).assertEqual('davuser');
      expect(fieldString(entry!, AutoOpenFieldName.IOC_PASSWORD)).assertEqual('davpass');
    });

    it('addEntryForOpenedChild: OneDrive child writes scheme URL without Ioc fields', 0, async () => {
      const parent = await TestUtils.createTestDatabase('Parent');
      const childDb = await TestUtils.createTestDatabase('Child');
      const child: DbFileParam = {
        password: 'p',
        authType: AuthType.PASSWORD,
        filePath: 'root/child.kdbx',
        fileName: 'child.kdbx',
        database: childDb,
        storageType: StorageType.ONEDRIVE,
        storageConfig: new OneDriveStorageConfig('token', 'refresh', 3600),
        modifiedTime: 0
      } as DbFileParam;
      const entry = AutoOpenEntryService.addEntryForOpenedChild(parent,
        '/data/parent/parent.kdbx', child, DEVICE_ID);
      expect(entry !== undefined).assertTrue();
      // PATH 文法：scheme://filePath
      expect(fieldString(entry!, 'URL')).assertEqual('onedrive://root/child.kdbx');
      // OAuth 型：不声明 extractCredentials → 不写 Ioc 字段
      expect(entry!.fields.has(AutoOpenFieldName.IOC_USER_NAME)).assertFalse();
      expect(entry!.fields.has(AutoOpenFieldName.IOC_PASSWORD)).assertFalse();
    });
  });
}
