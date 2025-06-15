import { describe, expect, it } from '@ohos/hypium';
import { Int64 } from '../../../../main/ets/index';

describe('Int64', () => {
    it('creates empty int64', 0,() => {
        const i = new Int64();
        expect(i.hi).assertEqual(0);
        expect(i.lo).assertEqual(0);
        expect(i.value).assertEqual(0);
        expect(i.valueOf()).assertEqual(0);
    });

    it('creates int64 with low part', 0,() => {
        const i = new Int64(0x123);
        expect(i.hi).assertEqual(0);
        expect(i.lo).assertEqual(0x123);
        expect(i.value).assertEqual(0x123);
        expect(i.valueOf()).assertEqual(0x123);
    });

    it('creates int64 with low and high parts', 0,() => {
        const i = new Int64(0x123, 0x456);
        expect(i.hi).assertEqual(0x456);
        expect(i.lo).assertEqual(0x123);
        expect(i.value).assertEqual(0x45600000123);
        expect(i.valueOf()).assertEqual(0x45600000123);
    });

    it('creates int64 with large value', 0,() => {
        const i = Int64.from(0x45600000123);
        expect(i.hi).assertEqual(0x456);
        expect(i.lo).assertEqual(0x123);
        expect(i.value).assertEqual(0x45600000123);
        expect(i.valueOf()).assertEqual(0x45600000123);
    });

    it('throws error for too high number conversion', 0,() => {
        const i = new Int64(0xffffffff, 0xffffffff);
        expect(() => i.value).to.throwException((e) => {
            expect(e.message).assertEqual('too large number');
        });
    });

    it('throws error for too high number creation', 0,() => {
        expect(() => {
            // eslint-disable-next-line no-loss-of-precision
            Int64.from(0xffffffffffffff);
        }).to.throwException((e) => {
            expect(e.message).assertEqual('too large number');
        });
    });
});
