# e2e 反向隧道自动 setup 与 DevEco Studio 挂钩指南

> 目标：存储回归测试（S3 / WebDAV / SFTP）所需的 hdc 反向隧道，**一条命令自动就绪**，
> 并可挂入 DevEco Studio 的测试 Run Configuration，点"运行测试"时自动建隧道。
> 上游总纲：`docs/storage-regression-test.md`（§4 回归命令 / §5 构建注意）；容器搭建：`docs/e2e/e2e-fileserver.sh`

---

## 1. 一条命令（脚本已就绪）

```bash
sh docs/e2e/e2e-tunnels.sh
```

| 参数 | 作用 |
|---|---|
| （无参数） | 为**所有**已连接设备幂等建立缺失隧道；重复执行安全 |
| `--containers` | 宿主端口不通时自动执行 `e2e-fileserver.sh` 拉起容器 |
| `--reset` | 强制清理重建（含僵尸监听清理，见 §3） |
| `-t <connect-key>` | 仅处理指定设备，如 `-t 127.0.0.1:5555` |

脚本行为：
1. 自动解析 hdc（环境变量 `HDC` > PATH > command-line-tools / DevEco SDK 常见安装位置）；
2. 遍历所有已连接设备（**多设备自动逐台 `-t` 执行**，规避多设备下 rport 目标不明确的问题）；
3. 以"主机注册表 + 设备侧监听"双条件判定隧道状态，只补缺失的；
4. 检测并自动清理僵尸监听（§3），建立后逐条复核，失败项汇总并以非零码退出。

## 2. DevEco Studio 自动挂钩（点运行测试时自动建隧道）

DevEco Studio（IntelliJ 内核）的 Run Configuration 支持 Before launch 任务，把脚本挂为
External Tool 即可：

### 步骤一：注册 External Tool（一次性）

1. `DevEco Studio → Settings（⌘,）→ Tools → External Tools`
2. 点 `+` 新建，填写：
   - **Name**：`E2E Tunnels`
   - **Program**：`/bin/sh`
   - **Arguments**：`$ProjectFileDir$/docs/e2e/e2e-tunnels.sh`
   - **Working directory**：`$ProjectFileDir$`
3. OK 保存。可在 `Tools → External Tools` 菜单手动点它随时补隧道。

### 步骤二：挂到测试运行配置

1. `Run → Edit Configurations...`，选择你的测试配置（ohosTest 的 HarmonyOS Test 条目；
   没有就先在测试类/用例侧栏点一次 ▶ 生成）
2. 展开 **Before launch** 区域 → `+` → `Run External Tool` → 选 `E2E Tunnels`
3. OK 保存。此后每次点 ▶ 运行该测试配置，都会先自动建好隧道再跑用例。

> 提示：同一个 External Tool 也可以挂到主应用 Run Configuration 上，
> 这样日常开发启动应用时隧道同样自动就绪。

### 原理说明

- 隧道登记在**宿主 hdc 服务进程**上，DevEco Studio 运行测试用的也是同一台 hdc 服务
  （hdc server 是宿主机单例），因此脚本建好的隧道对 DevEco 的测试执行直接生效。
- 脚本幂等：已就绪的隧道不会重复创建，挂在 Before launch 上不会拖慢运行
  （全部就绪时耗时约 1-2 秒）。

## 3. 关键机制与故障恢复（实测结论）

本机 hdc（command-line-tools 版本）的 rport 行为有三个坑，脚本已内置处理：

