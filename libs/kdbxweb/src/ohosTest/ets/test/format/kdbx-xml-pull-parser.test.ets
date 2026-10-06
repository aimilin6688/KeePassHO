import { describe, expect, it, beforeAll, afterAll } from '@ohos/hypium';
import * as kdbxweb from '../../../../main/ets/index';
import { ohosArgon2 } from '../../../../main/ets/crypto/argon2-rs';
import { TestResources } from '../test-support/test-resources';
import { fileIo as fs } from '@kit.CoreFileKit';

const TEST_DIR = '/data/storage/el2/base/haps/entry/files/xml-pull-parser-test';
const tmpFiles: string[] = [];

function writeFile(path: string, data: ArrayBuffer): Promise<void> {
    return fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC).then((file) => {
        return fs.write(file.fd, data).then(() => {
            return fs.fsync(file.fd).then(() => fs.close(file.fd));
        });
    });
}

function makeCred(password: string, keyFile?: ArrayBuffer): kdbxweb.KdbxCredentials {
    return new kdbxweb.KdbxCredentials(
        kdbxweb.ProtectedValue.fromString(password),
        keyFile
    );
}

function makeChaChaDb(name: string, cred: kdbxweb.KdbxCredentials): kdbxweb.Kdbx {
    const db = kdbxweb.Kdbx.create(cred, name);
    db.header.dataCipherUuid = new kdbxweb.KdbxUuid(kdbxweb.Consts.CipherId.ChaCha20);
    return db;
}

async function diffLoad(name: string, dbBuf: ArrayBuffer, cred: kdbxweb.KdbxCredentials): Promise<void> {
    const dbPath = TEST_DIR + '/' + name + '.kdbx';
    await writeFile(dbPath, dbBuf);
    tmpFiles.push(dbPath);

    const domT1 = TEST_DIR + '/' + name + '-dom-t1.tmp';
    const domT2 = TEST_DIR + '/' + name + '-dom-t2.tmp';
    const streamT1 = TEST_DIR + '/' + name + '-stream-t1.tmp';
    const streamT2 = TEST_DIR + '/' + name + '-stream-t2.tmp';
    tmpFiles.push(domT1, domT2, streamT1, streamT2);

    kdbxweb.KdbxFormat.streamingXmlParse = false;
    let domDb: kdbxweb.Kdbx;
    try {
        domDb = await kdbxweb.Kdbx.loadFromFile(dbPath, cred, { t1Path: domT1, t2Path: domT2 });
    } finally {
        kdbxweb.KdbxFormat.streamingXmlParse = false;
    }
    kdbxweb.KdbxFormat.streamingXmlParse = true;
    let streamDb: kdbxweb.Kdbx;
    try {
        streamDb = await kdbxweb.Kdbx.loadFromFile(dbPath, cred, { t1Path: streamT1, t2Path: streamT2 });
    } finally {
        kdbxweb.KdbxFormat.streamingXmlParse = false;
    }

    const domJson = JSON.stringify(dbToJson(domDb));
    const streamJson = JSON.stringify(dbToJson(streamDb));
    expect(domJson).assertEqual(streamJson);
}

// ==================== 模型 JSON 序列化（用于差分深比对） ====================

interface DeletedObjJson {
    uuid: string | undefined;
    deletionTime: string | undefined;
}

interface CustomDataEntryJson {
    key: string;
    value: string | undefined;
    lastModified: string | undefined;
}

interface CustomIconJson {
    data: string | undefined;
    name: string | undefined;
    lastModified: string | undefined;
}

interface TimesJson {
    creationTime: string | null;
    lastModTime: string | null;
    lastAccessTime: string | null;
    expiryTime: string | null;
    expires: boolean | null;
    usageCount: number | null;
    locationChanged: string | null;
}

interface AutoTypeJson {
    enabled: boolean;
    obfuscation: number;
    defaultSequence: string | null;
    items: kdbxweb.KdbxAutoTypeItem[];
}

interface FieldEntryJson {
    key: string;
    value: string;
}

interface BinaryEntryJson {
    key: string;
    value: string;
}

