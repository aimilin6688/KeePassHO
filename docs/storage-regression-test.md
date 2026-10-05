# 存储层真实回归测试总纲

> 范围：`entry/src/ohosTest` 下全部 IFileStorage 实现（Local / WebDAV / SFTP / FTP / S3 / OneDrive / 华为网盘 / pCloud / Cache）的回归测试说明
> 原则：**全部真实数据文件操作，零 mock**。测试不合适处直接改产品代码或测试代码，不做假通过
> 服务搭建：`docs/s3/seaweedfs-server.md`、`docs/webdav/webdav-server.md`、`docs/ftp/sftp-server.md`

---

## 1. 真实数据夹具

| 项 | 值 |
|---|---|
| 夹具文件 | `entry/src/ohosTest/resources/rawfile/unit-test.kdbx` |
| 来源 | 复制自 `libs/kdbxweb/src/ohosTest/resources/rawfile/AesKdfKdbx4.kdbx`（真实 KDBX4 / AES-KDF 库，250542 字节） |
| 读取方式 | `context.createModuleContext('entry_test').resourceManager.getRawFileContent()`，进程内缓存 |
| 夹具入口 | `entry/src/ohosTest/ets/test/storage/TestFixtures.ets` 的 `loadUnitTestKdbx()` |
| 断言 | `assertKdbxMagic()`：KDBX 魔数 `03 D9 A2 9A` + 精确字节数双重校验 |

## 2. 各存储后端的测试策略

| 后端 | 服务 | 测试文件 | 说明 |
|---|---|---|---|
| S3 | SeaweedFS（本地 podman） | `storage/s3/S3Client.test.ets`、`S3Storage.test.ets`、`S3ClientMultipart.test.ets` | 全量真实断言：listBuckets 必须成功且含测试桶、上传读回逐字节一致、多级/中文路径 |
| WebDAV | bytemark/webdav（本地 podman） | `entry/WebDav.test.ets` | 客户端层 + Storage 层，含条件写冲突（陈旧版本 → `VERSION_CONFLICT`） |
| SFTP | atmoz/sftp（本地 podman） | `storage/SFTPStorageSemantics.test.ets`、`storage/SFTPStorageRealFile.test.ets` | 真实上传/读回/getInfo（`size\|mtime` 版本）/条件写冲突 |
| FTP | 本地 podman | `docs/ftp/ftp-regression-test.md` | 明文 FTP 回归 |
| Local/Cache | 设备本地 | 各自测试文件 | 真实临时目录读写 |
| 华为网盘 | 专有云，无法自建 | `storage/huawei/*` | **条件注册**：`HuaweiDriveTestConfig.isRealApiEnabled()` 为假时真实 API 用例不注册（仓内凭证已清空），OAuth URL 构造等纯逻辑用例常驻 |
| pCloud | 专有云，无法自建 | `storage/pcloud/PCloudStorage.test.ets` | **条件注册**：`PCloudTestConfig.isRealApiEnabled()` 门控第 5-10 节 RealAPI 用例 |

### 门控约定（诚实跳过，非 mock 非假通过）

需要真实云端凭证的用例一律：

```ts
if (XxxTestConfig.isRealApiEnabled()) {
  it('RealAPI ...', 0, async () => { ... });
}
```

凭证留空 → 用例不注册 → 报告中不出现假通过。需要跑真实云端时，在对应 `*TestConfig.ets` 填入凭证即可。

## 3. 冲突解决方案的测试覆盖

条件写（`WriteOption` + `FileInfo.version`）语义在各后端验证：

- **版本号语义**：WebDAV = `etag|lastModified`；SFTP / FTP / Local = `size|mtime`
- **成功路径**：以当前版本条件写 → 成功
- **冲突路径**：以陈旧版本条件写 → 抛 `StorageError(VERSION_CONFLICT)`，且**远端文件未被覆盖**
- `FTPStorage.write` = serialize(writeOnce)，无重试；`StorageError` 透传

## 4. 回归命令

