/*
 * Salsa20 原生实现（djb Salsa20，32 字节 key + 8 字节 nonce），对齐 ets 侧 crypto/salsa20.ts。
 *
 * 用途：OtpKeyProv 插件兼容（.otp.xml 的 EncryptedSecret/OTP v2 解密）与 KDBX3 随机流保护，
 * 纯 JS 路径逐字节解释执行较慢；本模块编译进既有 libkdbxweb_zlib.so
 * （见 zlib_stream.cpp 的 Init 注入），不新增 napi 模块。
 *
 * 暴露 napi 接口（同步、JS 线程执行，语义与 TS getBytes 完全一致）：
 *   salsa20Xor(data, key, nonce, counter, blockOffset): void
 *     - data/key/nonce: Uint8Array（支持 view，如 iv16.subarray(0, 8)）
 *     - data 就地 XOR 密钥流，不分配内存
 *     - counter: 起始 64 字节块计数器（uint64，低 32 位 → input[8]，进位进入 input[9]，
 *       与 TS incrementCounter 的进位语义一致）
 *     - blockOffset: 首块内已消耗字节偏移 0..63（流式分块续解密）
 *   状态布局：input[0..3]=sigma，input[1..4]=key[0..3]，input[5]=sigma1，input[6..7]=nonce，
 *   input[8..9]=counter，input[10]=sigma2，input[11..14]=key[4..7]，input[15]=sigma3
 *   与 TS 实现的字节级等价由 Salsa20Native.test.ets 保证。
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

// Salsa20 quarter round：b ^= Rotl(a+d,7); c ^= Rotl(b+a,9); d ^= Rotl(c+b,13); a ^= Rotl(d+c,18)
inline void SalsaQuarterRound(uint32_t &a, uint32_t &b, uint32_t &c, uint32_t &d)
{
    b ^= Rotl(a + d, 7);
    c ^= Rotl(b + a, 9);
    d ^= Rotl(c + b, 13);
    a ^= Rotl(d + c, 18);
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
    // 20 轮 = 10 个 double round（列轮 4 + 行轮 4）
    for (int round = 0; round < 10; ++round) {
        SalsaQuarterRound(x[0], x[4], x[8], x[12]);
        SalsaQuarterRound(x[5], x[9], x[13], x[1]);
        SalsaQuarterRound(x[10], x[14], x[2], x[6]);
        SalsaQuarterRound(x[15], x[3], x[7], x[11]);
        SalsaQuarterRound(x[0], x[1], x[2], x[3]);
        SalsaQuarterRound(x[5], x[6], x[7], x[4]);
        SalsaQuarterRound(x[10], x[11], x[8], x[9]);
        SalsaQuarterRound(x[15], x[12], x[13], x[14]);
    }
    for (int i = 0; i < 16; ++i) {
        StoreLE32(out + 4 * i, x[i] + input[i]);
    }
}

// 与 TS incrementCounter 的进位语义一致：input[8] 溢出时进 input[9]
inline void AdvanceCounter(uint32_t *input)
{
    if (++input[8] == 0) {
        ++input[9];
    }
}

void Salsa20XorCore(uint8_t *data, size_t len, const uint8_t key[32], const uint8_t nonce[8],
                    uint64_t counter, uint32_t blockOffset)
{
    uint32_t input[16];
    input[0] = kSigma[0];
    input[1] = LoadLE32(key);
    input[2] = LoadLE32(key + 4);
    input[3] = LoadLE32(key + 8);
    input[4] = LoadLE32(key + 12);
    input[5] = kSigma[1];
    input[6] = LoadLE32(nonce);
    input[7] = LoadLE32(nonce + 4);
    input[8] = static_cast<uint32_t>(counter);
    input[9] = static_cast<uint32_t>(counter >> 32);
    input[10] = kSigma[2];
    input[11] = LoadLE32(key + 16);
    input[12] = LoadLE32(key + 20);
    input[13] = LoadLE32(key + 24);
    input[14] = LoadLE32(key + 28);
    input[15] = kSigma[3];

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

napi_value Salsa20Xor(napi_env env, napi_callback_info info)
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
    if (nonceLen != 8) {
        napi_throw_range_error(env, nullptr, "nonce must be 8 bytes");
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
    Salsa20XorCore(const_cast<uint8_t *>(data), dataLen, key, nonce,
                   static_cast<uint64_t>(counter), blockOffset);
    napi_value undefined = nullptr;
    napi_get_undefined(env, &undefined);
    return undefined;
}

} // namespace

// 由 zlib_stream.cpp 的 Init 调用，在同一 exports 上追加 salsa20Xor
napi_value DefineSalsa20(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"salsa20Xor", nullptr, Salsa20Xor, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
