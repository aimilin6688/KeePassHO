# SFTP 测试服务器信息（E2E）

> 用途：KeePassHO SFTP 路径 E2E 测试专用服务器（计划文档 §9.3 场景 1/2/3/4 均基于此环境）
> 环境：macOS (arm64) + podman（amd64 镜像走 qemu 仿真）+ HarmonyOS 模拟器（`127.0.0.1:5557`）
> 姊妹文档：`docs/ftp/ftp-regression-test.md`（FTP 明文回归）、`docs/uitest-manual-driving-guide.md`（UI 驱动手册）

---

## 1. 容器基本信息

| 项 | 值 |
|---|---|
| 镜像 | `atmoz/sftp:latest`（amd64，容器内进程为 `qemu-x86_64-static` 包装） |
| 容器名 | `sftp-e2e` |
| 端口映射 | Mac `2222` → 容器 `22` |
| 启动命令 | `podman run -d --name sftp-e2e -p 2222:22 -e SFTP_USERS=e2e:e2epass:1001 atmoz/sftp:latest` |

## 2. 凭据与 App 内配置

| 项 | 值 |
|---|---|
| SFTP 用户 | `e2e` / `e2epass`（uid 1001，gid 100） |
| App 协议 | SFTP |
| App 服务器地址 | `127.0.0.1`（经 rport 反向隧道到 Mac） |
| App 端口 | `2222` |
| App 根路径 | `/data/e2e-test.kdbx` |
| 配套测试数据 | 库名 `e2e-test`，主密码 `E2eTest123`（测试专用，非机密） |

## 3. 目录结构（chroot 约束——最大的坑）

- chroot 根 = 容器 `/home/e2e`：**必须 `root:root 755`**（sshd chroot 硬性要求）
- 用户可写目录必须是**子目录**：`/home/e2e/data`（`e2e:users`）→ 客户端视角路径为 `/data/`
- 初始化命令（每次重建容器后执行）：

```bash
podman exec sftp-e2e sh -c 'mkdir -p /home/e2e/data && chown 1001:100 /home/e2e/data && chown root:root /home/e2e && chmod 755 /home/e2e'
```

- **错误做法**：把 `/home/e2e` chown 给用户 → sshd 报 `bad ownership or modes for chroot directory` → **密码认证成功后会话即断**（App 侧表现为"连接中"卡死或连接失败，极易误判为客户端 bug；容器 logs 里能看到 auth 出现后会话立刻关闭）

## 4. 空闲掐连接配置（场景 3 专用）

容器 `/etc/ssh/sshd_config` 末尾追加（已持久化在容器可写层）：

```
ClientAliveInterval 15
ClientAliveCountMax 1
```

修改后需 `podman restart sftp-e2e` 生效（对已建立会话无影响，只作用于新会话）。
实测行为：客户端（russh）会自动应答服务器探针，空闲连接不会被掐；此配置反而成为"客户端 keepalive 正常"的验证手段。

## 5. 设备访问链路（rport 反向隧道）

```bash
hdc rport tcp:2222 tcp:2222        # 注意：本版 hdc 无 add 子命令
hdc fport ls                        # 确认 [Reverse] 条目
hdc -t 127.0.0.1:5557 shell "netstat -tln | grep 2222"   # 设备侧应 LISTEN
```

链路：设备 `127.0.0.1:2222` → hdcd → USB → Mac hdc → Mac `2222` → 容器 sshd。

## 6. 常用运维命令

```bash
# 启停
podman start sftp-e2e / podman stop sftp-e2e / podman restart sftp-e2e

# 服务器侧文件断言（E2E 验证点）
podman exec sftp-e2e ls -la /home/e2e/data/

# 登录验证（Mac 侧必须禁公钥，否则本机 agent 密钥导致 Too many authentication failures）
expect -c 'spawn sftp -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -P 2222 e2e@127.0.0.1
expect "password:"; send "e2epass\r"; expect "sftp>"; send "ls -la\r"; expect "sftp>"; send "bye\r"'

# 会话观察（容器内无 netstat/ss，用 /proc/net/tcp；st=01 为 ESTABLISHED，端口 22 = 十六进制 0016）
podman exec sftp-e2e sh -c "awk '\$4==\"01\"' /proc/net/tcp | grep -c ':0016'"

# 服务端强杀活会话（杀 sshd -R 三件套）
# 【坑】qemu 仿真下已断连接会残留僵尸 sshd 进程：pid 更大的是僵尸，pid 最小的三件套才是活会话
podman exec sftp-e2e sh -c 'for p in /proc/[0-9]*; do c=$(tr "\0" " " < $p/cmdline 2>/dev/null); case "$c" in *sshd*-R*) echo ${p#/proc/};; esac; done'
```

## 7. 该环境已验证的结论

| 场景 | 结果 |
|---|---|
| 1 正常读写闭环（上传 1269B → 解锁下载 → 加条目自动保存 1493B） | ✅ |
| 2 服务器不可达冷启动 → 记录保留 + 真实网络错误 | ✅ |
| 3 空闲掐连接：90s 挂起连接不断（探针全应答）；强杀后保存自动重连（L2） | ✅ |
| 4 服务端删文件 → 记录按设计移除 | ✅ |

## 8. 注意事项

- amd64 镜像在 arm64 Mac 上 SSH 握手偏慢（qemu 仿真），属正常现象。
- 该容器配置（chroot、ClientAliveInterval）持久化在容器可写层，`podman stop/start` 保留；`podman rm` 后需按 §3/§4 重建。
- 模拟器 hilog 拿不到应用日志，排障靠"dumpLayout 行为 + 服务器侧证据（podman exec / /proc/net/tcp）+ 代码审读"三方对照。
