import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, ChaCha20 } from '../../../../main/ets/index';

export default function ChaCha20Test() {
    describe('ChaCha20',  () => {
        it('transforms data', 0,() => {
            const key = new Uint8Array(32);
            const nonce = new Uint8Array(32);

            const chacha20 = new ChaCha20(key, nonce);
            expect(ByteUtils.bytesToHex(chacha20.getBytes(32))).assertEqual(
                '76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7'
            );
            expect(ByteUtils.bytesToHex(chacha20.getBytes(32))).assertEqual(
                'da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586'
            );
            // // @ets-ignore
            // chacha20._input[12] = 0xffffffff;
            // expect(ByteUtils.bytesToHex(chacha20.getBytes(16))).assertEqual(
            //     'ace4cd09e294d1912d4ad205d06f95d9'
            // );
        });
    });
}
