//! SSH 连接与 SFTP 会话核心实现（纯 Rust，无 napi 依赖，host 平台可测）。
//!
//! 设计要点（对应开发计划 §7.5-§7.6）：
//! - `sftp_exists` 仅将 `NO_SUCH_FILE` 折叠为 `false`，其余错误一律上抛；
//! - 连接（TCP+握手）与认证均有超时（默认 10s）；
//! - keepalive 心跳（默认 30s，`keepalive_max` 次无响应判定断线）；
//! - `is_closed()` 基于 russh `Handle::is_closed()`，断线（服务器掐断/NAT 超时/
//!   keepalive 失败）即感知；
//! - 同一 client 的所有 SFTP 操作经 tokio AsyncMutex 串行化，不阻塞调用线程；
//! - 文件读写为流式句柄模型（`sftp_open_*` → 多次 `sftp_read`/`sftp_write` →
//!   `sftp_close`），替换旧的 `dd bs=1` / `cat|base64` 慢路径。

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Arc;
use std::time::Duration;

use russh::client::Handle;
use russh_sftp::client::fs::File;
use russh_sftp::client::SftpSession;
use tokio::io::{AsyncReadExt, AsyncWriteExt};
use tokio::sync::Mutex as AsyncMutex;

use crate::error::{map_io_error, map_russh_error, map_sftp_error, SftpError, SftpErrorCode};
use crate::sftp::FileStat;

/// 连接（TCP+握手+认证）与通道建立的默认超时（秒）。
pub const DEFAULT_CONNECT_TIMEOUT_SEC: u64 = 10;
/// keepalive 心跳默认间隔（秒）；0 表示禁用。
pub const DEFAULT_KEEPALIVE_SEC: u64 = 30;
/// keepalive 连续无响应次数上限，超过即判定断线。
const KEEPALIVE_MAX: usize = 3;
/// 单个 SFTP 请求的超时（秒）。russh-sftp 默认 10s，慢网络下大分块易误报，
/// 放宽到 60s（传输循环仍受 ArkTS 侧整体控制）。
const SFTP_REQUEST_TIMEOUT_SEC: u64 = 60;

/// 连接参数。
#[derive(Debug, Clone)]
pub struct ConnectParams {
    pub host: String,
    pub port: u16,
    /// 连接+握手+认证超时（秒），0 取默认值
    pub timeout_sec: u64,
    /// keepalive 间隔（秒），0 禁用
    pub keepalive_sec: u64,
}

impl ConnectParams {
    pub fn new(host: impl Into<String>, port: u16) -> Self {
        Self {
            host: host.into(),
            port,
            timeout_sec: DEFAULT_CONNECT_TIMEOUT_SEC,
            keepalive_sec: DEFAULT_KEEPALIVE_SEC,
        }
    }

    fn timeout(&self) -> Duration {
        Duration::from_secs(if self.timeout_sec == 0 {
            DEFAULT_CONNECT_TIMEOUT_SEC
        } else {
            self.timeout_sec
        })
    }

    fn keepalive(&self) -> Option<Duration> {
        if self.keepalive_sec == 0 {
            None
        } else {
            Some(Duration::from_secs(self.keepalive_sec))
        }
    }
}

/// 接受任意 host key 的 client handler。
///
/// 与现网 `@ohos-rs/ssh` 行为一致：不做 host key 校验（应用侧无 known_hosts
/// 机制，用户配置只含 host/port/账号密码）。host key 固定校验列入后续增强。
pub struct AcceptAllKeys;

#[async_trait::async_trait]
impl russh::client::Handler for AcceptAllKeys {
    type Error = russh::Error;

    async fn check_server_key(
        &mut self,
        _server_public_key: &russh::keys::key::PublicKey,
    ) -> Result<bool, Self::Error> {
        Ok(true)
    }
}

/// 已连接状态：SSH handle + 可选 SFTP 会话 + 打开的文件句柄表。
struct Connected {
    handle: Handle<AcceptAllKeys>,
    sftp: Option<SftpSession>,
    files: HashMap<u32, File>,
    next_handle: u32,
    timeout: Duration,
}

