# KeePassHO 功能差距分析报告

> 对比对象：`../其他库` 下的三大 KeePass 参考实现
>
> - **KeePass 2.x**（原版 Windows，C#，`KeePass/`）
> - **KeePassXC**（跨平台桌面，C++/Qt，`keepassxc/`）
> - **KeePass2Android / KP2A**（Android，C#/Java，`keepass2android/`）
>
> 被分析项目：**KeePassHO**（HarmonyOS，ArkTS，本项目）
>
> 报告日期：2026-10-26 | App 版本：2.2.0

---

## 一、参考项目概览

| 项目 | 平台 | 技术栈 | 定位 |
|---|---|---|---|
| KeePass 2.x | Windows | C# (.NET) | 原版参考实现，功能最全（触发器/插件/打印等桌面特性） |
| KeePassXC | Win/macOS/Linux | C++/Qt | 跨平台标准实现，安全审计/浏览器集成/SSH Agent 最强 |
| KeePass2Android | Android | C#/Mono + Java | 移动端标杆，自动填充/键盘/云存储同步最完善 |
| **KeePassHO** | HarmonyOS | ArkTS | 本项目，KDBX 格式库基于 keeweb/kdbxweb 移植 |

---

## 二、总体结论

KeePassHO 已覆盖**约 70% 的核心能力**：

- ✅ KDBX 3/4 全版本读写（Argon2d/Argon2id/AES-KDF、AES/ChaCha20、HMAC 块流）
- ✅ 8 种存储后端（本地/WebDAV/FTP/SFTP/OneDrive/S3/华为云盘/百度网盘）
- ✅ TOTP 全家桶（RFC6238、Steam、5 种字段格式兼容、扫码配置、SHA1/256/512）
- ✅ 多数据库 + AutoOpen 子数据库（KeeAutoExec 兼容、IfDevice、KeyFile.bin 内嵌密钥）
- ✅ 条目历史版本（查看/回滚/清理）、附件（含加密磁盘缓存）、自定义图标、模板（20+ 预置 + 用户模板）
- ✅ 字段引用（`{REF}` / `{S:}`）、回收站、标签（含置顶/收藏扩展语义）
- ✅ 生物识别（指纹/人脸 ATL3）+ 快速解锁 + 自动锁定 + 剪贴板超时清除
- ✅ YubiKey NFC 挑战-应答、OtpKeyProv v1/v2（OTP 码解锁数据库）
- ✅ 保存冲突检测与合并（MERGE/OVERWRITE/RELOAD 策略）
- ✅ 会话常驻通知快捷复制（复制账号/密码）
- ✅ 导入 CSV / KeePass XML / Bitwarden JSON；导出 CSV / XML / KDBX / 密钥文件

主要差距集中在：**系统自动填充、安全键盘、密码健康/泄露检查、后台自动同步、导入格式广度、Spr 占位符引擎完整性**。

---

## 三、功能逐项对比矩阵

图例：✅ 完整实现 | 🟡 部分实现 | ❌ 未实现 | ➖ 不适用（桌面/平台特有，移动端通常裁剪）

### 3.1 数据库格式与加密

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| KDBX 3.1 读写 | ✅ | ✅ | ✅ | ✅ | `kdbx-format.ts` loadV3/saveV3 |
| KDBX 4.x 读写 | ✅ | ✅ | ✅ | ✅ | 含 inner header、HMAC 块流 |
| KDB（KeePass 1.x）读写 | ✅ | ✅ | ✅ | ❌ | **缺失**，本项目仅支持 KDBX |
| AES-256 | ✅ | ✅ | ✅ | ✅ | |
| ChaCha20 | ✅ | ✅ | ✅ | ✅ | |
| Twofish | ➖ | ✅ | ✅ | ❌ | **缺失**（老库兼容场景低频） |
| Argon2d/Argon2id | ✅ | ✅ | ✅ | ✅ | `@ohos-rs/argon2` 原生实现 |
| AES-KDF | ✅ | ✅ | ✅ | ✅ | KDBX3 keyEncryptionRounds 可调 |
| KDF 参数可视化调节 | ✅ | ✅ | ✅ | ✅ | `SettingDatabaseKeyFunction.ets` |
| KDBX3 → 4 升级 | ✅ | ✅ | ✅ | ✅ | `Kdbx.upgrade()` |
| 损坏库修复工具 | ✅ | ❌ | ❌ | ❌ | 低优先级 |
| GZip 压缩开关 | ✅ | ✅ | ✅ | ✅ | kdbxweb 内置 |

