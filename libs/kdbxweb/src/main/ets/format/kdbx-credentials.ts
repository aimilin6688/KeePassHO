import * as XmlUtils from '../utils/xml-utils';
import * as CryptoEngine from '../crypto/crypto-engine';
import { ProtectedValue } from '../crypto/protected-value';
import { KdbxError } from '../errors/kdbx-error';
import { ErrorCodes } from '../defs/consts';
import {
    arrayToBuffer,
    base64ToBytes,
    bytesToBase64,
    bytesToHex,
    bytesToString,
    hexToBytes,
    stringToBytes,
    zeroBuffer
} from '../utils/byte-utils';
import { Element } from '@xmldom/xmldom';

export type KdbxChallengeResponseFn = (challenge: ArrayBuffer) => Promise<ArrayBuffer | Uint8Array>;

export class KdbxCredentials {
    readonly ready: Promise<KdbxCredentials>;
    passwordHash: ProtectedValue | undefined;
    keyFileHash: ProtectedValue | undefined;
    customKeyHash: ProtectedValue | undefined;
    private _challengeResponse: KdbxChallengeResponseFn | undefined;

    constructor(
        password: ProtectedValue | null,
        keyFile?: ArrayBuffer | Uint8Array | null,
        challengeResponse?: KdbxChallengeResponseFn,
        customKey?: ArrayBuffer | Uint8Array | null
    ) {
        this.ready = Promise.all([
            this.setPassword(password),
            this.setKeyFile(keyFile),
            this.setChallengeResponse(challengeResponse),
            this.setCustomKey(customKey)
        ]).then(() => this);
    }

