# 子数据库（Child Databases / AutoOpen）功能设计方案

> 目标：参考 KeePass2Android（kp2a）的 Child Databases 实现，为 KeePassHO 引入「父数据库解锁后自动打开子数据库」能力，
> 并支持多数据库同时打开与切换。实现与 KeePass 桌面版内置 AutoOpen 机制、KeeAutoExec 插件（PC）字段约定兼容。
> 参考源码位置：`/Users/liujunguang1/workspace/code/other/harmony/KeePassHO/其他库/keepass2android`
> （核心文件：`src/keepass2android-app/KeeAutoExec.cs`、`ConfigureChildDatabasesActivity.cs`、`SelectCurrentDbActivity.cs`、`app/App.cs`）

---

## 0. 实施进度

> 按阶段滚动更新：实现 → 构建 → 真机单测通过 → 提交后标记。

| 阶段 | 状态 | 提交/说明 |
|---|---|---|
| M1 AutoOpen 解析基础（模型 / IfDevice / 路径解析 / DeviceIdentity + 单测） | 待开始 | — |
| M2 多库注册表（DatabaseRegistry + FileService 兼容改造 + 锁/保存/会话适配） | 待开始 | — |
| M3 自动打开编排 + 数据库切换 UI（AutoOpenCoordinator / 切换面板） | 待开始 | — |
| M4 子数据库管理页（启停本设备 / 立即打开 / 编辑 / 复制副本 / 添加子库） | 待开始 | — |
| M5 收尾（设置入口 / 字符串 / 提示条 / RecentFiles 适配 / E2E） | 待开始 | — |

---

## 1. KeePass2Android 子数据库功能研究

### 1.1 功能定义

kp2a 官方文案（`Resources/values/strings.xml:741`）：

> "Child databases are other databases which can be opened automatically when you open the parent
> database. Therefore, the child's master password and file location are stored in the parent.
> This feature allows to share some of your passwords with another person.
> The implementation is compatible with KeeAutoExec for PC."

要点：

1. **子数据库 = 父库内一条普通条目**：子库的**文件位置 + 主密码**存储在父库的一个专用条目里，不引入任何新文件格式；
2. **打开父库时自动打开子库**（多库并存，可切换）；
3. **可按设备启停**（IfDevice 过滤），典型场景是「与他人共享部分密码」；
4. **与 KeePass 桌面版内置 AutoOpen 机制、KeeAutoExec 插件双向兼容**——同一个 .kdbx 在 PC（KeePass/KeeAutoExec）与手机（kp2a）上行为一致。

### 1.2 数据模型：AutoOpen 组条目约定

KeePass 桌面版约定：在数据库**根组**下建一个名为 `AutoOpen` 的子组，组内每个条目描述一个待自动打开的数据库。kp2a 完整兼容并扩展（`KeeAutoExec.cs`）：

**组发现规则**（`KeeAutoExecExt.AddAutoExecEntries`，KeeAutoExec.cs:102）：

- 组名 `AutoOpen` **大小写不敏感**匹配；
- 从根组**递归**向下搜索（任意深度的嵌套组内名为 AutoOpen 的组都会命中）；
- 命中 AutoOpen 组后，收集其**全部层级**条目（`GetEntries(true)` 递归），不再继续下钻该子树。

**条目字段映射**（`MakeAutoExecItem` / `TryGetDatabaseIoc` / `AutoOpenEntry`）：

| 字段 | 含义 | 备注 |
|---|---|---|
| `Title` | 子库显示名 | 展示用 |
| `URL` | 子库文件路径 | **必填**（为空则条目被忽略）；支持占位符 `{DB_DIR}`、`{ENV_DIRSEP}`（kp2a 走完整 SprEngine 编译）；裸相对路径在 kp2a 本地文件场景**不支持**（AutoOpenEntry 返回 false），桌面版按 exe 目录解析 |
| `UserName` | 子库**密钥文件**路径 | 与 KeePass 桌面约定一致；亦支持占位符 |
| `Password` | 子库**主密码** | 以 ProtectedString 存于父库 |
| 自定义字符串 `Enabled` | `True`/`False`，条目总开关 | 覆盖默认；默认规则：条目 `Expires && ExpiryTime <= UtcNow` → 禁用 |
| 自定义字符串 `Visible` | `True`/`False`，是否在切换页展示 | 默认 true |
| 自定义字符串 `Priority` | long，打开顺序 | 默认按扫描顺序（0 递增），打开前按 Priority 排序 |
| 自定义字符串 `IfDevice` | 设备 CSV 过滤列表 | 详见 1.3 |
| 自定义字符串 `SkipIfNotExists`（兼容旧名 `Skip if not exists`） | `True` → 打开前检查文件存在（仅本地文件有意义），不存在则静默跳过 | 远程文件默认视为存在 |
| 自定义字符串 `SkipIfKeyFileNotExists` | `True` → 密钥文件不存在则静默跳过 | — |
| 自定义字符串 `Focus` | `Restore` → 子库加载后**不**切换为当前库 | 默认加载后 makeCurrent |
| 附件 `KeyFile.bin` | 内嵌密钥文件 | 无 UserName 字段时作为密钥文件来源 |
| `IocUserName` / `IocPassword` / `IocTimeout` / `IocPreAuth` / `IocUserAgent` / `IocExpect100Continue` / `IocPassive` | 远程协议（WebDAV/FTP/HTTP）连接参数 | kp2a 私有扩展，本项目 P2 再议 |