### 3.2 主密钥与解锁

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| 主密码 | ✅ | ✅ | ✅ | ✅ | |
| 密钥文件（XML v1/v2、raw、hex） | ✅ | ✅ | ✅ | ✅ | `KeyFileReader.ets` + 密钥文件生成导出 |
| 密钥文件路径记忆 | ✅ | ✅ | ✅ | ✅ | `RecentFilesService` SM4 加密记忆 |
| 指纹/人脸解锁 | ➖ | ✅ (Hello/TouchID) | ✅ (BiometricPrompt) | ✅ | `AuthService.ets` userAuth ATL3 |
| 快速解锁（部分密码片段） | ➖ | ✅ | ✅ | ✅ | `UnLockDatabase.ets`，片段长度可配置 |
| YubiKey 挑战-应答 | ✅ | ✅ | ✅ (NFC) | ✅ | NFC HMAC-SHA1，槽位 1/2（KeePassXC 风格） |
| OtpKeyProv（OTP 码解锁） | ✅ (插件) | ❌ | ✅ (插件) | ✅ | v1/v2 `.otp.xml` 辅助文件 |
| 硬件密钥 USB（YubiKey/OnlyKey） | ➖ | ✅ | 🟡 (NFC) | 🟡 | HarmonyOS 无 USB HID 场景，NFC 已覆盖 |
| 主密码质量下限 | ✅ | ✅ | ❌ | ❌ | **缺失** |
| 主密钥更换周期策略（Rec/ForceDays） | ✅ | ❌ | ❌ | ❌ | **缺失**（元数据字段读写无 UI） |

### 3.3 条目与组管理

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| 条目 CRUD / 移动 / 批量操作 | ✅ | ✅ | ✅ | ✅ | 批量选择/移动/删除、拖拽 |
| 回收站 | ✅ | ✅ | ✅ | ✅ | 开关 + 永久删除二次确认 |
| 条目历史（快照/回滚/删除） | ✅ | ✅ | ✅ | ✅ | 含历史条数/大小上限、按天清理 |
| 附件 | ✅ | ✅ | ✅ | ✅ | 图片预览、加密磁盘缓存（Asset Kit） |
| 自定义图标 | ✅ | ✅ | ✅ | ✅ | 增删、URL 下载、品牌图标库 |
| 标签 | ✅ | ✅ | ✅ | ✅ | 扩展置顶/收藏语义（PINNED/FAVORITE_TAG） |
| 模板 | ✅ | ✅ | ✅ | ✅ | 20+ 预置 + 用户模板（条目转模板） |
| 条目颜色（前景/背景） | ✅ | ✅ | ❌ | ❌ | **缺失**（有 ColorPickerDialog 组件但条目模型未接入） |
| TAN 条目（用后自动过期） | ✅ | ❌ | ✅ | ❌ | **缺失** |
| 多值批量编辑 | ✅ | ❌ | ❌ | ❌ | **缺失** |
| 条目克隆（含选项） | 🟡 (复制) | ✅ (7 种选项) | ✅ | 🟡 | 仅复制，无"含历史/引用原条目"等选项 |
| PreviousParentGroup（回收站恢复原位置） | ✅ (4.1) | ✅ | ❌ | ❌ | **缺失**（KDBX 4.1 特性） |
| 富文本备注 | ✅ | ❌ | ❌ | ❌ | 低优先级 |

### 3.4 搜索与报告

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| 全字段搜索 | ✅ | ✅ | ✅ | ✅ | 标准+自定义字段+标签、拼音+字母索引 |
| 搜索历史 | ✅ | ✅ | ✅ | ✅ | `RecentFilesService` |
| 高级搜索（字段限定/排除/正则/状态过滤） | ✅ (XPath) | ✅ | ❌ | ❌ | **缺失**：无 `is:expired`、`is:weak`、按标签/字段过滤 UI |
| 密码健康检查（熵评分/复用检测） | ✅ | ✅ | ❌ | ❌ | **缺失** |
| HIBP 泄露检查（离线 Pwned Passwords） | ❌ | ✅ | ❌ | ❌ | **缺失** |
| 相似/重复密码报告 | ✅ (Levenshtein) | ✅ | ❌ | ❌ | **缺失** |
| 数据库统计报告 | ❌ | ✅ | ❌ | ❌ | **缺失** |
| 过期条目报告 | ✅ | ✅ | ✅ | 🟡 | 仅有过期图标/删除线展示与搜索排除 |

