# sftp-ohos 架构与修改指南

> 用途：说明 `libs/sftp-ohos`（Rust 源码）、`libs/sftp`（HAR 材料）、`libs/sftp-ohos.har`（HAR 归档）三者的关系，以及修改 SFTP 原生模块时的标准流程与踩坑约束。
> 背景：KeePassHO 的 SFTP 存储基于 Rust（russh 0.46 + russh-sftp 2.4 + napi-ohos 1.2.0）协议级实现，替换旧的 exec 式 `@ohos-rs/ssh`（5.8MB → 三 ABI 各约 2.3-2.7MB），并修复了旧实现 `exists()` 对任意错误返回 false 导致"最近文件"记录被误删的问题。
> 姊妹文档：`libs/sftp-ohos/README.md`（Rust 工程自述）、`docs/e2e/sftp/sftp-server.md`（E2E 测试服务器）

---

## 1. 三者关系：源码 → HAR 材料 → HAR 归档 → 消费方

```
libs/sftp-ohos/              Rust 源码工程（cargo），编译产物 libsftp_ohos.so
        │  ./build.sh
        │  ├─ cargo build --target {aarch64,armv7,x86_64}-unknown-linux-ohos --release
        │  ├─ 拷贝 .so → ../sftp/libs/<abi>/
        │  └─ tar -czf 打包 ../sftp → ../sftp-ohos.har
        ▼
libs/sftp/                   HAR 库源目录（打包材料，含 .so 二进制）
        │  build.sh 末段打 gzip tar（根前缀 package/）
        ▼
libs/sftp-ohos.har           ohpm HAR 归档（git 入库，约 3.1MB，entry 唯一依赖入口）
        │  entry/oh-package.json5: "sftp-ohos": "file:../libs/sftp-ohos.har"
        ▼
entry 模块                    import { SshClient } from 'sftp-ohos'
        │
        ▼
entry/src/main/ets/storage/ftp/SFTPHandler.ets   业务消费层（IFileStorage 的 SFTP 实现）
```

一句话总结：**`libs/sftp-ohos` 是源码，`libs/sftp` 是打包材料目录，`libs/sftp-ohos.har` 是最终被 entry 依赖的归档产物**。三者同在 `libs/` 下，由 `libs/sftp-ohos/build.sh` 串成一条流水线。

## 2. 各目录职责

### 2.1 `libs/sftp-ohos/` — Rust 源码工程

| 文件 | 职责 |
|---|---|
| `src/client.rs` | `SshClientCore`：连接/认证/SFTP 全部方法（纯 Rust，host 平台可单测） |
| `src/sftp.rs` | `FileStat` 模型与转换 |
| `src/error.rs` | `SftpErrorCode` 枚举与 russh/russh-sftp 错误映射 |
| `src/lib.rs` | napi-ohos 绑定层（仅 `cfg(target_env = "ohos")` 编译），导出 ArkTS `SshClient` 类 |
| `tests/integration.rs` | 进程内 SSH+SFTP server 协议级集成测试（16 用例） |
| `build.sh` | 三 ABI 交叉编译 + 拷贝 .so + 打包 HAR（唯一构建入口） |
| `.cargo/config.toml` | 本机 NDK linker 配置（**不入库**，模板见 `.cargo/config.toml.example`） |
| `Cargo.toml` | crate 名 `sftp-ohos` → 决定产物文件名 `libsftp_ohos.so` |

### 2.2 `libs/sftp/` — HAR 库源目录（打包材料）

| 文件 | 职责 | git 入库 |
|---|---|---|
| `oh-package.json5` | 包名 `sftp-ohos`，`main: index.ets`，`types: libs/index.d.ts` | 是 |
| `index.ets` | 仅 1 行：`export * from 'libsftp_ohos.so'` | 是 |
| `libs/index.d.ts` | **手写**类型声明（与 `lib.rs` napi 绑定逐一对齐） | 是 |
| `libs/<abi>/libsftp_ohos.so` | 三 ABI 二进制产物（由 build.sh 拷贝而来） | **否** |
| `src/main/module.json5` | HAR module 声明（type: har） | 是 |

### 2.3 `libs/sftp-ohos.har` — HAR 归档

- 由 `build.sh` 从 `libs/sftp/` 打包生成的 **gzip tar（根前缀 `package/`）**，不是 zip。
- **git 入库**（约 3.1MB），是 entry 模块的唯一依赖入口——`libs/sftp/` 目录本身不直接被 entry 引用。
- 内容 = `libs/sftp/` 全量（oh-package.json5 + index.ets + libs/ + src/）。

### 2.4 消费方

- `entry/oh-package.json5`：`"sftp-ohos": "file:../libs/sftp-ohos.har"`。
- `entry/src/main/ets/storage/ftp/SFTPHandler.ets`：`import { SshClient } from 'sftp-ohos'`，含 `SftpErrorCode` 枚举与 `parseSftpErrorCode()`（用 `/\[sftp:(\d+)\]/` 解析原生层编码的错误码）。

## 3. 错误码跨语言契约（改动时必须三处同步）

原生层错误消息编码格式为 `[sftp:{code}] {detail}`，错误码数值在三处必须一致：

| 位置 | 内容 |
|---|---|
| `libs/sftp-ohos/src/error.rs` | `SftpErrorCode` 枚举（0=Unknown … 10=BadHandle，`#[repr(i32)]`） |
| `libs/sftp/libs/index.d.ts` | 手写声明中的注释说明 |
| `entry/.../ftp/SFTPHandler.ets` | `SftpErrorCode` 枚举 + `SFTP_CODE_MAP` 映射表 |