| # | 事实 | 后果与脚本对策 |
|---|---|---|
| 1 | rport 规则登记在宿主 hdc 服务进程；`hdc kill` / 服务重启 / 设备重连后**注册表清空** | 隧道失效，需重跑脚本（挂在 Before launch 即自动兜底） |
| 2 | 服务重启后设备侧 hdcd 的监听 socket 可能残留：表面 `LISTEN`，实际**黑洞**（连接被拒绝/超时） | 不能只看 netstat 判"已就绪"。脚本以 **fport ls（注册表）+ netstat（设备侧）双条件**判定；发现"有监听、无注册"即判僵尸 |
| 3 | 本版本 hdc **没有 `rport rm`**（`fport rm` 只管正向，反向删除报 "ruler is not exist"） | 僵尸监听清理手段：`hdc killall-sub`（全局清理子服务进程，**异步生效**，需等待数秒）；脚本自动执行并轮询等待 |
| 4 | 设备重连后 hdcd 可能**自行重放**监听（由 hdcd 主进程持有，非子服务）——此时 `killall-sub` 清不掉 | 脚本清理等待超时后仍建失败时，唯一可靠恢复是**重启设备**：`hdc -t <key> shell reboot`（socket 随进程消亡，应用与数据保留），回连后重跑脚本 |
| 5 | 部分模拟器镜像 `netstat -l` 参数失效（-tln 会列出全部状态） | 脚本判据显式锚定 `LISTEN` 关键字 + 端口后随空白，避免被应用残留的 ESTABLISHED/CLOSE_WAIT 客户端 socket 误判 |

**僵尸监听的典型症状**：脚本未引入前，`hdc rport` 报 `TCP Port listen failed`，
或 netstat 显示 LISTEN 但测试报 `Connection refused (os error 111)`（无监听）或**超时**（僵尸监听：TCP 可建连但转发已死，如 WebDAV list 15s timeout）。
脚本会自动 `killall-sub` 清理后重建；若命中 #4（killall-sub 无效），按提示重启设备后重跑。

**多设备注意**：两台及以上设备在线时，裸 `hdc rport tcp:9000 tcp:9000` 目标不明确，
必须 `hdc -t <connect-key> rport ...`（脚本已自动处理）。

## 4. 手动命令（等价操作，排查用）

```bash
# 建隧道（多设备需 -t）
hdc -t 127.0.0.1:5555 rport tcp:9000 tcp:9000    # S3   SeaweedFS 网关
hdc -t 127.0.0.1:5555 rport tcp:8800 tcp:8800    # WebDAV
hdc -t 127.0.0.1:5555 rport tcp:2223 tcp:2222    # SFTP

# 校验：注册表应见 [Reverse] 条目 + 设备侧应 LISTEN
hdc fport ls
hdc -t 127.0.0.1:5555 shell "netstat -tln | grep -E ':(9000|8800|2223)'"

# 僵尸监听清理（异步生效，等待数秒后再 rport）
hdc killall-sub
```

## 5. 完整回归流程（含构建安装，摘自 storage-regression-test.md §5）

```bash
# 1) 容器 + 隧道
sh docs/e2e/e2e-fileserver.sh            # 或脚本加 --containers
sh docs/e2e/e2e-tunnels.sh

# 2) 构建（主 HAP 与测试 HAP 都要；测试模块必须显式构建）
devecocli build --product mac_debug
devecocli build --product mac_debug --modules entry@ohosTest

# 3) 安装（必须先卸载，bm install -r 会报 sign info inconsistent）
cp entry/build/mac_debug/outputs/default/entry-default-signed.hap \
   entry/build/mac_debug/outputs/ohosTest/entry-ohosTest-signed.hap /tmp/haps/
hdc -t <connect-key> shell bm uninstall -n com.aimilin.keepassho
hdc -t <connect-key> file send /tmp/haps /data/local/tmp/
hdc -t <connect-key> shell bm install -p /data/local/tmp/haps

# 4) 执行（全量非 UI 回归）
hdc -t <connect-key> shell "aa test -b com.aimilin.keepassho -m entry_test \
  -s unittest OpenHarmonyTestRunner -s notClass OpenDatabaseUiTest -s timeout 60000"
```

## 6. 基线（本方案验证记录，2026-10-08）

僵尸监听复现并清理后重建隧道，真机模拟器（127.0.0.1:5555）实测：

| 套件 | 结果 |
|---|---|
| SFTPStorageRealFileTest | 4/4 Pass |
| S3ClientTest | 20/20 Pass |
| WebDavTest | 11/11 Pass |

（此前同环境因僵尸监听 SFTP 为 0/4 Error，错误 `Connection refused (os error 111)`，
经脚本 killall-sub 清理 + 重建后恢复全绿。）
