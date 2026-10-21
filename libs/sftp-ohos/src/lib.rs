//! sftp-ohos：KeePassHO 的 SFTP 原生客户端（russh + russh-sftp）。
//!
//! 结构分层：
//! - [`client`] / [`sftp`] / [`error`]：纯 Rust 核心，host 平台可单测；
//! - `binding`（仅 `target_env = "ohos"`）：napi-ohos 绑定层，将核心能力
//!   导出为 ArkTS `SshClient` 类，错误码编码进 message（`[sftp:{code}] msg`）。
//!
//! 详细设计见 `docs/SFTP客户端Rust绑定开发计划.md` §7。

pub mod client;
pub mod error;
pub mod sftp;

pub use client::{AcceptAllKeys, ConnectParams, SshClientCore, DEFAULT_CONNECT_TIMEOUT_SEC, DEFAULT_KEEPALIVE_SEC};
pub use error::{SftpError, SftpErrorCode};
pub use sftp::FileStat;

#[cfg(target_env = "ohos")]
mod binding {
    use napi_derive_ohos::napi;
    use napi_ohos::bindgen_prelude::*;
    use napi_ohos::{Error, Status};

    use crate::client::{ConnectParams, SshClientCore};
    use crate::error::SftpError;
    use crate::sftp::FileStat as CoreFileStat;

    /// `SftpError` → napi Error。错误码编码进 message（`[sftp:{code}] msg`），
    /// ArkTS 侧用 `/\[sftp:(\d+)\]/` 解析。
    fn to_napi_err(e: SftpError) -> Error {
        Error::new(Status::GenericFailure, e.encoded_message())
    }

    fn opt_secs(v: Option<f64>) -> u64 {
        match v {
            Some(v) if v.is_finite() && v > 0.0 => v as u64,
            _ => 0,
        }
    }

    /// 连接参数（对应 index.d.ts 的 `ConnectOptions`）。
    #[napi(object)]
    pub struct ConnectOptions {
        pub host: String,
        pub port: u16,
        /// 连接+握手+认证超时（秒），缺省 10
        #[napi(js_name = "timeoutSec")]
        pub timeout_sec: Option<f64>,
        /// keepalive 心跳间隔（秒），缺省 30；0 禁用
        #[napi(js_name = "keepaliveSec")]
        pub keepalive_sec: Option<f64>,
    }

    impl ConnectOptions {
        fn to_params(&self) -> ConnectParams {
            ConnectParams {
                host: self.host.clone(),
                port: self.port,
                timeout_sec: opt_secs(self.timeout_sec),
                keepalive_sec: opt_secs(self.keepalive_sec),
            }
        }
    }

    /// 远端文件/目录条目信息（对应 index.d.ts 的 `FileStat`）。
    #[napi(object)]
    pub struct FileStat {
        pub name: String,
        /// 字节数
        pub size: f64,
        /// 修改时间（Unix 秒）
        pub mtime: f64,
        pub is_dir: bool,
        /// POSIX 权限位
        pub permissions: f64,
    }

    impl From<CoreFileStat> for FileStat {
        fn from(stat: CoreFileStat) -> Self {
            Self {
                name: stat.name,
                size: stat.size as f64,
                mtime: stat.mtime as f64,
                is_dir: stat.is_dir,
                permissions: stat.permissions as f64,
            }
        }
    }

    /// SSH+SFTP 客户端。
    ///
    /// 生命周期：`connect → authenticatePassword → sftpInit → sftp* → disconnect`。
    /// `dispose` 后实例不可复用。所有异步方法返回 Promise，跑在原生 tokio
    /// 线程池，不阻塞 ArkTS 主线程。
    #[napi(js_name = "SshClient")]
    pub struct SshClient {
        core: SshClientCore,
    }

    #[napi]
    impl SshClient {
        #[napi(constructor)]
        pub fn new() -> Self {
            Self {
                core: SshClientCore::new(),
            }
        }

        /// 建立 TCP 连接并完成 SSH 握手（含 keepalive 配置）。
        #[napi]
        pub async fn connect(&self, options: ConnectOptions) -> Result<()> {
            self.core
                .connect(&options.to_params())
                .await
                .map_err(to_napi_err)
        }

