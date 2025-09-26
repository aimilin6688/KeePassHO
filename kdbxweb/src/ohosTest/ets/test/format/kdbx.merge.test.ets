import { describe, expect, it } from '@ohos/hypium';
import * as kdbxweb from '../../../../main/ets/index';
import { expects } from '../test-support/Asserts';


const dt:DateContainer = {
    pre1: new Date(2014, 1, 1),
    created: new Date(2015, 1, 1),
    upd1: new Date(2015, 1, 2),
    upd2: new Date(2015, 1, 3),
    upd3: new Date(2015, 1, 4),
    upd4: new Date(2015, 1, 5),
    upd5: new Date(2015, 1, 6),
    upd6: new Date(2015, 1, 7)
};

const id: IdContainer = {
    trash: kdbxweb.KdbxUuid.random(),
    name: kdbxweb.KdbxUuid.random(),
    tpl: kdbxweb.KdbxUuid.random(),
    eDel: kdbxweb.KdbxUuid.random(),
    eDel1: kdbxweb.KdbxUuid.random(),
    icon1: kdbxweb.KdbxUuid.random(),
    icon2: kdbxweb.KdbxUuid.random(),
    cd1: kdbxweb.KdbxUuid.random(),
    bin1: kdbxweb.KdbxUuid.random(),
    bin2: kdbxweb.KdbxUuid.random(),
    bin3: kdbxweb.KdbxUuid.random(),
    bin4: kdbxweb.KdbxUuid.random(),
    gRoot: kdbxweb.KdbxUuid.random(),
    g1: kdbxweb.KdbxUuid.random(),
    g11: kdbxweb.KdbxUuid.random(),
    g111: kdbxweb.KdbxUuid.random(),
    g112: kdbxweb.KdbxUuid.random(),
    g12: kdbxweb.KdbxUuid.random(),
    g2: kdbxweb.KdbxUuid.random(),
    g3: kdbxweb.KdbxUuid.random(),
    g31: kdbxweb.KdbxUuid.random(),
    g4: kdbxweb.KdbxUuid.random(),
    g5: kdbxweb.KdbxUuid.random(),
    er1: kdbxweb.KdbxUuid.random()
};

const bin:BinContainer = {
    bin1: kdbxweb.ByteUtils.stringToBytes('bin1'),
    bin2: kdbxweb.ByteUtils.stringToBytes('bin2'),
    bin3: kdbxweb.ByteUtils.stringToBytes('bin3'),
    bin4: kdbxweb.ByteUtils.stringToBytes('bin4'),
    icon1: kdbxweb.ByteUtils.stringToBytes('icon1'),
    icon2: kdbxweb.ByteUtils.stringToBytes('icon2')
};

