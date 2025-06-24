import { describe, expect, it, beforeAll, afterAll, beforeEach, afterEach } from '@ohos/hypium';
import * as kdbxweb from '../../../../main/ets/index';
import { ohosArgon2 } from '../../../../main/ets/crypto/argon2';
import { expects } from '../test-support/Asserts';
import { TestResources } from '../test-support/test-resources';


export default function KdbxTest() {
    describe('Kdbx', () => {
        const cryptoEngineArgon2 = kdbxweb.CryptoEngine.argon2;
        const challengeResponse: kdbxweb.KdbxChallengeResponseFn = (challenge) => {
            const responses = new Map<string, string>([
                [
                    '011ed85afa703341893596fba2da60b6cacabaa5468a0e9ea74698b901bc89ab',
                    'ae7244b336f3360e4669ec9eaf4ddc23785aef03'
                ],
                [
                    '0ba4bbdf2e44fe56b64136a5086ba3ab814130d8e3fe7ed0e869cc976af6c12a',
                    '18350f73193e1c89211921d3016bfe3ddfc54d3e'
                ]
            ]);
            const hexChallenge = kdbxweb.ByteUtils.bytesToHex(challenge);
            const response = responses.get(hexChallenge) || '0000000000000000000000000000000000000000';
            return Promise.resolve(kdbxweb.ByteUtils.hexToBytes(response));
        };

        const  checkDb = (db: ESObject) => {
            expect(db.meta.name).assertEqual('demo');
            expect(db.meta.nameChanged.toISOString()).assertEqual('2015-08-16T14:45:23.000Z');
            expect(db.meta.desc).assertEqual('demo db');
            expect(db.meta.descChanged.toISOString()).assertEqual('2015-08-16T14:45:23.000Z');
            expect(db.meta.defaultUser).assertEqual('me');
            expect(db.meta.defaultUserChanged.toISOString()).assertEqual('2015-08-16T14:45:23.000Z');
            expect(db.meta.mntncHistoryDays).assertEqual(365);
            expect(db.meta.color).assertEqual('#FF0000');
            expect(db.meta.keyChanged.toISOString()).assertEqual('2015-08-16T14:53:28.000Z');
            expect(db.meta.keyChangeRec).assertEqual(-1);
            expect(db.meta.keyChangeForce).assertEqual(-1);
            expect(db.meta.recycleBinEnabled).assertEqual(true);
            expect(db.meta.recycleBinUuid.id).assertEqual('fZ7q9U4TBU+5VomeW3BZOQ==');
            expect(db.meta.recycleBinChanged.toISOString()).assertEqual('2015-08-16T14:44:42.000Z');
            expect(db.meta.entryTemplatesGroup.empty).assertEqual(true);
            expect(db.meta.entryTemplatesGroupChanged.toISOString()).assertEqual('2015-08-16T14:44:42.000Z');
            expect(db.meta.historyMaxItems).assertEqual(10);
            expect(db.meta.historyMaxSize).assertEqual(6291456);
            expect(db.meta.lastSelectedGroup.id).assertEqual('LWIve8M1xUuvrORCdYeRgA==');
            expect(db.meta.lastTopVisibleGroup.id).assertEqual('LWIve8M1xUuvrORCdYeRgA==');
            expect(db.meta.memoryProtection.title).assertEqual(false);
            expect(db.meta.memoryProtection.userName).assertEqual(false);
            expect(db.meta.memoryProtection.password).assertEqual(true);
            expect(db.meta.memoryProtection.url).assertEqual(false);
            expect(db.meta.memoryProtection.notes).assertEqual(false);
            expect(db.meta.customIcons.size).assertEqual(1);
            expect(db.meta.customIcons.get('rr3vZ1ozek+R4pAcLeqw5w==')).not().assertNull();

            const binaries:ESObject = db.binaries.getAll();
            expect(binaries.length).assertEqual(1);
            expect(binaries[0].ref).not().assertNull();
            expect(binaries[0].value).not().assertNull();

            expect(db.deletedObjects.length).assertEqual(1);
            expect(db.deletedObjects[0].uuid.id).assertEqual('LtoeZ26BBkqtr93N9tqO4g==');
            expect(db.deletedObjects[0].deletionTime.toISOString()).assertEqual('2015-08-16T14:50:13.000Z');

            expect(db.groups.length).assertEqual(1);
            checkGroup(db.groups[0], {
                uuid: 'LWIve8M1xUuvrORCdYeRgA==',
                name: 'sample',
                notes: '',
                icon: 49,
                times: {
                    creationTime: new Date('2015-08-16T14:44:42Z'),
                    lastModTime: new Date('2015-08-16T14:44:42Z'),
                    lastAccessTime: new Date('2015-08-16T14:50:15Z'),
                    expiryTime: new Date('2015-08-16T14:43:04Z'),
                    expires: false,
                    usageCount: 28,
                    locationChanged: new Date('2015-08-16T14:44:42Z')
                } as  ESObject,
                expanded: true,
                defaultAutoTypeSeq: '',
                enableAutoType: null,
                enableSearching: null,
                lastTopVisibleEntry: 'HzYFsnGCkEKyrPtOa6bNMA==',
                groups: 4,
                entries: 2
            });
            const topGroup:ESObject = db.groups[0];
            checkGroup(topGroup.groups[0], {
                uuid: 'GaN4R2PK1U63ckOVDzTY6w==',
                name: 'General',
                notes: '',
                icon: 48,
                times: {
                    creationTime: new Date('2015-08-16T14:45:23Z'),
                    lastModTime: new Date('2015-08-16T14:45:23Z'),
                    lastAccessTime: new Date('2015-08-16T14:45:51Z'),
                    expiryTime: new Date('2015-08-16T14:43:04Z'),
                    expires: false,
                    usageCount: 3,
                    locationChanged: new Date('2015-08-16T14:45:23Z')
                } as  ESObject,
                expanded: true,
                defaultAutoTypeSeq: '',
                enableAutoType: null,
                enableSearching: null,
                lastTopVisibleEntry: 'vqcoCvE9/k6PSgutKI6snw==',
                groups: 0,
                entries: 1
            });
            const expEntry:ESObject = {
                uuid: 'vqcoCvE9/k6PSgutKI6snw==',
                icon: 2,
                customIcon: undefined,
                fgColor: '#FF0000',
                bgColor: '#00FF00',
                overrideUrl: 'cmd://{GOOGLECHROME} "{URL}"',
                tags: ['my', 'tag'],
                times: {
                    creationTime: new Date('2015-08-16T14:45:54Z'),
                    lastModTime: new Date('2015-08-16T14:49:12Z'),
                    lastAccessTime: new Date('2015-08-16T14:49:23Z'),
                    expiryTime: new Date('2015-08-29T21:00:00Z'),
                    expires: true,
                    usageCount: 3,
                    locationChanged: new Date('2015-08-16T14:45:54Z')
                } as kdbxweb.KdbxTimes | undefined,
                fields: new Map([
                    ['Notes', 'some notes'],
                    ['Title', 'my entry'],
                    ['URL', 'http://me.me'],
                    ['UserName', 'me'],
                    ['my field', 'my val']
                ]),
                prFields: new Map([
                    ['Password', 'mypass'],
                    ['my field protected', 'protected val']
                ]),
                binaries: new Map([
                    [
                        'attachment',
                        {
                            hash: '6de2ccb163da5f925ea9cdc1298b7c1bd6f7afbbbed41f3d52352f9efbd9db8a',
                            value: true
                        } as ESObject
                    ]
                ]),
                autoType: {
                    enabled: true,
                    obfuscation: 0,
                    defaultSequence: '{USERNAME}{TAB}{PASSWORD}{ENTER}{custom}',
                    items: [
                        {
                            window: 'chrome',
                            keystrokeSequence: '{USERNAME}{TAB}{PASSWORD}{ENTER}{custom}{custom-key}'
                        }  as ESObject
                    ]
                } as ESObject,
                history: 1
            };
            checkEntry(topGroup.groups[0].entries[0], expEntry);
            expEntry.times = undefined;
            expEntry.fields.set('Title', 'my-entry');
            expEntry.prFields.set('Password', 'pass');
            expEntry.history = 0;
            checkEntry(topGroup.groups[0].entries[0].history[0], expEntry);
            checkGroup(topGroup.groups[1], {
                uuid: 'QF6yl7EUVk6+NgdJtyl3sg==',
                name: 'Windows',
                notes: '',
                icon: 38,
                expanded: false,
                defaultAutoTypeSeq: '',
                enableAutoType: null,
                enableSearching: null,
                lastTopVisibleEntry: 'AAAAAAAAAAAAAAAAAAAAAA==',
                groups: 1,
                entries: 0
            });
            checkGroup(topGroup.groups[2], {
                uuid: 'nBnVmN3JYkalgnMu9fVcXQ==',
                name: 'Internet',
                notes: '',
                icon: 1,
                expanded: true,
                defaultAutoTypeSeq: '',
                enableAutoType: null,
                enableSearching: null,
                lastTopVisibleEntry: 'AAAAAAAAAAAAAAAAAAAAAA==',
                groups: 0,
                entries: 0
            });
            checkGroup(topGroup.groups[3], {
                uuid: 'fZ7q9U4TBU+5VomeW3BZOQ==',
                name: 'Recycle Bin',
                notes: '',
                icon: 43,
                expanded: false,
                defaultAutoTypeSeq: '',
                enableAutoType: false,
                enableSearching: false,
                lastTopVisibleEntry: 'AAAAAAAAAAAAAAAAAAAAAA==',
                groups: 2,
                entries: 1
            });
        }

        const checkGroup = (group: kdbxweb.KdbxGroup, exp: ESObject) =>{
            expect(group).not().assertNull();
            expect(group.uuid?.id).assertEqual(exp.uuid);
            expect(group.name).assertEqual(exp.name);
            expect(group.notes).assertEqual(exp.notes);
            expect(group.icon).assertEqual(exp.icon);
            expect(group.expanded).assertEqual(exp.expanded);
            expect(group.defaultAutoTypeSeq).assertEqual(exp.defaultAutoTypeSeq);
            expect(group.enableAutoType).assertEqual(exp.enableAutoType);
            expect(group.enableSearching).assertEqual(exp.enableSearching);
            expect(group.lastTopVisibleEntry?.id).assertEqual(exp.lastTopVisibleEntry);
            expect(group.groups.length).assertEqual(exp.groups);
            expect(group.entries.length).assertEqual(exp.entries);
            if (exp.times) {
                expect(group.times).assertDeepEquals(exp.times);
            }
            expect(group.enableAutoType).assertDeepEquals(exp.enableAutoType);
            expect(group.defaultAutoTypeSeq).assertDeepEquals(exp.defaultAutoTypeSeq);
        }

        const checkEntry = (entry: kdbxweb.KdbxEntry, exp: ESObject) => {
            expect(entry).not().assertNull();
            expect(entry.uuid.id).assertEqual(exp.uuid);
            expect(entry.icon).assertEqual(exp.icon);
            expect(entry.customIcon).assertEqual(exp.customIcon);
            expect(entry.fgColor).assertEqual(exp.fgColor);
            expect(entry.bgColor).assertEqual(exp.bgColor);
            expect(entry.overrideUrl).assertEqual(exp.overrideUrl);
            expect(entry.tags).assertDeepEquals(exp.tags);
            if (exp.times) {
                expect(entry.times).assertDeepEquals(exp.times);
            }
            expect(entry.fields.size).assertEqual((exp.fields.size | 0) + (exp.prFields.size | 0));

            const  expFields =  Array.from<[string, kdbxweb.KdbxEntryField]>(exp.fields.entries());
            for (const expEntry of expFields) {
                const field = expEntry[0] as string;
                const value = expEntry[1] as kdbxweb.KdbxEntryField;
                expect(entry.fields.get(field)).assertEqual(value);
            }

            const  expPrFields =  Array.from<[string, kdbxweb.ProtectedValue]>(exp.prFields.entries());
            for (const expPrField of expPrFields) {
                const field = expPrField[0] as string;
                const value = expPrField[1] as kdbxweb.ProtectedValue;
                expect((entry.fields.get(field) as kdbxweb.ProtectedValue).getText()).assertEqual(value);
            }
            expect(entry.binaries.size).assertEqual(exp.binaries.size);


            const  expBinariesMap =  Array.from<[string, kdbxweb.KdbxBinary | kdbxweb.KdbxBinaryWithHash]>(exp.binaries.entries());
            for (const expBinaries of expBinariesMap) {
                const field = expBinaries[0] as string;
                const value = expBinaries[1] as kdbxweb.KdbxBinaryWithHash;
                expect((entry.binaries.get(field) as kdbxweb.KdbxBinaryWithHash).hash).assertEqual(value.hash);
                expect(!!(entry.binaries.get(field) as kdbxweb.KdbxBinaryWithHash).value).assertEqual(!!value.value);
            }
            expect(entry.autoType).assertDeepEquals(exp.autoType);
            expect(entry.history.length).assertEqual(exp.history);
        }

        // timeout check
        let durationTime = Date.now();

        beforeAll(() => {
            kdbxweb.CryptoEngine.setArgon2Impl(ohosArgon2);
        });

        afterAll(() => {
            kdbxweb.CryptoEngine.argon2 = cryptoEngineArgon2;
        });

        beforeEach(()=>{
            durationTime = Date.now();
        });

        afterEach(()=>{
            durationTime = Date.now() - durationTime;
            expect(durationTime).assertLess(10000);
        })

        it('loads simple file', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                expect(db.meta.generator).assertEqual('KeePass');
                checkDb(db);
            });
        });

        it('checks versions', 0,async () => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            const db = await kdbxweb.Kdbx.load(TestResources.demoKdbx, cred);
            expect(db.versionMajor).assertEqual(3);
            expect(db.versionMinor).assertEqual(1);
            expect(db.versionIsAtLeast(1, 0)).assertEqual(true);
            expect(db.versionIsAtLeast(3, 0)).assertEqual(true);
            expect(db.versionIsAtLeast(3, 1)).assertEqual(true);
            expect(db.versionIsAtLeast(3, 2)).assertEqual(false);
            expect(db.versionIsAtLeast(4, 0)).assertEqual(false);
            expect(db.versionIsAtLeast(4, 1)).assertEqual(false);
            expect(db.versionIsAtLeast(4, 2)).assertEqual(false);
        });

        it('loads simple xml file', 0,() => {
            const cred = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString(''));
            const xml = kdbxweb.ByteUtils.bytesToString(TestResources.demoXml).toString();
            return kdbxweb.Kdbx.loadXml(xml, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                expect(db.meta.generator).assertEqual('KeePass');
                checkDb(db);
            });
        });

        it('generates error for malformed xml file', 0,() => {
            const cred = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString(''));
            return kdbxweb.Kdbx.loadXml('malformed-xml', cred)
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.FileCorrupt);
                    expect(e.message).assertContain('bad xml');
                });
        });

        it('loads utf8 uncompressed file', 0,() => {
            const cred = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('пароль'));
            return kdbxweb.Kdbx.load(TestResources.cyrillicKdbx, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
            });
        });

        it('loads a file with binary key', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('test'),
                TestResources.binKeyKey
            );
            return kdbxweb.Kdbx.load(TestResources.binKeyKdbx, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
            });
        });

        it('loads a file with empty pass', 0,() => {
            const cred = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString(''));
            return kdbxweb.Kdbx.load(TestResources.emptyPass, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
            });
        });

        it('loads a file with empty pass and keyfile', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString(''),
                TestResources.emptyPassWithKeyFileKey
            );
            return kdbxweb.Kdbx.load(TestResources.emptyPassWithKeyFile, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
            });
        });

        it('loads a file with no pass and keyfile', 0,() => {
            const cred = new kdbxweb.Credentials(null, TestResources.noPassWithKeyFileKey);
            return kdbxweb.Kdbx.load(TestResources.noPassWithKeyFile, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
            });
        });

        it('loads a 32-byte keyfile', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('test'),
                TestResources.key32KeyFile
            );
            return kdbxweb.Kdbx.load(TestResources.key32, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
            });
        });

        it('loads a 64-byte keyfile', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('test'),
                TestResources.key64KeyFile
            );
            return kdbxweb.Kdbx.load(TestResources.key64, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
            });
        });

        it('loads a xml-bom keyfile', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('test'),
                TestResources.keyWithBomKeyFile
            );
            return kdbxweb.Kdbx.load(TestResources.keyWithBom, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
            });
        });

        it('loads a V2 keyfile', 0,() => {
            const cred = new kdbxweb.Credentials(null, TestResources.keyV2KeyFile);
            return kdbxweb.Kdbx.load(TestResources.keyV2, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
            });
        });

        it('successfully loads saved file', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                checkDb(db);
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.meta.generator).assertEqual('KdbxWeb');
                        checkDb(db);
                    });
                });
            });
        });

        it('loads kdbx4 file with argon2 kdf',  0, () =>{
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.argon2, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                checkDb(db);
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.meta.generator).assertEqual('KdbxWeb');
                        checkDb(db);
                    });
                });
            });
        });

        it('loads kdbx4 file with argon2id kdf',  0, () =>{
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.argon2id, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                checkDb(db);
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.meta.generator).assertEqual('KdbxWeb');
                        checkDb(db);
                    });
                });
            });
        });

        it('loads kdbx3 file with chacha20', 0, () => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.aesChaCha, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                expect(db.header.dataCipherUuid!.toString()).assertEqual(kdbxweb.Consts.CipherId.ChaCha20);
                checkDb(db);
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.meta.generator).assertEqual('KdbxWeb');
                        expect(db.header.dataCipherUuid!.toString()).assertEqual(
                            kdbxweb.Consts.CipherId.ChaCha20
                        );
                        checkDb(db);
                    });
                });
            });
        });

        it('loads kdbx4 file with aes kdf', 0, () => {
            const cred = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('demo'));
            return kdbxweb.Kdbx.load(TestResources.aesKdfKdbx4, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                expect(db.header.dataCipherUuid!.toString()).assertEqual(kdbxweb.Consts.CipherId.Aes);
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.meta.generator).assertEqual('KdbxWeb');
                        expect(db.header.dataCipherUuid!.toString()).assertEqual(kdbxweb.Consts.CipherId.Aes);
                    });
                });
            });
        });

        it('loads kdbx4 file with argon2 kdf and chacha20 encryption', 0,  () => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.argon2ChaCha, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                checkDb(db);
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.meta.generator).assertEqual('KdbxWeb');
                        checkDb(db);
                    });
                });
            });
        });

        it('loads kdbx3 file with challenge-response',  0, () =>{
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                null,
                challengeResponse
            );
            return kdbxweb.Kdbx.load(TestResources.yubikey3, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                expect(db.meta.generator).assertEqual('Strongbox');
            });
        });

        it('loads a kdbx4 file with challenge-response',  0, () =>{
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                null,
                challengeResponse
            );
            return kdbxweb.Kdbx.load(TestResources.yubikey4, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                expect(db.meta.generator).assertEqual('KeePassXC');
            });
        });

        it('upgrades file to latest version', 0,  () =>{
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                checkDb(db);
                db.upgrade();
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.header.versionMajor).assertEqual(4);
                        expect(
                            kdbxweb.ByteUtils.bytesToBase64(
                                db.header.kdfParameters!.get('$UUID') as ArrayBuffer
                            )
                        ).assertEqual(kdbxweb.Consts.KdfId.Argon2);
                        checkDb(db);
                    });
                });
            });
        });

        it('upgrades file to V4 with aes kdf', 0,  () =>{
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                checkDb(db);
                db.upgrade();
                db.setKdf(kdbxweb.Consts.KdfId.Aes);
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.header.versionMajor).assertEqual(4);
                        expect(
                            kdbxweb.ByteUtils.bytesToBase64(
                                db.header.kdfParameters!.get('$UUID') as ArrayBuffer
                            )
                        ).assertEqual(kdbxweb.Consts.KdfId.Aes);
                        checkDb(db);
                    });
                });
            });
        });

        it('upgrades file to V4 with argon2id kdf', 0,  () =>{
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                checkDb(db);
                db.upgrade();
                db.setKdf(kdbxweb.Consts.KdfId.Argon2id);
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.header.versionMajor).assertEqual(4);
                        expect(
                            kdbxweb.ByteUtils.bytesToBase64(
                                db.header.kdfParameters!.get('$UUID') as ArrayBuffer
                            )
                        ).assertEqual(kdbxweb.Consts.KdfId.Argon2id);
                        checkDb(db);
                    });
                });
            });
        });

        it('downgrades file to V3', 0,  () =>{
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                checkDb(db);
                db.setVersion(3);
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.header.versionMajor).assertEqual(3);
                        checkDb(db);
                    });
                });
            });
        });

        it('saves kdbx4 to xml and loads it back', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                checkDb(db);
                db.upgrade();
                return db.saveXml().then((xml) => {
                    return kdbxweb.Kdbx.loadXml(xml, cred).then((db) => {
                        checkDb(db);
                    });
                });
            });
        });

        it('saves and loads custom data', 0,  () =>{
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                const iconId = kdbxweb.KdbxUuid.random();
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                checkDb(db);
                db.upgrade();
                db.getDefaultGroup().groups[0].customData = new Map([['custom', { value: 'group' } as kdbxweb.KdbxCustomDataItem]]);
                db.getDefaultGroup().groups[0].customIcon = iconId;
                db.getDefaultGroup().entries[0].customData = new Map([['custom', { value: 'entry' } as kdbxweb.KdbxCustomDataItem]]);
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.header.versionMajor).assertEqual(4);
                        expect(Array.from(db.getDefaultGroup().groups[0].customData!)).assertDeepEquals([
                            ['custom', { value: 'group' }]
                        ]);
                        expect(db.getDefaultGroup().groups[0].customIcon!.toString()).assertDeepEquals(
                            iconId.toString()
                        );
                        expect(Array.from(db.getDefaultGroup().entries[0].customData!)).assertDeepEquals([
                            ['custom', { value: 'entry' }]
                        ]);
                        checkDb(db);
                    });
                });
            });
        });

        it('creates new database', 0,() => {
            return kdbxweb.Credentials.createRandomKeyFile(1).then((keyFile) => {
                const cred = new kdbxweb.Credentials(
                    kdbxweb.ProtectedValue.fromString('demo'),
                    keyFile
                );
                const db = kdbxweb.Kdbx.create(cred, 'example');
                const subGroup = db.createGroup(db.getDefaultGroup(), 'subgroup');
                const entry = db.createEntry(subGroup);
                db.meta.customData.set('key', { value: 'val' });
                db.createDefaultGroup();
                db.createRecycleBin();
                entry.fields.set('Title', 'title');
                entry.fields.set('UserName', 'user');
                entry.fields.set('Password', kdbxweb.ProtectedValue.fromString('pass'));
                entry.fields.set('Notes', 'notes');
                entry.fields.set('URL', 'url');
                return db
                    .createBinary(kdbxweb.ProtectedValue.fromString('bin.txt content'))
                    .then((binary) => {
                        entry.binaries.set('bin.txt', binary);
                        entry.pushHistory();
                        entry.fields.set('Title', 'newtitle');
                        entry.fields.set('UserName', 'newuser');
                        entry.fields.set('Password', kdbxweb.ProtectedValue.fromString('newpass'));
                        entry.fields.set('CustomPlain', 'custom-plain');
                        entry.fields.set(
                            'CustomProtected',
                            kdbxweb.ProtectedValue.fromString('custom-protected')
                        );
                        entry.times.update();
                        return db.save().then((ab) => {
                            return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                                expect(db.meta.generator).assertEqual('KdbxWeb');
                                expect(db.meta.customData.get('key')?.value).assertEqual('val');
                                expect(db.groups.length).assertEqual(1);
                                expect(db.groups[0].groups.length).assertEqual(2);
                                expect(db.getGroup(db.meta.recycleBinUuid!)).assertEqual(
                                    db.groups[0].groups[0]
                                );
                            });
                        });
                    });
            });
        });

        it('creates random keyfile v2', 0,() => {
            return kdbxweb.Credentials.createRandomKeyFile(2).then((keyFile) => {
                const cred = new kdbxweb.Credentials(
                    kdbxweb.ProtectedValue.fromString('demo'),
                    keyFile
                );
                const db = kdbxweb.Kdbx.create(cred, 'example');
                const keyFileStr = kdbxweb.ByteUtils.bytesToString(keyFile).toString();
                expect(keyFileStr).assertContain('<Version>2.0</Version>');
                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.meta.generator).assertEqual('KdbxWeb');
                    });
                });
            });
        });

        it('generates error for bad file', 0,() => {
            // @ets-ignore
            return kdbxweb.Kdbx.load(null, null)
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidArg);
                    expect(e.message).assertContain('data');
                });
        });

        it('generates an error for too high major version 5', 0,() => {
            const file = new Uint8Array(TestResources.demoKdbx.byteLength);
            file.set(new Uint8Array(TestResources.demoKdbx));
            file[10] = 5;
            return kdbxweb.Kdbx.load(
                file.buffer,
                new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('demo'))
            )
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidVersion);
                });
        });

        it('generates an error for too high major version 2', 0,() => {
            const file = new Uint8Array(TestResources.demoKdbx.byteLength);
            file.set(new Uint8Array(TestResources.demoKdbx));
            file[10] = 2;
            return kdbxweb.Kdbx.load(
                file.buffer,
                new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('demo'))
            )
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidVersion);
                });
        });

        it('generates an error for too high minor version', 0,() => {
            const file = new Uint8Array(TestResources.demoKdbx.byteLength);
            file.set(new Uint8Array(TestResources.demoKdbx));
            file[11] = 10;
            return kdbxweb.Kdbx.load(
                file.buffer,
                new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('demo'))
            )
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidVersion);
                });
        });

        it('generates error for bad header hash', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            const file = new Uint8Array(TestResources.argon2.byteLength);
            file.set(new Uint8Array(TestResources.argon2));
            file[254] = 0;
            return kdbxweb.Kdbx.load(file.buffer, cred)
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.FileCorrupt);
                    expect(e.message).assertContain('header hash mismatch');
                });
        });

        it('generates error for bad header hmac', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            const file = new Uint8Array(TestResources.argon2.byteLength);
            file.set(new Uint8Array(TestResources.argon2));
            file[286] = 0;
            return kdbxweb.Kdbx.load(file.buffer, cred)
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidKey);
                });
        });

        it('generates error for saving bad version', 0,() => {
            return kdbxweb.Credentials.createRandomKeyFile().then((keyFile) => {
                const cred = new kdbxweb.Credentials(
                    kdbxweb.ProtectedValue.fromString('demo'),
                    keyFile
                );
                const db = kdbxweb.Kdbx.create(cred, 'example');
                db.header.setVersion(3);
                db.header.versionMajor = 1;
                return db
                    .save()
                    .then(() => {
                        throw new Error('Not expected');
                    })
                    .catch((e:Error) => {
                        expects(e).assertInstanceOf(kdbxweb.KdbxError);
                        expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidVersion);
                    });
            });
        });


        it('generates error for null credentials', 0,() => {
            // @ets-ignore
            return kdbxweb.Kdbx.load(new ArrayBuffer(0), null)
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidArg);
                    expect(e.message).assertContain('credentials');
                });
        });

        it('generates error for bad password null', 0,() => {
            const cred = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('demo'));
            return (
            cred
            // @ets-ignore
                .setPassword(null)
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidArg);
                    expect(e.message).assertContain('password');
                })
            );
        });

        it('generates error for bad keyfile', 0,() => {
            const cred = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('demo'));
            return (
            cred
            // @ets-ignore
                .setKeyFile(null)
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidArg);
                    expect(e.message).assertContain('keyFile');
                })
            );
        });

        it('generates error for create with bad credentials', 0,() => {
            expects(() => {
                // @ets-ignore
                kdbxweb.Kdbx.create(new kdbxweb.Credentials(null), null);
            }).assertThrowError((e:Error) => {
                expects(e).assertInstanceOf(kdbxweb.KdbxError);
                expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidArg);
                expect(e.message).assertContain('credentials');
            });
        });

        it('generates loadXml error for bad data', 0,() => {
            // @ets-ignore
            return kdbxweb.Kdbx.loadXml(null, null)
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidArg);
                    expect(e.message).assertContain('data');
                });
        });

        it('generates loadXml error for bad credentials', 0,() => {
            // @ets-ignore
            return kdbxweb.Kdbx.loadXml('str', null)
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidArg);
                    expect(e.message).assertContain('credentials');
                });
        });

        it('generates error for bad password', 0,() => {
            return kdbxweb.Kdbx.load(
                TestResources.demoKdbx,
                new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('badpass'))
            )
                .then(() => {
                    throw new Error('Not expected');
                })
                .catch((e:Error) => {
                    expect(e).not().assertNull();
                    expects(e).assertInstanceOf(kdbxweb.KdbxError);
                    expect((e as kdbxweb.KdbxError).code).assertEqual(kdbxweb.Consts.ErrorCodes.InvalidKey);
                });
        });

        it('deletes and restores an entry', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                const parentGroup = db.getDefaultGroup().groups[1];
                const group = parentGroup.groups[parentGroup.groups.length - 1];
                const recycleBin = db.getGroup(db.meta.recycleBinUuid!);
                const recycleBinLength = recycleBin!.groups.length;
                const groupLength = parentGroup.groups.length;
                db.remove(group);
                expect(recycleBin!.groups.length).assertEqual(recycleBinLength + 1);
                expect(group.groups.length).assertEqual(groupLength - 1);

                const parentGroupsBackup = group.parentGroup!.groups;
                group.parentGroup!.groups = [];
                db.move(group, parentGroup); // fake move; should not happen
                group.parentGroup!.groups = parentGroupsBackup;
                expect(recycleBin!.groups.length).assertEqual(recycleBinLength + 1);

                db.move(group, parentGroup);
                expect(recycleBin!.groups.length).assertEqual(recycleBinLength);
                checkDb(db);
            });
        });

        it('changes group order', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                const defaultGroup = db.getDefaultGroup();
                expect(defaultGroup.groups.length).assertLarger(3);
                const groupNames = defaultGroup.groups.map((g) => {
                    return g.name;
                });
                const fromIndex = 2;
                const toIndex = 1;
                db.move(defaultGroup.groups[fromIndex], defaultGroup, toIndex);
                groupNames.splice(toIndex, 0, groupNames.splice(fromIndex, 1)[0]);
                const newGroupNames = defaultGroup.groups.map((g) => {
                    return g.name;
                });
                expect(newGroupNames).assertDeepEquals(groupNames);
                db.move(defaultGroup.groups[fromIndex], defaultGroup, toIndex);
                checkDb(db);
            });
        });

        it('deletes entry without recycle bin', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                const parentGroup = db.getDefaultGroup().groups[1];
                const group = parentGroup.groups[parentGroup.groups.length - 1];
                const deletedObjectsLength = db.deletedObjects.length;
                db.meta.recycleBinEnabled = false;
                db.remove(group);
                expect(db.deletedObjects.length).assertEqual(deletedObjectsLength + 1);
                expect(db.deletedObjects[db.deletedObjects.length - 1].uuid).assertEqual(group.uuid);
            });
        });

        it('creates a recycle bin if it is enabled but not created', 0,() => {
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((db) => {
                const parentGroup = db.getDefaultGroup().groups[1];
                const group = parentGroup.groups[parentGroup.groups.length - 1];
                db.meta.recycleBinUuid = new kdbxweb.KdbxUuid();
                expect(db.meta.recycleBinUuid.empty).assertEqual(true);
                let recycleBin = db.getGroup(db.meta.recycleBinUuid);
                expect(recycleBin).assertEqual(undefined);
                const groupLength = parentGroup.groups.length;
                db.remove(group);
                expect(db.meta.recycleBinUuid.empty).assertEqual(false);
                recycleBin = db.getGroup(db.meta.recycleBinUuid);
                expect(recycleBin).not().assertNull();
                expect(recycleBin!.groups.length).assertEqual(1);
                expect(group.groups.length).assertEqual(groupLength - 1);
            });
        });

        it('saves db to xml', 0,() => {
            return kdbxweb.Credentials.createRandomKeyFile().then((keyFile) => {
                const cred = new kdbxweb.Credentials(
                    kdbxweb.ProtectedValue.fromString('demo'),
                    keyFile
                );
                const db = kdbxweb.Kdbx.create(cred, 'example');
                const subGroup = db.createGroup(db.getDefaultGroup(), 'subgroup');
                const entry = db.createEntry(subGroup);
                entry.fields.set('Title', 'title');
                entry.fields.set('UserName', 'user');
                entry.fields.set('Password', kdbxweb.ProtectedValue.fromString('pass'));
                entry.fields.set('Notes', 'notes');
                entry.fields.set('URL', 'url');
                entry.times.update();
                return db.saveXml().then((xml) => {
                    expect(xml).assertContain('<Value ProtectInMemory="True">pass</Value>');
                });
            });
        });

        it('cleanups by history rules', 0,() => {
            return kdbxweb.Credentials.createRandomKeyFile().then((keyFile) => {
                const cred = new kdbxweb.Credentials(
                    kdbxweb.ProtectedValue.fromString('demo'),
                    keyFile
                );
                const db = kdbxweb.Kdbx.create(cred, 'example');
                const subGroup = db.createGroup(db.getDefaultGroup(), 'subgroup');
                const entry = db.createEntry(subGroup);
                let i = 0;
                for (i = 0; i < 3; i++) {
                    entry.fields.set('Title', i.toString());
                    entry.pushHistory();
                }
                expect(entry.history[0].fields.get('Title')).assertEqual('0');
                expect(entry.history.length).assertEqual(3);
                db.cleanup({ historyRules: true });
                expect(entry.history.length).assertEqual(3);
                for (i = 3; i < 10; i++) {
                    entry.fields.set('Title', i.toString());
                    entry.pushHistory();
                }
                expect(entry.history[0].fields.get('Title')).assertEqual('0');
                expect(entry.history.length).assertEqual(10);
                expect(entry.history[0].fields.get('Title')).assertEqual('0');
                db.cleanup({ historyRules: true });
                expect(entry.history[0].fields.get('Title')).assertEqual('0');
                expect(entry.history.length).assertEqual(10);
                for (i = 10; i < 11; i++) {
                    entry.fields.set('Title', i.toString());
                    entry.pushHistory();
                }
                expect(entry.history.length).assertEqual(11);
                db.cleanup({ historyRules: true });
                expect(entry.history[0].fields.get('Title')).assertEqual('1');
                expect(entry.history.length).assertEqual(10);
                for (i = 11; i < 20; i++) {
                    entry.fields.set('Title', i.toString());
                    entry.pushHistory();
                }
                db.cleanup({ historyRules: true });
                expect(entry.history[0].fields.get('Title')).assertEqual('10');
                expect(entry.history.length).assertEqual(10);
                for (i = 20; i < 30; i++) {
                    entry.fields.set('Title', i.toString());
                    entry.pushHistory();
                }
                db.meta.historyMaxItems = -1;
                db.cleanup({ historyRules: true });
                expect(entry.history[0].fields.get('Title')).assertEqual('10');
                expect(entry.history.length).assertEqual(20);
                db.cleanup();
                db.cleanup({});
                expect(entry.history.length).assertEqual(20);
                db.meta.historyMaxItems = undefined;
                db.cleanup({ historyRules: true });
                expect(entry.history[0].fields.get('Title')).assertEqual('10');
                expect(entry.history.length).assertEqual(20);
            });
        });

        it('cleanups custom icons', 0,() => {
            return kdbxweb.Credentials.createRandomKeyFile().then((keyFile) => {
                const cred = new kdbxweb.Credentials(
                    kdbxweb.ProtectedValue.fromString('demo'),
                    keyFile
                );
                const db = kdbxweb.Kdbx.create(cred, 'example');
                const subGroup = db.createGroup(db.getDefaultGroup(), 'subgroup');
                const entry = db.createEntry(subGroup);
                let i = 0;
                const ids = [
                    kdbxweb.KdbxUuid.random(),
                    kdbxweb.KdbxUuid.random(),
                    kdbxweb.KdbxUuid.random(),
                    kdbxweb.KdbxUuid.random(),
                    kdbxweb.KdbxUuid.random(),
                    kdbxweb.KdbxUuid.random()
                ];
                for (i = 0; i < 3; i++) {
                    entry.fields.set('Title', i.toString());
                    entry.customIcon = ids[0];
                    entry.pushHistory();
                }
                entry.customIcon = ids[1];
                subGroup.customIcon = ids[2];

                const icon1 = new Uint8Array([1]).buffer;
                const icon2 = new Uint8Array([2]).buffer;
                const icon3 = new Uint8Array([3]).buffer;
                const rem1 = new Uint8Array([4]).buffer;
                const rem2 = new Uint8Array([5]).buffer;
                const rem3 = new Uint8Array([6]).buffer;

                db.meta.customIcons.set(ids[0].id, { data: icon1 });
                db.meta.customIcons.set(ids[1].id, { data: icon2 });
                db.meta.customIcons.set(ids[2].id, { data: icon3 });
                db.meta.customIcons.set(ids[3].id, { data: rem1 });
                db.meta.customIcons.set(ids[4].id, { data: rem2 });
                db.meta.customIcons.set(ids[5].id, { data: rem3 });
                db.cleanup({ customIcons: true });
                expect(Array.from(db.meta.customIcons)).assertDeepEquals([
                    [ids[0].id, { data: icon1 }],
                    [ids[1].id, { data: icon2 }],
                    [ids[2].id, { data: icon3 }]
                ]);
            });
        });

        it('cleanups binaries', 0,() => {
            return kdbxweb.Credentials.createRandomKeyFile().then(async (keyFile) => {
                const cred = new kdbxweb.Credentials(
                    kdbxweb.ProtectedValue.fromString('demo'),
                    keyFile
                );
                const db = kdbxweb.Kdbx.create(cred, 'example');
                const subGroup = db.createGroup(db.getDefaultGroup(), 'subgroup');
                const entry = db.createEntry(subGroup);
                let i = 0;
                const b1 = new Uint8Array([1]).buffer;
                const b2 = new Uint8Array([2]).buffer;
                for (i = 0; i < 3; i++) {
                    entry.fields.set('Title', i.toString());
                    entry.binaries.set('bin', await db.createBinary(b1));
                    entry.pushHistory();
                }
                entry.binaries.set('bin', await db.createBinary(b2));
                await db.createBinary(new Uint8Array([3]));
                await db.createBinary(new Uint8Array([4]));
                await db.createBinary(new Uint8Array([5]));
                db.cleanup({ binaries: true });
                expect(db.binaries.getAll().map((e) => e.value)).assertDeepEquals([b1, b2]);
            });
        });

        it('imports an entry from another file',  0, () =>{
            const cred = new kdbxweb.Credentials(
                kdbxweb.ProtectedValue.fromString('demo'),
                TestResources.demoKey
            );
            const db = kdbxweb.Kdbx.create(cred, 'example');
            return kdbxweb.Kdbx.load(TestResources.demoKdbx, cred).then((sourceDb) => {
                const sourceEntryWithCustomIcon = sourceDb.groups[0].entries[0];
                const sourceEntryWithBinaries = sourceDb.groups[0].groups[0].entries[0];

                expect(sourceDb.groups[0].entries.length).assertEqual(2);
                expect(sourceEntryWithCustomIcon.customIcon).not().assertNull();
                expect(Array.from(sourceEntryWithBinaries.binaries.keys())).assertDeepEquals(['attachment']);

                const importedEntryWithCustomIcon = db.importEntry(
                    sourceEntryWithCustomIcon,
                    db.groups[0],
                    sourceDb
                );
                const importedEntryWithBinaries = db.importEntry(
                    sourceEntryWithBinaries,
                    db.groups[0],
                    sourceDb
                );

                expect(importedEntryWithCustomIcon.uuid).not().assertDeepEquals(sourceEntryWithCustomIcon.uuid);
                expect(importedEntryWithBinaries.uuid).not().assertDeepEquals(sourceEntryWithBinaries.uuid);

                return db.save().then((ab) => {
                    return kdbxweb.Kdbx.load(ab, cred).then((db) => {
                        expect(db.groups[0].entries.length).assertEqual(2);

                        const withCustomIcon = db.groups[0].entries[0];
                        const withBinaries = db.groups[0].entries[1];

                        expect(withCustomIcon.uuid).assertDeepEquals(importedEntryWithCustomIcon.uuid);
                        expect(withCustomIcon.customIcon).not().assertNull();
                        expect(db.meta.customIcons.get(withCustomIcon.customIcon!.id)).not().assertNull();

                        expect(withBinaries.uuid).assertDeepEquals(importedEntryWithBinaries.uuid);
                        expect(Array.from(withBinaries.binaries.keys())).assertDeepEquals(['attachment']);
                    });
                });
            });
        });

        it('creates missing uuids', 0,() => {
            const cred = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString(''));
            const xml = kdbxweb.ByteUtils.bytesToString(TestResources.emptyUuidXml).toString();
            return kdbxweb.Kdbx.loadXml(xml, cred).then((db) => {
                expects(db).assertInstanceOf(kdbxweb.Kdbx);
                expect(db.groups.length).assertEqual(1);
                expect(db.groups[0].uuid).not().assertNull();
                expect(db.groups[0].uuid.id).not().assertNull();
                const entry = db.groups[0].groups[0].entries[0];
                expect(entry.uuid).not().assertNull();
                expect(entry.uuid.id).not().assertNull();
                expect(entry.history.length).assertLarger(0);
                for (let i = 0; i < entry.history.length; i++) {
                    const he = entry.history[i];
                    expect(he.uuid).not().assertNull();
                    expect(he.uuid.id).assertEqual(entry.uuid.id);
                }
            });
        });

        it('supports KDBX4.1 features',  0,async () => {
            const check = (db: kdbxweb.Kdbx) => {
                const groupWithTags = db.groups[0].groups[0].groups[0];
                expect(groupWithTags).not().assertNull();
                expect(groupWithTags.name).assertEqual('With tags');
                expect(groupWithTags.tags).assertDeepEquals(['Another tag', 'Tag1']);
                expect(groupWithTags.previousParentGroup).assertEqual(undefined);
                const regularEntry = db.groups[0].entries[0];
                expect(regularEntry.qualityCheck).assertEqual(undefined);
                const entryWithDisabledPasswordQuality = db.groups[0].entries[1];
                expect(entryWithDisabledPasswordQuality).not().assertNull();
                expect(entryWithDisabledPasswordQuality.fields.get('Title')).assertEqual('DisabledQ');
                expect(entryWithDisabledPasswordQuality.qualityCheck).assertEqual(false);
                const previousParentGroup = db.groups[0].groups[0].groups[1];
                expect(previousParentGroup).not().assertNull();
                expect(previousParentGroup.name).assertEqual('Inside');
                const groupMovedFromInside = db.groups[0].groups[0].groups[2];
                expect(groupMovedFromInside).not().assertNull();
                expect(groupMovedFromInside.name).assertEqual('New group was inside');
                expect(previousParentGroup.uuid.equals(groupMovedFromInside.previousParentGroup)).not().assertNull();
                const entryMovedFromInside = db.groups[0].groups[0].entries[0];
                expect(entryMovedFromInside).not().assertNull();
                expect(entryMovedFromInside.fields.get('Title')).assertEqual('Was inside');
                expect(previousParentGroup.uuid.equals(entryMovedFromInside.previousParentGroup)).not().assertNull();
                expect(db.meta.customIcons.size).assertEqual(2);
                const icon1 = db.meta.customIcons.get('3q2nWI0en0W/wvhaCFJsnw==');
                expect(icon1).not().assertNull();
                expect(icon1!.name).assertEqual('Bulb icon');
                expect(icon1!.lastModified?.toISOString()).assertEqual('2021-05-05T18:28:34.000Z');
                expect(db.meta.customData.size).assertEqual(4);
                expect(db.meta.customData.get('Test_A')).assertDeepEquals({
                    value: 'NmL56onQIqdk1WSt',
                    lastModified: new Date('2021-01-20T18:10:44.000Z')
                });
            }

            const cred = new kdbxweb.Credentials(kdbxweb.ProtectedValue.fromString('test'));
            let db = await kdbxweb.Kdbx.load(TestResources.kdbx41, cred);

            check(db);

            const xml = await db.saveXml();
            db = await kdbxweb.Kdbx.loadXml(xml, cred);

            check(db);
        });
    });
}