### 1.3 设备过滤：IfDevice CSV 格式

`GetIfDevice` / `BuildIfDevice` / `IsDeviceEnabled`（KeeAutoExec.cs:113-213）：

- 格式：逗号分隔 CSV，`TrimFields=true`，**反斜杠不转义**；
- 前缀 `!` = 排除项（`!` 后再 TrimStart），无前缀 = 包含项；
- **设备 ID 大小写不敏感**精确匹配；某设备显式命中 → 直接采用该项的包含/排除值（`isExplicit=true`）；
- 无任何显式命中时：**启用 ⇔（存在排除项 ∨ 不存在包含项）**。即：空 IfDevice → 所有设备启用；只有包含列表 → 不在列表中的设备禁用；只有排除列表 → 不在列表中的设备启用；
- 生成（BuildIfDevice）：若列表中存在任一启用设备，则**省略**禁用项；值含 `,` `\` `"` 时用 `"` 包裹并把 `"` 转义为 `\"`；
- 设备 ID 格式（`ThisDeviceId`）：
  `Build.Manufacturer + " " + Build.Model + " (" + ANDROID_ID + ")"`，并把 `!` `,` `;` 替换为 `_`。

### 1.4 多库管理：Kp2aApp

`app/App.cs`（Kp2aApp）维护多库状态：

| 成员 | 语义 |
|---|---|
| `_openDatabases: List<Database>` | 已打开数据库列表 |
| `_currentDatabase` | 当前库（`CurrentDb` setter 校验必须在列表内） |
| `_childDatabases: List<IOConnectionInfo>` | 经子库流程打开过的库（`RegisterChildDatabase` / `IsChildDatabase`），用于**抑制子库的生物识别设置建议**（GroupBaseActivity.cs:870）等 UX 差异 |
| `_openAttempts: List<IOConnectionInfo>` | 本次会话尝试打开过的文件，**防止失败后反复重试**（自动打开循环的关键防线） |
| `LoadDatabase(..., makeCurrent)` | 加载入列表；按 `Ioc.IsSameFileAs` 判重并**替换**旧实例 |
| `TryGetDatabase(ioc)` / `TrySelectCurrentDb(ioc)` | 按 ioc 查库 / 切当前库 |
| `FindDatabaseForElement(uuid)` | 跨库按 UUID 反查归属（配置页/编辑页用） |
| `CloseDatabase(db)` | 关单库；若关的是最后一个 → 走 `Lock()`（等于关全部） |
| `Lock()` | **一次性锁/清全部库**（QuickLock 除外——快速锁仅 UI 锁定，库仍驻留内存） |

### 1.5 自动打开流程（时序）

kp2a 在「数据库中枢页」`SelectCurrentDbActivity.OnResume` 触发（SelectCurrentDbActivity.cs:477-545）：

```
父库解锁成功（PasswordActivity 返回）
  → SelectCurrentDbActivity.OnResume
      → 遍历 OpenDatabases → OpenAutoExecEntries(db):
          对每个 AutoExecItem（已按 Priority 排序）：
            - Enabled == false → 跳过
            - IsDeviceEnabled(item, ThisDeviceId) == false → 跳过
            - TryGetDatabaseIoc 失败 / 无对应 FileStorage → 跳过
            - 子库已打开（TryGetDatabase(ioc) != null）→ 跳过
            - 本次会话已尝试过（AttemptedToOpenBefore）→ 跳过   ← 防循环/防重试
            - AutoOpenEntry(...):
                - SkipIfNotExists → CheckFileExsts（仅本地文件真正检查）
                - 组装 CompositeKey：Password 字段 → KcpPassword；
                  UserName 字段 → KcpKeyFile；否则附件 KeyFile.bin → KcpKeyFile
                - PasswordActivity.Launch(ioc, ck, makeCurrent = !Focus=Restore)
                - RegisterChildDatabase(ioc)
            - 返回 true（本 Resume 只打开一个，加载完成回到本页后继续下一个）
      → 全部打开完：多个库 → 停在中枢页供切换；单库 → 直接进 GroupActivity
```

子库加载完成回调（OnActivityResult，SelectCurrentDbActivity.cs:626-670）：`TrySelectCurrentDb(ioc)` 切为当前库 → 继续处理孙库条目 → 处理完再统一执行延迟的后台同步（`requiresSubsequentSync` 收集到 `_pendingBackgroundSyncs`，等 AutoOpen 链全部加载完再逐个同步）→ 进入主界面。

**防循环**：`_openAttempts` + 「已打开跳过」共同保证 A→B→A 时第二个 A 不会被重复打开；条目失败也只尝试一次。

### 1.6 添加子库（写入父库条目）

`ConfigureChildDatabasesActivity.AddAutoOpenEntryForDatabase`（ConfigureChildDatabasesActivity.cs:345-389）：

1. 在根组下查找名为 `AutoOpen` 的组，没有则创建（图标 1）；
2. 新建条目：
   - `Title` = 子库显示名；
   - `URL` = `TryMakeRelativePath`：子库与父库同目录时写 **`{DB_DIR}{ENV_DIRSEP}子库相对路径`**（跨设备可移植），否则写绝对路径；
   - `Password` = 子库当前主密码（`KcpPassword`，ProtectedString）；
   - `UserName` = 子库密钥文件路径（有密钥文件时，同样做相对化）；
   - `IfDevice` = `BuildIfDevice({本设备: true})`——**新添加的子库只对本设备启用**（保守默认）；
