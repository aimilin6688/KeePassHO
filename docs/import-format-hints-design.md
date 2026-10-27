# 导入格式提示（Import Format Discoverability）设计文档

> 状态：✅ 已交付（代码 + 护栏测试 + 真机回归全绿；三触达点手工 UI 走查待解锁库后确认，见 §九）
> 日期：2026-10-28
> 关联：`docs/import-format-expansion-report.md`（格式扩展主体已交付 M1~M2-6）

---

## 一、背景与问题

导入格式扩展完成后，应用实际支持的导入来源为：

- **CSV**：12 种已知来源（Bitwarden / Proton Pass / Keeper / Enpass 4 个特殊行 handler + 签名库 8 条纯数据格式 LastPass / Dashlane / 1Password / Firefox / Chrome / Norton / True Key / KeePass）+ 通用 CSV 兜底（列映射向导，任意 CSV 可导）；
- **JSON**：Bitwarden JSON / Proton Pass JSON 两种（无通用兜底，未识别即失败）；
- **XML**：KeePass 2.x XML。

但入口 UI（设置 → 数据库设置 → 导入）只有一个 `Select` 下拉，选项为注册表顶层 handler 的 `formatName`——用户只能看到 **"CSV" / "JSON" / "XML"** 三个抽象词：

1. **选文件前**：用户无从得知 CSV 支持 12 家来源、JSON 只支持 2 家，也不知道"未识别的 CSV 仍可通过列映射向导导入"这一兜底能力；
2. **选文件后**：嗅探 → 导入的中间过程是黑盒，成功 toast 只有"导入成功，共 N 条记录"，不体现按哪个格式导入；
3. **失败时**：JSON 未识别结构只收到一句通用"导入失败"，没有出路指引（改导出 CSV / 支持哪两种 JSON）。

## 二、目标与非目标

**目标**：在导入的三个触达时机向用户传达"支持哪些格式"：

| 时机 | 传达内容 | 载体 |
|---|---|---|
| 选文件前 | 下拉选项可读化 + 副标题摘要 + 完整格式清单 | 入口行副标题、「?」帮助半模态面板 |
| 选文件后 | 检测到的具体格式名 | 成功 toast（`导入成功（LastPass CSV），共 N 条记录`）；向导"未识别"宽慰提示 |
| 失败时 | 支持清单 + 出路建议 | JSON 未识别 → AlertDialog 内嵌清单与建议 |

**非目标**：

- 不改动 `IImportHandler` 接口签名（14 个 handler 与全部既有测试不受影响）；
- 不改动导入解析、嗅探、向导的既有逻辑（提示为旁路只读通道）；
- 不为品牌类格式名（'LastPass CSV' 等）做本地化（品牌名 + 通用扩展名中英通用），仅提示语句走 string 资源。

## 三、总体设计

### 3.1 单一数据源：ImportFormatCatalog

现状数据已全部数据驱动（签名库 8 条数据行 + handler `formatId`/`formatName` 只读字段）。新增**只读聚合** `ImportFormatCatalog`，从**真实 handler 实例**构建分组清单——与运行时注册表同源，天然防漂移：

```
ImportFormatCatalog.getCatalog(): ImportFormatGroupInfo[]
├─ CSV 组：CsvFamilyDispatcher.getSubFormats() → 12 已知 + GENERIC_CSV
├─ JSON 组：JsonFamilyDispatcher.getSubFormats() → BITWARDEN_JSON + PROTONPASS_JSON
└─ XML 组：XmlImportHandler（叶子 handler，直接包装）
```

两个 dispatcher 新增只读方法 `getSubFormats(): FormatInfo[]`（CSV：family + fallback；JSON：两个成员 handler）。无新 handler、无格式判定逻辑，纯数据读取。

**数据模型**：

```
ImportSubFormatInfo { formatId, formatName, note? }   // note: 如通用 CSV 的"任意 CSV 可导"
ImportFormatGroupInfo { groupId, groupLabel, description, formats[] }
```