interface EntryJson {
    uuid: string;
    icon: number | null;
    customIcon: string | null;
    fgColor: string | null;
    bgColor: string | null;
    overrideUrl: string | null;
    tags: string[];
    qualityCheck: boolean | null;
    previousParentGroup: string | null;
    times: TimesJson;
    fields: FieldEntryJson[];
    binaries: BinaryEntryJson[];
    autoType: AutoTypeJson;
    history: EntryJson[];
    customData: CustomDataEntryJson[] | null;
}

interface GroupJson {
    uuid: string;
    name: string | null;
    notes: string | null;
    icon: number | null;
    customIcon: string | null;
    tags: string[];
    expanded: boolean | null;
    defaultAutoTypeSeq: string | null;
    enableAutoType: boolean | null | undefined;
    enableSearching: boolean | null | undefined;
    lastTopVisibleEntry: string | null;
    previousParentGroup: string | null;
    fgColor: string | null;
    bgColor: string | null;
    times: TimesJson;
    customData: CustomDataEntryJson[] | null;
    entries: EntryJson[];
    groups: GroupJson[];
}

interface MetaJson {
    generator: string | null;
    name: string | null;
    desc: string | null;
    defaultUser: string | null;
    settingsChanged: string | null;
    nameChanged: string | null;
    descChanged: string | null;
    defaultUserChanged: string | null;
    mntncHistoryDays: number | null;
    color: string | null;
    keyChanged: string | null;
    keyChangeRec: number | null;
    keyChangeForce: number | null;
    recycleBinEnabled: boolean | null;
    recycleBinUuid: string | null;
    recycleBinChanged: string | null;
    entryTemplatesGroup: string | null;
    entryTemplatesGroupChanged: string | null;
    historyMaxItems: number | null;
    historyMaxSize: number | null;
    lastSelectedGroup: string | null;
    lastTopVisibleGroup: string | null;
    memoryProtection: kdbxweb.KdbxMemoryProtection;
    customData: CustomDataEntryJson[];
    customIcons: CustomIconJson[];
    headerHash: string | null;
}

interface DbJson {
    meta: MetaJson;
    groups: GroupJson[];
    deletedObjects: DeletedObjJson[];
}

function dbToJson(db: kdbxweb.Kdbx): DbJson {
    const deleted: DeletedObjJson[] = [];
    for (let i = 0; i < db.deletedObjects.length; i++) {
        const d = db.deletedObjects[i];
        deleted.push({ uuid: d.uuid?.id, deletionTime: d.deletionTime?.toISOString() });
    }
    return {
        meta: metaToJson(db.meta),
        groups: db.groups.map(g => groupToJson(g)),
        deletedObjects: deleted
    };
}

function metaToJson(m: kdbxweb.KdbxMeta): MetaJson {
    return {
        generator: m.generator ?? null,
        name: m.name ?? null,
        desc: m.desc ?? null,
        defaultUser: m.defaultUser ?? null,
        settingsChanged: m.settingsChanged?.toISOString() ?? null,
        nameChanged: m.nameChanged?.toISOString() ?? null,
        descChanged: m.descChanged?.toISOString() ?? null,
        defaultUserChanged: m.defaultUserChanged?.toISOString() ?? null,
        mntncHistoryDays: m.mntncHistoryDays ?? null,
        color: m.color ?? null,
        keyChanged: m.keyChanged?.toISOString() ?? null,
        keyChangeRec: m.keyChangeRec ?? null,
        keyChangeForce: m.keyChangeForce ?? null,
        recycleBinEnabled: m.recycleBinEnabled ?? null,
        recycleBinUuid: m.recycleBinUuid?.id ?? null,
        recycleBinChanged: m.recycleBinChanged?.toISOString() ?? null,
        entryTemplatesGroup: m.entryTemplatesGroup?.id ?? null,
        entryTemplatesGroupChanged: m.entryTemplatesGroupChanged?.toISOString() ?? null,
        historyMaxItems: m.historyMaxItems ?? null,
        historyMaxSize: m.historyMaxSize ?? null,
        lastSelectedGroup: m.lastSelectedGroup?.id ?? null,
        lastTopVisibleGroup: m.lastTopVisibleGroup?.id ?? null,
        memoryProtection: m.memoryProtection,
        customData: customDataMapToJson(m.customData),
        customIcons: customIconsToJson(m.customIcons),
        headerHash: m.headerHash ? kdbxweb.ByteUtils.bytesToBase64(m.headerHash) : null
    };
}

