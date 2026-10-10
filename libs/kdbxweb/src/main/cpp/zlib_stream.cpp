/*
 * S5 流式压缩：NDK zlib 流式原语（设计文档 §5）。
 *
 * @ohos/flate2 为整缓冲 Rust 绑定、@ohos/zlib 仅 zip 归档，均无法流式处理单成员 gzip
 * 载荷；本模块直接使用 NDK sysroot 自带的 zlib C API（inflate/deflate 流式），
 * 内存窗口 = 1MB 输入 + 4MB 输出，与文件大小解耦。
 *
 * 暴露两个 napi 接口（均为 Promise 异步，native 线程执行 zlib 循环）：
 *   inflateFile(inPath, outPath): Promise<number>  gzip 流式解压，返回解压后字节数
 *   deflateFile(inPath, outPath, level?): Promise<number>  gzip 流式压缩，返回压缩后字节数
 *
 * 失败时输出文件会被删除（不留残缺中间文件），Promise 以 Error reject。
 */

#include "napi/native_api.h"

#include <zlib.h>

#include <cerrno>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

// chacha20.cpp 提供：在同一 exports 上追加 chacha20Xor 导出
napi_value DefineChaCha20(napi_env env, napi_value exports);

namespace {

constexpr size_t kInChunkSize = 1u << 20;   // 1MB 输入窗口
constexpr size_t kOutChunkSize = 4u << 20;  // 4MB 输出窗口
constexpr int kWindowBitsGzip = 15 + 16;    // gzip 单成员模式
constexpr int kDeflateLevelDefault = 6;

struct WorkRequest {
    std::string inPath;
    std::string outPath;
    int level = kDeflateLevelDefault;
    bool inflate = true;
    int64_t written = 0;
    std::string error;
};

struct AsyncWork {
    WorkRequest request;
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
};

bool WriteAll(int fd, const unsigned char *data, size_t length)
{
    size_t offset = 0;
    while (offset < length) {
        ssize_t n = write(fd, data + offset, length - offset);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return false;
        }
        offset += static_cast<size_t>(n);
    }
    return true;
}

// 尽量读满 length 字节；普通文件短读即 EOF
ssize_t ReadFill(int fd, unsigned char *data, size_t length)
{
    size_t offset = 0;
    while (offset < length) {
        ssize_t n = read(fd, data + offset, length - offset);
        if (n < 0) {
            if (errno == EINTR) {
                continue;
            }
            return -1;
        }
        if (n == 0) {
            break;
        }
        offset += static_cast<size_t>(n);
    }
    return static_cast<ssize_t>(offset);
}

void SetError(std::string *error, const std::string &tag, const std::string &detail)
{
    if (error->empty()) {
        *error = tag + ": " + detail;
    }
}

int InflateRun(int inFd, int outFd, int64_t *total, std::string *error)
{
    unsigned char *in = static_cast<unsigned char *>(malloc(kInChunkSize));
    unsigned char *out = static_cast<unsigned char *>(malloc(kOutChunkSize));
    if (in == nullptr || out == nullptr) {
        free(in);
        free(out);
        SetError(error, "inflateFile", "out of memory");
        return -1;
    }
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    if (inflateInit2(&strm, kWindowBitsGzip) != Z_OK) {
        free(in);
        free(out);
        SetError(error, "inflateFile", "inflateInit2 failed");
        return -1;
    }
    int status = 0;
    int ret = Z_OK;
    while (status == 0) {
        ssize_t n = ReadFill(inFd, in, kInChunkSize);
        if (n < 0) {
            SetError(error, "inflateFile", "read failed");
            status = -1;
            break;
        }
        if (n == 0) {
            SetError(error, "inflateFile", "unexpected end of gzip stream");
            status = -1;
            break;
        }
        strm.next_in = in;
        strm.avail_in = static_cast<uInt>(n);
        do {
            strm.next_out = out;
            strm.avail_out = kOutChunkSize;
            ret = inflate(&strm, Z_NO_FLUSH);
            if (ret != Z_OK && ret != Z_STREAM_END && ret != Z_BUF_ERROR) {
                if (ret == Z_DATA_ERROR && strm.msg != nullptr) {
                    SetError(error, "inflateFile", std::string("corrupt gzip data: ") + strm.msg);
                } else {
                    SetError(error, "inflateFile", "inflate failed, code=" + std::to_string(ret));
                }
                status = -1;
                break;
            }
            size_t produced = kOutChunkSize - strm.avail_out;
            if (produced > 0) {
                if (!WriteAll(outFd, out, produced)) {
                    SetError(error, "inflateFile", "write failed");
                    status = -1;
                    break;
                }
                *total += static_cast<int64_t>(produced);
            }
        } while (strm.avail_out == 0 && ret != Z_STREAM_END);
        if (ret == Z_STREAM_END) {
            break;
        }
    }
    inflateEnd(&strm);
    free(in);
    free(out);
    return status;
}

