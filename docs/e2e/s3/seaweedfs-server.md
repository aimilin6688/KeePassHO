# SeaweedFS 测试服务器信息（E2E）

> 用途：KeePassHO S3 存储路径真实回归测试专用 S3 网关（`S3Client` / `S3Storage` / `S3ClientMultipart` 系列用例）
> 环境：macOS (arm64) + podman（amd64 镜像走 qemu 仿真）+ HarmonyOS 模拟器（`127.0.0.1:5557`）
> 姊妹文档：`docs/webdav/webdav-server.md`、`docs/storage-regression-test.md`（回归总纲）

---

## 1. 容器基本信息

| 项 | 值 |
|---|---|
| 镜像 | `docker.1ms.run/chrislusf/seaweedfs:3.81`（amd64，容器内进程为 `qemu-x86_64-static` 包装） |
| 容器名 | `seaweedfs-e2e` |
| 端口映射 | Mac `9000` → 容器 `8333`（S3 网关） |
| 启动命令 | 见下 |

```bash
podman run -d --name seaweedfs-e2e -p 9000:8333 \
  docker.1ms.run/chrislusf/seaweedfs:3.81 \
  server -dir=/data -master.volumeSizeLimitMB=1024 -filer -s3 -s3.port=8333
```

## 2. 为什么是 SeaweedFS 而不是 MinIO

选型时对 MinIO 做过全面尝试，**全部失败**，勿再重复：

| 来源 | 结果 |
|---|---|
| `docker.1ms.run/minio/minio`（全标签） | `manifest unknown` |
| `quay.io/minio/minio` RELEASE 标签 | `unauthorized` |
| `docker.m.daocloud.io` / `docker.1panel.live` | denied |
| `dl.min.io` 二进制直装 | HTTP 410 Gone（社区版已停止二进制分发） |

SeaweedFS 3.81 在 `docker.1ms.run` 可正常拉取，S3 网关完整支持 ListBuckets / PutObject / GetObject / HeadObject / ListObjects(delimiter) / Multipart Upload，满足全部用例需求。

## 3. 镜像使用注意（最大的坑）

- **镜像 ENTRYPOINT 是 `weed`**：容器命令直接以 `server` 开头，不要写 `weed server ...`（报 `unknown subcommand weed`）
- **必须带 `-filer`**：S3 网关依赖 filer，缺省会无限等待 `wait to connect to filer localhost:8888`
- **qemu 下启动慢**（约 20s）：启动期间日志出现 `wait to connect to filer` 属正常，等 `s3: S3 API server listening at` 即就绪
- `-s3.port=8333` 是网关监听端口，默认 8333，此处显式声明便于对照端口映射

## 4. 初始化（每次重建容器后执行）

```bash
# 创建测试桶（weed shell 交互式命令通过管道输入）
podman exec seaweedfs-e2e sh -c "echo 's3.bucket.create -name e2e-test' | weed shell"
# 预期输出： created bucket e2e-test
```

验证（宿主机匿名请求即返回桶列表）：

```bash
curl -s http://localhost:9000/
# <?xml version="1.0" encoding="UTF-8"?>
# <ListAllMyBucketsResult>...<Name>e2e-test</Name>...</ListAllMyBucketsResult>
```

## 5. 凭据与 App 内配置

| 项 | 值 |
|---|---|
| Access Key ID | `e2e`（未启用 IAM，**任意非空凭证**均可通过签名校验） |
| Secret Access Key | `e2etest123` |
| Region | `us-east-1`（不校验，保持 AWS 默认） |
| 桶 | `e2e-test` |
| App 服务器地址 | `127.0.0.1`（经 rport 反向隧道到 Mac，见 §6） |
| App 端口 | `9000` |
| **Path Style** | **必须开启**（自建网关不支持虚拟主机风格 `bucket.host` 域名） |

测试代码中的配置入口：`entry/src/ohosTest/ets/test/storage/s3/S3TestConfig.ets`。

## 6. 模拟器访问链路（rport 反向隧道）

```
App(设备 127.0.0.1:9000) → hdcd(rport) → Mac 127.0.0.1:9000 → pasta → 容器 8333
```

```bash
hdc rport tcp:9000 tcp:9000      # 建立
hdc fport ls                     # 确认 [Reverse] 记录存在
```

模拟器侧无 DNS，`127.0.0.1` 即宿主隧道入口；`hdc` 重启后隧道会丢失，需重建。

## 7. 与产品代码的关联（本轮真实回归修出的 bug）

自建 S3 网关必带**非标准端口**，暴露了两个对 AWS 默认端口无感的产品 bug（已修复）：

1. `S3Client.parseUrl` 剥离端口后，`listBuckets` 与虚拟主机风格 `buildUrl` 拼 URL 丢失端口 → 新增 `S3Client.buildAuthority()` 统一构造 `host:port`
2. `S3SignatureV4.signRequest` 的 Host 头丢端口 → 按 SigV4 规范保留非标准端口