impl Connected {
    fn is_closed(&self) -> bool {
        self.handle.is_closed()
    }
}

struct Inner {
    disposed: AtomicBool,
    /// None = 未连接或已断开；Some = 已连接。
    /// 所有异步操作全程持锁（串行化），不阻塞调用线程。
    state: AsyncMutex<Option<Connected>>,
}

/// SSH+SFTP 客户端核心。线程安全、可克隆（共享同一连接状态）。
#[derive(Clone)]
pub struct SshClientCore {
    inner: Arc<Inner>,
}

impl Default for SshClientCore {
    fn default() -> Self {
        Self::new()
    }
}

fn not_connected() -> SftpError {
    SftpError::new(SftpErrorCode::NotConnected, "not connected")
}

fn sftp_not_ready() -> SftpError {
    SftpError::new(SftpErrorCode::NotConnected, "sftp session not initialized")
}

fn bad_handle(handle: u32) -> SftpError {
    SftpError::new(SftpErrorCode::BadHandle, format!("invalid file handle {handle}"))
}

impl SshClientCore {
    pub fn new() -> Self {
        Self {
            inner: Arc::new(Inner {
                disposed: AtomicBool::new(false),
                state: AsyncMutex::new(None),
            }),
        }
    }

    fn ensure_not_disposed(&self) -> Result<(), SftpError> {
        if self.inner.disposed.load(Ordering::Acquire) {
            return Err(SftpError::new(SftpErrorCode::Disposed, "client disposed"));
        }
        Ok(())
    }

    /// 建立 TCP 连接并完成 SSH 握手（不含认证）。
    pub async fn connect(&self, params: &ConnectParams) -> Result<(), SftpError> {
        self.ensure_not_disposed()?;
        let mut config = russh::client::Config::default();
        config.keepalive_interval = params.keepalive();
        config.keepalive_max = KEEPALIVE_MAX;

        let fut = russh::client::connect(
            Arc::new(config),
            (params.host.as_str(), params.port),
            AcceptAllKeys,
        );
        let handle = tokio::time::timeout(params.timeout(), fut)
            .await
            .map_err(|_| {
                SftpError::new(
                    SftpErrorCode::Timeout,
                    format!(
                        "connect to {}:{} timed out after {}s",
                        params.host, params.port, params.timeout_sec
                    ),
                )
            })?
            .map_err(map_russh_error)?;

        let mut state = self.inner.state.lock().await;
        *state = Some(Connected {
            handle,
            sftp: None,
            files: HashMap::new(),
            next_handle: 1,
            timeout: params.timeout(),
        });
        Ok(())
    }

    /// 密码认证。返回是否认证成功（false = 服务器拒绝，非错误）。
    pub async fn authenticate_password(
        &self,
        user: &str,
        password: &str,
    ) -> Result<bool, SftpError> {
        self.ensure_not_disposed()?;
        let mut state = self.inner.state.lock().await;
        let connected = state.as_mut().ok_or_else(not_connected)?;
        if connected.is_closed() {
            return Err(SftpError::new(
                SftpErrorCode::NetworkError,
                "connection closed before authentication",
            ));
        }
        tokio::time::timeout(
            connected.timeout,
            connected.handle.authenticate_password(user, password),
        )
        .await
        .map_err(|_| {
            SftpError::new(SftpErrorCode::Timeout, "authentication timed out")
        })?
        .map_err(map_russh_error)
    }

    /// 主动断开连接（幂等，未连接时也返回 Ok）。
    pub async fn disconnect(&self) -> Result<(), SftpError> {
        let mut state = self.inner.state.lock().await;
        if let Some(connected) = state.take() {
            let _ = connected
                .handle
                .disconnect(
                    russh::Disconnect::ByApplication,
                    "client disconnect",
                    "en",
                )
                .await;
        }
        Ok(())
    }