```bash
# 前置：服务容器 + rport 隧道就绪（2223/9000/8800）
hdc fport ls   # 确认三条 [Reverse]

# 全量非 UI 回归（排除 UI 套件）
hdc shell aa test -b com.aimilin.keepassho -m entry_test \
  -s unittest OpenHarmonyTestRunner \
  -s notClass OpenDatabaseUiTest -s timeout 60000

# 单套件
hdc shell aa test -b com.aimilin.keepassho -m entry_test \
  -s unittest OpenHarmonyTestRunner -s class S3ClientTest -s timeout 60000
```

结果看 `OHOS_REPORT_RESULT`，失败明细 `OHOS_REPORT_STATUS: stream=Error in <用例名>, <原因>`。

## 5. 构建注意（重要）

**`devecocli build`（等价 `assembleHap`）只构建主 HAP，不构建 ohosTest 模块。** 测试代码变更后必须显式构建测试模块，否则设备上跑的是旧用例：

```bash
devecocli build --product mac_debug                          # 主 HAP
devecocli build --product mac_debug --modules entry@ohosTest # 测试 HAP
```

安装（双 HAP 一起装）：

```bash
cp entry/build/mac_debug/outputs/default/entry-default-signed.hap \
   entry/build/mac_debug/outputs/ohosTest/entry-ohosTest-signed.hap /tmp/haps/
hdc shell bm uninstall -n com.aimilin.keepassho
hdc file send /tmp/haps /data/local/tmp/
hdc shell bm install -p /data/local/tmp/haps
```

主 HAP 文件名是 `entry-default-signed.hap`（不是 `entry-mac_debug-signed.hap`）。`bm install -r` 会报 sign info inconsistent，必须先 uninstall。

## 6. 基线结论

- 2026-10-04：**Tests run: 418, Failure: 0, Error: 0, Pass: 418**（S3Client 20/20、S3Storage 27/27、WebDav 9/9、SFTPStorageRealFile 4/4、S3ClientMultipart 全过；华为/pCloud 真实 API 用例按门控不注册）
- 用例数相对旧基线（435）变化：华为 18 + pCloud 7 门控移除，WebDav 重写 +6，SFTPStorageRealFile +4
- 2026-10-05：KPSN 二进制快照协议合入后（`docs/KDBX跨线程数据传输优化设计-二进制快照协议.md` §12）WebDAV 回归复跑：**WebDavTest 9/9**（条件写冲突 VERSION_CONFLICT 用例在内，全过）
- 2026-10-05：rport 隧道整体重建后（SFTP 设备侧 2223、S3 9000、WebDAV 8800，见 §5），复跑全部 12 个非 UI 存储套件：**Tests run: 111, Pass: 111**（S3ClientTest、S3StorageTest、S3Client_Multipart_Upload/Logic/Integration、S3StorageIntegrationTest 6/6、SFTPHandlerTest、SFTPHandlerConnectTest、SFTPStorageRealFileTest、FTP/Cache/RecentFiles SftpSemanticsTest 全过）；其中 `should_use_regular_upload_below_threshold` 修复了 `new ArrayBuffer(4.9*1024*1024)` 浮点截断与浮点断言不一致的测试缺陷（分配与断言统一取 `Math.floor`）

## 7. 本轮真实回归修出的产品 bug

| Bug | 影响 | 修复 |
|---|---|---|
| `S3Client` listBuckets / 虚拟主机风格 URL 丢端口 | 自建 S3 网关（非标准端口）listBuckets 必失败、testConnection 误报；对 AWS 默认端口无感 | 新增 `S3Client.buildAuthority()` 统一拼 `host:port` |
| `S3SignatureV4.signRequest` Host 头丢端口 | 违反 SigV4 规范（非标准端口必须含在 Host 头），严格校验的服务端会 403 | 保留端口，注释说明规范要求 |
| `S3Storage` 初始化未从 config 读 pathStyle（测试侧） | S3Storage 测试走虚拟主机风格 → DNS 失败 | `S3TestConfig.getStorageConfig()` 显式设置 `pathStyle`/`timeout` |

## 8. UI 回归（独立执行）

UI 层冲突弹框三分支（合并/覆盖/重载）E2E 用 uitest 手动驱动，见 `docs/uitest-manual-driving-guide.md`，不在本回归范围内（`-s notClass OpenDatabaseUiTest`）。