3. `AddEntry` 任务落库保存。

### 1.7 子库管理页（ConfigureChildDatabasesActivity）

列表项（`ChildDatabasesAdapter`，按编译后 Title 排序、再按 LastModificationTime 倒序）展示：图标、Title、URL、「本设备启用：是/否/未指定」、条目禁用态。每行操作：

| 操作 | 行为 |
|---|---|
| 本设备启用 / 本设备停用 | `SetDeviceEnabled` 改写 IfDevice 字段 + 保存父库 |
| 立即打开 | 子库尚未打开时显示；`AutoOpenEntry` 手动打开 |
| 编辑 | 跳普通条目编辑页（EntryEditActivity） |
| 复制为本设备副本（Copy for this device） | 克隆条目：原条目恢复原 IfDevice 并把本设备置为**停用**；副本清空 IfDevice 后仅启用本设备、新 UUID、Title 追加 `" (" + 设备型号 + ")"`，加入同组——用于「多设备各自一条目」场景 |
| 添加子库 | 弹选：其他**已打开**的库（直接生成条目）或「打开其他数据库…」（走文件选择→解锁→再生成条目），见 1.6 |

入口：① 设置页 `pref_database.xml:65` → `configure_child_dbs`；② 主界面（GroupBaseActivity）底部信息条：根组视图且存在**未显式配置本设备**的 AutoOpen 条目时显示 `unconfigured_child_dbs` 提示 + 「配置子数据库」按钮 + 「不再显示」（按库记忆，GroupBaseActivity.cs:891-909）。

### 1.8 kp2a 关键源码索引

| 功能 | 文件:行 |
|---|---|
| AutoExecItem 模型 / KeeAutoExecExt 全部解析逻辑 | `keepass2android-app/KeeAutoExec.cs` |
| 多库状态管理 | `keepass2android-app/app/App.cs:430-433, 1373-1474` |
| 自动打开触发与切换页 | `keepass2android-app/SelectCurrentDbActivity.cs:477-545, 626-670` |
| 子库管理页 | `keepass2android-app/ConfigureChildDatabasesActivity.cs` |
| 底部提示条 / 生物识别建议抑制 | `keepass2android-app/GroupBaseActivity.cs:638-653, 864-909` |
| 字符串资源 | `keepass2android-app/Resources/values/strings.xml:736-750` |

---

## 2. KeePassHO 现状与差距分析

### 2.1 现有架构盘点（均为「单库假设」）

| 模块 | 位置 | 现状 |
|---|---|---|
| 数据库持有 | `entry/src/main/ets/services/FileService.ets` | **单槽** `dbFileParam: DbFileParam`（含 `database: Kdbx`、密码、storageType/Config、保存基线）；`close()` 置空即全清 |
| 加载管线 | `services/kdbx/KdbxLoadService.ets` + `workers/DatabaseLoad*.ets` | ≤4MB 主线程，否则**常驻单 Worker**，忙时直接拒绝 `worker_busy`；加载产物经结构化克隆回主线程 |
| 保存管线 | `services/kdbx/KdbxSaveService.ets` | 单 `saving` 标志 + 单 `pendingSave` 槽位，**不支持并发保存多库** |
| 锁屏 | `services/LockScreenService.ets` + `pages/UnLockDatabase.ets` | 单 `lockWindow` 子窗口；手动/自动锁**不清内存**（快速解锁语义）；`close_database` 才 `FileService.close()` 全清 |
| 会话通知 | `services/SessionManager.ets` | 单会话、单通知，监听 `EVENT_LOCK_ACTION` |
| 最近文件 | `services/RecentFilesService.ets` | `RecentFile{filePath, storageType, storageConfig, authType, keyLocation, password(SM4 加密), ...}`，上限 30 |
| 存储层 | `storage/`（IFileStorage + LOCAL/WEBDAV/HUAWEI_DRIVE/S3/ONEDRIVE/FTP，PCLOUD 注释） | `CacheStorage` 装饰器按 filePath 哈希做缓存（**多文件天然安全**） |
| 主界面 | `pages/DatabaseView.ets` | 硬绑 `FileService.getDbFileParam().database`；`@StorageLink('databaseView_currentGroupId')` |
| 导航 | `NavigationManager`（4 根页）+ `route_map.json`（31 路由） | 无「切换数据库」入口；`EntryAbility.onNewWant` 打开新库前**先关当前库** |
| kdbxweb HAR | `libs/kdbxweb` | `Kdbx.load/loadFromFile/save/saveToFile`、`KdbxCredentials`、`entry.fields: Map<string, string\|ProtectedValue>`、`group.allEntries()/allGroups()`、`times.expires/expiryTime`；**无 SprEngine**（`{DB_DIR}` 需应用层实现）、无事件、无 AutoOpen 概念；`{REF:...}`/`{S:field}` 可用 `KdbxFieldReference.resolveFieldRefsInText` |
| 事件 | `EventBus.ets` | `DATABASE_RELOAD` / `DATABASE_UPDATE` / `EVENT_LOCK_ACTION('unlock'\|'close_database')` / `EVENT_LOCK_SCREEN`，均隐含「那一个库」 |

### 2.2 差距清单

