# uitest 手动驱动 UI 操作手册（E2E 实战版）

> 沉淀日期：2026-10-02，设备：Mac + HarmonyOS 模拟器（x86_64, 1320×2720, `127.0.0.1:5557`），uitest 6.0.2.3
> 姊妹篇：`docs/ui-testing-guide.md`（命令行/ArkTS 两套 UI 测试基础 + verify_ui 坑 1-6）
> 本文专讲：**verify_ui 不可靠时，用 `hdc shell uitest uiInput` + `dumpLayout` 手动驱动 App 完成真实服务器 E2E 的完整操作流程**。全部经验为实测，非推断。

---

## 1. 定位：什么时候用这套流程

| 场景 | 用什么 |
|---|---|
| 快速核对单页 UI | verify_ui（简单场景够用） |
| **长表单、密码输入、多页跳转、真实服务器联调** | **本文的手动 uitest 驱动** |
| 可回归的正式用例 | ArkTS TestKit（见姊妹篇 B 节） |

verify_ui 在本次 E2E 中暴露的问题（2 次失败实证）：
- 输入注入会**多打尾随字符**（确认密码 10 字符被注入成 12 星 → `isCreateButtonEnabled()` 判不等 → 创建按钮禁用，点击"无响应"）
- 应用启动检测不稳（"应用图标已在桌面可见，但未启动"，实为息屏）
- 无法逐步断言每个字段的实际内容

手动驱动的核心优势：**每一步都 dumpLayout 断言，确定性强，错误可定位**。

---

## 2. 环境准备

### 2.1 设备与亮屏（必做，否则白干）

```bash
hdc -t 127.0.0.1:5557 shell "power-shell wakeup"          # 唤醒
hdc -t 127.0.0.1:5557 shell "power-shell timeout -o 600000"  # 亮屏 10 分钟
```

息屏时 UI 注入静默失败、verify_ui 启动检测报错。每 10 分钟续一次。

### 2.2 真实 SFTP 测试服务器（podman atmoz/sftp）

```bash
# 启动（amd64 镜像在 arm64 Mac 走 qemu 仿真，SSH 握手偏慢属正常）
podman run -d --name sftp-e2e -p 2222:22 -e SFTP_USERS=e2e:e2epass:1001 atmoz/sftp:latest

# 【关键坑】chroot 约束：/home/e2e 必须 root:root 755，用户可写目录必须是子目录
podman exec sftp-e2e sh -c 'mkdir -p /home/e2e/data && chown 1001:100 /home/e2e/data && chown root:root /home/e2e && chmod 755 /home/e2e'
# 误把 /home/e2e chown 给用户 → sshd 报 "bad ownership or modes for chroot directory"
# → 密码认证成功后会话即断（应用侧卡"连接中..."或报错，极易误判为客户端 bug）

# 凭据验证（Mac 侧必须禁公钥，否则本机 agent 密钥导致 Too many authentication failures）
expect -c 'spawn sftp -o PubkeyAuthentication=no -o StrictHostKeyChecking=no -P 2222 e2e@127.0.0.1
expect "password:"; send "e2epass\r"; expect "sftp>"; send "ls -la\r"; expect "sftp>"; send "bye\r"'

# 服务器侧验证命令（E2E 断言用）
podman exec sftp-e2e ls -la /home/e2e/data/
```

客户端视角路径映射：chroot 根 `/` = 容器 `/home/e2e`，App 里填 `/data/xxx.kdbx`。

### 2.3 反向隧道：让设备访问 Mac 上的服务器

```bash
# 【语法坑】本版 hdc 无 add 子命令，正确写法：
hdc -t 127.0.0.1:5557 shell "hdcd" >/dev/null 2>&1
hdc rport tcp:2222 tcp:2222      # 设备 127.0.0.1:2222 → Mac 2222
hdc fport ls                     # 确认 [Reverse] 127.0.0.1:5557 tcp:2222 tcp:2222
hdc -t 127.0.0.1:5557 shell "netstat -tn | grep 2222"   # 设备侧应 LISTEN
```

