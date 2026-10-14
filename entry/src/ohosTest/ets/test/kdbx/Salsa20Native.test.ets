import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils, Salsa20, nativeSalsa20Available, setNativeSalsa20Enabled } from 'kdbxweb';

/**
 * Salsa20 原生路径设备端验证（libkdbxweb_zlib.so 内 salsa20Xor，salsa20.cpp）。
 * 本套件在真实应用测试包（.so 随包）中断言原生路径生效：
 * djb 官方向量（key=0x80||0…0，nonce=0）+ JS/原生字节级等价 + 分块续算 + view 入参 + 零长度边界。
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

export default function Salsa20NativeTest() {
    describe('Salsa20Native', () => {
        it('native salsa20Xor is available', 0, () => {
            expect(nativeSalsa20Available()).assertTrue();
        });

        it('native path matches djb spec vectors', 0, () => {
            const key = new Uint8Array(32);
            key[0] = 0x80;
            const nonce = new Uint8Array(8);
            const state = new Salsa20(key, nonce);
            expect(state.getHexString(64)).assertEqual(
                'e3be8fdd8beca2e3ea8ef9475b29a6e7' +
                '003951e1097a5c38d23b7a5fad9f6844' +
                'b22c97559e2723c7cbbd3fe4fc8d9a07' +
                '44652a83e72a9c461876af4d7ef1a117'
            );
            state.getBytes(128);
            expect(state.getHexString(64)).assertEqual(
                '57be81f47b17d9ae7c4ff15429a73e10' +
                'acf250ed3a90a93c711308a74c6216a9' +
                'ed84cd126da7f28e8abf8bb63517e1ca' +
                '98e712f4fb2e1a6aed9fdc73291faa17'
            );
            expect(state.getHexString(64)).assertEqual(
                '958211c4ba2ebd5838c635edb81f513a' +
                '91a294e194f1c039aeec657dce40aa7e' +
                '7c0af57cacefa40c9f14b71a4b3456a6' +
                '3e162ec7d8d10b8ffb1810d71001b618'
            );
            state.getBytes(128);
            expect(state.getHexString(64)).assertEqual(
                '696afcfd0cddcc83c7e77f11a649d79a' +
                'cdc3354e9635ff137e929933a0bd6f53' +
                '77efa105a3a4266b7c0d089d08f1e855' +
                'cc32b15b93784a36e56a76cc64bc8477'
            );
        });

        it('native equals js across lengths and chunk boundaries', 0, () => {
            const key = makeData(32);
            const nonce = makeData(8);
            const lengths: number[] = [0, 1, 31, 32, 63, 64, 65, 127, 128, 129, 255, 1000];

            setNativeSalsa20Enabled(false);
            let oneShotHex = '';
            const chunkHexes: string[] = [];
            try {
                const jsOneShot = new Salsa20(key, nonce);
                oneShotHex = ByteUtils.bytesToHex(jsOneShot.getBytes(1895));
                const jsChunked = new Salsa20(key, nonce);
                for (let i = 0; i < lengths.length; i++) {
                    chunkHexes.push(ByteUtils.bytesToHex(jsChunked.getBytes(lengths[i])));
                }
            } finally {
                setNativeSalsa20Enabled(true);
            }

            const natOneShot = new Salsa20(key, nonce);
            expect(ByteUtils.bytesToHex(natOneShot.getBytes(1895))).assertEqual(oneShotHex);

            const natChunked = new Salsa20(key, nonce);
            for (let i = 0; i < lengths.length; i++) {
                expect(ByteUtils.bytesToHex(natChunked.getBytes(lengths[i]))).assertEqual(chunkHexes[i]);
            }
        });

        it('native accepts key and nonce views', 0, () => {
            // OtpUtil 场景：key 为 32 字节 view、nonce 取 iv16.subarray(0, 8)
            const keyBuffer = makeData(40);
            const key = new Uint8Array(keyBuffer.buffer, 4, 32);
            const iv16 = makeData(16);
            const nonce = iv16.subarray(0, 8);

            setNativeSalsa20Enabled(false);
            let refHex = '';
            try {
                const jsRef = new Salsa20(key, nonce);
                refHex = ByteUtils.bytesToHex(jsRef.getBytes(200));
            } finally {
                setNativeSalsa20Enabled(true);
            }

            const nativeSalsa = new Salsa20(key, nonce);
            expect(ByteUtils.bytesToHex(nativeSalsa.getBytes(200))).assertEqual(refHex);
        });

        it('native zero-length is no-op and stream continues', 0, () => {
            const key = makeData(32);
            const nonce = makeData(8);
            const a = new Salsa20(key, nonce);
            expect(a.getBytes(0).length).assertEqual(0);
            const b = new Salsa20(key, nonce);
            expect(ByteUtils.bytesToHex(a.getBytes(128))).assertEqual(ByteUtils.bytesToHex(b.getBytes(128)));
        });
    });
}
