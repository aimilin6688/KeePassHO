# KeePassHO 导入格式扩展开发报告

> 依据：`docs/feature-gap-analysis.md` §3.9（导入/导出差距）、P0-3（更多导入格式）、P2-7（通用 CSV 列映射向导）
>
> 约束：**导入能力必须以面向接口方式扩展；上层 UI / 服务层（页面、ViewModel、Facade、ImportService、Registry）零改动，只允许新增实现与组合根注册行；CSV 类导入必须提供列映射向导；尽可能多地支持其他密码库的导入。**
>
> 报告日期：2026-10-26 | 基线分支：`dev`（cc4e99ae） | 工作分支：`docs/import-format-expansion`（worktree）
>
> **交付状态（2026-10-27 更新）：M1 已交付并合并 `dev`（merge `f61fca93`）；M2-1（Bitwarden/1Password/Dashlane/Proton Pass 四个固定表头 CSV 格式）与 M2-2（Keeper CSV record_type 按行解析 + Enpass CSV 40 列）已交付，详见 §十 实现进度。**

---

## 一、背景与目标

### 1.1 差距结论（引自 gap 分析并核实）

三大参考实现的导入能力与本项目对比：

| 能力 | KeePass 2.x | KeePassXC | KP2A | KeePassHO |
|---|---|---|---|---|
| 通用 CSV 导入（列映射向导） | ✅ | ✅（`gui/csvImport`） | ✅ | 🟡 有导入、无向导 |
| KeePass XML 导入 | ✅ | ✅ | ✅ | ✅ |
| Bitwarden JSON 导入 | ✅ | ✅ | ❌ | ✅ |
| 1Password（CSV/1PUX/OpVault） | ✅ | ✅（`OPUXReader/OpVaultReader`） | ❌ | ❌ |
| LastPass CSV | ✅ | ✅ | ❌ | ❌ |
| Chrome/Firefox/Edge CSV | ✅ | ✅ | ❌ | ❌ |
| Dashlane / Enpass / Keeper / Proton Pass 等 | ✅（90+ 格式） | ✅（Proton） | ❌ | ❌ |
| KeePass 1.x（KDB）导入 | ✅ | ✅（`KeePass1Reader`） | ✅（`KP2AKdbLibrary`） | ❌ |
| KDBX | ✅ | ✅ | ✅ | ➖（直接打开即"导入"，无需 handler） |

KeePassXC `src/format` 实测文件清单（本次已核实）：`KeePass1Reader`、`CsvParser/CsvExporter`、`OpVaultReader/OPUXReader`（1Password）、`ProtonPassReader`、`BitwardenReader`、`HtmlExporter`——即其导入广度主要由 **1Password、Proton Pass、Bitwarden、KDB、通用 CSV** 构成；KeePass 2.x 的"90+ 格式"依赖外部转换器/插件生态，移动端不必对标数量，应覆盖高频来源。

### 1.2 本报告目标

1. 梳理现有导入管线架构，找出阻断"多格式扩展"的结构性问题；
2. 给出**零上层改动**的接口化扩展设计（调度器 + 能力接口 + 交互桥）；
3. 给出 CSV 列映射向导的完整设计；
4. 给出逐格式实现规格与分阶段交付计划。

---

## 二、现有导入管线剖析

### 2.1 调用链（现状）

```
SettingDatabase.ets (pages/setting)
  └─ registerDefaultHandlers()                       // aboutToAppear，幂等
  └─ viewModel.getImportFormatOptions()              // 注册表驱动 → UI 下拉自动出现新格式
  └─ startImport(formatId)                           // formatId 仅用于文件选择器后缀过滤
      └─ LocationParam → 文件选择页 → onLocation
      └─ viewModel.executeImport(location)
          └─ ImportExportFacade.importToCurrentDatabase(location)
              └─ ImportService.import(filePath, storageType, config)
                  └─ registry.getImportHandler(扩展名)   // ★ 按扩展名路由
                      └─ handler.import(fileContent)      // IImportHandler
              └─ 合并到当前库根分组 → saveDatabase
```

现有 handler（`services/importExport/handlers/import/`）：

| Handler | 扩展名 | 格式 |
|---|---|---|
| `CsvImportHandler` | `.csv` | KeePass/KeePassXC 风格 CSV（固定表头 `Group,Title,UserName,Password,URL,Notes,TOTP,Icon,...`） |
| `XmlImportHandler` | `.xml` | KeePass XML |
| `BitwardenJsonImportHandler` | `.json` | Bitwarden 明文 JSON |

**有利条件**：UI 下拉选项完全由注册表驱动（`getSupportedImportFormats()`），Facade 对 `handler.import()` 返回的 `KdbxGroup` 做通用合并——这天然满足"新增实现即自动出现在 UI"的扩展模型。

### 2.2 阻断性问题（必须在设计中解决）

| # | 问题 | 位置 | 影响 |
|---|---|---|---|
| P-1 | **扩展名路由冲突**：`FormatHandlerRegistry.registerImportHandler()` 以扩展名为 Map key，同扩展名后注册者覆盖先注册者 | `FormatHandlerRegistry.ets:29-34` | 无法同时注册 Chrome CSV、LastPass CSV、通用 CSV（都是 `.csv`） |
| P-2 | **用户选择的 formatId 不下发**：UI 选中的格式只用于文件选择器后缀过滤，`ImportService` 只按扩展名找 handler | `ImportService.ets:37-40`、`SettingDatabase.ets:73-82` | 无法按"用户声称的来源"路由，只能靠内容识别 |
| P-3 | **CSV 解析器缺陷**：`content.split('\n')` 逐行处理 | `CsvImportHandler.ets:50` | ① CRLF 文件最后表头/字段带 `\r`；② 不支持引号内换行（LastPass `extra` 列常见多行内容）；③ 分隔符/编码不可配置 |
| P-4 | **无内容嗅探** | — | 同扩展名多来源无法区分 |
| P-5 | **无交互通道**：`IImportHandler.import()` 是纯数据进出 | `IImportHandler.ets:35` | 列映射向导无法在导入过程中向用户询问 |
| P-6 | 表头校验写死 KeePass 列名，必需列仅 `Title` | `CsvImportHandler.ets:75-97` | 浏览器 CSV（无 Title 列，用 name）直接报"缺少必需列" |

