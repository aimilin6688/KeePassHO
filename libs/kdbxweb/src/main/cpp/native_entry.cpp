/*
 * kdbxweb 原生支持库（libkdbxweb_native.so）统一注册入口。
 *
 * 各子模块在各自源文件内实现并导出 DefineXxx(env, exports)，由本文件的 Init
 * 统一挂接到同一 exports 对象后注册 napi 模块：
 *   - zlib_stream.cpp：DefineZlibStream（inflateFile / deflateFile，S5 流式压缩）
 *   - chacha20.cpp：DefineChaCha20（chacha20Xor，KDBX4 主数据加密）
 *   - salsa20.cpp：DefineSalsa20（salsa20Xor，OtpKeyProv 兼容 / KDBX3 随机流）
 *
 * 新增原生能力：实现独立 cpp + DefineXxx，并在本文件顶部声明、Init 中挂接即可；
 * 不要在子模块内直接注册 napi_module 或向其他子模块注入。
 */

#include "napi/native_api.h"

napi_value DefineZlibStream(napi_env env, napi_value exports);
napi_value DefineChaCha20(napi_env env, napi_value exports);
napi_value DefineSalsa20(napi_env env, napi_value exports);

namespace {

napi_value Init(napi_env env, napi_value exports)
{
    DefineZlibStream(env, exports);
    DefineChaCha20(env, exports);
    DefineSalsa20(env, exports);
    return exports;
}

} // namespace

static napi_module g_kdbxwebNativeModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "kdbxweb_native",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterKdbxwebNativeModule(void)
{
    napi_module_register(&g_kdbxwebNativeModule);
}
