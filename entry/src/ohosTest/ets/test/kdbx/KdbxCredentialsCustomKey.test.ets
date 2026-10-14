import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, KdbxCredentials, ProtectedValue } from 'kdbxweb';

/**
 * KdbxCredentials customKey（自定义密钥分量，KeePass KcpCustomKey 等价）单元测试。
 *
 * 语义对齐 KeePass2Android PasswordActivity.CreateCompositeKey：
 * - KcpCustomKey(name, secret, true)：KeyData = SHA-256(secret)
 * - CompositeKey.CreateRawCompositeKey32：按 password → keyfile → customKey → challenge 顺序拼接
 *   （KP2A 中 OTP/KeeChallenge secret 均以 bPerformHash=true 加入，且位于 keyfile 之后）
 *
 * 期望向量由独立 SHA-256 链计算得出（node crypto 校验）。
 */
export default function KdbxCredentialsCustomKeyTest() {
  describe('KdbxCredentialsCustomKey', () => {
    it('customKey only: hash = SHA256(SHA256(customKey))', 0, async () => {
      const cred = new KdbxCredentials(null, null, undefined, new Uint8Array(32).fill(3));
      const hash = await cred.getHash();
      expect(ByteUtils.bytesToHex(hash)).assertEqual(
        'f517c428914b046c432b1d1927ac580d60e8b70d328c84c1b8c43231d8871721'
      );
      expect(cred.customKeyHash).not().assertNull();
      expect(ByteUtils.bytesToHex(cred.customKeyHash!.getBinary())).assertEqual(
        '648aa5c579fb30f38af744d97d6ec840c7a91277a499a0d780f3e7314eca090b'
      );
    });

    it('password + customKey: hash = SHA256(SHA256(pw) || SHA256(customKey))', 0, async () => {
      const cred = new KdbxCredentials(
        ProtectedValue.fromString('test'),
        null,
        undefined,
        new Uint8Array(32).fill(3)
      );
      const hash = await cred.getHash();
      expect(ByteUtils.bytesToHex(hash)).assertEqual(
        '89f0e9a585052c047d768a5cc7df32a5383d3d4790b3793f145e3068197bbd2d'
      );
    });

    it('password + 20-byte otp-like secret (KcpCustomKey hashed semantics)', 0, async () => {
      const cred = new KdbxCredentials(
        ProtectedValue.fromString('test'),
        null,
        undefined,
        new Uint8Array(20).fill(7)
      );
      const hash = await cred.getHash();
      expect(ByteUtils.bytesToHex(hash)).assertEqual(
        '9c6328ee84abb68e7dc09c4a55e3173745cb024d7d3e50cb44822cb4dd02e8f6'
      );
    });

    it('all components: password + keyfile + challengeResponse + customKey', 0, async () => {
      const cred = new KdbxCredentials(
        ProtectedValue.fromString('test'),
        new Uint8Array(32).fill(1),
        (challenge: ArrayBuffer) => Promise.resolve(challenge),
        new Uint8Array(32).fill(3)
      );
      const hash = await cred.getHash(new Uint8Array(32).fill(2).buffer);
      expect(ByteUtils.bytesToHex(hash)).assertEqual(
        '31504908a53171b6de4606855772c0f6b758b45c5fb63af86e1dd589a1905c7d'
      );
    });

    it('setCustomKey accepts ArrayBuffer and can be cleared', 0, async () => {
      const cred = new KdbxCredentials(ProtectedValue.fromString('test'));
      await cred.ready;
      expect(cred.customKeyHash).assertUndefined();

      await cred.setCustomKey(new Uint8Array(32).fill(3).buffer as ArrayBuffer);
      expect(cred.customKeyHash).not().assertNull();
      const withKey = await cred.getHash();
      expect(ByteUtils.bytesToHex(withKey)).assertEqual(
        '89f0e9a585052c047d768a5cc7df32a5383d3d4790b3793f145e3068197bbd2d'
      );

      await cred.setCustomKey(null);
      expect(cred.customKeyHash).assertUndefined();
      const cleared = await cred.getHash();
      expect(ByteUtils.bytesToHex(cleared)).assertEqual(
        '954d5a49fd70d9b8bcdb35d252267829957f7ef7fa6c74f88419bdc5e82209f4'
      );
    });
  });
}
