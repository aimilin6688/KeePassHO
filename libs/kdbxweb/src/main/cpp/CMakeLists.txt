cmake_minimum_required(VERSION 3.5.0)
project(kdbxweb_zlib)

# S5 流式压缩：NDK sysroot 自带 zlib（libz.so），仅依赖 napi 运行时
# ChaCha20：KDBX4 主数据加密，纯 JS 路径太慢，原生化（chacha20.cpp 注入 zlib_stream Init）
add_library(kdbxweb_zlib SHARED zlib_stream.cpp chacha20.cpp)

target_link_libraries(kdbxweb_zlib PUBLIC libace_napi.z.so libz.so)

# hvigor debug 构建经 CMAKE_CXX_FLAGS_DEBUG 在命令行尾部注入 "-O0 -g"，
# 会覆盖 build-profile cppFlags 的 "-O2"（后者位于 CMAKE_CXX_FLAGS，先于 config 标志生效）；
# 仅对 chacha20.cpp 以源文件级选项追加 -O2（排在全部全局/目标标志之后，最终生效），
# zlib_stream.cpp 维持原有 -O0 行为不变
set_source_files_properties(chacha20.cpp PROPERTIES COMPILE_OPTIONS "-O2")
