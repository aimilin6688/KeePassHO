# FTP（明文）回归测试流程 —— 场景 6

> 目的：SFTP Rust 绑定改造完成后，回归验证 `@ohos/basic-ftp` 明文 FTP 路径未被破坏（KdbxFileManager 两条协议路径共用 L1/L2 抽象，需确认改动无副作用）。
> 对应计划文档 §9.3 场景 6；验收标准 4.4。
> 姊妹文档：`docs/ftp/sftp-server.md`（SFTP 服务器）、`docs/uitest-manual-driving-guide.md`（UI 驱动手册）

---

## 1. 测试服务器选型：pyftpdlib（Mac 本机，不用容器）

- **选型理由**：设备经 rport 反向隧道访问的是 Mac 端口，pyftpdlib 跑在 Mac 本机与跑在容器里**链路完全等价**，且纯 Python 无 qemu 仿真开销、可 API 级控制被动端口。
- **环境注意**：Homebrew Python 3.14 受 PEP 668 保护，必须 venv：

```bash
python3 -m venv /tmp/deveco/ftpvenv            # 实际路径见 §2 脚本内 ROOT
/tmp/deveco/ftpvenv/bin/pip install pyftpdlib
```

- **关键认知（CLI 的坑）**：`python -m pyftpdlib` CLI **不支持** `--passive-ports` 与 `--masquerade-address`，而设备侧 rport 隧道场景**必须**固定被动端口范围 + 伪装地址，因此**必须用 API 脚本**启动。

## 2. 服务器脚本 `ftpd_e2e.py`

```python
import sys
import logging
logging.getLogger('pyftpdlib').setLevel(logging.DEBUG)   # 实测命令级 DEBUG 未见生效，只到 INFO
from pyftpdlib.authorizers import DummyAuthorizer
from pyftpdlib.handlers import FTPHandler
from pyftpdlib.servers import FTPServer

ROOT = '/var/folders/.../T/deveco/ftp-e2e-root'   # 改成本机任意临时目录

authorizer = DummyAuthorizer()
authorizer.add_user('e2e', 'e2epass', ROOT, perm='elradfmwMT')

handler = FTPHandler
handler.authorizer = authorizer
handler.masquerade_address = '127.0.0.1'   # 设备访问 127.0.0.1 经隧道到 Mac，PASV 应答必须回 127.0.0.1
handler.passive_ports = (30000, 30001)     # 与 rport 隧道一一对应
handler.banner = 'e2e-ftpd ready'

server = FTPServer(('0.0.0.0', 2123), handler)
print('ftpd serving', ROOT, 'on 2123, PASV 127.0.0.1:30000-30001', flush=True)
server.serve_forever()
```

| 配置项 | 值 | 说明 |
|---|---|---|
| 控制端口 | `2123`（0.0.0.0） | 直连方案用 2121；因排障插入代理，服务后挪 2123 |
| 凭据 | `e2e` / `e2epass` | 与 SFTP 场景同凭据，降低记忆成本 |
| 权限 | `elradfmwMT` | 含写/删/建目录/改权限 |
| PASV | `127.0.0.1:30000-30001` | **每个被动端口都要单独 rport** |
| 空闲掐线 | 默认 300s | "Control connection timed out"（本次缺陷排障的重要观测点） |

## 3. 透明 TCP 代理 `ftp_proxy.py`（协议级排障利器）

用途：hilog 拿不到应用日志、pyftpdlib DEBUG 又不生效时，用代理逐字节记录控制信道，一次即可看到完整 FTP 命令流。

