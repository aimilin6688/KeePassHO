import * as CryptoEngine from '../crypto/crypto-engine';
import { ProtectedValue } from '../crypto/protected-value';
import { ErrorCodes } from '../defs/consts';
import { KdbxError } from '../errors/kdbx-error';
import { AttachmentStore } from '../utils/attachment-store';
import { arrayToBuffer, bytesToHex, zeroBuffer } from '../utils/byte-utils';

export type KdbxBinaryRef = { ref: string };
export type KdbxBinaryRefWithValue = { ref: string; value: KdbxBinary };
export type KdbxBinaryWithHash = { hash: string; value: KdbxBinary };

/**
 * 附件磁盘引用（S4 附件磁盘化）：附件字节驻留在 AttachmentStore 加密缓存中，
 * 内存模型仅保留内容哈希与元信息。
 */
export class KdbxBinaryDiskRef {
    readonly hash: string;
    readonly byteLength: number;
    readonly isProtected: boolean;

    constructor(hash: string, byteLength: number, isProtected: boolean) {
        this.hash = hash;
        this.byteLength = byteLength;
        this.isProtected = isProtected;
    }
}

export type KdbxBinary = ProtectedValue | ArrayBuffer | KdbxBinaryDiskRef;
export type KdbxBinaryOrRef = KdbxBinary | KdbxBinaryRef;
export type KdbxBinaryIn = KdbxBinary | Uint8Array;

export class KdbxBinaries {
    /**
     * 附件加密磁盘缓存；未设置时模型保持纯内存模式（小库零行为差异）。
     * 引用只有经由该 store 才能创建/读取。
     */
    store: AttachmentStore | undefined = undefined;

    // temporary map used during database loading
    private readonly _mapById = new Map<string, KdbxBinary>();
    // in runtime, entries are addressed by hash
    private readonly _mapByHash = new Map<string, KdbxBinary>();
    // kept to be able to find binaries by id as well
    private readonly _idToHash = new Map<string, string>();

    computeHashes(): Promise<void> {
        // this method is called after the file is loaded
        const promises = [...this._mapById].map(([id, binary]) =>
            KdbxBinaries.getBinaryHash(binary).then((hash) => {
                this._idToHash.set(id, hash);
                this._mapByHash.set(hash, binary);
            })
        );
        return Promise.all(promises).then(() => {
            // it won't be used anymore
            this._mapById.clear();
        });
    }

    private static getBinaryHash(binary: KdbxBinaryIn): Promise<string> {
        let promise: Promise<string>;
        if (binary instanceof ProtectedValue) {
            promise = binary.getHash().then(bytesToHex);
        } else if (binary instanceof KdbxBinaryDiskRef) {
            // 磁盘引用的 hash 已是 hex 字符串（加载时 sha256FileRegion 产出），不得再次 bytesToHex
            promise = Promise.resolve(binary.hash);
        } else {
            const buf = arrayToBuffer(binary);
            promise = CryptoEngine.sha256(buf).then(bytesToHex);
        }
        return promise;
    }

    add(value: KdbxBinaryIn): Promise<KdbxBinaryWithHash> {
        // called after load
        if (value instanceof Uint8Array) {
            value = arrayToBuffer(value);
        }
        return KdbxBinaries.getBinaryHash(value).then((hash) => {
            this._mapByHash.set(hash, value);
            return { hash, value };
        });
    }

    addWithNextId(value: KdbxBinaryIn): void {
        // called during load (v4), when building the id map
        const id = this._mapById.size.toString();
        this.addWithId(id, value);
    }

    addWithId(id: string, value: KdbxBinaryIn): void {
        // called during load (v3), when building the id map
        if (value instanceof Uint8Array) {
            value = arrayToBuffer(value);
        }
        this._mapById.set(id, value);
    }

    addWithHash(binary: KdbxBinaryWithHash): void {
        this._mapByHash.set(binary.hash, binary.value);
    }

    importPool(pool: KdbxBinaryWithHash[]): void {
        // imports the binary pool from a KPSN snapshot:
        // pool index is used as binary ref, hashes are pre-computed
        for (let i = 0; i < pool.length; i++) {
            this._mapByHash.set(pool[i].hash, pool[i].value);
            this._idToHash.set(i.toString(), pool[i].hash);
        }
    }

    deleteWithHash(hash: string): void {
        this._mapByHash.delete(hash);
    }

    getByRef(binaryRef: KdbxBinaryRef): KdbxBinaryWithHash | undefined {
        const hash = this._idToHash.get(binaryRef.ref);
        if (!hash) {
            return undefined;
        }
        const value = this._mapByHash.get(hash);
        if (!value) {
            return undefined;
        }
        return { hash, value };
    }

    getRefByHash(hash: string): KdbxBinaryRef | undefined {
        const ref = [...this._mapByHash.keys()].indexOf(hash);
        if (ref < 0) {
            return undefined;
        }
        return { ref: ref.toString() };
    }

    getAll(): KdbxBinaryRefWithValue[] {
        return [...this._mapByHash.values()].map((value, index) => {
            return { ref: index.toString(), value };
        });
    }

