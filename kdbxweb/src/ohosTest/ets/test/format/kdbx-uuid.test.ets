import { describe, expect, it } from '@ohos/hypium';
import { KdbxUuid } from '../../../../main/ets/index';
export default function KdbxUuidTest() {
    describe('KdbxUuid', () => {
        it('creates uuid from 16 bytes ArrayBuffer', 0,() => {
            const uuid = new KdbxUuid(
                new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1, 2, 3, 4, 5, 6]).buffer
            );
            expect(uuid.id).assertEqual('AQIDBAUGBwgJCgECAwQFBg==');
        });

        it('creates uuid from 16 bytes array', 0,() => {
            const uuid = new KdbxUuid(
                new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1, 2, 3, 4, 5, 6])
            );
            expect(uuid.id).assertEqual('AQIDBAUGBwgJCgECAwQFBg==');
        });

        it('creates uuid base64 string', 0,() => {
            const uuid = new KdbxUuid('AQIDBAUGBwgJCgECAwQFBg==');
            expect(uuid.id).assertEqual('AQIDBAUGBwgJCgECAwQFBg==');
        });

        it('throws an error for less than 16 bytes', 0,() => {
            try {
                const uuid = new KdbxUuid(new Uint16Array([123]).buffer);
                throw new Error(`Expected an error to be thrown, got UUID instead: ${uuid}`);
            } catch (e) {
                expect((e as Error).message).to.contain('FileCorrupt: bad UUID length: 2');
            }
        });

        it('creates empty uuid from undefined', 0,() => {
            const uuid = new KdbxUuid(undefined);
            expect(uuid.id).assertEqual('AAAAAAAAAAAAAAAAAAAAAA==');
            expect(uuid.empty).assertEqual(true);
        });

        it('returns uuid in toString method', 0,() => {
            const uuid = new KdbxUuid(
                new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1, 2, 3, 4, 5, 6]).buffer
            );
            expect(uuid.toString()).assertEqual('AQIDBAUGBwgJCgECAwQFBg==');
        });

        it('returns uuid in valueOf method', 0,() => {
            const uuid = new KdbxUuid(
                new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1, 2, 3, 4, 5, 6]).buffer
            );
            expect(uuid.valueOf()).assertEqual('AQIDBAUGBwgJCgECAwQFBg==');
        });

        it('creates empty uuid from no arg', 0,() => {
            const uuid = new KdbxUuid();
            expect(uuid.toString()).assertEqual('AAAAAAAAAAAAAAAAAAAAAA==');
            expect(uuid.empty).assertEqual(true);
        });

        it('sets empty property for empty uuid', 0,() => {
            const uuid = new KdbxUuid(new Uint8Array(16).buffer);
            expect(uuid.toString()).assertEqual('AAAAAAAAAAAAAAAAAAAAAA==');
            expect(uuid.empty).assertEqual(true);
        });

        it('returns bytes in toBytes method', 0,() => {
            const bytes = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1, 2, 3, 4, 5, 6]);
            const uuid = new KdbxUuid(bytes.buffer);
            expect(uuid.toBytes()).assertDeepEquals(bytes);
        });

        it('returns bytes in bytes property', 0,() => {
            const bytes = new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1, 2, 3, 4, 5, 6]);
            const uuid = new KdbxUuid(bytes.buffer);
            expect(uuid.bytes).assertDeepEquals(bytes);
        });

        it('returns bytes in toBytes method for empty value', 0,() => {
            const uuid = new KdbxUuid();
            expect(uuid.toBytes()).assertDeepEquals([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
        });

        it('generates random uuid', 0,() => {
            const uuid = KdbxUuid.random();
            expect(uuid).to.be.a(KdbxUuid);
            expect(uuid.toString()).not.assertEqual('AAAAAAAAAAAAAAAAAAAAAA==');
        });

        it('checks equality', 0,() => {
            const uuid = new KdbxUuid(
                new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 1, 2, 3, 4, 5, 6]).buffer
            );
            expect(uuid.equals('AQIDBAUGBwgJCgECAwQFBg==')).assertEqual(true);
            expect(uuid.equals(new KdbxUuid('AQIDBAUGBwgJCgECAwQFBg=='))).assertEqual(true);
            expect(uuid.equals(undefined)).assertEqual(false);
            expect(uuid.equals(null)).assertEqual(false);
            expect(uuid.equals('')).assertEqual(false);
            expect(uuid.equals('???')).assertEqual(false);
            expect(uuid.equals(new KdbxUuid())).assertEqual(false);
        });
    });
}

