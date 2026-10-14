/*
 * ChaCha20 原生实现（RFC 7539 + DJB 8 字节 nonce 变体），对齐 ets 侧 crypto/chacha20.ts。
 *
 * 纯 JS 路径在移动端约 100~200MB/s，是 KDBX4 整文件加解密与流式保存的瓶颈；
 * 本模块编译进 libkdbxweb_native.so（经 native_entry.cpp 统一注册），不新增 napi 模块。
 *
 * 暴露 napi 接口（同步、JS 线程执行，语义与 TS xorInPlace 完全一致）：
 *   chacha20Xor(data, key, nonce, counter, blockOffset): void
 *     - data/key/nonce: Uint8Array（支持 view，如 new Uint8Array(hash, 32, 12)）
 *     - data 就地 XOR 密钥流，不分配内存
 *     - counter: 起始 64 字节块计数器（无状态设计，TS 侧跨调用重建流位置）
 *     - blockOffset: 首块内已消耗字节偏移 0..63（流式分块续解密）
 *   nonce 12 字节 → RFC 7539（input[12]=counter 低 32 位，进位进入 input[13]）
 *   nonce ≥8 字节 → DJB 变体（input[13]=counter 高 32 位，input[14..15]=nonce 前 8 字节）
 *   与 TS 实现的字节级等价由 chacha20.test.ets 保证。
 */

#include "napi/native_api.h"

#include <cstddef>
#include <cstdint>