int DeflateRun(int inFd, int outFd, int level, int64_t *total, std::string *error)
{
    unsigned char *in = static_cast<unsigned char *>(malloc(kInChunkSize));
    unsigned char *out = static_cast<unsigned char *>(malloc(kOutChunkSize));
    if (in == nullptr || out == nullptr) {
        free(in);
        free(out);
        SetError(error, "deflateFile", "out of memory");
        return -1;
    }
    z_stream strm;
    memset(&strm, 0, sizeof(strm));
    if (deflateInit2(&strm, level, Z_DEFLATED, kWindowBitsGzip, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
        free(in);
        free(out);
        SetError(error, "deflateFile", "deflateInit2 failed");
        return -1;
    }
    int status = 0;
    int ret = Z_OK;
    bool eof = false;
    while (status == 0) {
        size_t inLen = 0;
        if (!eof) {
            ssize_t n = ReadFill(inFd, in, kInChunkSize);
            if (n < 0) {
                SetError(error, "deflateFile", "read failed");
                status = -1;
                break;
            }
            inLen = static_cast<size_t>(n);
            if (inLen < kInChunkSize) {
                eof = true;
            }
        }
        strm.next_in = in;
        strm.avail_in = static_cast<uInt>(inLen);
        int flush = eof ? Z_FINISH : Z_NO_FLUSH;
        do {
            strm.next_out = out;
            strm.avail_out = kOutChunkSize;
            ret = deflate(&strm, flush);
            if (ret != Z_OK && ret != Z_STREAM_END && ret != Z_BUF_ERROR) {
                SetError(error, "deflateFile", "deflate failed, code=" + std::to_string(ret));
                status = -1;
                break;
            }
            size_t produced = kOutChunkSize - strm.avail_out;
            if (produced > 0) {
                if (!WriteAll(outFd, out, produced)) {
                    SetError(error, "deflateFile", "write failed");
                    status = -1;
                    break;
                }
                *total += static_cast<int64_t>(produced);
            }
        } while (strm.avail_out == 0 && ret != Z_STREAM_END);
        if (ret == Z_STREAM_END) {
            break;
        }
        if (eof && inLen == 0) {
            // 空输入收尾后仍未到 STREAM_END 属异常，防御性退出
            SetError(error, "deflateFile", "unexpected deflate state");
            status = -1;
        }
    }
    deflateEnd(&strm);
    free(in);
    free(out);
    return status;
}

void Execute(napi_env env, void *data)
{
    AsyncWork *async = static_cast<AsyncWork *>(data);
    WorkRequest &req = async->request;
    const std::string tag = req.inflate ? "inflateFile" : "deflateFile";

    int inFd = open(req.inPath.c_str(), O_RDONLY);
    if (inFd < 0) {
        req.error = tag + ": open input failed, errno=" + std::to_string(errno);
        return;
    }
    int outFd = open(req.outPath.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (outFd < 0) {
        close(inFd);
        req.error = tag + ": open output failed, errno=" + std::to_string(errno);
        return;
    }

    int64_t total = 0;
    int status = req.inflate ? InflateRun(inFd, outFd, &total, &req.error)
                             : DeflateRun(inFd, outFd, req.level, &total, &req.error);
    close(inFd);
    if (status == 0 && fsync(outFd) != 0) {
        status = -1;
        req.error = tag + ": fsync failed, errno=" + std::to_string(errno);
    }
    close(outFd);
    if (status == 0) {
        req.written = total;
    } else {
        // 失败不留残缺输出
        unlink(req.outPath.c_str());
    }
}

void Complete(napi_env env, napi_status status, void *data)
{
    AsyncWork *async = static_cast<AsyncWork *>(data);
    if (!async->request.error.empty()) {
        napi_value errMessage = nullptr;
        napi_create_string_utf8(env, async->request.error.c_str(), NAPI_AUTO_LENGTH, &errMessage);
        napi_value err = nullptr;
        napi_create_error(env, nullptr, errMessage, &err);
        napi_reject_deferred(env, async->deferred, err);
    } else {
        napi_value result = nullptr;
        napi_create_int64(env, async->request.written, &result);
        napi_resolve_deferred(env, async->deferred, result);
    }
    napi_delete_async_work(env, async->work);
    delete async;
}

bool GetStringArg(napi_env env, napi_value value, std::string *out)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return false;
    }
    if (length == 0) {
        out->clear();
        return true;
    }
    std::vector<char> buf(length + 1);
    size_t copied = 0;
    if (napi_get_value_string_utf8(env, value, buf.data(), buf.size(), &copied) != napi_ok) {
        return false;
    }
    out->assign(buf.data(), copied);
    return true;
}

