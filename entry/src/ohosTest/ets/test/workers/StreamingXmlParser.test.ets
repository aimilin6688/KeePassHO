import { describe, expect, it, beforeAll, afterAll } from '@ohos/hypium';
import { Kdbx, KdbxCredentials, KdbxUuid, ProtectedValue, Consts, ByteUtils, KdbxFormat, KdbxCustomDataItem, KdbxError, KdbxGroup, KdbxEntry, KdbxEntryField } from 'kdbxweb';
import { fileIo as fs } from '@kit.CoreFileKit';

const TEST_DIR = '/data/storage/el2/base/haps/entry/files/streaming-xml-test';
const tmpFiles: string[] = [];

function writeFile(path: string, data: ArrayBuffer): Promise<void> {
    return fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC).then((file) => {
        return fs.write(file.fd, data).then(() => {
            return fs.fsync(file.fd).then(() => fs.close(file.fd));
        });
    });
}

function makeCred(password: string): KdbxCredentials {
    return new KdbxCredentials(ProtectedValue.fromString(password));
}

function makeChaChaDb(name: string, cred: KdbxCredentials): Kdbx {
    const db = Kdbx.create(cred, name);
    db.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
    return db;
}

function dbToSummary(db: Kdbx): string {
    const lines: string[] = [];
    lines.push('meta.name=' + (db.meta.name ?? 'null'));
    lines.push('meta.desc=' + (db.meta.desc ?? 'null'));
    lines.push('meta.recycleBinEnabled=' + db.meta.recycleBinEnabled);
    lines.push('meta.historyMaxItems=' + db.meta.historyMaxItems);
    lines.push('meta.memoryProtection.title=' + db.meta.memoryProtection.title);
    lines.push('meta.memoryProtection.password=' + db.meta.memoryProtection.password);
    lines.push('meta.customData.size=' + db.meta.customData.size);
    lines.push('meta.customIcons.size=' + db.meta.customIcons.size);
    lines.push('groups.length=' + db.groups.length);
    for (const g of db.groups) {
        appendGroupSummary(g, lines, 0);
    }
    lines.push('deletedObjects=' + db.deletedObjects.length);
    return lines.join('\n');
}

function appendGroupSummary(g: KdbxGroup, lines: string[], depth: number): void {
    const prefix = '  '.repeat(depth);
    lines.push(prefix + 'group.name=' + (g.name ?? 'null'));
    lines.push(prefix + 'group.notes=' + (g.notes ?? 'null'));
    lines.push(prefix + 'group.icon=' + g.icon);
    lines.push(prefix + 'group.tags=' + g.tags.join(','));
    lines.push(prefix + 'group.fgColor=' + (g.fgColor ?? 'null'));
    lines.push(prefix + 'group.bgColor=' + (g.bgColor ?? 'null'));
    lines.push(prefix + 'group.expanded=' + g.expanded);
    lines.push(prefix + 'group.enableAutoType=' + g.enableAutoType);
    lines.push(prefix + 'group.enableSearching=' + g.enableSearching);
    lines.push(prefix + 'group.customData.size=' + (g.customData ? g.customData.size : 0));
    lines.push(prefix + 'group.times.lastMod=' + (g.times.lastModTime?.toISOString() ?? 'null'));
    lines.push(prefix + 'entries=' + g.entries.length);
    for (const e of g.entries) {
        appendEntrySummary(e, lines, depth + 1);
    }
    for (const sub of g.groups) {
        appendGroupSummary(sub, lines, depth + 1);
    }
}

