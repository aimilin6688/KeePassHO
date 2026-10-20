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
| M3 YubiKey 挑战-应答（XC 兼容）— NFC 服务与 UI | 已完成（代码与单测） | `YubiKeyNfcService`（tag.on readerMode 前台读卡 + IsoDepTag 两步 APDU：Select AID `A000000527200101` → HMAC 挑战 0x30/0x38 挑战补位至 64 字节 → 20 字节应答 + SW 9000；7 类错误码状态机，会话内可重贴重试；补位方式后经互操作复查修正为 PKCS#7，见下方复查行）；`NFC_TAG` 权限声明；`NfcChallengeDialog` 贴卡弹层（等待/读取/错误态，取消/重试，生命周期驱动会话）；Password.ets 槽位选择（默认槽位 2）+ 两阶段触发（阶段一头预解析提取挑战 → 弹层 → challengeResponseHex 加载）+ KDBX3/坏头/读失败分类提示；`RecentFile.yubikeySlot` 槽位记忆；`getAllTypes` 启用两个 XC 类型；APDU 纯函数真机单测，6 套件回归 58/58；待验证：YubiKey 5 NFC 实体钥互操作 |
| M4 快速解锁与收尾 | 已完成 | 快速解锁语义确认：应用内锁屏（UnLockDatabase）库保持内存解密态，生物识别/快速密码仅恢复界面，OTP/XC 无需重派生密钥，无需改动；Password.ets 生物识别对 XC 挑战-应答库改为仅代填密码分量（不自动弹 NFC 层，由用户按解锁键触发，与 OTP 行为一致）；`RecentFile.otpAuxLocation` OTP 辅助文件位置记忆（手动选择/自动定位结果持久化，重开免重新定位）；设置页验证无需改动（不枚举数据库认证方式）；新增用户使用说明 `docs/unlock-methods-guide.md`；6 套件回归 58/58 |
| 缺口复查修复（M4 后全链路复查） | 已完成 | ① OTP 库无法保存：`setFileParam` 的 DbFileParam/credentialsParam 从未携带 `otpSecretHex` → 保存时策略抛 `error_otp_secret_missing`；修复：Password.ets 解锁时暂存 `otpSecretHex`/`challengeResponseHex`（页面状态，切换认证方式即清理），`setFileParam` 双路透传（successMessageToKdbx 还原 + FileService.setDbFileParam），保存/重载/下拉刷新链路打通。② 大库（>4MB）Worker 容器路径：主线程 `successMessageToKdbx` 重建凭证缺 secret 而失败（"Database open failed"）；XC 模型路径 `fixedResponse` 函数随 Kdbx 实例 postMessage 触发结构化克隆 DataCloneError；修复：容器路径由 ① 提供 secret；DatabaseLoad 模型路径 XC 传输前 `setChallengeResponse(undefined)` 剥离挑战回调（`kdbxweb` setter 改 public）。③ XC 保存语义缺失：kdbxweb `save()` 必重新生成 KDF seed，解锁应答仅对当前 seed 有效，直接保存将产生无法回开的文件；修复：`KdbxSaveService.saveDatabase` 入口拦截（`error_challenge_response_save_unsupported`，覆盖手动/自动/合并全路径；RELOAD 不拦截——seed 未变应答仍有效，`byDbFileParam` 透传 challengeResponseHex 支持重载/下拉刷新）；两阶段「保存前重贴卡」列入 P2 backlog。新增 E2E 回归 `UnlockSecretsSaveReload`（OTP Worker 容器解锁→保存→重开、缺 secret 负例、XC 挑战剥离、XC 缺应答负例、XC 保存拦截文件零变更）；待验证：KeePass 桌面 OtpKeyProv / KeePassXC+YubiKey 实体钥互操作、反向保存后回开 |
| 互操作复查与修复（对照 keepass2android / KeePassXC / KeePass 源码全量复查） | 已完成 | ① **挑战补位修正（关键互操作缺陷）**：`YubiKeyNfcService.padChallengeTo64` 由补零改为 **PKCS#7 风格补位**（补位字节值 = 64−len），对齐 KeePassXC `YubiKeyInterfaceUSB.cpp:278-281` / `YubiKeyInterfacePCSC.cpp:752-755` 与 KP2A `ChallengeXCKey.cs:39-52`。依据：补零仅当 YubiKey HMAC 槽位配置了「消息 <64 字节」（`CFGFLAG_HMAC_LT64`）标志时等价（此时卡端剥离尾部同值字节），而 KeePassXC 标准配置为定长 64 字节 HMAC（LT64 未设置），补零会导致真实 YubiKey HMAC 输入不同 → 应答不同 → 实体钥解锁失败。PKCS#7 补位对两种槽位配置均兼容。同步更新 `YubiKeyNfcService.test`（12 用例）与 `KdbxHeaderReader.test`（10 用例）模拟卡侧补位。② **密钥文件防误选 KDBX**：`KeyFileReader` 新增 `isKdbxDatabaseBytes` 前 8 字节签名检查（0x9AA2D903 + {0xB54BFB67 / 0xB54BFB66 / 0xB54BFB65}），对齐 KeePass 桌面 `KcpKeyFile(bThrowIfDbFile)`（KcpKeyFile.cs:75-91），误选数据库文件时以 `error_keyfile_is_database`（zh/en）明确报错；新增 `KeyFileReader.test` 7 用例。③ 全量差距分析定稿见 §8（未实现功能清单与优先级）。待验证项不变：YubiKey 5 NFC 实体钥、KeePass 桌面 OtpKeyProv、反向保存回开 |
| 实现评审修复（P0/P1/P2，对照 yubikit / ykDroid / KeePassXC / KP2A 权威实现） | 已完成 | **P0-1 HMAC 挑战 APDU 布局**：槽位字节误占 INS 位（`00 (0x30\|0x38) 00 00 40`），真实 YubiKey 全部拒答；修正为三方一致布局 `00 01 <槽位> 00 40`（INS=0x01 API 请求，P1=槽位 0x30/0x38，依据 yubikit `send_apdu(0, INS_CONFIG=0x01, slot, 0, data)`、ykDroid PutApdu、KeePassXC `{CLA_ISO, INS_API_REQ=0x01, slot_cmd, 0, 64}`）。**P0-2 onSuccess 死代码**：成功路径先 `stopSession()`（清空 callbacks）再读 `this.callbacks` → 恒 null，挑战成功永不回调；修复：完成路径抽出 `onExchangeSuccess`/`onExchangeFailed`（protected，供测试子类驱动），成功路径先捕获回调再停会话，取消后迟到结果丢弃。**P1 Counter 写回时机**：v2 由解锁成功后写回提前至派生验证通过后、加载前（对齐 KP2A `SaveOtpAuxFileAndLoadDb` 先写后加载），避免加载失败令牌前进而文件未动 → 重试旧码全失效 OTP 锁死；实现：`OtpDerivedSecret.verified`（v2=PlainTextHash 校验通过，v1=false）、`advanceOtpCounterBeforeLoad`（await，失败告警不阻断）、`writeBackOtpCounter` 拆分——v2 已写回跳过 / 写回失败仅重试写盘不再次前进（防双倍消耗）/ v1 维持成功后写回。**P2 XC 双倍下载**：阶段一 `manager.read()` 整读远端文件仅取头部，阶段二再次全量下载；改为 `readToFile` 落盘临时文件（缓存装饰器回填缓存+版本元数据 → 阶段二命中快速路径免二次下载）+ 新增 `KdbxHeaderReader.readHeaderFromFile`（64KB 前缀预读，超大头部倍增回退，文件截断如实抛 TRUNCATED）。同步更新测试：`YubiKeyNfcService.test` APDU 断言修正 + 会话状态机 4 用例（Testable 子类，成功停会话/失败保持可重贴/非 YubiKeyNfcError 包装/取消丢迟到结果）、`OtpKeyProvService.test` verified 断言 ×3、`KdbxHeaderReader.test` readHeaderFromFile 3 用例（小文件/超大头回退/截断）。待验证：YubiKey 5 NFC 实体钥互操作 |
| XC 两阶段保存（预挑战注入，解除保存拦截） | 待开始（方案定稿 §9，排期 M1→M5） | — |
| M5 KeeChallenge 旧版（可选 P2） | 待开始 | — |