napi_value StartStream(napi_env env, napi_callback_info info, bool inflate)
{
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    if (argc < 2) {
        napi_throw_type_error(env, nullptr, "expected (inPath: string, outPath: string[, level: number])");
        return nullptr;
    }
    AsyncWork *async = new AsyncWork();
    async->request.inflate = inflate;
    if (!GetStringArg(env, args[0], &async->request.inPath) ||
        !GetStringArg(env, args[1], &async->request.outPath)) {
        delete async;
        napi_throw_type_error(env, nullptr, "string arguments expected");
        return nullptr;
    }
    if (!inflate && argc >= 3) {
        int32_t level = kDeflateLevelDefault;
        if (napi_get_value_int32(env, args[2], &level) == napi_ok && level >= 0 && level <= 9) {
            async->request.level = level;
        }
    }
    napi_value resourceName = nullptr;
    napi_create_string_utf8(env, "kdbxweb_zlib_stream", NAPI_AUTO_LENGTH, &resourceName);
    napi_value promise = nullptr;
    if (napi_create_promise(env, &async->deferred, &promise) != napi_ok) {
        delete async;
        napi_throw_error(env, nullptr, "create promise failed");
        return nullptr;
    }
    if (napi_create_async_work(env, nullptr, resourceName, Execute, Complete, async,
                               &async->work) != napi_ok) {
        delete async;
        napi_throw_error(env, nullptr, "create async work failed");
        return nullptr;
    }
    napi_queue_async_work(env, async->work);
    return promise;
}

napi_value InflateFile(napi_env env, napi_callback_info info)
{
    return StartStream(env, info, true);
}

napi_value DeflateFile(napi_env env, napi_callback_info info)
{
    return StartStream(env, info, false);
}

napi_value Init(napi_env env, napi_value exports)
{
    napi_property_descriptor desc[] = {
        {"inflateFile", nullptr, InflateFile, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"deflateFile", nullptr, DeflateFile, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    DefineChaCha20(env, exports);
    return exports;
}

} // namespace

static napi_module g_zlibStreamModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "kdbxweb_zlib",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterKdbxwebZlibModule(void)
{
    napi_module_register(&g_zlibStreamModule);
}
