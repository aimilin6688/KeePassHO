import { describe, expect, it } from '@ohos/hypium';
import { ByteUtils } from '../../../../main/ets/index';

export default function ByteUtilsTest() {
    describe('ByteUtils', () => {
        describe('arrayBufferEquals', () => {
            it('returns true for equal ArrayBuffers', 0,() => {
                const ab1 = new Int8Array([1, 2, 3]).buffer;
                const ab2 = new Int8Array([1, 2, 3]).buffer;
                expect(ByteUtils.arrayBufferEquals(ab1, ab2)).assertEqual(true);
            });

            it('returns false for ArrayBuffers of different length', 0,() => {
                const ab1 = new Int8Array([1, 2, 3]).buffer;
                const ab2 = new Int8Array([1, 2, 3, 4]).buffer;
                expect(ByteUtils.arrayBufferEquals(ab1, ab2)).assertEqual(false);
            });

            it('returns false for different ArrayBuffers', 0,() => {
                const ab1 = new Int8Array([1, 2, 3]).buffer;
                const ab2 = new Int8Array([3, 2, 1]).buffer;
                expect(ByteUtils.arrayBufferEquals(ab1, ab2)).assertEqual(false);
            });
        });

        const str = 'utf8стрƒΩ≈ç√∫˜µ≤æ∆©ƒ∂ß';
        const strBytes = new Uint8Array([
            117, 116, 102, 56, 209, 129, 209, 130, 209, 128, 198, 146, 206, 169, 226, 137, 136, 195,
            167, 226, 136, 154, 226, 136, 171, 203, 156, 194, 181, 226, 137, 164, 195, 166, 226, 136,
            134, 194, 169, 198, 146, 226, 136, 130, 195, 159
        ]);

        describe('bytesToString', () => {
            it('converts Array to string', 0,() => {
                expect(ByteUtils.bytesToString(strBytes)).assertEqual(str);
            });

            it('converts ArrayBuffer to string', 0,() => {
                expect(ByteUtils.bytesToString(strBytes.buffer)).assertEqual(str);
            });
        });

        describe('stringToBytes', () => {
            it('converts string to Array', 0,() => {
                expect(ByteUtils.stringToBytes(str)).assertDeepEquals(strBytes);
            });
        });

        const base64 = 'c3Ry0L/RgNC40LLQtdGC';
        const bytes = new Uint8Array([
            115, 116, 114, 208, 191, 209, 128, 208, 184, 208, 178, 208, 181, 209, 130
        ]);

        describe('base64ToBytes', () => {
            it('converts base64-string to byte array', 0,() => {
                expect(ByteUtils.base64ToBytes(base64)).assertDeepEquals(bytes);
            });

            it('converts base64-string to byte array using Buffer', 0,() => {
                expect(ByteUtils.base64ToBytes(base64)).assertDeepEquals(bytes);
            });
        });

        describe('bytesToBase64', () => {
            it('converts byte array to base64-string', 0,() => {
                expect(ByteUtils.bytesToBase64(bytes)).assertDeepEquals(base64);
            });

            it('converts ArrayBuffer base64-string', 0,() => {
                expect(ByteUtils.bytesToBase64(bytes.buffer)).assertDeepEquals(base64);
            });

            it('converts byte array to base64-string using Buffer', 0,() => {
                expect(ByteUtils.bytesToBase64(bytes)).assertDeepEquals(base64);
            });
        });

        const hexString = '737472d0bfd180d0b8d0b2d0b5d101';
        const hexBytes = new Uint8Array([
            115, 116, 114, 208, 191, 209, 128, 208, 184, 208, 178, 208, 181, 209, 1
        ]);

        describe('hexToBytes', () => {
            it('converts hex string to byte array', 0,() => {
                expect(ByteUtils.hexToBytes(hexString)).assertDeepEquals(hexBytes);
            });

            it('converts hex string in uppercase to byte array', 0,() => {
                expect(ByteUtils.hexToBytes(hexString.toUpperCase())).assertDeepEquals(hexBytes);
            });
        });

        describe('bytesToHex', () => {
            it('converts byte array to hex string', 0,() => {
                expect(ByteUtils.bytesToHex(hexBytes)).assertDeepEquals(hexString);
            });

            it('converts ArrayBuffer to hex string', 0,() => {
                expect(ByteUtils.bytesToHex(hexBytes.buffer)).assertDeepEquals(hexString);
            });
        });

        describe('zeroBuffer', () => {
            it('fills array with zeroes', 0,() => {
                const arr = new Uint8Array([1, 2, 3]);
                ByteUtils.zeroBuffer(arr);
                expect(ByteUtils.arrayBufferEquals(arr, new Uint8Array([0, 0, 0]))).assertTrue();
            });

            it('fills array buffer with zeroes', 0,() => {
                const arr = new Uint8Array([1, 2, 3]);
                ByteUtils.zeroBuffer(arr.buffer);
                expect(ByteUtils.arrayBufferEquals(arr, new Uint8Array([0, 0, 0]))).assertTrue();
            });
        });

        describe('arrayToBuffer', () => {
            it('converts array to buffer', 0,() => {
                const ab = ByteUtils.arrayToBuffer(new Uint8Array(4));
                expect(ab instanceof  ArrayBuffer).assertTrue();
                expect(ab.byteLength).assertEqual(4);
            });

            it('converts buffer to buffer', 0,() => {
                const ab = ByteUtils.arrayToBuffer(new Uint8Array(4).buffer);
                expect(ab instanceof  ArrayBuffer).assertTrue();
                expect(ab.byteLength).assertEqual(4);
            });

            it('makes sliced buffer from sliced array', 0,() => {
                const srcAb = new ArrayBuffer(10);
                const arr = new Uint8Array(srcAb, 1, 4);
                arr[0] = 1;
                expect(arr.buffer.byteLength).assertEqual(10);
                const ab = ByteUtils.arrayToBuffer(arr);
                expect(ab instanceof  ArrayBuffer).assertTrue();
                expect(ab.byteLength).assertEqual(4);
                expect(new Uint8Array(ab)[0]).assertEqual(1);
            });
        });

        describe('bytesToBuffer', () => {
            it('converts Uint8Array to buffer', 0,() => {
                const bytes = new Uint8Array([1, 2, 3, 4, 5]);
                const buffer = ByteUtils.bytesToBuffer(bytes);
                expect(buffer instanceof ArrayBuffer).assertTrue();
                expect(buffer.byteLength).assertEqual(5);
                const view = new Uint8Array(buffer);
                for (let i = 0; i < bytes.length; i++) {
                    expect(view[i]).assertEqual(bytes[i]);
                }
            });
        });

        describe('stringToBuffer', () => {
            it('converts string to buffer', 0,() => {
                const testStr = 'Hello, World!';
                const buffer = ByteUtils.stringToBuffer(testStr);
                expect(buffer instanceof ArrayBuffer).assertTrue();
                expect(buffer.byteLength).assertEqual(testStr.length);
                const bytes = ByteUtils.stringToBytes(testStr);
                const view = new Uint8Array(buffer);
                for (let i = 0; i < bytes.length; i++) {
                    expect(view[i]).assertEqual(bytes[i]);
                }
            });

            it('converts unicode string to buffer', 0,() => {
                const buffer = ByteUtils.stringToBuffer(str);
                expect(buffer instanceof ArrayBuffer).assertTrue();
                expect(buffer.byteLength).assertEqual(strBytes.length);
                const view = new Uint8Array(buffer);
                for (let i = 0; i < strBytes.length; i++) {
                    expect(view[i]).assertEqual(strBytes[i]);
                }
            });
        });


        describe('arrayBufferEquals', () => {
            it('returns true for equal buffers', 0, () => {
                const buffer1 = new Uint8Array([1, 2, 3, 4, 5]).buffer;
                const buffer2 = new Uint8Array([1, 2, 3, 4, 5]).buffer;
                expect(ByteUtils.arrayBufferEquals(buffer1, buffer2)).assertTrue();
            });

            it('returns false for buffers with different lengths', 0, () => {
                const buffer1 = new Uint8Array([1, 2, 3, 4, 5]).buffer;
                const buffer2 = new Uint8Array([1, 2, 3, 4]).buffer;
                expect(ByteUtils.arrayBufferEquals(buffer1, buffer2)).assertFalse();
            });

            it('returns false for buffers with different content', 0, () => {
                const buffer1 = new Uint8Array([1, 2, 3, 4, 5]).buffer;
                const buffer2 = new Uint8Array([1, 2, 3, 4, 6]).buffer;
                expect(ByteUtils.arrayBufferEquals(buffer1, buffer2)).assertFalse();
            });
        });

        describe('zeroBuffer', () => {
            it('zeros ArrayBuffer', 0, () => {
                const buffer = new Uint8Array([1, 2, 3, 4, 5]).buffer;
                ByteUtils.zeroBuffer(buffer);
                const view = new Uint8Array(buffer);
                for (let i = 0; i < view.length; i++) {
                    expect(view[i]).assertEqual(0);
                }
            });

            it('zeros Uint8Array', 0, () => {
                const array = new Uint8Array([1, 2, 3, 4, 5]);
                ByteUtils.zeroBuffer(array);
                for (let i = 0; i < array.length; i++) {
                    expect(array[i]).assertEqual(0);
                }
            });
        });

        describe('Base64Convert', () => {
            it('converts base64 to bytes', 0, () => {
                const base64Str = 'SGVsbG8gV29ybGQ='; // "Hello World"
                const bytes = ByteUtils.base64ToBytes(base64Str);
                expect(bytes instanceof Uint8Array).assertTrue();
                expect(bytes.length).assertEqual(11);
                expect(ByteUtils.bytesToString(bytes)).assertEqual('Hello World');
            });

            it('converts bytes to base64', 0, () => {
                const text = 'Hello World';
                const bytes = ByteUtils.stringToBytes(text);
                const base64Str = ByteUtils.bytesToBase64(bytes);
                expect(base64Str).assertEqual('SGVsbG8gV29ybGQ=');
            });

            it('roundtrip conversion preserves data', 0, () => {
                const originalText = 'Hello World';
                const bytes = ByteUtils.stringToBytes(originalText);
                const base64Str = ByteUtils.bytesToBase64(bytes);
                const resultBytes = ByteUtils.base64ToBytes(base64Str);
                const resultText = ByteUtils.bytesToString(resultBytes);
                expect(resultText).assertEqual(originalText);
            });
        });

        describe('HexToBytes', () => {
            it('converts hex to bytes', 0, () => {
                const hexStr = '48656c6c6f20576f726c64'; // "Hello World"
                const bytes = ByteUtils.hexToBytes(hexStr);
                expect(bytes instanceof Uint8Array).assertTrue();
                expect(bytes.length).assertEqual(11);
                expect(ByteUtils.bytesToString(bytes)).assertEqual('Hello World');
            });

            it('converts bytes to hex', 0, () => {
                const text = 'Hello World';
                const bytes = ByteUtils.stringToBytes(text);
                const hexStr = ByteUtils.bytesToHex(bytes);
                expect(hexStr).assertEqual('48656c6c6f20576f726c64');
            });

            it('handles single digit hex values correctly', 0, () => {
                const bytes = new Uint8Array([1, 10, 15]);
                const hexStr = ByteUtils.bytesToHex(bytes);
                expect(hexStr).assertEqual('010a0f');
            });

            it('roundtrip conversion preserves data', 0, () => {
                const originalText = 'Hello World';
                const bytes = ByteUtils.stringToBytes(originalText);
                const hexStr = ByteUtils.bytesToHex(bytes);
                const resultBytes = ByteUtils.hexToBytes(hexStr);
                const resultText = ByteUtils.bytesToString(resultBytes);
                expect(resultText).assertEqual(originalText);
            });
        });

        describe('bytesToString', () => {
            it('converts basic ASCII string', 0, () => {
                const text = 'Hello World';
                const bytes = ByteUtils.stringToBytes(text);
                expect(bytes instanceof Uint8Array).assertTrue();
                expect(bytes.length).assertEqual(11);
                const resultText = ByteUtils.bytesToString(bytes);
                expect(resultText).assertEqual(text);
            });

            it('handles special characters', 0, () => {
                const text = 'Hello\nWorld\t!@#$%^&*()';
                const bytes = ByteUtils.stringToBytes(text);
                const resultText = ByteUtils.bytesToString(bytes);
                expect(resultText).assertEqual(text);
            });

            it('handles Unicode characters', 0, () => {
                const text = '你好，世界！🌍';
                const bytes = ByteUtils.stringToBytes(text);
                const resultText = ByteUtils.bytesToString(bytes);
                expect(resultText).assertEqual(text);
            });

            it('handles empty string', 0, () => {
                const text = '';
                const bytes = ByteUtils.stringToBytes(text);
                expect(bytes).assertDeepEquals(new Uint8Array(0));
                const resultText = ByteUtils.bytesToString(bytes);
                expect(resultText).assertEqual(text);
            });

            it('converts ArrayBuffer to string', 0, () => {
                const text = 'Hello World';
                const bytes = ByteUtils.stringToBytes(text);
                const resultText = ByteUtils.bytesToString(bytes.buffer);
                expect(resultText).assertEqual(text);
            });

            it('roundtrip conversion preserves all characters', 0, () => {
                const text = 'Hello, 世界! 🌍\n\t!@#$%^&*()';
                const bytes = ByteUtils.stringToBytes(text);
                const resultText = ByteUtils.bytesToString(bytes);
                expect(resultText).assertEqual(text);
            });
        });
    });
}