function appendEntrySummary(e: KdbxEntry, lines: string[], depth: number): void {
    const prefix = '  '.repeat(depth);
    lines.push(prefix + 'entry.fields.Title=' + fieldText(e.fields.get('Title')));
    lines.push(prefix + 'entry.fields.UserName=' + fieldText(e.fields.get('UserName')));
    lines.push(prefix + 'entry.fields.Password=' + fieldText(e.fields.get('Password')));
    lines.push(prefix + 'entry.fields.URL=' + fieldText(e.fields.get('URL')));
    lines.push(prefix + 'entry.fields.Notes=' + fieldText(e.fields.get('Notes')));
    lines.push(prefix + 'entry.icon=' + e.icon);
    lines.push(prefix + 'entry.tags=' + e.tags.join(','));
    lines.push(prefix + 'entry.fgColor=' + (e.fgColor ?? 'null'));
    lines.push(prefix + 'entry.bgColor=' + (e.bgColor ?? 'null'));
    lines.push(prefix + 'entry.overrideUrl=' + (e.overrideUrl ?? 'null'));
    lines.push(prefix + 'entry.qualityCheck=' + e.qualityCheck);
    lines.push(prefix + 'entry.autoType.enabled=' + e.autoType.enabled);
    lines.push(prefix + 'entry.autoType.obfuscation=' + e.autoType.obfuscation);
    lines.push(prefix + 'entry.autoType.defaultSeq=' + (e.autoType.defaultSequence ?? 'null'));
    lines.push(prefix + 'entry.autoType.items=' + e.autoType.items.length);
    for (let i = 0; i < e.autoType.items.length; i++) {
        lines.push(prefix + 'entry.autoType.item[' + i + ']=' + e.autoType.items[i].window + '|' + e.autoType.items[i].keystrokeSequence);
    }
    lines.push(prefix + 'entry.binaries.size=' + e.binaries.size);
    lines.push(prefix + 'entry.history=' + e.history.length);
    lines.push(prefix + 'entry.customData.size=' + (e.customData ? e.customData.size : 0));
    lines.push(prefix + 'entry.times.lastMod=' + (e.times.lastModTime?.toISOString() ?? 'null'));
    for (const h of e.history) {
        appendEntrySummary(h, lines, depth + 1);
    }
}

function fieldText(v: KdbxEntryField | undefined): string {
    if (v instanceof ProtectedValue) {
        return v.getText();
    }
    return v ?? 'null';
}

async function diffLoad(name: string, dbBuf: ArrayBuffer, cred: KdbxCredentials): Promise<void> {
    const dbPath = TEST_DIR + '/' + name + '.kdbx';
    await writeFile(dbPath, dbBuf);
    tmpFiles.push(dbPath);
    const domT1 = TEST_DIR + '/' + name + '-dom-t1.tmp';
    const domT2 = TEST_DIR + '/' + name + '-dom-t2.tmp';
    const streamT1 = TEST_DIR + '/' + name + '-stream-t1.tmp';
    const streamT2 = TEST_DIR + '/' + name + '-stream-t2.tmp';
    tmpFiles.push(domT1, domT2, streamT1, streamT2);

    KdbxFormat.streamingXmlParse = false;
    let domDb: Kdbx;
    try {
        domDb = await Kdbx.loadFromFile(dbPath, cred, { t1Path: domT1, t2Path: domT2 });
    } finally {
        KdbxFormat.streamingXmlParse = false;
    }
    KdbxFormat.streamingXmlParse = true;
    let streamDb: Kdbx;
    try {
        streamDb = await Kdbx.loadFromFile(dbPath, cred, { t1Path: streamT1, t2Path: streamT2 });
    } finally {
        KdbxFormat.streamingXmlParse = false;
    }

    const domSummary = dbToSummary(domDb);
    const streamSummary = dbToSummary(streamDb);
    if (domSummary !== streamSummary) {
        console.error('DOM:\n' + domSummary);
        console.error('STREAM:\n' + streamSummary);
    }
    expect(domSummary).assertEqual(streamSummary);
}