export default function KdbxMergeTest() {
    describe('Kdbx.merge', () => {
        it('tests can check database structure', 0, () => {
            const db = getTestDb();
            assertDbEquals(db, getTestDbStructure());
        });

        // self-merge

        it('merges itself', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            db.merge(remote);
            assertDbEquals(db, getTestDbStructure());
        });

        // errors

        it('generates merge error when merging db without root', 0,() => {
            const db = getTestDb(),
                remote = kdbxweb.Kdbx.create(
                    new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('demo')),
                    'demo'
                );
            remote.groups = [];
            expects(() => {
                db.merge(remote);
            }).assertThrowError((e:Error) => {
                expects(e).assertInstanceOf(kdbxweb.KdbxError);
                expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidState);
                expect(e.message).assertContain('empty default group');
            });
        });

        it('generates merge error when merging another db', 0,() => {
            const db = getTestDb(),
                remote = kdbxweb.Kdbx.create(
                    new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('demo')),
                    'demo'
                );
            expects(() => {
                db.merge(remote);
            }).assertThrowError((e:Error) => {
                expects(e).assertInstanceOf(kdbxweb.KdbxError);
                expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.MergeError);
                expect(e.message).assertContain('default group is different');
            });
        });

        // deletedObjects

        it('merges deleted objects', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const delObj = new kdbxweb.KdbxDeletedObject();
            delObj.uuid = id.eDel1;
            delObj.deletionTime = dt.upd2;
            remote.deletedObjects.splice(0, 1);
            remote.deletedObjects.push(delObj);
            db.merge(remote);
            const del:Record<string, Date | undefined>  = {};
            del[id.eDel.id]=dt.upd1;
            del[id.eDel1.id]=dt.upd2;
            assertDbEquals(db, { del });
        });

        // meta

        it('merges metadata when remote is later', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.meta.name = 'name1';
            remote.meta.nameChanged = dt.upd2;
            remote.meta.desc = 'desc1';
            remote.meta.descChanged = dt.upd2;
            remote.meta.defaultUser = 'user1';
            remote.meta.defaultUserChanged = dt.upd2;
            remote.meta.mntncHistoryDays = 100;
            remote.meta.settingsChanged = dt.upd2;
            remote.meta.keyChanged = dt.upd2;
            remote.meta.keyChangeRec = 1000;
            remote.meta.keyChangeForce = 2000;
            remote.meta.recycleBinEnabled = false;
            remote.meta.recycleBinUuid = id.g1;
            remote.meta.recycleBinChanged = dt.upd2;
            remote.meta.entryTemplatesGroup = id.g2;
            remote.meta.entryTemplatesGroupChanged = dt.upd2;
            remote.meta.historyMaxItems = 100;
            remote.meta.historyMaxSize = 100000000;
            remote.meta.color = '#ff0000';
            db.merge(remote);
            assertDbEquals(db, {
                meta: {
                    name: 'name1',
                    nameChanged: dt.upd2,
                    desc: 'desc1',
                    descChanged: dt.upd2,
                    defaultUser: 'user1',
                    defaultUserChanged: dt.upd2,
                    mntncHistoryDays: 100,
                    settingsChanged: dt.upd2,
                    keyChanged: dt.upd2,
                    keyChangeRec: 1000,
                    keyChangeForce: 2000,
                    recycleBinEnabled: false,
                    recycleBinUuid: id.g1,
                    recycleBinChanged: dt.upd2,
                    entryTemplatesGroup: id.g2,
                    entryTemplatesGroupChanged: dt.upd2,
                    historyMaxItems: 100,
                    historyMaxSize: 100000000,
                    color: '#ff0000'
                } as kdbxweb.KdbxMeta
            });
        });

        it('merges metadata when local is later', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            db.meta.name = 'name1';
            db.meta.nameChanged = dt.upd2;
            db.meta.desc = 'desc1';
            db.meta.descChanged = dt.upd2;
            db.meta.defaultUser = 'user1';
            db.meta.defaultUserChanged = dt.upd2;
            db.meta.mntncHistoryDays = 100;
            db.meta.keyChanged = dt.upd2;
            db.meta.keyChangeRec = 1000;
            db.meta.keyChangeForce = 2000;
            db.meta.recycleBinEnabled = false;
            db.meta.recycleBinUuid = id.g1;
            db.meta.recycleBinChanged = dt.upd2;
            db.meta.entryTemplatesGroup = id.g2;
            db.meta.entryTemplatesGroupChanged = dt.upd2;
            db.meta.historyMaxItems = 100;
            db.meta.historyMaxSize = 100000000;
            db.meta.color = '#ff0000';
            db.merge(remote);
            assertDbEquals(db, {
                meta: {
                    name: 'name1',
                    nameChanged: dt.upd2,
                    desc: 'desc1',
                    descChanged: dt.upd2,
                    defaultUser: 'user1',
                    defaultUserChanged: dt.upd2,
                    mntncHistoryDays: 100,
                    keyChanged: dt.upd2,
                    keyChangeRec: 1000,
                    keyChangeForce: 2000,
                    recycleBinEnabled: false,
                    recycleBinUuid: id.g1,
                    recycleBinChanged: dt.upd2,
                    entryTemplatesGroup: id.g2,
                    entryTemplatesGroupChanged: dt.upd2,
                    historyMaxItems: 100,
                    historyMaxSize: 100000000,
                    color: '#ff0000'
                } as kdbxweb.KdbxMeta
            } );
        });

        it('merges binaries', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const binaries = new kdbxweb.KdbxBinaries();
            binaries.addWithHash({ hash: id.bin1.id, value: bin.bin1 });
            binaries.addWithHash({ hash: id.bin2.id, value: bin.bin2 });
            binaries.addWithHash({ hash: id.bin3.id, value: bin.bin3 });

            db.groups[0].entries[0].binaries.set(id.bin2.id, {
                hash: id.bin2.id,
                value: bin.bin2
            });
            db.groups[0].entries[0].history[0].binaries.set(id.bin2.id, {
                hash: id.bin3.id,
                value: bin.bin3
            });
            db.binaries.addWithHash({
                hash: id.bin2.id,
                value: bin.bin2
            });
            remote.binaries.addWithHash({
                hash: id.bin3.id,
                value: bin.bin3
            });
            db.merge(remote);
            assertDbEquals(db, { binaries });
        });

        it('merges custom icons', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const d1 = new Date();
            d1.setSeconds(-1);
            const d2 = new Date();
            const customIcons = new Map<string, kdbxweb.KdbxCustomIcon>([
                [id.icon2.id, { data: bin.icon2 }],
                [id.bin1.id, { data: bin.bin1 }],
                [id.bin3.id, { data: bin.bin3, name: 'i3', lastModified: d1 }],
                [id.bin4.id, { data: bin.bin4, name: 'i4', lastModified: d2 }],
                [id.bin2.id, { data: bin.bin2 }]
            ]);
            db.meta.customIcons.set(id.bin1.id, { data: bin.bin1 });
            db.meta.customIcons.set(id.bin3.id, { data: bin.bin3, name: 'i3', lastModified: d1 });
            db.meta.customIcons.set(id.bin4.id, { data: bin.bin3, name: 'i3', lastModified: d1 });
            db.groups[0].customIcon = id.bin1;
            db.groups[0].times.update();
            db.groups[0].groups[0].customIcon = id.bin3;
            db.groups[0].groups[0].times.update();
            db.groups[0].groups[1].customIcon = id.bin4;
            db.groups[0].groups[1].times.update();
            remote.meta.customIcons.set(id.bin2.id, { data: bin.bin2 });
            remote.meta.customIcons.set(id.bin4.id, { data: bin.bin4, name: 'i4', lastModified: d2 });
            remote.groups[0].entries[0].customIcon = id.bin2;
            remote.groups[0].entries[0].times.update();
            db.groups[0].groups[1].customIcon = id.bin4;
            db.groups[0].groups[1].times.update();
            db.merge(remote);
            assertDbEquals(db, { meta: { customIcons } as kdbxweb.KdbxMeta});
        });

        it('merges custom data', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();

            const dOld = new Date();
            dOld.setSeconds(-1);
            const dNew = new Date();

            const customData = new Map<string, kdbxweb.KdbxCustomDataItem>([
                ['cd1', { value: 'data1' }],
                ['dLocal', { value: 'local' }],
                ['1', { value: 'remoteNew', lastModified: dNew }],
                ['2', { value: 'new', lastModified: dNew }],
                ['dRemote', { value: 'remote' }]
            ]);
            db.meta.customData.set('dLocal', { value: 'local' });
            db.meta.customData.set('1', { value: 'old', lastModified: dOld });
            db.meta.customData.set('2', { value: 'new', lastModified: dNew });
            remote.meta.customData.set('dRemote', { value: 'remote' });
            remote.meta.customData.set('1', { value: 'remoteNew', lastModified: dNew });
            remote.meta.customData.set('2', { value: 'remoteOld', lastModified: dOld });
            db.merge(remote);
            assertDbEquals(db, { meta: { customData } as kdbxweb.KdbxMeta });
        });

        // groups: remote

        it('changes remote group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const grp = remote.getDefaultGroup();
            grp.name = 'root1';
            grp.notes = 'notes1';
            grp.icon = 1;
            grp.customIcon = id.icon2;
            grp.times.lastModTime = dt.upd2;
            grp.expanded = true;
            grp.defaultAutoTypeSeq = 'seq1';
            grp.enableAutoType = false;
            grp.enableSearching = false;
            grp.lastTopVisibleEntry = id.eDel1;
            grp.groups[1].customIcon = id.icon1;
            grp.groups[1].times.lastModTime = dt.upd2;
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.name = 'root1';
            exp.root.notes = 'notes1';
            exp.root.icon = 1;
            exp.root.customIcon = id.icon2;
            exp.root.modified = dt.upd2;
            exp.root.expanded = true;
            exp.root.defaultAutoTypeSeq = 'seq1';
            exp.root.enableAutoType = false;
            exp.root.enableSearching = false;
            exp.root.lastTopVisibleEntry = id.eDel1;
            assertDbEquals(db, exp);
        });

        it('adds new remote group to root', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const group = remote.createGroup(remote.getDefaultGroup(), 'newgrp');
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups.push({ uuid: group.uuid, name: group.name });
            assertDbEquals(db, exp);
        });

        it('adds new remote group to deep group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const group = remote.createGroup(remote.getDefaultGroup().groups[1].groups[0], 'newgrp');
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups[1].groups[0].groups.push({ uuid: group.uuid, name: group.name });
            assertDbEquals(db, exp);
        });

        it('deletes remote group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.move(remote.getDefaultGroup().groups[1].groups[0], null);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.root.groups[1].groups.splice(0, 1);
            assertDbEquals(db, exp);
        });

        it('moves remote group to root', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.move(remote.getDefaultGroup().groups[1].groups[0], remote.getDefaultGroup());
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups.push(exp.root.groups[1].groups[0]);
            exp.root.groups[1].groups.splice(0, 1);
            assertDbEquals(db, exp);
        });

        it('moves remote group to deep group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.move(
                remote.getDefaultGroup().groups[1].groups[0],
                remote.getDefaultGroup().groups[3]
            );
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups[3].groups.push(exp.root.groups[1].groups[0]);
            exp.root.groups[1].groups.splice(0, 1);
            assertDbEquals(db, exp);
        });

        // groups: local

        it('changes local group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const grp = db.getDefaultGroup();
            grp.name = 'root1';
            grp.notes = 'notes1';
            grp.icon = 1;
            grp.customIcon = id.icon2;
            grp.times.lastModTime = dt.upd2;
            grp.expanded = true;
            grp.defaultAutoTypeSeq = 'seq1';
            grp.enableAutoType = false;
            grp.enableSearching = false;
            grp.lastTopVisibleEntry = id.eDel1;
            grp.groups[1].customIcon = id.icon1;
            grp.groups[1].times.lastModTime = dt.upd2;
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.name = 'root1';
            exp.root.notes = 'notes1';
            exp.root.icon = 1;
            exp.root.customIcon = id.icon2;
            exp.root.modified = dt.upd2;
            exp.root.expanded = true;
            exp.root.defaultAutoTypeSeq = 'seq1';
            exp.root.enableAutoType = false;
            exp.root.enableSearching = false;
            exp.root.lastTopVisibleEntry = id.eDel1;
            assertDbEquals(db, exp);
        });

        it('adds new local group to root', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const group = db.createGroup(db.getDefaultGroup(), 'newgrp');
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups.push({ uuid: group.uuid, name: group.name });
            assertDbEquals(db, exp);
        });

        it('adds new local group to deep group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const group = db.createGroup(db.getDefaultGroup().groups[1].groups[0], 'newgrp');
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups[1].groups[0].groups.push({ uuid: group.uuid, name: group.name });
            assertDbEquals(db, exp);
        });

        it('deletes local group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.move(db.getDefaultGroup().groups[1].groups[0], null);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.root.groups[1].groups.splice(0, 1);
            assertDbEquals(db, exp);
        });

        it('moves local group to root', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            db.move(db.getDefaultGroup().groups[1].groups[0], db.getDefaultGroup());
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups.push(exp.root.groups[1].groups[0]);
            exp.root.groups[1].groups.splice(0, 1);
            assertDbEquals(db, exp);
        });

        it('moves local group to deep group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            db.move(db.getDefaultGroup().groups[1].groups[0], db.getDefaultGroup().groups[3]);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups[3].groups.push(exp.root.groups[1].groups[0]);
            exp.root.groups[1].groups.splice(0, 1);
            assertDbEquals(db, exp);
        });

        // groups: local+remote

        it('deletes group moved to subgroup of locally deleted group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.move(
                remote.getDefaultGroup().groups[1].groups[0],
                remote.getDefaultGroup().groups[3].groups[1]
            );
            tick();
            db.move(db.getDefaultGroup().groups[3], null);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.root.groups[1].groups.splice(0, 1);
            exp.root.groups.splice(3, 1);
            assertDbEquals(db, exp);
        });

        it('deletes group moved to subgroup of remotely deleted group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            db.move(db.getDefaultGroup().groups[1].groups[0], db.getDefaultGroup().groups[3].groups[1]);
            tick();
            remote.move(remote.getDefaultGroup().groups[3], null);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.root.groups[1].groups.splice(0, 1);
            exp.root.groups.splice(3, 1);
            assertDbEquals(db, exp);
        });

        it('deletes group moved out of subgroup of locally deleted group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.move(
                remote.getDefaultGroup().groups[1].groups[0],
                remote.getDefaultGroup().groups[3].groups[1]
            );
            tick();
            db.move(db.getDefaultGroup().groups[1], null);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.root.groups.splice(1, 1);
            assertDbEquals(db, exp);
        });

        it('deletes group moved out of subgroup of remotely deleted group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            db.move(db.getDefaultGroup().groups[1].groups[0], db.getDefaultGroup().groups[3].groups[1]);
            tick();
            remote.move(remote.getDefaultGroup().groups[1], null);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.root.groups.splice(1, 1);
            assertDbEquals(db, exp);
        });

        it('moves group moved to locally moved group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.move(
                remote.getDefaultGroup().groups[1].groups[0],
                remote.getDefaultGroup().groups[3].groups[0]
            );
            tick();
            db.move(db.getDefaultGroup().groups[3], db.getDefaultGroup().groups[2]);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.root.groups[3].groups[0].groups.push(exp.root.groups[1].groups[0]);
            exp.root.groups[1].groups.splice(0, 1);
            exp.root.groups[2].groups.push(exp.root.groups[3]);
            exp.root.groups.splice(3, 1);
            assertDbEquals(db, exp);
        });

        it('moves group moved to remotely moved group', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.move(remote.getDefaultGroup().groups[3], remote.getDefaultGroup().groups[2]);
            tick();
            db.move(db.getDefaultGroup().groups[1].groups[0], db.getDefaultGroup().groups[3].groups[0]);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.root.groups[3].groups[0].groups.push(exp.root.groups[1].groups[0]);
            exp.root.groups[1].groups.splice(0, 1);
            exp.root.groups[2].groups.push(exp.root.groups[3]);
            exp.root.groups.splice(3, 1);
            assertDbEquals(db, exp);
        });

        // groups: reorder

        it('moves group back', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();

            let group4 = db.createGroup(db.getDefaultGroup(), 'g4');
            group4.uuid = id.g4;
            group4.times.lastModTime = group4.times.locationChanged = dt.upd1;
            let group5 = db.createGroup(db.getDefaultGroup(), 'g5');
            group5.uuid = id.g5;
            group5.times.lastModTime = group5.times.locationChanged = dt.upd1;
            db.getDefaultGroup().groups.splice(
                1,
                2,
                db.getDefaultGroup().groups[2],
                db.getDefaultGroup().groups[1]
            );
            db.getDefaultGroup().groups[1].times.lastModTime = dt.upd3;

            group5 = remote.createGroup(remote.getDefaultGroup(), 'g5');
            group5.uuid = id.g5;
            group5.times.lastModTime = group5.times.locationChanged = dt.upd2;
            group4 = remote.createGroup(remote.getDefaultGroup(), 'g4');
            group4.uuid = id.g4;
            group4.times.lastModTime = group4.times.locationChanged = dt.upd1;

            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups.splice(1, 2, exp.root.groups[2], exp.root.groups[1]);
            exp.root.groups[1].modified = dt.upd3;
            exp.root.groups.push({ uuid: id.g5, name: 'g5' });
            exp.root.groups.push({ uuid: id.g4, name: 'g4' });
            assertDbEquals(db, exp);
        });

        it('moves group forward', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();

            let group4 = db.createGroup(db.getDefaultGroup(), 'g4');
            group4.uuid = id.g4;
            group4.times.lastModTime = group4.times.locationChanged = dt.upd1;
            let group5 = db.createGroup(db.getDefaultGroup(), 'g5');
            group5.uuid = id.g5;
            group5.times.lastModTime = group5.times.locationChanged = dt.upd1;
            db.getDefaultGroup().groups.splice(
                1,
                2,
                db.getDefaultGroup().groups[2],
                db.getDefaultGroup().groups[1]
            );
            db.getDefaultGroup().groups[2].times.lastModTime = dt.upd3;

            group5 = remote.createGroup(remote.getDefaultGroup(), 'g5');
            group5.uuid = id.g5;
            group5.times.lastModTime = group5.times.locationChanged = dt.upd1;
            group4 = remote.createGroup(remote.getDefaultGroup(), 'g4');
            group4.uuid = id.g4;
            group4.times.lastModTime = group4.times.locationChanged = dt.upd2;

            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups.splice(1, 2, exp.root.groups[2], exp.root.groups[1]);
            exp.root.groups[2].modified = dt.upd3;
            exp.root.groups.push({ uuid: id.g5, name: 'g5' });
            exp.root.groups.push({ uuid: id.g4, name: 'g4' });
            assertDbEquals(db, exp);
        });

        it('inserts group at start', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();

            const group4 = remote.createGroup(remote.getDefaultGroup(), 'g4');
            group4.uuid = id.g4;
            group4.times.lastModTime = group4.times.locationChanged = dt.upd2;
            remote.getDefaultGroup().groups.splice(remote.getDefaultGroup().groups.length - 1, 1);
            remote.getDefaultGroup().groups.unshift(group4);

            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.groups.unshift({ uuid: id.g4, name: 'g4' });
            assertDbEquals(db, exp);
        });

        // entries

        it('adds remote entry', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const entry = remote.createEntry(remote.getDefaultGroup());
            entry.fields.set('added', 'field');
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries.push({ fields: entry.fields });
            assertDbEquals(db, exp);
        });

        it('deletes remote entry', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.move(remote.getDefaultGroup().entries[0], null);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.meta.customIcons = undefined;
            exp.root.entries.splice(0, 1);
            exp.binaries = new kdbxweb.KdbxBinaries();
            assertDbEquals(db, exp);
        });

        it('deletes local entry', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            db.move(db.getDefaultGroup().entries[0], null);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.meta.customIcons = undefined;
            exp.root.entries.splice(0, 1);
            exp.binaries = new kdbxweb.KdbxBinaries();
            assertDbEquals(db, exp);
        });

        it('moves remote entry', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.move(remote.getDefaultGroup().entries[0], remote.getDefaultGroup().groups[1]);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.meta.customIcons = undefined;
            exp.root.groups[1].entries.push(exp.root.entries[0]);
            exp.root.entries.splice(0, 1);
            assertDbEquals(db, exp);
        });

        it('moves local entry', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            db.move(db.getDefaultGroup().entries[0], db.getDefaultGroup().groups[1]);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.del = undefined;
            exp.meta.customIcons = undefined;
            exp.root.groups[1].entries.push(exp.root.entries[0]);
            exp.root.entries.splice(0, 1);
            assertDbEquals(db, exp);
        });

        it('changes remote entry', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const ab = new ArrayBuffer(0);
            const prVal = kdbxweb.ProtectedValue.fromString('secret');
            const entry = remote.getDefaultGroup().entries[0];
            entry.icon = 21;
            entry.fgColor = '#aa0000';
            entry.bgColor = '#00aa00';
            entry.overrideUrl = '1234';
            entry.tags = ['tags1'];
            entry.times.lastModTime = dt.upd4;
            entry.fields = new Map<string, kdbxweb.KdbxEntryField>([
                ['Password', 'pass'],
                ['Another', 'field'],
                ['Protected', prVal]
            ]);
            entry.binaries.set('bin1', { hash: id.bin1.id, value: bin.bin1 });
            entry.binaries.set('bin2', bin.bin2);
            entry.binaries.set('ab', ab);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries[0].icon = 21;
            exp.root.entries[0].fgColor = '#aa0000';
            exp.root.entries[0].bgColor = '#00aa00';
            exp.root.entries[0].overrideUrl = '1234';
            exp.root.entries[0].tags = ['tags1'];
            exp.root.entries[0].modified = dt.upd4;
            exp.root.entries[0].fields = new Map<string, kdbxweb.KdbxEntryField>([
                ['Password', 'pass'],
                ['Another', 'field'],
                ['Protected', prVal]
            ]);
            exp.root.entries[0].binaries.set('bin1', { hash: id.bin1.id, value: bin.bin1 });
            exp.root.entries[0].binaries.set('bin2', bin.bin2);
            exp.root.entries[0].binaries.set('ab', ab);
            exp.root.entries[0].history.push({ modified: dt.upd3, tags: ['tags'] });
            assertDbEquals(db, exp);
        });

        it('ignores remote entry with same date', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const ab = new ArrayBuffer(0);
            const prVal = kdbxweb.ProtectedValue.fromString('secret');
            const entry = remote.getDefaultGroup().entries[0];
            entry.icon = 21;
            entry.fgColor = '#aa0000';
            entry.bgColor = '#00aa00';
            entry.overrideUrl = '1234';
            entry.tags = ['tags1'];
            entry.fields = new Map<string, kdbxweb.KdbxEntryField>([
                ['Password', 'pass'],
                ['Another', 'field'],
                ['Protected', prVal]
            ]);
            entry.binaries.set('bin1', { hash: id.bin1.id, value: bin.bin1 });
            entry.binaries.set('bin2', bin.bin2);
            entry.binaries.set('ab', ab);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            assertDbEquals(db, exp);
        });

        it('changes local entry', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const ab = new ArrayBuffer(0);
            const prVal = kdbxweb.ProtectedValue.fromString('secret');
            const entry = db.getDefaultGroup().entries[0];
            entry.pushHistory();
            entry.icon = 21;
            entry.fgColor = '#aa0000';
            entry.bgColor = '#00aa00';
            entry.overrideUrl = '1234';
            entry.tags = ['tags1'];
            entry.times.lastModTime = dt.upd4;
            entry.fields = new Map<string, kdbxweb.KdbxEntryField>([
                ['Password', 'pass'],
                ['Another', 'field'],
                ['Protected', prVal]
            ]);
            entry.binaries.set('bin1', { hash: id.bin1.id, value: bin.bin1 });
            entry.binaries.set('bin2', bin.bin2);
            entry.binaries.set('ab', ab);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries[0].icon = 21;
            exp.root.entries[0].fgColor = '#aa0000';
            exp.root.entries[0].bgColor = '#00aa00';
            exp.root.entries[0].overrideUrl = '1234';
            exp.root.entries[0].tags = ['tags1'];
            exp.root.entries[0].modified = dt.upd4;
            exp.root.entries[0].fields = new Map<string, kdbxweb.KdbxEntryField>([
                ['Password', 'pass'],
                ['Another', 'field'],
                ['Protected', prVal]
            ]);
            exp.root.entries[0].binaries.set('bin1', { hash: id.bin1.id, value: bin.bin1 });
            exp.root.entries[0].binaries.set('bin2', bin.bin2);
            exp.root.entries[0].binaries.set('ab', ab);
            exp.root.entries[0].history.push({ modified: dt.upd3, tags: ['tags'] });
            assertDbEquals(db, exp);
        });

        it('deletes history state remotely', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.getDefaultGroup().entries[0].removeHistory(0);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries[0].history.splice(0, 1);
            assertDbEquals(db, exp);
        });

        it('deletes history state locally', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            db.getDefaultGroup().entries[0].removeHistory(0);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries[0].history.splice(0, 1);
            assertDbEquals(db, exp);
        });

        it('deletes all history states remotely', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            remote.getDefaultGroup().entries[0].removeHistory(0, 5);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries[0].history = [];
            assertDbEquals(db, exp);
        });

        it('deletes all history states locally', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            db.getDefaultGroup().entries[0].removeHistory(0, 5);
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries[0].history = [];
            assertDbEquals(db, exp);
        });

        it('adds past history state remotely', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const remoteEntry = remote.getDefaultGroup().entries[0];
            const entry = db.getDefaultGroup().entries[0];
            remoteEntry.times.lastModTime = dt.upd3;
            entry.times.lastModTime = dt.upd4;
            remoteEntry.pushHistory();
            remoteEntry.times.lastModTime = dt.upd4;
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries[0].modified = dt.upd4;
            exp.root.entries[0].history.push({ modified: dt.upd3, tags: ['tags'] });
            assertDbEquals(db, exp);
        });

        it('adds future history state remotely and converts current state into history', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const remoteEntry = remote.getDefaultGroup().entries[0];
            const entry = db.getDefaultGroup().entries[0];
            remoteEntry.times.lastModTime = dt.upd4;
            remoteEntry.tags = ['t4'];
            remoteEntry.pushHistory();
            remoteEntry.times.lastModTime = dt.upd5;
            remoteEntry.tags = ['tRemote'];
            entry.tags = ['tLocal'];
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries[0].modified = dt.upd5;
            exp.root.entries[0].tags = ['tRemote'];
            exp.root.entries[0].history.push({ modified: dt.upd3, tags: ['tLocal'] });
            exp.root.entries[0].history.push({ modified: dt.upd4, tags: ['t4'] });
            assertDbEquals(db, exp);
        });

        it('adds history state locally and converts remote state into history', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const remoteEntry = remote.getDefaultGroup().entries[0];
            const entry = db.getDefaultGroup().entries[0];
            remoteEntry.times.lastModTime = dt.upd5;
            remoteEntry.tags = ['tRemote'];
            entry.tags = ['t4'];
            entry.times.lastModTime = dt.upd4;
            entry.pushHistory();
            entry.tags = ['tLocal'];
            entry.times.lastModTime = dt.upd6;
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries[0].modified = dt.upd6;
            exp.root.entries[0].tags = ['tLocal'];
            exp.root.entries[0].history.push({ modified: dt.upd4, tags: ['t4'] });
            exp.root.entries[0].history.push({ modified: dt.upd5, tags: ['tRemote'] });
            assertDbEquals(db, exp);
        });

        it('can merge with old entry state without state deletions', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();
            const entry = db.getDefaultGroup().entries[0];
            entry.times.lastModTime = dt.upd4;
            entry.tags = ['t4'];
            entry.pushHistory();
            entry.tags = ['tLocal'];
            entry.times.lastModTime = dt.upd5;
            entry._editState = undefined;
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            exp.root.entries[0].tags = ['tLocal'];
            exp.root.entries[0].modified = dt.upd5;
            exp.root.entries[0].history.push({ modified: dt.upd3, tags: ['tags'] });
            exp.root.entries[0].history.push({ modified: dt.upd4, tags: ['t4'] });
            assertDbEquals(db, exp);
        });

        // edit state management

        it('saves and restores edit state', 0,() => {
            const db = getTestDb(),
                remote = getTestDb();

            db.getDefaultGroup().entries[0].removeHistory(0);
            db.meta.historyMaxItems = 500;

            db.removeLocalEditState();
            db.merge(remote);
            const exp:ESObject = getTestDbStructure();
            assertDbEquals(db, exp);

            db.getDefaultGroup().entries[0].removeHistory(0);
            db.meta.historyMaxItems = 500;
            let editState = db.getLocalEditState();
            editState = JSON.parse(JSON.stringify(editState));
            db.removeLocalEditState();
            db.setLocalEditState(editState);
            db.merge(remote);

            exp.meta.historyMaxItems = 500;
            exp.root.entries[0].history.splice(0, 1);
        });
    });
}

