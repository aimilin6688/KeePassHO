cmake_minimum_required(VERSION 3.5.0)
project(kdbxweb_zlib)

# S5 流式压缩：NDK sysroot 自带 zlib（libz.so），仅依赖 napi 运行时
add_library(kdbxweb_zlib SHARED zlib_stream.cpp)

target_link_libraries(kdbxweb_zlib PUBLIC libace_napi.z.so libz.so)