1. **无多库注册表**：FileService 单槽是最大结构性缺口；
2. **无 AutoOpen 解析**：全工程（entry + kdbxweb）无任何 AutoOpen/KeeAutoExec 代码；
3. **无 SprEngine/占位符**：`{DB_DIR}`/`{ENV_DIRSEP}` 无处解析；
4. **加载互斥**：worker_busy 直接拒绝，无法串行自动打开多个子库；
5. **保存互斥**：单 saving 标志；
6. **UI 无切换/管理入口**；
7. **锁/关/会话语义单库**；
8. **设备身份**：HarmonyOS 无 ANDROID_ID，需新建设备 ID 方案。

### 2.3 可复用资产

- 加载/保存管线对**任意文件**可用（`LoadDatabase` 参数完整），子库可直接复用；
- 缓存按路径哈希隔离，多库共存安全；
- `CredentialsService` 策略链可构建「密码 / 密码+密钥文件」凭证——恰好覆盖 AutoOpen 条目能表达的凭证形态；
- `KdbxFieldReference.resolveFieldRefsInText` 可做 `{REF:...}` 编译（P2）；
- 结构化克隆传输 Kdbx 实例已有成熟先例（reload/refresh 路径）。

---

## 3. 总体设计

### 3.1 目标与非目标

**目标**

1. 父库解锁后，按 AutoOpen 条目**自动打开**子库（多库并存、可切换当前库）；
2. 与 KeePass 桌面 AutoOpen / KeeAutoExec / kp2a **字段级兼容**：PC 上配置好的父库拷到手机可直接用，反之亦然；
3. 按设备启停子库（IfDevice），提供子库管理页（启停/编辑/立即打开/复制副本/添加）；
4. 锁（快速锁）、关、超时自动锁对**全部库**统一生效。

**非目标（P2 backlog）**

- 跨库全局搜索、跨库条目移动/复制；
- 子库凭证写入 RecentFiles 生物识别持久化（子库不做生物识别建议，同 kp2a）；
- `IocUserName/IocPassword/...` 远程连接参数字段、`Focus` 字段、远程 URL scheme（`webdav://` 等）映射到 StorageType；
- 附件 `KeyFile.bin` 内嵌密钥文件（kp2a 支持，P2）；
- 子库自动后台同步编排（单库下拉刷新/保存照旧，按库独立）。

### 3.2 架构总览

```
┌────────────────────────────── UI ───────────────────────────────┐
│ DatabaseView（当前库视图 + 库名入口）                              │
│   ├─ DatabaseSwitcherSheet（切换面板：已打开/待打开子库/打开其他）      │
│   ├─ ChildDatabasesPage（子库管理页，路由 ChildDatabases）          │
│   └─ 子库提示条（未配置本设备时）                                    │
└──────────────────────────────────────────────────────────────────┘
              │ 事件 EVENT_DATABASE_REGISTRY_CHANGED / CURRENT_DB_CHANGED
┌─────────────────────────── 服务层 ───────────────────────────────┐
│ AutoOpenCoordinator（自动打开编排：串行队列/防循环/失败降级）          │
│ DatabaseRegistry（多库注册表：Map<iocKey, DbFileParam> + current）  │
│ AutoOpenService（纯解析：组扫描/条目解析/优先级/启用判定）             │
│ IfDeviceParser（CSV 解析/生成）   AutoOpenPathResolver（占位符展开） │
│ DeviceIdentity（设备 ID）                                        │
└──────────────────────────────────────────────────────────────────┘
              │ 复用
┌─────────────────── 既有管线（改造为多库安全）───────────────────────┐
│ KdbxLoadService（串行队列化）  KdbxSaveService（按库 saving 标志）    │
│ FileService（改造为 Registry 兼容 facade，API 不变）                 │
│ LockScreenService / SessionManager / EntryAbility（全库语义）        │
└──────────────────────────────────────────────────────────────────┘
```

### 3.3 核心数据模型

```text
// iocKey：库的唯一标识（注册表主键）
iocKey = `${storageType}::${filePath}`        // e.g. "LOCAL::file://docs/shared.kdbx"

// OpenDatabase：注册表条目（复用现有 DbFileParam 结构，不新造模型）
interface DbFileParam {  // 现有，TypeDefined.ets:89
  filePath, fileName, password, database: Kdbx, authType, keyLocation,
  storageType, storageConfig, modifiedTime, version, contentHash, ...
}

// AutoOpenItem：AutoOpen 条目解析结果（新文件 services/autoopen/AutoOpenItem.ets）
class AutoOpenItem {
  sourceIocKey: string;          // 归属父库
  entryUuid: string;             // KdbxUuid.toString()，编辑/启停定位
  title: string;
  url: string;                   // 原始 URL（未编译）
  keyFilePath?: string;          // UserName 字段
  password?: ProtectedValue;     // Password 字段
  enabled: boolean;              // Expires/自定义 Enabled 综合判定
  visible: boolean;
  priority: number;
  ifDeviceRaw?: string;
  skipIfNotExists: boolean;
  skipIfKeyFileNotExists: boolean;
}

// 解析产物（AutoOpenService.resolve 返回）
class ResolvedChildDatabase {
  item: AutoOpenItem;
  iocKey: string;                // 展开占位符 + 归一化后的子库 iocKey
  filePath: string;
  storageType: StorageType;      // M3 起恒为 LOCAL，schema 映射留 P2
}
```

### 3.4 关键决策