function getTestDbStructure(): ESObject {
    // @ark-ignore
    const exp:ESObject = {
        meta: {
            name: 'name',
            nameChanged: dt.created,
            desc: 'desc',
            descChanged: dt.created,
            defaultUser: 'user',
            defaultUserChanged: dt.created,
            mntncHistoryDays: 10,
            keyChanged: dt.created,
            keyChangeRec: 100,
            keyChangeForce: 200,
            recycleBinEnabled: true,
            recycleBinUuid: id.trash,
            recycleBinChanged: dt.created,
            entryTemplatesGroup: id.tpl,
            entryTemplatesGroupChanged: dt.created,
            historyMaxItems: 10,
            historyMaxSize: 10000,
            customIcons: new Map<string, kdbxweb.KdbxCustomIcon>(),
            customData: new Map<string, kdbxweb.KdbxCustomDataItem>([
                ['cd1', { value: 'data1' }]
            ])
        } as ESObject,
        binaries: new kdbxweb.KdbxBinaries(),
        del: {} as Record<string, Date | undefined>,
        root: {
            uuid: id.gRoot,
            name: 'root',
            notes: 'notes',
            icon: 1,
            customIcon: id.icon1,
            modified: dt.upd1,
            expanded: false,
            defaultAutoTypeSeq: 'seq',
            enableAutoType: true,
            enableSearching: true,
            lastTopVisibleEntry: null,
            groups: [
                {
                    uuid: id.trash,
                    name: 'trash',
                    groups: [],
                    entries: []
                } as ESObject ,
                {
                    uuid: id.g1,
                    name: 'g1',
                    entries: [],
                    groups: [
                        {
                            uuid: id.g11,
                            name: 'g11',
                            groups: [
                                {
                                    uuid: id.g111,
                                    name: 'g111',
                                    groups: [],
                                    entries: []
                                } as ESObject ,
                                {
                                    uuid: id.g112,
                                    name: 'g112',
                                    groups: [],
                                    entries: []
                                } as ESObject
                            ] as ESObject[]
                        },
                        {
                            uuid: id.g12,
                            name: 'g12',
                            groups: [],
                            entries: []
                        } as ESObject
                    ] as ESObject[]
                },
                {
                    uuid: id.g2,
                    name: 'g2',
                    groups: [],
                    entries: []
                } as ESObject,
                {
                    uuid: id.g3,
                    name: 'g3',
                    groups: [
                        {
                            uuid: id.g31,
                            name: 'g31',
                            groups: [],
                            entries: []
                        } as ESObject
                    ] as ESObject[]
                }
            ] as ESObject [],
            entries: [
                {
                    uuid: id.er1,
                    icon: 2,
                    customIcon: id.icon2,
                    fgColor: '#ff0000',
                    bgColor: '#00ff00',
                    overrideUrl: '123',
                    tags: ['tags'],
                    modified: dt.upd3,
                    fields: new Map([
                        ['Title', 'er1'],
                        ['Password', 'pass']
                    ]),
                    binaries: new Map([['bin1', { hash: id.bin1.id, value: bin.bin1 } as ESObject]]),
                    history: [
                        {
                            modified: dt.upd1,
                            tags: ['tags1']
                        },
                        {
                            modified: dt.upd2,
                            tags: ['tags2']
                        }
                    ] as ESObject[]
                }
            ] as ESObject[]
        } as ESObject
    };
    exp.del[id.eDel.id] = dt.upd1;
    exp.binaries.addWithHash({ hash: id.bin1.id, value: bin.bin1 });
    exp.meta.customIcons.set(id.icon1.id, { data: bin.icon1 });
    exp.meta.customIcons.set(id.icon2.id, { data: bin.icon2 });
    return exp;
}

