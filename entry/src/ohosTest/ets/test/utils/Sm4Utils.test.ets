import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { Sm4Utils } from '../../../../main/ets/common/utils/Sm4Utils';

export default function Sm4UtilsTest() {
  describe('Sm4Utils', () => {
    beforeAll(() => {});
    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    it('encrypt returns empty string for empty input', 0, () => {
      expect(Sm4Utils.encrypt('')).assertEqual('');
    });

    it('decrypt returns empty string for empty input', 0, () => {
      expect(Sm4Utils.decrypt('')).assertEqual('');
    });

    it('encryptWithPrefix returns empty string for empty input', 0, () => {
      expect(Sm4Utils.encryptWithPrefix('')).assertEqual('');
    });

    it('decryptWithPrefix returns empty string for empty input', 0, () => {
      expect(Sm4Utils.decryptWithPrefix('')).assertEqual('');
    });

    it('encryptWithPrefix returns original when already prefixed', 0, () => {
      const prefixed = 'SM4:abc123def456';
      expect(Sm4Utils.encryptWithPrefix(prefixed)).assertEqual(prefixed);
    });

    it('decryptWithPrefix returns original when no prefix', 0, () => {
      const plain = 'plain_data_no_prefix';
      expect(Sm4Utils.decryptWithPrefix(plain)).assertEqual(plain);
    });

    it('init resolves without error', 0, async () => {
      await Sm4Utils.init();
      expect(true).assertTrue();
    });

    it('initKey returns non-empty string', 0, () => {
      const key = Sm4Utils.initKey();
      expect(key.length > 0).assertTrue();
    });

    it('initKey is idempotent (returns same key on subsequent calls)', 0, () => {
      const key1 = Sm4Utils.initKey();
      const key2 = Sm4Utils.initKey();
      expect(key1).assertEqual(key2);
    });

    it('encrypt then decrypt round-trips correctly', 0, () => {
      const plaintext = 'hello_sm4_world';
      const encrypted = Sm4Utils.encrypt(plaintext);
      expect(encrypted.length > 0).assertTrue();
      expect(encrypted !== plaintext).assertTrue();
      expect(Sm4Utils.decrypt(encrypted)).assertEqual(plaintext);
    });

    it('encryptWithPrefix then decryptWithPrefix round-trips correctly', 0, () => {
      const plaintext = 'prefix_round_trip_test';
      const encrypted = Sm4Utils.encryptWithPrefix(plaintext);
      expect(encrypted.startsWith('SM4:')).assertTrue();
      expect(encrypted !== plaintext).assertTrue();
      expect(Sm4Utils.decryptWithPrefix(encrypted)).assertEqual(plaintext);
    });

    it('encryptWithPrefix output has SM4:iv:body format and round-trips', 0, () => {
      const plaintext = 'compare_body_test';
      const encPref = Sm4Utils.encryptWithPrefix(plaintext);
      // SM4-CBC uses a random IV per call, so encrypt() and encryptWithPrefix()
      // never produce identical ciphertext bodies for separate calls. Only the
      // format (SM4:iv:body) and decryptability can be asserted.
      const segments: string[] = encPref.split(':');
      expect(segments.length).assertEqual(3);
      expect(segments[0]).assertEqual('SM4');
      expect(segments[1].length > 0).assertTrue();
      expect(segments[2].length > 0).assertTrue();
      expect(Sm4Utils.decryptWithPrefix(encPref)).assertEqual(plaintext);
      // Same body layout as plain encrypt(): stripping the prefix yields a
      // ciphertext that decrypt() accepts.
      expect(Sm4Utils.decrypt(encPref.substring('SM4:'.length))).assertEqual(plaintext);
    });

    it('round-trips unicode and special characters', 0, () => {
      const plaintext = '你好世界！@#$%^&*()_+-=';
      const encrypted = Sm4Utils.encrypt(plaintext);
      expect(Sm4Utils.decrypt(encrypted)).assertEqual(plaintext);
    });

    it('round-trips long string', 0, () => {
      let plaintext = '';
      for (let i = 0; i < 500; i++) {
        plaintext += 'abcdefgh';
      }
      const encrypted = Sm4Utils.encrypt(plaintext);
      expect(encrypted.length > 0).assertTrue();
      expect(Sm4Utils.decrypt(encrypted)).assertEqual(plaintext);
    });

    it('decryptWithPrefix on encryptWithPrefix output returns original', 0, () => {
      const plaintext = 'combined_prefix_flow';
      const encrypted = Sm4Utils.encryptWithPrefix(plaintext);
      const decrypted = Sm4Utils.decryptWithPrefix(encrypted);
      expect(decrypted).assertEqual(plaintext);
    });
  });
}
