# sftp-ohos

KeePassHO 的原生 SFTP 客户端（russh 0.46 + russh-sftp 2.4 + napi-ohos 1.2.0），
替换 exec 式的 `@ohos-rs/ssh`（libssh.so 5.8MB → 三 ABI 各约 2.3-2.7MB）。

修复的核心问题：旧实现的 `exists()` 对任意错误返回 false，导致 SFTP 数据库在
网络抖动/超时后被"最近文件"逻辑误删记录。新实现仅当服务器明确报告
NO_SUCH_FILE 时返回 false，网络/超时错误一律上抛（错误消息编码 `[sftp:{code}]`）。

## 目录

- `src/client.rs` — `SshClientCore`：连接/认证/SFTP 全部方法（纯 Rust，host 可测）
- `src/sftp.rs` — `FileStat` 模型与转换
- `src/error.rs` — 错误码枚举与 russh/russh-sftp 错误映射
- `src/lib.rs` — napi-ohos 绑定（仅 `cfg(target_env = "ohos")` 编译）
- `tests/integration.rs` — 进程内 SSH+SFTP server 协议级集成测试（16 用例）

## 构建

前置条件：

1. rustup 三 target：`rustup target add aarch64-unknown-linux-ohos armv7-unknown-linux-ohos x86_64-unknown-linux-ohos`
2. `.cargo/config.toml` 按本机 NDK 路径配置（模板见 `.cargo/config.toml.example`）

```bash
# host 单测（无需设备）
source ~/.cargo/env && cargo test

# 三 ABI 交叉编译 + 拷贝到 ../sftp/libs/<abi>/ + 打包 ../sftp-ohos.har
./build.sh
```

## 打包格式（重要踩坑）

`.har` 必须是 **gzip tar（根前缀 `package/`）**，不是 zip：ohpm 以 tarball 读取
oh-package.json5，zip 布局报 `readPkgJson failed`。且依赖必须指向归档文件
（`"sftp-ohos": "file:../libs/sftp-ohos.har"`）而非目录——目录 file: 依赖是符号链接，
真实路径不属于任何 hvigor 模块，构建报 `Failed to resolve OhmUrl ... imported by "undefined"`。
以上步骤已固化在 `build.sh`。

## ArkTS 侧

- HAR 源目录：`libs/sftp/`（index.ets re-export `libsftp_ohos.so` + 手写 `libs/index.d.ts`）
- 消费方：`entry/src/main/ets/storage/ftp/SFTPHandler.ets`（含 `SftpErrorCode` 解析）
- `libsftp_ohos.so` 文件名由 crate 名推导，ArkTS import 路径必须逐字符一致

## 验证

- host：`cargo test`（16/16，含 NO_SUCH_FILE/NetworkError/超时语义）
- ArkTS：`devecocli build --product mac_debug`（本机）+ `--modules entry@ohosTest`
- 设备：`hdc shell aa test -b com.aimilin.keepassho -m entry_test -s unittest OpenHarmonyTestRunner -s class SFTPHandlerTest -s timeout 60000`