| # | 决策 | 理由 |
|---|---|---|
| D1 | **多库 = DatabaseRegistry + FileService facade**，不推翻现有单库调用方 | Password/DatabaseView/KdbxSave 等大量调用 `FileService.getDbFileParam()`；改造 Registry 内部持 `Map<iocKey, DbFileParam>` + `currentIocKey`，FileService 原 API 转发到「当前库」，改造面最小 |
| D2 | **触发点放在 Password.handleSuccessMessage 之后**（navigateBackToRoot('DatabaseView') 完成时），由 DatabaseView 首次 `loadDatabase()` 拉起 AutoOpenCoordinator | 对应 kp2a 的中枢页 OnResume 时机；避免在解锁页阻塞导航 |
| D3 | **自动打开为后台串行队列**，逐个加载、不阻塞父库浏览，完成一个发一个事件刷新 UI | 复用单 Worker；避免 worker_busy 拒绝；与 kp2a「一次只开一个」一致但体验更顺 |
| D4 | **锁/快速锁语义不变**：锁屏不清内存（多库驻留），`close_database` 关全部 | 与现行为及 kp2a 一致，改动最小 |
| D5 | **子库不写 RecentFiles、不弹生物识别建议**（`IsChildDatabase` 等价标记） | 同 kp2a；避免子库密码持久化面扩大 |
| D6 | **设备 ID = `${manufacturer} ${productModel} (${localUuid})`**，`!` `,` `;` → `_`；localUuid 为首启生成、存 SettingsService 的 UUID | 格式与 KeeAutoExec/kp2a 对齐；HarmonyOS ODID 需权限且可被用户重置，本地 UUID 最稳定 |
| D7 | 路径解析：`{DB_DIR}` = 父库文件目录；`{ENV_DIRSEP}` = `/`；裸相对路径按**父库目录**解析（kp2a 不支持裸相对路径，桌面版按 exe 目录——我们取父库目录并推荐显式 `{DB_DIR}{ENV_DIRSEP}` 写法） | 手机上 exe 目录无意义，父库目录符合直觉；显式写法保证三端一致 |
| D8 | 保存/刷新/搜索/TOTP 等操作**只作用于当前库** | kp2a 同语义，避免跨库写风险 |
| D9 | 添加子库默认 `IfDevice = 本设备启用`（保守默认），与 kp2a 一致 | 新子库不惊扰其他设备 |

---

## 4. 分阶段详细设计

### M1 AutoOpen 解析基础（纯逻辑，无 UI 变更，可独立交付）

**新增文件**（`entry/src/main/ets/services/autoopen/`）：

| 文件 | 职责 |
|---|---|
| `AutoOpenItem.ets` | 解析结果模型（3.3） |
| `IfDeviceParser.ets` | `parse(raw): Map<string, boolean>` / `build(devices): string` / `isEnabled(raw, deviceId): {enabled, isExplicit}`，规则严格对齐 1.3（含 `!` 排除、TrimFields、大小写不敏感、引号转义、Build 时省略禁用项） |
| `DeviceIdentity.ets` | `getDeviceId(): string`（D6；`deviceInfo.manufacturer/productModel` + SettingsService `KEY_DEVICE_LOCAL_UUID='device_local_uuid'`，首启生成） |
| `AutoOpenPathResolver.ets` | `resolve(url, parentFilePath): {filePath} \| undefined`：替换 `{DB_DIR}`/`{ENV_DIRSEP}` → 裸相对 → 拼 `dirname(parentFilePath) + '/' + rel` → 无路径返回 undefined；`makeRelative(childPath, parentFilePath): string`（同目录生成 `{DB_DIR}{ENV_DIRSEP}rel`，供添加子库用） |
| `AutoOpenService.ets` | `scan(database: Kdbx, parentIocKey): AutoOpenItem[]`：递归找 `AutoOpen` 组（大小写不敏感，命中即收全子树条目）；每条：URL 空跳过；`entry.times.expires && expiryTime <= now` → enabled=false；读自定义字符串 `Enabled`/`Visible`/`Priority`/`IfDevice`/`SkipIfNotExists`（兼容 `Skip if not exists`）/`SkipIfKeyFileNotExists`；Password 字段读为 `ProtectedValue`（`fields.get('Password')`，string 则包装）；按 priority 稳定排序。`resolveChild(item): ResolvedChildDatabase \| undefined`（调 PathResolver，storageType 暂恒 LOCAL） |

**读取字段注意事项**：`entry.fields` 值为 `string | ProtectedValue`，统一经 `KdbxUtils`/新 helper `readFieldText(entry, name)` 归一（ProtectedValue → `getText()`）。

**单元测试**（`entry/src/ohosTest/ets/test/`，新增 4 个套件，纯函数优先）：
- IfDeviceParser：空穿/包含/排除/`!` 后空格/大小写/引号转义往返/Build 省略禁用项/显式命中优先；
- AutoOpenService：嵌套组、组名大小写、无 URL 忽略、Expires 禁用、Enabled 覆盖、Priority 排序、AutoOpen 组子树全收集；
- PathResolver：`{DB_DIR}`、`{ENV_DIRSEP}`、裸相对、绝对、空 URL；
- DeviceIdentity：格式与字符替换（注入假 deviceInfo）。

### M2 多库注册表（行为不变，单库兼容）

**新增** `services/database/DatabaseRegistry.ets`：