---

## 1. 现状分析

### 1.1 KeePassHO 当前实现

> **注**：本小节为 M0 立项时的基线快照，保留用于追溯设计动机；各阶段完成后的实际现状见 §0 进度表与 §8 复查结论。

| 模块 | 位置 | 现状（M0 基线） |
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
   6. 派生校验通过（v2 PlainTextHash 比对命中）后、加载数据库前把 `Counter += OtpsRequired(+i)` 写回辅助文件（`SaveOtpAuxFileAndLoadDb`，先写后加载）。
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
  YubiKey 5 NFC 的 OTP 应用 AID 为 `A0000005272001`（7 字节：A0 00 00 05 27 20 01），HMAC 挑战 APDU：`00 01 <槽位> 00 40`，INS=0x01（API 请求）、P1=槽位（slot1=`0x30`、slot2=`0x38`，对齐 yubikit / ykDroid / KeePassXC）；
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
- **Counter 写回**：v2（PlainTextHash 校验通过）在派生后、加载前把 `Counter += OtpsRequired(+i)` 写回 `.otp.xml`（对齐 `SaveOtpAuxFileAndLoadDb` 先写后加载），写回失败不阻断加载、解锁成功后仅重试写盘（不再次前进，防双倍消耗）；v1（派生无校验）在解锁成功后写回；写回失败均仅告警不阻断（远端存储可能只读）；
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
| KeePassXC 保存模型（挑战内嵌） | `其他库/keepassxc/src/format/Kdbx4Writer.cpp:51`、`src/core/Database.cpp:909-996`、`src/keys/CompositeKey.cpp:85-160`、`src/keys/ChallengeResponseKey.cpp`、`src/keys/drivers/YubiKey.cpp:148-178`、`src/gui/DatabaseWidget.cpp:2486-2540`、`src/gui/MainWindow.cpp:1851` |

