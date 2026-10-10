import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, ChaCha20, nativeChaCha20Available } from 'kdbxweb';

/**
 * ChaCha20 原生路径设备端验证（libkdbxweb_zlib.so 内 chacha20Xor，chacha20.cpp）。
 * kdbxweb 侧 chacha20.test.ets 已保证 JS/native 字节级等价；
 * 本套件在真实应用测试包（.so 随包）中断言原生路径生效并复验官方向量。
 */

/** 确定性伪随机数据（xorshift32） */
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

/** RFC 向量明文为纯 ASCII */
function asciiToBytes(text: string): Uint8Array {
    const data = new Uint8Array(text.length);
    for (let i = 0; i < text.length; i++) {
        data[i] = text.charCodeAt(i);
    }
    return data;
}

export default function Chacha20NativeTest() {
    describe('Chacha20Native', () => {
        it('native chacha20Xor is available', 0, () => {
            expect(nativeChaCha20Available()).assertTrue();
        });

        it('native path matches rfc7539 2.3.2 zero vector', 0, () => {
            const chacha = new ChaCha20(new Uint8Array(32), new Uint8Array(32));
            expect(ByteUtils.bytesToHex(chacha.getBytes(32))).assertEqual(
                '76b8e0ada0f13d90405d6ae55386bd28bdd219b8a08ded1aa836efcc8b770dc7'
            );
            expect(ByteUtils.bytesToHex(chacha.getBytes(32))).assertEqual(
                'da41597c5157488d7724e03fb8d84a376a43b8f41518a11cc387b669b2ee6586'
            );
        });

        it('native path matches rfc7539 2.4.2 keystream', 0, () => {
            const key = ByteUtils.hexToBytes('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
            const nonce = ByteUtils.hexToBytes('000000090000004a00000000');
            const chacha = new ChaCha20(key, nonce);
            chacha.getBytes(64); // counter → 1
            expect(ByteUtils.bytesToHex(chacha.getBytes(64))).assertEqual(
                '10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e' +
                'd2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e'
            );
        });

        it('native path matches rfc7539 2.4.2 sunscreen encrypt', 0, () => {
            // §2.4.2 加密示例（key 同 2.4.2 向量，nonce=000000000000004a00000000，counter=1）
            const key = ByteUtils.hexToBytes('000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f');
            const nonce = ByteUtils.hexToBytes('000000000000004a00000000');
            const plaintext = asciiToBytes(
                "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it."
            );
            const encryptor = new ChaCha20(key, nonce);
            encryptor.getBytes(64); // counter → 1
            const encrypted = encryptor.encrypt(plaintext);
            expect(ByteUtils.bytesToHex(encrypted)).assertEqual(
                '6e2e359a2568f98041ba0728dd0d6981e97e7aec1d4360c20a27afccfd9fae0b' +
                'f91b65c5524733ab8f593dabcd62b3571639d624e65152ab8f530c359f0861d8' +
                '07ca0dbf500d6a6156a38e088a22b65e52bc514d16ccf806818ce91ab7793736' +
                '5af90bbf74a35be6b40b8eedf2785e42874d'
            );

            const decryptor = new ChaCha20(key, nonce);
            decryptor.getBytes(64);
            expect(ByteUtils.bytesToHex(decryptor.encrypt(encrypted)))
                .assertEqual(ByteUtils.bytesToHex(plaintext));
        });

        it('native chunked xorInPlace equals one-shot encrypt', 0, () => {
            const key = makeData(32);
            const nonce = makeData(12);
            const data = makeData(1000);
            const oneShot = new ChaCha20(key, nonce);
            const expected = oneShot.encrypt(data);

            const chunked = new ChaCha20(key, nonce);
            const sizes: number[] = [1, 63, 64, 65, 300, 507];
            let pos = 0;
            for (let i = 0; i < sizes.length; i++) {
                const view = new Uint8Array(data.buffer, pos, sizes[i]);
                chunked.xorInPlace(view);
                pos += sizes[i];
            }
            expect(ByteUtils.bytesToHex(data)).assertEqual(ByteUtils.bytesToHex(expected));
        });

        it('native zero-length operations are no-ops', 0, () => {
            // 回归：空 ProtectedValue（如模板条目空密码）经 getSalt(0) 触发 getBytes(0)，
            // 原生路径曾因零长度 typedarray 的 NAPI 空指针报 Uint8Array arguments expected
            const key = makeData(32);
            const nonce = makeData(12);
            const empty = new Uint8Array(0);
            const a = new ChaCha20(key, nonce);
            expect(a.getBytes(0).length).assertEqual(0);
            a.xorInPlace(empty);
            expect(a.encrypt(empty).length).assertEqual(0);
            const b = new ChaCha20(key, nonce);
            expect(ByteUtils.bytesToHex(a.getBytes(48))).assertEqual(ByteUtils.bytesToHex(b.getBytes(48)));
        });
    });
}
