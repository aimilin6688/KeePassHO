import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, Consts, KdbxCredentials, KdbxError, ProtectedValue } from '../../../../main/ets/index';
import { expects } from '../test-support/Asserts';

export default function KdbxCredentialsTest() {
    describe('KdbxCredentials', () => {
        it('calculates hash for null password', 0, async () => {
            const cred = new KdbxCredentials(null);
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
            );
        });

        it('calculates hash for empty password',  0,async () => {
            const cred = new KdbxCredentials(ProtectedValue.fromString(''));
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                '5df6e0e2761359d30a8275058e299fcc0381534545f55cf43e41983f5d4c9456'
            );
        });

        it('calculates hash for test password',  0,async () => {
            const cred = new KdbxCredentials(ProtectedValue.fromString('test'));
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                '954d5a49fd70d9b8bcdb35d252267829957f7ef7fa6c74f88419bdc5e82209f4'
            );
        });

        it('calculates hash for null password and a key file', 0, async () => {
            const cred = new KdbxCredentials(null, new Uint8Array(32).fill(1));
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                '72cd6e8422c407fb6d098690f1130b7ded7ec2f7f5e1d30bd9d521f015363793'
            );
        });

        it('calculates hash for test password and a key file',  0,async () => {
            const cred = new KdbxCredentials(
                ProtectedValue.fromString('test'),
                new Uint8Array(32).fill(1)
            );
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                'e37a11dc890fae6114bbc310a22a5b9bef0d253d4843679b4d76501bb849600e'
            );
        });

        it('calculates hash with challenge-response', 0, async () => {
            const cred = new KdbxCredentials(
                ProtectedValue.fromString('test'),
                new Uint8Array(32).fill(1),
                (challenge) => Promise.resolve(challenge)
            );
            const hash = await cred.getHash(new Uint8Array(32).fill(2).buffer);
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                '8cdc398b5e3906296d8b69f9a88162fa65b46bca0f9ac4024b083411d4a76324'
            );
        });

        it('accepts an array in challenge-response',  0,async () => {
            const cred = new KdbxCredentials(
                ProtectedValue.fromString('test'),
                new Uint8Array(32).fill(1),
                (challenge) => Promise.resolve(new Uint8Array(challenge))
            );
            const hash = await cred.getHash(new Uint8Array(32).fill(2).buffer);
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                '8cdc398b5e3906296d8b69f9a88162fa65b46bca0f9ac4024b083411d4a76324'
            );
        });

        it('calculates hash for a bad xml key file',  0,async () => {
            const keyFile = ByteUtils.stringToBytes('boo');
            const cred = new KdbxCredentials(null, keyFile);
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                '3ab83b7980ccad2dca61dd5f60d306c71d80f2d9856a72e2743d17cbb1c3cbf6'
            );
        });

        it('calculates hash for a plaintext key file',  0,async () => {
            const keyFile = ByteUtils.bytesToBuffer(new Uint8Array(32).fill(1));
            const cred = new KdbxCredentials(null, keyFile);
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                '72cd6e8422c407fb6d098690f1130b7ded7ec2f7f5e1d30bd9d521f015363793'
            );
        });

        it('calculates hash for a hex key file',  0,async () => {
            const keyFile = ByteUtils.stringToBytes(
                'DEADbeef0a0f0212812374283418418237418734873829748917389472314243'
            );
            const cred = new KdbxCredentials(null, keyFile);
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                'cf18a98ff868a7978dddc09861f792e6fe6d13503f4364ae2e1abeef2ba5bfc9'
            );
        });

        it('throws an error for a key file without meta', 0, async () => {
            const keyFile =  ByteUtils.stringToBytes('<KeyFile/>');
            const cred = new KdbxCredentials(null, keyFile);
            try {
                await cred.getHash();
            } catch (e) {
                expects(e).assertInstanceOf(KdbxError);
                expect((e as KdbxError).code).assertEqual(Consts.ErrorCodes.InvalidArg);
                expect((e as KdbxError).message).assertContain('key file without meta');
                return;
            }
            expect().assertFail();
        });

        it('throws an error for a key file without version',  0,async () => {
            const keyFile = ByteUtils.stringToBytes('<data><Meta></Meta></data>');
            const cred = new KdbxCredentials(null, keyFile);
            try {
                await cred.getHash();
            } catch (e) {
                expects(e).assertInstanceOf(KdbxError);
                expect((e as KdbxError).code).assertEqual(Consts.ErrorCodes.InvalidArg);
                expect((e as KdbxError).message).assertContain('key file without version');
                return;
            }
            expect().assertFail();
        });

        it('throws an error for a key file with bad version', 0, async () => {
            const keyFile = ByteUtils.stringToBytes(
                '<KeyFile><Meta><Version>10.0</Version></Meta><Key><Data>00</Data></Key></KeyFile>'
            );
            const cred = new KdbxCredentials(null, keyFile);
            try {
                await cred.getHash();
            } catch (e) {
                expects(e).assertInstanceOf(KdbxError);
                expect((e as KdbxError).code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect((e as KdbxError).message).assertContain('bad keyfile version');
                return;
            }
            expect().assertFail();
        });

        it('throws an error for a key file without key',  0,async () => {
            const keyFile = ByteUtils.stringToBytes(
                '<KeyFile><Meta><Version>1.0</Version></Meta></KeyFile>'
            );
            const cred = new KdbxCredentials(null, keyFile);
            try {
                await cred.getHash();
            } catch (e) {
                expects(e).assertInstanceOf(KdbxError);
                expect((e as KdbxError).code).assertEqual(Consts.ErrorCodes.InvalidArg);
                expect((e as KdbxError).message).assertContain('key file without key');
                return;
            }
            expect().assertFail();
        });

        it('throws an error for a key file without data',  0,async () => {
            const keyFile = ByteUtils.stringToBytes(
                '<KeyFile><Meta><Version>1.0</Version></Meta><Key></Key></KeyFile>'
            );
            const cred = new KdbxCredentials(null, keyFile);
            try {
                await cred.getHash();
            } catch (e) {
                expects(e).assertInstanceOf(KdbxError);
                expect((e as KdbxError).code).assertEqual(Consts.ErrorCodes.InvalidArg);
                expect((e as KdbxError).message).assertContain('key file without key data');
                return;
            }
            expect().assertFail();
        });

        it('calculates hash for a v1 key file',  0,async () => {
            const keyFile = ByteUtils.stringToBytes(
                '<KeyFile><Meta><Version>1.0</Version></Meta><Key><Data>AtY2GR2pVt6aWz2ugfxfSQWjRId9l0JWe/LEMJWVJ1k=</Data></Key></KeyFile>'
            );
            const cred = new KdbxCredentials(null, keyFile);
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                '829bd09b8d05fafaa0e80b7307a978c496931815feb0a5cf82ce872ee36fa355'
            );
        });

        it('calculates hash for a v2 key file',  0,async () => {
            const keyFile = ByteUtils.stringToBytes(
                '<KeyFile><Meta><Version>2.0</Version></Meta><Key><Data Hash="FE2949B8">A7007945 D07D54BA 28DF6434 1B4500FC 9750DFB1 D36ADA2D 9C32DC19 4C7AB01B</Data></Key></KeyFile>'
            );
            const cred = new KdbxCredentials(null, keyFile);
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                'fe2949b83209abdbd99f049b6a0231282b5854214b0b58f5135148f905ad5a95'
            );
        });

        it('throws an error for a v2 key file with bad hash',  0,async () => {
            const keyFile = ByteUtils.stringToBytes(
                '<KeyFile><Meta><Version>2.0</Version></Meta><Key><Data Hash="AABBCCDD">A7007945 D07D54BA 28DF6434 1B4500FC 9750DFB1 D36ADA2D 9C32DC19 4C7AB01B</Data></Key></KeyFile>'
            );
            const cred = new KdbxCredentials(null, keyFile);
            try {
                await cred.getHash();
            } catch (e) {
                expects(e).assertInstanceOf(KdbxError);
                expect((e as KdbxError).code).assertEqual(Consts.ErrorCodes.FileCorrupt);
                expect((e as KdbxError).message).assertContain('key file data hash mismatch');
                return;
            }
            expect().assertFail();
        });

        it('sets passwordHash and keyFileHash',  0,async () => {
            const keyFile = ByteUtils.stringToBytes(
                '<KeyFile><Meta><Version>2.0</Version></Meta><Key><Data Hash="FE2949B8">A7007945 D07D54BA 28DF6434 1B4500FC 9750DFB1 D36ADA2D 9C32DC19 4C7AB01B</Data></Key></KeyFile>'
            );
            const cred = new KdbxCredentials(ProtectedValue.fromString('123'), keyFile);
            const hash = await cred.getHash();
            expect(ByteUtils.bytesToHex(hash)).assertEqual(
                '4ecd13e7ea764ce2909e460864f4d4a513b07f612a1adb013770a40bb1cf77fc'
            );
            expect(cred.passwordHash).not().assertNull();
            expect(cred.keyFileHash).not().assertNull();
            expect(ByteUtils.bytesToHex(cred.passwordHash!.getBinary())).assertEqual(
                'a665a45920422f9d417e4867efdc4fb8a04a1f3fff1fa07e998e86f7f7a27ae3'
            );
            expect(ByteUtils.bytesToHex(cred.keyFileHash!.getBinary())).assertEqual(
                'a7007945d07d54ba28df64341b4500fc9750dfb1d36ada2d9c32dc194c7ab01b'
            );
        });
    });
}