**结论**：`IImportHandler` 接口本身、调用链、注册表均**保留不动**；多格式共存问题用"族调度器"在接口实现内部消化（见 §4）。

---

## 三、目标格式清单与优先级

依据用户迁移来源的市占率排序（Chrome/Edge 系 > LastPass > 1Password > 浏览器其余 > Bitwarden CSV > Dashlane/Keeper/Enpass/Proton > 长尾）。

| 阶段 | formatId | 来源 | 载体 | 表头/结构签名 | 预估 |
|---|---|---|---|---|---|
| **P1** | `CHROME_CSV` | Chrome / Edge / Brave / Opera / Vivaldi | CSV | `name,url,username,password[,note]` | 共用 1 个 handler，1 人天 |
| **P1** | `FIREFOX_CSV` | Firefox | CSV | `url,username,password,httpRealm,formActionOrigin,guid,timeCreated,timeLastUsed,timePasswordChanged` | 1 人天 |
| **P1** | `LASTPASS_CSV` | LastPass | CSV | `url,username,password,extra,name,grouping,fav`（TOTP 藏在 `extra`） | 2 人天（多行引号单元格） |
| **P1** | `CSV`（升级） | 任意/未知来源 | CSV | 无法识别签名 → 列映射向导兜底 | 2 人天（向导页）+ 2 人天（映射引擎） |
| **P2** | `BITWARDEN_CSV` | Bitwarden | CSV | `folder,favorite,type,name,notes,fields,reprompt,login_uri,login_username,login_password,login_totp` | 1 人天 |
| **P2** | `ONEPASSWORD_CSV` | 1Password 8 | CSV | `Title,Url,Username,Password,OTPAuth,Notes` | 0.5 人天 |
| **P2** | `DASHLANE_CSV` | Dashlane 6+ | CSV | `title,url,username,password,note,category,otpSecret,lastModified` | 1 人天 |
| **P2** | `KEEPER_CSV` | Keeper | CSV | 首列 `record_type`（login/card/address/bankAccount/...），login 行含 `login_url,login_username,login_password,login_totp` | 2 人天（多 record_type 映射） |
| **P2** | `PROTONPASS_CSV` | Proton Pass | CSV | `name,url,email,username,password,totp,note[,vault]` | 1 人天 |
| **P2** | `ENPASS_CSV` | Enpass | CSV | 首列 `"Title","Category",...`（约 40 个固定列） | 1.5 人天 |
| **P2** | `ENPASS_JSON` | Enpass 6 | JSON | 顶层 `records[]` | 1 人天 |
| **P2** | `DASHLANE_JSON` | Dashlane | JSON | `credentials[]` | 1 人天 |
| **P2** | `PROTONPASS_JSON` | Proton Pass | JSON | 顶层 `encrypted, vaults, items`（明文导出） | 1 人天 |
| **P3** | `ONEPASSWORD_1PUX` | 1Password | ZIP（`.1pux`） | ZIP 内 `export.data`：JSON + OpData01（AES-CBC + HMAC-SHA256） | 4-5 人天（`@ohos.zip` + `cryptoFramework`） |
| **P3** | `OPVAULT` | 1Password（本地库目录） | 目录/ZIP | `band_*.js` + `profile.js` | 3-4 人天，低优先级 |
| **P3** | `KDB` | KeePass 1.x | 二进制（`.kdb`） | 签名 `03 D9 A2 9A`，v1；参考 KeePassXC `KeePass1Reader` 移植（AES 为主，Twofish 可选） | 2-3 人周 |
| **P3** | 长尾 CSV | RoboForm / Sticky Password / RememBear / mSecure / Myki / Norton / Kaspersky / Zoho Vault / Avira / True Key 等 | CSV | 各自固定表头 | **不写独立 handler**，仅向"签名库"追加数据行 + 预设映射；未知签名走通用向导。每种 0.5 人天 |

> 说明：
> - KDBX 不需要导入 handler——本项目本来就按数据库打开；"导入另一个 KDBX"等价于"打开后复制/合并"，属已有能力。
> - Bitwarden 加密 JSON（`account.encrypted.json`）需要用户 KDF 参数推导，体验复杂，列为 P3 可选项。
> - HTML 导出为导出侧能力，不在本报告范围（见 gap 分析 §3.9）。

---

## 四、总体设计：族调度器 + 能力接口 + 交互桥（零上层改动）

### 4.1 零改动约束的落实

**不动的文件（上层 UI / 服务层）**：

- `pages/setting/SettingDatabase.ets`
- `services/importExport/ImportExportViewModel.ets`
- `services/importExport/ImportExportFacade.ets`
- `services/importExport/service/ImportService.ets`
- `services/importExport/FormatHandlerRegistry.ets`（注册表本身零改动！）
- `services/importExport/handlers/IImportHandler.ets`（核心接口零改动！）

**允许的改动（全部为"新增实现"性质）**：

| 类型 | 内容 |
|---|---|
| 新增文件 | 调度器、嗅探服务、CSV 解析器、映射引擎、向导桥、各格式 handler、向导页面 |
| 组合根 | `services/importExport/index.ets`：`registerDefaultHandlers()` 中**替换 1 行**（`new CsvImportHandler()` → `new CsvFamilyDispatcherImportHandler()`），**追加 N 行注册**；导出新符号 |
| 路由表 | `resources/base/profile/router_map.json` 追加向导页路由（纯追加） |
| 资源 | `resources/base/element/string.json` 等追加字符串（纯追加） |