组描述（description）走 i18n string 资源；组内格式名直接用 handler `formatName`。

### 3.2 检测结果透出：ImportSessionInfo 单例

检测逻辑在 dispatcher `import()` 内部完成，接口返回值只有 `KdbxGroup`。为避免改接口签名，新增轻量会话单例 `ImportSessionInfo`（`reset()` / `reportDetectedFormat(formatId, formatName)` / `detectedFormatId` / `detectedFormatName`）：

- `ImportExportFacade.importToCurrentDatabase()` 开头 `reset()`；
- `CsvFamilyDispatcher.import()`：命中已知格式 → report 该格式；经向导确认或回落直导 → report `GENERIC_CSV`；
- `JsonFamilyDispatcher.import()`：命中 → report 对应 JSON 格式；未识别不 report；
- `ImportExportViewModel.executeImport()` 成功后读取 → `lastImportFormatName` 供 toast 使用。

单线程 UI 导入流程内使用，无并发问题；与现有 `lastImportedCount` 同风格。

### 3.3 错误码透出

`Result.errorCode` 已由 Facade 保留（`handleError` 传 `error.code`），ViewModel 补 `lastErrorCode` 字段即可。UI 按「用户所选顶层格式 + 错误码」联合判定弹 JSON 引导弹窗：

```
selectedImportFormatId === 'JSON' && lastErrorCode ∈ { INVALID_FILE_FORMAT, INVALID_JSON_FORMAT }
→ AlertDialog（支持清单 + 建议）
否则 → 原 toast
```

以用户所选顶层格式为前置条件，可避免其他 handler 同错误码的误弹。

## 四、触达点详细设计

### 4.1 选文件前（入口）

**a. 下拉选项文案**：Select 选项显示 `displayImportFormatLabel(formatId)`：`CSV → CSV 文件`、`JSON → JSON 文件`、`XML → KeePass XML`（新 string 资源，未知 formatId 回落原 formatName）。仅改显示，不改 `FormatInfo`。

**b. 副标题**：导入行（`SettingDatabase.ets`）由单行 Row 改为 Column 双行——下行小字副标题，数量从 catalog 动态统计：

> `支持 %1$d 种 CSV 与 %2$d 种 JSON 来源，任意 CSV 可经列映射向导导入`

**c. 帮助面板**：导入行标题右侧加「?」图标 → `bindSheet` 半模态（复用 DatabaseView 的 bindSheet 模式）：

- 标题：`支持的导入格式`
- 按 catalog 三组渲染卡片：组名 + 组描述（i18n）+ 格式名 chips（Flex wrap）；
- CSV 组内 `GENERIC_CSV` 条目附注（note）：`未识别来源时进入列映射向导，手动指定列后仍可导入`。

数据全部来自 `viewModel.getImportFormatCatalog()`，新增格式 = 签名库加一行数据，UI 零改动。

### 4.2 选文件后（反馈）

**a. 成功 toast 带格式名**：`doImport` 成功且 `lastImportFormatName !== ''` 时：

> `导入成功（LastPass CSV），共 12 条记录`

无格式名（如 XML 导入未 report）时保持原文案。

**b. 向导"未识别"宽慰提示**：`ColumnMappingWizardPage` Step1 预览页在 `detectedFormatName === ''` 时，原"未识别来源"行下追加浅色提示行（新增 string，保留原 key 不动避免影响既有断言）：

> `支持任意 CSV：在"映射"步骤手动指定每列对应的字段即可`

### 4.3 失败时（JSON 引导弹窗）

条件命中时 `AlertDialog.show`：

- 标题：`无法识别该 JSON 文件`
- 正文：`当前支持 %1$s 与 %2$s 导出的 JSON 文件。可在来源应用中改导出为 CSV，导入时经列映射向导手动映射。`（两个格式名从 catalog JSON 组动态取，不硬编码）
- 按钮：`知道了`