App 内服务器地址填 `127.0.0.1`、端口 `2222`。模拟器 shell 无 curl/nc/wget，只能靠 netstat 和 App 实连验证。

### 2.4 应用构建/安装/确定性冷启动

```bash
devecocli build --product mac_debug    # default 产品签名是 Windows 路径，Mac 必须用 mac_debug
hdc -t 127.0.0.1:5557 install -r entry/build/mac_debug/outputs/default/entry-default-signed.hap
hdc -t 127.0.0.1:5557 shell "bm clean -n com.aimilin.keepassho -d"   # 清数据=回出厂首页
hdc -t 127.0.0.1:5557 shell "aa force-stop com.aimilin.keepassho"
hdc -t 127.0.0.1:5557 shell "aa start -a EntryAbility -b com.aimilin.keepassho"
```

冷启动行为（坑 6 复述）：**有最近记录时自动跳解锁页，不停首页**。要回首页必须 `bm clean`。

---

## 3. 核心操作原语

### 3.1 注入命令

```bash
hdc -t 127.0.0.1:5557 shell "uitest uiInput click 900 455"            # 点击
hdc -t 127.0.0.1:5557 shell "uitest uiInput longClick 900 858"        # 长按（弹选择菜单）
hdc -t 127.0.0.1:5557 shell "uitest uiInput swipe 660 2000 660 1500 800"  # 滑动
hdc -t 127.0.0.1:5557 shell "uitest uiInput inputText 900 656 127.0.0.1" # 输入（追加式！见 §4）
hdc -t 127.0.0.1:5557 shell "uitest uiInput keyEvent Back"            # 返回/收键盘
hdc -t 127.0.0.1:5557 shell "uitest uiInput keyEvent 2055"            # 退格 KEYCODE_DEL（见 §4）
```

### 3.2 dumpLayout + Python 解析（每步断言的基础）

```bash
F=$(hdc -t 127.0.0.1:5557 shell "uitest dumpLayout" 2>/dev/null | tail -1 | sed 's/.*://')
# 【坑】保存路径 /data/local/tmp/layout_<随机数>.json，文件名每次不同，必须从输出解析
hdc -t 127.0.0.1:5557 shell "cat $F" > /tmp/l.json
python3 - <<'EOF'
import json
d = json.load(open('/tmp/l.json'))
def walk(n):
    a = n.get('attributes', {})
    if a.get('type') in ('TextInput', 'TextArea', 'Select', 'Button'):
        t = a.get('text', '')
        print(a.get('type'), repr(t[:30]) if '*' not in t else f"{t.count('*')} asterisks", a.get('bounds', ''))
    for c in n.get('children', []):
        walk(c)
walk(d)
EOF
```

bounds 格式 `[x1,y1][x2,y2]` 物理像素，中心点 `((x1+x2)//2,(y1+y2)//2)` 即点击坐标。
**任何结构变化（切协议、键盘弹出/收起、展开菜单）后必须重新 dump 拿新坐标。**

---

## 4. 实证行为特性（本节是手册核心，全部踩坑实测）

### 4.1 `inputText` 是追加式，不是替换

- 行为：点击坐标定位光标 → 在光标处**插入**文本。已有 `22` 的端口框再输 `2222` → `222222`。
- 空字段直接输 ✓；**修改已有内容必须先删除**。
- 点文本末尾右侧（如字段内 x=1230）可确保光标落在末尾。

### 4.2 退格：`keyEvent 2055` 可用，其他全废

| 尝试 | 结果 |
|---|---|
| `uitest uiInput keyEvent 67`（Android 码） | 无效 |
| `uinput -K -d 14 -u 14`（Linux KEY_BACKSPACE） | 无效，且把键状态机搞乱 |
| **`uitest uiInput keyEvent 2055`（OHOS KEYCODE_DEL）** | **有效** ✓ |

