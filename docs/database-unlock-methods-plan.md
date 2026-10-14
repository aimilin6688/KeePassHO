# 数据库解锁方式扩展开发计划

> 目标：参考 KeePass2Android / KeePassXC / KeePass 的实现，在现有「密码、密钥文件、密码+密钥文件」
> 三种解锁方式基础上，新增 **OTP 一次性密码**（含恢复模式）与 **YubiKey 挑战-应答**
> （KeePassXC 兼容，含密钥文件组合）等数据库解锁方式。
> 参考源码位置：`/Users/liujunguang1/workspace/code/other/harmony/KeePassHO/其他库/`
> （keepass2android、KeePass-2.61.1-Source、keepassxc）

---

## 0. 实施进度

> 按阶段滚动更新：实现 → 构建 → 真机单测通过 → 提交后标记。

| 阶段 | 状态 | 提交/说明 |
|---|---|---|
| M1 基础设施（kdbxweb customKey / AuthType 判定 / 凭证分派 / Worker 链路透传） | 已完成 | `dc93068d`、`515cc83e`；凭证构建策略化重构 `cb0f2678`；真机单测 5/5 + 22/22 通过 |
| M2-1 OTP 核心服务（HmacOtp / EncodingUtil / OtpUtil / OtpInfo / OtpKeyProvService + 单测） | 已完成 | services/otpkey/ 5 文件落地；真机单测 31/31 通过（HmacOtp 6：RFC 4226 官方向量 / EncodingUtil 8：RFC 4648 Base32 向量 / OtpUtil 6：v1/v2 夹具 / OtpInfo 5：双格式解析+往返 / OtpKeyProvService 6：前瞻窗口+恢复模式）；凭证回归 5/5 + 22/22 |
| M2-2 OTP 解锁 UI（Password.ets OTP 输入区 / 恢复模式区 / Counter 写回） | 已完成 | `getAllTypes` 启用 `password_otp` / `password_otp_recovery`；OTP 输入区（OtpsRequired 个码，辅助文件自动定位失败引导手动选择）+ 恢复模式区（secret + 五种编码格式）；解锁成功后 Counter 写回（重加密，失败仅告警）；生物识别仅代填密码分量；新增 `OtpAuxFileService`（定位/读写/写回）真机单测 4/4，otpkey 全量 31/31 + 凭证 22/22 + AuthType 相关回归 39/39 |
| M3-1 YubiKey 挑战-应答（XC 兼容）— KDBX 头预解析 | 已完成 | 新增 `services/kdbx/KdbxHeaderReader.ets`（签名/版本校验、KDBX3 拒绝、外层字段 11 VarDictionary 解析、提取 KDF seed 'S' 与 '$UUID'）；真机单测 9/9（合成头向量 / 两阶段挑战-应答 E2E：预解析 seed → 模拟 HMAC-SHA1 → challengeResponseHex 语义重开成功、错误应答拒开 / KDBX3、版本、签名、截断、缺字段、缺 seed、坏字典异常路径），凭证与加载回归 38/38 |
| M3 YubiKey 挑战-应答（XC 兼容）— NFC 服务与 UI | 已完成（代码与单测） | `YubiKeyNfcService`（tag.on readerMode 前台读卡 + IsoDepTag 两步 APDU：Select AID `A000000527200101` → HMAC 挑战 0x30/0x38 挑战补零 64 字节 → 20 字节应答 + SW 9000；7 类错误码状态机，会话内可重贴重试）；`NFC_TAG` 权限声明；`NfcChallengeDialog` 贴卡弹层（等待/读取/错误态，取消/重试，生命周期驱动会话）；Password.ets 槽位选择（默认槽位 2）+ 两阶段触发（阶段一头预解析提取挑战 → 弹层 → challengeResponseHex 加载）+ KDBX3/坏头/读失败分类提示；`RecentFile.yubikeySlot` 槽位记忆；`getAllTypes` 启用两个 XC 类型；APDU 纯函数真机单测 11/11，6 套件回归 58/58；待验证：YubiKey 5 NFC 实体钥互操作 |
| M4 快速解锁与收尾 | 已完成 | 快速解锁语义确认：应用内锁屏（UnLockDatabase）库保持内存解密态，生物识别/快速密码仅恢复界面，OTP/XC 无需重派生密钥，无需改动；Password.ets 生物识别对 XC 挑战-应答库改为仅代填密码分量（不自动弹 NFC 层，由用户按解锁键触发，与 OTP 行为一致）；`RecentFile.otpAuxLocation` OTP 辅助文件位置记忆（手动选择/自动定位结果持久化，重开免重新定位）；设置页验证无需改动（不枚举数据库认证方式）；新增用户使用说明 `docs/unlock-methods-guide.md`；6 套件回归 58/58 |
| 缺口复查修复（M4 后全链路复查） | 已完成 | ① OTP 库无法保存：`setFileParam` 的 DbFileParam/credentialsParam 从未携带 `otpSecretHex` → 保存时策略抛 `error_otp_secret_missing`；修复：Password.ets 解锁时暂存 `otpSecretHex`/`challengeResponseHex`（页面状态，切换认证方式即清理），`setFileParam` 双路透传（successMessageToKdbx 还原 + FileService.setDbFileParam），保存/重载/下拉刷新链路打通。② 大库（>4MB）Worker 容器路径：主线程 `successMessageToKdbx` 重建凭证缺 secret 而失败（"Database open failed"）；XC 模型路径 `fixedResponse` 函数随 Kdbx 实例 postMessage 触发结构化克隆 DataCloneError；修复：容器路径由 ① 提供 secret；DatabaseLoad 模型路径 XC 传输前 `setChallengeResponse(undefined)` 剥离挑战回调（`kdbxweb` setter 改 public）。③ XC 保存语义缺失：kdbxweb `save()` 必重新生成 KDF seed，解锁应答仅对当前 seed 有效，直接保存将产生无法回开的文件；修复：`KdbxSaveService.saveDatabase` 入口拦截（`error_challenge_response_save_unsupported`，覆盖手动/自动/合并全路径；RELOAD 不拦截——seed 未变应答仍有效，`byDbFileParam` 透传 challengeResponseHex 支持重载/下拉刷新）；两阶段「保存前重贴卡」列入 P2 backlog。新增 E2E 回归 `UnlockSecretsSaveReload`（OTP Worker 容器解锁→保存→重开、缺 secret 负例、XC 挑战剥离、XC 缺应答负例、XC 保存拦截文件零变更）；待验证：KeePass 桌面 OtpKeyProv / KeePassXC+YubiKey 实体钥互操作、反向保存后回开 |
| M5 KeeChallenge 旧版（可选 P2） | 待开始 | — |