function getTestDb() {
    const cred = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('demo'));
    const db = kdbxweb.Kdbx.create(cred, 'demo');

    db.meta._name = 'name';
    db.meta.nameChanged = dt.created;
    db.meta._desc = 'desc';
    db.meta.descChanged = dt.created;
    db.meta._defaultUser = 'user';
    db.meta.defaultUserChanged = dt.created;
    db.meta._mntncHistoryDays = 10;
    db.meta.settingsChanged = dt.created;
    db.meta.keyChanged = dt.created;
    db.meta._keyChangeRec = 100;
    db.meta._keyChangeForce = 200;
    db.meta._recycleBinEnabled = true;
    db.meta._recycleBinUuid = id.trash;
    db.meta.recycleBinChanged = dt.created;
    db.meta._entryTemplatesGroup = id.tpl;
    db.meta.entryTemplatesGroupChanged = dt.created;
    db.meta._historyMaxItems = 10;
    db.meta._historyMaxSize = 10000;
    db.meta.customIcons.set(id.icon1.id, { data: bin.icon1 });
    db.meta.customIcons.set(id.icon2.id, { data: bin.icon2 });
    db.meta.customData.set('cd1', { value: 'data1' });
    db.meta._editState = undefined;
    db.binaries.addWithHash({ hash: id.bin1.id, value: bin.bin1 });

    const root = db.getDefaultGroup();
    root.uuid = id.gRoot;
    root.name = 'root';
    root.notes = 'notes';
    root.icon = 1;
    root.customIcon = id.icon1;
    root.times.lastModTime = dt.upd1;
    root.times.locationChanged = dt.upd1;
    root.expanded = false;
    root.defaultAutoTypeSeq = 'seq';
    root.enableAutoType = true;
    root.enableSearching = true;
    root.lastTopVisibleEntry = undefined;

    const recycleBin = root.groups[0];
    recycleBin.uuid = id.trash;
    recycleBin.name = 'trash';
    recycleBin.times.lastModTime = dt.upd1;
    recycleBin.times.locationChanged = dt.upd1;

    let entry = db.createEntry(root);
    entry.uuid = id.eDel;
    db.move(entry, undefined);
    db.deletedObjects[0].deletionTime = dt.upd1;

    entry = db.createEntry(root);
    entry.uuid = id.er1;
    entry.icon = 2;
    entry.customIcon = id.icon2;
    entry.fgColor = '#ff0000';
    entry.bgColor = '#00ff00';
    entry.overrideUrl = '123';
    entry.tags = ['tags1'];
    entry.times.lastModTime = dt.upd3;
    entry.times.locationChanged = dt.upd1;
    entry.fields = new Map([
        ['Title', 'er1'],
        ['Password', 'pass']
    ]);
    entry.binaries.set('bin1', { hash: id.bin1.id, value: bin.bin1 });
    entry.pushHistory();
    entry.tags = ['tags2'];
    entry.history[0].times.lastModTime = dt.upd1;
    entry.pushHistory();
    entry.tags = ['tags'];
    entry.history[1].times.lastModTime = dt.upd2;
    entry._editState = undefined;

    const group1 = db.createGroup(root, 'g1');
    group1.uuid = id.g1;
    group1.times.lastModTime = group1.times.locationChanged = dt.upd1;
    const group11 = db.createGroup(group1, 'g11');
    group11.uuid = id.g11;
    group11.times.lastModTime = group11.times.locationChanged = dt.upd1;
    const group111 = db.createGroup(group11, 'g111');
    group111.uuid = id.g111;
    group111.times.lastModTime = group111.times.locationChanged = dt.upd1;
    const group112 = db.createGroup(group11, 'g112');
    group112.uuid = id.g112;
    group112.times.lastModTime = group112.times.locationChanged = dt.upd1;
    const group12 = db.createGroup(group1, 'g12');
    group12.uuid = id.g12;
    group12.times.lastModTime = group12.times.locationChanged = dt.upd1;
    const group2 = db.createGroup(root, 'g2');
    group2.uuid = id.g2;
    group2.times.lastModTime = group2.times.locationChanged = dt.upd1;
    const group3 = db.createGroup(root, 'g3');
    group3.uuid = id.g3;
    group3.times.lastModTime = group3.times.locationChanged = dt.upd1;
    const group31 = db.createGroup(group3, 'g31');
    group31.uuid = id.g31;
    group31.times.lastModTime = group31.times.locationChanged = dt.upd1;

    return db;
}

