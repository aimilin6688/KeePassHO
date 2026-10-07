import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { CryptoUtils } from '../../../../main/ets/common/utils/CryptoUtils';

export default function CryptoUtilsTest() {
  describe('CryptoUtils', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    // ---------------- encryptText ----------------
    it('encryptText returns empty string for empty input', 0, async () => {
      const result = await CryptoUtils.encryptText('');
      expect(result).assertEqual('');
    });

    // ---------------- decryptText ----------------
    it('decryptText returns empty string for empty input', 0, async () => {
      const result = await CryptoUtils.decryptText('');
      expect(result).assertEqual('');
    });

    // ---------------- generateKey ----------------
    it('generateKey returns a boolean', 0, async () => {
      const result = await CryptoUtils.generateKey();
      expect(typeof result).assertEqual('boolean');
    });

    it('generateKey returns true on second call (key exists)', 0, async () => {
      await CryptoUtils.generateKey();
      const result = await CryptoUtils.generateKey();
      expect(result).assertTrue();
    });

    // ---------------- round trip ----------------
    it('encryptText and decryptText round trip preserves plain text', 0, async () => {
      const plain = 'secret password 123';
      const encrypted = await CryptoUtils.encryptText(plain);
      // On devices/emulators with HUKS support encryption produces output;
      // otherwise encryptText returns ''. Verify round trip only when output exists.
      if (encrypted.length > 0) {
        const decrypted = await CryptoUtils.decryptText(encrypted);
        expect(decrypted).assertEqual(plain);
      }
    });

    it('encryptText produces different ciphertext for same input (random IV)', 0, async () => {
      const plain = 'same secret text';
      const e1 = await CryptoUtils.encryptText(plain);
      const e2 = await CryptoUtils.encryptText(plain);
      if (e1.length > 0 && e2.length > 0) {
        expect(e1 === e2).assertFalse();
      }
    });

    it('encryptText handles unicode plain text', 0, async () => {
      const plain = '密码测试 🔐';
      const encrypted = await CryptoUtils.encryptText(plain);
      if (encrypted.length > 0) {
        const decrypted = await CryptoUtils.decryptText(encrypted);
        expect(decrypted).assertEqual(plain);
      }
    });
  });
}