export default function StreamingXmlParserTest() {
    describe('StreamingXmlParserTest', () => {
        beforeAll(() => {
            try {
                if (!fs.accessSync(TEST_DIR, fs.AccessModeType.EXIST)) {
                    fs.mkdirSync(TEST_DIR, true);
                }
            } catch (e) {
                // ignore
            }
        });

        afterAll(() => {
            for (const f of tmpFiles) {
                try { fs.unlinkSync(f); } catch { /* ignore */ }
            }
        });

        it('diff: empty database', 0, async () => {
            const cred = makeCred('empty');
            const db = makeChaChaDb('EmptyDb', cred);
            await diffLoad('empty', await db.save(), cred);
        });

        it('diff: nested groups', 0, async () => {
            const cred = makeCred('groups');
            const db = makeChaChaDb('GroupsDb', cred);
            const root = db.getDefaultGroup();
            db.createGroup(root, 'Sub1');
            db.createGroup(root, 'Sub2');
            db.createGroup(root.groups[0], 'Sub1_1');
            await diffLoad('nested-groups', await db.save(), cred);
        });

        it('diff: meta all fields', 0, async () => {
            const cred = makeCred('meta');
            const db = makeChaChaDb('MetaDb', cred);
            const m = db.meta;
            m.name = 'Test DB';
            m.desc = 'Description';
            m.defaultUser = 'defuser';
            m.mntncHistoryDays = 365;
            m.color = 'FF0000';
            m.keyChangeRec = 30;
            m.keyChangeForce = 90;
            m.historyMaxItems = 10;
            m.historyMaxSize = 65536;
            m.memoryProtection = { title: true, userName: true, password: true, url: true, notes: true };
            m.customData.set('mk', { value: 'mv', lastModified: new Date('2026-03-02T00:00:00.000Z') });
            m.customIcons.set(new KdbxUuid().id, {
                data: ByteUtils.stringToBuffer('icon'),
                name: 'icn',
                lastModified: new Date('2026-03-01T00:00:00.000Z')
            });
            await diffLoad('meta-full', await db.save(), cred);
        });

        it('diff: entry with protected fields', 0, async () => {
            const cred = makeCred('entry');
            const db = makeChaChaDb('EntryDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'MyTitle');
            e.setField('UserName', 'user', true);
            e.setField('Password', 'pass', true);
            e.setField('URL', 'https://x.com');
            e.setField('Notes', 'notes');
            e.icon = 5;
            e.tags = ['a', 'b'];
            await diffLoad('entry-prot', await db.save(), cred);
        });

        it('diff: entry with history', 0, async () => {
            const cred = makeCred('hist');
            const db = makeChaChaDb('HistDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'V1');
            e.pushHistory();
            e.setField('Title', 'V2');
            e.pushHistory();
            await diffLoad('entry-history', await db.save(), cred);
        });

        it('diff: entry with autotype', 0, async () => {
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

        it('diff: entry with binary attachment', 0, async () => {
            const cred = makeCred('bin');
            const db = makeChaChaDb('BinDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'Bin');
            const bin = await db.binaries.add(ByteUtils.stringToBuffer('hello-world'));
            e.binaries.set('a.txt', bin);
            await diffLoad('entry-binary', await db.save(), cred);
        });

        it('diff: group with customData and colors', 0, async () => {
            const cred = makeCred('gcd');
            const db = makeChaChaDb('GroupCdDb', cred);
            const g = db.getDefaultGroup();
            g.fgColor = '#ABCDEF';
            g.bgColor = '#123456';
            g.customData = new Map<string, KdbxCustomDataItem>();
            g.customData.set('fgColor', { value: '#ABCDEF' });
            g.customData.set('bgColor', { value: '#123456' });
            g.customData.set('gk', { value: 'gv' });
            await diffLoad('group-customdata', await db.save(), cred);
        });

        it('diff: entry with customData', 0, async () => {
            const cred = makeCred('ecd');
            const db = makeChaChaDb('EntryCdDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'ECD');
            e.customData = new Map<string, KdbxCustomDataItem>();
            e.customData.set('ek1', { value: 'ev1' });
            e.customData.set('ek2', { value: 'ev2', lastModified: new Date('2026-05-01T00:00:00.000Z') });
            await diffLoad('entry-customdata', await db.save(), cred);
        });

        it('diff: deleted objects', 0, async () => {
            const cred = makeCred('del');
            const db = makeChaChaDb('DelDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'ToDelete');
            db.remove(e);
            await diffLoad('deleted', await db.save(), cred);
        });

        it('diff: XML entities', 0, async () => {
            const cred = makeCred('ent');
            const db = makeChaChaDb('EntitiesDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'a<b>c&d"e\'f');
            e.setField('Notes', 'line1\nline2\ttab<>&"\'');
            await diffLoad('entities', await db.save(), cred);
        });

        it('diff: unicode', 0, async () => {
            const cred = makeCred('uni');
            const db = makeChaChaDb('UnicodeDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', '中文标题');
            e.setField('Notes', '日本語 한국어 ελληνικά');
            await diffLoad('unicode', await db.save(), cred);
        });

        it('diff: boolean null values', 0, async () => {
            const cred = makeCred('bool');
            const db = makeChaChaDb('BoolDb', cred);
            const g = db.getDefaultGroup();
            g.enableAutoType = null;
            g.enableSearching = null;
            const e = db.createEntry(g);
            e.setField('Title', 'B');
            e.autoType.enabled = true;
            e.autoType.obfuscation = 0;
            await diffLoad('bool-null', await db.save(), cred);
        });

        it('diff: large text crossing chunk boundary', 0, async () => {
            const cred = makeCred('large');
            const db = makeChaChaDb('LargeDb', cred);
            const e = db.createEntry(db.getDefaultGroup());
            e.setField('Title', 'Large');
            let big = '';
            for (let i = 0; i < 50000; i++) {
                big += 'Line ' + i + ' of content.\n';
            }
            e.setField('Notes', big);
            await diffLoad('large-text', await db.save(), cred);
        });

        it('diff: mixed database', 0, async () => {
            const cred = makeCred('mixed');
            const db = makeChaChaDb('MixedDb', cred);
            const root = db.getDefaultGroup();
            root.notes = 'root notes';
            root.tags = ['r1', 'r2'];
            const sub = db.createGroup(root, 'Sub');
            sub.icon = 4;
            sub.expanded = false;
            const e1 = db.createEntry(sub);
            e1.setField('Title', 'E1');
            e1.setField('UserName', 'u1', true);
            e1.setField('Password', 'p1', true);
            e1.tags = ['t1'];
            e1.pushHistory();
            e1.setField('Title', 'E1-v2');
            e1.autoType.items.push({ window: 'W1', keystrokeSequence: '{ENTER}' });
            const e2 = db.createEntry(root);
            e2.setField('Title', 'E2');
            const bin = await db.binaries.add(ByteUtils.stringToBuffer('payload'));
            e2.binaries.set('f.bin', bin);
            db.createRecycleBin();
            const e3 = db.createEntry(root);
            e3.setField('Title', 'Del');
            db.remove(e3);
            db.meta.customData.set('mk', { value: 'mv' });
            await diffLoad('mixed', await db.save(), cred);
        });

        it('streaming parser produces non-empty model', 0, async () => {
            const cred = makeCred('ne');
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
            KdbxFormat.streamingXmlParse = true;
            let loaded: Kdbx;
            try {
                loaded = await Kdbx.loadFromFile(dbPath, cred, { t1Path: t1, t2Path: t2 });
            } finally {
                KdbxFormat.streamingXmlParse = false;
            }
            expect(loaded.groups.length > 0).assertTrue();
            let found = false;
            for (const g of loaded.groups) {
                for (const entry of g.entries) {
                    if (entry.fields.get('Title') === 'VerifyStreaming') {
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
            KdbxFormat.streamingXmlParse = true;
            try {
                await Kdbx.loadFromFile(dbPath, wrongCred, { t1Path: t1, t2Path: t2 });
                throw new Error('should have thrown');
            } catch (e) {
                const isKdbxError = e instanceof KdbxError;
                const code = isKdbxError ? (e as KdbxError).code : undefined;
                expect(isKdbxError || code === Consts.ErrorCodes.InvalidKey).assertTrue();
            } finally {
                KdbxFormat.streamingXmlParse = false;
            }
        });
    });
}