### 4.2 核心机制：族调度器（Dispatcher）

问题 P-1/P-2 的解法：**调度器本身就是一个普通的 `IImportHandler` 实现**，独占一个扩展名路由键；它内部持有该扩展名家族的全部成员 handler，通过内容嗅探分发。注册表、ImportService 因此完全无需感知多格式。

```
FormatHandlerRegistry（零改动）
  '.csv'  → CsvFamilyDispatcherImportHandler      ★ 占据扩展名键，实现 IImportHandler
  '.json' → JsonFamilyDispatcherImportHandler     ★ 同上
  '.xml'  → XmlImportHandler（原样）
  '.kdb'  → KdbImportHandler（P3）
       │
       │ 内部子注册表（Dispatcher 构造函数中组装，与主注册表无关）
       ▼
  ┌─ CsvFamilyDispatcher ──────────────────────────────────────┐
  │  sniff(content) → 置信度评分 → 选定成员                      │
  │                                                            │
  │  ├─ ChromeCsvImportHandler        (ISniffableImport)       │
  │  ├─ FirefoxCsvImportHandler       (ISniffableImport)       │
  │  ├─ LastPassCsvImportHandler      (ISniffableImport)       │
  │  ├─ BitwardenCsvImportHandler     (ISniffableImport)       │
  │  ├─ OnePasswordCsvImportHandler   (ISniffableImport)       │
  │  ├─ DashlaneCsvImportHandler      (ISniffableImport)       │
  │  ├─ KeeperCsvImportHandler        (ISniffableImport)       │
  │  ├─ ProtonPassCsvImportHandler    (ISniffableImport)       │
  │  ├─ EnpassCsvImportHandler        (ISniffableImport)       │
  │  ├─ GenericCsvImportHandler       (原 CsvImportHandler 迁移，│
  │  │                                  未知签名时走列映射向导)   │
  │  └─ （长尾来源：签名库数据行 + 预设映射，不新增类）            │
  └────────────────────────────────────────────────────────────┘
```

**UI 呈现**：`getSupportedImportFormats()` 按 formatId 去重，调度器在 UI 下拉中表现为一项，如 `CSV（自动识别来源）`、`JSON（自动识别来源）`。用户选定后仅用于文件选择器后缀过滤（现状行为），真正路由靠嗅探——与现状语义一致，用户心智负担反而更低。

> 备选方案（不采纳）：让每个来源 handler 直接注册 `.csv` 到主注册表——后注册者覆盖先注册者（P-1），且 UI 选中的来源不下发（P-2），实际路由结果与用户选择脱节，不可控。调度器方案将"多来源"封装在一个 `IImportHandler` 实现内部，是唯一满足零改动约束的形态。

### 4.3 新增接口与数据模型（面向接口的核心）

全部为新文件，位于 `services/importExport/` 下。遵循 ArkTS 严格模式：显式 class/interface、无 any、无对象字面量类型、无索引签名（用 `Map`/`Record` + 显式类型）。

```ts
// contracts/ISniffableImport.ets —— 能力接口①：可嗅探
export interface ISniffableImport {
  /** 对文件内容做置信度评分（0-100），≥70 视为可接管 */
  sniff(content: Uint8Array): number;
}

// contracts/IColumnMappingImport.ets —— 能力接口②：支持列映射（CSV 家族）
export interface IColumnMappingImport {
  /** 解析表头与前 N 行，生成向导预览数据 */
  buildMappingPreview(content: FileContentInfo): CsvMappingPreview;
  /** 基于同义词字典 + 启发式，给出建议映射 */
  suggestMapping(preview: CsvMappingPreview): ColumnMappingProfile;
  /** 按用户确认后的映射执行导入 */
  importWithMapping(content: FileContentInfo, profile: ColumnMappingProfile): Promise<KdbxGroup>;
}
```

```ts
// model/CsvMappingModels.ets —— 向导数据模型（显式 class）
export enum TargetField {
  Skip = 0, Group, Title, Username, Password, Url,
  Notes, Totp, Tags, Icon, ExpiresTime, Custom
}

export class ColumnMappingItem {
  sourceColumnIndex: number = -1;
  sourceColumnName: string = '';
  targetField: TargetField = TargetField.Skip;
  protectedField: boolean = false;      // 导入后是否为保护字段
  customFieldName: string = '';          // targetField == Custom 时生效
}

export class ColumnMappingProfile {
  formatId: string = '';                 // 归属来源
  items: ColumnMappingItem[] = [];       // 每源列一条
  firstRowAsHeader: boolean = true;
  delimiter: string = ',';
  encoding: string = 'utf-8';
  importTargetGroupName: string = '';    // 导入到哪个分组（空=根分组）
}

export class CsvMappingPreview {
  headers: string[] = [];
  sampleRows: string[][] = [];           // 前 20 行
  suggestedProfile: ColumnMappingProfile | null = null;
  detectedFormatName: string = '';
  totalRowEstimate: number = 0;
}
```

能力接口与 `IImportHandler` 的关系：**成员 handler 只需实现 `ISniffableImport`（识别）+ 业务方法**；是否实现 `IColumnMappingImport` 由格式决定（固定表头格式可不实现，通用 CSV 必须实现）。调度器用 `instanceof` 探测能力——这是纯运行时多态，不触碰核心接口。