### 4.3 点击后首个退格偶发丢失

点击定位光标后立刻退格，第一下常被焦点切换吃掉。**删 N 字符发 N+1 次退格，dump 复核，多删了补输**。批量退格脚本：

```bash
hdc -t 127.0.0.1:5557 shell "uitest uiInput click 1230 1469"; sleep 0.6
for i in $(seq 1 14); do hdc -t 127.0.0.1:5557 shell "uitest uiInput keyEvent 2055" >/dev/null; sleep 0.12; done
```

### 4.4 密码框掩码星号数 ≠ 字符数（重大陷阱）

- FTPPage 密码框：输入 8 字符只显示 **7 个星**，但实际内容完整（后来明文态看到 `e2epass` 全在）。
- CreateDatabase / Password 页密码框：星号数与字符数 1:1。
- **结论：绝不能用星号计数断言密码正确性**，用"测试连接"的认证结果做真值验证。

### 4.5 Back 键的双重语义

键盘弹起时按 Back **只收键盘不返回**；再按才返回上一页。点底部按钮前必须先 Back 收键盘（安全键盘 Canvas 会盖住 [115,1988] 一带的按钮）。

### 4.6 Select 下拉两步走

点 Select → dumpLayout 找选项 Text 坐标 → 点选项 → **重新 dump**（布局会重排：如 FTPPage 切 SFTP 后 FTPS 行隐藏、按钮从 y1877 上移到 y1675）。

### 4.7 toast 转瞬即逝，状态标签更稳

- toast（如"连接成功""网络连接失败"）约 3 秒消失：点击后 sleep 2~3 秒内 dump 抓，或轮询。
- 页面状态标签（FTPPage "连接中.../连接成功/错误信息"）持久存在，优先断言它。
- 轮询模板：

```bash
for i in 1 2 3 4 5 6; do
  sleep 3; F=$(hdc ... "uitest dumpLayout" | tail -1 | sed 's/.*://'); hdc ... "cat $F" > /tmp/p$i.json
  S=$(python3 -c "...解析状态区...")
  echo "poll$i: $S"; case "$S" in *成功*|*失败*) break;; esac
done
```

### 4.8 隐藏栈与重叠按钮（坑 1 复述 + 新证据）

- `dumpLayout` 包含 4 个隐藏根导航栈，重叠控件取**有 id 的那个**（如 `btn_add_fab`）。
- DatabaseView 悬浮球区有两个 56vp 按钮纵向堆叠：上=时间令牌、下=添加球 `btn_add_fab`。
- `btn_add_fab` 点击后**展开菜单**（添加分组/添加条目/模板创建），纯图标按钮——dump 过滤条件要含无文本 Button，否则看不见。

### 4.9 hilog 在模拟器上拿不到应用日志

app pid 过滤结果 0 行，无法用日志排障。**排障 = dumpLayout 行为观察 + 服务器侧证据（podman exec / netstat）+ 代码审读**三方对照。

### 4.10 后台挂起、快锁与连接观察（场景 3 新增）

- **挂起**：`uitest uiInput keyEvent Home`（有效）→ dump 出现桌面图标即确认后台。**不要用 force-stop**（那是冷启动，会销毁运行态）。
- **快锁**：App 从后台返回时弹"快速解锁"对话框（安全特性，要求输密码末 3 位）：输入框 ~(660,1144)、关闭 ~(363,2618)、解锁 ~(957,2618)。不解锁则 FAB 点击被对话框挡住。
- **后台期间连接观察**：
  - 设备侧：`netstat -tn | grep 2222`（ESTABLISHED 成对出现）
  - 容器侧：**无 netstat/ss，用 `/proc/net/tcp`**——`awk '$4=="01"' /proc/net/tcp`（st=01=ESTABLISHED），端口 22=十六进制 `0016`
