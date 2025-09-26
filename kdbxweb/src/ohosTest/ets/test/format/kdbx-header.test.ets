import { describe, expect, it } from '@ohos/hypium';
import {
    BinaryStream,
    ByteUtils,
    Consts,
    Int64,
    Kdbx,
    KdbxBinaries,
    KdbxContext,
    KdbxError,
    KdbxHeader,
    KdbxUuid,
    ProtectedValue,
    VarDictionary
} from '../../../../main/ets/index';
import { ValueType } from '../../../../main/ets/utils/var-dictionary';
import { expects } from '../test-support/Asserts';

export default function KdbxHeaderTest() {
    describe('KdbxHeader', () => {
        const kdbx = new Kdbx();

        it('writes and reads header v3', 0,() => {
            const ctx = new KdbxContext({ kdbx });
            const header = KdbxHeader.create();
            expect(header.versionMajor).assertEqual(4);
            header.setVersion(3);
            expect(header.versionMajor).assertEqual(3);
            header.masterSeed = ByteUtils.bytesToBuffer(new Uint32Array([1, 1, 1, 1]));
            header.transformSeed = ByteUtils.bytesToBuffer(new Uint32Array([2, 2, 2, 2]));
            header.streamStartBytes = ByteUtils.bytesToBuffer(new Uint32Array([3, 3, 3, 3]));
            header.protectedStreamKey = ByteUtils.bytesToBuffer(new Uint32Array([4, 4, 4, 4]));
            header.encryptionIV = ByteUtils.bytesToBuffer(new Uint32Array([5, 5]));

            const headerStm = new BinaryStream();
            header.write(headerStm);
            const newHeader = KdbxHeader.read(new BinaryStream(headerStm.getWrittenBytes()), ctx);

            expect(newHeader.versionMajor).assertEqual(header.versionMajor);
            expect(newHeader.versionMinor).assertEqual(header.versionMinor);
            expect(newHeader.dataCipherUuid!.toString()).assertEqual(Consts.CipherId.Aes);
            expect(newHeader.crsAlgorithm).assertEqual(Consts.CrsAlgorithm.Salsa20);
            expect(newHeader.compression).assertEqual(Consts.CompressionAlgorithm.GZip);
            expect(newHeader.endPos).assertEqual(headerStm.getWrittenBytes().byteLength);
            expect(ByteUtils.bytesToHex(newHeader.masterSeed!)).assertEqual(
                '01000000010000000100000001000000'
            );
            expect(ByteUtils.bytesToHex(newHeader.transformSeed!)).assertEqual(
                '02000000020000000200000002000000'
            );
            expect(ByteUtils.bytesToHex(newHeader.streamStartBytes!)).assertEqual(
                '03000000030000000300000003000000'
            );
            expect(ByteUtils.bytesToHex(newHeader.protectedStreamKey!)).assertEqual(
                '04000000040000000400000004000000'
            );
            expect(ByteUtils.bytesToHex(newHeader.encryptionIV!)).assertEqual('0500000005000000');
            expect(newHeader.kdfParameters).assertEqual(undefined);
            expect(newHeader.publicCustomData).assertEqual(undefined);
        });

        it('writes and reads header v4',  0,async () => {
            const kdbx = new Kdbx();
            kdbx.binaries = new KdbxBinaries();
            kdbx.binaries.addWithNextId(new Uint8Array([1, 2]));
            kdbx.binaries.addWithNextId(ProtectedValue.fromBinary(new Uint8Array([1, 2, 3]).buffer));
            await kdbx.binaries.computeHashes();

            const header = KdbxHeader.create();
            expect(header.versionMajor).assertEqual(4);
            header.masterSeed = ByteUtils.bytesToBuffer(new Uint32Array([1, 1, 1, 1]));
            header.transformSeed = ByteUtils.bytesToBuffer(new Uint32Array([2, 2, 2, 2]));
            header.streamStartBytes = ByteUtils.bytesToBuffer(new Uint32Array([3, 3, 3, 3]));
            header.protectedStreamKey = ByteUtils.bytesToBuffer(new Uint32Array([4, 4, 4, 4]));
            header.encryptionIV = ByteUtils.bytesToBuffer(new Uint32Array([5, 5]));
            header.kdfParameters!.set('S', ValueType.Bytes, new Uint32Array([6, 6, 6, 6]).buffer);
            header.publicCustomData = new VarDictionary();
            header.publicCustomData.set('custom', ValueType.String, 'val');

            const headerStm = new BinaryStream();
            const innerHeaderStm = new BinaryStream();
            header.write(headerStm);
            header.writeInnerHeader(innerHeaderStm, new KdbxContext({ kdbx }));

            const newKdbx = new Kdbx();
            newKdbx.binaries = new KdbxBinaries();
            const newHeader = KdbxHeader.read(
                new BinaryStream(headerStm.getWrittenBytes()),
                new KdbxContext({ kdbx: newKdbx })
            );

            expect(newHeader.versionMajor).assertEqual(header.versionMajor);
            expect(newHeader.versionMinor).assertEqual(header.versionMinor);
            expect(newHeader.dataCipherUuid!.toString()).assertEqual(Consts.CipherId.Aes);
            expect(newHeader.crsAlgorithm).assertEqual(undefined);
            expect(newHeader.compression).assertEqual(Consts.CompressionAlgorithm.GZip);
            expect(newHeader.endPos).assertEqual(headerStm.getWrittenBytes().byteLength);
            expect(ByteUtils.bytesToHex(newHeader.masterSeed!)).assertEqual(
                '01000000010000000100000001000000'
            );
            expect(newHeader.transformSeed).assertEqual(undefined);
            expect(newHeader.streamStartBytes).assertEqual(undefined);
            expect(newHeader.protectedStreamKey).assertEqual(undefined);
            expect(ByteUtils.bytesToHex(newHeader.encryptionIV!)).assertEqual('0500000005000000');
            expect(newHeader.kdfParameters!.length).assertEqual(6);
            expect(ByteUtils.bytesToBase64(newHeader.kdfParameters!.get('$UUID') as ArrayBuffer)).assertEqual(
                Consts.KdfId.Argon2
            );
            expect(ByteUtils.bytesToHex(newHeader.kdfParameters!.get('S') as ArrayBuffer)).assertEqual(
                '06000000060000000600000006000000'
            );
            expect(newHeader.kdfParameters!.get('P')).assertEqual(1);
            expect(newHeader.kdfParameters!.get('V')).assertEqual(0x13);
            expect((newHeader.kdfParameters!.get('I') as Int64).value).assertEqual(2);
            expect((newHeader.kdfParameters!.get('M') as Int64).value).assertEqual(1024 * 1024);
            expect(newHeader.publicCustomData!.length).assertEqual(1);
            expect(newHeader.publicCustomData!.get('custom')).assertEqual('val');
            expect(newKdbx.binaries.getAll()).assertDeepEquals([]);

            newHeader.readInnerHeader(
                new BinaryStream(innerHeaderStm.getWrittenBytes()),
                new KdbxContext({ kdbx: newKdbx })
            );

            await newKdbx.binaries.computeHashes();

            expect(newHeader.crsAlgorithm).assertEqual(Consts.CrsAlgorithm.ChaCha20);
            expect(ByteUtils.bytesToHex(newHeader.protectedStreamKey!)).assertEqual(
                '04000000040000000400000004000000'
            );

            const oldBinaries = kdbx.binaries.getAll();
            const newBinaries = newKdbx.binaries.getAll();
            expect(newBinaries.length).assertEqual(2);
            expect(newBinaries[0].ref).assertEqual('0');
            expects(newBinaries[0].value).assertInstanceOf(ArrayBuffer);
            expect(ByteUtils.bytesToHex(newBinaries[0].value as ArrayBuffer)).assertEqual(
                ByteUtils.bytesToHex(oldBinaries[0].value as ArrayBuffer)
            );
            expect(newBinaries[1].ref).assertEqual('1');
            expects(newBinaries[1].value).assertInstanceOf(ProtectedValue);
            expect(ByteUtils.bytesToHex((newBinaries[1].value as ProtectedValue).getBinary())).assertEqual(
                ByteUtils.bytesToHex((oldBinaries[1].value as ProtectedValue).getBinary())
            );
        });

        it('generates salts v3', 0,() => {
            const header = new KdbxHeader();
            header.versionMajor = 3;
            header.generateSalts();

            expect(header.masterSeed).not().assertNull();
            expect(header.masterSeed!.byteLength).assertEqual(32);
            expect(header.transformSeed).not().assertNull();
            expect(header.transformSeed!.byteLength).assertEqual(32);
            expect(header.streamStartBytes).not().assertNull();
            expect(header.streamStartBytes!.byteLength).assertEqual(32);
            expect(header.protectedStreamKey).not().assertNull();
            expect(header.protectedStreamKey!.byteLength).assertEqual(32);
            expect(header.encryptionIV).not().assertNull();
            expect(header.encryptionIV!.byteLength).assertEqual(16);
        });

        it('generates salts v4', 0,() => {
            const header = new KdbxHeader();
            header.versionMajor = 4;
            header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
            header.kdfParameters = new VarDictionary();
            header.generateSalts();

            expect(header.protectedStreamKey).not().assertNull();
            expect(header.protectedStreamKey!.byteLength).assertEqual(64);
            expect(header.kdfParameters.get('S')).not().assertNull();
            expect((header.kdfParameters.get('S') as ArrayBuffer).byteLength).assertEqual(32);
            expect(header.encryptionIV).not().assertNull();
            expect(header.encryptionIV!.byteLength).assertEqual(12);

            header.dataCipherUuid = new KdbxUuid(Consts.CipherId.Aes);
            header.generateSalts();
            expect(header.encryptionIV!.byteLength).assertEqual(16);
        });

        it('skips binaries for v3', 0, async () => {
            const kdbx = new Kdbx();
            await kdbx.binaries.add(new Uint8Array([1]));
            await kdbx.binaries.computeHashes();
            const ctx = new KdbxContext({ kdbx });
            const header = KdbxHeader.create();
            header.setVersion(3);
            const stm = new BinaryStream();
            // @ets-ignore
            (header as ESObject).writeBinary(stm, ctx);
            expect(stm.pos).assertEqual(0);
        });

        it('writes header without public custom data', 0, async () => {
            const kdbx = new Kdbx();
            await kdbx.binaries.add(new Uint8Array([1]));
            await kdbx.binaries.computeHashes();
            const ctx = new KdbxContext({ kdbx });
            const header = KdbxHeader.create();
            header.setVersion(KdbxHeader.MaxFileVersion);
            header.generateSalts();
            let stm = new BinaryStream();
            header.write(stm);
            header.writeInnerHeader(stm, ctx);

            stm = new BinaryStream(stm.getWrittenBytes());
            const newHeader = KdbxHeader.read(stm, ctx);
            newHeader.readInnerHeader(stm, ctx);
            expect(newHeader.publicCustomData).assertEqual(undefined);
        });

        it('validates header cipher with dataCipherUuid', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(KdbxHeader.MaxFileVersion);
            header.generateSalts();
            header.dataCipherUuid = undefined;
            expects(() => {
                header.write(new BinaryStream());
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no cipher in header');
            });
        });

        it('validates header cipher with compression', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(KdbxHeader.MaxFileVersion);
            header.generateSalts();
            header.compression = undefined;
            expects(() => {
                header.write(new BinaryStream());
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no compression in header');
            });
        });

        it('validates master seed cipher', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(KdbxHeader.MaxFileVersion);
            header.generateSalts();
            header.masterSeed = undefined;
            expects(() => {
                header.write(new BinaryStream());
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no master seed in header');
            });
        });

        it('validates header encryption iv', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(KdbxHeader.MaxFileVersion);
            header.generateSalts();
            header.encryptionIV = undefined;
            expects(() => {
                header.write(new BinaryStream());
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no encryption iv in header');
            });
        });

        it('validates header kdf parameters', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(KdbxHeader.MaxFileVersion);
            header.generateSalts();
            header.kdfParameters = undefined;
            expects(() => {
                header.write(new BinaryStream());
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no kdf parameters in header');
            });
        });

        it('validates header transform seed', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(3);
            header.generateSalts();
            header.transformSeed = undefined;
            expects(() => {
                header.write(new BinaryStream());
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no transform seed in header');
            });
        });

        it('validates header key encryption rounds', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(3);
            header.generateSalts();
            header.keyEncryptionRounds = undefined;
            expects(() => {
                header.write(new BinaryStream());
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no key encryption rounds in header');
            });
        });

        it('validates header protected stream key', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(3);
            header.generateSalts();
            header.protectedStreamKey = undefined;
            expects(() => {
                header.write(new BinaryStream());
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no protected stream key in header');
            });
        });

        it('validates header stream start bytes', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(3);
            header.generateSalts();
            header.streamStartBytes = undefined;
            expects(() => {
                header.write(new BinaryStream());
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no stream start bytes in header');
            });
        });

        it('validates header crs algorithm', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(3);
            header.generateSalts();
            header.crsAlgorithm = undefined;
            expects(() => {
                header.write(new BinaryStream());
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no crs algorithm in header');
            });
        });

        it('validates inner header protected straem key', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(KdbxHeader.MaxFileVersion);
            header.generateSalts();
            header.protectedStreamKey = undefined;
            expects(() => {
                header.writeInnerHeader(new BinaryStream(), new KdbxContext({ kdbx }));
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no protected stream key in header');
            });
        });

        it('validates inner header crs algorithm', 0,() => {
            const header = KdbxHeader.create();
            header.setVersion(KdbxHeader.MaxFileVersion);
            header.generateSalts();
            header.crsAlgorithm = undefined;
            expects(() => {
                header.writeInnerHeader(new BinaryStream(), new KdbxContext({ kdbx }));
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('no crs algorithm in header');
            });
        });

        it('throws error for bad signature', 0,() => {
            expects(() => {
                KdbxHeader.read(
                    new BinaryStream(ByteUtils.bytesToBuffer(ByteUtils.hexToBytes('0000000000000000'))),
                    new KdbxContext({ kdbx })
                );
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.BadSignature);
            });
        });

        it('throws error for bad version', 0,() => {
            expects(() => {
                KdbxHeader.read(
                    new BinaryStream(ByteUtils.bytesToBuffer(ByteUtils.hexToBytes('03d9a29a67fb4bb501000500'))),
                    new KdbxContext({ kdbx })
                );
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.InvalidVersion);
            });
        });

        it('throws error for bad cipher', 0,() => {
            expects(() => {
                KdbxHeader.read(
                    new BinaryStream(
                        ByteUtils.bytesToBuffer(ByteUtils.hexToBytes('03d9a29a67fb4bb501000400020100000031c1f2e6bf'))
                    ),
                    new KdbxContext({ kdbx })
                );
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.Unsupported);
                expect(e.message).assertContain('cipher');
            });
        });

        it('throws error for bad compression flags', 0,() => {
            expects(() => {
                KdbxHeader.read(
                    new BinaryStream(
                        ByteUtils.bytesToBuffer(ByteUtils.hexToBytes('03d9a29a67fb4bb5010004000320000000011111111'))
                    ),
                    new KdbxContext({ kdbx })
                );
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.Unsupported);
                expect(e.message).assertContain('compression');
            });
        });

        it('throws error for empty files', 0,() => {
            expects(() => {
                KdbxHeader.read(new BinaryStream(new ArrayBuffer(0)), new KdbxContext({ kdbx }));
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect(e.message).assertContain('not enough data');
            });
        });

        it('throws error for bad version in setVersion', 0,() => {
            const header = KdbxHeader.create();
            expects(() => {
                header.setVersion(2);
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
            });
        });

        it('throws error for bad KDF in setKdf', 0,() => {
            const header = KdbxHeader.create();
            expects(() => {
                header.setKdf('unknown');
            }).assertThrowError((e:KdbxError) => {
                expect(e.code).assertEqual(Consts.ErrorCodes.InvalidArg);
            });
        });
    });
}