```ts
// csv/CsvParser.ets —— 状态机 CSV 解析器（新文件，替换 split('\n') 方案）
// 要点：① 引号内分隔符/换行原样保留；② "" 转义；③ CRLF/CR 归一；
//      ④ 可配置分隔符（, ; \t |）；⑤ UTF-8 → GBK 编码回退（util.TextDecoder）；
//      ⑥ BOM 剥离；⑦ 流式逐记录回调，避免大文件全量驻留内存
export class CsvParser {
  parse(content: Uint8Array, options: CsvParseOptions): CsvParseResult;
  // CsvParseOptions: delimiter / encoding / firstRowAsHeader / maxPreviewRows
}

// sniffing/FormatSignatureLibrary.ets —— 签名库（数据驱动）
// 每条签名 = 列名集合 + 精确/子集匹配策略 + formatId + 预设映射（ColumnMappingProfile）
// 长尾格式（RoboForm/mSecure/Norton/...）只在此追加数据行，不新增类
export class FormatSignatureLibrary {
  matchCsvHeaders(headers: string[]): SignatureMatchResult;   // 置信度 + formatId
  matchJsonStructure(topLevelKeys: string[]): SignatureMatchResult;
}

// sniffing/ImportWizardBridge.ets —— 交互桥（问题 P-5 的解法）
// handler 在 import() 内 await bridge.requestColumnMapping(preview)，
// 桥通过 NavigationManager.pushPathByName 打开向导页（新路由），
// 向导页完成后 resolve(profile)、取消/锁库时 reject。
export class ImportWizardBridge {
  requestColumnMapping(preview: CsvMappingPreview): Promise<ColumnMappingProfile>;
  // 内部：EventBus 订阅向导结果 → resolve/reject；导航 push；页面 aboutToDisappear 时 reject
}
```

**交互桥的关键正确性约束**：

1. 向导页是新增路由（`router_map.json` 追加 `ColumnMappingWizard`），通过 `NavigationManager` 推栈，与现有导航体系一致；
2. 用户取消 → `reject(new ImportError(CANCELLED))` → Facade 现有 `handleError` 返回失败 → UI toast"导入已取消"，**无需改任何上层代码**；
3. 锁库/页面销毁 → 向导页 `aboutToDisappear` 中发结束事件 → 桥 reject，防止 Promise 永久挂起；
4. 桥内部用 `EventBus`（项目既有 emitter 封装）收发结果，遵循"订阅方 aboutToDisappear 中 off"的项目约定。

### 4.4 调度器工作流

```
Dispatcher.import(fileContent):
  1. content 前几 KB 做嗅探（不必全文）
  2. 遍历成员（均实现 ISniffableImport），取最高分：
       score >= 70  → 选定成员 → 成员.import(fileContent)
  3. 全部 < 70（未知来源）：
       a. 若 Dispatcher 自身实现 IColumnMappingImport（CSV 族）：
          preview = buildMappingPreview()
          策略开关（SettingsService，默认开）：
            - "总是显示向导" → bridge.requestColumnMapping(preview)
            - 否则直接采用 suggestMapping() 的建议映射导入
       b. JSON 族 → 明确报 INVALID_FILE_FORMAT（无法启发式映射）
  4. 成员导入抛 ImportError → 原样上抛（Facade 统一处理）
```

**已知来源的确定性**：Chrome/Firefox/LastPass 等固定表头格式命中签名后**直接导入、不弹向导**（签名即等价于映射）；用户仍可通过设置项"CSV 导入总是显示列映射向导"强制预览确认。通用/未知来源才默认弹向导。

### 4.5 嗅探与消歧规则

- 表头归一化：剥 BOM、去引号、trim、小写、CRLF→LF；
- 匹配策略：**列名集合精确匹配（100 分）** > 已知列集的子集（70 分）> 前缀序列匹配（60 分）> 不匹配（0 分）；
- 典型消歧：
  - Chrome `name,url,username,password` vs Proton Pass `name,url,email,username,password,totp,note`：前者是后者前缀但列集不同——用**完整列集匹配**区分，选中 user 文件后以全集签名定胜负（Proton 含 `totp/email` 列 → 100 分；Chrome 精确四列 → 100 分；仅当文件表头同时命中两者时取列数多的）；
  - KeePass/KeePassXC CSV（`Group,Title,UserName,Password,URL,Notes,...`）→ `GenericCsvImportHandler` 的签名之一（保持现状行为兼容）；
- JSON 嗅探：解析顶层键——`folders+items`→Bitwarden；`records`→Enpass；`vaults+items`→Proton；`credentials`→Dashlane；
- 二进制嗅探：魔数（`.kdb` = `03 D9 A2 9A`；`.1pux` = ZIP `PK` + 内含 `export.data`）。

---

## 五、CSV 列映射向导设计

### 5.1 页面流程（新增 `ColumnMappingWizardPage`，4 步）

```
Step 1 预览       表格展示前 20 行；显示识别结果（"未识别来源"/"疑似 LastPass"）；
                  选项：首行是否表头、分隔符（自动检测可改）、编码（UTF-8/GBK）
Step 2 映射       每个源列一行：源列名 → 目标字段下拉（分组/标题/用户名/密码/URL/
                  备注/TOTP/标签/图标/过期时间/自定义[名称输入]/跳过）；
                  目标字段默认取建议映射（同义词字典：login→Username、pwd→Password、
                  site/website/link→URL、otp/totp/one-time→Totp…）
Step 3 选项       导入到指定分组（默认按来源名建分组，如 "LastPass 导入"）；
                  密码列是否保护字段（默认是）；跳过完全空行
Step 4 校验确认   校验：至少映射 Title/Username/Password 之一，否则以 URL/用户名兜底生成标题；
                  冲突提示（两个源列映射到同一目标字段）；完成后 resolve(profile)
```

### 5.2 数据流（零上层改动的交互闭环）