    /// 连接是否已关闭（未连接/已断开/已释放均为 true）。
    ///
    /// 基于russh `Handle::is_closed()`：服务器掐断、keepalive 超时、
    /// socket 错误均会立即可感知。锁被占用（有操作进行中）时视为使用中。
    pub fn is_closed(&self) -> bool {
        if self.inner.disposed.load(Ordering::Acquire) {
            return true;
        }
        match self.inner.state.try_lock() {
            Ok(guard) => match guard.as_ref() {
                None => true,
                Some(connected) => connected.is_closed(),
            },
            Err(_) => false,
        }
    }

    /// 释放实例：置释放标志并尽量清理连接。之后所有调用返回 `DISPOSED`。
    ///
    /// 锁被占用（有操作进行中）时仅置标志，连接由 `disconnect()`（绑定层
    /// 异步调度）或实例 drop 兜底释放。
    pub fn dispose(&self) {
        self.inner.disposed.store(true, Ordering::Release);
        if let Ok(mut guard) = self.inner.state.try_lock() {
            *guard = None;
        }
    }

    /// 打开 SFTP 子系统会话（幂等）。
    pub async fn sftp_init(&self) -> Result<(), SftpError> {
        self.ensure_not_disposed()?;
        let mut state = self.inner.state.lock().await;
        let connected = state.as_mut().ok_or_else(not_connected)?;
        if connected.is_closed() {
            return Err(not_connected());
        }
        if connected.sftp.is_some() {
            return Ok(());
        }

        let channel = tokio::time::timeout(connected.timeout, connected.handle.channel_open_session())
            .await
            .map_err(|_| SftpError::new(SftpErrorCode::Timeout, "open channel timed out"))?
            .map_err(map_russh_error)
            .map_err(|e| {
                SftpError::new(SftpErrorCode::ChannelError, e.message)
            })?;
        channel
            .request_subsystem(true, "sftp")
            .await
            .map_err(|e| {
                SftpError::new(
                    SftpErrorCode::ChannelError,
                    format!("request sftp subsystem failed: {e}"),
                )
            })?;

        let sftp_config = russh_sftp::client::Config {
            max_packet_len: 262144,
            max_concurrent_writes: 8,
            request_timeout_secs: SFTP_REQUEST_TIMEOUT_SEC,
        };
        let sftp = tokio::time::timeout(
            connected.timeout,
            SftpSession::new_with_config(channel.into_stream(), sftp_config),
        )
        .await
        .map_err(|_| SftpError::new(SftpErrorCode::Timeout, "sftp init timed out"))?
        .map_err(map_sftp_error)?;
        connected.sftp = Some(sftp);
        Ok(())
    }

    /// 关闭 SFTP 会话（幂等）。
    pub async fn sftp_shutdown(&self) -> Result<(), SftpError> {
        self.ensure_not_disposed()?;
        let mut state = self.inner.state.lock().await;
        let connected = state.as_mut().ok_or_else(not_connected)?;
        if let Some(sftp) = connected.sftp.take() {
            sftp.close().await.map_err(map_sftp_error)?;
        }
        Ok(())
    }

    /// 路径是否存在。
    ///
    /// **核心语义（§7.5）**：仅当服务器明确返回 `NO_SUCH_FILE` 时返回 false；
    /// 网络/超时/权限等一切其他错误原样上抛，绝不折叠为"不存在"。
    pub async fn sftp_exists(&self, path: &str) -> Result<bool, SftpError> {
        match self.sftp_stat(path).await {
            Ok(_) => Ok(true),
            Err(e) if e.code == SftpErrorCode::NoSuchFile => Ok(false),
            Err(e) => Err(e),
        }
    }

    /// 获取文件/目录元数据。
    pub async fn sftp_stat(&self, path: &str) -> Result<FileStat, SftpError> {
        self.ensure_not_disposed()?;
        let mut state = self.inner.state.lock().await;
        let connected = state.as_mut().ok_or_else(not_connected)?;
        let sftp = connected.sftp.as_ref().ok_or_else(sftp_not_ready)?;
        let attrs = sftp.metadata(path).await.map_err(map_sftp_error)?;
        Ok(FileStat::from_attrs(FileStat::name_of_path(path), &attrs))
    }

