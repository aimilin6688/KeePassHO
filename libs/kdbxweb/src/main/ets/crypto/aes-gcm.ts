import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { KdbxError } from '../errors/kdbx-error';
import { ErrorCodes } from '../defs/consts';
import * as CryptoEngine from './crypto-engine';

const KEY_BYTES = 32;
const NONCE_BYTES = 12;
const AUTH_TAG_BYTES = 16;

/**
 * 原生 AES-256-GCM 加解密会话（cryptoFramework，分段 update / 末次 finalize）。
 * GCM 为流式 AEAD：各次 update 输出按序拼接即为完整密文/明文，
 * finalize 产出（加密）或校验（解密）末尾 16 字节 authTag。
 */
export class AesGcmEncryptSession {
    private readonly cipher: cryptoFramework.Cipher;

    constructor(cipher: cryptoFramework.Cipher) {
        this.cipher = cipher;
    }

    /** 加密一个分段：输出与输入等长的密文分段 */
    update(chunk: Uint8Array): Uint8Array {
        return this.cipher.updateSync({ data: chunk }).data;
    }

    /** 结束加密流程：返回 16 字节 authTag */
    finalize(): Uint8Array {
        return this.cipher.doFinalSync(null).data;
    }
}

export class AesGcmDecryptSession {
    private readonly cipher: cryptoFramework.Cipher;

    constructor(cipher: cryptoFramework.Cipher) {
        this.cipher = cipher;
    }

    /** 解密一个分段：输出与输入等长的明文分段 */
    update(chunk: Uint8Array): Uint8Array {
        return this.cipher.updateSync({ data: chunk }).data;
    }

    /** 结束解密流程：校验 authTag，不匹配抛错（cryptoFramework 17630001） */
    finalize(): void {
        this.cipher.doFinalSync(null);
    }
}

/**
 * 原生 AES-256-GCM 公共加解密（cryptoFramework 实现，供跨线程会话文件、
 * 附件磁盘缓存等内部加密复用；明文与密钥均不在 ArkTS 层逐字节循环）。
 *
 * 一次性接口（seal/open）封包布局：[12B nonce][密文][16B authTag]；
 * 流式接口（openEncryptSession/openDecryptSession）供分块读写文件的场景，
 * 分块语义与 ChaCha20 xorInPlace 一致：会话状态跨块连续，等价单次整段加解密。
 */
export class AesGcm {
    /** 密钥长度（字节） */
    static readonly KEY_LENGTH = KEY_BYTES;
    /** nonce 长度（字节） */
    static readonly NONCE_LENGTH = NONCE_BYTES;
    /** authTag 长度（字节） */
    static readonly AUTH_TAG_LENGTH = AUTH_TAG_BYTES;

    /**
     * 一次性加密：生成随机 nonce，返回 [12B nonce][密文][16B authTag]
     * @param key 32 字节密钥
     * @param data 明文（长度可为 0）
     */
    static seal(key: Uint8Array, data: Uint8Array): Uint8Array {
        const nonce = CryptoEngine.random(NONCE_BYTES);
        const session = AesGcm.openEncryptSession(key, nonce);
        const cipherBytes = data.byteLength > 0 ? session.update(data) : new Uint8Array(0);
        const tag = session.finalize();
        const out = new Uint8Array(NONCE_BYTES + cipherBytes.byteLength + tag.byteLength);
        out.set(nonce, 0);
        out.set(cipherBytes, NONCE_BYTES);
        out.set(tag, NONCE_BYTES + cipherBytes.byteLength);
        return out;
    }

    /**
     * 一次性解密：输入 [12B nonce][密文][16B authTag]，返回明文；
     * authTag 校验失败时抛出 cryptoFramework 错误（17630001），由调用方归类
     * @param key 32 字节密钥
     * @param sealed seal 输出布局的密文
     */
    static open(key: Uint8Array, sealed: Uint8Array): Uint8Array {
        if (sealed.byteLength < NONCE_BYTES + AUTH_TAG_BYTES) {
            throw new KdbxError(ErrorCodes.InvalidArg, 'sealed data too short');
        }
        const nonce = sealed.slice(0, NONCE_BYTES);
        const tag = sealed.slice(sealed.byteLength - AUTH_TAG_BYTES);
        const cipherBytes = sealed.slice(NONCE_BYTES, sealed.byteLength - AUTH_TAG_BYTES);
        const session = AesGcm.openDecryptSession(key, nonce, tag);
        const plain = cipherBytes.byteLength > 0 ? session.update(cipherBytes) : new Uint8Array(0);
        session.finalize();
        return plain;
    }

    /**
     * 打开流式加密会话（调用方自备 nonce，便于先写文件头再分块加密）
     * @param key 32 字节密钥
     * @param nonce 12 字节随机数
     */
    static openEncryptSession(key: Uint8Array, nonce: Uint8Array): AesGcmEncryptSession {
        AesGcm.validateKey(key);
        AesGcm.validateNonce(nonce);
        const cipher = cryptoFramework.createCipher('AES256|GCM');
        const gcmParams: cryptoFramework.GcmParamsSpec = {
            algName: 'GcmParamsSpec',
            iv: { data: new Uint8Array(nonce) },
            aad: { data: new Uint8Array(0) },
            authTag: { data: new Uint8Array(0) }
        };
        cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, AesGcm.createSymKey(key), gcmParams);
        return new AesGcmEncryptSession(cipher);
    }

    /**
     * 打开流式解密会话（GCM 需在 init 时提供 authTag，流式场景先从密文末尾读取）
     * @param key 32 字节密钥
     * @param nonce 12 字节 nonce
     * @param tag 16 字节 authTag
     */
    static openDecryptSession(key: Uint8Array, nonce: Uint8Array, tag: Uint8Array): AesGcmDecryptSession {
        AesGcm.validateKey(key);
        AesGcm.validateNonce(nonce);
        if (tag.byteLength !== AUTH_TAG_BYTES) {
            throw new KdbxError(ErrorCodes.InvalidArg, 'bad authTag length');
        }
        const cipher = cryptoFramework.createCipher('AES256|GCM');
        const gcmParams: cryptoFramework.GcmParamsSpec = {
            algName: 'GcmParamsSpec',
            iv: { data: new Uint8Array(nonce) },
            aad: { data: new Uint8Array(0) },
            authTag: { data: new Uint8Array(tag) }
        };
        cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, AesGcm.createSymKey(key), gcmParams);
        return new AesGcmDecryptSession(cipher);
    }

    private static createSymKey(key: Uint8Array): cryptoFramework.SymKey {
        const generator = cryptoFramework.createSymKeyGenerator('AES256');
        return generator.convertKeySync({ data: new Uint8Array(key) });
    }

    private static validateKey(key: Uint8Array): void {
        if (!(key instanceof Uint8Array) || key.byteLength !== KEY_BYTES) {
            throw new KdbxError(ErrorCodes.InvalidArg, 'bad aes-256-gcm key length');
        }
    }

    private static validateNonce(nonce: Uint8Array): void {
        if (!(nonce instanceof Uint8Array) || nonce.byteLength !== NONCE_BYTES) {
            throw new KdbxError(ErrorCodes.InvalidArg, 'bad aes-256-gcm nonce length');
        }
    }
}