---

## 8. 与 keepass2android / KeePassXC 对比复查结论（2026-10）

> 对照 `其他库/keepass2android`、`其他库/keepassxc`、`其他库/KeePass-2.61.1-Source` 源码全量复查，
> 确认已实现项、本轮修复项与未实现功能清单。

### 8.1 已对齐项（KP2A 全部 KeyProviders 能力面）

| 能力 | KP2A/KeePassXC 参考 | KeePassHO 现状 |
|---|---|---|
| KeyFile / Password / 组合 | `PasswordActivity.cs:1505-1531` | 一致（策略化凭证构建） |
| OTP（OtpKeyProv v1/v2） | `OathHotpKeyProv.cs`、`OtpUtil.cs` | 一致：KeyFromOtps（SHA-256→AES-KDF→SHA-256）、Salsa20 `s20://` 解密、LookAhead 前瞻窗口、PlainTextHash 校验、Counter `+= OtpsRequired(+i)` 写回（失败仅告警，对齐 `SaveOtpAuxFileAndLoadDb`） |
| OTP 恢复模式 | `EncodingUtil.cs`（Hex/Base64/Base32/Utf8/Dec） | 一致（五种编码解析） |
| XC 挑战-应答 | `ChallengeXCKey.cs`、KeePassXC `YubiKey.cpp` | 一致：KDBX4-only、challenge=KDF seed、64 字节 PKCS#7 补位（本轮修正）、应答 SHA-256 并入复合密钥、槽位 1/2 |
| 复合密钥拼接顺序 | `CompositeKey.cs:87` | 一致：password→keyfile→customKey→challenge（kdbxweb getHash） |
| 密钥文件防误选 KDBX | KeePass `KcpKeyFile.cs:75-91` | 本轮补齐（`isKdbxDatabaseBytes`） |
| 快速解锁 | `QuickUnlock.cs` | 语义一致（内存解密态 + 快速密码/生物识别恢复） |

### 8.2 本轮修复项

| # | 问题 | 根因 | 修复 |
|---|---|---|---|
| 1 | YubiKey 挑战补位为补零，与 KeePassXC/KP2A 不一致 | 实现时未对齐 `YubiKeyInterfaceUSB.cpp:278-281` 的 PKCS#7 补位；补零仅在槽位配置 LT64 标志时等价，KeePassXC 标准定长 64 字节 HMAC 槽位下产生不同应答 → 实体钥解锁必失败 | `padChallengeTo64` 改 PKCS#7 风格补位（字节值=64−len）；单测同步修正 |
| 2 | 密钥文件无 KDBX 防误选 | `KeyFileReader` 未实现 KeePass `bThrowIfDbFile` 签名检查 | 前 8 字节三组签名比对，命中抛 `error_keyfile_is_database`（zh/en） |

### 8.3 未实现功能清单（按优先级）