---

## 1. 现状分析

### 1.1 KeePassHO 当前实现

| 模块 | 位置 | 现状 |
|---|---|---|
| 认证类型定义 | `entry/src/main/ets/services/TypeDefined.ets:167` | `AuthType` 已定义 9 种 `AuthTypeInfo`，`getAllTypes()` 仅启用 3 种：`PASSWORD` / `KEYFILE` / `PASSWORD_KEYFILE`；其余 6 种（OTP、挑战-应答系列）已预定义但被注释（`TypeDefined.ets:240-245`），资源串已存在 |
| 凭证构建 | `entry/src/main/ets/services/CredentialsService.ets` | 仅处理「密码 / 密钥文件」两分支，未处理 OTP / 挑战-应答 |
| 解锁页 | `entry/src/main/ets/pages/Password.ets` | `Select` 下拉选择认证方式 + 密码输入 + 密钥文件选择器；`verifyAndOpenDatabase()` 组装 `LoadDatabase` 后交由 `KdbxLoadService.loadDatabase()` 加载 |
| Worker 加载 | `entry/src/main/ets/workers/DatabaseLoad.ets:38` | 在 Worker 线程内调用 `CredentialsService.createKdbxCredentials(request)` 构建 `KdbxCredentials` 后加载 KDBX |
| 快速解锁 | `entry/src/main/ets/pages/UnLockDatabase.ets` | 快速密码 + 指纹/人脸（`AuthService`），密码以 SM4 加密存于最近文件记录（`RecentFile.password`） |
| kdbxweb 库 | `libs/kdbxweb/src/main/ets/format/kdbx-credentials.ts` | `KdbxCredentials` **已支持** `challengeResponse` 回调（第 18/143/172 行）与 `keyFileHash`；**不支持**自定义密钥（OTP secret 之类的第 4 种密钥分量） |

