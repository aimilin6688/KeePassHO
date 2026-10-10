import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, ChaCha20 } from '../../../../main/ets/index';
import { setNativeChaCha20Enabled } from '../../../../main/ets/crypto/chacha20-native';

/** 确定性伪随机数据（xorshift32），保证 JS/native 两次运行输入完全一致 */
function makeData(length: number): Uint8Array {
    const data = new Uint8Array(length);
    let seed = 0x12345678;
    for (let i = 0; i < length; i++) {
        seed ^= seed << 13;
        seed ^= seed >>> 17;
        seed ^= seed << 5;
        data[i] = seed & 0xff;
    }
    return data;
}

/**
 * 混合调用序列（半块读 / 跨块 xorInPlace / getBytes 续读 / 一次性 encrypt / encrypt 后续写），
 * 返回全部输出拼接 hex，用于 JS 与原生路径的字节级等价校验。
 * 开关在构造前切换（_useNative 构造期决定），finally 恢复避免影响后续测试套件。
 */
function runMixedSequence(nativeEnabled: boolean): string {
    const key = makeData(32);
    const nonce = makeData(12);
    setNativeChaCha20Enabled(nativeEnabled);
    let result = '';
    try {
        const chacha = new ChaCha20(key, nonce);
        result += ByteUtils.bytesToHex(chacha.getBytes(48));
        const chunk1 = makeData(100);
        chacha.xorInPlace(chunk1);
        result += ByteUtils.bytesToHex(chunk1);
        result += ByteUtils.bytesToHex(chacha.getBytes(64));
        const chunk2 = makeData(63);
        chacha.xorInPlace(chunk2);
        result += ByteUtils.bytesToHex(chunk2);
        result += ByteUtils.bytesToHex(chacha.encrypt(makeData(200)));
        result += ByteUtils.bytesToHex(chacha.getBytes(1));
        const chunk3 = makeData(65);
        chacha.xorInPlace(chunk3);
        result += ByteUtils.bytesToHex(chunk3);
    } finally {
        setNativeChaCha20Enabled(true);
    }
    return result;
}

/** RFC 向量明文为纯 ASCII */
function asciiToBytes(text: string): Uint8Array {
    const data = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) {
        data[i] = text.charCodeAt(i);
    }
    return data;
}

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

        it('rfc7539 2.4.2 keystream at counter 1', 0, () => {
            const key = ByteUtils.hexToBytes('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
            const nonce = ByteUtils.hexToBytes('000000090000004a00000000');
            const chacha = new ChaCha20(key, nonce);
            // 构造 API 无初始 counter 参数，丢弃首块推进到 counter=1
            chacha.getBytes(64);
            expect(ByteUtils.bytesToHex(chacha.getBytes(64))).assertEqual(
                '10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e' +
                'd2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e'
            );
        });

        it('rfc7539 2.4.2 sunscreen encrypt and decrypt', 0, () => {
            // §2.4.2 加密示例（key 同 2.4.2 向量，nonce=000000000000004a00000000，counter=1）
            const key = ByteUtils.hexToBytes('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
            const nonce = ByteUtils.hexToBytes('000000000000004a00000000');
            const plaintext = asciiToBytes(
                "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
            );
            expect(plaintext.length).assertEqual(114);

            const encryptor = new ChaCha20(key, nonce);
            encryptor.getBytes(64); // counter → 1
            const encrypted = encryptor.encrypt(plaintext);
            expect(ByteUtils.bytesToHex(encrypted)).assertEqual(
                '6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0b' +
                'f91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d8' +
                '07ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab7793736' +
                '5af90bbf74a35be6b40b8eedf2785e42874d'
            );

            // 对称性：同位置再加密一次还原明文
            const decryptor = new ChaCha20(key, nonce);
            decryptor.getBytes(64);
            const decrypted = decryptor.encrypt(encrypted);
            expect(ByteUtils.bytesToHex(decrypted)).assertEqual(ByteUtils.bytesToHex(plaintext));
        });

        it('djb 8-byte nonce equals long nonce prefix', 0, () => {
            // 32 字节 nonce 走 DJB 分支仅取前 8 字节，与显式 8 字节 nonce 输出一致
            const key = new Uint8Array(32);
            const shortNonce = new ChaCha20(key, new Uint8Array(8));
            const stream = shortNonce.getBytes(96);
            const longNonce = new ChaCha20(key, new Uint8Array(32));
            expect(ByteUtils.bytesToHex(stream)).assertEqual(ByteUtils.bytesToHex(longNonce.getBytes(96)));
            // nonce 全零时 DJB 与 RFC 初始状态相同，块 0 即 RFC 7539 §2.3.2 向量
            expect(ByteUtils.bytesToHex(stream.subarray(0, 32))).assertEqual(
                '76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7'
            );
        });

        it('js fallback equals native', 0, () => {
            const nativeResult = runMixedSequence(true);
            const jsResult = runMixedSequence(false);
            expect(jsResult).assertEqual(nativeResult);
        });

        it('chunked xorInPlace equals one-shot encrypt', 0, () => {
            const key = makeData(32);
            const nonce = makeData(12);
            const data = makeData(1000);
            const oneShot = new ChaCha20(key, nonce);
            const expected = oneShot.encrypt(data);

            const chunked = new ChaCha20(key, nonce);
            const sizes: number[] = [1, 63, 64, 65, 300, 507];
            let pos = 0;
            for (let i = 0; i < sizes.length; i++) {
                // 视图分块，同时覆盖原生路径对 Uint8Array view 的处理
                const view = new Uint8Array(data.buffer, pos, sizes[i]);
                chunked.xorInPlace(view);
                pos += sizes[i];
            }
            expect(pos).assertEqual(data.length);
            expect(ByteUtils.bytesToHex(data)).assertEqual(ByteUtils.bytesToHex(expected));
        });

        it('zero-length operations are no-ops and keep stream position', 0, () => {
            // 回归：空 ProtectedValue（如模板条目空密码）经 getSalt(0) 触发 getBytes(0)，
            // 原生路径曾因零长度 typedarray 的 NAPI 空指针报 Uint8Array arguments expected
            const key = makeData(32);
            const nonce = makeData(12);
            const empty = new Uint8Array(0);
            const a = new ChaCha20(key, nonce);
            expect(a.getBytes(0).length).assertEqual(0);
            a.xorInPlace(empty);
            expect(a.encrypt(empty).length).assertEqual(0);
            // 空操作不推进流位置：与全新实例后续输出一致
            const b = new ChaCha20(key, nonce);
            expect(ByteUtils.bytesToHex(a.getBytes(48))).assertEqual(ByteUtils.bytesToHex(b.getBytes(48)));
        });

        it('getBytes continues across blocks', 0, () => {
            const key = makeData(32);
            const nonce = makeData(12);
            const whole = new ChaCha20(key, nonce).getBytes(100);
            const split = new ChaCha20(key, nonce);
            const part1 = split.getBytes(64);
            const part2 = split.getBytes(36);
            expect(ByteUtils.bytesToHex(part1) + ByteUtils.bytesToHex(part2))
                .assertEqual(ByteUtils.bytesToHex(whole));
        });
    });
}
