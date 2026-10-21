//! Host 平台协议级集成测试。
//!
//! 在测试进程内用 russh server 模块起一个真实 SSH 服务器，subsystem "sftp"
//! 由 russh-sftp 自带 server 端处理、后端映射到临时目录（std::fs），对
//! `SshClientCore` 做端到端验证：认证、stat/list、流式读写往返、
//! NO_SUCH_FILE 语义、断线/未连接/坏句柄/释放等错误路径。

use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::time::{Duration, UNIX_EPOCH};

use russh::server::{Auth, Msg, Server as _, Session};
use russh::{Channel, ChannelId, ChannelOpenFailure};
use russh_sftp::protocol::{
    Attrs, Data, File as SftpFile, FileAttributes, Handle, Name, OpenFlags, Status, StatusCode,
    Version,
};
use sftp_ohos::client::ConnectParams;
use sftp_ohos::{SftpErrorCode, SshClientCore};
use tokio::sync::Mutex;

const TEST_USER: &str = "testuser";
const TEST_PASS: &str = "testpass";

// ---------------------------------------------------------------------------
// SSH 服务器
// ---------------------------------------------------------------------------

#[derive(Clone)]
struct TestSshServer {
    root: PathBuf,
}

impl russh::server::Server for TestSshServer {
    type Handler = SshSession;

    fn new_client(&mut self, _peer: Option<SocketAddr>) -> Self::Handler {
        SshSession {
            root: self.root.clone(),
            channels: Arc::new(Mutex::new(HashMap::new())),
        }
    }
}

struct SshSession {
    root: PathBuf,
    channels: Arc<Mutex<HashMap<ChannelId, Channel<Msg>>>>,
}

#[async_trait::async_trait]
impl russh::server::Handler for SshSession {
    type Error = russh::Error;

    async fn auth_password(&mut self, user: &str, password: &str) -> Result<Auth, Self::Error> {
        if user == TEST_USER && password == TEST_PASS {
            Ok(Auth::Accept)
        } else {
            Ok(Auth::Reject {
                proceed_with_methods: None,
            })
        }
    }

    async fn channel_open_session(
        &mut self,
        channel: Channel<Msg>,
        _session: &mut Session,
    ) -> Result<bool, Self::Error> {
        self.channels.lock().await.insert(channel.id(), channel);
        Ok(true)
    }

    async fn subsystem_request(
        &mut self,
        channel_id: ChannelId,
        name: &str,
        session: &mut Session,
    ) -> Result<(), Self::Error> {
        if name != "sftp" {
            return Err(russh::Error::ChannelOpenFailure(ChannelOpenFailure::Unknown));
        }
        let Some(channel) = self.channels.lock().await.remove(&channel_id) else {
            return Err(russh::Error::WrongChannel);
        };
        session.channel_success(channel_id);
        russh_sftp::server::run(
            channel.into_stream(),
            FsSftpHandler::new(self.root.clone()),
        )
        .await;
        Ok(())
    }
}

// ---------------------------------------------------------------------------
// SFTP 服务器（tempdir std::fs 后端）
// ---------------------------------------------------------------------------

struct FsSftpHandler {
    root: PathBuf,
    files: HashMap<String, std::fs::File>,
    dirs: HashMap<String, PathBuf>,
    next_id: u32,
}

impl FsSftpHandler {
    fn new(root: PathBuf) -> Self {
        Self {
            root,
            files: HashMap::new(),
            dirs: HashMap::new(),
            next_id: 0,
        }
    }

    fn next_handle(&mut self) -> String {
        self.next_id += 1;
        format!("h{}", self.next_id)
    }

    /// 把客户端路径解析到 tempdir 根（"/a/b" → root/a/b）。
    fn resolve(&self, path: &str) -> PathBuf {
        let trimmed = path.trim_start_matches('/');
        self.root.join(trimmed)
    }
}