### 1.2 参考项目研究结论

**KeePass2Android**（`其他库/keepass2android/src/keepass2android-app/PasswordActivity.cs:78`）的解锁方式枚举：

```csharp
enum KeyProviders {
  KeyFile = 1,       // 密钥文件
  Otp = 2,           // OTP 一次性密码（OtpKeyProv, OATH HOTP RFC 4226）
  OtpRecovery = 3,   // OTP 恢复模式（直接输入 OTP secret）
  Challenge = 4,     // KeeChallenge（旧版 YubiKey 挑战-应答，依赖 .ChallengeInfo 辅助文件）
  ChalRecovery = 5,  // KeeChallenge 恢复模式
  ChallengeXC = 6,   // KeePassXC 兼容挑战-应答（KDBX4+，challenge = KDF seed）
}
```

各方式与密码可自由组合为复合密钥（CompositeKey）。

**OTP（OtpKeyProv）机制**（`addons/OtpKeyProv/`，作者 Dominik Reichl，KeePass 官方插件）：

- 辅助文件：与数据库同目录的 `<数据库名>.otp.xml`（`OathHotpKeyProv.AuxFileExt = ".otp.xml"`），内容为 `OtpInfo` XML；
- `OtpInfo` 关键字段：`OtpLength`（单码长度，默认 8）、`OtpsRequired`（所需码数，默认 4）、`LookAheadCount`（前瞻数）、`Counter`（HOTP 计数器）、`EncryptedSecrets[]`（v2.0+，按前瞻分组的加密密文；每项含 `CipherText`/`IV`/`TransformationKey`/`TransformationRounds`/`PlainTextHash`/`PlainTextHashTransformationKey`/`PlainTextHashTransformationRounds`）；
- 解锁流程（`OtpUtil.cs`）：
  1. 用户按 HOTP 令牌（硬件器/App）输入 `OtpsRequired` 个连续 OTP 码；
  2. `KeyFromOtps`：把码用 `:` 连接 → UTF-8 → SHA-256 → AES-KDF（`TransformationKey`/`TransformationRounds`）变换 → 再 SHA-256，得到 32 字节派生密钥；
  3. `DecryptData`：`CipherText` 以 `s20://` 前缀 + Base64 存储，用 Salsa20（IV 取 `IV` 前 8 字节）解密出 secret；
  4. `HashAndTransform(secret, PlainTextHashTransformationKey, rounds)` 与 `PlainTextHash` 比对校验；
  5. secret（`OtpInfo.Secret`）作为 `KcpCustomKey(OathHotpKeyProv.Name, secret, true)` 并入复合密钥；
  6. 成功后把 `Counter += OtpsRequired(+i)` 写回辅助文件（`SaveOtpAuxFileAndLoadDb`）。
- 恢复模式（`EncodingUtil.ParseKey`）：令牌丢失时直接输入 secret，支持 `Hex/Base64/Base32/Utf8/Dec` 五种编码。

**挑战-应答（KeePassXC 兼容）机制**（`ChallengeXCKey.cs`、KeePassXC `src/keys/ChallengeResponseKey.h`）：