- **服务端强杀会话**：杀 sshd 会话三件套（`sshd -D -e -R` 进程）。**坑：qemu 仿真容器里会残留已断连接的僵尸 sshd 进程（pid 更大的是僵尸，pid 最小的三件套才是活会话）**——杀错只清了 TIME_WAIT 的残骸，活连接纹丝不动；杀对后 FIN 会经 rport 链路传回设备侧（连接行消失）。
- **实测结论**：后台 90s + `ClientAliveInterval 15` 掐连接配置下，连接被 russh 保活应答全程保住；强杀后 App 首次保存经 `isClosed()`→自动重连无缝恢复。

---

## 5. 完整 E2E 操作流程（SFTP 数据库创建 → 解锁 → 条目 → 保存回环）

> 坐标为本机（1320×2720）实测示例，**换设备/布局变动后一切以当次 dump 为准**。每步的"验证"列必须执行。

### 阶段 A：创建数据库

| # | 操作 | 坐标/值 | 验证 |
|---|---|---|---|
| A1 | 冷启动（bm clean + force-stop + aa start） | — | dump 出现 打开数据库(714,1489)/创建数据库(714,1759) |
| A2 | 点创建数据库 | click 714 1759 | 出现 标题/密码/确认密码 输入框 |
| A3 | 填名称 | inputText 660 558 e2e-test | dump 文本=`e2e-test` |
| A4 | 填密码×2 | inputText 660 877 / 660 1196，各 E2eTest123 | dump 两框星号数一致（此页 1:1） |
| A5 | Back 收键盘 | keyEvent Back | 创建按钮可见且坐标回到 (660,2069) |
| A6 | 点创建 | click 660 2069 | 进入"请选择文件"位置选择页 |

### 阶段 B：FTP/SFTP 配置（最长链路，坑最密）

| # | 操作 | 坐标/值 | 验证 |
|---|---|---|---|
| B1 | 点 FTP/SFTP 卡片 | click 660 1682 | 出现 协议/服务器地址/端口/用户名/密码/根路径/FTPS |
| B2 | 切协议 SFTP | click 900 455 → dump → 点 SFTP 选项(660,805) | 协议=SFTP、端口自动 21→22、FTPS 行消失、按钮上移 y1675 |
| B3 | 端口 22→2222 | **利用追加式**：inputText 900 858 `22` | dump=`2222`（不要先清空再输，追加是捷径） |
| B4 | 服务器地址 | inputText 900 656 127.0.0.1 | dump=`127.0.0.1` |
| B5 | 用户名 | inputText 900 1060 e2e | dump=`e2e` |
| B6 | 密码（两段式） | click 900 1262 → **sleep 1.5**（等安全键盘稳）→ inputText 900 1262 e2epass | 星号数可能 7/8，**不作断言**，留给 B8 认证验证 |
| B7 | 根路径改 `/data/e2e-test.kdbx` | click 1230 1469（光标到末尾）→ 退格×14 → 复核为空 → inputText 900 1469 `/data/e2e-test.kdbx` | dump 精确匹配该字符串（多字符残留就补退格） |
| B8 | 测试连接 | keyEvent Back → click 216 1675 → 轮询状态区 | 状态=`连接成功`；netstat 有 127.0.0.1:2222 ESTABLISHED |
| B9 | 确定（上传） | click 1158 1763 → sleep 8 | 跳转"解锁数据库"页 **且** `podman exec sftp-e2e ls -la /home/e2e/data/` 有文件——**双端都要验**（App 跳转≠上传成功，见 §6 缺陷 2） |

### 阶段 C：解锁

| # | 操作 | 坐标/值 | 验证 |
|---|---|---|---|
| C1 | 输入主密码 | click 660 1377 → sleep 1.2 → inputText 660 1377 E2eTest123 | 星号 10（此页 1:1） |
| C2 | 解锁 | keyEvent Back → click 988 2653 → 轮询 | 页面出现库名/下拉刷新/回收站（DatabaseView） |

### 阶段 D：添加条目（保存回环验证）