## 五、文件清单

| 文件 | 动作 | 内容 |
|---|---|---|
| `services/importExport/catalog/ImportFormatCatalog.ets` | 新增 | 分组清单聚合（数据模型 + getCatalog） |
| `services/importExport/common/ImportSessionInfo.ets` | 新增 | 检测结果会话单例 |
| `handlers/import/CsvFamilyDispatcherImportHandler.ets` | 修改 | +`getSubFormats()`；import 内 report 检测结果 |
| `handlers/import/JsonFamilyDispatcherImportHandler.ets` | 修改 | +`getSubFormats()`；import 内 report 检测结果 |
| `ImportExportFacade.ets` | 修改 | +`getImportFormatCatalog()`；importToCurrentDatabase 开头 reset 会话 |
| `ImportExportViewModel.ets` | 修改 | +`lastImportFormatName` / `lastErrorCode` / `getImportFormatCatalog()` / `displayImportFormatLabel()` |
| `index.ets` | 修改 | 导出新类型 |
| `pages/setting/SettingDatabase.ets` | 修改 | 选项文案 + 副标题 + 「?」bindSheet 面板 + 成功 toast 带格式名 + JSON 失败弹窗 |
| `pages/importwizard/ColumnMappingWizardPage.ets` | 修改 | Step1 未识别宽慰提示行 |
| `resources/{base,zh_CN}/element/string.json` | 修改 | 新增约 14 条资源（见 §六） |
| `src/ohosTest/ets/test/importExport/ImportFormatCatalog.test.ets` | 新增 | 防漂移护栏（见 §七） |
| `src/ohosTest/ets/test/List.test.ets` | 修改 | 注册新套件 |

**零改动**：`IImportHandler` 接口、14 个 handler 的解析逻辑、签名库数据、向导流程逻辑、注册表。

## 六、字符串资源（base / zh_CN 成对新增）

| name | zh_CN |
|---|---|
| `import_format_label_csv` | CSV 文件 |
| `import_format_label_json` | JSON 文件 |
| `import_format_label_xml` | KeePass XML |
| `import_entry_format_hint` | 支持 %1$d 种 CSV 与 %2$d 种 JSON 来源，任意 CSV 可经列映射向导导入 |
| `import_format_help_title` | 支持的导入格式 |
| `import_format_group_csv_desc` | 支持以下来源导出的 CSV 文件 |
| `import_format_group_json_desc` | 仅支持以下来源导出的 JSON 文件 |
| `import_format_group_xml_desc` | KeePass 2.x 导出的 XML 文件 |
| `import_format_generic_note` | 未识别来源时进入列映射向导，手动指定列后仍可导入 |
| `import_wizard_unknown_format_hint` | 支持任意 CSV：在“映射”步骤手动指定每列对应的字段即可 |
| `import_success_with_format` | 导入成功（%1$s），共 %2$d 条记录 |
| `import_json_unsupported_title` | 无法识别该 JSON 文件 |
| `import_json_unsupported_message` | 当前支持 %1$s 与 %2$s 导出的 JSON 文件。可在来源应用中改导出为 CSV，导入时经列映射向导手动映射。 |
| `import_json_unsupported_confirm` | 知道了 |

## 七、测试计划（防漂移护栏）

新套件 `ImportFormatCatalog.test.ets`（真机 Hypium）：

1. **CSV 组 = 签名库 ∪ 特殊 handler ∪ Generic**：CSV 组 formatId 集合包含 `FormatSignatureLibrary.getAllSignatures()` 全部 formatId（8 条）、4 个特殊 handler formatId 与 `GENERIC_CSV`，且总数 = 签名数 + 5；
2. **JSON 组 = 两个 JSON handler**：`BITWARDEN_JSON` + `PROTONPASS_JSON`；
3. **XML 组 = XmlImportHandler**；
4. **catalog 与顶层注册表一致**：组 groupId 覆盖注册表全部导入 handler 的 formatId（CSV/JSON/XML），不多不少；
5. **ImportSessionInfo 行为**：reset 清空；report 后读取一致；二次 report 覆盖。