- 仅支持 **KDBX 4**（`GetMinKdbxVersion() = FileVersion32_4`）；
- challenge 取自数据库头的 **KDF seed**（kdbxweb 中即 `getHash(kdfSalt)`，见 `libs/kdbxweb/src/main/ets/format/kdbx-format.ts:1113`）；challenge 不足 64 字节时按 `0x40-len` 填充（`ChallengeXCKey.cs:40-52`）；
- YubiKey HMAC-SHA1 槽位（slot 1/2）计算 20 字节应答；应答再被 SHA-256 后并入复合密钥（kdbxweb `getChallengeResponse` 已实现该 SHA-256）；
- KeePass2Android 通过外部 App（ykDroid，`LockingActivity.cs:149`，Intent `net.pp3345.ykdroid.intent.action.CHALLENGE_RESPONSE`）完成与 YubiKey 的 USB/NFC 通信。

**KeeChallenge 旧版机制**（`KeeChallenge.cs` + `ChallengeInfo.cs`，P2 优先级）：

- 辅助文件 `.ChallengeInfo.xml`（`encrypted`/`iv`/`challenge`/`verification`/`lt64` 字段）；
- 64 字节 challenge（`LT64` 时 63 字节），HMAC-SHA1 应答 20 字节；secret 以 AES 加密存辅助文件，每次成功解锁需重新生成 challenge 写回，防重放。

**KeePass 复合密钥合成顺序**（`KeePassLib/Keys/CompositeKey.cs:87`）：按 `AddUserKey` 顺序拼接——KeePass2Android 实际顺序为 密码 → 密钥文件 → OTP secret / 挑战应答。kdbxweb `getHash` 当前顺序为 passwordHash → keyFileHash → challengeResponse，与之兼容；新增自定义密钥分量应插在 keyFileHash 之后、challengeResponse 之前。

### 1.3 HarmonyOS 能力基础

- **NFC**：`@kit.ConnectivityKit` 的 `@ohos.nfcTag` 支持 `IsoDepTag`（ISO 14443-4），可发 APDU；
  需在 `module.json5` 声明 `ohos.permission.NFC_TAG`（system_grant，无需运行时弹窗）；
  YubiKey 5 NFC 的 OTP 应用 AID 为 `A000000527200101`，HMAC 槽位指令：slot1=`0x30`、slot2=`0x38`（与 ykDroid 实现一致）；
- **本机无 ykDroid 类外部 App**，需在应用内原生实现 NFC APDU 读写（`entry/src/main/ets/services/yubikey/`）。

---

## 2. 待新增解锁方式总览

| # | 解锁方式 | AuthType.type | 优先级 | 依赖硬件 | 说明 |
|---|---|---|---|---|---|
| 1 | 密码 + OTP | `password_otp` | **P0** | 无（HOTP 令牌 App/硬件） | OtpKeyProv 兼容，`.otp.xml` 辅助文件 |
| 2 | 密码 + OTP（恢复模式） | `password_otp_recovery` | **P0** | 无 | 直接输入 secret（Hex/Base64/Base32/Utf8/Dec） |
| 3 | 密码 + 挑战-应答（XC） | `password_challenge_response_xc` | **P1** | YubiKey 5 NFC | KDBX4+，KeePassXC 兼容 |
| 4 | 密码 + 密钥文件 + 挑战-应答（XC） | `password_keyfile_challenge_response_xc` | **P1** | YubiKey 5 NFC | 同上，叠加密钥文件 |
| 5 | 密码 + 挑战-应答（KeeChallenge 旧版） | `password_challenge_response` | P2 | YubiKey NFC | `.ChallengeInfo.xml` 辅助文件 |
| 6 | 密码 + 挑战-应答恢复模式 | `password_challenge_response_recovery` | P2 | 无 | 直接输入 secret |

> 说明：`AuthType` 中上述 6 种类型与资源串均已预定义，无需新增枚举，只需启用并打通链路。

---

## 3. 总体技术方案

### 3.1 kdbxweb 库扩展（新增自定义密钥分量）

`libs/kdbxweb/src/main/ets/format/kdbx-credentials.ts`：