| 优先级 | 功能 | KP2A 参考 | 说明 |
|---|---|---|---|
| P2 | **M5 KeeChallenge 旧版挑战-应答**（`password_challenge_response` / `password_challenge_response_recovery`） | `KeeChallenge.cs`、`ChallengeInfo.cs` | `.ChallengeInfo.xml` 辅助文件（data/aes/encrypted/iv/challenge/verification/lt64）；64 字节 challenge（LT64 时 63）、HMAC-SHA1 应答；secret 以 AES 加密存辅助文件；**每次成功解锁须重新生成 challenge 写回防重放**（与 XC 的只读语义不同，保存链路须额外设计）；恢复模式直接输入 secret。枚举/资源串/凭证策略占位已预留（`OtpSecretStrategy.useChallengeAuth` 走 customKey 路径）。仅在明确存量用户需求时排期 |
| P2 | XC 库「保存前重贴卡」两阶段保存 | KeePassXC 支持保存时重新挑战 | **方案定稿见 §9（预挑战注入）**：保存入口生成新 KDF salt → NFC 贴卡取应答 → kdbxweb `save({ kdfSalt })` 注入写出 → 成功后更新会话应答。现状仍为保存拦截（`error_challenge_response_save_unsupported`），§9 M1–M5 实施后解除 |
| P3 | OTP 码剪贴板自动读取 | `PasswordActivity.cs:1929-1976` | KP2A 监听剪贴板：令牌 App 复制 OTP 码后切回，自动填入（5 秒新鲜度 + 长度/纯数字校验 + 去重）。KeePassHO 现需手动输入 |
| P3 | OTP 辅助文件随库同步 + Counter 冲突合并 | `SyncUtil.cs:119-124`、`OtpAuxCachingFileStorage.cs:29-93` | KP2A 数据库同步后同步 `.otp.xml`，双端并发修改时按 **Counter 较大者胜出** 合并。KeePassHO 现为解锁时直读 + 写回（last-writer-wins），多设备并发极端场景 Counter 可能回退 |
| P3 | 空密码重试语义 | `LoadDB.cs:212-225` | KP2A：复合密钥含**空密码分量**且多因子加载失败时，移除空密码分量重试一次（区分「空密码」与「无密码」）。KeePassHO 需用户显式选择正确认证方式（KEYFILE vs PASSWORD_KEYFILE） |
| — | 实体钥/桌面端互操作实测 | §5 测试计划 | 待硬件：YubiKey 5 NFC 实体钥（含 KeePassXC 建库解锁、APDU 兼容性 Spike）、KeePass 桌面 OtpKeyProv 建库解锁、反向保存回开 |

### 8.4 行为差异说明（设计取舍，非缺陷）

| 差异 | KeePassHO | KP2A | 取舍原因 |
|---|---|---|---|
| XC 挑战-应答保存 | 拦截并明确提示（§9 方案实施后解除） | 支持（保存内重新挑战） | 两阶段保存方案定稿见 §9；拦截期优先保证不产生无法回开的文件 |
| 生物识别 | 仅代填密码分量，硬件因子手动触发 | 同（OTP/XC 因子不自动提交） | 一致 |
| OTP secret / XC 应答持久化 | 不持久化，每次重新派生/采集 | 同 | 安全设计一致 |

---

## 9. XC 库两阶段保存整改方案（预挑战注入，2026-10 定稿）

> 对照 KeePassXC 源码（`其他库/keepassxc`）分析其挑战-应答保存模型，结合本项目 Worker 架构定稿。
> 目标：解除 XC 库保存拦截（`KdbxSaveService.ets:98`），实现「保存前贴卡」两阶段保存，
> 使 XC 库从只读升级为完整读写闭环。

### 9.1 KeePassXC 保存模型（源码结论）

严格说 KeePassXC **没有「两阶段」保存**——它是**单次保存内嵌挑战**，顺序由代码结构保证：

1. **应答永不缓存**：`ChallengeResponseKey` 只存槽位（serial, slot），`rawKey()` 返回刚算出的应答
   （`ChallengeResponseKey.cpp:25-64`）；应答不持久化、不跨阶段传递；
2. **挑战点在保存管道内、新 KDF seed 生成之后**：`Kdbx4Writer.cpp:51` →
   `db->setKey(key, false, /*updateTransformSalt=*/true)` → `kdf->randomizeSeed()`
   （`Database.cpp:965-968`）→ `CompositeKey::rawKey(&newSeed)` → `challenge(newSeed)`
   （`CompositeKey.cpp:97-104, 135-160`）→ 阻塞等待贴卡（`AsyncTask::runAndWaitForFuture`）→
   应答哈进复合密钥 → KDF 变换 → 加密写出。**seed 生成 → 挑战 → 加密的顺序在结构上不可能错配**；