```
Dispatcher.import(fileContent)                       [UI 正在 await viewModel.executeImport]
  → GenericCsvImportHandler.import(fileContent)
    → preview = buildMappingPreview(fileContent)
    → profile = await ImportWizardBridge.requestColumnMapping(preview)   ★ 挂起等待用户
        → NavigationManager.pushPathByName('ColumnMappingWizard', preview)
        → 用户四步操作
        ← EventBus 事件：完成(profile) / 取消 / 页面销毁
    → importWithMapping(fileContent, profile)
  → 返回 KdbxGroup → Facade 现有合并+保存逻辑 → UI toast 导入成功
```

整个过程中 `SettingDatabase.ets`、ViewModel、Facade、ImportService **一行不改**——它们只是在 `await` 一个耗时更长的 Promise，向导页作为普通路由页面推入导航栈，完全符合现有页面管理模型。

### 5.3 列映射引擎（`CsvColumnMappingEngine`，新文件）

职责：把 `(CsvParseResult × ColumnMappingProfile)` 生成 `KdbxGroup`：

- 目标字段写入对应 KdbxEntry 字段；`Custom` 目标写入 `entry.fields.set(customFieldName, value)`；
- TOTP 列规范化：裸 Base32 密钥 / `otpauth://` URI → 统一写入 `otp` 字段（复用 `TotpService` 已有解析，兼容 5 种字段格式）；
- `Group` 目标支持 `/` 分层（复用现有 `getOrCreateGroup` 逻辑，迁移进引擎）；
- 标题兜底链：Title → Username → URL 域名 → `条目 N`；
- 每行独立 try/catch 计数，容忍脏行（汇总"成功 N 条 / 跳过 M 行"）。

**固定表头格式复用该引擎**：Chrome/LastPass 等 handler 只需提供"预设映射 Profile"（签名库中随签名定义），解析后调用引擎同一代码路径——这就是"新增一个格式 = 新增一条签名 + 一份预设映射"的落地方式。

---

## 六、逐格式实现规格（要点摘要）

| 格式 | 关键映射 | 特殊处理 |
|---|---|---|
| Chrome/Edge/Brave/Opera | name→Title, url→URL, username→Username, password→Password, note→Notes | iOS 版 Chrome 导出表头一致；合并进"浏览器导入"分组；无 TOTP |
| Firefox | url→URL, username→Username, password→Password；timePasswordChanged→条目 times | `httpRealm`/`formActionOrigin` 追加到 Notes；无标题列 → 以域名生成 Title |
| LastPass | name→Title, url→URL, username/password 直映, grouping→Group, extra→Notes | `extra` 含多行文本与 `TOTPTimeOut`/otpauth 内容：解析出 TOTP 写入 otp 字段，剩余文本入 Notes；`fav=1` → FAVORITE_TAG（项目已有标签扩展语义） |
| Bitwarden CSV | folder→Group, name→Title, login_uri/username/password/totp 直映, notes, fields→自定义字段 | `fields` 为 `name: value; ...` 格式需拆分；`favorite=1` → 标签；type 2/3（卡/身份）转安全笔记式条目 |
| 1Password CSV | Title, Url, Username, Password, OTPAuth, Notes | OTPAuth 为 otpauth URI 或裸密钥，统一走 TotpService 规范化 |
| Dashlane CSV | title,url,username,password,note,category→Group,otpSecret→TOTP | lastModified→times.lastModificationTime |
| Keeper CSV | 首列 record_type 分派：login→常规条目；card/address/bankAccount→模板条目（项目已有 20+ 模板体系可对位）；login_totp→TOTP | 自定义列 `record_type` 之后按类型偏移，需按行类型解析；`folder`→Group |
| Enpass CSV | Title,Category→Group,Login→Username,Password,TOTP Secret,URL,Note + 大量自定义列（Email/Phone/...→自定义字段） | 定长约 40 列，按列名而非位置映射 |
| Enpass JSON | `records[]`：title/category/login/password/totp/url/note/fields | 6.x JSON 结构，`fields` 数组逐项入自定义字段 |
| Proton Pass | name,url,email→自定义字段或 Username 兜底,username,password,totp,note,vault→Group | CSV 与 JSON 双格式共享映射表 |
| Dashlane JSON | `credentials[]`：login/domain/password/note/otpSecret；`transactions[]` 忽略 | 顶层多集合合并导入 |
| 1Password 1PUX | ZIP→`export.data`(JSON)：`accounts[].attrs` + `items[]`；每个 item 的 `details` 为 OpData01 密文 | OpData01 = HMAC-SHA256 校验 + AES-256-CBC；`@ohos.zip` 解压 + `cryptoFramework` 解密；附件（`files[]`）写入条目附件；P3 |
| KDB（KeePass 1.x） | 扁平 group/entry；密码、URL、备注；4 个时间字段；图标 | 参考 `KeePass1Reader`（KeePassXC）与 KP2A `KP2AKdbLibrary` 语义；AES 主，Twofish 可选后置；P3 |

---

## 七、测试方案

1. **Fixture 单元测试**（Hypium，`entry/src/ohosTest/ets/test/`）：
   - 每格式 1 份真实导出样本（脱敏）+ 1 份畸形样本（截断/坏编码/空文件/引号不闭合）；
   - 嗅探用例：每签名精确匹配、CRLF/BOM 变体、Chrome vs Proton 消歧、未知表头；
   - CSV 解析器：多行单元格、`""` 转义、`;`/`\t` 分隔符、GBK 编码；
   - 映射引擎：目标字段全覆盖、标题兜底链、TOTP 规范化（5 种字段格式）。
2. **交互桥测试**：完成/取消/页面销毁三条路径，确认 Promise 均 settle 且无泄漏（EventBus off）。
3. **E2E**（`docs/e2e` 基础设施扩展）：Chrome CSV → 导入 → 与 KeePassXC 打开同一库互操作回归（条目数、字段、TOTP 码一致性）。
4. **零改动回归**：`git diff --stat` 校验受保护文件清单（§4.1）为空。

