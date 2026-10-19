import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { Consts, Kdbx, KdbxEntry, KdbxError, KdbxGroup, ProtectedValue } from 'kdbxweb';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { ResourceManager } from '../../../../main/ets/common/utils/ResourceManager';
import { SortMode } from '../../../../main/ets/common/constants/SortConstants';
import { TestUtils } from '../importExport/TestUtils';

/**
 * KdbxUtils 纯逻辑单元测试（离线）：
 * 覆盖字段取值/保护字段判定、条目定位、分组树判断与搜索、
 * 置顶/收藏标签、排序与索引器、TOTP URL、错误消息映射与分组路径。
 */
export default function KdbxUtilsTest() {
  describe('KdbxUtilsCore', () => {
    beforeAll(() => {
      const appContext: common.Context = abilityDelegatorRegistry.getAbilityDelegator()
        .getAppContext().getApplicationContext();
      ResourceManager.getInstance().init(appContext as common.UIAbilityContext);
    });

    it('init clears custom icon map without error', 0, () => {
      KdbxUtils.init();
      expect(true).assertTrue();
    });

    it('field accessors handle plain, protected and missing values', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const entry: KdbxEntry = TestUtils.createTestEntry(db, root, 'Title', 'user', 'secret');
      expect(KdbxUtils.getFieldValueString(entry.fields, 'Title')).assertEqual('Title');
      expect(KdbxUtils.getFieldValueString(entry.fields, 'UserName')).assertEqual('user');
      expect(KdbxUtils.getFieldValueString(entry.fields, 'Password')).assertEqual('secret');
      expect(KdbxUtils.getFieldValueString(entry.fields, 'Missing')).assertEqual('');
      expect(KdbxUtils.isProtectedValue(entry.fields.get('Password'))).assertTrue();
      expect(KdbxUtils.isProtectedValue(entry.fields.get('Title'))).assertFalse();
      expect(KdbxUtils.isProtectedValue(undefined)).assertFalse();
      expect(KdbxUtils.getValueString(undefined)).assertEqual('');
      const protectedValue = ProtectedValue.fromString('p');
      expect(KdbxUtils.getValueString(protectedValue)).assertEqual('p');
    });

    it('getEntry locates entry by group/entry ids and null for misses', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const entry: KdbxEntry = TestUtils.createTestEntry(db, root, 'E1', 'u', 'p');
      const found = KdbxUtils.getEntry(db, root.uuid.id, entry.uuid.id);
      expect(found === entry).assertTrue();
      expect(KdbxUtils.getEntry(db, 'no-such-group', entry.uuid.id)).assertNull();
      expect(KdbxUtils.getEntry(db, root.uuid.id, 'no-such-entry')).assertNull();
      // 历史分支：无历史时取 history[0] 得 undefined
      const withHistoryIndex = KdbxUtils.getEntry(db, root.uuid.id, entry.uuid.id, 0);
      expect(withHistoryIndex).assertUndefined();
    });

    it('isChildGroup detects descendants at any depth', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const g1: KdbxGroup = TestUtils.createTestGroup(db, root, 'L1');
      const g2: KdbxGroup = TestUtils.createTestGroup(db, g1, 'L2');
      expect(KdbxUtils.isChildGroup(root, g1)).assertTrue();
      expect(KdbxUtils.isChildGroup(root, g2)).assertTrue();
      expect(KdbxUtils.isChildGroup(g1, g2)).assertTrue();
      expect(KdbxUtils.isChildGroup(g1, root)).assertFalse();
      expect(KdbxUtils.isChildGroup(g2, g1)).assertFalse();
      expect(KdbxUtils.isChildGroup(root, root)).assertFalse();
    });

    it('searchInGroup matches groups and entries recursively, case-insensitive', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const banking: KdbxGroup = TestUtils.createTestGroup(db, root, 'Banking');
      TestUtils.createTestEntry(db, root, 'GitHub login', 'octocat');
      const bankEntry: KdbxEntry = TestUtils.createTestEntry(db, banking, 'Bank Account', 'teller');
      const result = KdbxUtils.searchInGroup(root, 'bank', db);
      const groupHit = result.filteredGroups.some(g => g.uuid.id === banking.uuid.id);
      expect(groupHit).assertTrue();
      const entryHit = result.filteredEntries.some(e => e.uuid.id === bankEntry.uuid.id);
      expect(entryHit).assertTrue();
      const githubResult = KdbxUtils.searchInGroup(root, 'GITHUB', db);
      expect(githubResult.filteredEntries.length).assertEqual(1);
      expect(githubResult.filteredGroups.length).assertEqual(0);
      const miss = KdbxUtils.searchInGroup(root, 'zzz-not-there', db);
      expect(miss.filteredGroups.length).assertEqual(0);
      expect(miss.filteredEntries.length).assertEqual(0);
    });

    it('searchInEntries matches title/username/notes and rejects empty query', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const e1: KdbxEntry = TestUtils.createTestEntry(db, root, 'Alpha Site', 'alice');
      const e2: KdbxEntry = TestUtils.createTestEntry(db, root, 'Beta Site', 'bob', undefined, undefined, 'secret note');
      const entries: Array<KdbxEntry> = [e1, e2];
      expect(KdbxUtils.searchInEntries(entries, 'alice').length).assertEqual(1);
      expect(KdbxUtils.searchInEntries(entries, 'SECRET').length).assertEqual(1);
      expect(KdbxUtils.searchInEntries(entries, 'site').length).assertEqual(2);
      expect(KdbxUtils.searchInEntries(entries, '').length).assertEqual(0);
      expect(KdbxUtils.searchInEntries([], 'alpha').length).assertEqual(0);
    });

    it('toImgBase64Url produces png data URL', 0, () => {
      const empty = KdbxUtils.toImgBase64Url(new ArrayBuffer(0));
      expect(empty).assertEqual('data:image/png;base64,');
      const buffer = new ArrayBuffer(3);
      const url = KdbxUtils.toImgBase64Url(buffer);
      expect(url !== null).assertTrue();
      expect(url!.startsWith('data:image/png;base64,')).assertTrue();
      expect(url!.length).assertLarger('data:image/png;base64,'.length);
    });

    it('isPinned/togglePinned round-trip on entry and group', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const entry: KdbxEntry = TestUtils.createTestEntry(db, root, 'E');
      const group: KdbxGroup = TestUtils.createTestGroup(db, root, 'G');
      expect(KdbxUtils.isPinned(entry)).assertFalse();
      expect(KdbxUtils.togglePinned(entry)).assertTrue();
      expect(KdbxUtils.isPinned(entry)).assertTrue();
      expect(KdbxUtils.togglePinned(entry)).assertFalse();
      expect(KdbxUtils.isPinned(entry)).assertFalse();
      expect(KdbxUtils.togglePinned(group)).assertTrue();
      expect(KdbxUtils.isPinned(group)).assertTrue();
      expect(KdbxUtils.togglePinned(group)).assertFalse();
    });

    it('isFavorite/toggleFavorite round-trip and getFavoriteItems collects tree', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const sub: KdbxGroup = TestUtils.createTestGroup(db, root, 'Sub');
      const favoriteEntry: KdbxEntry = TestUtils.createTestEntry(db, sub, 'Fav');
      const favoriteGroup: KdbxGroup = TestUtils.createTestGroup(db, root, 'FavGroup');
      TestUtils.createTestEntry(db, root, 'Plain');
      expect(KdbxUtils.isFavorite(favoriteEntry)).assertFalse();
      expect(KdbxUtils.toggleFavorite(favoriteEntry)).assertTrue();
      expect(KdbxUtils.toggleFavorite(favoriteGroup)).assertTrue();
      const favorites = KdbxUtils.getFavoriteItems(db);
      expect(favorites.length).assertEqual(2);
      const entryHit = favorites.some(item => item.uuid.id === favoriteEntry.uuid.id);
      const groupHit = favorites.some(item => item.uuid.id === favoriteGroup.uuid.id);
      expect(entryHit).assertTrue();
      expect(groupHit).assertTrue();
      expect(KdbxUtils.toggleFavorite(favoriteEntry)).assertFalse();
      expect(KdbxUtils.getFavoriteItems(db).length).assertEqual(1);
    });

    it('compare handles undefined dates and millisecond difference', 0, () => {
      const d1 = new Date(1000);
      const d2 = new Date(2000);
      expect(KdbxUtils.compare(undefined, undefined)).assertEqual(0);
      expect(KdbxUtils.compare(undefined, d1)).assertEqual(-1);
      expect(KdbxUtils.compare(d1, undefined)).assertEqual(1);
      expect(KdbxUtils.compare(d1, d2)).assertEqual(-1000);
      expect(KdbxUtils.compare(d2, d1)).assertEqual(1000);
      expect(KdbxUtils.compare(d1, d1)).assertEqual(0);
    });

    it('comparePinnedAndTime orders pinned first, newest pinned before older', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const pinnedNew: KdbxEntry = TestUtils.createTestEntry(db, root, 'PinnedNew');
      const pinnedOld: KdbxEntry = TestUtils.createTestEntry(db, root, 'PinnedOld');
      const plain: KdbxEntry = TestUtils.createTestEntry(db, root, 'Plain');
      pinnedNew.times.lastModTime = new Date(2000);
      pinnedOld.times.lastModTime = new Date(1000);
      KdbxUtils.togglePinned(pinnedNew);
      KdbxUtils.togglePinned(pinnedOld);
      expect(KdbxUtils.comparePinnedAndTime(pinnedNew, plain)).assertEqual(-1);
      expect(KdbxUtils.comparePinnedAndTime(plain, pinnedNew)).assertEqual(1);
      expect(KdbxUtils.comparePinnedAndTime(pinnedNew, pinnedOld)).assertLess(0);
      expect(KdbxUtils.comparePinnedAndTime(pinnedOld, pinnedNew)).assertLarger(0);
      expect(KdbxUtils.comparePinnedAndTime(plain, plain)).assertEqual(0);
    });

    it('sortBy NAME puts pinned first then alphabetical', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const alpha: KdbxEntry = TestUtils.createTestEntry(db, root, 'Alpha');
      const beta: KdbxEntry = TestUtils.createTestEntry(db, root, 'Beta');
      KdbxUtils.togglePinned(beta);
      const items: Array<KdbxGroup | KdbxEntry> = [alpha, beta];
      KdbxUtils.sortBy(items, SortMode.NAME);
      expect(items[0] === beta).assertTrue();
      expect(items[1] === alpha).assertTrue();
    });

    it('sortBy MODIFIED and CREATED order newest first with pinned priority', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const older: KdbxEntry = TestUtils.createTestEntry(db, root, 'Older');
      const newer: KdbxEntry = TestUtils.createTestEntry(db, root, 'Newer');
      const pinned: KdbxEntry = TestUtils.createTestEntry(db, root, 'Pinned');
      older.times.lastModTime = new Date(1000);
      newer.times.lastModTime = new Date(2000);
      older.times.creationTime = new Date(1000);
      newer.times.creationTime = new Date(2000);
      KdbxUtils.togglePinned(pinned);
      const byModified: Array<KdbxGroup | KdbxEntry> = [older, newer, pinned];
      KdbxUtils.sortBy(byModified, SortMode.MODIFIED);
      expect(byModified[0] === pinned).assertTrue();
      expect(byModified[1] === newer).assertTrue();
      expect(byModified[2] === older).assertTrue();
      const byCreated: Array<KdbxGroup | KdbxEntry> = [older, newer, pinned];
      KdbxUtils.sortBy(byCreated, SortMode.CREATED);
      expect(byCreated[0] === pinned).assertTrue();
      expect(byCreated[1] === newer).assertTrue();
      expect(byCreated[2] === older).assertTrue();
      const byDefault: Array<KdbxGroup | KdbxEntry> = [older, newer, pinned];
      KdbxUtils.sortBy(byDefault, SortMode.DEFAULT);
      expect(byDefault[0] === pinned).assertTrue();
    });

    it('isTotpUrl validates otpauth totp scheme only', 0, () => {
      expect(KdbxUtils.isTotpUrl('otpauth://totp/Secret?issuer=X')).assertTrue();
      expect(KdbxUtils.isTotpUrl('otpauth://hotp/Secret')).assertFalse();
      expect(KdbxUtils.isTotpUrl('https://example.com')).assertFalse();
      expect(KdbxUtils.isTotpUrl('')).assertFalse();
      expect(KdbxUtils.isTotpUrl(undefined)).assertFalse();
    });

    it('getTotpUrl extracts otpauth URLs from entry TOTP field', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const withTotp: KdbxEntry = TestUtils.createTestEntry(db, root, 'WithTotp');
      withTotp.fields.set('TOTP', 'otpauth://totp/Secret?issuer=X');
      const urls = KdbxUtils.getTotpUrl(withTotp);
      expect(urls.length).assertLargerOrEqual(1);
      expect(urls[0].startsWith('otpauth://')).assertTrue();
      const withoutTotp: KdbxEntry = TestUtils.createTestEntry(db, root, 'NoTotp');
      expect(KdbxUtils.getTotpUrl(withoutTotp).length).assertEqual(0);
      const withProcessed = KdbxUtils.getTotpUrlWithProcessedFields(withTotp);
      expect(withProcessed.urls.length).assertLargerOrEqual(1);
    });

    it('getGroupPath builds full path with root exclusion and custom separator', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase('RootDb');
      const root: KdbxGroup = db.getDefaultGroup();
      const banking: KdbxGroup = TestUtils.createTestGroup(db, root, 'Banking');
      const cards: KdbxGroup = TestUtils.createTestGroup(db, banking, 'Cards');
      expect(KdbxUtils.getGroupPath(cards)).assertEqual('RootDb/Banking/Cards');
      expect(KdbxUtils.getGroupPath(cards, '/', false)).assertEqual('Banking/Cards');
      expect(KdbxUtils.getGroupPath(cards, ' > ')).assertEqual('RootDb > Banking > Cards');
      expect(KdbxUtils.getGroupPath(root)).assertEqual('RootDb');
      expect(KdbxUtils.getGroupPath(undefined)).assertEqual('');
    });

    it('buildIndexerData indexes letters skipping pinned, # first', 0, async () => {
      const db: Kdbx = await TestUtils.createTestDatabase();
      const root: KdbxGroup = db.getDefaultGroup();
      const pinned: KdbxEntry = TestUtils.createTestEntry(db, root, 'PinnedFirst');
      const numeric: KdbxEntry = TestUtils.createTestEntry(db, root, '42digit');
      const alpha: KdbxEntry = TestUtils.createTestEntry(db, root, 'Alpha');
      const beta: KdbxEntry = TestUtils.createTestEntry(db, root, 'Beta');
      const gamma: KdbxGroup = TestUtils.createTestGroup(db, root, 'Gamma');
      KdbxUtils.togglePinned(pinned);
      const items: Array<KdbxGroup | KdbxEntry> = [pinned, numeric, alpha, beta, gamma];
      const indexer = KdbxUtils.buildIndexerData(items);
      expect(indexer.indexerValues.length).assertEqual(4);
      expect(indexer.indexerValues[0]).assertEqual('#');
      expect(indexer.indexerValues[1]).assertEqual('A');
      expect(indexer.indexerValues[2]).assertEqual('B');
      expect(indexer.indexerValues[3]).assertEqual('G');
      expect(indexer.indexerMap.get('#')).assertEqual(1);
      expect(indexer.indexerMap.get('A')).assertEqual(2);
      expect(indexer.indexerMap.get('B')).assertEqual(3);
      expect(indexer.indexerMap.get('G')).assertEqual(4);
      const empty = KdbxUtils.buildIndexerData([]);
      expect(empty.indexerValues.length).assertEqual(0);
      expect(empty.indexerMap.size).assertEqual(0);
    });

    it('kdbxErrorMessage returns raw text for plain errors', 0, () => {
      expect(KdbxUtils.kdbxErrorMessage(new Error('boom'))).assertEqual('boom');
    });

    it('kdbxErrorMessage localizes KdbxError code and appends detail', 0, () => {
      let message = '';
      try {
        throw new KdbxError(Consts.ErrorCodes.InvalidKey, 'wrong password');
      } catch (e) {
        message = KdbxUtils.kdbxErrorMessage(e);
      }
      expect(message.endsWith(': wrong password')).assertTrue();
      expect(message.length).assertLarger(': wrong password'.length);
    });

    it('kdbxErrorDetail extracts detail only for KdbxError carrying one', 0, () => {
      let detail: string | undefined = 'unset';
      try {
        throw new KdbxError(Consts.ErrorCodes.InvalidKey, 'det');
      } catch (e) {
        detail = KdbxUtils.kdbxErrorDetail(e);
      }
      expect(detail).assertEqual('det');
      let noDetail: string | undefined = 'unset';
      try {
        throw new KdbxError(Consts.ErrorCodes.InvalidKey);
      } catch (e) {
        noDetail = KdbxUtils.kdbxErrorDetail(e);
      }
      expect(noDetail).assertUndefined();
      expect(KdbxUtils.kdbxErrorDetail(new Error('Error 1: x'))).assertUndefined();
    });

    it('kdbxErrorPayload maps plain, network and KdbxError kinds', 0, () => {
      // 普通错误：原文透传
      expect(KdbxUtils.kdbxErrorPayload(new Error('boom'))).assertEqual('boom');
      // 网络错误：资源 ID（数字）
      const networkPayload = KdbxUtils.kdbxErrorPayload(new Error('Connection refused'));
      expect(typeof networkPayload === 'number').assertTrue();
      // KdbxError 已知错误码：资源 ID（数字）
      let keyPayload: string | number = '';
      try {
        throw new KdbxError(Consts.ErrorCodes.InvalidKey, 'x');
      } catch (e) {
        keyPayload = KdbxUtils.kdbxErrorPayload(e);
      }
      expect(typeof keyPayload === 'number').assertTrue();
      // KdbxError 未知错误码：原文（message）透传
      let unknown: string | number = '';
      try {
        throw new KdbxError('TotallyUnknown', 'why');
      } catch (e) {
        unknown = KdbxUtils.kdbxErrorPayload(e);
      }
      expect(unknown).assertEqual('Error TotallyUnknown: why');
    });
  });
}
