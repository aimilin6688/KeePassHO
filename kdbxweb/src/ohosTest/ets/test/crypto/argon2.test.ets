import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, CryptoEngine } from '../../../../main/ets/index';

export default function Argon2Test() {
    describe('Argon2', () => {
        it('calculates Argon2d hash', 0, async () => {
            const password = ByteUtils.stringToBytes('password');
            const salt = ByteUtils.stringToBytes('somesalt');
            const result = await CryptoEngine.argon2(
                ByteUtils.arrayToBuffer(password),
                ByteUtils.arrayToBuffer(salt),
                1024,  // memory cost in KB
                2,     // iterations
                32,    // hash length
                1,     // parallelism
                CryptoEngine.Argon2TypeArgon2d,
                0x13   // version
            );

            // Known test vector for Argon2d
            expect(ByteUtils.bytesToHex(new Uint8Array(result))).assertEqual(
                'ed6969800b5e64101404df1fb029419aa8c02b4c25654ae59f655a8b581424ab'
            );
        });

        it('calculates Argon2id hash', 0, async () => {
            const password = ByteUtils.stringToBytes('password');
            const salt = ByteUtils.stringToBytes('somesalt');
            const result = await CryptoEngine.argon2(
                ByteUtils.arrayToBuffer(password),
                ByteUtils.arrayToBuffer(salt),
                1024,  // memory cost in KB
                2,     // iterations
                32,    // hash length
                1,     // parallelism
                CryptoEngine.Argon2TypeArgon2id,
                0x13   // version
            );

            // Known test vector for Argon2id
            expect(ByteUtils.bytesToHex(new Uint8Array(result))).assertEqual(
                'ec57ec9c0eaf51eeea2e92ffdcaa9cdee478f1927215b515b7b8d66657f41ed9'
            );
        });

        it('produces consistent results', 0, async () => {
            const password = ByteUtils.stringToBytes('testpassword');
            const salt = ByteUtils.stringToBytes('testsalt');

            const result1 = await CryptoEngine.argon2(
                ByteUtils.arrayToBuffer(password),
                ByteUtils.arrayToBuffer(salt),
                1024,
                2,
                32,
                1,
                CryptoEngine.Argon2TypeArgon2d,
                0x13,
            );

            const result2 = await CryptoEngine.argon2(
                ByteUtils.arrayToBuffer(password),
                ByteUtils.arrayToBuffer(salt),
                1024,
                2,
                32,
                1,
                CryptoEngine.Argon2TypeArgon2d,
                0x13,
            );

            expect(ByteUtils.bytesToHex(new Uint8Array(result1))).assertEqual(
                ByteUtils.bytesToHex(new Uint8Array(result2))
            );
        });

        it('works with different versions', 0, async () => {
            const password = ByteUtils.stringToBytes('password');
            const salt = ByteUtils.stringToBytes('somesalt');

            // Version 0x10
            const result1 = await CryptoEngine.argon2(
                ByteUtils.arrayToBuffer(password),
                ByteUtils.arrayToBuffer(salt),
                1024,
                2,
                32,
                1,
                CryptoEngine.Argon2TypeArgon2d,
                0x10
            );

            // Version 0x13
            const result2 = await CryptoEngine.argon2(
                ByteUtils.arrayToBuffer(password),
                ByteUtils.arrayToBuffer(salt),
                1024,
                2,
                32,
                1,
                CryptoEngine.Argon2TypeArgon2d,
                0x13
            );

            // Results should be different for different versions
            expect(ByteUtils.bytesToHex(new Uint8Array(result1))).not().assertEqual(
                ByteUtils.bytesToHex(new Uint8Array(result2))
            );
        });

        it('works with different parameters', 0, async () => {
            const password = ByteUtils.stringToBytes('password');
            const salt = ByteUtils.stringToBytes('somesalt');

            // More memory
            const result1 = await CryptoEngine.argon2(
                ByteUtils.arrayToBuffer(password),
                ByteUtils.arrayToBuffer(salt),
                2048,  // 2MB
                2,
                32,
                1,
                CryptoEngine.Argon2TypeArgon2d,
                0x13
            );

            // More iterations
            const result2 = await CryptoEngine.argon2(
                ByteUtils.arrayToBuffer(password),
                ByteUtils.arrayToBuffer(salt),
                1024,
                4,    // 4 iterations
                32,
                1,
                CryptoEngine.Argon2TypeArgon2d,
                0x13
            );

            // More parallelism
            const result3 = await CryptoEngine.argon2(
                ByteUtils.arrayToBuffer(password),
                ByteUtils.arrayToBuffer(salt),
                1024,
                2,
                32,
                2,    // 2 threads
                CryptoEngine.Argon2TypeArgon2d,
                0x13
            );

            // Different output length
            const result4 = await CryptoEngine.argon2(
                ByteUtils.arrayToBuffer(password),
                ByteUtils.arrayToBuffer(salt),
                1024,
                2,
                64,   // 64 bytes output
                1,
                CryptoEngine.Argon2TypeArgon2d,
                0x13
            );

            // All results should be different
            const hex1 = ByteUtils.bytesToHex(new Uint8Array(result1));
            const hex2 = ByteUtils.bytesToHex(new Uint8Array(result2));
            const hex3 = ByteUtils.bytesToHex(new Uint8Array(result3));
            const hex4 = ByteUtils.bytesToHex(new Uint8Array(result4));

            expect(hex1).not().assertEqual(hex2);
            expect(hex1).not().assertEqual(hex3);
            expect(hex1).not().assertEqual(hex4);
            expect(hex2).not().assertEqual(hex3);
            expect(hex2).not().assertEqual(hex4);
            expect(hex3).not().assertEqual(hex4);

            // Length check
            expect(new Uint8Array(result4).length).assertEqual(64);
        });
    });
}