| # | 操作 | 坐标/值 | 验证 |
|---|---|---|---|
| D1 | 点添加球展开菜单 | click 1118 2473（id=btn_add_fab 那个） | dump 出现 添加分组/添加条目/模板创建 |
| D2 | 点添加条目 | click 1118 2418 | 出现 标题/用户名/密码 表单 |
| D3 | 填三字段 | inputText 471 483 / 660 781 / click 660 1132+inputText | dump 三字段齐（密码 12 星=12 字符，此页 1:1） |
| D4 | 保存 | click 1185 206（右上角图标按钮） | 回 DatabaseView 且列表出现该条目；**`podman exec` 服务器文件 size/mtime 变化**（1269→1493B）——这是"自动保存走 SFTP"的直接证据 |

### 阶段 E：记录语义验证（L1/L2 核心）

**E1 服务器不可达 → 记录保留 + 真实网络错误（场景 2）**
```
podman stop sftp-e2e → force-stop → aa start
→ 预期：自动跳解锁页（记录还在）
→ 输密码点解锁 → 轮询抓 toast「网络连接失败，请稍后重试」（绝不能是"文件不存在"）
→ Index 点"最近打开的数据库"(714,2029) → RecentFiles 页记录行仍在
```

**E2 服务端删文件 → 记录移除（场景 4）**
```
podman start sftp-e2e → podman exec sftp-e2e rm /home/e2e/data/e2e-test.kdbx
→ force-stop → aa start
→ 预期：不跳解锁页、停在 Index
→ Index 点"最近打开的数据库" → RecentFiles 页「暂无记录」
```

**【易错点】Index 页"最近打开的数据库"是导航按钮，不是记录列表！** Index 页面本身不渲染任何记录行；记录断言必须进 RecentFiles 页做。曾因误读此布局得出错误结论后返工。

### 阶段 F：保存冲突弹框三分支（合并/覆盖/重载）

**F0 设计要点**
- 冲突触发条件：保存时下载远端 → hash ≠ App 加载基线 → AlertDialog「远端数据库已修改」三按钮：合并 [108,1398][1212,1533]→click(660,1465)、覆盖 [108,1546][1212,1681]→(660,1613)、重载 [108,1694][1212,1829]→(660,1761)。hilog 证据行（tag `DatabaseSave`）：`Remote content changed: hash mismatch`。
- **【同库约束】合并分支双方必须同根分组**（kdbxweb `merge` 遇不同根组抛 `MergeError: default group is different`，toast「合并异常」）。用两个独立创建的库模拟"他设备修改"只能测覆盖/重载；测合并必须用**同库文件副本**。
- 模拟"他设备保存"：`podman exec sftp-e2e cp /home/e2e/data/e2e-test.kdbx /home/e2e/data/e2e-test2.kdbx` → App 打开 e2e-test2.kdbx 加条目保存 → 再 `cp e2e-test2.kdbx e2e-test.kdbx` 覆盖回去。
- **【chown 坑】`podman exec cp` 新建的文件属主是 root**，SFTP 用户 e2e 写入报 `sftp:6 Permission denied`（FTPStorage.ets:283 FILE_WRITE_ERROR），必须 `podman exec sftp-e2e chown e2e:users /home/e2e/data/*.kdbx`。cp 覆盖已有文件不改属主，新建才会踩。
- 换库路径：**DatabaseView 无"更换数据库"按钮**。路线：force-stop + aa start → 解锁页「更换数据库」(331,2653) → 打开页（卡片列表，FTP/SFTP (660,1682)）→ 打开表单（同创建表单，但按钮文案=「确定」；端口预填 **21** 需先 2055×3 清空再输 2223）→ 测试连接 (216,1675) → **连接成功后状态行使按钮下移**，确定变 (1158,1763)。回程：解锁页 → 更换数据库 → 打开页 → Back → Back → Index → 最近打开的数据库 (714,2029) → RecentFiles 点记录行（第二行 (420,664)）→ 解锁页。
- DatabaseView 标题显示**数据库名**（创建时填的名称）而非文件名——重载他库内容后标题会变，勿误判打开错文件。

