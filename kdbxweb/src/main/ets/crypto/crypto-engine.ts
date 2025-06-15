/*
    @note           as of node 19, webcrypto is now global.
                    update script to work with node 19, until then, build with node 18
                        - https://nodejs.org/id/blog/announcements/v19-release-announce#stable-webcrypto

                        - The WebCrypto API is now stable (with the exception of the following algorithms:
                            Ed25519, Ed448, X25519, and X448)

                        - Use globalThis.crypto or require('node:crypto').webcrypto to access this module.
*/

import { KdbxError } from '../errors/kdbx-error';
import { ErrorCodes } from '../defs/consts';
import { arrayToBuffer, bytesToString, hexToBytes, stringToBuffer } from '../utils/byte-utils';
import { ChaCha20 } from './chacha20';
import { CryptoJS } from '@ohos/crypto-js';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { ByteUtils } from '..';

const EmptySha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855';
const EmptySha512 =
  'cf83e1357eefb8bdf1542850d66d8007d620e4050b5715dc83f4a921d36ce9ce' +
    '47d0d13c5d85f2b0ff8318d2877eec2f63b931bd47417a81a538327af927da3e';

const rand = cryptoFramework.createRandom();

// maxRandomQuota is the max number of random bytes you can asks for from the cryptoEngine
// https://developer.mozilla.org/en-US/docs/Web/API/Crypto/getRandomValues
const MaxRandomQuota = 65536;

export function sha256(data: ArrayBuffer): Promise<ArrayBuffer> {
  if (!data.byteLength) {
    return Promise.resolve(arrayToBuffer(hexToBytes(EmptySha256)));
  }
  return new Promise((resolve) => {
    const sha = CryptoJS.SHA256(CryptoJS.lib.WordArray.create(data));
    resolve(ByteUtils.bytesToBuffer(ByteUtils.hexToBytes(sha.toString())));
  });
}

export function sha512(data: ArrayBuffer): Promise<ArrayBuffer> {
  if (!data.byteLength) {
    return Promise.resolve(arrayToBuffer(hexToBytes(EmptySha512)));
  }
  return new Promise((resolve) => {
    const sha = CryptoJS.SHA512(CryptoJS.lib.WordArray.create(data));
    resolve(ByteUtils.bytesToBuffer(ByteUtils.hexToBytes(sha.toString())));
  });
}

export function hmacSha256(key: ArrayBuffer, data: ArrayBuffer): Promise<ArrayBuffer> {
  return new Promise((resolve) => {
    const sha = CryptoJS.HmacSHA256(CryptoJS.lib.WordArray.create(data), CryptoJS.lib.WordArray.create(key));
    resolve(ByteUtils.bytesToBuffer(ByteUtils.hexToBytes(sha.toString())));
  });
}

export abstract class AesCbc {
  abstract importKey(key: ArrayBuffer): Promise<void>;

  abstract encrypt(data: ArrayBuffer, iv: ArrayBuffer): Promise<ArrayBuffer>;

  abstract decrypt(data: ArrayBuffer, iv: ArrayBuffer): Promise<ArrayBuffer>;
}

class AesCbcNode extends AesCbc {
  private _key: ArrayBuffer | undefined;

  private get key(): ArrayBuffer {
    if (!this._key) {
      throw new KdbxError(ErrorCodes.InvalidState, 'no key');
    }
    return this._key;
  }

  importKey(key: ArrayBuffer): Promise<void> {
    this._key = key;
    return Promise.resolve();
  }

  encrypt(data: ArrayBuffer, iv: ArrayBuffer): Promise<ArrayBuffer> {
    return Promise.resolve().then(() => {
      const encrypted = CryptoJS.AES.encrypt(
        CryptoJS.lib.WordArray.create(data),
        CryptoJS.lib.WordArray.create(this.key),
        {
          iv: CryptoJS.lib.WordArray.create(iv),
          mode: CryptoJS.mode.CBC,
          padding: CryptoJS.pad.Pkcs7
        }
      );
      return ByteUtils.wordArrayToArrayBuffer(encrypted.ciphertext);
    });
  }

  decrypt(data: ArrayBuffer, iv: ArrayBuffer): Promise<ArrayBuffer> {
    return Promise.resolve()
      .then(() => {
        const decrypted = CryptoJS.AES.decrypt(
          CryptoJS.lib.CipherParams.create({ ciphertext: CryptoJS.lib.WordArray.create(data) }),
          CryptoJS.lib.WordArray.create(this.key),
          {
            iv: CryptoJS.lib.WordArray.create(iv),
            mode: CryptoJS.mode.CBC,
            padding: CryptoJS.pad.Pkcs7
          }
        );
        return ByteUtils.wordArrayToArrayBuffer(decrypted);
      })
      .catch((e: Error) => {
        throw new KdbxError(ErrorCodes.InvalidKey, 'Invalid key');
      });
  }
}

export function createAesCbc(): AesCbc {
  return new AesCbcNode();
}

function safeRandomWeb(len: number): Uint8Array {
  const randomBytes = new Uint8Array(len);
  while (len > 0) {
    let segmentSize = len % MaxRandomQuota;
    segmentSize = segmentSize > 0 ? segmentSize : MaxRandomQuota;
    const randomBytesSegment = rand.generateRandomSync(segmentSize).data;
    len -= segmentSize;
    randomBytes.set(randomBytesSegment, len);
  }
  return randomBytes;
}

export function random(len: number): Uint8Array {
  return safeRandomWeb(len);
}

export function chacha20(
  data: ArrayBuffer,
  key: ArrayBuffer,
  iv: ArrayBuffer
): Promise<ArrayBuffer> {
  return Promise.resolve().then(() => {
    const algo = new ChaCha20(new Uint8Array(key), new Uint8Array(iv));
    return arrayToBuffer(algo.encrypt(new Uint8Array(data)));
  });
}

export const Argon2TypeArgon2d = 0;

export const Argon2TypeArgon2id = 2;

export type Argon2Type = typeof Argon2TypeArgon2d | typeof Argon2TypeArgon2id;

export type Argon2Version = 0x10 | 0x13;

export type Argon2Fn = (
  password: ArrayBuffer,
  salt: ArrayBuffer,
  memory: number,
  iterations: number,
  length: number,
  parallelism: number,
  type: Argon2Type,
  version: Argon2Version
) => Promise<ArrayBuffer>;

let argon2impl: Argon2Fn | undefined;

export function argon2(
  password: ArrayBuffer,
  salt: ArrayBuffer,
  memory: number,
  iterations: number,
  length: number,
  parallelism: number,
  type: Argon2Type,
  version: Argon2Version
): Promise<ArrayBuffer> {
  if (argon2impl) {
    return argon2impl(
      password,
      salt,
      memory,
      iterations,
      length,
      parallelism,
      type,
      version
    ).then(arrayToBuffer);
  }
  return Promise.reject(new KdbxError(ErrorCodes.NotImplemented, 'argon2 not implemented'));
}

export function setArgon2Impl(impl: Argon2Fn): void {
  argon2impl = impl;
}