    getAllWithHashes(): KdbxBinaryWithHash[] {
        return [...this._mapByHash].map(([hash, value]) => ({
            hash,
            value
        }));
    }

    getValueByHash(hash: string): KdbxBinary | undefined {
        return this._mapByHash.get(hash);
    }

    static isKdbxBinaryRef(binary: KdbxBinaryOrRef | undefined): binary is KdbxBinaryRef {
        return !!(binary as KdbxBinaryRef)?.ref;
    }

    static isKdbxBinaryWithHash(
        binary: KdbxBinaryOrRef | KdbxBinaryWithHash | undefined
    ): binary is KdbxBinaryWithHash {
        return !!(binary as KdbxBinaryWithHash)?.hash;
    }

    hasDiskRefs(): boolean {
        for (const value of this._mapByHash.values()) {
            if (value instanceof KdbxBinaryDiskRef) {
                return true;
            }
        }
        return false;
    }

    /**
     * 附件总字节估算（含 ProtectedValue 盐值开销），用于阈值判断。
     */
    private totalMemoryBytes(): number {
        let total = 0;
        for (const value of this._mapByHash.values()) {
            if (value instanceof KdbxBinaryDiskRef) {
                total += value.byteLength;
            } else if (value instanceof ProtectedValue) {
                total += value.value.byteLength + value.salt.byteLength;
            } else {
                total += value.byteLength;
            }
        }
        return total;
    }

    /**
     * 阈值触发时把附件池转为磁盘引用（S4 附件磁盘化）：
     * 附件字节写入加密缓存后从内存模型移除，仅保留哈希与元信息。
     * 缓存命中（磁盘已存在同哈希）直接复用，不重复加密/写盘。
     * @returns 是否发生了转换
     */
    maybeConvertToDiskRefs(thresholdBytes: number): Promise<boolean> {
        if (!this.store || thresholdBytes <= 0 || this._mapByHash.size === 0) {
            return Promise.resolve(false);
        }
        if (this.totalMemoryBytes() < thresholdBytes) {
            return Promise.resolve(false);
        }
        const entries = [...this._mapByHash];
        let chain: Promise<void> = Promise.resolve();
        for (const entry of entries) {
            const hash = entry[0];
            const value = entry[1];
            chain = chain.then(() => {
                return this.convertOneToDiskRef(hash, value).then((ref) => {
                    if (ref) {
                        this._mapByHash.set(hash, ref);
                    }
                });
            });
        }
        return chain.then(() => true);
    }

    private convertOneToDiskRef(
        hash: string,
        value: KdbxBinary
    ): Promise<KdbxBinaryDiskRef | undefined> {
        const store = this.store;
        if (!store) {
            return Promise.resolve(undefined);
        }
        if (value instanceof KdbxBinaryDiskRef) {
            return Promise.resolve(value);
        }
        let bytes: ArrayBuffer;
        let isProtected: boolean;
        if (value instanceof ProtectedValue) {
            bytes = arrayToBuffer(value.getBinary());
            isProtected = true;
        } else {
            bytes = value;
            isProtected = false;
        }
        const byteLength = bytes.byteLength;
        return store.put(hash, bytes).then(() => {
            if (value instanceof ProtectedValue) {
                zeroBuffer(bytes);
            }
            return new KdbxBinaryDiskRef(hash, byteLength, isProtected);
        });
    }

    /**
     * 把所有磁盘引用物化回内存值（v3 保存 / XML 导出前调用）。
     */
    materializeDiskRefs(): Promise<void> {
        const entries = [...this._mapByHash].filter(
            (entry) => entry[1] instanceof KdbxBinaryDiskRef
        );
        if (entries.length === 0) {
            return Promise.resolve();
        }
        let chain: Promise<void> = Promise.resolve();
        for (const entry of entries) {
            const hash = entry[0];
            const ref = entry[1] as KdbxBinaryDiskRef;
            chain = chain.then(() => {
                return this.readDiskRef(ref).then((bytes) => {
                    const value: KdbxBinary = ref.isProtected
                        ? ProtectedValue.fromBinary(bytes)
                        : bytes;
                    this._mapByHash.set(hash, value);
                });
            });
        }
        return chain;
    }

    /**
     * 从加密缓存读取一个磁盘引用的附件内容。
     */
    readDiskRef(ref: KdbxBinaryDiskRef): Promise<ArrayBuffer> {
        if (!this.store) {
            return Promise.reject(
                new KdbxError(
                    ErrorCodes.InvalidState,
                    'disk-ref attachments require an attachment store'
                )
            );
        }
        return this.store.get(ref.hash);
    }

    /**
     * 从加密缓存流式读取磁盘引用附件内容到目标 fd（S6 保存管道）：
     * 4MB 分块解密直写，不整读入内存；哈希校验由 store 保证。
     */
    readDiskRefToFile(ref: KdbxBinaryDiskRef, destFd: number): Promise<void> {
        if (!this.store) {
            return Promise.reject(
                new KdbxError(
                    ErrorCodes.InvalidState,
                    'disk-ref attachments require an attachment store'
                )
            );
        }
        return this.store.getToFile(ref.hash, destFd);
    }
}