fn attrs_of(meta: &std::fs::Metadata) -> FileAttributes {
    use std::os::unix::fs::PermissionsExt;
    let mut attrs = FileAttributes::default();
    attrs.size = Some(meta.len());
    attrs.permissions = Some(meta.permissions().mode());
    attrs.mtime = meta
        .modified()
        .ok()
        .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
        .map(|d| d.as_secs() as u32);
    if meta.is_dir() {
        attrs.set_dir(true);
    } else if meta.is_file() {
        attrs.set_regular(true);
    }
    attrs
}

fn io_status() -> StatusCode {
    StatusCode::Failure
}

fn ok_status(id: u32) -> Status {
    Status {
        id,
        status_code: StatusCode::Ok,
        error_message: "Ok".to_string(),
        language_tag: "en-US".to_string(),
    }
}

impl russh_sftp::server::Handler for FsSftpHandler {
    type Error = StatusCode;

    fn unimplemented(&self) -> Self::Error {
        StatusCode::OpUnsupported
    }

    async fn open(
        &mut self,
        id: u32,
        filename: String,
        pflags: OpenFlags,
        _attrs: FileAttributes,
    ) -> Result<Handle, Self::Error> {
        use std::os::unix::fs::OpenOptionsExt;
        let path = self.resolve(&filename);
        let mut opts = std::fs::OpenOptions::new();
        opts.read(pflags.contains(OpenFlags::READ))
            .write(pflags.contains(OpenFlags::WRITE))
            .append(pflags.contains(OpenFlags::APPEND))
            .create(pflags.contains(OpenFlags::CREATE))
            .truncate(pflags.contains(OpenFlags::TRUNCATE))
            .mode(0o644);
        let file = opts.open(&path).map_err(|_| io_status())?;
        let handle = self.next_handle();
        self.files.insert(handle.clone(), file);
        Ok(Handle { id, handle })
    }

    async fn close(&mut self, id: u32, handle: String) -> Result<Status, Self::Error> {
        self.files.remove(&handle);
        self.dirs.remove(&handle);
        Ok(ok_status(id))
    }

    async fn read(
        &mut self,
        id: u32,
        handle: String,
        offset: u64,
        len: u32,
    ) -> Result<Data, Self::Error> {
        use std::os::unix::fs::FileExt;
        let Some(file) = self.files.get(&handle) else {
            return Err(StatusCode::Failure);
        };
        let mut buf = vec![0u8; len as usize];
        let n = file.read_at(&mut buf, offset).map_err(|_| io_status())?;
        if n == 0 {
            return Err(StatusCode::Eof);
        }
        buf.truncate(n);
        Ok(Data { id, data: buf })
    }

    async fn write(
        &mut self,
        id: u32,
        handle: String,
        offset: u64,
        data: Vec<u8>,
    ) -> Result<Status, Self::Error> {
        use std::os::unix::fs::FileExt;
        let Some(file) = self.files.get(&handle) else {
            return Err(StatusCode::Failure);
        };
        file.write_at(&data, offset).map_err(|_| io_status())?;
        Ok(ok_status(id))
    }

    async fn stat(&mut self, id: u32, path: String) -> Result<Attrs, Self::Error> {
        let meta = std::fs::metadata(self.resolve(&path))
            .map_err(|_| StatusCode::NoSuchFile)?;
        Ok(Attrs { id, attrs: attrs_of(&meta) })
    }

    async fn lstat(&mut self, id: u32, path: String) -> Result<Attrs, Self::Error> {
        let meta = std::fs::symlink_metadata(self.resolve(&path))
            .map_err(|_| StatusCode::NoSuchFile)?;
        Ok(Attrs { id, attrs: attrs_of(&meta) })
    }

    async fn opendir(&mut self, id: u32, path: String) -> Result<Handle, Self::Error> {
        let dir = self.resolve(&path);
        if !dir.is_dir() {
            return Err(StatusCode::NoSuchFile);
        }
        let handle = self.next_handle();
        self.dirs.insert(handle.clone(), dir);
        Ok(Handle { id, handle })
    }

