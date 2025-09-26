import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, ProtectedValue } from '../../../../main/ets/index';

export default function ProtectedValueTest() {
    describe('ProtectedValue', () => {
        const valueBytes = ByteUtils.stringToBytes('strvalue'),
            encValueBytes = ByteUtils.stringToBytes('strvalue'),
            saltBytes = new Uint8Array(valueBytes.length);
        for (let i = 0; i < saltBytes.length; i++) {
            saltBytes[i] = i;
            encValueBytes[i] ^= i;
        }

        it('decrypts salted value in string', 0,() => {
            const value = new ProtectedValue(ByteUtils.bytesToBuffer(encValueBytes), ByteUtils.bytesToBuffer(saltBytes));
            expect(value.getText()).assertEqual('strvalue');
        });

        it('returns string in binary', 0,() => {
            const value = new ProtectedValue(ByteUtils.bytesToBuffer(encValueBytes), ByteUtils.bytesToBuffer(saltBytes));
            expect(value.getBinary()).assertDeepEquals(valueBytes);
        });

        it('checks substring', 0,() => {
            const value = new ProtectedValue(ByteUtils.bytesToBuffer(encValueBytes), ByteUtils.bytesToBuffer(saltBytes));
            expect(value.includes('test')).assertEqual(false);
            expect(value.includes('str')).assertEqual(true);
            expect(value.includes('val')).assertEqual(true);
            expect(value.includes('value')).assertEqual(true);
            expect(value.includes('')).assertEqual(false);
        });

        it('calculates SHA512 hash', 0,() => {
            const value = new ProtectedValue(ByteUtils.bytesToBuffer(encValueBytes), ByteUtils.bytesToBuffer(saltBytes));
            return value.getHash().then((hash) => {
                expect(ByteUtils.bytesToHex(hash)).assertEqual(
                    '1f5c3ef76d43e72ee2c5216c36187c799b153cab3d0cb63a6f3ecccc2627f535'
                );
            });
        });

        it('creates value from string', 0,() => {
            const value = ProtectedValue.fromString('test');
            expect(value.getText()).assertEqual('test');
        });

        it('creates value from binary', 0,() => {
            const value = ProtectedValue.fromBinary(ByteUtils.stringToBytes('test'));
            expect(value.getText()).assertEqual('test');
        });

        it('returns byte length', 0,() => {
            const value = ProtectedValue.fromBinary(ByteUtils.stringToBytes('test'));
            expect(value.byteLength).assertEqual(4);
        });

        it('can change salt', 0,() => {
            const value = ProtectedValue.fromString('test');
            expect(value.getText()).assertEqual('test');
            value.setSalt(new Uint8Array([1, 2, 3, 4]).buffer);
            expect(value.getText()).assertEqual('test');
        });

        it('returns protected value as base64 string', 0,() => {
            const value = ProtectedValue.fromBinary(ByteUtils.stringToBytes('test'));
            value.setSalt(new Uint8Array([1, 2, 3, 4]).buffer);
            expect(value.toString()).assertEqual('dWdwcA==');
        });

        it('clones itself', 0,() => {
            const value = ProtectedValue.fromString('test').clone();
            expect(value.getText()).assertEqual('test');
        });

        it('creates a value from base64', 0,() => {
            const value = ProtectedValue.fromBase64('aGVsbG8=');
            expect(value.getText()).assertEqual('hello');
        });

        it('returns base64 of the value', 0,() => {
            const value = ProtectedValue.fromString('hello');
            expect(value.toBase64()).assertEqual('aGVsbG8=');
        });
    });
}