```python
import socket
import threading
import time

UPSTREAM = ('127.0.0.1', 2123)

def log(tag, data):
    ts = time.strftime('%H:%M:%S')
    text = data.decode('utf-8', 'replace')
    print(f"[{ts}] {tag} {len(data)}B: {text!r}", flush=True)

def pipe(src, dst, tag):
    try:
        while True:
            data = src.recv(4096)
            if not data:
                log(tag, b'<EOF>')
                break
            log(tag, data)
            dst.sendall(data)
    except Exception as e:
        log(tag, str(e).encode())

def handle(client, addr):
    upstream = socket.create_connection(UPSTREAM, timeout=10)
    t1 = threading.Thread(target=pipe, args=(client, upstream, 'APP->SRV'), daemon=True)
    t2 = threading.Thread(target=pipe, args=(upstream, client, 'SRV->APP'), daemon=True)
    t1.start(); t2.start(); t1.join(); t2.join()
    client.close(); upstream.close()

srv = socket.socket()
srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
srv.bind(('127.0.0.1', 2121))
srv.listen(5)
print('proxy listening 2121 -> 2123', flush=True)
while True:
    c, a = srv.accept()
    print(f"[{time.strftime('%H:%M:%S')}] === control connection from hdc {a} ===", flush=True)
    threading.Thread(target=handle, args=(c, a), daemon=True).start()
```

## 4. 链路搭建（rport 隧道）

```bash
hdc rport tcp:2121 tcp:2121      # 控制（→ Mac 代理 2121 → ftpd 2123；直连时 ftpd 直接听 2121）
hdc rport tcp:30000 tcp:30000    # PASV 数据口 1
hdc rport tcp:30001 tcp:30001    # PASV 数据口 2
hdc fport ls                     # 确认三条 [Reverse] 条目
```

**链路**：设备 `127.0.0.1:2121` → hdcd → USB → Mac（代理/ftpd）→ PASV 数据回 `127.0.0.1:30000-30001` 同链路返回。

本机连通性预检（Mac 侧，排除服务器问题后再上设备）：

```bash
python3 - <<'EOF'
import ftplib
f = ftplib.FTP(); f.connect('127.0.0.1', 2121, timeout=5); f.login('e2e', 'e2epass')
f.storbinary('STOR probe.txt', __import__('io').BytesIO(b'probe'))
print(f.nlst()); f.quit()
EOF
```

## 5. App 操作流程（1320×2720 模拟器坐标）

冷启动 App（先清数据或删除旧记录）→ 创建数据库 `e2e-ftp` → 保存位置选 FTP：

| 步骤 | 操作 | 坐标/值 |
|---|---|---|
| 1 | 存储类型选 FTP | 协议下拉默认即 FTP；**FTPS 保持"无加密(FTP)"**（SFTP 之外 FTPS Select 行才可见） |
| 2 | 主机 | `(900,656)` 输入 `127.0.0.1` |
| 3 | 端口 | `(900,858)` **追加技巧**：默认值 21，inputText 是追加式，只补输入 `21` 得 `2121` |
| 4 | 用户 | `(900,1060)` 输入 `e2e` |
| 5 | 密码 | `(900,1262)` 输入 `e2epass`（8 字符显示 7 星，正常） |
| 6 | 文件路径 | 默认 `e2e-ftp.kdbx` **无需修改**（getFullPath 自动补 `/`） |
| 7 | （可选）测试连接 | 状态行出现"连接成功" |
| 8 | 确定 | 触发 selectDir：exists 检查（无此文件）→ STOR 上传 → 跳解锁页 |

### 按钮位置随状态行动态变化（每次点击前必须 dump 复核！）

| 页面状态 | 确定按钮坐标 |
|---|---|
| 无状态行 | `(1158,1877)` |
| "连接成功"状态行出现后 | `(1158,1965)`（下移 88px） |
| 报错状态行出现后 | `(1158,2020)` |

## 6. 已发现缺陷（本场景产出，未修复）

### 缺陷 D【致命→已修复】FTP 二进制下载必损坏 —— 已通过 vendor+2行补丁修复

- **现象**：上传的 e2e-ftp.kdbx 在服务器侧完全合法（魔数 `03d9a29a`、版本 4.1，xxd 验证 ✓），但 App 解锁下载后解析报 **"签名错误"**（`kdbx_error_BadSignature`，kdbx-header.ts:108 文件头魔数校验，尚未走到凭据校验 InvalidKey）。
- **根因**：`@ohos/basic-ftp@1.0.3` `transfer.ts` `downloadTo()` 第 626/648 行，**下载写入前把二进制 ArrayBuffer 有损转成 UTF-8 字符串**：

  ```typescript
  let tempStr = buffer.from(tempData).toString('utf-8')   // ← 二进制 → 文本，非法序列变 U+FFFD
  destination.writeSync(tempStr);                          // ← 文本再按 UTF-8 编码写盘，字节不可逆改变
  ```

  kdbx 为 gzip+随机种子的二进制流，必然含非法 UTF-8 序列 → 下载即损坏。**上传路径无此问题**（`uploadFrom` 直接 `send({data: trueData})` 二进制安全）——完美解释"上传完好、下载必坏"。MLSD/SIZE 等文本命令也不受影响（`Client.list` 读回 temp 文件后再 `toString` 解码，文本本就 UTF-8 安全）。