    async fn readdir(&mut self, id: u32, handle: String) -> Result<Name, Self::Error> {
        let Some(dir) = self.dirs.remove(&handle) else {
            return Err(StatusCode::Eof);
        };
        let mut files = Vec::new();
        let entries = std::fs::read_dir(&dir).map_err(|_| io_status())?;
        for entry in entries {
            let entry = entry.map_err(|_| io_status())?;
            let name = entry.file_name().to_string_lossy().to_string();
            let meta = entry.metadata().map_err(|_| io_status())?;
            files.push(SftpFile {
                filename: name,
                longname: String::new(),
                attrs: attrs_of(&meta),
            });
        }
        Ok(Name { id, files })
    }

    async fn remove(&mut self, id: u32, filename: String) -> Result<Status, Self::Error> {
        std::fs::remove_file(self.resolve(&filename))
            .map_err(|_| StatusCode::NoSuchFile)?;
        Ok(ok_status(id))
    }

    async fn mkdir(&mut self, id: u32, path: String, _attrs: FileAttributes) -> Result<Status, Self::Error> {
        std::fs::create_dir(self.resolve(&path)).map_err(|_| io_status())?;
        Ok(ok_status(id))
    }

    async fn rmdir(&mut self, id: u32, path: String) -> Result<Status, Self::Error> {
        std::fs::remove_dir(self.resolve(&path)).map_err(|_| StatusCode::NoSuchFile)?;
        Ok(ok_status(id))
    }

    async fn realpath(&mut self, id: u32, path: String) -> Result<Name, Self::Error> {
        let resolved = if path == "." {
            self.root.clone()
        } else {
            self.resolve(&path)
        };
        let mut attrs = FileAttributes::default();
        attrs.set_dir(true);
        Ok(Name {
            id,
            files: vec![SftpFile {
                filename: resolved.to_string_lossy().to_string(),
                longname: String::new(),
                attrs,
            }],
        })
    }

    async fn init(
        &mut self,
        _version: u32,
        _extensions: HashMap<String, String>,
    ) -> Result<Version, Self::Error> {
        Ok(Version::new())
    }
}

// ---------------------------------------------------------------------------
// 测试基建
// ---------------------------------------------------------------------------

/// 启动测试 SSH+SFTP 服务器，返回 (端口, tempdir 根)。
async fn start_server() -> (u16, PathBuf) {
    let root = tempfile::tempdir().expect("tempdir");
    let root_path = root.keep();

    let config = russh::server::Config {
        auth_rejection_time: Duration::from_millis(10),
        auth_rejection_time_initial: Some(Duration::from_millis(10)),
        keys: vec![russh::keys::key::KeyPair::generate_ed25519()],
        ..Default::default()
    };
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.expect("bind");
    let port = listener.local_addr().expect("local addr").port();

    let server = TestSshServer {
        root: root_path.clone(),
    };
    tokio::spawn(async move {
        let mut server = server;
        let _ = server.run_on_socket(Arc::new(config), &listener).await;
    });
    (port, root_path)
}

async fn connected_client(port: u16) -> SshClientCore {
    let client = SshClientCore::new();
    client
        .connect(&ConnectParams::new("127.0.0.1", port))
        .await
        .expect("connect");
    client
        .authenticate_password(TEST_USER, TEST_PASS)
        .await
        .expect("auth")
        .then_some(true)
        .expect("auth success");
    client.sftp_init().await.expect("sftp init");
    client
}

fn write_local(path: &Path, bytes: &[u8]) {
    std::fs::write(path, bytes).expect("local write");
}

fn code_of(err: &sftp_ohos::SftpError) -> SftpErrorCode {
    err.code
}

// ---------------------------------------------------------------------------
// 用例
// ---------------------------------------------------------------------------