---

## 八、风险与缓解

| 风险 | 缓解 |
|---|---|
| 向导 Promise 挂起（用户退出页面/锁库/应用切后台） | 向导页 `aboutToDisappear` 必发结束事件；桥 reject(CANCELLED)；与 `LockScreenService` 联动验证 |
| 大 CSV 全量解析内存峰值 | `CsvParser` 流式逐记录回调；嗅探只读前 4KB |
| 签名误判（用户改过导出表头） | 置信度阈值 70；未知走向导；设置项"总是显示向导"；导入结果 toast 展示识别到的来源，用户可感知 |
| GBK/其他编码乱码 | UTF-8 优先，解码失败自动回退 GBK（`util.TextDecoder`），向导 Step1 可手动切换 |
| 调度器成为单点 | 调度器仅做"嗅探+委托"，无业务逻辑；成员 handler 单测独立覆盖 |
| 1PUX/KDB 工期不可控 | 排 P3，前置验证 `@ohos.zip`/`cryptoFramework` 能力后立里程碑 |

---

## 九、交付计划

| 里程碑 | 内容 | 人日 | 状态 |
|---|---|---|---|
| M1（P1，2.4.x） | 契约与模型文件、`CsvParser`、签名库、映射引擎、交互桥、向导页；`CsvFamilyDispatcher` + Chrome/Edge/Firefox/LastPass/Generic（原 CSV 行为兼容）；测试与回归 | 10-12 | ✅ 已交付（`f61fca93` 合并 dev） |
| M2-1 | Bitwarden CSV、1Password CSV、Dashlane 6+、Proton Pass 四个固定表头 CSV 格式（TDD） | 2-3 | ✅ 已交付（见 §10.5 验证记录） |
| M2-2 | Keeper CSV（record_type 按行解析）+ Enpass CSV（40 列） | 2-3 | ✅ 已交付（见 §10.5 验证记录） |
| M2-3 | `JsonFamilyDispatcher`（Bitwarden JSON 迁入）+ JSON 格式（Proton Pass JSON 等） | 2-3 | ✅ 已交付（见 §10.5 验证记录） |
| M2-4 | 列映射向导（L-1~L-7）+ 长尾签名库首批（RoboForm/mSecure/Norton/Sticky Password） | 4-5 | ⬜ 未启动 |
| M3（P3，按需） | 1PUX（OpData01）、OpVault、KDB 移植 | 25-35 | ⬜ 未启动 |

M1 完成即达成 gap 分析 P0-3 首批目标（浏览器 + LastPass + 通用向导），M2 达成 P2-7 的"覆盖长尾导入格式"。

---

## 十、实现进度（2026-10-27 更新）

### 10.1 已完成

**M1（commit `4eefd0b7`，merge `f61fca93`）**：