function assertDbEquals(db: kdbxweb.Kdbx, exp: ESObject) {
    if (exp.meta) {
        if (exp.meta.name) {
            expect(db.meta.name).assertDeepEquals(exp.meta.name);
        }
        if (exp.meta.nameChanged) {
            expect(db.meta.nameChanged).assertDeepEquals(exp.meta.nameChanged);
        }
        if (exp.meta.desc) {
            expect(db.meta.desc).assertDeepEquals(exp.meta.desc);
        }
        if (exp.meta.descChanged) {
            expect(db.meta.descChanged).assertDeepEquals(exp.meta.descChanged);
        }
        if (exp.meta.defaultUser) {
            expect(db.meta.defaultUser).assertDeepEquals(exp.meta.defaultUser);
        }
        if (exp.meta.defaultUserChanged) {
            expect(db.meta.defaultUserChanged).assertDeepEquals(exp.meta.defaultUserChanged);
        }
        if (exp.meta.mntncHistoryDays) {
            expect(db.meta.mntncHistoryDays).assertDeepEquals(exp.meta.mntncHistoryDays);
        }
        if (exp.meta.settingsChanged) {
            expect(db.meta.settingsChanged).assertDeepEquals(exp.meta.settingsChanged);
        }
        if (exp.meta.keyChanged) {
            expect(db.meta.keyChanged).assertDeepEquals(exp.meta.keyChanged);
        }
        if (exp.meta.keyChangeRec) {
            expect(db.meta.keyChangeRec).assertDeepEquals(exp.meta.keyChangeRec);
        }
        if (exp.meta.keyChangeForce) {
            expect(db.meta.keyChangeForce).assertDeepEquals(exp.meta.keyChangeForce);
        }
        if (exp.meta.recycleBinEnabled) {
            expect(db.meta.recycleBinEnabled).assertDeepEquals(exp.meta.recycleBinEnabled);
        }
        if (exp.meta.recycleBinUuid) {
            expect(db.meta.recycleBinUuid).assertDeepEquals(exp.meta.recycleBinUuid);
        }
        if (exp.meta.recycleBinChanged) {
            expect(db.meta.recycleBinChanged).assertDeepEquals(exp.meta.recycleBinChanged);
        }
        if (exp.meta.entryTemplatesGroup) {
            expect(db.meta.entryTemplatesGroup).assertDeepEquals(exp.meta.entryTemplatesGroup);
        }
        if (exp.meta.entryTemplatesGroupChanged) {
            expect(db.meta.entryTemplatesGroupChanged).assertDeepEquals(
                exp.meta.entryTemplatesGroupChanged
            );
        }
        if (exp.meta.historyMaxItems) {
            expect(db.meta.historyMaxItems).assertDeepEquals(exp.meta.historyMaxItems);
        }
        if (exp.meta.historyMaxSize) {
            expect(db.meta.historyMaxSize).assertDeepEquals(exp.meta.historyMaxSize);
        }
        if (exp.meta.customData) {
            expect(Array.from(db.meta.customData.entries())).assertDeepEquals(
                Array.from<[string, kdbxweb.KdbxCustomDataItem]>(exp.meta.customData.entries())
            );
        }
        if (exp.meta.customIcons) {
            expect(Array.from(db.meta.customIcons.entries())).assertDeepEquals(Array.from<[string, kdbxweb.KdbxCustomIcon]>(exp.meta.customIcons.entries()));
        }
    }
    if (exp.binaries) {
        expect(db.binaries.getAll()).assertDeepEquals(exp.binaries.getAll());
    }
    if (exp.del) {
        expect(db.deletedObjects.length).assertEqual(Object.keys(exp.del).length);
        const del: Record<string, Date | undefined> = {};
        for (const d of db.deletedObjects) {
            del[d.uuid!.id] = d.deletionTime;
        }
        expect(del).assertDeepEquals(exp.del);
    }
    if (exp.root) {
        expect(db.getDefaultGroup().parentGroup).assertEqual(undefined);
        assertGroupEquals(db.getDefaultGroup(), exp.root);
    }
}