namespace {

constexpr uint32_t kSigma[4] = {0x61707865u, 0x3320646eu, 0x79622d32u, 0x6b206574u};

inline uint32_t Rotl(uint32_t v, uint32_t c)
{
    return (v << c) | (v >> (32u - c));
}

inline void QuarterRound(uint32_t &a, uint32_t &b, uint32_t &c, uint32_t &d)
{
    a += b;
    d = Rotl(d ^ a, 16);
    c += d;
    b = Rotl(b ^ c, 12);
    a += b;
    d = Rotl(d ^ a, 8);
    c += d;
    b = Rotl(b ^ c, 7);
}

inline uint32_t LoadLE32(const uint8_t *p)
{
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

inline void StoreLE32(uint8_t *p, uint32_t v)
{
    p[0] = static_cast<uint8_t>(v);
    p[1] = static_cast<uint8_t>(v >> 8);
    p[2] = static_cast<uint8_t>(v >> 16);
    p[3] = static_cast<uint8_t>(v >> 24);
}

void GenerateBlock(const uint32_t *input, uint8_t out[64])
{
    uint32_t x[16];
    for (int i = 0; i < 16; ++i) {
        x[i] = input[i];
    }
    // 20 轮 = 10 个 double round（列 4 + 对角 4）
    for (int round = 0; round < 10; ++round) {
        QuarterRound(x[0], x[4], x[8], x[12]);
        QuarterRound(x[1], x[5], x[9], x[13]);
        QuarterRound(x[2], x[6], x[10], x[14]);
        QuarterRound(x[3], x[7], x[11], x[15]);
        QuarterRound(x[0], x[5], x[10], x[15]);
        QuarterRound(x[1], x[6], x[11], x[12]);
        QuarterRound(x[2], x[7], x[8], x[13]);
        QuarterRound(x[3], x[4], x[9], x[14]);
    }
    for (int i = 0; i < 16; ++i) {
        StoreLE32(out + 4 * i, x[i] + input[i]);
    }
}

// 与 TS generateBlock 的进位语义一致：input[12] 溢出时进 input[13]
inline void AdvanceCounter(uint32_t *input)
{
    if (++input[12] == 0) {
        ++input[13];
    }
}

void ChaCha20XorCore(uint8_t *data, size_t len, const uint8_t key[32], const uint8_t *nonce,
                     bool isRfcNonce, uint64_t counter, uint32_t blockOffset)
{
    uint32_t input[16];
    input[0] = kSigma[0];
    input[1] = kSigma[1];
    input[2] = kSigma[2];
    input[3] = kSigma[3];
    for (int i = 0; i < 8; ++i) {
        input[4 + i] = LoadLE32(key + 4 * i);
    }
    input[12] = static_cast<uint32_t>(counter);
    input[13] = isRfcNonce ? LoadLE32(nonce) : static_cast<uint32_t>(counter >> 32);
    input[14] = isRfcNonce ? LoadLE32(nonce + 4) : LoadLE32(nonce);
    input[15] = isRfcNonce ? LoadLE32(nonce + 8) : LoadLE32(nonce + 4);

    uint8_t block[64];
    size_t pos = 0;
    if (blockOffset > 0) {
        // 续流：重新生成 counter 块，跳过已消耗的 blockOffset 字节
        GenerateBlock(input, block);
        AdvanceCounter(input);
        const size_t n = len < (64u - blockOffset) ? len : (64u - blockOffset);
        for (size_t i = 0; i < n; ++i) {
            data[pos + i] ^= block[blockOffset + i];
        }
        pos = n;
    }
    while (pos < len) {
        GenerateBlock(input, block);
        AdvanceCounter(input);
        const size_t n = (len - pos) < 64u ? (len - pos) : 64u;
        for (size_t i = 0; i < n; ++i) {
            data[pos + i] ^= block[i];
        }
        pos += n;
    }
}

bool GetUint8ArrayPtr(napi_env env, napi_value value, const uint8_t **data, size_t *length)
{
    napi_typedarray_type type = napi_uint8_array;
    size_t len = 0;
    void *ptr = nullptr;
    napi_value arraybuffer = nullptr;
    size_t byteOffset = 0;
    if (napi_get_typedarray_info(env, value, &type, &len, &ptr, &arraybuffer, &byteOffset) != napi_ok) {
        return false;
    }
    if (type != napi_uint8_array || (ptr == nullptr && len > 0)) {
        // 零长度 Uint8Array 的 data 指针可能为 null，属合法输入（XorCore 不会解引用）
        return false;
    }
    *data = static_cast<const uint8_t *>(ptr);
    *length = len;
    return true;
}

napi_value ChaCha20Xor(napi_env env, napi_callback_info info)
{
    size_t argc = 5;
    napi_value args[5] = {nullptr, nullptr, nullptr, nullptr, nullptr};
    if (napi_get_cb_info(env, info, &argc, args, nullptr, nullptr) != napi_ok || argc != 5) {
        napi_throw_type_error(env, nullptr, "expected (data, key, nonce: Uint8Array, counter: number, blockOffset: number)");
        return nullptr;
    }
    const uint8_t *data = nullptr;
    const uint8_t *key = nullptr;
    const uint8_t *nonce = nullptr;
    size_t dataLen = 0;
    size_t keyLen = 0;
    size_t nonceLen = 0;
    if (!GetUint8ArrayPtr(env, args[0], &data, &dataLen) ||
        !GetUint8ArrayPtr(env, args[1], &key, &keyLen) ||
        !GetUint8ArrayPtr(env, args[2], &nonce, &nonceLen)) {
        napi_throw_type_error(env, nullptr, "Uint8Array arguments expected");
        return nullptr;
    }
    if (keyLen != 32) {
        napi_throw_range_error(env, nullptr, "key must be 32 bytes");
        return nullptr;
    }
    if (nonceLen != 12 && nonceLen < 8) {
        napi_throw_range_error(env, nullptr, "nonce must be 8 or 12 bytes");
        return nullptr;
    }
    int64_t counter = 0;
    if (napi_get_value_int64(env, args[3], &counter) != napi_ok || counter < 0) {
        napi_throw_range_error(env, nullptr, "counter must be a non-negative number");
        return nullptr;
    }
    uint32_t blockOffset = 0;
    if (napi_get_value_uint32(env, args[4], &blockOffset) != napi_ok || blockOffset > 63) {
        napi_throw_range_error(env, nullptr, "blockOffset must be in [0, 63]");
        return nullptr;
    }
    ChaCha20XorCore(const_cast<uint8_t *>(data), dataLen, key, nonce, nonceLen == 12,
                    static_cast<uint64_t>(counter), blockOffset);
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

} // namespace

// 由 native_entry.cpp 的 Init 调用，在同一 exports 上追加 chacha20Xor
napi_value DefineChaCha20(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"chacha20Xor", nullptr, ChaCha20Xor, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