function customDataMapToJson(m: Map<string, kdbxweb.KdbxCustomDataItem>): CustomDataEntryJson[] {
    const arr: CustomDataEntryJson[] = [];
    m.forEach((v, k) => {
        arr.push({ key: k, value: v.value ?? undefined, lastModified: v.lastModified?.toISOString() });
    });
    return arr;
}

function customIconsToJson(m: Map<string, kdbxweb.KdbxCustomIcon>): CustomIconJson[] {
    const arr: CustomIconJson[] = [];
    m.forEach((v, k) => {
        arr.push({
            data: v.data ? kdbxweb.ByteUtils.bytesToBase64(v.data) : undefined,
            name: v.name ?? undefined,
            lastModified: v.lastModified?.toISOString()
        });
    });
    return arr;
}

function groupToJson(g: kdbxweb.KdbxGroup): GroupJson {
    return {
        uuid: g.uuid.id,
        name: g.name ?? null,
        notes: g.notes ?? null,
        icon: g.icon ?? null,
        customIcon: g.customIcon?.id ?? null,
        tags: g.tags,
        expanded: g.expanded ?? null,
        defaultAutoTypeSeq: g.defaultAutoTypeSeq ?? null,
        enableAutoType: g.enableAutoType ?? null,
        enableSearching: g.enableSearching ?? null,
        lastTopVisibleEntry: g.lastTopVisibleEntry?.id ?? null,
        previousParentGroup: g.previousParentGroup?.id ?? null,
        fgColor: g.fgColor ?? null,
        bgColor: g.bgColor ?? null,
        times: timesToJson(g.times),
        customData: g.customData ? customDataMapToJson(g.customData) : null,
        entries: g.entries.map(e => entryToJson(e)),
        groups: g.groups.map(sub => groupToJson(sub))
    };
}

function entryToJson(e: kdbxweb.KdbxEntry): EntryJson {
    const fields: FieldEntryJson[] = [];
    e.fields.forEach((v, k) => fields.push({ key: k, value: fieldToJson(v) }));
    const bins: BinaryEntryJson[] = [];
    e.binaries.forEach((v, k) => bins.push({ key: k, value: binaryToJson(v) }));
    return {
        uuid: e.uuid.id,
        icon: e.icon ?? null,
        customIcon: e.customIcon?.id ?? null,
        fgColor: e.fgColor ?? null,
        bgColor: e.bgColor ?? null,
        overrideUrl: e.overrideUrl ?? null,
        tags: e.tags,
        qualityCheck: e.qualityCheck ?? null,
        previousParentGroup: e.previousParentGroup?.id ?? null,
        times: timesToJson(e.times),
        fields,
        binaries: bins,
        autoType: {
            enabled: e.autoType.enabled,
            obfuscation: e.autoType.obfuscation,
            defaultSequence: e.autoType.defaultSequence ?? null,
            items: e.autoType.items
        },
        history: e.history.map(h => entryToJson(h)),
        customData: e.customData ? customDataMapToJson(e.customData) : null
    };
}

function fieldToJson(v: kdbxweb.KdbxEntryField): string {
    if (v instanceof kdbxweb.ProtectedValue) {
        return v.getText();
    }
    return v ?? '';
}

function binaryToJson(v: kdbxweb.KdbxBinary | kdbxweb.KdbxBinaryWithHash): string {
    let bin: kdbxweb.KdbxBinary;
    if (kdbxweb.KdbxBinaries.isKdbxBinaryWithHash(v)) {
        bin = v.value;
    } else {
        bin = v;
    }
    if (bin instanceof kdbxweb.ProtectedValue) {
        return kdbxweb.ByteUtils.bytesToBase64(bin.getBinary());
    }
    if (bin instanceof ArrayBuffer) {
        return kdbxweb.ByteUtils.bytesToBase64(bin);
    }
    return '';
}