3. **UX**：需交互时 500ms 定时器触发 `userInteractionRequest` 信号（`YubiKey.cpp:53`）→
   `MainWindow::showYubiKeyPopup()` 全局提示（`MainWindow.cpp:1851`）；`challengeCompleted` → 隐藏；
4. **失败语义**（`DatabaseWidget.cpp:2511-2539`、`Database.cpp:335-355`）：无卡/贴卡失败 →
   保存失败（"Unable to calculate database key"）；`markAsModified()` 保持修改态不丢数据，
   用户贴卡后重试即可；
5. 每次保存都重新贴卡（新 seed 必然新挑战）；快速解锁只用缓存的 `transformedDatabaseKey`，与保存无关。

### 9.2 与本项目现状差距

| 维度 | KeePassXC | 本项目现状 | 评估 |
|---|---|---|---|
| XC 库保存 | 保存内重新挑战 | 入口硬拦截（`KdbxSaveService.ets:98`），完全不能保存 | **核心缺口** |
| 线程模型 | 挑战与保存同线程，同步回调 | 保存跑在 Worker，NFC 只能在主线程；challenge 回调是函数，不可跨 Worker 结构化克隆（`kdbx-credentials.ts:140-143` 注释） | 不能照搬，需适配 |
| 应答生命周期 | 永不缓存 | 会话内存 `challengeResponseHex` 仅供 RELOAD（seed 未变，重用安全） | 可保留的取舍 |
| 失败语义 | modified 保留可重试 | 拦截 + toast + 清 pending changes | 随新方案重做 |

**为什么不能照搬内嵌挑战**：Worker 内 `save()` → `getHash(newSalt)` → challenge 回调需要跨线程
请求主线程贴卡再回传，需建立 worker→main→worker 双向 RPC（挂起 Promise + 消息关联），改动面大
且时序复杂。

### 9.3 选定方案：两阶段预挑战（Pre-challenged save）

- **阶段一（主线程）**：保存入口发现 XC 库 → 生成新 KDF salt（`CryptoEngine.random(32)`，与
  `generateSalts` 同源同强度）→ 弹 `NfcChallengeDialog` 贴卡（challenge=salt）→
  得到 (saltHex, responseHex) 挑战对；
- **阶段二（Worker）**：kdbxweb `save()/saveToFile()` 接受 `kdfSalt` 注入——`generateSalts()`
  之后用注入 salt 覆盖 `kdfParameters 'S'`；凭证用固定应答回调（现有策略机制扩展）；
- **安全等价性**：salt 仍是 32 字节 CSPRNG，仅生成时机从「写文件前一刻」提前到「保存入口」，
  加密强度无差；未用完的挑战对随保存失败作废；
- **MERGE 路径**：`mergeDatabase` 仍用旧凭证+旧应答加载远端（seed 未变），合并后 save 用新对；
- **冲突重试**：VERSION_CONFLICT 重试循环中每次 `buildSavedContent` 重新反序列化 →
  `generateSalts` → 注入覆盖 → 固定应答可重复调用，**同一挑战对可安全复用**；
- **关键新增不变量**：保存成功后必须把 `DbFileParam.challengeResponseHex` 更新为本次新应答
  （文件 seed 已变为新 salt，否则后续 RELOAD 报 InvalidKey）——KeePassXC 每次实时挑战无此簿记，
  是本方案唯一的会话状态维护点。

### 9.4 实施计划（M1→M5）

#### M1 kdbxweb：注入 KDF salt（约 1 人日）

| 任务 | 文件 | 说明 |
|---|---|---|
| `SaveOptions` + `save()`/`saveToFile()` 支持 `kdfSalt?: ArrayBuffer` | `libs/kdbxweb/.../format/kdbx-format.ts` | `generateSalts()`（:682/:788）之后若提供则覆盖 `kdfParameters 'S'`（校验 32 字节）；`:927`（saveXml 导出）不涉及 |
| `Kdbx.save(opts)` 透传 | `libs/kdbxweb/.../format/kdbx.ts` | 不传 opts 行为完全不变 |
| 单测 | `libs/kdbxweb/src/ohosTest/` | 注入 salt 保存 → 重读文件头 'S' == 注入值；无 opts 行为不变 |

