import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, Consts, ProtectSaltGenerator } from '../../../../main/ets/index';

describe('ProtectSaltGenerator', () => {
    it('generates random sequences with Salsa20', 0,() => {
        return ProtectSaltGenerator.create(
            new Uint8Array([1, 2, 3]),
            Consts.CrsAlgorithm.Salsa20
        ).then((gen) => {
            let bytes = gen.getSalt(0);
            expect(bytes.byteLength).assertEqual(0);
            bytes = gen.getSalt(10);
            expect(ByteUtils.bytesToBase64(bytes)).assertEqual('q1l4McuyQYDcDg==');
            bytes = gen.getSalt(10);
            expect(ByteUtils.bytesToBase64(bytes)).assertEqual('LJTKXBjqlTS8cg==');
            bytes = gen.getSalt(20);
            expect(ByteUtils.bytesToBase64(bytes)).assertEqual('jKVBKKNUnieRr47Wxh0YTKn82Pw=');
        });
    });

    it('generates random sequences with ChaCha20', 0,() => {
        return ProtectSaltGenerator.create(
            new Uint8Array([1, 2, 3]),
            Consts.CrsAlgorithm.ChaCha20
        ).then((gen) => {
            let bytes = gen.getSalt(0);
            expect(bytes.byteLength).assertEqual(0);
            bytes = gen.getSalt(10);
            expect(ByteUtils.bytesToBase64(bytes)).assertEqual('iUIv7m2BJN2ubQ==');
            bytes = gen.getSalt(10);
            expect(ByteUtils.bytesToBase64(bytes)).assertEqual('BILRgZKxaxbRzg==');
            bytes = gen.getSalt(20);
            expect(ByteUtils.bytesToBase64(bytes)).assertEqual('KUeBUGjNBYhAoJstSqnMXQwuD6E=');
        });
    });

    it('fails if the algorithm is not supported', 0,() => {
        return ProtectSaltGenerator.create(new Uint8Array(0), 0)
            .then(() => {
                throw 'Not expected';
            })
            .catch((e) => {
                expect(e.message).to.contain('Unsupported: crsAlgorithm');
            });
    });
});
