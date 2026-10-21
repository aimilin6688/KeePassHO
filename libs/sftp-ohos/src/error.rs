//! 统一错误模型：russh / russh-sftp / IO 错误折叠为带错误码的 `SftpError`。
//!
//! 错误码与 ArkTS 侧 `index.d.ts` 的 `SftpErrorCode` 一一对应；
//! 跨 napi 边界时错误码编码进 message（`[sftp:{code}] {msg}`），
//! 由 ArkTS 侧解析。

use std::fmt;

/// SFTP 错误码（数值与 ArkTS 侧 index.d.ts 保持一致）
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum SftpErrorCode {
    /// 未知错误
    Unknown = 0,
    /// DNS/TCP 失败、socket 错误
    NetworkError = 1,
    /// 连接或操作超时
    Timeout = 2,
    /// 密码/密钥认证失败
    AuthFailed = 3,
    /// SSH 握手失败
    HandshakeFailed = 4,
    /// 通道打开/ subsystem 请求失败
    ChannelError = 5,
    /// SFTP 子系统其他错误（含权限拒绝等，保留服务器消息）
    SftpError = 6,
    /// 服务器明确返回"文件不存在"
    NoSuchFile = 7,
    /// 实例已释放（dispose 后不可复用）
    Disposed = 8,
    /// 尚未连接（connect 未调用或已断开）
    NotConnected = 9,
    /// 文件句柄无效（未打开或已关闭）
    BadHandle = 10,
}

/// 带 `SftpErrorCode` 的错误。
#[derive(Debug, Clone)]
pub struct SftpError {
    pub code: SftpErrorCode,
    pub message: String,
}

impl SftpError {
    pub fn new(code: SftpErrorCode, message: impl Into<String>) -> Self {
        Self { code, message: message.into() }
    }

    /// 错误码数值。
    pub fn code(&self) -> i32 {
        self.code as i32
    }

    /// 跨 napi 边界的消息编码：`[sftp:{code}] {message}`。
    /// ArkTS 侧用 `/\[sftp:(\d+)\]/` 解析错误码。
    pub fn encoded_message(&self) -> String {
        format!("[sftp:{}] {}", self.code as i32, self.message)
    }
}

impl fmt::Display for SftpError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.encoded_message())
    }
}

impl std::error::Error for SftpError {}

/// russh（SSH 层）错误 → `SftpError`
pub fn map_russh_error(e: russh::Error) -> SftpError {
    use russh::Error as E;
    match e {
        E::Disconnect | E::HUP => {
            SftpError::new(SftpErrorCode::NetworkError, "connection closed")
        }
        E::IO(io) => SftpError::new(SftpErrorCode::NetworkError, format!("io error: {io}")),
        E::ConnectionTimeout | E::KeepaliveTimeout | E::InactivityTimeout => {
            SftpError::new(SftpErrorCode::Timeout, format!("{e}"))
        }
        E::Kex
        | E::KexInit
        | E::Version
        | E::NoCommonAlgo { .. }
        | E::PacketAuth
        | E::WrongServerSig
        | E::UnknownAlgo => {
            SftpError::new(SftpErrorCode::HandshakeFailed, format!("ssh handshake failed: {e}"))
        }
        E::ChannelOpenFailure(_) | E::WrongChannel | E::RequestDenied => {
            SftpError::new(SftpErrorCode::ChannelError, format!("{e}"))
        }
        e => SftpError::new(SftpErrorCode::Unknown, format!("{e}")),
    }
}

/// russh-sftp（SFTP 层）错误 → `SftpError`
pub fn map_sftp_error(e: russh_sftp::client::error::Error) -> SftpError {
    use russh_sftp::client::error::Error as E;
    match e {
        E::Status(status) => match status.status_code {
            russh_sftp::protocol::StatusCode::NoSuchFile => {
                SftpError::new(SftpErrorCode::NoSuchFile, "no such file")
            }
            code => SftpError::new(
                SftpErrorCode::SftpError,
                format!("sftp status {code}: {}", status.error_message),
            ),
        },
        E::Timeout => SftpError::new(SftpErrorCode::Timeout, "sftp response timeout"),
        E::IO(msg) => SftpError::new(SftpErrorCode::NetworkError, format!("io error: {msg}")),
        e => SftpError::new(SftpErrorCode::SftpError, format!("{e}")),
    }
}

/// IO 错误（文件句柄读写）→ `SftpError`
pub fn map_io_error(e: std::io::Error) -> SftpError {
    match e.kind() {
        std::io::ErrorKind::TimedOut => SftpError::new(SftpErrorCode::Timeout, format!("{e}")),
        _ => SftpError::new(SftpErrorCode::NetworkError, format!("{e}")),
    }
}