#### M2 保存链路：透传挑战对（约 2 人日）

| 任务 | 文件 | 说明 |
|---|---|---|
| `SaveDatabaseMessage` 增加 `saveKdfSaltHex?`/`saveChallengeResponseHex?` | `workers/DatabaseSaveWorkerParam.ets` | 单次保存专用，勿与 `challengeResponseHex`（当前文件 seed 的应答）语义混淆 |
| XC 策略消费挑战对 | `services/credentials/ChallengeResponseXcStrategy.ets`、`workers/DatabaseSave.ets` | `buildSavedContent` 用 `saveChallengeResponseHex` 构建固定应答凭证；`database.save({ kdfSalt })` / `saveToFile` 带注入 |
| 成功后更新会话应答 | `services/kdbx/KdbxSaveService.ets` 成功回调 | `DbFileParam.challengeResponseHex` = 本次新应答（§9.3 不变量），单点更新 |

#### M3 编排层：两阶段入口（约 2 人日）

| 任务 | 文件 | 说明 |
|---|---|---|
| 移除硬拦截，改为两阶段编排 | `services/kdbx/KdbxSaveService.ets:98` | XC 库 && strategy != RELOAD：无 pending 对时主线程生成 salt → 弹 `NfcChallengeDialog` → 得对后 `executeSave`；取消/失败 → 保存中止（modified 保留，提示可重试） |
| 挑战对生命周期 | 同上 | 成功即消费并更新会话应答；失败/取消即作废（下次保存重新贴卡）；每次保存都贴卡（对齐 XC） |
| RELOAD 策略 | 同上 | 继续放行不贴卡（seed 未变应答仍有效，现有行为不变） |

#### M4 边界语义（约 1 人日）

- **ChangePassword/换认证**：保留或新增 XC 分量 → 走同一贴卡机制；移除 XC 分量（转纯密码）→
  不需贴卡（新凭证无 challenge 分量）；验证 pending credential changes 与新机制组合；
- 应用切后台 → NFC 会话取消 → 保存中止数据保留；
- 确认 `challengeResponseHex` 只在内存 `DbFileParam`，不进 RecentFiles 持久层（保持现状）；
- 用户文档 `docs/unlock-methods-guide.md` 同步更新（解除「XC 库暂不能保存」描述）。

#### M5 测试（约 2 人日）

- kdbxweb 单测：salt 注入一致性（重读 'S'）、注入 seed + 固定应答复合密钥向量（对拍 KeePassXC 文件）；
- Worker 链路单测：消息透传、MERGE 重试复用对、成功后会话应答更新、取消/失败作废；
- 设备 E2E：解锁→改→保存（贴卡）→RELOAD（不贴卡）→再保存（再贴卡）；MERGE 冲突；取消贴卡；
- 回归：现有保存/加载/OTP 全量套件。

### 9.5 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 注入 seed 与应答错配（编排 bug 旧应答配新 seed） | 保存出无法回开的文件（数据损坏） | 挑战对原子化（salt+response 成对传递/成对作废）；M5 对拍 KeePassXC 文件回开；无对时保留拦截兜底（不裸保存） |
| 保存成功但会话应答未更新 | 后续 RELOAD 报 InvalidKey | 成功回调单点更新；E2E 覆盖「保存→重载」 |
| 贴卡弹层跨页面触发（保存入口分散） | UI 上下文获取失败 | 保存编排统一走 `KdbxSaveService`；弹层经 UIAbility window 弹出；失败路径降级为明确报错（modified 保留） |
| 自动保存场景频繁弹卡 | 打扰 | 对齐 KeePassXC 行为（其 autosave 同样触发贴卡提示）；后续可按反馈加设置项 |

### 9.6 收益与不改的影响

- **不改**：XC 库实质只读（解锁/浏览可用，一切修改保存被拦）；应用内编辑作废（观感等同丢数据）；
  无脱困路径（改密/换认证不可用）；YubiKey+KeePassXC 安全敏感核心用户群只能当查看器。
- **改**：XC 库完整读写闭环（解锁→编辑→保存贴卡→重载），与桌面端体验对齐；安全语义不降级
  （每次保存新 seed+新挑战、应答不持久化）；就地改密/换认证可用；挑战对机制可复用于后续
  KeeChallenge 等其它 CR 变体。