function assertGroupEquals(group: kdbxweb.KdbxGroup, exp: ESObject) {
    if (exp.uuid) {
        expect(group.uuid).assertDeepEquals(exp.uuid);
    }
    if (exp.name) {
        expect(group.name).assertDeepEquals(exp.name);
    }
    if (exp.notes) {
        expect(group.notes).assertDeepEquals(exp.notes);
    }
    if (exp.icon) {
        expect(group.icon).assertDeepEquals(exp.icon);
    }
    if (exp.customIcon) {
        expect(group.customIcon).assertDeepEquals(exp.customIcon);
    }
    if (exp.modified) {
        expect(group.times.lastModTime).assertDeepEquals(exp.modified);
    }
    if (exp.expanded) {
        expect(group.expanded).assertDeepEquals(exp.expanded);
    }
    if (exp.defaultAutoTypeSeq) {
        expect(group.defaultAutoTypeSeq).assertDeepEquals(exp.defaultAutoTypeSeq);
    }
    if (exp.enableAutoType) {
        expect(group.enableAutoType).assertDeepEquals(exp.enableAutoType);
    }
    if (exp.enableSearching) {
        expect(group.enableSearching).assertDeepEquals(exp.enableSearching);
    }
    if (exp.lastTopVisibleEntry) {
        expect(group.lastTopVisibleEntry).assertDeepEquals(exp.lastTopVisibleEntry);
    }
    if (exp.groups) {
        expect(group.groups.length).assertEqual(exp.groups.length);
        group.groups.forEach((grp, ix) => {
            expect(grp.parentGroup).assertEqual(group);
            assertGroupEquals(grp, exp.groups[ix]);
        });
    }
    if (exp.entries) {
        expect(group.entries.length).assertEqual(exp.entries.length);
        group.entries.forEach((entry, ix) => {
            expect(entry.parentGroup).assertEqual(group);
            assertEntryEquals(entry, exp.entries[ix]);
        });
    }
}

