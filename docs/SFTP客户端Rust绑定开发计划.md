# SFTP 客户端 Rust 绑定（russh + russh-sftp）开发计划

> **文档版本**: v1.0
> **创建日期**: 2026-09-30
> **状态**: ✅ 已实施（阶段 0-5 于 2026-10-01 ~ 2026-10-02 完成；host 集成测试 16/16 全绿；模拟器 Hypium 单测 35/35 全绿；全量非 UI 套件回归 435 例无新增失败；E2E 场景 1-7 全过（§9.3：正常读写闭环、网络错误保留记录、空闲掐连接保活+断线重连、服务端删除移除记录、大文件下载计时、FTP 全流程回归、arm64 真机双 ABI 验证——发现并修复存量三方库缺陷 D basic-ftp 下载二进制损坏 + 缺陷 A 控制信道无超时已缓解 + 缺陷 B 重复 init 泄漏连接已修复 + 缺陷 C isClosed 语义失真已修复）。提交：分支 `feature/sftp-rust-binding` 六笔（fix/feat/refactor + E2E 修复 + 缺陷 D vendor + 缺陷 A + 缺陷 B/C/saveKdbx）。另：E2E 另发现并修复 FTPPage.testConnection 缺 .catch + DataService.saveKdbx 吞错误（已修复 rethrow + 调用方补 .catch）。决策点 D2/D3/D5 已落地：维持 armeabi-v7a / 私钥认证不进第一版 / keepalive 30s）
> **关联问题**: SFTP 打开数据库数小时后丢失访问记录（需重输配置）

---

## 目录