### 3.5 TOTP / OTP

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| TOTP（SHA1/256/512、自定义位数步长） | ✅ | ✅ | ✅ | ✅ | `TotpService.ets` |
| Steam Guard | ❌ | ✅ | ✅ | ✅ | |
| 多字段格式兼容 | 🟡 | ✅ (3 种) | ✅ (5 种) | ✅ | otpauth/KeePass2 TimeOtp-*/KeeOTP/KeeTrayTOTP |
| 扫码配置 | ❌ | ❌ | ✅ | ✅ | ScanKit |
| TOTP 独立列表页 | ❌ | ❌ | ✅ | ✅ | `TotpView.ets` + 列表/条目预览开关 |
| TOTP 二维码导出 | ❌ | ✅ | ✅ (插件) | ❌ | **缺失** |
| 服务器时间校正 | ❌ | ❌ | ✅ | ❌ | **缺失**（低优先级） |
| otpauth:// 深链/分享接收建条目 | ❌ | ❌ | ✅ | ❌ | **缺失**（仅扫码，无深链 Intent） |

### 3.6 自动填充与输入（移动端核心差距）

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| 系统自动填充服务 | ➖ | ➖ | ✅ (AutofillService) | ❌ | **最大差距**：无 HarmonyOS AutoFillExtensionAbility，当前主动 `enableAutoFill(false)` |
| 表单解析/域名匹配/应用凭据匹配 | ➖ | ➖ | ✅ | ❌ | 随自动填充缺失 |
| 保存新凭据回填 | ➖ | ✅ (浏览器) | ✅ | ❌ | 随自动填充缺失 |
| 安全键盘/输入法（打字注入绕过剪贴板） | ➖ | ➖ | ✅ (MagiKeyboard) | ❌ | **缺失**：无 InputMethodExtensionAbility |
| 键盘内联建议 | ➖ | ➖ | ✅ | ❌ | 随输入法缺失 |
| 通知快捷复制（近似替代） | ➖ | ➖ | ✅ | ✅ | 会话常驻通知"复制账号/密码"，可后台静默复制 |

### 3.7 浏览器集成 / 桌面集成

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| 浏览器扩展协议（Native Messaging） | ➖ | ✅ | ❌ | ❌ | HarmonyOS 无对应生态，➖ 化处理 |
| Passkeys（FIDO2 通行密钥） | ➖ | ✅ | ❌ | ❌ | 可关注 HarmonyOS 系统通行密钥 API 演进 |
| SSH Agent 集成 | ➖ | ✅ | ❌ | ❌ | 移动端低优先级 |
| Auto-Type（自动键入/全局热键） | ✅ | ✅ | ❌ | ❌ | 桌面特性，移动端不适用 |
| KeeShare（签名共享容器） | ❌ | ✅ | ❌ | ❌ | **缺失** |
| FreeDesktop Secret Service | ➖ | ✅ | ➖ | ➖ | Linux 特有 |
| 系统全局搜索集成 | ➖ | ➖ | ✅ (SearchProvider) | ❌ | HarmonyOS 有全局搜索接入点，可探索 |