既有套件回归：`PresetCsvImportFormats`、`CsvFamilyDispatcherImportHandler`、`JsonFamilyDispatcherImportHandler`、`ImportFixtureFiles`（dispatcher 改动仅旁路 report，不影响断言）。

## 八、风险与对策

| 风险 | 对策 |
|---|---|
| catalog 实例化 dispatcher 构造成本 | dispatcher 构造仅组装轻量对象（无 I/O），每次 getCatalog 新建可接受；如需可缓存 |
| 全局单例残留状态（上次导入格式名串扰下次） | Facade 每次导入开头 reset；测试用例独立 reset |
| `INVALID_FILE_FORMAT` 非独占错误码 | 弹窗条件叠加「用户所选顶层格式 === JSON」前置判定 |
| 改动 `import_wizard_unknown_format` 旧值影响既有断言 | 保留原 key 原值，提示行走新 key |
| string 资源漂移（base/zh_CN 不成对） | 新增资源两 locale 成对提交，arkts_check + build 双资源校验兜底 |

## 九、交付与验证记录（2026-10-28，HUAWEI Mate 60 Pro+）

**构建**：`arkts_check` 11 文件通过；`devecocli build`（entry default）成功；ohosTest HAP `hvigorw assembleHap --mode module -p module=entry@ohosTest` 成功。

**护栏套件（新）**：`ImportFormatCatalog` 11/11 通过（`hdc shell aa test -s class ImportFormatCatalog`）。

**回归套件（真机）**：全部通过，共 234 条——

| 套件 | 结果 |
|---|---|
| CsvFamilyDispatcherImportHandler | 32/32 |
| JsonFamilyDispatcherImportHandler | 12/12 |
| ImportExportFacade | 11/11 |
| ImportExportViewModel | 12/12 |
| FormatSignatureLibrary | 30/30 |
| ImportFixtureFiles | 14/14 |
| CsvMappingWizard | 16/16 |
| ImportWizardBridge | 8/8 |
| XmlImportHandler | 17/17 |
| PresetCsvImportHandler_{chrome,firefox,lastpass,dashlane,onepassword} | 17+15+16+17+16 |
| ImportFormatCatalog（新） | 11/11 |

**部署**：`devecocli run --skip-build` 覆盖安装并启动成功；smoke `FAIL_BLANK` 为密码库解锁页防截屏假阳性，经 `uitest dumpLayout` 确认 UI 树正常渲染（"解锁数据库 / Test.kdbx / 认证方式"）。

**实现中踩坑记录（护栏测试两处修正）**：

1. **Hypium 1.0.28 的 `beforeEach` 不作用于嵌套 describe 用例**——父 suite 向子 suite 只传播 `beforeEachIt`/`afterEachIt`（`@ohos/hypium/src/main/service.js` run() 的 childSuites 分支），顶层 `beforeEach` 赋值的 `groups` 在嵌套用例中恒为初始值。修正：测试改用文件级 memo（`catalogGroups()`）在用例内自取；catalog 为确定性数据，构建一次即可。
2. **ohosTest 环境需显式注入 ResourceManager context**——`getString` 在 `!context` 时返回空串，GENERIC_CSV 的 note 断言必失败。修正：套件顶层 `beforeAll` 经 `TestContextHelper.getUIAbilityContext()` 初始化（父级 `beforeAll` 在子 suite 前执行，见 service.js run() 顺序）。

**待办（手工 UI 走查，需解锁数据库）**：① 设置 → 数据库设置 → 导入行副标题与「?」帮助面板；② 导入 lastpass.csv 观察成功 toast 带 "LastPass CSV"；③ 选 JSON 导入不支持的 JSON 文件观察引导弹窗。
