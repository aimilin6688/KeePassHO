import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, Consts, HashedBlockTransform, Kdbx, KdbxError } from '../../../../main/ets/index';

export default function HashedBlockTransformTest() {
  describe('HashedBlockTransform', () => {
    it('decrypts and encrypts data', 0, () => {
      const src = new Uint8Array([1, 2, 3, 4, 5]);
      return HashedBlockTransform.encrypt(src.buffer).then((enc) => {
        return HashedBlockTransform.decrypt(enc).then((dec) => {
          expect(ByteUtils.arrayBufferEquals(dec, src)).assertTrue();
        });
      });
    });

    it('decrypts several blocks', 0, () => {
      const src = new Uint8Array(1024 * 1024 * 2 + 2);
      for (let i = 0; i < src.length; i++) {
        src[i] = i % 256;
      }
      return HashedBlockTransform.encrypt(src.buffer).then((enc) => {
        return HashedBlockTransform.decrypt(enc).then((dec) => {
          expect(ByteUtils.bytesToBase64(dec)).assertEqual(ByteUtils.bytesToBase64(src));
        });
      });
    });

    it('throws error for invalid hash block', 0, () => {
      const src = new Uint8Array([1, 2, 3, 4, 5]);
      return HashedBlockTransform.encrypt(src.buffer).then((enc) => {
        new Uint8Array(enc)[4] = 0;
        return HashedBlockTransform.decrypt(enc)
          .then(() => {
            throw new Error('We should not get here');
          })
          .catch((e:Error) => {
            expect(e instanceof KdbxError).assertTrue();
            expect((e as KdbxError).code).assertEqual(Consts.ErrorCodes.FileCorrupt);
          });
      });
    });
  });
}



