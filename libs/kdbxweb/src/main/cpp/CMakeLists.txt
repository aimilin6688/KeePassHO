cmake_minimum_required(VERSION 3.5.0)
project(kdbxweb_native)

# kdbxweb 原生支持库（libkdbxweb_native.so）：子模块各自实现 DefineXxx(env, exports)，
# 由 native_entry.cpp 统一挂接注册，不在子模块内散落注册 napi_module：
#   - zlib_stream.cpp：S5 流式压缩（inflateFile / deflateFile），依赖 sysroot zlib
#   - chacha20.cpp：KDBX4 主数据加密（chacha20Xor），纯 JS 路径太慢
#   - salsa20.cpp：OtpKeyProv 兼容解密 / KDBX3 随机流保护（salsa20Xor）
add_library(kdbxweb_native SHARED native_entry.cpp zlib_stream.cpp chacha20.cpp salsa20.cpp)

target_link_libraries(kdbxweb_native PUBLIC libace_napi.z.so libz.so)

# hvigor debug 构建经 CMAKE_CXX_FLAGS_DEBUG 在命令行尾部注入 "-O0 -g"，
# 会覆盖 build-profile cppFlags 的 "-O2"（后者位于 CMAKE_CXX_FLAGS，先于 config 标志生效）；
# 仅对加密热路径源文件以源文件级选项追加 -O2（排在全部全局/目标标志之后，最终生效），
# zlib_stream.cpp / native_entry.cpp 维持原有 -O0 行为不变
set_source_files_properties(chacha20.cpp salsa20.cpp PROPERTIES COMPILE_OPTIONS "-O2")
