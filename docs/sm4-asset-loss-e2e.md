# 「关键资产不存在」问题 E2E 复现指南（S3 存储路径）

> 目标：端到端复现"SM4 密钥资产不存在 → 旧存储配置解密失败 → 引导用户重新编辑"的完整链路，
> 并验证 `ConfigDecryptError` 修复闭环（toast → 弹框 → 重新编辑 → 恢复）。
> 姊妹文档：`seaweedfs-server.md`（S3 网关容器）、`../e2e-tunnels.md`（反向隧道总纲）、
> `../../../docs/storage-regression-test.md`（回归总纲）

---

## 1. 问题背景

- S3/WebDAV 等存储凭据经 SM4 加密后保存在**最近文件记录**（应用沙箱）；
  SM4 密钥本身存放在 **HarmonyOS Asset Kit（关键资产）**，别名为 `sm4_key`
  （`entry/src/main/ets/common/utils/Sm4Utils.ets` 中 `ASSET_SM4_KEY_NAME`）。
- 线上症状（1.9.0 → 2.0.0 升级后部分用户）：打开 S3 最近记录时提示
  **"连接配置已过期，请重新编辑"**。根因：旧密钥资产不存在/不可访问，
  应用生成新钥后无法解密旧密文（错误码 17630001，`bad decrypt`）。

## 2. 为什么必须"临时换别名"来复现

| 手段 | 资产（Asset Kit） | 应用数据（沙箱） | 能否复现 |
|---|---|---|---|
| 卸载重装 | 删除 | 删除 | 否（数据也没了） |
| 覆盖升级 | 保留 | 保留 | 否（资产没丢） |
| **临时改密钥别名** | 查询必失败 → 生成新钥 | 保留 | **是**（无损、可还原） |

把 `ASSET_SM4_KEY_NAME` 临时改为 `sm4_key_repro`：应用查不到旧资产 → 走"生成新钥"分支；
旧密文记录仍在 → 精确模拟"数据在、密钥丢"。原 `sm4_key` 资产全程未动，改回别名即恢复。

## 3. 环境准备

1. **S3 网关**：SeaweedFS（podman，宿主 `9000`，桶 `e2e-test`），见 `seaweedfs-server.md`。
2. **反向隧道**（设备 `127.0.0.1:9000` → 宿主 `9000`）：

   ```powershell
   .\docs\e2e\e2e-tunnels.ps1 -Target <connect-key>   # 如 192.168.3.6:42755
   ```

3. **App 内 S3 配置**（复现用）：

   | 项 | 值 |
   |---|---|
   | 服务器地址 | `127.0.0.1:9000`（无 scheme 时 S3Client 默认 http） |
   | Access Key / Secret | 任意非空（网关未启用 IAM） |
   | 桶 | `e2e-test` |
   | Path Style | **开启**（自建网关不支持虚拟主机风格） |

## 4. 复现流程（三阶段）

> 全程**只允许覆盖安装**（`devecocli run --skip-build` / `hdc install -r`），
> 严禁卸载（会连带删除资产与数据）。

### 阶段 A：建立含 SM4 加密凭据的 S3 最近记录

1. 启动 App → 新建数据库 → 输入库名、主密码；
2. 存储位置选 **S3**，按 §3 配置填写 → 确认、保存；
3. 打开成功后，最近文件出现 S3 记录 —— 其凭据已用当前 `sm4_key` 加密。

### 阶段 B：模拟资产丢失（临时改别名）

1. `Sm4Utils.ets` 中 `ASSET_SM4_KEY_NAME`：`'sm4_key'` → `'sm4_key_repro'`；
2. 构建并覆盖安装，启动后观察：

   | 观察点 | 预期 |
   |---|---|
   | hilog（过滤 `sm4`） | `sm4_key not found in asset store, generating NEW key`（WARN） |
   | 点开 S3 最近记录 | toast「连接配置已过期，请重新编辑」 |
   | 引导弹框 | 提示配置无法解密，提供「重新编辑」按钮 |
   | 点「重新编辑」 | 跳转 S3Page，预填原配置明文字段（endpoint/region/bucket/URL 样式/超时），AK/SK 留空待重输 |
   | （完整闭环）重填凭据并确认 | 记录被新钥重新加密，恢复可打开 |

3. **清理注意**：若在本阶段完成了重存，记录已被 `sm4_key_repro` 加密；
   阶段 C 还原别名后需再走一次「重新编辑」，或直接删除测试记录。

#### 阶段 B 实测发现并修复的 bug（2026-10-14）