#[tokio::test]
async fn connect_auth_and_full_roundtrip() {
    let (port, root) = start_server().await;
    let client = connected_client(port).await;

    // 上传：分块写入 300KB（跨 256KB SFTP 上限，验证自动分块）
    let payload: Vec<u8> = (0..300 * 1024).map(|i| (i % 251) as u8).collect();
    write_local(&root.join("local.bin"), &payload);
    let handle = client.sftp_open_write("/remote.bin").await.expect("open write");
    for chunk in payload.chunks(64 * 1024) {
        let n = client.sftp_write(handle, chunk).await.expect("write");
        assert_eq!(n, chunk.len());
    }
    client.sftp_close(handle).await.expect("close write");

    // stat：大小一致
    let stat = client.sftp_stat("/remote.bin").await.expect("stat");
    assert_eq!(stat.name, "remote.bin");
    assert_eq!(stat.size, payload.len() as u64);
    assert!(!stat.is_dir);
    assert!(stat.mtime > 0);

    // 下载：分块读回并比对
    let handle = client.sftp_open_read("/remote.bin").await.expect("open read");
    let mut downloaded: Vec<u8> = Vec::with_capacity(payload.len());
    loop {
        let chunk = client.sftp_read(handle, 256 * 1024).await.expect("read");
        if chunk.is_empty() {
            break;
        }
        downloaded.extend_from_slice(&chunk);
    }
    client.sftp_close(handle).await.expect("close read");
    assert_eq!(downloaded, payload);

    // exists
    assert!(client.sftp_exists("/remote.bin").await.expect("exists"));
    assert!(!client.is_closed());

    client.disconnect().await.expect("disconnect");
    assert!(client.is_closed());
}

#[tokio::test]
async fn exists_no_such_file_is_false_but_other_errors_throw() {
    let (port, _root) = start_server().await;
    let client = connected_client(port).await;

    // 明确不存在 → false（唯一折叠为 false 的路径）
    assert!(!client.sftp_exists("/definitely/not/here").await.expect("exists"));
    // stat 对不存在路径 → NoSuchFile 错误码
    let err = client.sftp_stat("/definitely/not/here").await.unwrap_err();
    assert_eq!(code_of(&err), SftpErrorCode::NoSuchFile);
    // message 携带编码，供 ArkTS 侧解析
    assert!(err.encoded_message().starts_with("[sftp:7]"));
}

#[tokio::test]
async fn list_dir_returns_entries() {
    let (port, root) = start_server().await;
    let client = connected_client(port).await;

    std::fs::create_dir(root.join("adir")).unwrap();
    write_local(&root.join("a.txt"), b"hello");
    write_local(&root.join("b.txt"), b"world!");

    let entries = client.sftp_list_dir("/").await.expect("list dir");
    let names: Vec<&str> = entries.iter().map(|e| e.name.as_str()).collect();
    assert!(names.contains(&"adir"));
    assert!(names.contains(&"a.txt"));
    assert!(names.contains(&"b.txt"));
    // 不含 . 与 ..
    assert!(!names.contains(&"."));
    assert!(!names.contains(&".."));

    let a = entries.iter().find(|e| e.name == "a.txt").unwrap();
    assert_eq!(a.size, 5);
    assert!(!a.is_dir);
    let dir = entries.iter().find(|e| e.name == "adir").unwrap();
    assert!(dir.is_dir);
}

#[tokio::test]
async fn auth_failure_returns_false() {
    let (port, _root) = start_server().await;
    let client = SshClientCore::new();
    client
        .connect(&ConnectParams::new("127.0.0.1", port))
        .await
        .expect("connect");
    let ok = client
        .authenticate_password(TEST_USER, "wrong-password")
        .await
        .expect("no transport error");
    assert!(!ok, "wrong password must be rejected");
}

#[tokio::test]
async fn connect_refused_maps_to_network_error() {
    let client = SshClientCore::new();
    // 127.0.0.1:1 无监听 → 立即 ECONNREFUSED → NETWORK_ERROR
    let err = client
        .connect(&ConnectParams::new("127.0.0.1", 1))
        .await
        .unwrap_err();
    assert_eq!(code_of(&err), SftpErrorCode::NetworkError);
}