1. `KdbxCredentials` 构造函数追加可选参数 `customKey?: ArrayBuffer | Uint8Array`（对应 KeePass `KcpCustomKey` 的 KeyData）；
2. 新增 `setCustomKey()`：对入参做 SHA-256 得 `customKeyHash: ProtectedValue`（KeePass 复合密钥对每个 user key 的贡献即其 KeyData 的 SHA-256）；
3. `getHash()` 中在 `keyFileHash` 之后、`chalResp` 之前追加 `customKeyHash`（保持 KeePass/KP2A 的拼接顺序）；
4. 兼容性：不传 `customKey` 时行为与现状完全一致（现有 3 种解锁方式零影响）。

### 3.2 认证链路扩展

```
Password.ets (UI 收集)
  → OtpKeyProvService / YubiKeyChallengeService（主线程完成 secret 派生或 NFC 挑战）
  → LoadDatabase 消息新增字段（otpSecretHex / challengeResponseHex / auxFileLocation 等）
  → DatabaseLoad Worker
  → CredentialsService.createKdbxCredentials() 按 AuthType 组装 KdbxCredentials
     （password + keyfile + customKey + challengeResponse 固定回调）
```

关键决策：

- **OTP secret 在主线程派生**：`.otp.xml` 解析、`KeyFromOtps`（AES-KDF 变换可能达 1 万+ 轮）、Salsa20 解密、`PlainTextHash` 校验全部在主线程（或独立轻量任务）完成后，仅把 secret 以 hex 传入 Worker（与现有 `password` 字段同级的消息通道，无新增安全面）；
- **挑战-应答两阶段加载**（规避 Worker↔主线程 RPC 复杂度）：
  1. 阶段一（主线程）：读取数据库文件头，解析 KDF seed（KDBX4 头字段 11 的 VarDictionary：Argon2 `Salt` / AES-KDF `Seed`）；
  2. 弹出 NFC 贴卡引导 → `IsoDepTag` APDU 选择 YubiKey OTP 应用 → HMAC 槽位挑战 → 得到 20 字节应答；
  3. 阶段二（Worker）：以「固定应答回调」构建 `KdbxCredentials`（kdbxweb 加载时对 KDF seed 调用回调，直接返回预计算应答，再由 kdbxweb 做 SHA-256 并入复合密钥）；
  - KDF seed 在两次读取间不变（同一份文件字节），结果等价于在线挑战；
- **仅 KDBX4 支持 XC 挑战-应答**：阶段一解析头时校验版本，KDBX3 提示不支持（对齐 `ChallengeXCKey.GetMinKdbxVersion()`）。

### 3.3 凭证构建（CredentialsService 改造）

`entry/src/main/ets/services/CredentialsService.ets` 按 `AuthType` 分派：

| AuthType | KdbxCredentials 组装 |
|---|---|
| `password_otp` / `password_otp_recovery` | `new KdbxCredentials(password, null, undefined, otpSecretBytes)` |
| `password_challenge_response_xc` | `new KdbxCredentials(password, null, fixedChallengeResponseFn)` |
| `password_keyfile_challenge_response_xc` | `new KdbxCredentials(password, keyFileBytes, fixedChallengeResponseFn)` |
| （P2）`password_challenge_response(_recovery)` | 同 OTP，customKey = KeeChallenge secret |

### 3.4 UI 改造（Password.ets）

- `AuthType.getAllTypes()` 启用新类型（`TypeDefined.ets:240-245` 解除注释，按发布节奏分批）；
- 按 `AuthType` 条件渲染新区块：
  - **OTP 输入区**：`OtpsRequired` 个 `TextInput`（`otp1..otp6`，参考 KP2A `_otpTextViewIds`），自动加载辅助文件（`<db>.otp.xml`，本地/远端存储走 `IFileStorage`）；辅助文件缺失时提示引导；
  - **恢复模式区**：secret 单行输入 + 编码格式选择（Hex/Base64/Base32/Utf8/Dec）；
  - **挑战-应答区**：YubiKey 槽位选择（slot1/slot2）+「开始验证」按钮触发 NFC 贴卡引导弹层（读卡中/成功/失败/超时状态）；
- `updateButtonState()` / `verifyAndOpenDatabase()` 增加对应校验分支；
- 资源串：大部分已存在（`auth_type_password_otp` 等），补充 OTP 输入提示、NFC 引导等新串（zh-CN/en 双语）。