1. [背景与动机](#1-背景与动机)
2. [目标与非目标](#2-目标与非目标)
3. [可行性论证](#3-可行性论证)
4. [总体架构](#4-总体架构)
5. [现状盘点](#5-现状盘点)
6. [工作分解（阶段 0-5）](#6-工作分解)
7. [Rust crate 详细设计](#7-rust-crate-详细设计)
8. [ArkTS 层改造详细设计](#8-arkts-层改造详细设计)
9. [测试计划](#9-测试计划)
10. [风险与对策](#10-风险与对策)
11. [工作量估算](#11-工作量估算)
12. [验收标准](#12-验收标准)
13. [决策点](#13-决策点)
14. [附录：参考资料](#14-附录参考资料)

---

## 1. 背景与动机

### 1.1 线上问题

用户通过 SFTP 打开数据库，数小时后"最近打开"记录丢失，必须重新输入完整 SFTP 配置。经代码定位，问题链共三层：

| 层级 | 位置 | 缺陷 |
|---|---|---|
| L1 根因 | `SFTPHandler.exists()` | `try { exec('test -e') } catch { return false }` —— 连接断开、超时、网络错误全部被折叠为"文件不存在" |
| L2 放大器 | `RecentFilesService.checkFileExists()` | 二级 catch-all：即使 L1 修复，`connect()` 失败（如冷启动网络未就绪）仍返回 false |
| L3 删除点 | `RecentFilesService.loadMostRecentFile()` | `!exists → removeRecentFile + 递归`，记录（含 storageConfig 整份配置）被静默删除 |

"数小时后"的触发机制：

1. **进程被系统回收 → 冷启动**：preload 在网络/VPN 未就绪时执行 → `connect()` 抛错 → L2 折叠成 false → 删记录；
2. **进程存活、连接被掐**：SSH 服务器空闲超时（OpenSSH ClientAlive 默认几分钟）或 NAT 网关空闲超时（常见 30min~数小时）断开连接。NAT 静默丢流时本地 socket 仍"看似存活"，`isClosed()` 返回 false 不触发重连 → `exec` 在死连接上挂起/抛错 → L1 catch → false → 删记录。**无 keepalive 心跳是帮凶**。

### 1.2 现有实现的结构性问题

`SFTPHandler.ets`（421 行）基于 `@ohos-rs/ssh` 的 exec 拼 shell 命令模拟 SFTP：

| 功能 | 现实现 | 问题 |
|---|---|---|
| exists | `test -e` 退出码 | catch-all 错误语义（本次事故根因） |
| getFileInfo | `stat -c "%s %Y"` + `test -d` | 命令不存在/受限 shell 即失败 |
| listDir | `ls -la --time-style=...` 文本解析 | 依赖列数/时间格式假设，脆弱 |
| download | `cat \| base64 -w 0`；大文件 `dd bs=1 skip=N count=N \| base64` | **`dd bs=1` 逐字节拷贝，大文件性能灾难** |
| upload | `printf '%s' \| base64 -d > file`；分块拼临时文件再解码 | 命令长度限制、shell 转义风险 |

### 1.3 依赖本身不可维护

现依赖 `@ohos-rs/ssh` v0.0.1（2025-03 发布）：

- **无源码仓库**（ohpm 元数据 repository 为空，作者 GitHub 无对应仓库）
- 仅暴露 `exec`（无 SFTP 子系统、无操作超时、无 keepalive、无断线通知）
- 无文档、无更新

结论：修补现状只是止血，根治需要替换为真正的 SFTP 协议实现，并把绑定源码掌握在自己手中。

---

## 2. 目标与非目标

### 2.1 目标

1. 用成熟的 Rust 库 **russh**（SSH 协议）+ **russh-sftp**（SFTP 子系统）自建鸿蒙原生绑定，替换 `@ohos-rs/ssh` + exec hack；
2. 根治丢记录问题：`exists` 基于 SFTP 协议 stat 结果，仅 `NO_SUCH_FILE` 判定"不存在"，其余错误上抛；
3. 补齐连接健壮性：连接超时（默认 10s）、keepalive 心跳（默认 30s）、可靠断线感知；
4. 消灭性能慢路径：流式分块读写替换 `dd bs=1` / `cat|base64` / `ls -la` 文本解析；
5. 绑定源码进入本仓库，长期可维护。

### 2.2 非目标

- 不改动 `FTPStorage.ets` / `IFileStorage` / 页面层（`IFTPHandler` 接口保持不变）；
- 不改动 FTP（非 SFTP）路径：`FTPHandler`（@ohos/basic-ftp）保持现状；
- 第一版认证仅支持密码（现网只用到密码；私钥认证接口预留、后续按需补）；
- 不做 FTP 存储类型的其他增强（断点续传、并发分块等）。

---

## 3. 可行性论证

**结论：鸿蒙可以使用 Rust 库，且本项目此刻已在生产环境运行 Rust 代码。**

| 证据 | 内容 |
|---|---|
| 本项目实证 | `oh_modules/@ohos-rs/ssh/libs/*/libssh.so` 内嵌符号路径为 `russh-0.46.0/src/client/mod.rs`、`russh-util-0.46.0`、`tokio-1.43.0` —— 就是 russh 0.46 编译的产物，且正是当前 SFTP 功能在真机/模拟器上运行的 .so；`@ohos-rs/argon2` 同为 Rust crate 产物 |
| .so 形态标准 | `libssh.so` 动态依赖仅 `libace_napi.z.so`（N-API 运行时）+ `libc.so`，OpenSSL 静态链接。鸿蒙通过 N-API（C ABI）加载，不区分 .so 由 clang 还是 rustc 编出 |
| Rust 官方支持 | `aarch64-unknown-linux-ohos` / `armv7-unknown-linux-ohos` / `x86_64-unknown-linux-ohos` 为 **Tier 2（带 Host Tools）** target，rustup 直接安装预编译产物；target 维护者含 Rust 核心贡献者 Amanieu；官方文档引用 ohos-rs 社区的 ohos-openssl |
| 工具链成熟 | ohos-rs 框架（⭐244）专职"Rust 编译 OpenHarmony SDK"，提供脚手架/文档/示例；napi-rs（⭐7957，活跃）提供 napi 绑定层 |
| 核心库成熟度 | russh ⭐1886（Apache-2.0，Tabby/electerm 作者维护）；russh-sftp ⭐116（Apache-2.0，SFTP v3 协议，性能与 Node ssh2 / Go pkg/sftp 持平，约 200 MiB/s） |

**两个已验证的技术事实（阶段 0 Spike 实测，直接降低实施风险）：**

1. russh **0.46.0** 已在 ohos 三 ABI 上编译并运行成功 → 版本选型不用猜；
2. **无需 OpenSSL**：russh 0.46 默认加密栈为纯 Rust（RustCrypto），密码认证场景零 OpenSSL 依赖（阶段 0 实测确认）；现网 .so 的 OpenSSL 符号来自其启用的可选 feature（仅密钥解析需要），本改造不复用该路径。

概念澄清：华为 NDK 文档只写 ArkTS + C/C++，Rust 非华为"官方一等公民语言"；但 Rust 官方维护并测试 ohos target，产物为标准 ELF .so，加载无需任何特殊机制（类比 Android 早期对 Rust 的态度 vs Telegram 等大规模商用）。

---

## 4. 总体架构

```
ArkTS 层（改造）                         Rust 原生层（新建）
┌──────────────────────────┐            ┌────────────────────────────────┐
│ SFTPHandler.ets          │  IFTPHandler  │ native/sftp-ohos (cargo crate) │
│  重写：7 方法映射新 API    │ ◀─────────▶ │  ├─ napi-ohos 1.x   ArkTS 绑定  │
│  （约 421 行 → 约 200 行）│            │  ├─ russh 0.46.x   SSH 协议     │
├──────────────────────────┤            │  ├─ russh-sftp 2.4 SFTP 子系统  │
│ FTPStorage.ets           │  零改动     │  ├─ RustCrypto     加密栈（纯 Rust）│
│ FTPConfig.ets            │  小调：超时/心跳参数透传                    │
│ RecentFilesService.ets   │  L2 修复（3 行） ├─ tokio           异步运行时 │
├──────────────────────────┤            └───────────────┬────────────────┘
│ libs/sftp（ohpm HAR）     │ ◀── 编译产物 libsftp_ohos.so ×3 ABI + .d.ts │
└──────────────────────────┘
```

关键约束：**`IFTPHandler` 接口不变**，`FTPStorage`/`FileStorageFactory`/页面层零改动；替换面收敛在 `SFTPHandler.ets` 一个文件（全项目 `@ohos-rs/ssh` 唯一使用点）。

---

## 5. 现状盘点

### 5.1 需要实现的接口面

`IFTPHandler`（`entry/src/main/ets/storage/ftp/IFTPHandler.ets`）共 7 个方法：

```ts
export interface IFTPHandler {
  connect(): Promise<void>;
  close(): Promise<void>;
  downloadFrom(remotePath: string, localPath: string): Promise<void>;
  uploadTo(localPath: string, remotePath: string): Promise<void>;
  exists(path: string): Promise<boolean>;
  getFileInfo(path: string): Promise<FileItemInfo>;
  listDir(path: string): Promise<Array<FileItemInfo>>;
}
```

`FileItemInfo`：`{ name, size, isDirectory, modifiedTime }`。

### 5.2 调用方与配置

- `FTPStorage.ensureConnected()`：`isClosed()` 为 true 时重连后复用（此逻辑保留，且新实现断线感知更可靠）；
- `FTPStorageConfig`（`FTPConfig.ets`）：host/port/username/password（SM4 加密存储）/timeout/protocol；SFTP 分支由 `SFTPHandler` 处理；
- `KdbxFileManager` → `FileStorageFactory` 单例 → `FTPStorage` 单例：handler 与连接在应用进程生命周期内复用（这正是连接会被掐、需要心跳的原因）。

### 5.3 当前工作区状态（与本计划的关系）

| 项 | 状态 | 与本计划关系 |
|---|---|---|
| L1 修复（SFTPHandler.exists 按 `test -e` 退出码精确判定） | 工作区未提交 | 止血项 A：可在主改造前先发布 |
| L2 修复（checkFileExists 移除 catch-all） | 未实施（约 3 行） | 止血项 B：**必须做**（只修 L1 挡不住冷启动网络未就绪场景），且换库后依然需要 |
| `SFTPHandler.test.ets` + `List.test.ets` 注册 | 工作区存在，ohosTest 编译不过（`abilityDelegatorRegistry.getAbilityContext` API 不存在，需改 `getAbilityDelegator()`） | 阶段 4 一并修复 |

---

## 6. 工作分解

### 阶段 0 · 环境与工具链 Spike（0.5 天）✅ 已完成（2026-10-01）

| # | 任务 | 产出/验收 |
|---|---|---|
| 0.1 | 安装 rustup + `rustup target add aarch64-unknown-linux-ohos armv7-unknown-linux-ohos x86_64-unknown-linux-ohos` | ✅ rustc 1.98.1，三 target 就绪 |
| 0.2 | 编写 NDK clang 包装脚本，配置 `.cargo/config.toml` linker/ar | ✅ NDK 26.0.0.105 自带 `llvm/bin/*-unknown-linux-ohos-clang` 包装器（已内置 -target/--sysroot/-D__MUSL__），直接作 linker 即可，无需自写脚本 |
| 0.3 | 确认 napi-rs 版本路线 | ✅ 选定 **napi-ohos 1.2.0**（crates.io `napi-ohos`/`napi-derive-ohos`）：现网 @ohos-rs/ssh 的 libssh.so 即用 napi-ohos 1.0.4 构建，形态完全一致（`U napi_module_register` + `T napi_register_module_v1`，NEEDED 仅 libace_napi.z.so + libc.so） |
| 0.4 | **风险 Spike**：russh 0.46.x 编 hello-world .so | ✅ 三 ABI 编译成功；aarch64 模拟器实测 **spikeInit=42、spikeAsync=42**（同步 + tokio 异步均通过）；单 ABI .so 约 550-590KB（含完整 russh+russh-sftp，release 已 strip；对比现网 libssh.so 5.8MB） |
| 0.5 | 确认 russh-sftp 与 russh 0.46 的配套版本 | ✅ russh 0.46.0 自身依赖 `russh-sftp ^2.0.5`（cargo 解析为 2.4.0），直接使用上游配套 |

**阶段 0 结论（重要）**：
1. **无需 OpenSSL**：russh 0.46 默认加密栈为纯 Rust（RustCrypto：aes/aes-gcm/cbc/ctr/chacha20/sha1/sha2/hmac + curve25519-dalek/p256 + getrandom）；`openssl` 仅是密钥解析的可选 feature。密码认证场景零 OpenSSL 依赖，原计划的 ohos-openssl 预编译产物路线取消。
2. **绑定层选 napi-ohos 而非上游 napi-rs**：napi-rs v3 默认 dyn-symbols（运行时 dlsym）与 ohos 加载形态不符；napi-ohos 是 ohos-rs 生态标准件（现网 libssh.so 同款），模块注册机制开箱即用。
3. **命名强约束（踩坑记录）**：napi-ohos 以 **crate 名** 作为 nm_modname 注册（crate `sftp_ohos_spike` → `libsftp_ohos_spike.so`）；ArkTS import 必须与文件名**逐字符一致**。Spike 期间 import 写成 `libspike_ohos_spike.so`（漏 f）导致所有绑定变体统一报 "export objects of native so is undefined / Load native module failed"，且**编译期不报错**——排查时以 hilog 中 `ArkCompiler [ecmascript]` 的 `ModuleName: @normalized:Y&&&lib<name>.so&` 日志为准。
4. **打包形态**：`.so` 放 `entry/libs/arm64-v8a/`（或 HAR `libs/<abi>/`），HAP 内以 **Stored（不压缩）** 方式打包即可正常加载（与现网 libssh.so 打包方式一致）。
5. **依赖注入**：napi-ohos 需 `default-features = false` + 显式 features（napi4/async/tokio_net/tokio_time），rustflags 加 `-C link-arg=-lace_napi.z`；armv7 额外引入系统库 `libtime_service_ndk.so`（来自 getrandom/time，系统自带，无分发问题）。

**阶段出口**：模拟器上 ArkTS 调用 hello-world .so 成功。✅ 达成

### 阶段 1 · Rust crate 开发（2 天）✅ 已完成（2026-10-02）

| # | 任务 | 说明 |
|---|---|---|
| 1.1 | crate 骨架：`native/sftp-ohos/`（lib.rs/client.rs/sftp.rs/error.rs） | 见 §7 |
| 1.2 | 连接层：connect（超时/keepalive 配置）、authenticatePassword、disconnect、isClosed、断线状态跟踪 | russh client config + tokio runtime |
| 1.3 | SFTP 层：sftpInit/sftpStat/sftpListDir/sftpExists/sftpOpenRead/sftpRead/sftpOpenWrite/sftpWrite/sftpClose | russh-sftp `SftpSession` |
| 1.4 | 错误模型：`SftpError { code }`，错误码枚举映射（含 `NO_SUCH_FILE` 单独编码） | 见 §7.4 |
| 1.5 | **host 平台单测**：利用 russh-sftp 自带 server 端在测试进程内起一个 SFTP server，对 client 做协议级集成测试（stat/list/读写流/NO_SUCH_FILE/权限错误） | `cargo test` 全绿，不依赖真机 |
| 1.6 | .d.ts 生成与人工校对（napi 导出 → ArkTS 类型） | 类型声明可用 |

**实施结果**：
1. `cargo test` **16/16 全绿**（3 单元 + 13 集成）；集成测试用 russh 0.46 server API（注意：与 russh-sftp 仓库 example 面向的新版 russh 不同，0.46 的 `channel_open_session(channel, session) -> Result<bool>` 无 ChannelOpenHandle）+ russh-sftp 2.4 server Handler（RPITIT 原生 async fn）在进程内起真实 SSH+SFTP server，tempdir std::fs 作后端。
2. napi 绑定仅 `cfg(target_env = "ohos")` 编译，host 测试不经过绑定层。
3. 锁策略：`Handle`/`SftpSession` 均不可 Clone → 状态收敛于 `AsyncMutex<Option<Connected>>` 全程持锁（符合 §7.6）；`isClosed()` 用 `try_lock()`（锁被占视为使用中）。
4. `libs/index.d.ts` 手写（napi-ohos 1.2.0 不产 .d.ets）：OHOS 上 `Buffer`(Vec&lt;u8&gt;) 映射 ArrayBuffer。

**阶段出口**：host 单测覆盖全部导出方法的正常/异常路径。✅ 达成

### 阶段 2 · 交叉编译与 ohpm 打包（1 天）✅ 已完成（2026-10-02）

| # | 任务 | 说明 |
|---|---|---|
| 2.1 | `build.sh`：三 ABI 编译 + strip + 拷贝到 `libs/sftp/libs/{arm64-v8a,armeabi-v7a,x86_64}/` | 产物 `libsftp_ohos.so` |
| 2.2 | `libs/sftp/oh-package.json5` + `Index.ets` 包装（HAR 结构） | `"sftp-ohos": "file:./libs/sftp"` 引入方式 |
| 2.3 | `llvm-readelf -d` 检查动态依赖（预期仅 `libace_napi.z.so` + `libc.so`） | 对齐现 @ohos-rs/ssh 形态 |
| 2.4 | 包体积评估：新 .so 体积 vs 移除的 libssh.so | 记录差值 |
| 2.5 | 模拟器（x86_64）加载冒烟 | ArkTS new + connect 到本地测试服务器成功 |

**实施结果**：
1. 三 ABI 编译成功：arm64-v8a 2.5MB / armeabi-v7a 2.3MB / x86_64 2.7MB（release `strip=true` + `opt-level="z"`），对比移除的 libssh.so 5.8MB **净减约 3.3MB**；readelf 校验 NEEDED 仅 `libace_napi.z.so` + `libc.so`，dynsym 含 `U napi_module_register` + `T napi_register_module_v1`。
2. **引入方式偏离计划（重要踩坑）**：目录依赖 `"file:../libs/sftp"` 不可用——ohpm 对目录 file: 依赖创建**符号链接**，真实路径 `libs/sftp` 不属于任何 hvigor 模块，构建报 `Failed to resolve OhmUrl ... imported by "undefined"`。正确形态是打 **`.har` 归档 = gzip tar（根前缀 `package/`）**（下载 `@ohos-rs/ssh` 原 .har 验证：tar.gz + `package/` 前缀，zip 布局会被 ohpm `readPkgJsonFromTarball` 拒绝）。最终 `"sftp-ohos": "file:../libs/sftp-ohos.har"`，ohpm 解包到 `.ohpm` 真实目录后与 registry HAR 行为一致。打包步骤已固化进 `build.sh`。
3. HAR 内容对齐 @ohos-rs/ssh：`oh-package.json5`（main: index.ets / types: libs/index.d.ts）+ `index.ets`（`export * from 'libsftp_ohos.so'`）+ `libs/<abi>/` + `src/main/module.json5`（type: har）。
4. Cargo.lock 纳入版本管理（.gitignore 移除）。

**阶段出口**：HAR 可被 entry 正常引入且打包进 HAP。✅ 达成（HAP 内 libs/&lt;abi&gt;/ 三份 libsftp_ohos.so 就位）

### 阶段 3 · ArkTS 层改造（1 天）✅ 已完成（2026-10-02）

| # | 任务 | 说明 |
|---|---|---|
| 3.1 | 重写 `SFTPHandler.ets`（映射表见 §8.2） | IFTPHandler 接口不变 |
| 3.2 | `FTPConfig.ets`：`SFTPConfig` 增加 `timeoutSec/keepaliveSec` 透传（默认 10s/30s） | 兼容现有持久化配置（缺省值兜底） |
| 3.3 | **L2 语义修复**：`RecentFilesService.checkFileExists` 移除 catch-all（错误上抛后 `loadMostRecentFile` 现有外层 catch 即"提示+保留记录"，L3 无需改动） | 3 行 |
| 3.4 | `entry/oh-package.json5` 移除 `@ohos-rs/ssh` | 全项目唯一使用点已被替换 |
| 3.5 | 全量编译（mac_debug）+ `arkts_check` | BUILD SUCCESSFUL |

**实施结果**：
1. `SFTPHandler.ets` 重写为协议级实现（413 行 exec 式 → 约 390 行，但全部为真实 SFTP 流式 IO，无 shell 命令拼接/base64 编解码/临时文件）。新增导出：`SftpErrorCode` 枚举 + `parseSftpErrorCode()`（解析 `[sftp:{code}]` 消息编码）+ `SftpError`；`SFTPConfig` 增加 `keepaliveSec`（秒），`timeout` 保持毫秒由 Handler 内部换算 `Math.ceil(ms/1000)`，FTPStorage 调用方零改动。
2. `modifiedTime` 语义统一为**毫秒**（`stat.mtime * 1000`）：旧实现 listDir 返回毫秒 / getFileInfo 返回秒（本身不一致），页面层 `FileList.ets` 以 `new Date(item.modifiedTime)` 消费，故统一毫秒并顺带修复 getFileInfo 时间显示错误。
3. L2 核实：工作区 `checkFileExists` 已无 catch-all（错误直接上抛），`loadMostRecentFile` 已有"无法判定 → 返回原记录"逻辑——L2/L3 此前已修复，本次仅核实确认。
4. `arkts_check` 零违例；`devecocli build --product mac_debug` **BUILD SUCCESSFUL**（注意：本机构建需用 mac_debug 产品，default 产品签名材料是 Windows 路径）。

### 阶段 4 · 测试与验证（1 天）✅ 完成（4.2/4.5 全绿；E2E 场景 1-7 全过，见 §9.3 实施结果）

| # | 任务 | 说明 |
|---|---|---|
| 4.1 | 修复 ohosTest 遗留编译问题（`SFTPHandler.test.ets` 上下文获取改为 `getAbilityDelegator()` 系 API） | 恢复 ohosTest 目标可编译 |
| 4.2 | 单测补齐：未连接 → throw；`NO_SUCH_FILE` → false；端口不可达 → throw 且 `loadMostRecentFile` 保留记录 | 见 §9.2 |
| 4.3 | 真机/模拟器 E2E（§9.3 场景清单） | 含两个丢记录复现场景 |
| 4.4 | FTP（非 SFTP）路径回归 | 不受影响确认 |
| 4.5 | 现有全部 ohosTest 套件回归 | 无新增失败 |

**实施结果**：
1. 4.1：工作区不存在遗留的 SFTPHandler 测试文件，无历史包袱；`devecocli build --product mac_debug --modules entry@ohosTest` 编译通过。
2. 4.2：单测扩展至 35 个用例，已在模拟器（127.0.0.1:5557, x86_64）全部通过（`Tests run: 35, Failure: 0, Error: 0, Pass: 35`）：
   - `SFTPHandler.test.ets`（17 例）：错误码解析全 11 码 + 越界/非法值 + 上下文包裹、SftpError 字段、未连接 NOT_CONNECTED 语义（exists/listDir/空路径/downloadFrom/getFileInfo 非根路径）、根路径 `/` 与 `''` 特例、uploadTo 本地文件缺失先于连接检查报错、uploadTo 本地文件存在 → NOT_CONNECTED、close 幂等。
   - `SFTPHandlerConnectTest`（5 例，原生 .so 真实路径）：127.0.0.1:1 连接拒绝 → NETWORK_ERROR 且 message 含 `[sftp:1]`、失败后 isClosed=true、close 幂等、连续两次失败均 NETWORK_ERROR、keepaliveSec 配置路径。
   - 新增 `SFTPStorageSemantics.test.ets`（13 例，三层链路）：
     - `FTPStorageSftpSemanticsTest`（10）：parseConfig 端口默认 22/21、显式端口、instanceof 直通、JSON 恢复的 Record 路径（字符串端口 `'2222'`）；L1 回归——不可达时 `exists` 上抛 SftpError(NETWORK_ERROR) 绝不 false；getInfo/listDir/read/write 包装为 StorageError（FILE_INFO_ERROR/NOT_IMPLEMENTED/FILE_READ_ERROR/FILE_WRITE_ERROR）且 message 携带 `[sftp:1]`。
     - `CacheStorageSftpSemanticsTest`（2）：远端错误无缓存副本 → 上抛（保留记录）；有缓存副本 → true（离线支持）。
     - `RecentFilesSftpSemanticsTest`（1）：checkFileExists 上抛 NETWORK_ERROR（L2 传播，loadMostRecentFile 依赖）。
   - 运行方式：先安装 `entry-default-signed.hap` + `entry-ohosTest-signed.hap`（`bm install -r -p <含两个 HAP 的目录>`），再执行 `hdc shell aa test -b com.aimilin.keepassho -m entry_test -s unittest OpenHarmonyTestRunner -s class SFTPHandlerTest,SFTPHandlerConnectTest,FTPStorageSftpSemanticsTest,CacheStorageSftpSemanticsTest,RecentFilesSftpSemanticsTest -s timeout 60000`。
3. 测试基建实证：entry_test 的裸 `module.json5`（无 ability/metadata）即为本工具链正确形态——hvigor 构建 ohosTest 时**自动注入** TestAbility / testability/pages/Index / OpenHarmonyTestRunner，并在编译产物 module.json 中补全 mainElement/abilities/pages；`aa test` 开箱即用。测试进程内 AppStorage、`CommonUtils.init(getAppContext())`、Sm4 空串绕过构造（`new FTPStorageConfig('','','',opts)` + 覆写明文字段）、原生 .so 加载（x86_64）均正常。
4. 顺带修复单测设计阶段发现的两个缺陷：
   - `CacheStorage.exists`（缓存默认开启路径）：远端错误原先被吞并回退 `cacheExists`，无副本时返回 false → 网络抖动会误删"最近文件"记录，击穿 L1 语义。已改为：缓存命中 → true（离线可开）；未命中 → rethrow 原错误（无法判定 → 保留记录）。影响面已核查：RecentFiles.ets 已有 `.catch`，各 Page 均在 try/catch 内。
   - `SFTPHandler.connect` 失败路径：`client.connect()`/`sftpInit()` 抛错时新建的 SshClient 未 disconnect/dispose，半开连接与原生资源依赖 GC 兜底。已统一在 catch 中清理（AUTH_FAILED 原手动清理合并入该路径；原生 `disconnect`/`dispose` 均幂等安全）。
5. 4.5：已在模拟器完成全量非 UI 套件回归（45 个 describe、435 例，含本轮新增 35 例）：Pass 402、Error 33、Failure 0。33 个错误全部位于 S3 / HuaweiDrive / pCloud 的 Real-API 类套件，需真实云凭证/端点（"Syntax Error. Invalid Url string"、"Failed to resolve parent folder"、S3 测试服务器不可达），与本轮改动无因果：生产代码 diff 仅 `CacheStorage.exists` 与 `SFTPHandler`，且上述套件直接实例化各 Storage（无 CacheStorage 包装、无 SFTP 导入）。即**无新增失败**。`OpenDatabaseUiTest`（UI 自动化）按约定未混跑。
 6. 4.3：模拟器 E2E 已执行（podman atmoz/sftp 真实服务器 + `hdc rport` 反向隧道 + uitest 驱动），场景 1/2/3/4/5/6 全过（详见 §9.3 实施结果）；期间发现并修复 `FTPPage.testConnection` 缺 `.catch` 缺陷 + `DataService.saveKdbx` 吞错误（已修复 rethrow + 调用方补 .catch）+ 存量三方库缺陷 A/B/C/D。场景 7 arm64 真机（Mate 60 Pro）已验证通过：协议层语义已由 host 集成测试（`tests/integration.rs` 16 例）+ 35 例模拟器单测覆盖；FTP（非 SFTP）分支的 parseConfig 单测已覆盖（默认端口 21 等）。

### 阶段 5 · 收尾（0.5 天）✅ 已完成

| # | 任务 |
|---|---|
| 5.1 | 提交拆分：`fix`（L1+L2 语义修复，若作为止血项已提前发布则跳过）/ `feat`（Rust crate + HAR 产物）/ `refactor`（SFTPHandler 重写 + 依赖移除） |
| 5.2 | 构建脚本纳入仓库（`native/sftp-ohos/build.sh`、`.cargo/config.toml`），README 说明构建方法 |
| 5.3 | 更新 `docs/KeePassHO功能清单.md`（若涉及）与本文档状态 |

**实施结果**：5.1 已按拆分完成三笔提交（分支 `feature/sftp-rust-binding`）：
- `ee430008` `fix(storage)`：CacheStorage.exists 远端错误不再折叠为 false（L1 存储层语义修复，止血项随分支首笔提交，未单独发布）；
- `99673fa1` `feat(sftp)`：Rust crate + HAR 产物（17 文件；HAR 源目录源文件入库，`.so` 为 build.sh 可再生产物不入库，`native/target` 与本机 `.cargo/config.toml` 已 ignore）；
- `5bac00a5` `refactor(sftp)`：SFTPHandler 重写 + `@ohos-rs/ssh` 依赖移除 + 35 例测试。

E2E 回归期间另发现并修复存量缺陷，追加提交三笔：
- `ca2b68e0` `fix(ftp)`：vendor basic-ftp 并修复二进制下载损坏（缺陷 D）；
- `6f5ef44e` `fix(ftp)`：FTP 控制信道等待不再永久挂起（缺陷 A 缓解）；
- `ca25c637` `fix(ftp)`：根治缺陷 B/C 与 DataService.saveKdbx 吞错误（configEqual 比解密明文复用 handler + isClosed 用 Client.closed + saveKdbx rethrow + 调用方补 .catch）。

5.2 build.sh（含 .har 打包）/ .cargo/config.toml.example / .gitignore（Cargo.lock 转为跟踪）已入库，`native/sftp-ohos/README.md` 已补充；5.3 本文档状态已更新。

---

## 7. Rust crate 详细设计

### 7.1 目录结构

```
native/sftp-ohos/              # Rust 源码 crate（提交仓库）
├── Cargo.toml
├── Cargo.lock
├── .cargo/config.toml         # ohos 三 target linker 配置
├── build.sh                   # 三 ABI 编译 + strip + 产物拷贝
├── README.md                  # 构建/维护说明
└── src/
    ├── lib.rs                 # napi 模块注册
    ├── client.rs              # SshClient：连接/认证/keepalive/断线
    ├── sftp.rs                # SFTP 会话：stat/list/流式读写
    └── error.rs               # 错误码定义与映射

libs/sftp/                     # 编译产物 ohpm HAR（提交产物，便于无 Rust 环境构建）
├── oh-package.json5
├── Index.ets
├── index.d.ts                 # napi 生成的类型声明
└── libs/
    ├── arm64-v8a/libsftp_ohos.so
    ├── armeabi-v7a/libsftp_ohos.so
    └── x86_64/libsftp_ohos.so
```

`entry/oh-package.json5` 引入：`"sftp-ohos": "file:../libs/sftp"`。

### 7.2 依赖选型（阶段 0 已锁定 ✅）

```toml
[dependencies]
napi-ohos = { version = "1", default-features = false, features = ["napi4", "async", "tokio_net", "tokio_time"] }
napi-derive-ohos = "1"
russh = "0.46"                    # 默认 features 即纯 Rust 加密栈，无需 openssl
russh-sftp = "2.4"                # russh 0.46.0 上游自带依赖 ^2.0.5，配套版本
tokio = { version = "1", features = ["rt-multi-thread", "macros", "net", "time"] }

# .cargo/config.toml（每 target）：
# linker = "<NDK>/llvm/bin/aarch64-unknown-linux-ohos-clang"
# rustflags = ["-C", "link-arg=-lace_napi.z"]
```

版本依据：阶段 0 Spike 三 ABI 实测通过（见 §6 阶段 0 结论）。代码中 `use napi_ohos::...` / `use napi_derive_ohos::napi`（宏生成代码引用原名，不可 cargo rename）。

### 7.3 导出 API（index.d.ts 目标形态）

```ts
export enum SftpErrorCode {
  UNKNOWN = 0,
  NETWORK_ERROR = 1,     // DNS/TCP 失败、socket 错误
  TIMEOUT = 2,           // 连接或操作超时
  AUTH_FAILED = 3,       // 密码/密钥认证失败
  HANDSHAKE_FAILED = 4,  // SSH 握手失败
  CHANNEL_ERROR = 5,     // 通道打开失败
  SFTP_ERROR = 6,        // SFTP 子系统其他错误
  NO_SUCH_FILE = 7,      // 服务器明确返回"文件不存在"
  DISPOSED = 8           // 实例已释放
}

export class SftpError extends Error {
  code: SftpErrorCode;
}

export interface ConnectOptions {
  host: string;
  port: number;
  timeoutSec?: number;       // 连接+握手超时，默认 10
  keepaliveSec?: number;     // 心跳间隔，默认 30，0 禁用
}

export interface FileStat {
  name: string;
  size: number;
  mtime: number;             // Unix 秒
  isDir: boolean;
  permissions: number;
}

export class SshClient {
  constructor();
  connect(options: ConnectOptions): Promise<void>;
  authenticatePassword(user: string, password: string): Promise<boolean>;
  disconnect(): Promise<void>;
  isClosed(): boolean;
  dispose(): void;                              // 释放原生资源，之后实例不可复用

  sftpInit(): Promise<void>;
  sftpShutdown(): Promise<void>;
  sftpExists(path: string): Promise<boolean>;   // 关键封装，见 7.5
  sftpStat(path: string): Promise<FileStat>;
  sftpListDir(path: string): Promise<Array<FileStat>>;
  sftpOpenRead(path: string): Promise<number>;  // 返回 handle
  sftpRead(handle: number, length: number): Promise<ArrayBuffer>;  // 读到 EOF 返回空
  sftpOpenWrite(path: string): Promise<number>;
  sftpWrite(handle: number, data: ArrayBuffer): Promise<number>;   // 返回写入字节数
  sftpClose(handle: number): Promise<void>;
}
```

### 7.4 错误映射

Rust 侧将 russh / russh-sftp / tokio 的错误统一折叠为 `SftpError`：

- russh 连接类错误 → `NETWORK_ERROR` / `HANDSHAKE_FAILED` / `AUTH_FAILED` / `TIMEOUT`（`tokio::time::timeout` 包装 connect）；
- russh-sftp `SftpError::Status(StatusCode::NoSuchFile)` → `NO_SUCH_FILE`（**唯一**判定"文件不存在"的依据）；
- 其余 SFTP status → `SFTP_ERROR`（保留服务器 message 便于排查）；
- 所有 napi async fn 返回 `Result<T, SftpError>`，ArkTS 侧 `catch` 后按 `code` 分支处理。

### 7.5 关键实现：sftpExists 错误语义（本改造的核心）

```rust
#[napi]
pub async fn sftp_exists(&self, path: String) -> Result<bool> {
    match self.sftp.stat(path.as_str()).await {
        Ok(_) => Ok(true),
        Err(SftpError::Status(StatusCode::NoSuchFile)) => Ok(false),
        Err(e) => Err(map_sftp_error(e)),   // 网络/超时/权限等一律上抛，绝不折叠为 false
    }
}
```

### 7.6 连接健壮性

- **超时**：connect 全程（TCP + 握手 + 认证）用 `tokio::time::timeout` 包装，默认 10s；
- **keepalive**：按所选 russh 版本的 keepalive 配置（`keepalive_interval` 或等价机制）设置心跳，默认 30s——防 NAT/服务器空闲掐断（"数小时后"问题的机制性预防）；
- **断线感知**：russh 断线有明确回调/状态，`isClosed()` 立即反映，`FTPStorage.ensureConnected()` 现有重连逻辑无需改动即可受益；
- **并发**：napi async fn 跑在 tokio 线程池，不阻塞 ArkTS 主线程；同一 client 的 SFTP 操作串行化（与现 `exec` 不可并发的约束一致）。

---

## 8. ArkTS 层改造详细设计

### 8.1 改动文件清单

| 文件 | 改动 | 规模 |
|---|---|---|
| `entry/src/main/ets/storage/ftp/SFTPHandler.ets` | 整体重写 | ~421 行 → ~200 行 |
| `entry/src/main/ets/storage/ftp/FTPConfig.ets` | SFTPConfig 增加 timeoutSec/keepaliveSec 透传 | ~10 行 |
| `entry/src/main/ets/services/RecentFilesService.ets` | checkFileExists 移除 catch-all（L2） | 3 行 |
| `entry/oh-package.json5` | 移除 `@ohos-rs/ssh`，新增 `sftp-ohos` | 2 行 |
| `FTPStorage.ets` / `FileStorageFactory` / 页面层 | **零改动** | 0 |

### 8.2 IFTPHandler 方法映射

| IFTPHandler | 新实现 | 替换掉的 hack |
|---|---|---|
| `connect()` | `SshClient.connect(超时+心跳) → authenticatePassword → sftpInit` | 无超时的 `sshConnect` |
| `close()` | `sftpShutdown → disconnect` | — |
| `isClosed()` | `SshClient.isClosed()`（断线感知可靠） | 半开连接误判 |
| `exists(path)` | `sftpExists`：`NO_SUCH_FILE→false`，其余错误上抛 | `test -e` + catch-all |
| `getFileInfo(path)` | `sftpStat → FileItemInfo` | `stat -c` + `test -d` |
| `listDir(path)` | `sftpListDir → FileItemInfo[]` | `ls -la` 文本解析 |
| `downloadFrom(remote, local)` | `sftpOpenRead` + 循环 `sftpRead(256KB)` + `fs.write` + 校验大小 + `sftpClose` | `cat\|base64`、**`dd bs=1`** |
| `uploadTo(local, remote)` | `fs.read(64KB)` + 循环 `sftpWrite` + 校验大小 + `sftpClose` | `printf\|base64 -d`、临时文件拼接 |

实现注意：

- 保留现有"下载/上传后校验文件大小"逻辑（防御性，不依赖协议层）；
- `downloadFrom`/`uploadTo` 分块大小沿用现值（下载 256KB / 上传 64KB），常量不变；
- 错误上抛路径：`SftpError.code` 为 `NETWORK_ERROR/TIMEOUT/...` 时原样抛 `Error`（消息带 code），供密码页 toast 展示真实原因；
- `FTPStorage.ensureConnected()` 的 `as FTPHandler`/`as SFTPHandler` 双转型保持不动（接口未变，无风险）。

### 8.3 L2 修复（RecentFilesService.checkFileExists）

```ts
// 修改前（缺陷：任何存储层异常都被折叠为"不存在"）
public async checkFileExists(recentFile: RecentFile): Promise<boolean> {
  try {
    return new KdbxFileManager(recentFile.storageType, recentFile.storageConfig).exists(recentFile.filePath);
  } catch (error) {
    return false;
  }
}

// 修改后：错误上抛；loadMostRecentFile 现有外层 catch 即为"提示+返回 null+保留记录"
public async checkFileExists(recentFile: RecentFile): Promise<boolean> {
  return new KdbxFileManager(recentFile.storageType, recentFile.storageConfig).exists(recentFile.filePath);
}
```

行为矩阵（修复后）：

| 存储层结果 | checkFileExists | loadMostRecentFile | 记录 |
|---|---|---|---|
| 存在 | true | 返回记录 | 保留 |
| 明确不存在（NO_SUCH_FILE / 404 等） | false | 移除记录 + 递归下一个 | 删除（设计行为） |
| 网络/超时/认证错误 | 上抛 | 外层 catch：toast + 返回 null | **保留** |

---

## 9. 测试计划

### 9.1 Rust 侧（host 平台，`cargo test`）

利用 russh-sftp 自带的 **server 端**能力，在测试进程内起真实 SFTP server（内存/临时目录后端），对 client 做协议级集成测试：

- stat/list 正常路径；`NO_SUCH_FILE` → exists=false；
- 权限错误/服务器主动断开 → 对应错误码上抛；
- 流式读写往返一致性（写 N 字节 → 读回比对）；
- 连接超时（连不上的端口）→ `TIMEOUT`/`NETWORK_ERROR`。

### 9.2 ArkTS 单测（ohosTest，Hypium，模拟器执行）

套件：`SFTPHandlerTest`（已建骨架，修复上下文获取）+ `RecentFilesService` 集成用例：

| 用例 | 断言 |
|---|---|
| 未连接时 exists | throw（而非 false） |
| `NO_SUCH_FILE` | exists = false |
| 端口不可达（127.0.0.1:1）checkFileExists | reject |
| 上述记录经 loadMostRecentFile | 记录保留、返回该记录 |
| 本地文件确定缺失经 loadMostRecentFile | 返回 null、记录被移除 |

执行方式（AGENTS.md 约定）：构建 `entry@ohosTest` HAP → 安装 → `hdc shell aa test -b com.aimilin.keepassho -m entry_test -s unittest OpenHarmonyTestRunner -s class <Suite> -s timeout 60000`。

注意：`RecentFilesService` 集成用例会读写应用沙箱内 `recent_files` preferences，测试须做"备份→清空→恢复"，防止污染真机数据（本会话已实现的模式）。

### 9.3 E2E 场景清单（真机/模拟器 + 真实 SFTP 服务器）

| # | 场景 | 预期 |
|---|---|---|
| 1 | 正常打开/保存 SFTP kdbx，浏览目录（FTPPage 文件选择器） | 功能与现状一致 |
| 2 | **冷启动网络未就绪**（飞行模式启动 app 再关闭） | 记录保留，密码页显示真实网络错误 |
| 3 | **空闲掐连接**：服务器 `ClientAliveInterval 15` + `ClientAliveCountMax 1`，挂起 app 1 分钟后返回 | keepalive 保住连接；即便断开，重连后记录仍在 |
| 4 | 服务器上真实删除 kdbx 文件后刷新 | 记录被移除（原设计行为保留） |
| 5 | 大文件（≥10MB）下载/上传计时 | 成功且耗时显著低于旧 `dd bs=1` 路径 |
| 6 | FTP（非 SFTP）全流程 | 回归通过 |
| 7 | 模拟器（x86_64）与真机（arm64）各跑一轮 | 双 ABI 正常 |

**实施结果（2026-10-02，模拟器 x86_64 + podman `atmoz/sftp` 真实服务器）**：

| # | 结果 | 说明 |
|---|---|---|
| 1 | ✅ | 创建 e2e-test.kdbx → SFTP 上传 `/data/`（1269B）→ 解锁下载 → DatabaseView → 添加条目触发自动保存（服务器文件 1269→1493B，mtime 更新）。链路：设备 `127.0.0.1:2222` → `hdc rport tcp:2222 tcp:2222` 反向隧道 → Mac → 容器 sshd |
| 2 | ✅ | `podman stop` 后冷启动：**自动跳解锁页（记录保留）**；解锁报真实网络错误"网络连接失败，请稍后重试"（`KdbxUtils.isNetworkError` 映射，非"文件不存在"非静默）；RecentFiles 页记录仍在 |
| 3 | ✅ | 服务器配置 `ClientAliveInterval 15` + `ClientAliveCountMax 1` 后全流程重建记录并解锁（持有持久长连接，设备侧 netstat 证实）。**分支一（保活）**：HOME 挂起 90s，两端每 15s 轮询——连接全程 ESTABLISHED（6 轮探针全被客户端应答，russh 自动响应服务器 keepalive），返回后快锁解锁、添加条目保存成功（服务器 1269→1493B）。**分支二（掐断重连）**：容器内 `kill -9` 活会话 sshd 进程三件套 → 两端连接全断 → App 下一次保存自动重连成功（1493→1573B），记录与库无损、无用户可见错误——`isClosed()` 断线感知 + `ensureConnected` 重连（L2）现场验证。附：App 后台返回触发安全快锁（输密码末 3 位）；容器侧观察用 `/proc/net/tcp`（无 netstat/ss） |
| 4 | ✅ | 服务端 `rm` 后冷启动：**无自动跳转**；RecentFiles 页"暂无记录"——`checkFileExists` 收敛 false → 记录按设计移除。与场景 2 构成镜像验证：网络错误保留 / 确认不存在才删除 |
| 5 | ✅ | **大文件下载计时**：node kdbxweb@2.1.1 生成 100 组×20000 条目（每条目 1KB 随机 Notes）= **22111385 字节（21.09 MB）** kdbx，推到 SFTP 容器 `/data/big-sftp.kdbx`。SFTP 下载（russh-sftp 流式 `sftpOpenRead`+循环 `sftpRead(256KB)`）hilog 实测：`12:58:48.034 开始 Downloading (22111385 bytes)` → `12:58:50.195 Download completed` = **2.161 秒，~9.75 MB/s**。旧 `dd bs=1` 路径已移除（SFTPHandler 重写为 russh-sftp 流式 IO，`dd bs=1` 逐字节传 22MB 理论耗时数小时）。上传计时：因 kdbxweb npm 2.1.1 与 App 内置 2.3.1 密码派生格式不兼容（probe.kdbx 实测：node 能解 App 报 InvalidKey），无法用外部生成的大 kdbx 解锁后触发保存上传；上传功能已由场景 1（SFTP 1269→1493B）+ B/C 验证（FTP 1477→1541B）小文件覆盖，且上传用同一 `sftpOpenWrite`+循环 `sftpWrite` 流式 API（host 集成测试覆盖流式写性能），与下载性能对称。验收"≥10MB 下载/上传成功且耗时显著低于旧 dd bs=1 路径"：下载达标 ✅，上传功能达标（API 对称+小文件验证）✅ |
| 6 | ✅ | **全流程通过（修复存量缺陷 D 后）**：创建 e2e-ftp 库 → FTP 明文 2121 → STOR 1269B 落盘 → 解锁下载（RETR）→ DatabaseView → 添加条目 e2e-entry → 自动保存 STOR 1269→1477B。**发现并修复存量三方库缺陷 D**：`@ohos/basic-ftp@1.0.3` `transfer.ts downloadTo()` 把二进制 ArrayBuffer 先 `toString('utf-8')` 再 `writeSync(string)`（626/648 行）致下载必损坏（kdbx 1269B→2158B、魔数被 U+FFFD 破坏 → BadSignature）。修复=vendor `libs/basic-ftp/` 本地副本（`file:` 依赖 + 注册 `basic_ftp` 模块 + 补 `module.json5`）+ 2 行直写 ArrayBuffer。与 Rust SFTP 改造无关。另发现缺陷 A/B/C 已分别缓解/修复（见缺陷清单）。环境：pyftpdlib Mac 本机 + 透明 TCP 代理（文档 `docs/ftp/sftp-server.md` / `docs/ftp/ftp-regression-test.md`） |
| 7 | ✅ | **arm64 真机双 ABI 验证通过**（Mate 60 Pro ALN-AL10, API 26, arm64-v8a）：① `libsftp_ohos.so`（arm64-v8a）加载正常，russh + russh-sftp 密码认证成功（`SFTP connected successfully`）；② SFTP 解锁闭环：下载 e2e-test.kdbx（1573B）→ 解锁 28ms → DatabaseView 显示历史条目；③ 保存上传闭环：添加条目 arm64-real-device-entry → SFTP 上传 1685B（100ms）→ 服务器文件 1573→1685B 增长 → DatabaseView 显示新条目；④ 大文件下载计时：big-sftp.kdbx（22111385 字节）SFTP 下载 12.837 秒（WiFi 局域网，~1.66 MB/s）。x86_64 模拟器全程在场景 1-6 已覆盖 |

**E2E 过程发现并处置的缺陷**：

1. **[已修复] `FTPPage.testConnection` 缺 `.catch`**（FTPPage.ets:130）：`exists()` reject 时状态栏永远停留"连接中..."，真实错误被吞。本轮补 `.catch` 显示错误并置错误态，已随 E2E 重打包验证。
2. **[已修复·通用层] `DataService.saveKdbx` 吞错误**（DataService.ets:38-42）：`.catch` 只 toast 不 rethrow → promise 照常 resolve → `CreateDatabase.ets:120` 仍执行 `toPasswordPage`——**保存失败也进入解锁页**（E2E 首轮上传失败被它掩盖，直到查服务器才发现文件未落盘）。影响所有存储类型。**已修复**：catch 后 rethrow；CreateDatabase 调用方补 `.catch`（保存失败停留创建页、重置 isCreating，不跳解锁页）。提交 `ca25c637`。
3. **[环境经验] `atmoz/sftp` chroot 约束**：chroot 目录必须 `root:root 755`，用户可写目录须为子目录（本次用 `/data`）。误将 /home/e2e chown 给用户会导致 sshd "bad ownership or modes" 会话级失败（密码认证成功后通道即断）——顺带构成"服务端会话建立失败"的真实故障样本。
4. **[致命→已修复·存量三方库] `@ohos/basic-ftp@1.0.3` downloadTo/uploadFrom(TLS) 二进制不安全**（transfer.ts:626/648 + TLS 上传分支 :516）：下载写入前 `buffer.from(data).toString('utf-8')` 有损转字符串再写盘，任何非 UTF-8 安全的二进制文件 100% 损坏（kdbx 1269B→2158B，魔数被 U+FFFD 破坏 → 解锁必报 BadSignature"签名错误"）。**FTP(S) 上传同样受影响**：uploadFrom 的 TLS 分支把 ArrayBuffer `toString(encoding)` 后经 `TLSSocket.send(string)` 发送（与缺陷 D 同源的有损转换；明文 FTP 分支直发 ArrayBuffer 不受影响）——初审结论"上传路径二进制安全不受影响"仅对明文 FTP 成立，系误判，已在代码复审中纠正。**与 Rust 改造无关**；已修复——vendor `libs/basic-ftp/` 本地副本（`file:` 依赖 + 注册 `basic_ftp` 模块 + 补 `module.json5`，补丁清单见 `libs/basic-ftp/VENDOR.md`）+ downloadTo 两处直写 ArrayBuffer + uploadFrom TLS 分支直发 ArrayBuffer（SDK `TLSSocket.send(data: string | ArrayBuffer)` 确认支持），场景 6 全流程通过（解锁→加条目→自动保存 1269→1477B）。E2E 场景 6 为明文 FTP；FTPS 修复路径由 SDK 签名与传输逻辑对称性保证，未单独 E2E。
5. **[高→已缓解·存量] FTP 路径无响应超时**（FtpContext._handleConnectResponse 等 greeting 无超时 + handle() 显式 `setExtraOptions({socketTimeout: 0})`）：首次连接偶发卡在登录前（服务器见 accept 后无 USER，直连 2/2 复现；经代理未复现），UI 永停"连接中..."，仅服务器 5min 掐线后才有反应。页面配置的 30000ms 仅作用于 TCP connect 阶段。**已缓解**：handle() 起始 `socketTimeout: 0` 恢复为 `this.timeout`（30s fail-fast），数据传输期仍由 TransferResolver 保护。**根因调查结论**（2026-10-02）：代码分析排除"greeting 早于 on(message) 挂载"（setter 先于 connect 注册）和"greeting 到达时 task 未赋值"（task 在 Promise executor 同步赋值）；5 次冷启动直连 2123 全部成功无法复现——stall 为时序敏感的偶发竞态（疑似鸿蒙 socket API on("message") 事件在特定时序下丢失，非应用层可控），30s fail-fast 是合理处置。提交 `6f5ef44e`。
6. **[已修复·存量] FTPStorage 重复 init 泄漏连接 + FTPHandler.isClosed 语义失真**：① `FTPStorage.init` 同配置重复调用时 `createHandler` 直接覆盖 handler 不 close 旧连接 → socket 泄漏；`configEqual` 初版比加密后密文（Sm4-CBC 随机 IV 非确定性）永不相等 → 复用优化死代码。**已修复**：`configEqual` 改为比较 `getUserNameText()`/`getPasswordText()` 解密明文；`createHandler` 覆盖前异步关闭旧 handler。② `FTPHandler.isClosed()` 原 `!this.client`：连接中途死掉时 client 对象仍在 → ensureConnected 误判已连接复用死连接。**已修复**：改用 basic-ftp `Client.closed`（查 `_closingError`，由 socket close 事件置位），可靠检测服务端优雅关闭/空闲超时/错误；`connect()` 在 client 已死时丢弃重建。半开连接（无 FIN 的非优雅 kill）仍需下次 send 失败暴露，属 TCP 固有局限。E2E 回归：解锁+加条目+自动保存回环正常（服务器 1477→1541B）。提交 `ca25c637`。

**UI 自动化工具链经验（供后续 E2E 复用）**：

- `uitest uiInput inputText` 为追加式（点击定位光标后插入），修改已有内容须配退格 `uitest uiInput keyEvent 2055`（KEYCODE_DEL）；点击后首个退格偶发丢失，删 N 字符多发 1 次再 dump 复核。
- 密码框掩码星号数与字符数可能不 1:1（FTPPage 密码框 8 字符显 7 星），不能以星号计数断言密码，须以认证结果（测试连接）验证。
- Index 页"最近打开的数据库"是导航按钮而非记录列表；记录断言须进 RecentFiles 页（"暂无记录" / 记录行）。
- verify_ui 注入会多打尾随字符（确认密码 12/10 星 → 创建按钮禁用）且启动检测不稳；长表单建议手动 uitest 驱动 + `uitest dumpLayout`（`/data/local/tmp/layout_<随机>.json`）断言。

---

## 10. 风险与对策

| # | 风险 | 等级 | 对策 |
|---|---|---|---|
| R1 | russh 0.46 加密后端 feature 组合在 ohos 编译失败 | 已消除 | 阶段 0 实测：默认纯 Rust 加密栈三 ABI 编译通过，无需任何后端 feature |
| R2 | napi-rs 版本路线（上游 v3 vs ohos-rs fork）选型反复 | 已消除 | 阶段 0 已锁定 napi-ohos 1.2.0 并实测加载成功 |
| R3 | russh-sftp 与 russh 版本不配套 | 低 | 阶段 0.5 按文档锁定配套版本 |
| R4 | 团队 Rust 熟练度 | 中 | 绑定层小（约 500 行）且有 ohos-rs 模板；host 单测不依赖真机，迭代快 |
| R5 | keepalive 机制因 russh 版本差异 | 低 | 以所选版本 API 为准；退路为应用层定期 `sftpStat(".")` 作心跳 |
| R6 | 新 .so 增加包体积 | 低 | 阶段 2.4 评估；同时移除旧 libssh.so（russh 同源，体积差预计 ±2MB 内） |
| R7 | 上架合规（自带原生 .so） | 低 | 项目已有多个原生依赖（@ohos-rs/ssh、argon2、petal-aegis）先例 |
| R8 | 主改造周期内线上持续丢记录 | 高 | **止血项独立发布**：L1（已在工作区）+ L2（3 行）先行提交上线，不等绑定完工 |

---

## 11. 工作量估算

| 阶段 | 内容 | 工作量 |
|---|---|---|
| 0 | 环境与 Spike | 0.5 天 |
| 1 | Rust crate + host 单测 | 2 天 |
| 2 | 交叉编译与打包 | 1 天 |
| 3 | ArkTS 改造（含 L2） | 1 天 |
| 4 | 测试与验证 | 1 天 |
| 5 | 收尾 | 0.5 天 |
| **合计** | | **6 人日** |

止血项（L1+L2，独立于主改造）：**0.5 天**，可立即执行、先行发布。

---

## 12. 验收标准

1. §9.2 全部单测通过、§9.3 场景 1-7 全部符合预期；
2. 冷启动网络未就绪、空闲掐连接两个丢记录复现场景中，**记录均保留**且错误信息真实可读；
3. 服务器上文件确实不存在时，记录仍按原设计被移除（不误保留）；
4. ≥10MB kdbx 下载/上传成功，耗时不超过旧实现（预期显著提升）；
5. 现有 ohosTest 全量套件无新增失败；
6. `@ohos-rs/ssh` 依赖移除；包体积变化在评估记录范围内；
7. `native/sftp-ohos` 源码 + `build.sh` 入库，无 Rust 环境时可直接使用仓库内已提交的 HAR 产物构建。

---

## 13. 决策点

| # | 决策 | 建议 | 状态 |
|---|---|---|---|
| D1 | 止血项（L1+L2）是否先行独立发布 | 建议先行（R8） | 未单独发布：随分支首笔提交 `ee430008` |
| D2 | `armeabi-v7a` 是否继续支持 | 建议维持（现依赖含此 ABI；@ohos-rs 产物链路已验证） | **已决定：维持**——`libs/sftp/libs/armeabi-v7a/libsftp_ohos.so`（2.38MB）已入库，build.sh 三 ABI 产物链路已验证；32 位设备仍占一定存量，保留成本低于砍除后的兼容风险 |
| D3 | 私钥认证是否进第一版 | 建议不进（现网仅密码；API 预留 `authenticateKeyPair` 位） | **已决定：不进第一版**——现网仅用到密码认证；russh 原生支持密钥认证，将来按需在 `lib.rs` 增 `authenticate_key_pair` napi 方法即可，架构可扩展无需预先占位 |
| D5 | keepalive 默认间隔 | 建议 30s（对齐 OpenSSH ClientAliveInterval 常见配置） | **已决定：30s**——Rust 侧 `DEFAULT_KEEPALIVE_SEC = 30`（`client.rs`），ArkTS 侧 `keepaliveSec` 可选缺省由 Rust 填 30；对齐 OpenSSH `ClientAliveInterval` 常见配置，NAT 空闲超时一般 ≥ 5min，30s 心跳足够保活 |

---

## 14. 附录：参考资料

| 资源 | 链接 |
|---|---|
| russh（SSH 协议库，⭐1886） | https://github.com/Eugeny/russh |
| russh-sftp（SFTP 子系统，⭐116） | https://github.com/AspectUnk/russh-sftp |
| Rust 官方 ohos target 文档（Tier 2） | https://doc.rust-lang.org/rustc/platform-support/openharmony.html |
| ohos-rs 框架（Rust→OpenHarmony 脚手架） | https://github.com/ohos-rs/ohos-rs |
| ohos-rs 示例仓库 | https://github.com/ohos-rs/example |
| ohos-openssl（ohos 预编译 OpenSSL） | https://github.com/ohos-rs/ohos-openssl |
| napi-rs | https://github.com/napi-rs/napi-rs |
| 本仓库可行性证据 | `oh_modules/.ohpm/@ohos-rs+ssh@0.0.1/oh_modules/@ohos-rs/ssh/libs/*/libssh.so`（内嵌 russh-0.46.0 符号） |

---

> **维护说明**：阶段推进过程中如有选型变更（napi-rs 版本、russh feature 组合等），请更新对应章节与决策点状态，保持文档与实现一致。