function assertEntryEquals(entry: kdbxweb.KdbxEntry, exp: ESObject) {
    if (exp.uuid) {
        expect(entry.uuid).assertDeepEquals(exp.uuid);
    }
    if (exp.icon) {
        expect(entry.icon).assertDeepEquals(exp.icon);
    }
    if (exp.customIcon) {
        expect(entry.customIcon).assertDeepEquals(exp.customIcon);
    }
    if (exp.fgColor) {
        expect(entry.fgColor).assertDeepEquals(exp.fgColor);
    }
    if (exp.bgColor) {
        expect(entry.bgColor).assertDeepEquals(exp.bgColor);
    }
    if (exp.overrideUrl) {
        expect(entry.overrideUrl).assertDeepEquals(exp.overrideUrl);
    }
    if (exp.tags) {
        expect(entry.tags).assertDeepEquals(exp.tags);
    }
    if (exp.modified) {
        expect(entry.times.lastModTime).assertDeepEquals(exp.modified);
    }
    if (exp.fields) {
        expect(Array.from(entry.fields.entries())).assertDeepEquals(Array.from<[string, kdbxweb.KdbxEntryField]>(exp.fields.entries()));
    }
    if (exp.binaries) {
        expect(entry.binaries).assertDeepEquals(exp.binaries);
    }
    if (exp.history) {
        expect(entry.history.length).assertEqual(exp.history.length);
        entry.history.forEach((historyEntry, ix) => {
            assertEntryEquals(historyEntry, exp.history[ix]);
        });
    }
}