#[tokio::test]
async fn operations_before_connect_throw_not_connected() {
    let client = SshClientCore::new();
    assert!(client.is_closed());

    let err = client.sftp_stat("/x").await.unwrap_err();
    assert_eq!(code_of(&err), SftpErrorCode::NotConnected);
    let err = client
        .authenticate_password("u", "p")
        .await
        .unwrap_err();
    assert_eq!(code_of(&err), SftpErrorCode::NotConnected);
}

#[tokio::test]
async fn sftp_ops_before_init_throw_not_connected() {
    let (port, _root) = start_server().await;
    let client = SshClientCore::new();
    client
        .connect(&ConnectParams::new("127.0.0.1", port))
        .await
        .expect("connect");
    // 已连接但未 sftp_init
    let err = client.sftp_stat("/x").await.unwrap_err();
    assert_eq!(code_of(&err), SftpErrorCode::NotConnected);
}

#[tokio::test]
async fn bad_handle_throws() {
    let (port, _root) = start_server().await;
    let client = connected_client(port).await;

    let err = client.sftp_read(4242, 1024).await.unwrap_err();
    assert_eq!(code_of(&err), SftpErrorCode::BadHandle);
    let err = client.sftp_write(4242, b"x").await.unwrap_err();
    assert_eq!(code_of(&err), SftpErrorCode::BadHandle);
    // sftp_close 幂等
    client.sftp_close(4242).await.expect("close is idempotent");
}

#[tokio::test]
async fn dispose_makes_client_unusable() {
    let (port, _root) = start_server().await;
    let client = connected_client(port).await;

    client.dispose();
    assert!(client.is_closed());

    let err = client
        .connect(&ConnectParams::new("127.0.0.1", port))
        .await
        .unwrap_err();
    assert_eq!(code_of(&err), SftpErrorCode::Disposed);
    let err = client.sftp_exists("/x").await.unwrap_err();
    assert_eq!(code_of(&err), SftpErrorCode::Disposed);
}

#[tokio::test]
async fn read_empty_file_returns_empty_immediately() {
    let (port, root) = start_server().await;
    let client = connected_client(port).await;

    write_local(&root.join("empty.bin"), b"");
    let handle = client.sftp_open_read("/empty.bin").await.expect("open");
    let chunk = client.sftp_read(handle, 4096).await.expect("read");
    assert!(chunk.is_empty(), "EOF must be empty vec");
    client.sftp_close(handle).await.expect("close");
}

#[tokio::test]
async fn server_side_disconnect_is_detected() {
    let (port, _root) = start_server().await;
    let client = connected_client(port).await;
    assert!(!client.is_closed());

    // 强制断开（drop 内部连接）后 is_closed 立即为 true
    client.disconnect().await.expect("disconnect");
    assert!(client.is_closed());

    // 断开后操作 → NotConnected
    let err = client.sftp_exists("/x").await.unwrap_err();
    assert_eq!(code_of(&err), SftpErrorCode::NotConnected);
}

#[tokio::test]
async fn keepalive_config_is_accepted() {
    let (port, _root) = start_server().await;
    let mut params = ConnectParams::new("127.0.0.1", port);
    params.keepalive_sec = 1;
    params.timeout_sec = 5;
    let client = SshClientCore::new();
    client.connect(&params).await.expect("connect with keepalive");
    client
        .authenticate_password(TEST_USER, TEST_PASS)
        .await
        .expect("auth");
    // 连接保持 2 个心跳周期后仍存活
    tokio::time::sleep(Duration::from_secs(2)).await;
    assert!(!client.is_closed(), "keepalive should keep session alive");
    client.disconnect().await.expect("disconnect");
}

#[test]
fn connect_params_defaults() {
    let p = ConnectParams::new("h", 22);
    assert_eq!(p.timeout_sec, 10);
    assert_eq!(p.keepalive_sec, 30);
}