### 3.5 辅助文件与最近记录

- **OTP 辅助文件定位**：与数据库同目录同名 + `.otp.xml`；本地/远端存储统一经 `IFileStorage` 抽象读取（复用 `KdbxFileManager`/`FileService` 的存储访问层）；
- **Counter 写回**：解锁成功后 `Counter += OtpsRequired(+i)` 写回 `.otp.xml`（对齐 `SaveOtpAuxFileAndLoadDb`）；写回失败仅告警不阻断（远端存储可能只读）；
- **RecentFile 扩展**（`TypeDefined.ets:334`）：新增可选字段 `otpAuxLocation?: LocationInfo`（恢复模式/重开时免重新定位）、`yubikeySlot?: number`（记忆槽位）；OTP secret **不持久化**（每次解锁重新由 OTP 码派生）；
- **快速解锁/生物识别适配**（M4 实测确认）：应用内锁屏（UnLockDatabase）下库保持内存解密态，快速密码/生物识别仅恢复界面遮罩，不重新派生密钥——OTP/挑战库无需补齐硬件因子，原方案（锁屏后重新输入 OTP 码/贴卡）不再需要；冷启动完整解锁流程中，生物识别仅代填密码分量，OTP 码 / YubiKey 贴卡仍需手动完成（KDF seed 每次保存后变化，应答不可复用，对齐 KP2A 行为）；仅密码分量可走既有快速密码/生物识别通道。

---

## 4. 分阶段实施计划

### 阶段 M1：基础设施（预估 2~3 人日）【已完成，见第 0 节】

| 任务 | 文件 | 说明 |
|---|---|---|
| kdbxweb `KdbxCredentials` 支持 customKey | `libs/kdbxweb/.../kdbx-credentials.ts` | 构造参数 + `setCustomKey` + `getHash` 拼接顺序 |
| `AuthType` 辅助方法 | `entry/src/main/ets/services/TypeDefined.ets` | `useOtpAuth()` / `useChallengeAuth()` / `isRecoveryMode()` |
| `CredentialsService` 分派重构 | `entry/src/main/ets/services/CredentialsService.ets` | 新增 customKey / challengeResponse 分支 |
| `LoadDatabase` 消息扩展 | `entry/src/main/ets/workers/DatabaseLoadWorkerParam.ets` | `otpSecretHex?` / `challengeResponseHex?` / `otpAuxLocation?` |
| kdbxweb 单元测试 | `libs/kdbxweb/src/ohosTest/ets/test/format/kdbx-credentials.test.ets` | customKey 哈希向量、与 KeePass 桌面版生成的库互验 |

### 阶段 M2：OTP + OTP 恢复模式（P0，预估 4~5 人日）

| 任务 | 文件 | 说明 |
|---|---|---|
| `OtpInfo` XML 解析/序列化 | `entry/src/main/ets/services/otpkey/OtpInfo.ets`（新建） | 对齐 `addons/OtpKeyProv/OtpInfo.cs` 字段，v1（EncryptedSecret）/v2（EncryptedSecrets[]）双格式 |
| 密钥派生工具 | `entry/src/main/ets/services/otpkey/OtpUtil.ets`（新建） | `KeyFromOtps`（SHA-256→AES-KDF→SHA-256）、Salsa20 解密（复用 kdbxweb `Salsa20`）、`PlainTextHash` 校验 |
| HOTP 生成（前瞻校验用） | `entry/src/main/ets/services/otpkey/HmacOtp.ets`（新建） | RFC 4226，仅用于密钥创建/验证场景 |
| 编码解析（恢复模式） | `entry/src/main/ets/services/otpkey/EncodingUtil.ets`（新建） | Hex/Base64/Base32/Utf8/Dec（对齐 `OtpDataFmt`） |
| `OtpKeyProvService` 编排 | `entry/src/main/ets/services/otpkey/OtpKeyProvService.ets`（新建） | 辅助文件定位读取 → OTP 码派生 secret / 恢复模式解析 secret → hex 交 Worker；成功后 Counter 写回 |
| UI：OTP 输入区 + 恢复模式区 | `entry/src/main/ets/pages/Password.ets` | 多码输入、编码选择、按钮状态校验 |
| 辅助文件读写 | 复用 `KdbxFileManager` / `IFileStorage` | 本地 + 远端存储 |
| 测试 | `entry/src/ohosTest/ets/test/` | RFC 4226 测试向量；用 KeePass 桌面版 OtpKeyProv 生成的 `.otp.xml` + KDBX 做互操作解锁测试 |