    setPassword(password: ProtectedValue | null): Promise<void> {
        if (!password) {
            this.passwordHash = undefined;
            return Promise.resolve();
        } else if (password instanceof ProtectedValue) {
            return password.getHash().then((hash) => {
                this.passwordHash = ProtectedValue.fromBinary(hash);
            });
        } else {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidArg, 'password'));
        }
    }

    setKeyFile(keyFile: ArrayBuffer | Uint8Array | null | undefined): Promise<void> {
        if (keyFile && !(keyFile instanceof ArrayBuffer) && !(keyFile instanceof Uint8Array)) {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidArg, 'keyFile'));
        }
        if (keyFile) {
            if (keyFile.byteLength === 32) {
                this.keyFileHash = ProtectedValue.fromBinary(arrayToBuffer(keyFile));
                return Promise.resolve();
            }
            let keyFileVersion;
            let dataEl;
            try {
                const keyFileStr = bytesToString(arrayToBuffer(keyFile));
                if (/^[a-f\d]{64}$/i.exec(keyFileStr)) {
                    const bytes = hexToBytes(keyFileStr);
                    this.keyFileHash = ProtectedValue.fromBinary(bytes);
                    return Promise.resolve();
                }
                const xml = XmlUtils.parse(keyFileStr.trim());
                const metaEl = XmlUtils.getChildNode(xml.documentElement, 'Meta');
                if (!metaEl) {
                    return Promise.reject(
                        new KdbxError(ErrorCodes.InvalidArg, 'key file without meta')
                    );
                }

                const versionEl = XmlUtils.getChildNode(metaEl, 'Version');
                if (!versionEl?.textContent) {
                    return Promise.reject(
                        new KdbxError(ErrorCodes.InvalidArg, 'key file without version')
                    );
                }
                keyFileVersion = +versionEl.textContent.split('.')[0];

                const keyEl = XmlUtils.getChildNode(xml.documentElement, 'Key');
                if (!keyEl) {
                    return Promise.reject(
                        new KdbxError(ErrorCodes.InvalidArg, 'key file without key')
                    );
                }

                dataEl = <Element>XmlUtils.getChildNode(keyEl, 'Data');
                if (!dataEl?.textContent) {
                    return Promise.reject(
                        new KdbxError(ErrorCodes.InvalidArg, 'key file without key data')
                    );
                }
            } catch (e) {
                return CryptoEngine.sha256(keyFile).then((hash) => {
                    this.keyFileHash = ProtectedValue.fromBinary(hash);
                });
            }

            switch (keyFileVersion) {
                case 1:
                    this.keyFileHash = ProtectedValue.fromBinary(base64ToBytes(dataEl.textContent));
                    break;
                case 2: {
                    const keyFileData = hexToBytes(dataEl.textContent.replace(/\s+/g, ''));
                    // Official KeePass (KfxFile.VerifyHash): the hash is optional,
                    // an empty or missing hash means verification is skipped;
                    // ParseHex is case-insensitive (StrUtil.IsHexString(str, true)).
                    const keyFileDataHash = (dataEl.getAttribute('Hash') || '').trim().toUpperCase();
                    if (!keyFileDataHash) {
                        this.keyFileHash = ProtectedValue.fromBinary(keyFileData);
                        return Promise.resolve();
                    }
                    return CryptoEngine.sha256(keyFileData).then((computedHash) => {
                        const computedHashStr = bytesToHex(
                            new Uint8Array(computedHash).subarray(0, 4)
                        ).toUpperCase();
                        if (computedHashStr !== keyFileDataHash) {
                            throw new KdbxError(
                                ErrorCodes.FileCorrupt,
                                'key file data hash mismatch'
                            );
                        }
                        this.keyFileHash = ProtectedValue.fromBinary(keyFileData);
                    });
                }
                default: {
                    return Promise.reject(
                        new KdbxError(ErrorCodes.FileCorrupt, 'bad keyfile version')
                    );
                }
            }
        } else {
            this.keyFileHash = undefined;
        }
        return Promise.resolve();
    }

    /**
     * Sets or clears the challenge-response callback.
     * Public: the XC challenge fn is single-use per KDF seed; callers clear it
     * after load so the Kdbx instance can cross worker boundaries (functions
     * are not structurally cloneable).
     */
    setChallengeResponse(
        challengeResponse: KdbxChallengeResponseFn | undefined
    ): Promise<void> {
        this._challengeResponse = challengeResponse;
        return Promise.resolve();
    }

    /**
     * Sets a custom key component (KeePass KcpCustomKey equivalent, e.g. OTP secret).
     * The raw key data is SHA-256 hashed once, matching KcpCustomKey with bPerformHash = true
     * as used by KeePass2Android for OtpKeyProv / KeeChallenge secrets.
     * The hash is combined into the composite key after the key file and before the
     * challenge-response component (KeePass CompositeKey concatenation order).
     */
    setCustomKey(customKey: ArrayBuffer | Uint8Array | null | undefined): Promise<void> {
        if (customKey && !(customKey instanceof ArrayBuffer) && !(customKey instanceof Uint8Array)) {
            return Promise.reject(new KdbxError(ErrorCodes.InvalidArg, 'customKey'));
        }
        if (customKey) {
            return CryptoEngine.sha256(customKey).then((hash) => {
                this.customKeyHash = ProtectedValue.fromBinary(hash);
            });
        }
        this.customKeyHash = undefined;
        return Promise.resolve();
    }

    getHash(challenge?: ArrayBuffer): Promise<ArrayBuffer> {
        return this.ready.then(() => {
            return this.getChallengeResponse(challenge).then((chalResp) => {
                const buffers: Uint8Array[] = [];
                if (this.passwordHash) {
                    buffers.push(this.passwordHash.getBinary());
                }
                if (this.keyFileHash) {
                    buffers.push(this.keyFileHash.getBinary());
                }
                if (this.customKeyHash) {
                    buffers.push(this.customKeyHash.getBinary());
                }
                if (chalResp) {
                    buffers.push(new Uint8Array(chalResp));
                }
                const totalLength = buffers.reduce((acc, buf) => acc + buf.byteLength, 0);
                const allBytes = new Uint8Array(totalLength);
                let offset = 0;
                for (const buffer of buffers) {
                    allBytes.set(buffer, offset);
                    zeroBuffer(buffer);
                    offset += buffer.length;
                }
                return CryptoEngine.sha256(arrayToBuffer(allBytes)).then((hash) => {
                    zeroBuffer(allBytes);
                    return hash;
                });
            });
        });
    }

    getChallengeResponse(challenge?: ArrayBuffer): Promise<ArrayBuffer | Uint8Array | null> {
        return Promise.resolve().then(() => {
            if (!this._challengeResponse || !challenge) {
                return null;
            }
            return this._challengeResponse(challenge).then((response) => {
                return CryptoEngine.sha256(arrayToBuffer(response)).then((hash) => {
                    zeroBuffer(response);
                    return hash;
                });
            });
        });
    }

    static createRandomKeyFile(version = 1): Promise<Uint8Array> {
        const keyLength = 32;
        const keyBytes = CryptoEngine.random(keyLength),
            salt = CryptoEngine.random(keyLength);
        for (let i = 0; i < keyLength; i++) {
            keyBytes[i] ^= salt[i];
            keyBytes[i] ^= (Math.random() * 1000) % 255;
        }
        return KdbxCredentials.createKeyFileWithHash(keyBytes, version);
    }

    static createKeyFileWithHash(keyBytes: ArrayBuffer, version = 1): Promise<Uint8Array> {
        const xmlVersion = version === 2 ? '2.0' : '1.00';
        const dataPadding = '        ';
        let makeDataElPromise;
        if (version === 2) {
            const keyDataPadding = dataPadding + '    ';
            makeDataElPromise = CryptoEngine.sha256(keyBytes).then((computedHash) => {
                const keyHash = bytesToHex(
                    new Uint8Array(computedHash).subarray(0, 4)
                ).toUpperCase();
                const keyStr = bytesToHex(keyBytes).toUpperCase();
                let dataElXml = dataPadding + '<Data Hash="' + keyHash + '">\n';
                for (let num = 0; num < 2; num++) {
                    const parts = [0, 1, 2, 3].map((ix) => {
                        return keyStr.substr(num * 32 + ix * 8, 8);
                    });
                    dataElXml += keyDataPadding;
                    dataElXml += parts.join(' ');
                    dataElXml += '\n';
                }
                dataElXml += dataPadding + '</Data>\n';
                return dataElXml;
            });
        } else {
            const dataElXml = dataPadding + '<Data>' + bytesToBase64(keyBytes) + '</Data>\n';
            makeDataElPromise = Promise.resolve(dataElXml);
        }
        return makeDataElPromise.then((dataElXml) => {
            const xml =
                '<?xml version="1.0" encoding="utf-8"?>\n' +
                '<KeyFile>\n' +
                '    <Meta>\n' +
                '        <Version>' +
                xmlVersion +
                '</Version>\n' +
                '    </Meta>\n' +
                '    <Key>\n' +
                dataElXml +
                '    </Key>\n' +
                '</KeyFile>';
            return stringToBytes(xml);
        });
    }
}