复现时 toast 正常但引导弹框不弹：`KdbxUtils.kdbxErrorPayload` 对非 KdbxError
返回 `error.message`——而 Worker 中 `$r` 同样可用，`ConfigDecryptError.message`
已是本地化文案「连接配置已过期，请重新编辑」，主线程
`ConfigDecryptError.isDecryptFailedMessage` 只识别资源名
`storage_config_decrypt_failed` → 判定失败、弹框永不出现。
修复：`kdbxErrorPayload` 对 `ConfigDecryptError` 特判映射为资源名
（`entry/src/main/ets/common/utils/KdbxUtils.ets`），主线程 `ResourceManager.getMessage`
按名本地化展示 toast、`isDecryptFailedMessage` 按名识别并弹框。
修复后实测：弹框弹出 →「重新编辑」正确跳转 S3Page。

#### 阶段 B 补充：重新编辑预填原配置（2026-10-14）

引导跳转 S3Page 时会携带文件路径（URL），页面按路径从最近记录解析原配置预填表单，
用户只需重输 AK/SK：

- 传参链路（参考 SAVE 模式，经导航参数而非方法签名层层传递）：
  调用方（`Password.ets` / `RecentFiles.ets` 引导弹框，只传 `filePath`）
  → `DataService.reEditStorageConfig(storageType, filePath?)`
  → `NavigationManager.navigateTo(pageName, { filePath })`（`ReEditParam`）
  → `S3PageBuilder(name, param)` 转发 → `S3Page.reEditParam`；
- S3Page `initReEditPrefill()`（SELECT 模式生效，SAVE 模式仍走 `initSaveParam`）：
  按 `filePath` 从 `RecentFilesService.getRecentFiles()` 匹配最近记录，
  明文字段（endpoint/region/bucket/pathStyle/timeout）直接回填；
  AK/SK 密文经 `Sm4Utils.decryptWithPrefix` 尝试解密——
  密钥正常时回填明文，密钥变更（`ConfigDecryptError`）时留空待用户重输；
- 实测（别名临时改为 `sm4_key_prefill`，Password 与 RecentFiles 两条引导路径均验证）：
  endpoint `127.0.0.1:9000`、region `us-east-1`、bucket `e2e-test`、
  路径样式选中、超时 `30000` 均正确预填，AK/SK 为空；
  还原别名后原密钥解锁恢复正常。

#### 阶段 C 实测发现并修复的 bug：预加载快照劫持重新编辑闭环（2026-10-14）

完整闭环实测（B 重存后还原别名）时发现：重新编辑→重填凭据→选中文件后解锁**仍报
「连接配置已过期」，必须重启应用才能恢复**。根因：`Password.openRecentFileOptimized`
优先命中启动时预加载的最近记录快照（`AppStorage` 的
`Constants.APP_STORAGE_PRELOAD_RECENT_FILE`，仅启动时由
`EntryAbility.preloadEssentialServices` 写入、整个会话不刷新）——
`DataService.toPasswordPage` 虽已把新配置写入最近记录（preferences），
但同会话内解锁页仍用旧快照的 `storageConfig`（旧钥密文）发起加载，必然 bad decrypt。
重启后预加载重新读取已修复的记录，故又能解锁。

修复：`DataService.toPasswordPage` 在 `addRecentFile` 成功后同步刷新
`AppStorage` 的预加载快照（与持久化记录同源），同会话内重新编辑闭环即时生效。
修复后实测：B/C 两阶段闭环（换别名重存→还原别名重存）均在**同一会话内**解锁成功，
重启后直接解锁正常。

> 注：新钥生成的 WARN（`generating NEW key`）仅在别名对应资产**不存在**时打印；
> 复现别名资产残留（上轮测试已生成）时直接走「旧钥密文 + 新钥解密失败」路径，
> 复现效果等价（`bad decrypt` + `ConfigDecryptError`），hilog 无 WARN 属预期。

### 阶段 C：还原

1. 别名改回 `'sm4_key'`；重建并覆盖安装；
2. 原 `sm4_key` 资产未动 → 旧记录恢复正常打开（若 B 阶段未重存凭据）。

## 5. 命令速查

```powershell
devecocli build                                        # 构建主 HAP
devecocli run --skip-build --device "<connect-key>"    # 覆盖安装并启动
devecocli log --device "<connect-key>" --keyword sm4   # 观察密钥日志
& "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe" `
  -t <connect-key> fport ls                            # 确认 [Reverse] 隧道
```

## 6. 注意事项

- `hdc` 服务重启/设备重连后隧道丢失，重跑 `e2e-tunnels.ps1`（幂等）。
- 隧道出现"有监听、无注册"的僵尸状态时脚本会 `killall-sub` 自动清理；
  清理无效则需重启设备（见 `../e2e-tunnels.md` §3）。
- 资产查询的**瞬时故障**（如系统繁忙）不应被当作"密钥不存在"而生成新钥——
  该语义已在 `Sm4Utils.initKey` 中保证（确认不存在才生成 + WARN 日志），
  复现与回归时不要破坏此行为。
