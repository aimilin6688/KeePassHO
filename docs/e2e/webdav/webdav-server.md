# WebDAV 测试服务器信息（E2E）

> 用途：KeePassHO WebDAV 存储路径真实回归测试专用服务器（`WebDav.test.ets` 用例）
> 环境：macOS (arm64) + podman（amd64 镜像走 qemu 仿真）+ HarmonyOS 模拟器（`127.0.0.1:5557`）
> 姊妹文档：`docs/s3/seaweedfs-server.md`、`docs/storage-regression-test.md`（回归总纲）

---

## 1. 容器基本信息

| 项 | 值 |
|---|---|
| 镜像 | `docker.io/bytemark/webdav:latest`（amd64，Apache mod_dav） |
| 容器名 | `webdav-e2e` |
| 端口映射 | Mac `8800` → 容器 `80` |
| 启动命令 | 见下 |

```bash
podman run -d --name webdav-e2e -p 8800:80 \
  -e USERNAME=e2e -e PASSWORD=e2etest123 -e AUTH_TYPE=Basic \
  docker.io/bytemark/webdav:latest
```

## 2. 凭据与 App 内配置

| 项 | 值 |
|---|---|
| 用户名 / 密码 | `e2e` / `e2etest123`（Basic 认证） |
| App 服务器地址 | `127.0.0.1`（经 rport 反向隧道到 Mac） |
| App 端口 | `8800` |
| 数据目录 | 容器 `/var/lib/dav`（挂载宿主目录可持久化，测试场景可不挂） |

测试代码入口：`entry/src/ohosTest/ets/test/entry/WebDav.test.ets`。

## 3. 行为要点（与客户端实现的对照）

- **PROPFIND 必须带 `Depth` 头**：无 `Depth` 的 PROPFIND 返回 403，带 `Depth: 0` 返回 207（Apache 行为）。`WebDavClient` 的 list/valid 实现已带该头
- **207 归一化**：`WebDavClient.request()` 把全部 2xx（含 207 Multi-Status）归一化为 `statusCode=200`，上层按 200 判断成功，故 list() 对标准 WebDAV 服务器可用
- 匿名访问 401 → `WebDavClient.valid()` 凭据错误路径的负例来源

## 4. 模拟器访问链路（rport 反向隧道）

```
App(设备 127.0.0.1:8800) → hdcd(rport) → Mac 127.0.0.1:8800 → pasta → 容器 80
```

```bash
hdc rport tcp:8800 tcp:8800      # 建立
hdc fport ls                     # 确认 [Reverse] 记录存在
```

## 5. 快速自检

```bash
curl -s -o /dev/null -w "%{http_code}\n" -u e2e:e2etest123 -X PROPFIND -H "Depth: 0" http://localhost:8800/
# 预期：207
```
