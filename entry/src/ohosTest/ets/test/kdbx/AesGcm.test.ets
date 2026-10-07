import { describe, expect, it } from '@ohos/hypium';
import { AesGcm, CryptoEngine, KdbxError } from 'kdbxweb';

/**
 * 生成确定性测试数据（非随机，便于逐字节比对）
 */
function makePatternData(length: number): Uint8Array {
  const arr = new Uint8Array(length);
  for (let i = 0; i < length; i++) {
    arr[i] = i % 251;
  }
  return arr;
}

function makeRandomData(length: number): Uint8Array {
  const arr = new Uint8Array(length);
  let seed = 0x12345678;
  for (let i = 0; i < length; i++) {
    seed ^= seed << 13;
    seed ^= seed >>> 17;
    seed ^= seed << 5;
    arr[i] = seed & 0xff;
  }
  return arr;
}

function bytesEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.byteLength !== b.byteLength) {
    return false;
  }
  for (let i = 0; i < a.byteLength; i++) {
    if (a[i] !== b[i]) {
      return false;
    }
  }
  return true;
}

/**
 * 公共原生 AES-256-GCM（AesGcm）单元测试：
 * 一次性 seal/open 往返（含空缓冲与 >4MB 大缓冲）、封包布局与随机 nonce、
 * 篡改/错钥/截断拒绝、流式会话与一次性语义等价
 */