### 3.8 存储与同步

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| 本地文件 | ✅ | ✅ | ✅ | ✅ | |
| WebDAV | ✅ | ➖ | ✅ | ✅ | ETag/Last-Modified 版本快速路径 |
| FTP/FTPS | ✅ | ➖ | ✅ | ✅ | basic-ftp + sftp-ohos 原生 |
| SFTP/SSH | ➖ (插件) | ➖ | ✅ | ✅ | |
| S3 兼容 | ❌ | ❌ | ❌ | ✅ | **本项目独有优势**（SigV4、分片上传） |
| OneDrive | ➖ | ➖ | ✅ | ✅ | OAuth2 |
| 华为云盘 / 百度网盘 | ❌ | ❌ | ❌ | ✅ | **本项目独有优势** |
| pCloud | ❌ | ❌ | ✅ | 🟡 | 代码已实现，`FileStorageFactory.ets:29` 注册被注释未启用 |
| Dropbox / Google Drive / Mega / SMB | ➖ | ➖ | ✅ | ❌ | HarmonyOS 生态缺失 GMS，Dropbox/Mega/SMB 可考虑 |
| 离线缓存打开（远端不可用回退本地） | ➖ | ➖ | ✅ (CachingFileStorage) | 🟡 | 有 CacheStorage 装饰器，无"离线打开+联网后合并"闭环 |
| 保存冲突检测与合并 | ✅ | ✅ | ✅ | ✅ | MERGE/OVERWRITE/RELOAD 弹框 |
| 后台自动同步（定时） | ➖ | ➖ | ✅ (前台服务+SSID 白名单) | ❌ | **缺失** |
| 三方合并同步策略细化 | ✅ | ✅ | ✅ (AlwaysMergeOnConflict) | 🟡 | 有基本合并，无策略选项 |
| 远程同步命令自定义 | ➖ | ✅ (rsync/ssh) | ➖ | ❌ | 桌面特性，低优先级 |

### 3.9 导入 / 导出

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| CSV 导入（列映射向导） | ✅ | ✅ | ✅ | 🟡 | 有导入，无列映射向导 |
| KeePass XML 导入 | ✅ | ✅ | ✅ | ✅ | |
| Bitwarden JSON 导入 | ✅ | ✅ | ❌ | ✅ | |
| 1Password（OPUX/OpVault） | ✅ | ✅ | ❌ | ❌ | **缺失** |
| LastPass CSV | ✅ | ✅ | ❌ | ❌ | **缺失** |
| Chrome/Firefox/Edge CSV | ✅ | ✅ | ❌ | ❌ | **缺失**（通用 CSV 可勉强覆盖，但缺浏览器专属字段映射） |
| Dashlane / Enpass / Keeper / Proton Pass 等 | ✅ (90+ 格式) | ✅ (Proton) | ❌ | ❌ | **缺失** |
| KeePass 1.x 导入 | ✅ | ✅ | ✅ | ❌ | 随 KDB 支持缺失 |
| CSV 导出 | ✅ | ✅ | ✅ | ✅ | |
| XML 导出 | ✅ | ✅ | ✅ | ✅ | |
| HTML 导出 | ✅ | ✅ | ❌ | ❌ | **缺失**（应急查阅场景） |
| KDBX 副本导出 | ✅ | ✅ | ✅ | ✅ | |

### 3.10 安全策略

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| 自动锁定（后台超时） | ✅ | ✅ | ✅ | ✅ | `EntryAbility` + `LockScreenService` 锁屏子窗口 |
| 锁库即清剪贴板 | ✅ | ✅ | ✅ | ✅ | |
| 剪贴板超时自动清除 | ✅ | ✅ | ✅ | ✅ | 可配时长、后台冻结补偿、禁止跨设备粘贴 |
| 隐私窗口（防截屏） | ✅ | ✅ | ✅ (FLAG_SECURE) | ✅ | PRIVACY_WINDOW 权限 + 设置开关 |
| 密码/TOTP 掩码显示 | ✅ | ✅ | ✅ | ✅ | |
| 应用锁（独立于数据库锁） | ➖ | ➖ | ✅ | 🟡 | 锁屏页承担，无独立应用锁口令 |
| 防截屏豁免清单 | ❌ | ❌ | ❌ | ❌ | 三端均无 |

### 3.11 平台特性与扩展

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| 多数据库同时打开 | ✅ (标签页) | ✅ (标签页) | ✅ | ✅ | `DatabaseRegistry` + 切换面板 |
| 子数据库 AutoOpen/KeeAutoExec | ✅ | ✅ | ✅ | ✅ | 含 IfDevice、内嵌密钥，**实现深度超 KP2A** |
| 桌面卡片/小部件 | ➖ | ➖ | ✅ (Widget) | ❌ | **缺失**：无 FormExtensionAbility（TOTP 卡片/快捷复制卡片是机会点） |
| 插件体系 | ✅ (PLGX) | ❌ | ✅ (SDK) | ❌ | HarmonyOS 生态暂无对应机制 |
| 触发器（事件-条件-动作） | ✅ | ❌ | ❌ | ❌ | 桌面特性，低优先级 |
| CLI | ✅ (KPScript) | ✅ (35+ 命令) | ❌ | ❌ | 移动端不适用 |
| 打印/应急表 | ✅ | ❌ | ❌ | ❌ | 可用 HTML 导出替代，低优先级 |
| 跨设备设置同步 | ❌ | ❌ | ❌ | ✅ | **本项目独有**（分布式 KV + 版本冲突解决） |
| 系统备份恢复 | ➖ | ➖ | ✅ (隐式) | ✅ | BackupExtensionAbility |
| 崩溃日志收集分享 | ❌ | ❌ | ✅ | ✅ | EL1 目录 `CrashLogService` |
| .kdbx 文件关联/深链打开 | ✅ | ✅ | ✅ | ✅ | file scheme + `keepassho://aimilin.com` |