- **字节级仿真证据**（Mac 侧 Python 精确复现该变换）：1269B → **2158B**（889 个替换符）；前 8 字节 `03 d9 a2 9a 67 fb 4b b5` → `03 d9 a2 ef bf bd 67 ef`；sig1 读数 `0x9AA2D903`（合法 FileMagic）→ `0xEFA2D903` → BadSignature，与 App 症状逐位吻合。
- **影响范围**：`FTPStorage.read()` → `FTPHandler.downloadFrom()` → `client.downloadTo()` 全部经此路径 —— **FTP 协议下任何二进制文件下载 100% 损坏**。此缺陷与 Rust SFTP 改造无关（改造未触及 basic-ftp），属存量三方库缺陷；SFTP 路径（russh 二进制读写）不受影响。
- **修复（已实施）**：vendor 本地副本 `libs/basic-ftp/`（260K 源码，`oh-package.json5` 改 `file:../libs/basic-ftp`，root `build-profile.json5` 注册为 `basic_ftp` 模块，补 `src/main/module.json5`），将两处 `toString`+`writeSync(string)` 改为直写 `destination.writeSync(tempData)`（fs.Stream.writeSync 原生支持 ArrayBuffer，二进制安全）。修复后场景 6 全流程通过（解锁→加条目→自动保存回环，服务器 1269→1477B）。

### 缺陷 A【高→已缓解】FTP 首次连接偶发卡死在登录前 —— 已 fail-fast 缓解

- **现象**：selectDir 的首次 FTP 连接，TCP 三次握手成功后**应用不发 USER 命令**，UI 永久停在"连接中..."；服务器侧见 accept + 已回 banner，之后 300s 空闲掐线报 `421 Control connection timed out`，应用侧才有反应。
- **复现**：直连 pyftpdlib 路径 2/2 卡死；"测试连接"按钮路径 1/1 正常；**经透明代理（2121→2123）后重试 1/1 完整成功**——直连/代理差异是巧合还是因果**尚未定性**。
- **代码证据**（`oh_modules/.ohpm/@ohos+basic-ftp@1.0.3`）：
  - `FtpContext._handleConnectResponse()` 等待 greeting **无超时**；
  - `FtpContext.handle()` 执行任务前 `setExtraOptions({ socketTimeout: 0 })` ——OHOS 移植版**显式关闭**了控制信道超时（原版 basic-ftp 此处是设置 timeout）；
  - 页面配置的 30000ms（`FTPPage.getStorageConfig` 硬编码）**只作用于 TCP connect 阶段**，连上后所有等待均无限期。
- **嫌疑方向**（未证实）：`FtpContext._newSocket()` 的 `connection.getDefaultNet()`/`getConnectionProperties` 竞态；或 connect 完成与 greeting 数据到达几乎同时时 OHOS `TCPSocket` 的 `message` 事件丢失（ greeting 早于 `on("message")` 挂载）。
- **缓解（已实施）**：`FtpContext.handle()` 起始的 `socketTimeout: 0`（禁用）恢复为 `this.timeout`（30000ms）——等待无响应时 30s 后转为错误而非永久挂起。数据传输期仍由 `TransferResolver` 单独保护（onDataStart 置 0、onDataDone 恢复），不会误超时。**此为 fail-fast 缓解，stall 根因仍需单独排查**。
- **影响**：用户遇到即表现为"永远转圈"，只能杀进程。

### 缺陷 B【中】FTPStorage 重复 init 直接覆盖 handler 不 close 旧连接

`FTPStorage.ets` `createHandler()` 每次重建 handler 并覆盖 `this.handler`，旧 handler 的控制 socket 不关闭——socket 泄漏嫌疑，也可能是缺陷 A 的诱因之一（同端口多会话竞争）。