```text
class OpenDatabaseRecord { iocKey; dbFileParam: DbFileParam; isChild: boolean; attempted: boolean }

class DatabaseRegistry {
  private records: Map<string, OpenDatabaseRecord> = new Map();
  private currentKey: string = '';
  get(iocKey) / getCurrent(): DbFileParam | undefined
  put(param, opts: { makeCurrent: boolean, isChild: boolean })   // 同 iocKey 替换（对齐 kp2a LoadDatabase）
  setCurrent(iocKey): boolean
  remove(iocKey)                                                  // 最后一个 → 由调用方走关闭流程
  has(iocKey) / isChild(iocKey) / markAttempted(iocKey) / wasAttempted(iocKey)
  all(): DbFileParam[]
  size()
}
```

**改造点**：

| 文件 | 改动 |
|---|---|
| `FileService.ets` | 内部改为 `get/setDbFileParam` 委托 Registry 当前库；`close()` = 清空 Registry（关全部）；新增 `closeCurrent()`（关当前，最后一个则全关，对齐 kp2a CloseDatabase）；API 签名不变，**所有既有调用方零改动** |
| `EntryAbility.ets` | `isLockScreen()` 判定改为 `Registry.size() > 0`；`onNewWant` 打开普通文件维持「先关再开」（子库走 Coordinator 专用路径不经过 onNewWant） |
| `KdbxSaveService.ets` | `saving`/`pendingSave` 单槽 → `Map<iocKey, SaveState>`；保存入口按当前库（或指定 iocKey）取槽位 |
| `KdbxLoadService.ets` | `workerBusy` 拒绝保留给**用户主动**操作；新增导出 `enqueueLoad(param, callback)`：忙则入队，空闲依序出队（供 Coordinator 使用）；复用既有 Worker 与缓存策略 |
| `LockScreenService.ets` / `UnLockDatabase.ets` | 语义注释化确认：快速锁不清 Registry（现行为已满足）；`close_database` → `FileService.close()`（清全部）保持；锁窗标题显示当前库名 |
| `SessionManager.ets` | 无需改动（事件语义「unlock/关」本来就是全局的） |
| `DatabaseView.ets` | `loadDatabase()` 改读 `Registry.getCurrent()`（经 FileService 不变，仅确认实例切换时按 Kdbx 身份重置视图状态——现有 rootPage 监听已做） |

**验收**：全量回归（解锁/保存/锁/关/刷新/OTP/XC 路径）零行为变化；新增单测：Registry 判重/替换/切换/关最后一个。

### M3 自动打开编排 + 切换 UI

**新增** `services/autoopen/AutoOpenCoordinator.ets`（单例）：

```
onParentUnlocked(parentIocKey):
  queue = AutoOpenService.scan(parent).filter(设备启用 && 未打开 && 未尝试)
        .map(resolveChild).filter(有效)          // SkipIfNotExists → 本地 exists 检查
  for item of queue（priority 序）:
    markAttempted(childIocKey)                    ← 防循环/防重试（D 系防线）
    creds = KdbxCredentials(ProtectedValue(密码) [, 密钥文件字节])   // keyFile 读失败且 SkipIfKeyFileNotExists → 跳过
    await KdbxLoadService.enqueueLoad(LoadDatabase{...})            // 串行
      成功 → Registry.put(param, {makeCurrent: 默认 true（Focus=Restore 不实现，注释预留）, isChild: true})
             → EventBus.emit(EVENT_DATABASE_OPENED, iocKey)
      失败 → hilog + EventBus.emit(EVENT_DATABASE_OPEN_FAILED, {iocKey, reason})；不重试
  全部完成 → EventBus.emit(EVENT_AUTO_OPEN_DONE, parentIocKey)
```

- 触发点：`Password.handleSuccessMessage` 末尾（setFileParam + 导航后）调 `Coordinator.onParentUnlocked(iocKey)`；
- 递归：子库打开成功事件里再次 `onParentUnlocked(childIocKey)`（孙库）；`wasAttempted` 已挡住环；
- 失败降级：父库浏览不受影响；失败子库出现在切换面板「待打开」区可手动重试（手动路径清 attempted 标记一次）。

**UI：DatabaseSwitcherSheet**（新组件 `components/DatabaseSwitcherSheet.ets`，DatabaseView 工具栏库名 chip → bindSheet）：

- 区块 1「已打开」：`Registry.all()`，当前库高亮；点击其他库 → `Registry.setCurrent` → `EventBus.emit(EVENT_CURRENT_DATABASE_CHANGED)` → DatabaseView 重载（复用 rootPage 监听 + `databaseView_currentGroupId` 重置）；
- 区块 2「子数据库」：当前库 AutoOpen 条目中 `visible && 设备启用 && 未打开` 的项（对齐 kp2a OpenDatabaseAdapter），点击 → Coordinator 手动打开（走解锁页补输密码当条目密码为空）；
- 区块 3「打开其他数据库…」→ push RecentFiles（以**添加**语义：不关当前库——此处放开 onNewWant 语义，走应用内导航而非新 Want）。

**事件新增**（Constants.ets）：`EVENT_DATABASE_OPENED` / `EVENT_DATABASE_OPEN_FAILED` / `EVENT_AUTO_OPEN_DONE` / `EVENT_CURRENT_DATABASE_CHANGED`。

### M4 子数据库管理页

**新增** `pages/ChildDatabases.ets` + route_map `ChildDatabases` + PageConstants `PAGE_CHILD_DATABASES`（对齐 ConfigureChildDatabasesActivity）：