### 3.12 Spr 占位符 / 字段引用引擎

| 功能 | KeePass | KeePassXC | KP2A | KeePassHO | 说明 |
|---|---|---|---|---|---|
| `{REF:x@y:z}` 字段引用 | ✅ | ✅ | ✅ | ✅ | `kdbx-field-reference.ts` |
| `{S:Field}` 自定义字段占位 | ✅ | ✅ | ✅ | ✅ | |
| 基础占位（TITLE/USERNAME/PASSWORD/URL/NOTES） | ✅ | ✅ | ✅ | 🟡 | 展示/复制场景解析，无 URL 执行场景 |
| `{PICKCHARS}` 选字符填充 | ✅ | ✅ | ✅ | ❌ | **缺失** |
| `{URL:RMVSCM/HOST/PORT/...}` URL 分解 | ✅ | ✅ | ❌ | ❌ | **缺失** |
| `{T-CONV}` `{T-REPLACE-RX}` 文本变换 | ✅ | ✅ | ❌ | ❌ | **缺失** |
| `{GROUP}` `{GROUP_PATH}` 组路径 | ✅ | ✅ | ❌ | ❌ | **缺失** |
| `{DT_*}` 日期时间 | ✅ | ✅ | ❌ | ❌ | **缺失** |
| `{NEWPASSWORD}` 生成新密码 | ✅ | ✅ | ❌ | ❌ | **缺失** |
| `{TIMEOTP}` `{HMACOTP}` 占位 | ✅ | ✅ | 🟡 | ❌ | TOTP 经独立服务覆盖，占位符形式缺失 |

---

## 四、缺失功能汇总清单

### 完全缺失（KeePassHO 未实现）

1. **系统自动填充**（AutoFillExtensionAbility）— KP2A/KeePassXC 核心能力
2. **安全键盘/输入法**（InputMethodExtensionAbility）— KP2A MagiKeyboard
3. **密码健康检查**（熵评分、弱/复用密码检测）— KeePassXC/KeePass
4. **HIBP 泄露检查** — KeePassXC
5. **数据库统计报告** — KeePassXC
6. **后台自动同步**（定时任务） — KP2A
7. **离线缓存打开闭环**（断网可用 + 联网合并） — KP2A
8. **KDB（KeePass 1.x）格式支持** — 三端均有
9. **Twofish 加密算法** — KeePassXC/KP2A
10. **1Password / LastPass / Chrome 等导入格式** — KeePass/KeePassXC
11. **HTML 导出**（应急查阅） — KeePass/KeePassXC
12. **TOTP 二维码导出** — KeePassXC/KP2A
13. **otpauth:// 深链/分享接收** — KP2A
14. **高级搜索**（字段限定、状态过滤、正则） — KeePass/KeePassXC
15. **条目到期提醒通知**（解锁后提示即将过期） — KeePassXC
16. **桌面卡片**（TOTP 卡片/快捷复制卡片） — KP2A Widget 对应
17. **TAN 条目**（一次性密码，用后自动过期） — KeePass/KP2A
18. **条目颜色（前景/背景）** — KeePass/KeePassXC
19. **多值批量编辑** — KeePass
20. **`{PICKCHARS}`、URL 分解、文本变换、组路径、日期时间等 Spr 占位符** — KeePass/KeePassXC
21. **主密码质量下限 / 更换周期策略** — KeePass/KeePassXC
22. **PreviousParentGroup（KDBX 4.1 回收站恢复原位置）** — KeePass/KeePassXC
23. **KeeShare 共享容器** — KeePassXC
24. **自动保存**（修改后自动保存 + 延迟配置） — KeePassXC