    /// 列出目录内容（跳过 `.` 与 `..`）。
    pub async fn sftp_list_dir(&self, path: &str) -> Result<Vec<FileStat>, SftpError> {
        self.ensure_not_disposed()?;
        let mut state = self.inner.state.lock().await;
        let connected = state.as_mut().ok_or_else(not_connected)?;
        let sftp = connected.sftp.as_ref().ok_or_else(sftp_not_ready)?;
        let read_dir = sftp.read_dir(path).await.map_err(map_sftp_error)?;
        let mut out = Vec::new();
        for entry in read_dir {
            let name = entry.file_name();
            if name == "." || name == ".." {
                continue;
            }
            let attrs = entry.metadata();
            out.push(FileStat::from_attrs(name, &attrs));
        }
        Ok(out)
    }

    /// 以只读方式打开远端文件，返回句柄 id。
    pub async fn sftp_open_read(&self, path: &str) -> Result<u32, SftpError> {
        self.ensure_not_disposed()?;
        let mut state = self.inner.state.lock().await;
        let connected = state.as_mut().ok_or_else(not_connected)?;
        let sftp = connected.sftp.as_ref().ok_or_else(sftp_not_ready)?;
        let file = sftp.open(path).await.map_err(map_sftp_error)?;
        Ok(insert_file(connected, file))
    }

    /// 以覆盖写方式打开（TRUNC|CREAT）远端文件，返回句柄 id。
    pub async fn sftp_open_write(&self, path: &str) -> Result<u32, SftpError> {
        self.ensure_not_disposed()?;
        let mut state = self.inner.state.lock().await;
        let connected = state.as_mut().ok_or_else(not_connected)?;
        let sftp = connected.sftp.as_ref().ok_or_else(sftp_not_ready)?;
        let file = sftp.create(path).await.map_err(map_sftp_error)?;
        Ok(insert_file(connected, file))
    }

    /// 从句柄顺序读取至多 `length` 字节；读到 EOF 返回空 Vec。
    pub async fn sftp_read(&self, handle: u32, length: usize) -> Result<Vec<u8>, SftpError> {
        self.ensure_not_disposed()?;
        if length == 0 {
            return Ok(Vec::new());
        }
        let mut state = self.inner.state.lock().await;
        let connected = state.as_mut().ok_or_else(not_connected)?;
        let file = connected
            .files
            .get_mut(&handle)
            .ok_or_else(|| bad_handle(handle))?;
        let mut buf = vec![0u8; length];
        let mut total = 0usize;
        loop {
            let n = file
                .read(&mut buf[total..])
                .await
                .map_err(map_io_error)?;
            if n == 0 {
                break;
            }
            total += n;
            if total == length {
                break;
            }
        }
        buf.truncate(total);
        Ok(buf)
    }

    /// 向句柄顺序写入全部数据（内部自动分块），返回写入字节数。
    pub async fn sftp_write(&self, handle: u32, data: &[u8]) -> Result<usize, SftpError> {
        self.ensure_not_disposed()?;
        if data.is_empty() {
            return Ok(0);
        }
        let mut state = self.inner.state.lock().await;
        let connected = state.as_mut().ok_or_else(not_connected)?;
        let file = connected
            .files
            .get_mut(&handle)
            .ok_or_else(|| bad_handle(handle))?;
        file.write_all(data).await.map_err(map_io_error)?;
        file.flush().await.map_err(map_io_error)?;
        Ok(data.len())
    }

    /// 关闭句柄（幂等：句柄不存在也返回 Ok）。
    pub async fn sftp_close(&self, handle: u32) -> Result<(), SftpError> {
        self.ensure_not_disposed()?;
        let mut state = self.inner.state.lock().await;
        let connected = state.as_mut().ok_or_else(not_connected)?;
        match connected.files.remove(&handle) {
            None => Ok(()),
            Some(file) => {
                file.close().await.map_err(map_io_error)?;
                Ok(())
            }
        }
    }
}

fn insert_file(connected: &mut Connected, file: File) -> u32 {
    let id = connected.next_handle;
    connected.next_handle = connected.next_handle.wrapping_add(1).max(1);
    connected.files.insert(id, file);
    id
}
