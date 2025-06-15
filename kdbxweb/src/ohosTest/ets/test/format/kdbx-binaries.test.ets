import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, KdbxBinaries, ProtectedValue } from '../../../../main/ets/index';


export default function KdbxBinariesTest() {

    describe('KdbxBinaries', () => {
        const protectedBinary = ProtectedValue.fromBinary(new TextEncoder().encode('bin'));
        const protectedBinary2 = ProtectedValue.fromBinary(new TextEncoder().encode('another'));
        const hash = '51a1f05af85e342e3c849b47d387086476282d5f50dc240c19216d6edfb1eb5a';
        const hash2 = 'ae448ac86c4e8e4dec645729708ef41873ae79c6dff84eff73360989487f08e5';

        describe('add', () => {
            it('adds a ProtectedValue', 0, async () => {
                const binaries = new KdbxBinaries();
                const bin = await binaries.add(protectedBinary);
                expect(bin).to.be.ok();
                expect(bin.hash).assertEqual(hash);
                expect(binaries.getAllWithHashes()).to.eql([{ hash, value: protectedBinary }]);
            });

            it('adds an ArrayBuffer',  0,async () => {
                const binaries = new KdbxBinaries();
                const ab = ByteUtils.arrayToBuffer(protectedBinary.getBinary());
                const bin = await binaries.add(ab);
                expect(bin).to.be.ok();
                expect(bin.hash).assertEqual(hash);
                expect(binaries.getAllWithHashes()).to.eql([{ hash, value: ab }]);
            });

            it('adds an Uint8Array',  0,async () => {
                const binaries = new KdbxBinaries();
                const arr = protectedBinary.getBinary();
                const bin = await binaries.add(arr);
                expect(bin).to.be.ok();
                expect(bin.hash).assertEqual(hash);
                expect(binaries.getAllWithHashes()).to.eql([{ hash, value: arr.buffer }]);
            });
        });

        describe('addWithNextId', () => {
            it('adds a binary and generates id',  0,async () => {
                const binaries = new KdbxBinaries();
                binaries.addWithNextId(protectedBinary);
                binaries.addWithNextId(protectedBinary2);

                await binaries.computeHashes();

                const found1 = binaries.getByRef({ ref: '0' });
                expect(found1).to.be.ok();
                expect(found1!.hash).assertEqual(hash);

                const found2 = binaries.getByRef({ ref: '1' });
                expect(found2).to.be.ok();
                expect(found2!.hash).assertEqual(hash2);

                const notFound = binaries.getByRef({ ref: '2' });
                expect(notFound).assertEqual(undefined);
            });
        });

        describe('addWithId', () => {
            it('adds a binary with the specified id', 0, async () => {
                const binaries = new KdbxBinaries();
                binaries.addWithId('0', protectedBinary);
                binaries.addWithId('0', protectedBinary2);

                await binaries.computeHashes();

                const found2 = binaries.getByRef({ ref: '0' });
                expect(found2).to.be.ok();
                expect(found2!.hash).assertEqual(hash2);

                const notFound = binaries.getByRef({ ref: '1' });
                expect(notFound).assertEqual(undefined);
            });
        });

        describe('addWithHash', () => {
            it('adds a binary with the specified hash', 0,() => {
                const binaries = new KdbxBinaries();
                binaries.addWithHash({ hash, value: protectedBinary });

                expect(binaries.getAllWithHashes()).to.eql([{ hash, value: protectedBinary }]);
            });
        });

        describe('deleteWithHash', () => {
            it('adds a binary with the specified hash', 0,() => {
                const binaries = new KdbxBinaries();
                binaries.addWithHash({ hash, value: protectedBinary });
                binaries.addWithHash({ hash: hash2, value: protectedBinary2 });
                binaries.deleteWithHash(hash2);

                expect(binaries.getAllWithHashes()).to.eql([{ hash, value: protectedBinary }]);
            });
        });

        describe('getByRef', () => {
            it('returns a binary by reference', 0, async () => {
                const binaries = new KdbxBinaries();
                binaries.addWithNextId(protectedBinary);
                binaries.addWithNextId(protectedBinary2);

                await binaries.computeHashes();

                binaries.deleteWithHash(hash2);

                const found1 = binaries.getByRef({ ref: '0' });
                expect(found1).to.be.ok();
                expect(found1!.hash).assertEqual(hash);

                expect(binaries.getByRef({ ref: '1' })).assertEqual(undefined);
                expect(binaries.getByRef({ ref: '2' })).assertEqual(undefined);
            });
        });

        describe('get...', () => {
            it('gets a reference by hash', 0, async () => {
                const binaries = new KdbxBinaries();
                binaries.addWithNextId(protectedBinary);
                binaries.addWithNextId(protectedBinary2);

                await binaries.computeHashes();

                const ref1 = binaries.getRefByHash(hash);
                expect(ref1).to.be.ok();
                expect(ref1?.ref).assertEqual('0');

                const ref2 = binaries.getRefByHash(hash2);
                expect(ref2).to.be.ok();
                expect(ref2?.ref).assertEqual('1');

                const refNotExisting = binaries.getRefByHash('boo');
                expect(refNotExisting).assertEqual(undefined);

                const all = binaries.getAll();
                expect(all).to.eql([
                    { ref: '0', value: protectedBinary },
                    { ref: '1', value: protectedBinary2 }
                ]);

                const allWithHashes = binaries.getAllWithHashes();
                expect(allWithHashes).to.eql([
                    { hash, value: protectedBinary },
                    { hash: hash2, value: protectedBinary2 }
                ]);

                expect(binaries.getValueByHash(hash)).assertEqual(protectedBinary);
                expect(binaries.getValueByHash(hash2)).assertEqual(protectedBinary2);
                expect(binaries.getValueByHash('boo')).assertEqual(undefined);
            });
        });

        describe('isKdbxBinaryRef', () => {
            it('returns true for KdbxBinaryRef', 0,() => {
                const isRef = KdbxBinaries.isKdbxBinaryRef({ ref: '1' });
                expect(isRef).assertEqual(true);
            });

            it('returns false for a ProtectedValue', 0,() => {
                const isRef = KdbxBinaries.isKdbxBinaryRef(protectedBinary);
                expect(isRef).assertEqual(false);
            });

            it('returns false for undefined', 0,() => {
                const isRef = KdbxBinaries.isKdbxBinaryRef(undefined);
                expect(isRef).assertEqual(false);
            });
        });

        describe('isKdbxBinaryWithHash', () => {
            it('returns true for KdbxBinaryWithHash', 0,() => {
                const isRef = KdbxBinaries.isKdbxBinaryWithHash({ ref: '1', hash });
                expect(isRef).assertEqual(true);
            });

            it('returns false for KdbxBinaryRef', 0,() => {
                const isRef = KdbxBinaries.isKdbxBinaryWithHash({ ref: '1' });
                expect(isRef).assertEqual(false);
            });

            it('returns false for a ProtectedValue', 0,() => {
                const isRef = KdbxBinaries.isKdbxBinaryWithHash(protectedBinary);
                expect(isRef).assertEqual(false);
            });

            it('returns false for undefined', 0,() => {
                const isRef = KdbxBinaries.isKdbxBinaryWithHash(undefined);
                expect(isRef).assertEqual(false);
            });
        });
    });
}


