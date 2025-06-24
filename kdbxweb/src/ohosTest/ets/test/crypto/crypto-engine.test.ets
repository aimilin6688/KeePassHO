import { describe, expect, it, afterEach} from '@ohos/hypium';
import { ByteUtils, CryptoEngine } from '../../../../main/ets/index';
import hilog from '@ohos.hilog';

// const isNode = !!global.process?.versions?.node;
const  isNode = true;

function fromHex(str: string) {
    return ByteUtils.arrayToBuffer(ByteUtils.hexToBytes(str));
}

function toHex(bytes: ArrayBuffer) {
    if (!(bytes instanceof ArrayBuffer)) {
        throw new Error('Not ArrayBuffer');
    }
    return ByteUtils.bytesToHex(bytes);
}

function useDefaultImpl() {
    // if (isNode) {
    //     // @ets-ignore
    //     global.crypto = undefined;
    // }
}

function useSubtleMock() {
    // if (isNode) {
    //     // @ets-ignore
    //     global.crypto = require('../test-support/subtle-mock-node').SubtleMockNode;
    // }
}

export default function CryptoEngineTest() {
    describe('CryptoEngine', () => {
        afterEach(useDefaultImpl);

        describe('sha256', () => {
            const src = 'f03f102fa66d1847535a85ffc09c3911d1d56887c451832448df3cbac293be4b';
            const exp = 'affa378dae878f64d10f302df67c614ebb901601dd53a51713ffe664850c833b';
            const expEmpty = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';

            it('calculates sha256', 0,() => {
                useDefaultImpl();
                return CryptoEngine.sha256(fromHex(src)).then((hash) => {
                    hilog.info(1,  'test', 'hash:%s', toHex(hash));
                    expect(toHex(hash)).assertEqual(exp);
                });
            });

            it('calculates sha256 test', 0,() => {
                useDefaultImpl();
                return CryptoEngine.sha256(ByteUtils.stringToBuffer("test")).then((hash) => {
                    hilog.info(1,  'test', 'hash:%s', ByteUtils.bytesToString(hash));
                    expect(toHex(hash)).assertEqual('9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08');
                });
            });

            it('calculates sha256 of empty data', 0,() => {
                useDefaultImpl();
                return CryptoEngine.sha256(new ArrayBuffer(0)).then((hash) => {
                    expect(toHex(hash)).assertEqual(expEmpty);
                });
            });

            if (isNode) {
                it('calculates sha256 with subtle', 0, () => {
                    useSubtleMock();
                    return CryptoEngine.sha256(fromHex(src)).then((hash) => {
                        expect(toHex(hash)).assertEqual(exp);
                    });
                });
            }
        });

        describe('sha512', () => {
            const src = 'f03f102fa66d1847535a85ffc09c3911d1d56887c451832448df3cbac293be4b';
            const exp =
                '8425338d314de7b33d2be207494bd10335c543b9e354ed9316400bf86ecca4b8' +
                    '707b22e3a7f3f32b1b0e83793137f5cdbff4c5cfd331ca66dc4887a10594257f';
            const expEmpty =
                'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce' +
                    '47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e';

            it('calculates sha512', 0,() => {
                useDefaultImpl();
                return CryptoEngine.sha512(fromHex(src)).then((hash) => {
                    expect(toHex(hash)).assertEqual(exp);
                });
            });

            it('calculates sha512 of empty data', 0,() => {
                useDefaultImpl();
                return CryptoEngine.sha512(new ArrayBuffer(0)).then((hash) => {
                    expect(toHex(hash)).assertEqual(expEmpty);
                });
            });

            if (isNode) {
                it('calculates sha512 with subtle', 0,() => {
                    useSubtleMock();
                    return CryptoEngine.sha512(fromHex(src)).then((hash) => {
                        expect(toHex(hash)).assertEqual(exp);
                    });
                });
            }
        });

        describe('hmacSha256', () => {
            const data = '14af83cb4ecb6e1773a0ff0fa607e2e96a43dbeeade61291c52ab3853b1dda9d';
            const key = 'c50d2f8d0d51ba443ec46f7f843bf17491b8c0a09b58437acd589b14b73aa35c';
            const exp = 'f25a33a0424440b91d98cb4d9c0e897ff0a1f48c78820e6374257cf7fa774fb2';

            it('calculates hmac-sha256', 0,() => {
                useDefaultImpl();
                return CryptoEngine.hmacSha256(fromHex(key), fromHex(data)).then((hash) => {
                    expect(toHex(hash)).assertEqual(exp);
                });
            });

            if (isNode) {
                it('calculates hmac-sha256 with subtle', 0,() => {
                    useSubtleMock();
                    return CryptoEngine.hmacSha256(fromHex(key), fromHex(data)).then((hash) => {
                        expect(toHex(hash)).assertEqual(exp);
                    });
                });
            }
        });

        describe('random', () => {
            it('fills random bytes', 0,() => {
                useDefaultImpl();
                const rand1 = CryptoEngine.random(20);
                expect(rand1.length).assertEqual(20);
                const rand2 = CryptoEngine.random(20);
                expect(rand2.length).assertEqual(20);
                expect(ByteUtils.arrayBufferEquals(rand1, rand2)).assertEqual(false);
                const rand3 = CryptoEngine.random(10);
                expect(rand3.length).assertEqual(10);
            });

            it('can fill more than 65536 bytes', 0,() => {
                useDefaultImpl();
                const rand1 = CryptoEngine.random(77111);
                expect(rand1.length).assertEqual(77111);
            });

            if (isNode) {
                it('generates random bytes with subtle', 0,() => {
                    useSubtleMock();
                    const rand1 = CryptoEngine.random(20);
                    expect(rand1.length).assertEqual(20);
                });

                it('can fill more than 65536 bytes', 0,() => {
                    useSubtleMock();
                    const rand1 = CryptoEngine.random(77111);
                    expect(rand1.length).assertEqual(77111);
                });
            }
        });

        describe('AesCbc', () => {
            const key = '6b2796fa863a6552986c428528d053b76de7ba8e12f8c0e74edb5ed44da3f601';
            const data = 'e567554429098a38d5f819115edffd39';
            const iv = '4db46dff4add42cb813b98de98e627c4';
            const exp = '46ab4c37d9ec594e5742971f76f7c1620bc29f2e0736b27832d6bcc5c1c39dc1';

            it('encrypts-decrypts with aes-cbc', 0,() => {
                useDefaultImpl();
                const aes = CryptoEngine.createAesCbc();
                return aes.importKey(fromHex(key)).then(() => {
                    return aes.encrypt(fromHex(data), fromHex(iv)).then((result) => {
                        expect(toHex(result)).assertEqual(exp);
                        console.log("data------------------------->", toHex(result));
                        return aes.decrypt(result, fromHex(iv)).then((result) => {
                            console.log('decrypted data:', toHex(result));
                            expect(toHex(result)).assertEqual(data);
                        });
                    });
                });
            });

            it('throws error or generates wrong data for bad key', 0,() => {
                useDefaultImpl();
                const aes = CryptoEngine.createAesCbc();
                return aes.importKey(fromHex(key)).then(() => {
                    return aes
                        .decrypt(fromHex(data), fromHex(iv))
                        .then((result) => {
                            expect(toHex(result)).not().assertEqual(data);
                        })
                        .catch((e:Error) => {
                            expect(e.message).assertContain('Error InvalidKey: ');
                        });
                });
            });

            it('throws if key is not set', 0, async () => {
                useDefaultImpl();
                const aes = CryptoEngine.createAesCbc();
                try {
                    await aes.encrypt(new ArrayBuffer(0), new ArrayBuffer(0));
                } catch (e) {
                    expect((e as Error).message).assertContain('no key');
                    return;
                }
                throw new Error('Not expected');
            });

            if (isNode) {
                it('encrypts-decrypts with aes-cbc with subtle', 0,() => {
                    useSubtleMock();
                    const aes = CryptoEngine.createAesCbc();
                    return aes.importKey(fromHex(key)).then(() => {
                        return aes.encrypt(fromHex(data), fromHex(iv)).then((result) => {
                            expect(toHex(result)).assertEqual(exp);
                            return aes.decrypt(result, fromHex(iv)).then((result) => {
                                expect(toHex(result)).assertEqual(data);
                            });
                        });
                    });
                });

                it('throws error for bad key', 0,() => {
                    useSubtleMock();
                    const aes = CryptoEngine.createAesCbc();
                    return aes.importKey(fromHex(key)).then(() => {
                        return aes
                            .decrypt(fromHex(data), fromHex(iv))
                            .then((result) => {
                                expect(toHex(result)).not().assertEqual(data);
                            })
                            .then(() => {
                                throw  new Error('Not expected');
                            })
                            .catch((e:Error) => {
                                expect(e.message.indexOf('Not expected')).not().assertEqual(-1);
                            });
                    });
                });

                it('throws if key is not set',0, async () => {
                    useSubtleMock();
                    const aes = CryptoEngine.createAesCbc();
                    try {
                        await aes.encrypt(new ArrayBuffer(0), new ArrayBuffer(0));
                    } catch (e) {
                        expect((e as Error).message).assertContain('no key');
                        return;
                    }
                    throw new Error('Not expected');
                });
            }
        });

        describe('chacha20', () => {
            const key = '6b2796fa863a6552986c428528d053b76de7ba8e12f8c0e74edb5ed44da3f601';
            const data = 'e567554429098a38d5f819115edffd39';
            const iv12 = '4db46dff4add42cb813b98de';
            const exp12 = 'd0b413d0e71dd55db9ce29ed092724d1';
            const iv8 = '4db46dff4add42cb';
            const exp8 = 'ebaee4b6790192fd6e60f6294ea12c98';

            it('encrypts with chacha20', 0,() => {
                useDefaultImpl();
                return CryptoEngine.chacha20(
                    ByteUtils.hexToBytes(data),
                    ByteUtils.hexToBytes(key),
                    ByteUtils.hexToBytes(iv12)
                ).then((result) => {
                    expect(toHex(result)).assertEqual(exp12);
                });
            });

            it('encrypts with short iv', 0,() => {
                useDefaultImpl();
                return CryptoEngine.chacha20(
                    ByteUtils.hexToBytes(data),
                    ByteUtils.hexToBytes(key),
                    ByteUtils.hexToBytes(iv8)
                ).then((result) => {
                    expect(toHex(result)).assertEqual(exp8);
                });
            });
        });
    });
}