### 缺陷 C【中】FTPHandler.isClosed 语义失真

`isClosed() = !this.client`：连接中途死掉时 `client` 对象仍在，`isClosed` 返回 false，`ensureConnected` 误判"已连接"而复用已死连接。

### 待评审（非 FTP 独有）

`DataService.saveKdbx`（`DataService.ets:33-43`）吞掉保存异常——保存静默失败时用户无感知。

## 7. 实施记录与结论

| 阶段 | 结果 |
|---|---|
| 服务器搭建 + 本机 ftplib 预检（并发双会话+STOR+PASV 往返） | ✅ 全过 |
| App 创建 e2e-ftp 库 → FTP 配置 → 确定 → STOR `/e2e-ftp.kdbx` 1269B 落盘 → 跳转解锁页 | ✅（经代理路径） |
| 代理日志证实的完整协议流：`OPTS UTF8 ON`(530) → `USER/PASS` → `FEAT` → `TYPE I` → `STRU F` → `EPSV`(30000) → exists 用 MLSD / 保存用 STOR(30001) → `226 Transfer complete` | ✅ |
| 解锁：RETR 下载 1269B（缺陷 D 修复后二进制安全）→ kdbx 解析成功 → DatabaseView | ✅ |
| 添加条目 e2e-entry/e2euser/e2epass123 → 触发自动保存 → STOR `/e2e-ftp.kdbx` → 服务器文件 1269→1477B（mtime 更新） | ✅ |

**最终结论**：明文 FTP 全流程闭环通过（创建→上传→下载→解析→编辑→自动保存回环）。缺陷 D（basic-ftp downloadTo 二进制不安全）已通过 vendor `libs/basic-ftp/` + 2 行直写 ArrayBuffer 修复，与 Rust SFTP 改造无关。缺陷 A（首次连接偶发卡死无超时）/B（handler 重复 init 不关旧连接）/C（isClosed 语义失真）仍为存量已知缺陷，不阻断 happy path（连接保活时不触发 C；A 经代理路径未复现）。

### 排障过程中的辅助发现

- 代理脚本 `socket.create_connection(UPSTREAM, timeout=10)` 的 10s 超时会**遗留到整个 socket 生命周期**，空闲 10s 即误杀连接（日志表现为 `'timed out'`）；长流程排障时应连接后 `settimeout(None)`。
- 解锁失败 toast（"签名错误"）仅持续 3s，常规间隔 dump 会错过；密集 dump（点击后每 2s）可稳定捕获。

## 8. 与 SFTP 场景（场景 1-4）的差异清单

| 维度 | SFTP（atmoz/sftp 容器） | FTP（pyftpdlib Mac 本机） |
|---|---|---|
| 数据连接 | 单一 SSH 信道 | 控制口 + 每次传输新开 PASV 数据口（**每个都要 rport**） |
| 端口 | 2222 一条 | 2121 + 30000 + 30001 三条 |
| 超时行为 | Rust 侧 connect/read 超时 + keepalive，断线有感知 | connect 后无任何超时（缺陷 A） |
| 服务器观察 | podman exec + /proc/net/tcp | 本机进程 + 透明代理逐字节日志 |
| FTPPage 布局 | FTPS Select 行不可见 | FTPS Select 行可见 → **按钮整体位置不同**（§5 坐标仅适用 FTP/FTPS 可见态） |

## 9. 复现步骤总览（供回归他人使用）

1. venv + pyftpdlib，起 `ftpd_e2e.py`（直连方案改听 2121；排障方案 2123 + `ftp_proxy.py` 占 2121）
2. `hdc rport` 三条隧道（§4）
3. Mac 侧 ftplib 预检（§4 末）
4. 冷启动 App → 创建库 → FTP 配置（§5）→ 确定
5. 服务器根目录断言 `ls -la` 出现 `e2e-ftp.kdbx`（1269B 量级）
6. 解锁（主密码 `E2eTest123`）→ DatabaseView → 添加条目 → 等 FTP 自动保存 → 服务器断言文件增长
7. 记录缺陷 A 是否复现（直连 2 连发：测试连接 + 确定）