- 数据：`AutoOpenService.scan(当前库)`，按 Title 排序、LastModificationTime 倒序；
- 行展示：图标 / Title / URL / 「本设备启用：是·否·未指定」/ 条目整体禁用态（`plugin_disabled` 语义）；
- 操作：
  - **本设备启用/停用**：`IfDeviceParser.build/parse` 改写 `IfDevice` 字段 → 走现有保存管线存父库；
  - **立即打开**：未打开时显示，Coordinator 手动打开；
  - **编辑**：push EntryEdit（现有页，按 entryUuid 定位）；
  - **复制为本设备副本**：原条目 IfDevice 中本设备置停用 → 克隆条目（新 UUID、Title + ` (设备型号)`、IfDevice 仅本设备启用）入同组 → 保存；
  - **添加子库**：弹选来源——「其他已打开的库」直接生成条目 /「选择文件」走 RecentFiles/SelectLocation 选库并解锁后回生成。生成逻辑（对齐 1.6）：找/建根下 `AutoOpen` 组（无则 `database.createGroup(root, 'AutoOpen')`）→ 新条目 Title/URL（`AutoOpenPathResolver.makeRelative` 同目录相对化）/Password=子库主密码 ProtectedValue/UserName=密钥文件路径（如有）/`IfDevice`=仅本设备启用；
- 入口：① 设置 → 数据库设置（`SettingDatabase.ets` 增行）；② 切换面板「管理子数据库…」；③ M5 的底部提示条。

### M5 收尾

1. **设置入口**：`SettingDatabase.ets` 增加「子数据库管理」行（`pref_database.xml` 对应物）；
2. **底部提示条**：DatabaseView 根组视图且存在**未显式配置本设备**的 AutoOpen 条目时显示（对齐 GroupBaseActivity.UpdateChildDbInfo）：文案 + 「去配置」+「不再提示」（`SettingsService KEY_CHILD_DB_HINT_HIDDEN_<iocKeyHash>`）；
3. **生物识别建议抑制**：子库（`Registry.isChild`）不弹指纹/人脸开通建议（kp2a IsChildDatabase 同义）；
4. **字符串资源**：`resources/base/element/string.json` + `zh_CN`：child_dbs_title / add_child_db / child_db_enabled_on_this_device / enable·disable_on_this_device / copy_for_this_device / unconfigured_child_dbs / open_other_db / child_db_explanation（翻译对齐 1.7 字符串表）；
5. **RecentFiles**：子库自动打开**不**调 `putFileToRecentFile`（D5）；
6. **用户文档**：`docs/child-databases-guide.md`（使用说明 + 与 PC 互操作指引：KeePass 桌面建 AutoOpen 组、KeeAutoExec 字段表、`{DB_DIR}` 写法建议）。

---

## 5. 生命周期语义汇总（多库下）

| 场景 | 行为 | 对应 kp2a |
|---|---|---|
| 父库解锁成功 | 进入 DatabaseView + Coordinator 后台串行开子库 | SelectCurrentDbActivity.OnResume |
| 快速锁（手动/超时） | 锁屏子窗口；**全部库驻留内存**；解锁（快速密码/生物识别）恢复全部 | Lock()→QuickLocked |
| 关闭数据库（锁窗「关闭」） | `FileService.close()` 清空 Registry（全部库）→ 回 Index | close_database |
| 切换当前库 | Registry.setCurrent + 事件刷新 DatabaseView；视图组状态重置 | TrySelectCurrentDb |
| 保存 | 仅当前库，按库独立槽位互不阻塞 | SaveDb（按 db 实例） |
| 下拉刷新 | 仅当前库 forceRefresh | CurrentDb.ReloadRequested |
| 自动锁计时 | 不变（全局） | TimeoutHelper |
| 会话通知 | 不变（全局会话） | OngoingNotificationsService |

---

## 6. 安全考量

1. **子库主密码存于父库条目**（功能固有）：文档需明确告知用户此事实（kp2a 官方文案同款表述）；写入时用 `ProtectedValue`（KDBX 内存保护字段）；
2. **内存驻留**：多库 = 多份解密模型驻留；锁屏不清内存为既有语义（快速解锁依赖），与 kp2a 一致；`close_database` 全清不变；
3. **不扩大持久化面**：子库密码不写 RecentFiles（不落 SM4 持久层）、不写日志（hilog 仅 iocKey/reason，不打 URL 密码）；
4. **主线程不持有明文密码**：Coordinator 组装凭证后即交 Worker 管线（既有约定）；
5. **DeviceIdentity 本地 UUID** 存 SettingsService（明文无害，仅设备过滤用途）。

---

## 7. 兼容性对照表（三端）

| 能力 | KeePass 桌面 | KeeAutoExec 插件 | kp2a | KeePassHO（本设计） |
|---|---|---|---|---|
| 根下 AutoOpen 组 | ✅ | ✅ | ✅ | ✅ M1 |
| Title/URL/UserName(密钥文件)/Password | ✅ | ✅ | ✅ | ✅ M1/M4 |
| `{DB_DIR}` `{ENV_DIRSEP}` 占位符 | ✅（SprEngine） | ✅ | ✅ | ✅ M1（最小实现） |
| 条目过期禁用 | ✅ | ✅ | ✅ | ✅ M1 |
| Enabled/Visible/Priority | ❌ | ✅ | ✅ | ✅ M1（Priority 排序 M3 生效） |
| IfDevice 设备 CSV | ❌ | ✅ | ✅ | ✅ M1/M4 |
| SkipIfNotExists（及旧名） | ❌ | ✅ | ✅ | ✅ M3 |
| 附件 KeyFile.bin | ❌ | ✅ | ✅ | P2 |
| Focus=Restore | ❌ | ✅ | ✅ | P2（默认 makeCurrent） |
| 多库并存+切换 | ❌（多实例多开） | — | ✅ | ✅ M2/M3 |
| 子库管理页 | — | ✅（插件 UI） | ✅ | ✅ M4 |