### 部分实现（可增强）

1. **pCloud 存储**：代码完成，工厂注册被注释（`FileStorageFactory.ets:29`）— 启用即可
2. **合并同步策略**：有 MERGE，无 AlwaysMergeOnConflict 策略选项
3. **CSV 导入**：能导，无列映射向导
4. **条目克隆**：仅复制，无"含历史/引用原条目"等选项
5. **过期管理**：有展示，无提醒
6. **Dropbox / Mega / SMB**：HarmonyOS 生态可补充的云存储

---

## 五、开发优先级规划

评估维度：**用户价值**（迁移/日常使用刚需）× **实现成本**（HarmonyOS API 可用性、工作量）× **风险**。

### P0 — 高价值、强需求（建议近期启动）

| 优先级 | 功能 | 理由 | 预估成本 | 实现要点 |
|---|---|---|---|---|
| P0-1 | **系统自动填充**（AutoFillExtensionAbility） | 移动端密码管理器的核心卖点；KP2A/系统密码管理器均以此为主入口；HarmonyOS 已开放自动填充扩展能力 | 高（3-5 人月） | 申请自动填充扩展权限；实现填充数据提供（按应用包名/域名匹配条目，复用 `KdbxUtils` 搜索 + URL 匹配）；保存新凭据回填；设置页开关与排除清单 |
| P0-2 | **密码健康检查**（本地版） | 纯本地计算零风险、实现成本低（熵评估 + 复用检测无需联网）；KeePassXC Health Check 已验证价值 | 低（2-3 人周） | 新增报告页：zxcvbn 式熵评分（五级）、复用密码分组、短密码列表；`excludeFromReports` 排除支持 |
| P0-3 | **更多导入格式**（1Password / LastPass / Chrome / Edge / Firefox CSV） | 用户迁移第一道门槛，直接决定新用户转化；均为本地文件解析，风险低 | 低-中（每种 2-5 人天） | 扩展 `importExport` 注册表：新增 `ChromeCsvImportHandler`（浏览器 CSV 格式相对固定）、`OnePasswordImportHandler`（1PUX/CSV）、`LastPassCsvImportHandler`；考虑通用 CSV 列映射向导 |
| P0-4 | **条目到期提醒** | 安全合规刚需（密码轮换）；已有 `DateUtils.isExpired` 基础 | 低（1-2 人周） | 解锁后检查 N 天内将过期条目，弹提示条/通知；设置项：提醒提前天数 |

### P1 — 补齐核心体验（P0 之后）

| 优先级 | 功能 | 理由 | 预估成本 | 实现要点 |
|---|---|---|---|---|
| P1-1 | **后台自动同步** | 云端多端使用场景下，手动下拉刷新体验割裂；KP2A 已验证移动端可行性 | 中（3-4 人周） | 后台任务（`@ohos.backgroundTaskManager`）周期拉取远端版本探测（已有 ETag 快速路径）→ 变更静默合并 → 通知；设置项：频率、仅 Wi-Fi |
| P1-2 | **离线缓存打开闭环** | 出差/弱网场景刚需；`CacheStorage` 已有 80% 基础 | 中（2-3 人周） | 打开时远端失败 → 回退本地缓存 → 标记离线会话；保存时远端失败 → 暂存本地 + 联网后合并上传 |
| P1-3 | **HIBP 泄露检查** | 在 P0-2 健康检查页之上叠加；可用 k-anonymity 在线 API 或离线库 | 中（2-4 人周） | 优先 k-anonymity SHA1 前缀查询（不泄露密码）；设置项：仅 Wi-Fi / 手动触发 |
| P1-4 | **安全键盘/输入法**（评估后决策） | MagiKeyboard 是 KP2A 差异化能力；但 HarmonyOS 输入法扩展开发成本高，且 P0-1 自动填充落地后价值下降 | 高（需先做技术预研） | InputMethodExtensionAbility 可行性预研 → 键盘内条目字段注入；若预研不通过则降级为 P3 |
| P1-5 | **TOTP 二维码导出 + otpauth 深链** | 小而美的生态补全；扫码导入已有，逆向导出成本低 | 低（1 人周） | 条目 TOTP 弹窗增加二维码展示（复用已有二维码能力）；module.json5 注册 otpauth scheme/分享接收 |
| P1-6 | **高级搜索** | 数据量大的用户刚需；搜索基础已扎实 | 中（2-3 人周） | 搜索语法：`tag:x`、`user:x`、`is:expired`、`-排除词`、`"短语"`；搜索页高级过滤面板 |

