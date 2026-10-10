import { chacha20XorNative, nativeChaCha20Available } from './chacha20-native';

/**
 * 流式加解密的字节位置（无状态原生调用的重建参数）：
 * counter = 起始 64 字节块计数器，offset = 首块内已消耗字节偏移 0..63
 */
interface ChaCha20StreamPosition {
    counter: number;
    offset: number;
}

export class ChaCha20 {
    private readonly _sigmaWords = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574];
    private readonly _block = new Uint8Array(64);
    private _blockUsed = 64;
    private readonly _x = new Uint32Array(16);
    private readonly _input: Uint32Array;

    // ---- 原生路径状态镜像（与 _input/_blockUsed 同步维护，见 nativeStart/applyNativeAdvance）----
    private readonly _key: Uint8Array;
    private readonly _nonce: Uint8Array;
    private readonly _isRfcNonce: boolean;
    private readonly _baseInput13: number; // RFC: nonce 前 4 字节；DJB: 0
    private _counterUnits = 0;             // 已生成的 64 字节块总数（对应 generateBlock 调用数）
    private readonly _useNative: boolean;  // 构造期决定：native 可用且参数合法则走原生路径

    constructor(key: Uint8Array, nonce: Uint8Array) {
        const input = new Uint32Array(16);

        input[0] = this._sigmaWords[0];
        input[1] = this._sigmaWords[1];
        input[2] = this._sigmaWords[2];
        input[3] = this._sigmaWords[3];
        input[4] = u8to32le(key, 0);
        input[5] = u8to32le(key, 4);
        input[6] = u8to32le(key, 8);
        input[7] = u8to32le(key, 12);
        input[8] = u8to32le(key, 16);
        input[9] = u8to32le(key, 20);
        input[10] = u8to32le(key, 24);
        input[11] = u8to32le(key, 28);
        input[12] = 0; // counter

        if (nonce.length === 12) {
            input[13] = u8to32le(nonce, 0);
            input[14] = u8to32le(nonce, 4);
            input[15] = u8to32le(nonce, 8);
        } else {
            input[13] = 0;
            input[14] = u8to32le(nonce, 0);
            input[15] = u8to32le(nonce, 4);
        }

        this._input = input;
        this._key = key;
        this._nonce = nonce;
        this._isRfcNonce = nonce.length === 12;
        this._baseInput13 = this._isRfcNonce ? u8to32le(nonce, 0) : 0;
        // 原生路径要求 key 32 字节、nonce ≥8 字节（view 亦可）
        this._useNative = key.length === 32 && nonce.length >= 8 && nativeChaCha20Available();
    }

    getBytes(numberOfBytes: number): Uint8Array {
        const out = new Uint8Array(numberOfBytes);
        if (this._useNative) {
            // out 全零，XOR 密钥流后即为 keystream；空数据为 no-op（流位置不变），
            // 避免零长度 typedarray 的 NAPI 空指针边界
            if (numberOfBytes > 0) {
                const start = this.nativeStart();
                chacha20XorNative(out, this._key, this._nonce, start.counter, start.offset);
                this.applyNativeAdvance(numberOfBytes, start);
            }
            return out;
        }
        for (let i = 0; i < numberOfBytes; i++) {
            if (this._blockUsed === 64) {
                this.generateBlock();
                this._blockUsed = 0;
            }
            out[i] = this._block[this._blockUsed];
            this._blockUsed++;
        }
        return out;
    }

    /**
     * 流式就地解密/加密：用密钥流 XOR data（状态跨块保持，可用于分块文件流式处理）
     * ChaCha20 加解密对称，同一方法即可
     */
    xorInPlace(data: Uint8Array): void {
        if (this._useNative) {
            if (data.length > 0) {
                const start = this.nativeStart();
                chacha20XorNative(data, this._key, this._nonce, start.counter, start.offset);
                this.applyNativeAdvance(data.length, start);
            }
            return;
        }
        for (let i = 0; i < data.length; i++) {
            if (this._blockUsed === 64) {
                this.generateBlock();
                this._blockUsed = 0;
            }
            data[i] ^= this._block[this._blockUsed];
            this._blockUsed++;
        }
    }

    private generateBlock(): void {
        const input = this._input;
        const x = this._x;
        const block = this._block;

        x.set(input);
        for (let i = 20; i > 0; i -= 2) {
            quarterRound(x, 0, 4, 8, 12);
            quarterRound(x, 1, 5, 9, 13);
            quarterRound(x, 2, 6, 10, 14);
            quarterRound(x, 3, 7, 11, 15);
            quarterRound(x, 0, 5, 10, 15);
            quarterRound(x, 1, 6, 11, 12);
            quarterRound(x, 2, 7, 8, 13);
            quarterRound(x, 3, 4, 9, 14);
        }
        for (let i = 16; i--; ) {
            x[i] += input[i];
        }
        for (let i = 16; i--; ) {
            u32to8le(block, 4 * i, x[i]);
        }

        input[12] += 1;
        if (!input[12]) {
            input[13] += 1;
        }
        this._counterUnits++;
    }

    /**
     * 原生路径：重建当前流位置。
     * _blockUsed === 64 → 下一块为 _counterUnits；否则当前块为 _counterUnits - 1、已消耗 _blockUsed 字节。
     */
    private nativeStart(): ChaCha20StreamPosition {
        if (this._blockUsed === 64) {
            const pos: ChaCha20StreamPosition = { counter: this._counterUnits, offset: 0 };
            return pos;
        }
        const pos: ChaCha20StreamPosition = { counter: this._counterUnits - 1, offset: this._blockUsed };
        return pos;
    }

    /**
     * 原生路径：按本次消耗的字节数推进镜像状态，并回写 _input[12/13]
     * 供潜在的 JS 回退路径（encrypt 混合场景）从正确计数器续算。
     */
    private applyNativeAdvance(len: number, start: ChaCha20StreamPosition): void {
        const availableInFirst = 64 - start.offset;
        const remaining = len > availableInFirst ? len - availableInFirst : 0;
        const newBlocks = remaining > 0 ? Math.ceil(remaining / 64) : 0;
        // start.offset === 0 时首块为本次新生成块（对应 JS 路径 generateBlock 的触发）
        const firstIsNew = start.offset === 0 && len > 0;
        this._counterUnits += newBlocks + (firstIsNew ? 1 : 0);
        this._blockUsed = remaining === 0
            ? start.offset + len
            : (remaining % 64 === 0 ? 64 : remaining % 64);
        this.syncInputCounter();
    }

    /** 将 _counterUnits 回写为 _input 的计数器字（与 JS generateBlock 的进位语义一致） */
    private syncInputCounter(): void {
        this._input[12] = this._counterUnits % 4294967296;
        this._input[13] = this._baseInput13 + Math.floor(this._counterUnits / 4294967296);
    }

    public encrypt(data: Uint8Array): Uint8Array {
        const length = data.length;
        const res = new Uint8Array(length);
        if (this._useNative && this._blockUsed === 64) {
            // 与 JS 语义一致：从当前计数器整块续生成，忽略半块状态（该状态由 xorInPlace 维护）
            if (length > 0) {
                res.set(data);
                chacha20XorNative(res, this._key, this._nonce, this._counterUnits, 0);
                this._counterUnits += Math.ceil(length / 64);
                this.syncInputCounter();
            }
            return res;
        }
        let pos = 0;
        const block = this._block;
        while (pos < length) {
            this.generateBlock();
            const blockLength = Math.min(length - pos, 64);
            for (let i = 0; i < blockLength; i++) {
                res[pos] = data[pos] ^ block[i];
                pos++;
            }
        }
        return res;
    }
}

function quarterRound(x: Uint32Array, a: number, b: number, c: number, d: number): void {
    x[a] += x[b];
    x[d] = rotate(x[d] ^ x[a], 16);
    x[c] += x[d];
    x[b] = rotate(x[b] ^ x[c], 12);
    x[a] += x[b];
    x[d] = rotate(x[d] ^ x[a], 8);
    x[c] += x[d];
    x[b] = rotate(x[b] ^ x[c], 7);
}

function u8to32le(x: Uint8Array, i: number): number {
    return x[i] | (x[i + 1] << 8) | (x[i + 2] << 16) | (x[i + 3] << 24);
}

function u32to8le(x: Uint8Array, i: number, u: number): void {
    x[i] = u;
    u >>>= 8;
    x[i + 1] = u;
    u >>>= 8;
    x[i + 2] = u;
    u >>>= 8;
    x[i + 3] = u;
}

function rotate(v: number, c: number): number {
    return (v << c) | (v >>> (32 - c));
}