function tick() {
    const dt = new Date();
    while (new Date() <= dt) {
        continue;
    }
}


interface DateContainer {
    readonly pre1: Date;
    readonly created: Date;
    readonly upd1: Date;
    readonly upd2: Date;
    readonly upd3: Date;
    readonly upd4: Date;
    readonly upd5: Date;
    readonly upd6: Date;
}
interface IdContainer {
    readonly trash: kdbxweb.KdbxUuid;
    readonly name: kdbxweb.KdbxUuid;
    readonly tpl: kdbxweb.KdbxUuid;
    readonly eDel: kdbxweb.KdbxUuid;
    readonly eDel1: kdbxweb.KdbxUuid;
    readonly icon1: kdbxweb.KdbxUuid;
    readonly icon2: kdbxweb.KdbxUuid;
    readonly cd1: kdbxweb.KdbxUuid;
    readonly bin1: kdbxweb.KdbxUuid;
    readonly bin2: kdbxweb.KdbxUuid;
    readonly bin3: kdbxweb.KdbxUuid;
    readonly bin4: kdbxweb.KdbxUuid;
    readonly gRoot: kdbxweb.KdbxUuid;
    readonly g1: kdbxweb.KdbxUuid;
    readonly g11: kdbxweb.KdbxUuid;
    readonly g111: kdbxweb.KdbxUuid;
    readonly g112: kdbxweb.KdbxUuid;
    readonly g12: kdbxweb.KdbxUuid;
    readonly g2: kdbxweb.KdbxUuid;
    readonly g3: kdbxweb.KdbxUuid;
    readonly g31: kdbxweb.KdbxUuid;
    readonly g4: kdbxweb.KdbxUuid;
    readonly g5: kdbxweb.KdbxUuid;
    readonly er1:kdbxweb.KdbxUuid;
}

interface BinContainer {
  readonly bin1: Uint8Array;
  readonly bin2: Uint8Array;
  readonly bin3: Uint8Array;
  readonly bin4: Uint8Array;
  readonly icon1: Uint8Array;
  readonly icon2: Uint8Array;
}