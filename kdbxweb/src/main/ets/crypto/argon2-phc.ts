import { Argon2Type, Argon2TypeArgon2id, Argon2Version } from './crypto-engine';
import { argon2Hash } from '@huozhiniao/argon2';


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
  const algorithmType: number = type === Argon2TypeArgon2id ? 2 : 0;
  try {
    const res = argon2Hash(password, salt, {
      memoryCost: memory,
      timeCost: iterations,
      hashLength: length,
      parallelism: parallelism,
      argon2Type: algorithmType,
      argon2Version: version
    });
    if (res.result != 'ARGON2_OK') {
      throw new Error(res.result);
    }
    return Promise.resolve(res.hash);
  } catch (e) {
    return Promise.reject(e);
  }
}