### 阶段 M3：YubiKey 挑战-应答（XC 兼容）（P1，预估 4~6 人日）

| 任务 | 文件 | 说明 |
|---|---|---|
| KDBX 头预解析工具 | `entry/src/main/ets/services/kdbx/KdbxHeaderReader.ets`（新建） | 读签名/版本/KDF 参数，提取 KDF seed；KDBX3 拒绝并提示 |
| YubiKey NFC 服务 | `entry/src/main/ets/services/yubikey/YubiKeyNfcService.ets`（新建） | `IsoDepTag` APDU：Select AID `A000000527200101` → HMAC slot 挑战（0x30/0x38）→ 20 字节应答；超时/失败/移卡状态机 |
| NFC 权限与前台分发 | `entry/src/main/module.json5`、`EntryAbility.ets` | 声明 `ohos.permission.NFC_TAG`；`tagforeground` 注册（前台优先） |
| NFC 贴卡引导弹层 | `entry/src/main/ets/components/yubikey/NfcChallengeDialog.ets`（新建） | 贴卡动画、取消、错误重试 |
| UI：槽位选择 + 挑战触发 | `entry/src/main/ets/pages/Password.ets` | `password_challenge_response_xc` / `password_keyfile_challenge_response_xc` 两类型 |
| `RecentFile.yubikeySlot` 记忆 | `TypeDefined.ets` / `RecentFilesService.ets` | 槽位持久化 |
| 测试 | 真机（YubiKey 5 NFC） | 用 KeePassXC 创建挑战-应答库做互操作解锁；坏卡/超时/中途回退等异常路径 |

### 阶段 M4：快速解锁与收尾（预估 2~3 人日）

| 任务 | 文件 | 说明 |
|---|---|---|
| 快速解锁适配 | `UnLockDatabase.ets`、`Password.ets` | OTP/挑战库生物识别通过后的硬件因子补齐流程；`putFileToRecentFile` 仅存密码分量 |
| 设置页适配 | `pages/setting/SettingSecurity.ets` | 默认认证方式与新增类型的联动展示 |
| i18n 资源补齐 | `resources/base/element/string.json` 等 | 新增提示串 zh-CN/en |
| 文档 | `docs/` | 用户使用说明（各解锁方式操作指引） |

### 阶段 M5（可选，P2）：KeeChallenge 旧版兼容（预估 3~4 人日）

- `.ChallengeInfo.xml` 解析、HMAC-SHA1/AES 解密 secret、challenge 写回（对齐 `KeeChallenge.cs`/`ChallengeInfo.cs`）；
- `password_challenge_response` / `password_challenge_response_recovery` 启用；
- 仅在明确存在存量用户需求时排期。

---

## 5. 测试计划

| 层级 | 内容 | 工具/位置 |
|---|---|---|
| 单元测试（kdbxweb） | customKey 哈希拼接顺序与 KeePass 一致；challengeResponse 固定回调 | `libs/kdbxweb/src/ohosTest/`，Hypium，`hdc shell aa test` 真机运行 |
| 单元测试（entry） | HOTP RFC 4226 向量；`KeyFromOtps`/Salsa20/PlainTextHash 向量（从 KP2A 插件测试取数）；五种编码解析 | `entry/src/ohosTest/ets/test/` |
| 互操作 | KeePass 2.x（Windows）+ OtpKeyProv 创建 `.otp.xml` 库 → KeePassHO 解锁；KeePassXC + YubiKey 创建 KDBX4 挑战-应答库 → KeePassHO 解锁；反向保存后回开 | 真机 + 桌面工具；**均未执行，待验证**（无 YubiKey 实体钥与桌面环境） |
| 回归 | 现有 3 种解锁方式（密码/密钥/密码+密钥）全链路回归；快速解锁、生物识别、锁定流程 | 真机 E2E |
| 异常路径 | OTP 码错误（PlainTextHash 不匹配）、辅助文件缺失/损坏、Counter 写回失败、NFC 超时/移卡、KDBX3 库选 XC 挑战、远端存储离线 | 手工/自动化 |