**F1 三分支操作与断言**

| 分支 | 前置 | 操作 | 断言 |
|---|---|---|---|
| 覆盖 | 服务器被换成他库内容（1461B） | 加条目 → 保存 → 弹框点覆盖 (660,1613) | 列表保留本地条目；服务器 size/mtime 变为本地版（1461→1637B） |
| 重载 | 同上 | 加条目 → 保存 → 弹框点重载 (660,1761) | 列表变远端内容（他库条目）；**服务器文件 size/mtime 完全不变**（重载只读不写） |
| 合并 | 同库副本 e2e-test2 加 Merge-Remote 保存（P2），cp 回 e2e-test（App 持 P1） | 加条目 Merge-New → 保存 → 弹框点合并 (660,1465) | 列表含**双方条目**（远端 Merge-Remote + 本地 Merge-New）；服务器 size/mtime 变化（1605→1653B）；hilog `合并中...→保存成功` |

**【弹框时机】点保存后冲突弹框出现需 3~10s**（SFTP 下载远端对比 hash），轮询 dump 等「远端数据库已修改」文本，勿固定 sleep 一次就断言。表单页右上保存按钮 (1185,206)；保存失败时表单不关闭，服务器 mtime 不变。

---



## 6. 故障排查速查

| 症状 | 根因 | 处置 |
|---|---|---|
| 测试连接永远"连接中..." | ① FTPPage 曾缺 `.catch`（已修复 627abe8f）② 服务器会话级故障（见下行） | 先看 sshd 日志 `podman logs sftp-e2e` |
| sshd 日志 "bad ownership or modes for chroot directory" | chroot 目录被 chown 给用户 | `chown root:root /home/e2e && chmod 755`，可写目录放子目录 `/data` |
| 连接成功但上传后服务器无文件 | ① chroot 根不可写（root:root 755）② `DataService.saveKdbx` 吞错误跳了解锁页（待修缺陷，App 侧行为正常≠成功） | 双端验证；查容器目录属主 |
| SFTP 写入报 `sftp:6 Permission denied` | 容器内文件属主 root（`podman exec cp` 新建文件默认 root） | `podman exec sftp-e2e chown e2e:users /home/e2e/data/*.kdbx` |
| netstat 只有 TIME_WAIT 无 ESTABLISHED | 连接建立后被服务端掐断 | 查 sshd 日志，多为 chroot/权限问题 |
| 点按钮无响应 | ① 键盘遮住 ② 按钮被禁用（表单校验不过，如两次密码不等）③ 点中隐藏栈按钮 | Back 收键盘；dump 复核字段内容；换重叠位置 |
| 输入字段内容错乱 | 追加式 inputText + 光标定位失败 | click 字段最右侧确保末尾光标，退格 N+1 次清空后重输，dump 复核 |
| rport 隧道不通 | 语法错误（本版无 add） | `hdc rport tcp:2222 tcp:2222` + `hdc fport ls` 复核 |
| UI 注入全部无效 | 息屏 | `power-shell wakeup` + `timeout -o 600000` |

---

## 7. 与既有资产的关系

| 资产 | 覆盖内容 | 关系 |
|---|---|---|
| `docs/ui-testing-guide.md` | uitest 命令全景、ArkTS TestKit、verify_ui 坑 1-6 | 基础篇，先读 |
| 本文 | 手动驱动方法论 + 真实服务器 E2E 全流程 + 实证坑 4.x | 实战篇 |
| `docs/SFTP客户端Rust绑定开发计划.md` §9.3 | E2E 场景定义与结果 | 本文是其执行手册 |
| 计划文档 §9.3 末尾"UI 自动化工具链经验" | §4 的浓缩版 | 本文为完整版 |

若后续需要把本流程升级为 agent 技能（每次会话自动可用），以本文为蓝本封装 SKILL.md 即可。