export default function AesGcmTest() {
  describe('AesGcmTest', () => {
    it('seal and open roundtrip preserves content', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const data = makePatternData(1024);
      const sealed = AesGcm.seal(key, data);
      const plain = AesGcm.open(key, sealed);
      expect(bytesEqual(plain, data)).assertTrue();
    });

    it('seal and open roundtrip handles empty buffer', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const sealed = AesGcm.seal(key, new Uint8Array(0));
      // 空明文封包 = nonce(12) + 密文(0) + tag(16)
      expect(sealed.byteLength).assertEqual(AesGcm.NONCE_LENGTH + AesGcm.AUTH_TAG_LENGTH);
      const plain = AesGcm.open(key, sealed);
      expect(plain.byteLength).assertEqual(0);
    });

    it('seal and open roundtrip handles multi-chunk large buffer', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const data = makeRandomData(4 * 1024 * 1024 + 12345);
      const sealed = AesGcm.seal(key, data);
      const plain = AesGcm.open(key, sealed);
      expect(bytesEqual(plain, data)).assertTrue();
    });

    it('seal layout is nonce + cipher + tag and nonce is random', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const data = makePatternData(2048);
      const sealed = AesGcm.seal(key, data);
      expect(sealed.byteLength).assertEqual(
        AesGcm.NONCE_LENGTH + data.byteLength + AesGcm.AUTH_TAG_LENGTH
      );
      const sealed2 = AesGcm.seal(key, data);
      // 随机 nonce：两次封包首 12 字节（nonce）不同，密文也不同
      let nonceEqual = true;
      for (let i = 0; i < AesGcm.NONCE_LENGTH; i++) {
        if (sealed[i] !== sealed2[i]) {
          nonceEqual = false;
          break;
        }
      }
      expect(nonceEqual).assertFalse();
      expect(bytesEqual(sealed, sealed2)).assertFalse();
      // 同一密钥下两次封包均可正确解密
      expect(bytesEqual(AesGcm.open(key, sealed), data)).assertTrue();
      expect(bytesEqual(AesGcm.open(key, sealed2), data)).assertTrue();
    });

    it('open rejects tampered ciphertext', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const data = makePatternData(4096);
      const sealed = AesGcm.seal(key, data);
      sealed[AesGcm.NONCE_LENGTH + 100] ^= 0xff;
      let thrown = false;
      try {
        AesGcm.open(key, sealed);
      } catch (e) {
        thrown = true;
      }
      expect(thrown).assertTrue();
    });

    it('open rejects tampered authTag', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const data = makePatternData(4096);
      const sealed = AesGcm.seal(key, data);
      sealed[sealed.byteLength - 1] ^= 0xff;
      let thrown = false;
      try {
        AesGcm.open(key, sealed);
      } catch (e) {
        thrown = true;
      }
      expect(thrown).assertTrue();
    });

    it('open rejects wrong key', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const otherKey = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const sealed = AesGcm.seal(key, makePatternData(4096));
      let thrown = false;
      try {
        AesGcm.open(otherKey, sealed);
      } catch (e) {
        thrown = true;
      }
      expect(thrown).assertTrue();
    });

    it('open rejects sealed data shorter than nonce plus tag', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const short = makePatternData(AesGcm.NONCE_LENGTH + AesGcm.AUTH_TAG_LENGTH - 1);
      let thrown = false;
      try {
        AesGcm.open(key, short);
      } catch (e) {
        expect(e instanceof KdbxError).assertTrue();
        thrown = true;
      }
      expect(thrown).assertTrue();
    });

    it('seal and session factories validate key nonce and tag lengths', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const badKey = CryptoEngine.random(AesGcm.KEY_LENGTH - 1);
      const nonce = CryptoEngine.random(AesGcm.NONCE_LENGTH);
      const badNonce = CryptoEngine.random(AesGcm.NONCE_LENGTH - 1);
      const tag = CryptoEngine.random(AesGcm.AUTH_TAG_LENGTH);
      const badTag = CryptoEngine.random(AesGcm.AUTH_TAG_LENGTH - 1);

      let thrown = 0;
      try {
        AesGcm.seal(badKey, new Uint8Array(16));
      } catch (e) {
        expect(e instanceof KdbxError).assertTrue();
        thrown++;
      }
      try {
        AesGcm.openEncryptSession(key, badNonce);
      } catch (e) {
        expect(e instanceof KdbxError).assertTrue();
        thrown++;
      }
      try {
        AesGcm.openDecryptSession(key, nonce, badTag);
      } catch (e) {
        expect(e instanceof KdbxError).assertTrue();
        thrown++;
      }
      expect(thrown).assertEqual(3);
    });

    it('streaming sessions are equivalent to one-shot seal and open', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const nonce = CryptoEngine.random(AesGcm.NONCE_LENGTH);
      const data = makeRandomData(1024 * 1024 + 777);

      // 分块加密（非对齐块边界，验证会话状态跨块连续）
      const enc = AesGcm.openEncryptSession(key, nonce);
      const cipher = new Uint8Array(data.byteLength);
      const boundaries = [0, 1, 4097, 300000, data.byteLength];
      let offset = 0;
      for (let i = 1; i < boundaries.length; i++) {
        const chunk = data.subarray(boundaries[i - 1], boundaries[i]);
        const out = enc.update(chunk);
        expect(out.byteLength).assertEqual(chunk.byteLength);
        cipher.set(out, offset);
        offset += chunk.byteLength;
      }
      expect(offset).assertEqual(data.byteLength);
      const tag = enc.finalize();
      expect(tag.byteLength).assertEqual(AesGcm.AUTH_TAG_LENGTH);

      // 流式产物按 [nonce][cipher][tag] 组装后与一次性 open 语义一致
      const sealed = new Uint8Array(
        AesGcm.NONCE_LENGTH + cipher.byteLength + AesGcm.AUTH_TAG_LENGTH
      );
      sealed.set(nonce, 0);
      sealed.set(cipher, AesGcm.NONCE_LENGTH);
      sealed.set(tag, AesGcm.NONCE_LENGTH + cipher.byteLength);
      expect(bytesEqual(AesGcm.open(key, sealed), data)).assertTrue();

      // 分块解密与一次性解密语义一致
      const dec = AesGcm.openDecryptSession(key, nonce, tag);
      const plain = new Uint8Array(data.byteLength);
      offset = 0;
      for (let i = 1; i < boundaries.length; i++) {
        const chunk = cipher.subarray(boundaries[i - 1], boundaries[i]);
        const out = dec.update(chunk);
        expect(out.byteLength).assertEqual(chunk.byteLength);
        plain.set(out, offset);
        offset += chunk.byteLength;
      }
      dec.finalize();
      expect(bytesEqual(plain, data)).assertTrue();
    });

    it('streaming decrypt session rejects tampered chunk', 0, () => {
      const key = CryptoEngine.random(AesGcm.KEY_LENGTH);
      const nonce = CryptoEngine.random(AesGcm.NONCE_LENGTH);
      const data = makePatternData(8192);

      const enc = AesGcm.openEncryptSession(key, nonce);
      const cipher = enc.update(data);
      const tag = enc.finalize();
      cipher[cipher.byteLength - 1] ^= 0xff;

      const dec = AesGcm.openDecryptSession(key, nonce, tag);
      dec.update(cipher.subarray(0, 4096));
      dec.update(cipher.subarray(4096));
      let thrown = false;
      try {
        dec.finalize();
      } catch (e) {
        thrown = true;
      }
      expect(thrown).assertTrue();
    });
  });
}