---

## 6. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| YubiKey NFC APDU 在部分鸿蒙机型 NFC 控制器上兼容性差 | M3 不可用 | 早期真机 Spike（M3 首日）验证 AID 选择 + HMAC 槽位指令；失败则降级为仅支持「恢复模式」并明确产品提示 |
| KDF seed 两阶段读取不一致（远端文件中途被改） | 挑战应答错误 → 解锁失败 | 阶段一与阶段二共用同一份已下载字节（复用本地缓存/同一读取会话）；失败提示重试 |
| `.otp.xml` 写回失败（远端只读/离线） | Counter 不前进，下次 OTP 码需从原计数起 | 仅告警不阻断；`LookAheadCount` 容忍前瞻窗口 |
| AES-KDF 变换轮数高（OTP 派生）主线程卡顿 | 输入 OTP 后 UI 冻结 | 轮数来自辅助文件（典型 1 万轮，量级可控）；>5 万轮时放 Worker 派生 |
| 新增密钥分量改变复合密钥拼接顺序导致互操作破坏 | 跨端无法解锁 | 不传 customKey 时零行为变化；单测锁定拼接顺序（password→keyfile→customKey→challenge） |
| OTP secret 经 Worker 消息通道传输 | 内存暴露面扩大 | 与现有 password 通道同级；用后 `zeroBuffer` 清理（kdbxweb 已有此惯例） |
| XC 库保存被拦截后用户误以为已保存 | 修改丢失（用户预期落空） | 拦截以明确错误提示（Toast/回调 onError），文案说明"修改未保存"；远端重载/下拉刷新不受影响；后续 P2 支持「保存前重贴卡」两阶段保存后解除拦截 |

---

## 7. 附录：关键参考源码索引

| 主题 | 位置 |
|---|---|
| KP2A 解锁方式枚举与编排 | `其他库/keepass2android/src/keepass2android-app/PasswordActivity.cs:78`（KeyProviders）、`:1532-1573`（复合密钥组装） |
| OtpKeyProv 核心 | `其他库/keepass2android/src/keepass2android-app/addons/OtpKeyProv/`（`OtpInfo.cs`、`OtpUtil.cs`、`OathHotpKeyProv.cs`） |
| HOTP 生成 | `其他库/keepass2android/src/KeePassLib2Android/Cryptography/HmacOtp.cs` |
| 挑战-应答（XC） | `其他库/keepass2android/src/keepass2android-app/ChallengeXCKey.cs`；KeePassXC `其他库/keepassxc/src/keys/ChallengeResponseKey.h` |
| 挑战-应答（KeeChallenge 旧版） | `其他库/keepass2android/src/keepass2android-app/KeeChallenge.cs`、`ChallengeInfo.cs` |
| ykDroid 外部挑战 App 集成 | `其他库/keepass2android/src/keepass2android-app/LockingActivity.cs:149` |
| 复合密钥拼接顺序 | `其他库/KeePass-2.61.1-Source/KeePassLib/Keys/CompositeKey.cs:87` |
| 本项目 kdbxweb 挑战-应答支持 | `libs/kdbxweb/src/main/ets/format/kdbx-credentials.ts:18,143,172`；`kdbx-format.ts:1113` |
| 本项目现有认证链路 | `entry/src/main/ets/services/TypeDefined.ets:167`、`services/CredentialsService.ets`、`workers/DatabaseLoad.ets:38`、`pages/Password.ets` |