### P2 — 完善与差异化（中期）

| 优先级 | 功能 | 理由 | 预估成本 |
|---|---|---|---|
| P2-1 | **桌面卡片**（TOTP 卡片 / 快捷复制卡片） | HarmonyOS 特色入口，差异化卖点；KP2A Widget 对应 | 中（2-3 人周） |
| P2-2 | **Spr 占位符引擎补全**（`{PICKCHARS}`、`{URL:*}`、`{GROUP_PATH}`、`{DT_*}`、`{T-CONV}`） | 与桌面版数据互操作完整性；`kdbx-field-reference.ts` 已有扩展点 | 中（3-4 人周） |
| P2-3 | **自动保存 + 保存策略选项** | 减少用户丢数据心智负担；保存管线已成熟 | 低-中（1-2 人周） |
| P2-4 | **条目颜色 + PreviousParentGroup + TAN** | 数据模型补全，KDBX 4.1 兼容性 | 中（2-3 人周） |
| P2-5 | **数据库统计报告** | 健康检查页的自然扩展 | 低（1 人周） |
| P2-6 | **启用 pCloud + 补充 Dropbox/Mega/SMB** | pCloud 仅需放开工厂注册（半天）；其余按用户反馈排期 | pCloud 极低 / 其余中 |
| P2-7 | **通用 CSV 列映射向导** | 覆盖长尾导入格式（Enpass/Keeper 等） | 中（2-3 人周） |

### P3 — 长尾 / 低收益（按需评估）

| 优先级 | 功能 | 说明 |
|---|---|---|
| P3-1 | KDB（KeePass 1.x）支持 | 存量 1.x 用户极少；如需实现可参考 `KP2AKdbLibrary` 移植，成本高（1-2 人月） |
| P3-2 | Twofish 算法 | 极老库兼容，kdbxweb 上游也仅插件形态；cryptoFramework 无原生支持需自实现 |
| P3-3 | HTML 导出 | 应急查阅场景，可用"导出 XML + 说明文档"临时替代 |
| P3-4 | KeeShare | KeePassXC 签名共享在移动端使用率低；AutoOpen 子库已覆盖主要共享场景 |
| P3-5 | SSH Agent / Passkeys / 浏览器扩展协议 | 桌面/生态特性；持续关注 HarmonyOS 系统通行密钥 API，条件成熟时升级优先级 |
| P3-6 | 主密码更换周期策略 / 多值批量编辑 / 触发器 / 插件体系 | 桌面管理特性，移动端收益低 |
| P3-7 | 损坏库修复工具 / 服务器时间校正 / 富文本备注 | 极低频场景 |

### 快速见效清单（≤1 人周，可穿插排期）

1. 启用 pCloud（放开 `FileStorageFactory.ets:29` 注册注释 + 回归测试）
2. 条目到期提醒（P0-4）
3. TOTP 二维码导出 + otpauth 深链（P1-5）
4. 密码健康检查 MVP（熵评分 + 复用检测，P0-2 首期）
5. Chrome/Edge/Firefox CSV 导入（P0-3 首批，格式固定最简单）

---

## 六、实施建议

1. **自动填充先行**：P0-1 是唯一改变产品定位的功能，建议立项后先做 1-2 周技术预研（HarmonyOS 自动填充扩展的权限申请、应用识别能力、与锁库状态的联动），预研结论决定排期是否调整。
2. **健康检查与导入格式并行**：二者互不依赖、风险低，可由不同开发者并行推进。
3. **每期都保持与桌面版互操作回归**：Spr 占位符、KDBX 4.1 字段（PreviousParentGroup）等数据模型变更，需用 KeePassXC 桌面版做双向打开验证（本项目 `docs/e2e` 已有 E2E 基础设施可扩展）。
4. **差异化保持**：S3/华为云盘/百度网盘、AutoOpen 子库深度、跨设备分布式同步是本项目相对 KP2A 的独有优势，新功能开发时不应造成回归。