function timesToJson(t: kdbxweb.KdbxTimes): TimesJson {
    return {
        creationTime: t.creationTime?.toISOString() ?? null,
        lastModTime: t.lastModTime?.toISOString() ?? null,
        lastAccessTime: t.lastAccessTime?.toISOString() ?? null,
        expiryTime: t.expiryTime?.toISOString() ?? null,
        expires: t.expires ?? null,
        usageCount: t.usageCount ?? null,
        locationChanged: t.locationChanged?.toISOString() ?? null
    };
}

// ==================== 测试套件 ====================

export default function KdbxXmlPullParserTest() {
    describe('KdbxXmlPullParser', () => {
        beforeAll(() => {
            kdbxweb.CryptoEngine.setArgon2Impl(ohosArgon2);
            try {
                if (!fs.accessSync(TEST_DIR, fs.AccessModeType.EXIST)) {
                    fs.mkdirSync(TEST_DIR, true);
                }
            } catch (e) {
                // 目录可能已存在
            }
        });

        afterAll(() => {
            for (const f of tmpFiles) {
                try { fs.unlinkSync(f); } catch { /* ignore */ }
            }
        });

        // ==================== 真实 fixture 差分 ====================

        it('diff: argon2ChaCha fixture', 0, async () => {
            const cred = makeCred('demo', TestResources.demoKey);
            await diffLoad('argon2chacha', TestResources.argon2ChaCha, cred);
        });

        // ==================== 空库 / 基础结构 ====================

        it('diff: empty database with default group only', 0, async () => {
            const cred = makeCred('empty');
            const db = makeChaChaDb('EmptyDb', cred);
            await diffLoad('empty', await db.save(), cred);
        });

        it('diff: nested groups (3 levels, no entries)', 0, async () => {
            const cred = makeCred('groups');
            const db = makeChaChaDb('GroupsDb', cred);
            const root = db.getDefaultGroup();
            db.createGroup(root, 'Sub1');
            db.createGroup(root, 'Sub2');
            const sub1 = root.groups[0];
            db.createGroup(sub1, 'Sub1_1');
            db.createGroup(sub1, 'Sub1_2');
            await diffLoad('nested-groups', await db.save(), cred);
        });

        // ==================== Meta 全字段覆盖 ====================

        it('diff: all meta fields populated', 0, async () => {
            const cred = makeCred('meta');
            const db = makeChaChaDb('MetaDb', cred);
            const m = db.meta;
            m.name = 'Test DB';
            m.desc = 'A description';
            m.defaultUser = 'defaultuser';
            m.mntncHistoryDays = 365;
            m.color = 'FF0000';
            m.keyChangeRec = 30;
            m.keyChangeForce = 90;
            m.recycleBinEnabled = true;
            m.historyMaxItems = 10;
            m.historyMaxSize = 65536;
            m.memoryProtection = {
                title: true, userName: true, password: true, url: true, notes: true
            };
            const iconId = new kdbxweb.KdbxUuid().id;
            m.customIcons.set(iconId, {
                data: kdbxweb.ByteUtils.stringToBuffer('icon-data'),
                name: 'icon-name',
                lastModified: new Date('2026-03-01T00:00:00.000Z')
            });
            m.customData.set('mkey', {
                value: 'mval',
                lastModified: new Date('2026-03-02T00:00:00.000Z')
            });
            await diffLoad('meta-full', await db.save(), cred);
        });

        it('diff: meta customData without lastModified', 0, async () => {
            const cred = makeCred('cd');
            const db = makeChaChaDb('CdDb', cred);
            db.meta.customData.set('k1', { value: 'v1' });
            db.meta.customData.set('k2', { value: 'v2' });
            await diffLoad('meta-cd', await db.save(), cred);
        });

        // ==================== Entry 字段覆盖 ====================

        it('diff: entry with all scalar fields', 0, async () => {
            const cred = makeCred('entry');
            const db = makeChaChaDb('EntryDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'MyTitle');
            e.setField('UserName', 'myuser', true);
            e.setField('Password', 'mypass', true);
            e.setField('URL', 'https://x.com');
            e.setField('Notes', 'some notes');
            e.setField('Custom1', 'val1');
            e.setField('Custom2', 'val2', true);
            e.icon = 5;
            e.tags = ['a', 'b', 'c'];
            e.overrideUrl = 'cmd://app';
            e.fgColor = '#FF0000';
            e.bgColor = '#00FF00';
            await diffLoad('entry-full', await db.save(), cred);
        });

        it('diff: entry with empty protected field', 0, async () => {
            const cred = makeCred('emptyprot');
            const db = makeChaChaDb('EmptyProtDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'E');
            e.setField('Password', '', true);
            await diffLoad('entry-empty-prot', await db.save(), cred);
        });

        it('diff: entry with tags', 0, async () => {
            const cred = makeCred('tags');
            const db = makeChaChaDb('TagsDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'Tagged');
            e.tags = ['tag1', 'tag2', 'tag3'];
            await diffLoad('entry-tags', await db.save(), cred);
        });

        // ==================== History ====================

        it('diff: entry with multiple history entries', 0, async () => {
            const cred = makeCred('hist');
            const db = makeChaChaDb('HistDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'V1');
            e.pushHistory();
            e.setField('Title', 'V2');
            e.pushHistory();
            e.setField('Title', 'V3');
            await diffLoad('entry-history', await db.save(), cred);
        });

        // ==================== AutoType ====================

        it('diff: entry with autotype items', 0, async () => {
            const cred = makeCred('at');
            const db = makeChaChaDb('AutoTypeDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'AT');
            e.autoType.enabled = false;
            e.autoType.obfuscation = 1;
            e.autoType.defaultSequence = '{USERNAME}{TAB}{PASSWORD}{ENTER}';
            e.autoType.items.push({ window: 'Win1*', keystrokeSequence: '{ENTER}' });
            e.autoType.items.push({ window: 'Win2', keystrokeSequence: '{TAB}{ENTER}' });
            await diffLoad('entry-autotype', await db.save(), cred);
        });

        it('diff: entry with autotype disabled', 0, async () => {
            const cred = makeCred('atdis');
            const db = makeChaChaDb('AutoTypeDisabledDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'ATD');
            e.autoType.enabled = false;
            e.autoType.obfuscation = 0;
            await diffLoad('entry-autotype-disabled', await db.save(), cred);
        });

        // ==================== Binary / 附件 ====================

        it('diff: entry with binary attachment (pool ref)', 0, async () => {
            const cred = makeCred('bin');
            const db = makeChaChaDb('BinDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'Bin');
            const bin = await db.binaries.add(kdbxweb.ByteUtils.stringToBuffer('hello-world'));
            e.binaries.set('a.txt', bin);
            await diffLoad('entry-binary', await db.save(), cred);
        });

        it('diff: entry with multiple binary attachments', 0, async () => {
            const cred = makeCred('multibin');
            const db = makeChaChaDb('MultiBinDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'MB');
            const b1 = await db.binaries.add(kdbxweb.ByteUtils.stringToBuffer('data1'));
            const b2 = await db.binaries.add(kdbxweb.ByteUtils.stringToBuffer('data2'));
            const b3 = await db.binaries.add(new ArrayBuffer(16));
            e.binaries.set('f1.txt', b1);
            e.binaries.set('f2.txt', b2);
            e.binaries.set('f3.bin', b3);
            await diffLoad('entry-multi-binary', await db.save(), cred);
        });

        it('diff: same binary content shared across entries', 0, async () => {
            const cred = makeCred('sharebin');
            const db = makeChaChaDb('ShareBinDb', cred);
            const bin = await db.binaries.add(kdbxweb.ByteUtils.stringToBuffer('shared-content'));
            const e1 = db.createEntry(db.getDefaultGroup());
            e1.setField('Title', 'E1');
            e1.binaries.set('s.txt', bin);
            const e2 = db.createEntry(db.getDefaultGroup());
            e2.setField('Title', 'E2');
            e2.binaries.set('s.txt', bin);
            await diffLoad('entry-shared-binary', await db.save(), cred);
        });

        // ==================== Group 颜色 / CustomData ====================

        it('diff: group with fgColor/bgColor via customData', 0, async () => {
            const cred = makeCred('gcolor');
            const db = makeChaChaDb('GroupColorDb', cred);
            const g = db.getDefaultGroup();
            g.fgColor = '#ABCDEF';
            g.bgColor = '#123456';
            g.customData = new Map<string, kdbxweb.KdbxCustomDataItem>();
            g.customData.set('fgColor', { value: '#ABCDEF' });
            g.customData.set('bgColor', { value: '#123456' });
            await diffLoad('group-color', await db.save(), cred);
        });

        it('diff: group with customData', 0, async () => {
            const cred = makeCred('gcd');
            const db = makeChaChaDb('GroupCdDb', cred);
            const g = db.getDefaultGroup();
            g.customData = new Map<string, kdbxweb.KdbxCustomDataItem>();
            g.customData.set('gk1', { value: 'gv1' });
            g.customData.set('gk2', { value: 'gv2', lastModified: new Date('2026-04-01T00:00:00.000Z') });
            await diffLoad('group-customdata', await db.save(), cred);
        });

        it('diff: entry with customData', 0, async () => {
            const cred = makeCred('ecd');
            const db = makeChaChaDb('EntryCdDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'ECD');
            e.customData = new Map<string, kdbxweb.KdbxCustomDataItem>();
            e.customData.set('ek1', { value: 'ev1' });
            e.customData.set('ek2', { value: 'ev2', lastModified: new Date('2026-05-01T00:00:00.000Z') });
            await diffLoad('entry-customdata', await db.save(), cred);
        });

        // ==================== Deleted Objects ====================

        it('diff: deleted objects in recycle bin', 0, async () => {
            const cred = makeCred('del');
            const db = makeChaChaDb('DelDb', cred);
            db.createRecycleBin();
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'ToDelete');
            db.remove(e);
            await diffLoad('deleted', await db.save(), cred);
        });

        // ==================== XML 特殊字符 ====================

        it('diff: XML entities in text fields', 0, async () => {
            const cred = makeCred('ent');
            const db = makeChaChaDb('EntitiesDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'a<b>c&d"e\'f');
            e.setField('Notes', 'line1\nline2\ttab<>&"\'');
            await diffLoad('entities', await db.save(), cred);
        });

        it('diff: unicode and multibyte characters', 0, async () => {
            const cred = makeCred('uni');
            const db = makeChaChaDb('UnicodeDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', '中文标题');
            e.setField('Notes', '日本語テスト 한국어 ελληνικά русский');
            await diffLoad('unicode', await db.save(), cred);
        });

        // ==================== Boolean 边界值 ====================

        it('diff: boolean null values', 0, async () => {
            const cred = makeCred('bool');
            const db = makeChaChaDb('BoolDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'B');
            e.autoType.enabled = true;
            e.autoType.obfuscation = 0;
            const g = db.getDefaultGroup();
            g.enableAutoType = null;
            g.enableSearching = null;
            await diffLoad('bool-null', await db.save(), cred);
        });

        // ==================== 大文本跨块 ====================

        it('diff: large notes field crossing chunk boundary', 0, async () => {
            const cred = makeCred('large');
            const db = makeChaChaDb('LargeDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'Large');
            let big = '';
            for (let i = 0; i < 50000; i++) {
                big += 'Line ' + i + ' of large notes content.\n';
            }
            e.setField('Notes', big);
            await diffLoad('large-text', await db.save(), cred);
        });

        // ==================== 多 entry 综合场景 ====================

        it('diff: mixed database (groups/entries/binaries/history/deleted)', 0, async () => {
            const cred = makeCred('mixed');
            const db = makeChaChaDb('MixedDb', cred);
            const root = db.getDefaultGroup();
            root.notes = 'root notes';
            root.tags = ['root1', 'root2'];

            const sub = db.createGroup(root, 'SubGroup');
            sub.icon = 4;
            sub.expanded = false;

            const e1 = db.createEntry(sub);
            e1.setField('Title', 'Entry1');
            e1.setField('UserName', 'u1', true);
            e1.setField('Password', 'p1', true);
            e1.tags = ['t1'];
            e1.pushHistory();
            e1.setField('Title', 'Entry1-v2');
            e1.autoType.items.push({ window: 'W1', keystrokeSequence: '{ENTER}' });

            const e2 = db.createEntry(root);
            e2.setField('Title', 'Entry2');
            const bin = await db.binaries.add(kdbxweb.ByteUtils.stringToBuffer('payload'));
            e2.binaries.set('f.bin', bin);

            db.createRecycleBin();
            const e3 = db.createEntry(root);
            e3.setField('Title', 'ToDelete');
            db.remove(e3);

            db.meta.customData.set('mk', { value: 'mv' });
            await diffLoad('mixed', await db.save(), cred);
        });

        // ==================== v4.1 特性 ====================

        it('diff: v4.1 features (tags, qualityCheck, customIcon)', 0, async () => {
            const cred = makeCred('v41');
            const db = makeChaChaDb('V41Db', cred);
            const root = db.getDefaultGroup();
            root.tags = ['g-tag'];
            const sub = db.createGroup(root, 'Sub');
            const e = db.createEntry(sub);
            e.setField('Title', 'V41');
            e.tags = ['e-tag1', 'e-tag2'];
            e.qualityCheck = false;
            const iconId = new kdbxweb.KdbxUuid().id;
            db.meta.customIcons.set(iconId, {
                data: kdbxweb.ByteUtils.stringToBuffer('ic'),
                name: 'icn',
                lastModified: new Date('2026-06-01T00:00:00.000Z')
            });
            e.customIcon = new kdbxweb.KdbxUuid(iconId);
            await diffLoad('v41-features', await db.save(), cred);
        });

        // ==================== 验证流式解析器确实被调用 ====================

        it('streaming parser produces non-empty model', 0, async () => {
            const cred = makeCred('nonempty');
            const db = makeChaChaDb('NonEmptyDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'VerifyStreaming');
            const dbBuf = await db.save();
            const dbPath = TEST_DIR + '/nonempty.kdbx';
            await writeFile(dbPath, dbBuf);
            tmpFiles.push(dbPath);
            const t1 = TEST_DIR + '/nonempty-t1.tmp';
            const t2 = TEST_DIR + '/nonempty-t2.tmp';
            tmpFiles.push(t1, t2);

            kdbxweb.KdbxFormat.streamingXmlParse = true;
            let loaded: kdbxweb.Kdbx;
            try {
                loaded = await kdbxweb.Kdbx.loadFromFile(dbPath, cred, { t1Path: t1, t2Path: t2 });
            } finally {
                kdbxweb.KdbxFormat.streamingXmlParse = false;
            }
            expect(loaded.groups.length > 0).assertTrue();
            let found = false;
            for (const g of loaded.groups) {
                for (const entry of g.entries) {
                    const t = entry.fields.get('Title');
                    if (t === 'VerifyStreaming') {
                        found = true;
                    }
                }
            }
            expect(found).assertTrue();
        });

        it('streaming parser handles wrong password', 0, async () => {
            const cred = makeCred('right');
            const db = makeChaChaDb('WrongPassDb', cred);
            const dbBuf = await db.save();
            const dbPath = TEST_DIR + '/wrongpass.kdbx';
            await writeFile(dbPath, dbBuf);
            tmpFiles.push(dbPath);
            const t1 = TEST_DIR + '/wrongpass-t1.tmp';
            const t2 = TEST_DIR + '/wrongpass-t2.tmp';
            tmpFiles.push(t1, t2);

            const wrongCred = makeCred('wrong');
            kdbxweb.KdbxFormat.streamingXmlParse = true;
            try {
                await kdbxweb.Kdbx.loadFromFile(dbPath, wrongCred, { t1Path: t1, t2Path: t2 });
                throw new Error('should have thrown InvalidKey');
            } catch (e) {
                expect(e instanceof kdbxweb.KdbxError).assertTrue();
                expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidKey);
            } finally {
                kdbxweb.KdbxFormat.streamingXmlParse = false;
            }
        });
    });
}