新增/调整错误码时，三处都要改，缺一处会导致 ArkTS 侧解析回 `UNKNOWN`。

## 4. 修改流程

### 场景 A：只改 Rust 内部实现（不改对外 API）

例如修 bug、调超时逻辑、换依赖版本：

```bash
cd libs/sftp-ohos
source ~/.cargo/env
cargo test                 # ① host 单测（无需设备，16 用例）
./build.sh                 # ② 三 ABI 交叉编译 + 更新 libs/sftp/libs/ + 重打 libs/sftp-ohos.har
# ③ 回项目根目录
devecocli build            # ④ 重新构建 entry（重新解包 HAR）
```

### 场景 B：新增/修改对外 API（需跨层同步）

以新增一个 `sftpMkdir(path)` 为例，按依赖顺序：

1. **Rust 核心**：`src/client.rs` 的 `SshClientCore` 加 `sftp_mkdir()`（纯 Rust，可单测）。
2. **napi 绑定**：`src/lib.rs` 的 `binding::SshClient` 加 `#[napi(js_name = "sftpMkdir")] pub async fn sftp_mkdir(...)`。
3. **类型声明**：`libs/sftp/libs/index.d.ts` 的 `SshClient` 类加 `sftpMkdir(path: string): Promise<void>`。
4. **测试**：`cargo test`（host）。
5. **打包**：`./build.sh`（更新 .so 与 .har）。
6. **ArkTS 消费方**：`SFTPHandler.ets`（或 `IFTPHandler` 接口）加对应方法。
7. **构建**：`devecocli build`。

### 场景 C：只改 ArkTS 侧包装（.d.ts 注释、index.ets）

**注意**：`libs/sftp/` 目录的任何改动都不会自动生效——entry 消费的是 `.har` 归档。改完仍需重跑 `./build.sh` 重新打包（或至少执行 build.sh 末段的 tar 打包步骤）。

### 场景 D：修改 .so 文件名 / crate 名（强烈不建议）

文件名 `libsftp_ohos.so` 由 crate 名 `sftp-ohos` 推导（napi-ohos 规则：加 `lib` 前缀 + 下划线连接 + `.so`）。改名会级联影响：

- `Cargo.toml` 的 `name` → 产物文件名；
- `libs/sftp/index.ets` 的 `export * from 'libsftp_ohos.so'`；
- `libs/sftp/libs/index.d.ts` 位置约定；
- `build.sh` 中所有 `libsftp_ohos.so` 引用；
- `.cargo/config.toml` 无需改（linker 只看 target triple）。

ArkTS import 路径必须与 `.so` 文件名**逐字符一致**，任何偏差都会在运行时报模块不存在。

## 5. 关键约束与踩坑（build.sh 已固化，勿绕过）

1. **`.har` 必须是 gzip tar，且根目录前缀为 `package/`**——ohpm 以 tarball 读取 oh-package.json5，zip 布局报 `readPkgJson failed`。
2. **entry 依赖必须指向 `.har` 归档文件，不能指向 `libs/sftp/` 目录**——目录 `file:` 依赖是符号链接，真实路径不属于任何 hvigor 模块，构建报 `Failed to resolve OhmUrl ... imported by "undefined"`。
3. **`.cargo/config.toml` 不入库**——新环境需从 `.cargo/config.toml.example` 复制并替换本机 NDK 路径（NDK ≥ API 26，`llvm/bin` 下自带 `*-unknown-linux-ohos-clang` 包装器）。
4. **rustup 三 target 前置**：`rustup target add aarch64-unknown-linux-ohos armv7-unknown-linux-ohos x86_64-unknown-linux-ohos`。
5. **napi 绑定层只在 ohos target 编译**（`cfg(target_env = "ohos")`）——host `cargo test` 不拉取 napi 依赖，核心逻辑必须放 `client.rs` 保持 host 可测。
6. **napi `Buffer` 在 OHOS ArkTS 侧表现为 `ArrayBuffer`**（见 `index.d.ts` 顶部注释）。
7. **`.so` 二进制不入库、`.har` 入库**——clone 后无需本地 Rust 工具链即可构建 entry（har 已含三 ABI 产物）；只有改 Rust 代码才需要 Rust 环境。
8. **profile.release 已调优**（`lto = true, strip = true, opt-level = "z"`），体积敏感，勿随意加依赖。

## 6. 验证清单

| 层级 | 命令 | 说明 |
|---|---|---|
| Rust 单测 | `cd libs/sftp-ohos && cargo test` | 16/16，含 NO_SUCH_FILE/NetworkError/超时语义（无需设备） |
| ArkTS 构建 | `devecocli build`（或 `devecocli build --product mac_debug`） | 验证 HAR 解包 + import 解析 |
| 设备测试 | `hdc shell aa test -b com.aimilin.keepassho -m entry_test -s unittest OpenHarmonyTestRunner -s class SFTPHandlerTest -s timeout 60000` | 真机/模拟器上的 handler 测试 |
| E2E | 见 `docs/e2e/sftp/sftp-server.md` | atmoz/sftp 容器环境，覆盖连接/读写/断线场景 |

## 7. 产物形态自检（build.sh 内置）

build.sh 对每个 ABI 执行 `llvm-readelf -d` 校验动态依赖：**NEEDED 必须仅为 `libace_napi.z.so` + `libc.so`**（对齐 @ohos-rs 产物形态）。若出现多余依赖（如 `librustls.so`），说明依赖树被静态链接配置破坏，需排查 Cargo 特性开关。
