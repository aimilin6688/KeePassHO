import { describe, expect, it } from '@ohos/hypium';
import { HashUtils } from '../../../../main/ets/common/utils/HashUtils';

function stringToArrayBuffer(input: string): ArrayBuffer {
  const bytes: Uint8Array = new Uint8Array(input.length);
  for (let i = 0; i < input.length; i++) {
    bytes[i] = input.charCodeAt(i) & 0xff;
  }
  return bytes.buffer;
}

function bytesToArrayBuffer(bytes: number[]): ArrayBuffer {
  const view: Uint8Array = new Uint8Array(bytes.length);
  for (let i = 0; i < bytes.length; i++) {
    view[i] = bytes[i];
  }
  return view.buffer;
}

export default function HashUtilsTest() {
  describe('HashUtilsTest', () => {
    // ---------------- sha256Hex known vectors ----------------
    // sha256HexFile/sha256Hex cross-consistency is covered by
    // HashUtilsFileTest; this suite pins sha256Hex to known SHA-256 vectors.
    it('sha256Hex of empty buffer matches empty SHA256 vector', 0, () => {
      const hex = HashUtils.sha256Hex(new ArrayBuffer(0));
      expect(hex).assertEqual('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    it('sha256Hex of "abc" matches FIPS vector', 0, () => {
      const hex = HashUtils.sha256Hex(stringToArrayBuffer('abc'));
      expect(hex).assertEqual('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });

    it('sha256Hex of "hello" matches known vector', 0, () => {
      const hex = HashUtils.sha256Hex(stringToArrayBuffer('hello'));
      expect(hex).assertEqual('2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
    });

    it('sha256Hex of single zero byte matches known vector', 0, () => {
      const hex = HashUtils.sha256Hex(bytesToArrayBuffer([0x00]));
      expect(hex).assertEqual('6e340b9cffb37a989ca544e6bb780a2c78901d3fb33738768511a30617afa01d');
    });

    // ---------------- output format ----------------
    it('sha256Hex returns 64 lowercase hex characters', 0, () => {
      const hex = HashUtils.sha256Hex(stringToArrayBuffer('format-check'));
      expect(hex.length).assertEqual(64);
      expect(/^[0-9a-f]{64}$/.test(hex)).assertTrue();
    });

    // ---------------- determinism / sensitivity ----------------
    it('sha256Hex is deterministic for the same input', 0, () => {
      const data = stringToArrayBuffer('deterministic-input');
      expect(HashUtils.sha256Hex(data)).assertEqual(HashUtils.sha256Hex(data));
    });

    it('sha256Hex differs for different inputs', 0, () => {
      const hexA = HashUtils.sha256Hex(stringToArrayBuffer('input-a'));
      const hexB = HashUtils.sha256Hex(stringToArrayBuffer('input-b'));
      expect(hexA !== hexB).assertTrue();
    });

    it('sha256Hex differs when a single byte changes', 0, () => {
      const hexA = HashUtils.sha256Hex(bytesToArrayBuffer([0x01, 0x02, 0x03]));
      const hexB = HashUtils.sha256Hex(bytesToArrayBuffer([0x01, 0x02, 0x04]));
      expect(hexA !== hexB).assertTrue();
    });
  });
}