1. `csvimport/CsvParser.ets` — RFC4180 宽松解析（引号转义、未闭合引号、跨行字段）
2. `csvimport/ColumnNameMapper.ets` — KeePass 同义词精确匹配 + 模糊子串匹配
3. `csvimport/CsvColumnMappingEngine.ets` — Profile 列映射（缺失必需列抛 `INVALID_CSV_HEADER`）+ 建议映射
4. `csvimport/CsvImportModels.ets` — `CsvTargetField` 等模型
5. `csvimport/ISniffableImport.ets` — 嗅探能力接口
6. `handlers/import/BaseCsvImportHandler.ets` — 基类（时间戳/标签/hostname 解析、`getOrCreateGroup`、标题兜底链）
7. `handlers/import/CsvFamilyDispatcherImportHandler.ets` — `formatId 'CSV'` 族调度器（嗅探阈值 70，未识别回落 Generic）
8. `handlers/import/{Chrome,Firefox,LastPass,Generic}CsvImportHandler.ets` — 四个格式 handler
9. `index.ets` 组合根注册 dispatcher（受保护文件中唯一允许的注册改动）
10. TOTP 列导入：otpauth:// 原文存 `otp`（protected）；裸密钥转 `key=`（KeeOtp 兼容）
11. Firefox 导入 httpRealm/timeCreated/timePasswordChanged
12. LastPass `grouping` 支持 `\` 与 `/` 两种嵌套分隔符
13. 新增 8 个测试套件共 114 用例 + `List.test.ets` 注册

**M2-1（本迭代，TDD）**：

14. `BaseCsvImportHandler` 扩展：`applyRowExtensions(entry, headerRow, row)` 行级扩展钩子（默认空实现）+ `findHeaderIndex` 静态辅助
15. `handlers/import/BitwardenCsvImportHandler.ets` — favorite=1 → `FAVORITE_TAG` 标签；fields 列按「name: value; …」拆自定义字段；type 2/3/4 统一映射
16. `handlers/import/OnePasswordCsvImportHandler.ets` — `OTPAuth` 特征列消歧（避免误判含 Notes 的 KeePass 风格导出）
17. `handlers/import/DashlaneCsvImportHandler.ets` — 特征列 `category/otpsecret/lastmodified` + 排除列 `group/notes`（本应用导出含 Last Modified，不排除会丢 Group/Notes 映射）
18. `handlers/import/ProtonPassCsvImportHandler.ets` — email 兜底：UserName 为空时作 UserName，否则存自定义字段 `Email`（对齐 KeePassXC ProtonPassReader 语义）
19. 调度器 family 新序：LastPass → Bitwarden → ProtonPass → Dashlane → OnePassword → Firefox → Chrome（两两冲突已由特征列/排除列消歧）
20. 新增 4 个测试套件共 52 用例 + 调度器消歧用例（含 §4.5 Chrome 表头超集判 Proton、Dashlane vs 1Password 互斥、本应用导出回归）

**M2-2（本迭代，TDD）**：

21. `handlers/import/KeeperCsvImportHandler.ets` — 首列 `record_type` 嗅探特征；login 行全字段映射（folder→Group、login_url/username/password/totp）；非 login 行（card/bankAccount 等）列按行类型偏移：`login_*` 列值按原表头名转自定义字段（login_password 受保护）+ 清空对应标准字段 + `Record Type` 标记（保留原始大小写）
22. `handlers/import/EnpassCsvImportHandler.ets` — 首两列 `Title,Category` 嗅探特征；约 40 固定列按列名映射（Category→Group、Login→UserName、OTP Secret/TOTP Secret→TOTP）；其余非空列按原表头名转自定义字段，列名含 password/cvv/ssn/secret 的受保护；字面 `Group` 列为普通自定义字段（分组由 Category 承载，避免双 Group 歧义）
23. 调度器 family 新序：LastPass → Bitwarden → ProtonPass → Dashlane → OnePassword → **Keeper → Enpass** → Firefox → Chrome（Keeper 首列 record_type、Enpass 首两列 Title,Category 均为唯一特征，与既有 handler 无冲突）
24. 新增 2 个测试套件共 34 用例 + 调度器 2 个检测用例（Keeper/Enpass 格式识别）

**M2-3（本迭代，TDD）**：

25. `handlers/import/JsonFamilyDispatcherImportHandler.ets` — `formatId 'JSON'` 族调度器：`detectFormatId(content)` 按顶层 `vaults` → PROTONPASS_JSON、`items` → BITWARDEN_JSON 嗅探（folders 缺省不影响 Bitwarden 识别，兼容 folder-less 导出）；未知结构报 `INVALID_FILE_FORMAT`，非法 JSON 报 `INVALID_JSON_FORMAT`；`.json` 扩展名路由由其接管（`index.ets` 组合根 BitwardenJson 注册替换，BitwardenJsonImportHandler 文件零改动）
26. `handlers/import/ProtonPassJsonImportHandler.ets` — 以 KeePassXC `ProtonPassReader.cpp` 为权威参考：`vaults`（vaultId→{name,items[]}）内嵌条目优先，顶层 `items`（shareId/vaultId 解析 vault 名建组）仅在 vaults 无内嵌条目时回落；`encrypted:true` → `UNSUPPORTED_FORMAT`，零条目 → `FILE_EMPTY`
27. Proton Pass JSON 字段映射：login（itemUsername/itemEmail 兜底/password(protected)/totpUri→applyTotp/urls[0]→URL 其余 `KP2A_URL_1..N`）、creditCard（cardholder→UserName 语义、number→UserName、verificationNumber→Password(protected)、card_* 自定义字段）、wifi（ssid/security）、sshKey（ssh_public_key/ssh_private_key(protected)）、未知类型（Notes 加 `Unknown entry type '<原样 type>'` 前缀 + `content_*` 固定 13 字段名转自定义字段，urls 数组跳过）；extraFields（text/totp 明文、hidden 受保护、空值跳过、字段名冲突加 `_N` 后缀）；pinned → `FAVORITE_TAG`；state==2 → expires；秒级时间戳 → times
28. 新增 2 个测试套件共 33 用例（ProtonPassJson 20 + JsonFamilyDispatcher 13）+ `Index.test.ets` 断言改 'JSON'（3 处）

### 10.2 实现差异（相对本报告原设计）

1. 契约与模型实际落在 `csvimport/` 单目录（原设计拆 `contracts/`/`model/`/`csv/`/`sniffing/`/`wizard/`），`ISniffableImport` 即契约
2. 长尾签名库 `FormatSignatureLibrary` 未在 M1/M2-1 实现（推迟至 M2-4 向导一并落地）
3. `IColumnMappingImport` 交互桥未实现（依赖向导页，推迟至 M2-4）
4. TOTP 存储格式：统一 `otp` 字段（otpauth 原文 protected / `key=secret`），非独立 KeeOtp 字段
5. Bitwarden favorite 语义用 `KdbxUtils.FAVORITE_TAG`（`__FAVORITE__`）标签，与旧 `BitwardenJsonImportHandler` 的 `Favorite` 自定义字段不一致（历史遗留，后续统一）
6. Keeper/Enpass 非 login 记录不自动对位模板条目（本报告 §六「card→模板条目」）：preset 模板体系（credit_card/bank_card/id_card 等）字段名与 Keeper 列偏移、Enpass 列名无权威映射语义，自动对位属猜测；非登录行以自定义字段无损保留 + `Record Type` 标记（Keeper），后续可在模板体系稳定后补充对位规则
7. Proton Pass JSON `itemEmail` 兜底字段名对齐 ProtonPass CSV（自定义字段 `Email`），非 KeePassXC 的 `login_email`——与 CSV 族共享映射语义，减少同一产品两种导出间的字段名差异
8. 未知类型 `content_*` 字段名采用固定 13 个白名单（CONTENT_FIELD_NAMES），非 KeePassXC 的全字段动态展开；urls 数组跳过（已有 `KP2A_URL_*` 语义承载）
9. JSON 调度器 import 双重解析（`detectFormatId` 一次 + 成员 handler 一次）：换取 `BitwardenJsonImportHandler` 零改动；`.json` 文件典型 <10MB，二次解析开销可接受
10. JSON 族无通用回落 handler（CSV 族回落 Generic）：JSON 长尾格式无稳定"通用"结构，未知结构明确报 `INVALID_FILE_FORMAT` 引导用户确认文件来源

### 10.3 缺失项（对应原设计，均属 M2-4 向导）

- L-1 列映射向导页面 `ColumnMappingWizardPage`
- L-2 `ImportWizardBridge` 交互桥
- L-3 router_map 注册
- L-4 签名库 `FormatSignatureLibrary`（RoboForm/mSecure/Norton/Sticky Password 首批）
- L-5 建议映射 UI 呈现（`buildSuggestedMapping` 已就绪）
- L-6 列映射人工修正
- L-7 向导结果回填导入
- L-8~L-11 向导测试

### 10.4 未启动

M2-4（向导 + 签名库）、M3（1PUX/OpVault/KDB）。

### 10.5 验证记录

| 日期 | 范围 | 结果 |
|---|---|---|
| 2026-10-26 | M1 新增 8 套件 | 114/114 真机通过 |
| 2026-10-26 | M1 回归（importExport 既有套件） | 89/89 通过 |
| 2026-10-26 | dev 完整套件（M1 合并后） | 2974 用例：2909 pass；65 失败全部为 WebDAV/S3/SFTP 测试连接失败（环境性，需本地服务器） |
| 2026-10-27 | M2-1 新增（4 handler + 调度器消歧） | 83/83 真机通过（Mate 60 Pro+，`aa test -s class` 5 套件） |
| 2026-10-27 | M2-1 回归（CSV 全家 + 编排层 + 注册表 15 套件） | 208/208 通过 |
| 2026-10-27 | M2-2 新增（2 handler + 调度器检测） | 53/53 真机通过（Mate 60 Pro+，`aa test -s class` 3 套件） |
| 2026-10-27 | M2-2 回归（M2-1 4 套件 + CSV 全家 8 套件） | 178/178 通过 |
| 2026-10-27 | M2-3 新增（ProtonPassJson 20 + JsonFamilyDispatcher 13） | 33/33 真机通过（Mate 60 Pro+） |
| 2026-10-27 | M2-3 组合回归（JsonFamilyDispatcher + importExportIndex + BitwardenJson） | 50/50 通过（含 `.json` 路由改 'JSON' 断言） |
| 2026-10-27 | M2-3 CSV 全家回归（调度器 + 10 CSV handler + TotpHelper + Facade 12 套件） | 156/156 通过 |
| 2026-10-27 | dev 完整套件（M2-3 收尾） | 3107 用例：3042 pass；65 失败全部为 WebDAV/S3/SFTP/FTP 测试连接失败（环境性，需本地服务器），import/export 相关零失败 |

受保护文件（附录 A）在 M1/M2-1/M2-2 中 diff 均为空；`index.ets` 组合根为唯一注册改动（M1 完成，M2-1/M2-2 零改动——新 handler 由 dispatcher 内部注册）。

---

## 附录 A：零改动文件清单（受保护，验收时 diff 必须为空）

```
entry/src/main/ets/pages/setting/SettingDatabase.ets
entry/src/main/ets/services/importExport/ImportExportViewModel.ets
entry/src/main/ets/services/importExport/ImportExportFacade.ets
entry/src/main/ets/services/importExport/service/ImportService.ets
entry/src/main/ets/services/importExport/FormatHandlerRegistry.ets
entry/src/main/ets/services/importExport/handlers/IImportHandler.ets
entry/src/main/ets/services/importExport/handlers/IExportHandler.ets
```

## 附录 B：新增文件清单（✅ 已交付 / ⬜ 待实现）

```
entry/src/main/ets/services/importExport/
  csvimport/ISniffableImport.ets                        ✅（M1，契约）
  csvimport/CsvImportModels.ets                         ✅（M1）
  csvimport/CsvParser.ets                               ✅（M1）
  csvimport/ColumnNameMapper.ets                        ✅（M1，KeePass 同义词库）
  csvimport/CsvColumnMappingEngine.ets                  ✅（M1，含 Profile 引擎）
  sniffing/FormatSignatureLibrary.ets                   ⬜（M2-4）
  wizard/ImportWizardBridge.ets                         ⬜（M2-4）
  handlers/import/CsvFamilyDispatcherImportHandler.ets  ✅（M1；M2-1 扩 family 至 7 handler）
  handlers/import/BaseCsvImportHandler.ets              ✅（M1；M2-1 加 applyRowExtensions 钩子）
  handlers/import/GenericCsvImportHandler.ets           ✅（M1）
  handlers/import/ChromeCsvImportHandler.ets            ✅（M1）
  handlers/import/FirefoxCsvImportHandler.ets           ✅（M1）
  handlers/import/LastPassCsvImportHandler.ets          ✅（M1）
  handlers/import/BitwardenCsvImportHandler.ets         ✅（M2-1）
  handlers/import/OnePasswordCsvImportHandler.ets       ✅（M2-1）
  handlers/import/DashlaneCsvImportHandler.ets          ✅（M2-1）
  handlers/import/ProtonPassCsvImportHandler.ets        ✅（M2-1）
  handlers/import/KeeperCsvImportHandler.ets            ✅（M2-2）
  handlers/import/EnpassCsvImportHandler.ets            ✅（M2-2）
  handlers/import/JsonFamilyDispatcherImportHandler.ets ✅（M2-3；`.json` 路由接管）
  handlers/import/ProtonPassJsonImportHandler.ets       ✅（M2-3）
  ...（P3: OnePassword1PuxImportHandler / KdbImportHandler）
entry/src/main/ets/pages/importwizard/ColumnMappingWizardPage.ets   ⬜（M2-4，新页面 + router_map 追加）
```

## 附录 C：与 feature-gap-analysis.md 的条目映射

| gap 条目 | 本报告落点 |
|---|---|
| §3.9 CSV 导入（列映射向导） | §4.3/§5 全量设计 |
| §3.9 1Password / LastPass / Chrome/Firefox/Edge | §三 格式清单、§六 规格 |
| §3.9 Dashlane/Enpass/Keeper/Proton 等 | §三 P2 批次 |
| §3.9 KeePass 1.x 导入 | §三 P3 `KDB` |
| P0-3 更多导入格式 | M1+M2 |
| P2-7 通用 CSV 列映射向导 | §5 向导 + 签名库兜底 |
