# E2E 测试数据库（e2e-test-data.kdbx）

预生成的 KeePass 测试数据库，存放在 SeaweedFS（S3 协议）中，用于手工与自动化 E2E 测试。
数据库包含多级嵌套分组、TOTP 令牌、附件、图片附件、标题/密码边界条目、颜色分组、回收站条目等完整测试场景。

- 生成时间：2026-10-14（真机 24F0224819000140 实测通过）
- 格式：KDBX 4.1，约 170 KB
- 生成测试：`GenerateE2eTestDatabaseTest` 3/3 通过；改密码/元数据套件 `DatabaseChangePasswordMetaTest` 2/2 通过

## 连接信息（App 内 S3 存储配置）

| 配置项 | 值 |
| --- | --- |
| 存储类型 | S3 |
| 服务商 | 其他/自定义（S3 兼容） |
| 端点 Endpoint | `http://127.0.0.1:9000`（设备侧地址，经反向隧道到宿主） |
| Region | `us-east-1` |
| Access Key ID | `e2e` |
| Secret Access Key | `e2etest123` |
| Bucket | `e2e-test` |
| 文件路径 | `e2e-test-data.kdbx`（桶根目录） |
| Path Style | 开启 |
| 超时 | 30000 ms |

> SeaweedFS 测试网关对 AK/SK 只要求非空，`e2e` / `e2etest123` 仅为约定值。

## 数据库凭据

| 项 | 值 |
| --- | --- |
| 主密码 | `E2e-Test-123!` |
| 密钥文件 | 无 |
| 数据库名 | `E2E-Test-Database` |
| 默认用户名 | `test-user@example.com` |
| 历史记录上限 | 10 条 / 10 MB |

## App 内打开步骤

1. 启动 KeePassHO → 打开数据库页 → 存储选择 **S3**
2. 按上表填入连接信息（端点 `http://127.0.0.1:9000`、AK/SK、桶 `e2e-test`、Path Style 开启）
3. 浏览文件列表，选择 `e2e-test-data.kdbx`
4. 输入主密码 `E2e-Test-123!` 解锁

> 设备必须先建立反向隧道：`hdc rport tcp:9000 tcp:9000`（设备 127.0.0.1:9000 → 宿主 9000），且宿主 SeaweedFS S3 网关在运行。

## 数据库结构（约 85 条目 / 41 分组）

```
E2E-Test-Database（根）
├─ 使用说明（1 条目：本数据库的说明与主密码提示）
├─ 网络账号（蓝色，9 条目）
│  ├─ 邮箱服务：QQ邮箱(TOTP)、Gmail、Outlook
│  ├─ 社交平台：微信、微博、Twitter X
│  └─ 云存储：阿里云OSS、AWS S3(TOTP, 60s)、七牛云
├─ 工作账号（绿色，5 条目）
│  ├─ 办公系统：OA系统、企业VPN
│  └─ 开发平台：GitLab(TOTP, issuer=CompanyGitLab)、Jenkins、生产服务器SSH
├─ 金融账户（红色，3 条目）
│  ├─ 银行账户：招商银行、支付宝
│  └─ 投资理财：证券账户
├─ 边界测试（40 条目）
│  ├─ 标题边界测试：10 条目（纯空格标题、超长标题、emoji、特殊字符、空用户名等）
│  ├─ 密码强度测试：9 条目（空、超长、全数字、全符号、弱口令、强口令等）
│  ├─ TOTP令牌测试：8 条目（RFC6238/SHA1/SHA256/SHA512、6/8 位、30/60s、带 issuer 等）
│  ├─ 附件测试：8 条目（文本/JSON/CSV/超长文件名等附件）
│  ├─ 图片附件测试：5 条目（程序化生成的纯色/渐变 PNG，64x64 与 256x256）
│  └─ 综合测试：5 条目（全字段、3 版历史、已过期、即将过期、回收站条目）
├─ 深层嵌套（7 层长中文名，用于测试树形展开与路径显示）
├─ 颜色分组大全（15 个分组：红/橙/黄/绿/青/蓝/紫/粉/棕/灰/黑/白/金/银/自定义）
└─ 回收站（1 条目：综合测试-回收站条目）
```

其他特征：

- 密码字段启用内存保护；TOTP 存于受保护自定义字段 `otp`（otpauth URI）
- 条目含 icon、前景色/背景色、tags（`测试`/`边界`/`附件` 等）、备注、过期时间
- 深层嵌套第 2 层分组名超过 40 个字符，用于验证名称截断
- 回收站条目通过 `db.remove()` 移入，App 内"回收站"分组可见

## 重新生成 / 重新上传

测试代码全部位于测试目录（不进入主应用）：

```
entry/src/ohosTest/ets/test/testdata/
├─ TestPngBuilder.ets                  # 程序化 PNG 生成（CRC32/zlib stored 块）
├─ TestDataGenerator.ets               # 数据结构与生成逻辑 + 验证辅助
├─ GenerateE2eTestDatabase.test.ets    # 结构验证 + S3 上传（3 用例）
└─ DatabaseChangePasswordMeta.test.ets # 改密码往返 + 元数据持久化（2 用例，纯内存）
```

构建并运行（覆盖安装，勿卸载）：

```bash
# 构建主包与测试包（Mac）
devecocli build --product mac_debug
devecocli build --modules entry@ohosTest --product mac_debug

# 覆盖安装
hdc install -r entry/build/mac_debug/outputs/default/entry-default-signed.hap
hdc install -r entry/build/mac_debug/outputs/ohosTest/entry-ohosTest-signed.hap

# 确保反向隧道与网关就绪
hdc rport tcp:9000 tcp:9000   # 已存在则跳过（hdc fport ls 查看）
curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:9000/   # 期望 200

# 运行生成套件（生成 → 结构断言 → 上传 S3 → S3 读回重载断言）
hdc shell aa test -b com.aimilin.keepassho -m entry_test \
  -s unittest OpenHarmonyTestRunner \
  -s class GenerateE2eTestDatabaseTest -s timeout 300000
```

注意：`DatabaseChangePasswordMetaTest` 为纯内存用例（改密码、改元数据不落盘、不影响 S3 上的文件），S3 上的数据库主密码始终保持 `E2e-Test-123!`。

## 宿主侧直查

```bash
# 匿名即可读（测试网关桶为公开读）
curl -sI http://127.0.0.1:9000/e2e-test/e2e-test-data.kdbx   # 期望 200
curl -s -o /tmp/e2e.kdbx http://127.0.0.1:9000/e2e-test/e2e-test-data.kdbx
xxd -l 8 /tmp/e2e.kdbx   # 期望 03 d9 a2 9a 67 fb 4b b5（KeePass 2.x / KDBX 魔数）
```