同一 .kdbx 三端往返注意：本设计生成的条目仅使用上表「KeePass 桌面 ✅ 或 KeeAutoExec ✅」的字段，保证桌面端可读。

---

## 8. 测试计划

**单元（ohosTest，随 M1/M2 交付）**

- `IfDeviceParser.test.ets`：解析/生成/判定全分支（≥12 例，含往返一致性）；
- `AutoOpenService.test.ets`：扫描/排序/启用判定（≥10 例）；
- `AutoOpenPathResolver.test.ets`：占位符/相对化（≥8 例）；
- `DatabaseRegistry.test.ets`：判重替换/切换/关最后库（≥6 例）。

**集成（真机，随 M3/M4/M5）**

1. 父库（AutoOpen 组 2 条目：本设备启用 / 未指定）解锁 → 2 子库自动打开，切换面板可见可切换；
2. 子库密码错误 → 单库失败 toast，父库与其余子库不受影响，不重试；
3. 环依赖 A→B→A → 无死循环（attempted 防线）；
4. 大子库（>4MB）×2 → Worker 串行队列逐个完成，父库期间可浏览；
5. 多库下：锁 → 快速解锁恢复；关 → 全部清理回 Index；保存当前库互不影响另一库；
6. PC 互操作：KeePass 桌面创建的 AutoOpen 库在真机自动打开；本机 M4 添加的子库在桌面 KeePass/KeeAutoExec 可识别；
7. 回归：既有解锁方式（密码/密钥文件/OTP/XC）、E2E 套件全绿。

---

## 9. 风险与缓解

| 风险 | 等级 | 缓解 |
|---|---|---|
| FileService 单槽改造波及面大（Password 1543 行 / DatabaseView 2931 行调用点） | 高 | M2 只动内部实现，API 不变 + 全量回归把关 |
| 多库内存压力（每库一份解密模型 + XML） | 中 | DatabaseLoadGuard CP1 单库上限已存在；Coordinator 记录总解压量，超过阈值告警并停止继续自动打开（提示手动打开） |
| Worker 单实例自动打开耗时 | 中 | 串行 + 逐库事件刷新，用户可先浏览父库；P2 可评估并行双 Worker |
| 结构化克隆传输多 Kdbx 实例稳定性 | 低 | reload/refresh 已有先例；M3 集成测试覆盖 |
| 单槽 AppStorage 键遗漏（isLocked/isLockScreen 判定等） | 中 | M2 盘点清单化（EntryAbility.isLockScreen、databaseView_currentGroupId），逐项确认 |
| IfDevice 与 PC 端设备名不可对应（PC 用机器名） | 低 | 属 KeeAutoExec 预期行为：CSV 多条目各设备一行，文档说明 |

---

## 10. 附录：kp2a → KeePassHO 实现映射表

| kp2a | KeePassHO 对应物 | 阶段 |
|---|---|---|
| `KeeAutoExecExt.GetAutoExecItems` / `AddAutoExecEntries` | `services/autoopen/AutoOpenService.ets` | M1 |
| `KeeAutoExecExt.GetIfDevice`/`BuildIfDevice`/`IsDeviceEnabled` | `services/autoopen/IfDeviceParser.ets` | M1 |
| `KeeAutoExecExt.ThisDeviceId` | `services/autoopen/DeviceIdentity.ets` | M1 |
| `SprEngine` + `{DB_DIR}` 编译 | `services/autoopen/AutoOpenPathResolver.ets`（最小占位符集） | M1 |
| `Kp2aApp._openDatabases/_currentDatabase/_childDatabases/_openAttempts` | `services/database/DatabaseRegistry.ets` | M2 |
| `Kp2aApp.LoadDatabase(makeCurrent)` / `TrySelectCurrentDb` | `Registry.put({makeCurrent})` / `setCurrent` | M2 |
| `SelectCurrentDbActivity.OpenAutoExecEntries` | `services/autoopen/AutoOpenCoordinator.ets` | M3 |
| `KeeAutoExecExt.AutoOpenEntry`（组装 CompositeKey） | Coordinator 内 `KdbxCredentials` 组装（复用 CredentialsService 策略链形态） | M3 |
| `SelectCurrentDbActivity`（切换页） | `components/DatabaseSwitcherSheet.ets` | M3 |
| `ConfigureChildDatabasesActivity` | `pages/ChildDatabases.ets` | M4 |
| `AddAutoOpenEntryForDatabase` / `TryMakeRelativePath` | M4 添加流程 + `AutoOpenPathResolver.makeRelative` | M4 |
| `GroupBaseActivity.UpdateChildDbInfo` 提示条 | DatabaseView 底部提示条 | M5 |
| `IsChildDatabase` 生物识别建议抑制 | `Registry.isChild` | M5 |
| `pref_database.xml` 设置入口 | `SettingDatabase.ets` | M5 |
