import { Argon2Type, Argon2Version,Argon2TypeArgon2id } from './crypto-engine';
import {Algorithm,Version, hashRaw } from '@ohos-rs/argon2'

import { hilog } from '@kit.PerformanceAnalysisKit';
const DOMAIN = 0x0000;
const TAG = 'ohosArgon2-rs';

export function ohosArgon2(
    password: ArrayBuffer,
    salt: ArrayBuffer,
    memory: number,
    iterations: number,
    length: number,
    parallelism: number,
    type: Argon2Type,
    version: Argon2Version
): Promise<ArrayBuffer> {
    const algorithmType:Algorithm = type === Argon2TypeArgon2id ? Algorithm.Argon2id : Algorithm.Argon2d;
    const rsVersion:Version = version === 0x13 ? Version.V0x13 : Version.V0x10;
    try {
        const param = {
            memoryCost: memory,
            timeCost: iterations,
            outputLen: length,
            parallelism: parallelism,
            algorithm: algorithmType,
            version: rsVersion,
            salt: salt
        };
        hilog.info(DOMAIN, TAG, 'ohosArgon2 param: ' + JSON.stringify(param));
        const res = hashRaw(password, param);
        return Promise.resolve(res);
    } catch (e) {
        return Promise.reject(e);
    }
}