        /// 密码认证；false = 服务器拒绝（密码错误）。
        #[napi(js_name = "authenticatePassword")]
        pub async fn authenticate_password(&self, user: String, password: String) -> Result<bool> {
            self.core
                .authenticate_password(&user, &password)
                .await
                .map_err(to_napi_err)
        }

        /// 主动断开（幂等）。
        #[napi]
        pub async fn disconnect(&self) -> Result<()> {
            self.core.disconnect().await.map_err(to_napi_err)
        }

        /// 连接是否已关闭（断线感知：服务器掐断/keepalive 超时即 true）。
        #[napi(js_name = "isClosed")]
        pub fn is_closed(&self) -> bool {
            self.core.is_closed()
        }

        /// 释放原生资源，之后实例不可复用。
        #[napi]
        pub fn dispose(&self) {
            self.core.dispose();
            let core = self.core.clone();
            spawn(async move {
                let _ = core.disconnect().await;
            });
        }

        /// 打开 SFTP 子系统会话（幂等）。
        #[napi(js_name = "sftpInit")]
        pub async fn sftp_init(&self) -> Result<()> {
            self.core.sftp_init().await.map_err(to_napi_err)
        }

        /// 关闭 SFTP 会话（幂等）。
        #[napi(js_name = "sftpShutdown")]
        pub async fn sftp_shutdown(&self) -> Result<()> {
            self.core.sftp_shutdown().await.map_err(to_napi_err)
        }

        /// 路径是否存在。仅服务器明确返回"文件不存在"时为 false，
        /// 网络/超时/权限等错误上抛（message 带 `[sftp:{code}]`）。
        #[napi(js_name = "sftpExists")]
        pub async fn sftp_exists(&self, path: String) -> Result<bool> {
            self.core.sftp_exists(&path).await.map_err(to_napi_err)
        }

        /// 获取文件/目录元数据。
        #[napi(js_name = "sftpStat")]
        pub async fn sftp_stat(&self, path: String) -> Result<FileStat> {
            self.core
                .sftp_stat(&path)
                .await
                .map(FileStat::from)
                .map_err(to_napi_err)
        }

        /// 列出目录内容（跳过 `.` 与 `..`）。
        #[napi(js_name = "sftpListDir")]
        pub async fn sftp_list_dir(&self, path: String) -> Result<Vec<FileStat>> {
            self.core
                .sftp_list_dir(&path)
                .await
                .map(|list| list.into_iter().map(FileStat::from).collect())
                .map_err(to_napi_err)
        }

        /// 以只读方式打开远端文件，返回句柄 id。
        #[napi(js_name = "sftpOpenRead")]
        pub async fn sftp_open_read(&self, path: String) -> Result<u32> {
            self.core.sftp_open_read(&path).await.map_err(to_napi_err)
        }

        /// 从句柄顺序读取至多 `length` 字节；读到 EOF 返回空 ArrayBuffer。
        #[napi(js_name = "sftpRead")]
        pub async fn sftp_read(&self, handle: u32, length: u32) -> Result<Buffer> {
            let data = self
                .core
                .sftp_read(handle, length as usize)
                .await
                .map_err(to_napi_err)?;
            Ok(Buffer::from(data))
        }

        /// 以覆盖写方式打开远端文件（TRUNC|CREAT），返回句柄 id。
        #[napi(js_name = "sftpOpenWrite")]
        pub async fn sftp_open_write(&self, path: String) -> Result<u32> {
            self.core.sftp_open_write(&path).await.map_err(to_napi_err)
        }

        /// 向句柄顺序写入全部数据，返回写入字节数。
        #[napi(js_name = "sftpWrite")]
        pub async fn sftp_write(&self, handle: u32, data: Buffer) -> Result<u32> {
            let written = self
                .core
                .sftp_write(handle, &data)
                .await
                .map_err(to_napi_err)?;
            Ok(written as u32)
        }

        /// 关闭句柄（幂等）。
        #[napi(js_name = "sftpClose")]
        pub async fn sftp_close(&self, handle: u32) -> Result<()> {
            self.core.sftp_close(handle).await.map_err(to_napi_err)
        }
    }
}

#[cfg(target_env = "ohos")]
pub use binding::{ConnectOptions, SshClient};
