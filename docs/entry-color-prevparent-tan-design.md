# P2-4 详细设计：条目颜色 + PreviousParentGroup + TAN（数据模型补全，KDBX 4.1 兼容性）

| 项 | 内容 |
|---|---|
| 优先级/编号 | P2-4 |
| 预估工作量 | 2-3 人周 |
| 涉及模块 | `libs/kdbxweb`（数据层）、`entry`（UI/业务层） |
| 状态 | 设计稿（待评审） |

---

## 1. 背景与目标

P2-4 的目标是补全 KeePassHO 对 KDBX 4.1 数据模型三项语义的支持，使本应用与 KeePass 2.x / KeePassXC / KeePass2Android 达到**双向互操作**水平：

1. **条目颜色**（`ForegroundColor` / `BackgroundColor`）—— 编辑、渲染、详情展示完整闭环；
2. **PreviousParentGroup**（`PreviousParentGroup`，KDBX ≥4.1）—— 不再是"只写不读"字段，提供回收站**恢复到原位置**能力，并修复 merge 数据丢失；
3. **TAN 条目**（一次性口令）—— 识别、批量创建、使用后过期、专用渲染。

**重要结论（调研后修正范围）**：本地 fork 的 kdbxweb 数据层对 KDBX 4.1 的字段级支持**已基本完整**（Entry/Group 的颜色、Tags、PreviousParentGroup、QualityCheck、CustomData、Times 含 LocationChanged 均已建模且 XML 读写正确）。真正的差距是：

| # | 差距 | 严重程度 |
|---|---|---|
| G1 | TAN 语义完全缺失（识别/创建/用后过期/渲染） | 功能缺失 |
| G2 | PreviousParentGroup 无任何消费点（回收站恢复原位置缺失） | 功能缺失 |
| G3 | `KdbxEntry.copyFrom()` 不复制 `customData`/`qualityCheck`/`previousParentGroup`，`KdbxGroup.copyFrom()` 不复制 `tags`/`previousParentGroup`/`customData` —— **merge（同步）与历史回滚路径静默丢字段** | 数据丢失 bug |
| G4 | merge 时 `previousParentGroup` 未随较新的 `locationChanged` 一并落地（KeePass 官方 GetBestPool 语义） | 互操作缺陷 |
| G5 | 4.0 版本数据库保存时 4.1 特性字段被静默丢弃（无 `getMinKdbxVersion()` 自动升级机制） | 数据丢失 |
| G6 | 条目详情页头部未应用 fgColor/bgColor 渲染 | UI 小缺口 |
| G7 | 过期提醒未排除 TAN 条目（KeePass 官方行为：过期报告排除 TAN） | 体验问题 |

---

## 2. 术语

| 术语 | 说明 |
|---|---|
| KDBX 3.1 / 4.0 / 4.1 | KeePass 数据库文件格式版本；4.1 由 KeePass 2.36（2016）引入 |
| TAN | Transaction Authentication Number，银行等机构下发的一次性口令。KeePass 中以特殊条目形式管理，使用后即过期 |
| PreviousParentGroup | 条目/分组**上一次被移动前**所在的父分组 UUID，用于回收站恢复与合并 |
| LocationChanged | Times 中的"位置变化时间"，merge 时判定移动冲突胜负的依据 |
| Inherit（颜色继承） | 颜色字段为空 ⇔ 使用列表默认配色；KeePass 以 `Color.Empty`/空字符串表示，无独立标志位 |

---

## 3. 现状调研

### 3.1 本项目现状

#### 3.1.1 数据层（libs/kdbxweb）

| 字段/能力 | 状态 | 位置 |
|---|---|---|
| Entry `fgColor`/`bgColor` | ✅ 已有，XML 无条件读写 | `libs/kdbxweb/src/main/ets/format/kdbx-entry.ts:44-45,82-87,296-297` |
| Entry `tags` | ✅ 已有 | kdbx-entry.ts:47,91-93,299 |
| Entry `previousParentGroup` | ✅ 已有，写出门控 ≥4.1 | kdbx-entry.ts:58,115-117,306-311 |
| Entry `qualityCheck` | ✅ 已有，写出门控 ≥4.1 | kdbx-entry.ts:60,112-114,300-305 |
| Entry/Group/Meta/Header `customData`（含 Item LastModificationTime） | ✅ 已有 | kdbx-entry.ts:59；kdbx-custom-data.ts:36-42 |
| Group `previousParentGroup`/`tags`/`customData` | ✅ 已有（tags、prevParent 写出 4.1 门控） | kdbx-group.ts:18,28-29,94-96,106-120 |
| Group 颜色 | ⚠️ fork 私有扩展：存于 Group `CustomData` 的 `fgColor`/`bgColor` 键 | kdbx-group.ts:31-32,121-153 |
| Times 含 `locationChanged` | ✅ 已有 | kdbx-times.ts:7-13 |
| 版本支持 3.1/4.0/4.1，新库默认 4.1 | ✅ | kdbx-header.ts:76-101,880-889 |
| `Kdbx.move()` 自动维护 previousParentGroup + locationChanged | ✅ | kdbx.ts:335-370（赋值在 367-369） |
| `isInRecycleBin()`（fork 新增） | ✅ | kdbx.ts:389-394 |
| `Kdbx.getGroup(uuid)` 递归查找 | ✅ | kdbx.ts:316-324 |
| merge（locationChanged 判移动 + lastModTime 判内容 + DeletedObjects 墓碑） | ✅ | kdbx.ts:594-626,704-728；kdbx-group.ts:247-296 |
| TAN 相关 | ❌ 全库零匹配 | — |
| `copyFrom` 完整性 | ⚠️ Entry 缺 customData/qualityCheck/previousParentGroup/history；Group 缺 tags/previousParentGroup/customData | kdbx-entry.ts:457-488；kdbx-group.ts:332-346 |
| 保存时 4.1 特性驱动的版本自动升级 | ❌ 无（对齐 KeePass `GetMinKdbxVersion` 的机制缺失） | — |

#### 3.1.2 应用/UI 层（entry 模块）

| 能力 | 状态 | 位置 |
|---|---|---|
| 条目颜色编辑（fg/bg，14 预设 + HSV 自定义） | ✅ 已有 | `entry/src/main/ets/pages/EntryEdit.ets:64-65,469-475,1071-1099`；`components/ColorPickerDialog.ets` |
| 列表按颜色渲染（fgColor 文字色 / bgColor 背景） | ✅ 已有 | `pages/DatabaseView.ets:2452-2453,2498,2510,2560-2561` |
| 过期条目渲染（删除线 + Expired 图标） | ✅ 已有（通用逻辑，非 TAN 专属） | DatabaseView.ets:2485-2514 |
| Tags 编辑/展示/搜索 | ✅ 已有（纯文本输入） | EntryEdit.ets:436-448,1221-1241；KdbxUtils.ets:243-257 |
| 置顶/收藏（保留字 tag 实现） | ✅ 已有 | KdbxUtils.ets:53-55,508-561 |
| 条目详情页 | ✅ 已有，但头部未用颜色渲染（G6） | `pages/EntryView.ets:149-250,503-542` |
| 保存链路（merge → expectedVersion → 冲突重试） | ✅ 已有 | `workers/DatabaseSave.ets:173-197,359-380` |
| 移动分组（move + MoveParam + 批量） | ✅ 已有 | DatabaseView.ets:1279-1309,1838-1878 |
| 回收站恢复原位置 | ❌ 缺失 | — |
| TAN | ❌ 缺失 | — |
| 过期提醒 | ✅ 已有，未排除 TAN（G7） | 见 `docs/expiry-reminder-dev-plan.md` |

### 3.2 参考实现语义（权威依据）

参考源码：`D:\workspace\harmonyos\其他库\{KeePass, keepassxc, kdbxweb}`。

#### 3.2.1 KeePass 2.x（官方 C#，权威语义）

**TAN**
- 识别：`PwDefs.IsTanEntry(pe)` ⇔ **`Strings["Title"] == "<TAN>"`**（`KeePassLib/PwDefs.cs:156-161,229-234`）。与图标、Tags、分组名**无关**。
- TAN 序号复用 **UserName** 字段（`TanIndexField = UserNameField`）。
- 创建（`KeePass/Forms/TanWizardForm.cs:129-144`）：Title=`"<TAN>"`、Password=TAN 文本、Username=序号（可选）；不设置过期/图标/颜色。向导把粘贴文本按字符集（默认 `A-Za-z0-9-`）切分批量生成，目标分组=当前选中分组。
- 用后过期：选项 `TanExpiresOnUse`（默认 **true**）。触发点=**复制密码**与**自动输入完成后**：`EntryUtil.ExpireTanEntryIfOption`（`KeePass/Util/EntryUtil.cs:749-765`）→ `Expires=true; ExpiryTime=UtcNow; Touch()`。双击 TAN 标题=复制密码（使其过期）。
- 渲染：过期 TAN 走通用过期渲染（Strikeout 字体 + Expired 图标，`MainForm_Functions.cs:1298-1314`）；纯 TAN 列表启用简化视图时主项文本显示 **UserName（序号）**（`MainForm_Functions.cs:1351-1362`）。
- 无"TAN 分组"持久化标记；一切按 `ListContainsOnlyTans` 动态判断。
- 过期条目报告、密码质量报告**排除 TAN**（`MainForm_Functions.cs:2372`、`EntryUtil.cs:1589`）。

**条目颜色**
- 类型 `System.Drawing.Color`，默认 `Color.Empty`；序列化时 `A != 255` → **空字符串**（"Inherit"），否则 `#RRGGBB` 大写（`StrUtil.cs:497-523`）。
- 编辑：条目对话框 Properties 页"自定义前景/背景色"复选框（勾选 ⇔ 颜色非 Empty）+ 取色按钮；未勾选保存即写回 Empty=继承（`PwEntryForm.cs:477-483,1111-1114`）。
- 渲染：行级 ForeColor/BackColor，整行子项统一继承（`MainForm_Functions.cs:1338-1346`）。

**PreviousParentGroup**
- `PwUuid`，默认 Zero；语义="上次被移动前包含该对象的分组"（`IStructureItem.cs:36-40`）。
- 赋值：拖放移动条目/分组、删除到回收站时记录原父组 UUID（`MainForm_Functions.cs:5182-5189,5290-5293,6481-6499,7035-7060`）。`PwGroup.AddEntry` 本身不维护该字段。
- 消费 1：**"Move to Previous Parent Group (Restore)"命令** —— 安全校验（非 Zero、能在根组树找到、≠当前父组；分组版另禁止移入自身/子孙，`MainForm_Functions.cs:6896-6928`）；条目在回收站且原父组不在回收站时文案追加 "(Restore)"；执行后把 `PreviousParentGroup` 交换更新为移动前所在组。
- 消费 2：**merge** —— `PwDatabase.MergeInLocationChanged`（`PwDatabase.cs:1406-1490`）：取 `LocationChanged` 较新一方的 `LocationChanged` 与 `PreviousParentGroup` **一起落地**（GetBestPool），保证两字段来源一致。
- 序列化门控：文件版本 ≥4.1 且 UUID 非 Zero 才写（`KdbxFile.Write.cs:505-508,545-546`）。

**KDBX 版本策略**
- 保存版本由 `GetMinKdbxVersion()`（`KdbxFile.cs:351-397`）决定：默认 **4.0**，出现以下内容自动升 **4.1**：任一分组有 Tags；任一条目 `QualityCheck==false`；自定义图标带 Name/LastModificationTime；CustomData 键带 LastModificationTime。`PreviousParentGroup` 的存在**不触发**升级（4.0 库中该字段被静默丢弃，官方亦如此）。
- 元素级写出门控：Entry `<Tags>` 无条件；`<QualityCheck>` 仅 false 且 ≥4.1；Group `<Tags>`、Entry/Group `<PreviousParentGroup>` ≥4.1 且非默认。

#### 3.2.2 KeePassXC（C++/Qt）

- **TAN：完全不支持**（全仓库 `\bTAN\b` 零匹配），TAN 条目按普通条目显示。
- **PreviousParentGroup**：唯一消费场景=**回收站还原**。`DatabaseWidget::restoreSelectedEntries()`（`src/gui/DatabaseWidget.cpp:607-625`）：`if (entry->previousParentGroup()) entry->setGroup(entry->previousParentGroup())`；按 UUID 反查组（`Entry.cpp:1526-1544`），找不到则不还原；菜单仅回收站内条目可见（`MainWindow.cpp:908-913`）。merge 不使用该字段（只用 locationChanged）。
- 赋值差异：跨数据库移动=**清除** previousParentGroup，库内移动=记录旧父组（`Entry.cpp:1406-1439`）。
- 版本：`kdbxVersionRequired()`（`KeePass2Writer.cpp:52-107`）从 3.1 起步，group tags / group & entry previousParentGroup / entry QualityCheck=false / 图标 Name 等出现时升 4.1。
- 颜色：Advanced 页 checkbox + QColorDialog；fg 缺省时按 palette 明度自动调整保证可读（`EntryModel.cpp:332-357`）。

#### 3.2.3 上游 kdbxweb（keeweb）

- 库层**无 TAN 概念**；`previousParentGroup` 为**只写不读**字段（唯一赋值点 `Kdbx.move()`，`lib/format/kdbx.ts:232`），merge 不读。
- Group 无颜色字段（本地 fork 的 Group CustomData 颜色是自创扩展）。

### 3.3 结论

- 数据层字段建模已齐 → 本期**重点在语义补全与消费闭环**，而非"加字段"。
- TAN 语义采用 KeePass 官方约定（Title=`"<TAN>"`），保证三方互操作。
- PreviousParentGroup 消费采用 KeePassXC 的"回收站还原"模式（最简、最被验证），merge 补全采用 KeePass 官方 GetBestPool 模式。
- 版本策略对齐 KeePass：**仅 4.0 库自动小版本升级到 4.1**（4.0→4.1 不涉及加密算法/头部结构变更，主流客户端自 2016 年起均支持）；3.1 库不自动升级。

---

## 4. 需求范围

### 4.1 功能需求

| 编号 | 需求 | 来源差距 |
|---|---|---|
| FR-1 | 回收站中的条目/分组可通过"恢复到原位置"回到 PreviousParentGroup 指向的分组；支持批量 | G2 |
| FR-2 | 通过 TAN 向导在当前分组批量创建 TAN 条目（粘贴文本按字符集切分） | G1 |
| FR-3 | 复制 TAN 条目密码后自动置为过期（设置项控制，默认开启） | G1 |
| FR-4 | 列表/详情对 TAN 条目做专用渲染（显示序号），过期沿用删除线渲染 | G1 |
| FR-5 | 条目详情页头部应用 fgColor/bgColor | G6 |
| FR-6 | 过期提醒排除 TAN 条目 | G7 |
| FR-7 | merge 与历史回滚不再丢失 customData / qualityCheck /（merge 场景）previousParentGroup / Group tags | G3、G4 |
| FR-8 | 4.0 版本库保存时，若使用 4.1 特性自动升级为 4.1 | G5 |

### 4.2 非功能需求

- **互操作**：与 KeePass 2.x、KeePassXC 双向 roundtrip 无数据丢失（含 TAN、颜色、回收站还原后 KeePass 端再次还原）。
- **不做的事**（明确排除）：
  - 不做自动输入（HarmonyOS 无全局自动输入框架，KeePass 的 AutoType 触发过期不适用）；
  - 不做纯 TAN 列表"简化视图"切换（KeePass 的 View.List 单列模式），移动端列表形态不同，仅做序号渲染；
  - 不实现"跨库移动清除 previousParentGroup"（本应用跨库移动为复制语义，无此场景）；
  - 不改 Group 颜色的 CustomData 私有扩展（保持现状，见 6.4.3）。

---

## 5. 总体设计

```
┌──────────────────────────── entry（应用层） ────────────────────────────┐
│  DatabaseView.ets      EntryView.ets      EntryEdit.ets   设置页        │
│   ├─ 回收站"恢复"入口    ├─ 头部颜色渲染   └─ TAN 向导入口   ├ TAN用后过期开关 │
│   ├─ TAN 序号渲染        └─ 复制密码→TAN过期                   └ (SettingsService)│
│   └─ TAN 向导对话框 TanWizardDialog.ets                                 │
│──────────────────────────────────────────────────────────────────────│
│  KdbxUtils.ets（业务语义层）                                            │
│   ├─ isTanEntry / addTanEntries / expireTanEntryOnUse                  │
│   ├─ getPreviousParentGroupSafe / restoreToPreviousLocation            │
│   └─ parseEntryColor                                                   │
│──────────────────────────────────────────────────────────────────────│
│  过期提醒服务：收集时排除 isTanEntry                                    │
└───────────────────────────────┬───────────────────────────────────────┘
                                │
┌───────────────────── libs/kdbxweb（数据层） ───────────────────────────┐
│  kdbx-entry.ts / kdbx-group.ts：copyFrom 补全                          │
│  kdbx.ts：merge 补全（previousParentGroup 随 locationChanged 落地）      │
│  kdbx.ts / kdbx-header.ts：getMinKdbxVersion() 保存前自动升 4.1         │
└────────────────────────────────────────────────────────────────────────┘
```

分层原则：**TAN/恢复的业务语义放应用层 `KdbxUtils`**（与现有 `isPinned`/`toggleFavorite` 的保留字 tag 模式一致），kdbxweb 库只做与文件格式相关的修复（copyFrom/merge/版本），保持与上游 keeweb 的可合并性。

---

## 6. 详细设计

### 6.1 数据层补全（libs/kdbxweb）

#### 6.1.1 `copyFrom` 字段补全（G3 修复）

**现状**：
- `KdbxEntry.copyFrom()`（kdbx-entry.ts:457-488）：不复制 `customData`、`qualityCheck`、`previousParentGroup`、`history`。
- `KdbxGroup.copyFrom()`（kdbx-group.ts:332-346）：不复制 `tags`、`previousParentGroup`、`customData`。

`copyFrom` 有两类调用场景，字段取舍不同：

| 字段 | merge（远端较新时整条覆盖本地） | 历史回滚（rollbackToHistory） |
|---|---|---|
| `customData` | **必须复制**（否则同步时丢数据） | **必须复制**（回滚应恢复当时快照） |
| `qualityCheck` | **必须复制** | **必须复制** |
| Group `tags` | **必须复制** | **必须复制** |
| `previousParentGroup` | **不通过 copyFrom 复制**，由 merge 专用逻辑处理（见 6.1.2） | **不复制**（回滚内容不应改变当前位置元数据） |
| `history` | 不复制（merge 有专用 mergeHistory） | 不复制（沿用现状） |

**改动**：

```typescript
// kdbx-entry.ts copyFrom() 内追加：
this.customData = other.customData.clone();     // KdbxCustomDataMap 已有 clone
this.qualityCheck = other.qualityCheck;

// kdbx-group.ts copyFrom() 内追加：
this.tags = other.tags ? [...other.tags] : undefined;
this.customData = other.customData.clone();
```

> 说明：上游 keeweb 同样不复制这些字段（上游 bug），本 fork 修复后需在 `libs/kdbxweb` 维护补丁清单，同步上游时保留。

#### 6.1.2 merge 补全：previousParentGroup 随 locationChanged 落地（G4）

对齐 KeePass `MergeInLocationChanged`（PwDatabase.cs:1457-1490）的 GetBestPool 语义。

**现状**：`kdbx-group.ts mergeCollection()`（247-296）移动冲突用 `locationChanged` 比较，远端较新则 `item.parentGroup = this`，但 `item.previousParentGroup` 保留本地旧值 → 与新 `locationChanged` 来源不一致；若本地库随后被 KeePass 官方客户端 merge，其 GetBestPool 会以（错误的）本地 previousParentGroup 覆盖。

**改动**（kdbx-group.ts mergeCollection 内，远端移动胜出的分支）：

```typescript
// item.times.locationChanged 已取较新方后：
if (item.previousParentGroup !== remoteItem.previousParentGroup) {
  item.previousParentGroup = remoteItem.previousParentGroup;
}
```

KdbxEntry 的内容 merge 走 `copyFrom`（见 6.1.1，不含 previousParentGroup），条目的移动归属与 Group 同理由 `mergeCollection` 判定，故条目版本在同一分支补齐。

#### 6.1.3 保存前版本自动升级（G5）

**策略（对齐 KeePass `GetMinKdbxVersion`）**：仅当数据库 major==4 且 minor==0 时评估；命中任一条件则 header 升级为 4.1。**3.1 库不自动升级**（3.1→4.x 涉及加密头部变更，必须用户显式操作，保持现有 upgrade() 入口）。

**触发条件**（遍历 root group）：
1. 任一 Group 有 `tags`；
2. 任一 Entry `qualityCheck === false`；
3. 任一 Entry/Group `previousParentGroup !== undefined`；
4. 任一 CustomIcon 有 `name` 或 `lastModified`；
5. 任一 CustomData item 有 `lastModificationTime`。

> 注：KeePass 官方第 3 项不触发升级（官方 4.0 库静默丢弃该字段）；本应用选择**触发升级**（与 KeePassXC `kdbxVersionRequired` 一致，`KeePass2Writer.cpp:75-77,87-89`），理由：本应用把 previousParentGroup 作为回收站恢复的依据，丢弃会直接破坏功能；且 4.0→4.1 兼容性风险极低。

**实现位置**：`Kdbx.saveV4()` 入口处（kdbx-format.ts:691-712 分发后），新增私有方法：

```typescript
private upgradeMinorVersionIfNeeded(): void {
  if (this.header.versionMajor !== 4 || this.header.versionMinor !== 0) {
    return;
  }
  if (this.uses41Features(this.getDefaultGroup())) {
    this.header.versionMinor = 1;   // 仅 minor 提升，KDF/Cipher 不变
  }
}
```

`uses41Features` 递归实现，注意 ArkTS 约束（无 this 泄漏、无动态属性访问）。

#### 6.1.4 不改动的部分（明确记录）

- TAN 常量与识别逻辑**不进 kdbxweb 库**（上游无此概念，进库会加大与上游的 diff；放应用层 KdbxUtils，见 6.3）。
- Group 颜色的 CustomData 私有扩展保留（KeePass/KeePassXC 会忽略未知 CustomData 键，数据不丢失）。

### 6.2 PreviousParentGroup 消费：回收站恢复到原位置（FR-1）

#### 6.2.1 业务 API（KdbxUtils.ets 新增）

```typescript
/** KdbxUtils.ets */

/**
 * 获取可安全恢复的目标父分组（对齐 KeePass GetPreviousParentGroupSafeI）
 * @returns 目标分组；不可恢复时返回 undefined
 */
public static getPreviousParentGroupSafe(database: Kdbx,
  object: KdbxEntry | KdbxGroup): KdbxGroup | undefined {
  // 1. previousParentGroup 未设置 → 不可恢复
  if (!object.previousParentGroup) {
    return undefined;
  }
  // 2. 按 UUID 在根组树递归查找（Kdbx.getGroup，kdbx.ts:316）
  const target = database.getGroup(object.previousParentGroup);
  if (!target) {
    return undefined;   // 原分组已被永久删除
  }
  // 3. 不允许"恢复"到当前父组（已在原位置）
  if (target === object.parentGroup) {
    return undefined;
  }
  // 4. 分组恢复：目标不得是自身或自身子孙（循环检测，参照 moveItemToCurrentGroup 的做法）
  if (object instanceof KdbxGroup && KdbxUtils.isDescendantOrSelf(target, object as KdbxGroup)) {
    return undefined;
  }
  return target;
}

/**
 * 恢复条目/分组到原位置。
 * Kdbx.move 会自动更新 previousParentGroup（→回收站 UUID）与 locationChanged，
 * 与 KeePassXC restoreSelectedEntries 行为一致。
 */
public static restoreToPreviousLocation(database: Kdbx,
  object: KdbxEntry | KdbxGroup): boolean {
  const target = KdbxUtils.getPreviousParentGroupSafe(database, object);
  if (!target) {
    return false;
  }
  database.move(object, target);
  return true;
}
```

`isDescendantOrSelf(candidate, group)`：沿 candidate.parentGroup 向上遍历，命中 group 即 true（复用 DatabaseView.ets:1861 的子分组循环检测思路，提为 KdbxUtils 公共方法）。

#### 6.2.2 UI 入口（DatabaseView.ets）

| 入口 | 位置 | 行为 |
|---|---|---|
| 单项操作 | 回收站内条目/分组的操作菜单（现有"复制密码/编辑/删除"菜单，DatabaseView.ets:964 附近）新增"**恢复到原位置**"项 | `restoreToPreviousLocation` → 成功：Toast "已恢复到「目标分组名」" + 触发保存；失败（目标不存在）：Toast "原分组已不存在，请手动移动" |
| 批量操作 | 选择模式工具栏（SelectionModeBar，DatabaseView.ets:2780-2793）在回收站分组内时新增"恢复"按钮 | 逐项 `restoreToPreviousLocation`，统计成功/跳过数 |
| 菜单可用性 | 仅 `database.isInRecycleBin(object) && getPreviousParentGroupSafe(...) !== undefined` 时显示/启用 | 隐藏规则与现有"置顶/收藏"菜单一致 |

**保存触发**：恢复操作修改了内存模型，必须走现有保存链路（`KdbxSaveService`，与 `togglePinned` 等写操作相同路径），冲突重试由 `workers/DatabaseSave.ets` 的 expectedVersion 机制兜底。

**文案**：
- 菜单：`恢复到原位置`（zh）/ `Restore to original location`（en）
- 成功：`已恢复到「%s」`
- 不可恢复：`原分组已不存在或不可恢复，请在列表中手动移动`

#### 6.2.3 恢复后的 previousParentGroup 语义

`Kdbx.move()`（kdbx.ts:367）会把 previousParentGroup 更新为**恢复前的父组（回收站 UUID）**，即 KeePass 的"交换语义"：再次删除到回收站后仍可再恢复，KeePass 官方/本应用两侧语义自洽，无需额外处理。

### 6.3 TAN 支持（FR-2/3/4/6）

#### 6.3.1 常量与识别（KdbxUtils.ets）

对齐 KeePass `PwDefs`（PwDefs.cs:156-161,229-234）：

```typescript
/** TAN 条目标题（KeePass 官方约定，区分大小写，含尖括号） */
public static readonly TAN_TITLE = '<TAN>';

/**
 * 是否 TAN 条目（对齐 PwDefs.IsTanEntry：Title 精确等于 '<TAN>'）
 */
public static isTanEntry(entry: KdbxEntry): boolean {
  return KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_TITLE)
    === KdbxUtils.TAN_TITLE;
}

/** TAN 序号（KeePass 约定：复用 UserName 字段） */
public static getTanIndex(entry: KdbxEntry): string {
  return KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_USERNAME);
}
```

> 注意：`getFieldValueString` 需处理字段值为 `ProtectedValue` 的情形（沿用现有工具，与 copyPassword 一致，DatabaseView.ets:1145）。

#### 6.3.2 TAN 向导（FR-2）

新增组件 `entry/src/main/ets/components/TanWizardDialog.ets`（CustomDialog，复用现有对话框风格）：

**表单项**：
| 项 | 控件 | 默认值 |
|---|---|---|
| TAN 文本（多行粘贴框） | TextArea | 空 |
| 分隔字符集 | TextInput | `A-Za-z0-9-`（KeePass 默认 `TanCharacters`，AceDefaults.cs:96） |
| 起始序号 | TextInput(数字) | 1 |
| 预览计数 | 文本 | 实时显示"将创建 N 个 TAN" |

**切分逻辑**：将粘贴文本按"非字符集字符"切分为连续片段序列（等价 KeePass `TanWizardForm` 解析，TanWizardForm.cs:105-127），正则 `[^A-Za-z0-9-]+` 分割（字符集可自定义时动态构建，注意 ArkTS 中 `new RegExp` 转义）。

**创建逻辑**（KdbxUtils 新增）：

```typescript
/**
 * 批量创建 TAN 条目（对齐 TanWizardForm.AddTan，TanWizardForm.cs:129-144）
 * @returns 实际创建的条目数
 */
public static addTanEntries(group: KdbxGroup, tans: string[],
  startIndex: number): number {
  let index = startIndex;
  for (const tan of tans) {
    if (!tan) {
      continue;
    }
    const entry = new KdbxEntry();
    KdbxUtils.setFieldValue(entry, KdbxUtils.FIELD_TITLE, KdbxUtils.TAN_TITLE);
    KdbxUtils.setFieldValue(entry, KdbxUtils.FIELD_PASSWORD, tan); // 明文字段
    KdbxUtils.setFieldValue(entry, KdbxUtils.FIELD_USERNAME,
      index > 0 ? String(index) : '');
    group.entries.push(entry);   // 或走 Kdbx 现有 addEntry 语义
    index++;
  }
  return index - startIndex;
}
```

> 字段保护遵循库的 MemoryProtection 配置（kdbxweb 序列化时自动按 meta.memoryProtection 落盘），与 KeePass 行为一致。

**入口**：DatabaseView 顶部"+"菜单（现有新建条目/分组菜单）新增"**添加 TAN**"，仅在存在当前分组时可用；创建成功后触发保存并刷新列表。

**不自动建分组**（KeePass 亦无此逻辑），用户可在任意分组（含新建的"TAN"命名分组）中执行向导。

#### 6.3.3 用后过期（FR-3）

**设置项**（SettingsService，遵循 `KEY_*` + `*_DEFAULT` 约定）：

```typescript
public static readonly KEY_TAN_EXPIRES_ON_USE = 'tanExpiresOnUse';
public static readonly TAN_EXPIRES_ON_USE_DEFAULT = true;   // KeePass 默认 true
```

设置页新增开关"TAN 使用后过期"（建议放 设置 → 安全 或通用行为分组，具体随现有设置信息架构）。

**核心逻辑**（KdbxUtils 新增，对齐 `EntryUtil.ExpireTanEntryIfOption`，EntryUtil.cs:749-765）：

```typescript
/**
 * TAN 条目用后过期。返回是否发生了变更（调用方据此触发保存与 UI 刷新）
 */
public static expireTanEntryOnUse(entry: KdbxEntry,
  expiresOnUse: boolean): boolean {
  if (!expiresOnUse || !KdbxUtils.isTanEntry(entry)) {
    return false;
  }
  // 变更前推入历史（保持与其他字段修改一致的可回滚性，EntryEdit.pushEntryToHistory 模式）
  entry.pushHistory();
  entry.times.expires = true;
  entry.times.expiryTime = new Date();
  entry.times.lastAccessTime = new Date();
  entry.touch?.();   // 若 fork 提供 touch 则调用
  return true;
}
```

**触发点**（调用方统一模式：复制动作成功后调用，变更则触发保存 + 列表刷新）：

| 触发点 | 位置 | 说明 |
|---|---|---|
| 列表条目"复制密码" | DatabaseView.ets:1144 `copyPassword()` | 复制后调用；设置开启且为 TAN → 过期 + `KdbxSaveService` 保存 + 列表刷新（出现删除线） |
| 详情页复制密码字段 | EntryView.ets 密码字段复制动作 | 同上 |
| 通知栏"复制密码"按钮 | SessionNotificationService.ets | **本期不做**（通知栏复制为后台动作，过期后通知交互复杂，列为后续增强；文档明确记录） |

**过期后渲染**：沿用现有过期渲染（删除线 + `C45_Expired` 图标，DatabaseView.ets:2485-2514），无需新增代码；KeePass 亦无 TAN 专属过期样式。

**失败降级**：若保存失败（远端冲突/断网），内存态已过期，下次保存成功时落盘；现有 `MAX_CONFLICT_RETRY` 重试链路兜底。可接受，不做回滚。

#### 6.3.4 渲染（FR-4）

**列表项**（DatabaseView.ets 条目分支，L2482-2590 区域）：

- 主标题：`isTanEntry(entry)` 时显示 `TAN ${序号}`（有序号）或 `<TAN>`（无序号）—— 对齐 KeePass 简化视图"主项文本显示 UserName 序号"（MainForm_Functions.cs:1351-1362），加 `TAN` 前缀以在混合列表中保持可辨识；
- 副标题：显示密码掩码（沿用现有密码遮蔽渲染），不显示序号（已上移）；
- 搜索不受影响（搜索匹配字段原文，见 KdbxUtils.entryMatchesSearch，仅展示层替换）。

**详情页**（EntryView.ets EntryHeader，L503-542）：

- 标题：`<TAN> (#序号)`（对齐 KeePass 汇总格式 `标题 (#序号)`，EntryUtil.cs:839-844）；
- 其余字段正常展示。

#### 6.3.5 过期提醒排除 TAN（FR-6）

过期提醒的条目收集逻辑（参见 `docs/expiry-reminder-dev-plan.md` 对应实现）增加过滤：

```typescript
if (KdbxUtils.isTanEntry(entry)) {
  continue;   // KeePass 官方：过期条目报告排除 TAN（MainForm_Functions.cs:2372）
}
```

### 6.4 条目颜色补缺（FR-5）

#### 6.4.1 详情页头部渲染（G6）

`EntryView.ets` 的 `EntryHeader` Builder（L503-542）：

- 标题/用户名文字色：`entry.fgColor` 合法时优先，否则 `text_primary`；
- 头部区域背景：`entry.bgColor` 合法时优先，否则透明/默认卡片背景。

与列表渲染规则（DatabaseView.ets:2498,2510,2560-2561）保持完全一致。

#### 6.4.2 颜色格式容错（KdbxUtils 新增）

KDBX 中颜色为 `#RRGGBB`（KeePass 写大写；读取端 KeePassXC 要求 7 位 `#` 开头 hex，`KdbxXmlReader.cpp:1088-1112`）。外部工具写入的非法值需容错：

```typescript
/**
 * 校验并归一化条目颜色字符串（#RRGGBB）；非法/空返回 undefined（=继承默认色）
 */
public static parseEntryColor(color: string | undefined): string | undefined {
  if (!color) {
    return undefined;
  }
  return /^#[0-9a-fA-F]{6}$/.test(color) ? color.toUpperCase() : undefined;
}
```

列表与详情渲染统一经此函数取色（替换现有直接 `item.fgColor ||` 的写法，空串/非法串自然回退默认）。

#### 6.4.3 Group 颜色（决策：保持现状）

fork 将 Group 颜色存于 Group `CustomData` 的 `fgColor`/`bgColor` 键（kdbx-group.ts:121-153），**非 KDBX 标准内容**（Entry 才有标准颜色元素）。决策：**保留**。理由：
- KDBX 规范无 Group 颜色标准，任何方案都是扩展；
- CustomData 是标准 4.x 元素，KeePass/KeePassXC 会原样保留未知键，**不丢数据**，仅不渲染；
- 改动无收益且有迁移风险。

在本文档记录即可，不做代码改动。

### 6.5 KDBX 4.1 兼容性矩阵（验收基准）

| 元素 | 3.1 | 4.0 | 4.1 | 本应用行为 |
|---|---|---|---|---|
| Entry `<ForegroundColor>/<BackgroundColor>` | ✅ | ✅ | ✅ | 读写已有；详情渲染本期补 |
| Entry `<Tags>` | ✅ | ✅ | ✅ | 读写已有 |
| Group `<Tags>` | ❌ | ❌ | ✅ | 读写已有（写出 4.1 门控） |
| Entry `<QualityCheck>` | ❌ | ❌ | ✅(false 才写) | 读写已有 |
| Entry/Group `<PreviousParentGroup>` | ❌ | ❌ | ✅(非空才写) | 读写已有；**4.0 库保存时自动升 4.1**（本期新增） |
| CustomData Item `<LastModificationTime>` | ❌ | ❌ | ✅ | 读写已有 |
| CustomIcon `<Name>/<LastModificationTime>` | ❌ | ❌ | ✅ | 读写已有 |
| Times `<LocationChanged>` | ✅ | ✅ | ✅ | 已有，merge 判定移动 |

---

## 7. 设置项与国际化

| 项 | 值 | 位置 |
|---|---|---|
| 设置键 | `SettingsService.KEY_TAN_EXPIRES_ON_USE`，默认 `true` | `SettingsService.ets` |
| 设置 UI | 开关"TAN 使用后过期"（zh/en） | 设置页（安全或行为分组） |
| 新增文案 | TAN 向导（标题/输入提示/预览/确认）、"恢复到原位置"及结果 Toast、详情页 TAN 标题格式 | `resources/base/element/string.json` + `zh_CN`/`en_US` |

---

## 8. 测试方案

### 8.1 单元测试（Hypium，on-device）

**kdbxweb（`libs/kdbxweb/src/ohosTest/`，沿用现有 KDBX4.1 roundtrip 用例风格）**：
1. `copyFrom` 补全：含 customData/qualityCheck/tags 的 Entry/Group，copyFrom 后字段一致；
2. merge 字段保留：远端较新分支合并后 customData/qualityCheck/Group tags 不丢；移动冲突远端胜后 previousParentGroup 与 locationChanged 同源；
3. 历史回滚：rollback 后 previousParentGroup 不变、customData/qualityCheck 恢复为快照值；
4. 版本自动升级：4.0 库 + 含 previousParentGroup/Group tags 的条目 → 保存后 header.versionMinor==1；4.0 库无 4.1 特性 → 保持 4.0；3.1 库 → 不升级；
5. roundtrip：4.1 库 TAN 条目 + 颜色 + 回收站 previousParentGroup，save→load 全字段一致（对照上游 `test/format/kdbx.spec.ts:1053-1095`）。

**entry（`entry/src/ohosTest/ets/test/`）**：
6. `isTanEntry`：Title=`<TAN>` 为 true；`<tan>`/`TAN`/普通标题为 false（大小写敏感）；
7. `addTanEntries`：切分/序号/字段赋值正确；
8. `expireTanEntryOnUse`：开关关闭不变更；TAN 过期（expires=true、expiryTime≈now、历史+1）；非 TAN 不变；
9. `getPreviousParentGroupSafe`/`restoreToPreviousLocation`：未设置/目标已删/目标==当前父组/目标是自身子孙 → 拒绝；正常路径 → parentGroup 正确且 previousParentGroup 更新为回收站；
10. `parseEntryColor`：`#AABBCC`→`#AABBCC`；`#abc`/`red`/空 → undefined。

### 8.2 互操作手工测试（关键验收）

| 场景 | 步骤 | 预期 |
|---|---|---|
| KeePass→本应用 | KeePass 2.x 建 TAN（向导）+ 条目颜色 + 删除条目进回收站，本应用打开 | TAN 识别渲染正确；颜色正确；"恢复到原位置"可用且恢复到 KeePass 中的原分组 |
| 本应用→KeePass | 本应用创建 TAN（用后过期触发）+ 设颜色 + 回收站恢复，KeePass 打开 | KeePass `IsTanEntry` 判定成功（双击=复制过期）；颜色/位置正确；KeePass "Move to Previous Parent Group" 语义自洽 |
| 本应用→KeePassXC | 同上数据 KeePassXC 打开 | TAN 按普通条目显示（KeePassXC 无 TAN 支持，预期行为）；颜色正确；回收站还原可用 |
| 同步 merge | 两端各改条目（A 改字段，B 移动条目），本应用 WebDAV 双向同步 | customData/qualityCheck 不丢；移动归属与 previousParentGroup 一致 |

### 8.3 E2E（可选）

复用 uitest dumpLayout 驱动（见 `.agents/skills/uitest-dump-driving`）：TAN 向导创建→复制密码→列表出现删除线；回收站恢复→条目回到原分组。

---

## 9. 工作量估算与里程碑（2-3 人周）

| 阶段 | 内容 | 工作量 |
|---|---|---|
| M1（W1） | kdbxweb 数据层：copyFrom 补全、merge 补全、版本自动升级 + 单测 1-5 | 3-4 人日 |
| M2（W1-W2） | 回收站恢复：KdbxUtils API + DatabaseView 单项/批量入口 + 单测 9 + 互操作场景 1-2 | 2-3 人日 |
| M3（W2） | TAN：常量/识别、向导对话框、用后过期 + 设置项、渲染、过期提醒排除 + 单测 6-8、10 | 4-5 人日 |
| M4（W3） | 颜色补缺（详情头部 + parseEntryColor 接入）、国际化、互操作全场景回归、修尾 | 2-3 人日 |

关键路径：M1 →（M2、M3 可并行）→ M4。

---

## 10. 风险与开放问题

| # | 风险/问题 | 等级 | 应对 |
|---|---|---|---|
| R1 | `copyFrom`/`merge` 语义变更影响现有同步冲突行为 | 中 | M1 完成后立即跑 WebDAV/S3 双端同步回归（现有 e2e 环境，`docs/e2e/`）；merge 单测覆盖本地胜/远端胜/删除三分支 |
| R2 | 自动升 4.1 后极老客户端（KeePass<2.36 / KeePassXC<2.4）无法打开 | 低 | 4.1 已发布 10 年，主流客户端均支持；不做设置开关，文档记录即可 |
| R3 | TAN 过期写入与用户后续编辑冲突（过期后用户又编辑保存） | 低 | 正常 lastModTime 语义覆盖，无特殊处理 |
| R4 | 通知栏复制密码不触发 TAN 过期（本期排除项） | 低 | 已在 6.3.3 记录为后续增强；通知栏 TAN 场景罕见 |
| R5 | 外部库写入非法颜色字符串导致渲染异常 | 低 | `parseEntryColor` 统一容错（6.4.2） |
| O1 | **开放**：TAN 向导是否需要支持"从文本文件导入"（KeePass 支持打开 txt） | — | 建议后续版本；本期仅粘贴 |
| O2 | **开放**：纯 TAN 分组是否隐藏密码列（KeePass 简化视图的一部分） | — | 本期不做（4.2 明确排除），观察用户反馈 |
| O3 | **开放**：`KdbxEntry.touch()` 在 fork 中是否存在（上游有） | — | 实现时确认；缺失则手动更新 times.lastAccessTime |

---

## 11. 附录：参考实现证据索引

| 结论 | 来源 |
|---|---|
| TAN 识别 = Title=="\<TAN\>"，序号在 UserName | KeePassLib/PwDefs.cs:156-161,229-234 |
| TAN 创建字段集 | KeePass/Forms/TanWizardForm.cs:105-144 |
| TanExpiresOnUse 默认 true，复制密码/自动输入后过期 | KeePass/Util/EntryUtil.cs:749-765；AceDefaults.cs:109-115；MainForm.cs:901-915 |
| 过期报告排除 TAN | KeePass/Forms/MainForm_Functions.cs:2372 |
| 颜色 Empty=继承，序列化为空串 | KeePassLib/Utility/StrUtil.cs:497-523；KdbxFile.Read.Streamed.cs:444-455 |
| 行级颜色渲染 | KeePass/Forms/MainForm_Functions.cs:1338-1346 |
| PreviousParentGroup 赋值/交换语义 | KeePass/Forms/MainForm_Functions.cs:5182-5189,7021-7064 |
| merge GetBestPool（prevParent 随 locationChanged） | KeePassLib/PwDatabase.cs:1406-1490 |
| GetMinKdbxVersion 版本升级条件 | KeePassLib/Serialization/KdbxFile.cs:351-397 |
| 回收站还原（KeePassXC） | keepassxc/src/gui/DatabaseWidget.cpp:607-625；Entry.cpp:1526-1544 |
| kdbxVersionRequired（4.0→4.1 条件，含 prevParent 触发） | keepassxc/src/format/KeePass2Writer.cpp:52-107 |
| 上游 kdbxweb：无 TAN、prevParent 只写不读 | kdbxweb/lib/format/kdbx.ts:200-235,404-436 |
| 本地 fork move/previousParentGroup/isInRecycleBin/getGroup | libs/kdbxweb/.../format/kdbx.ts:316-324,335-370,389-394 |
| 本地 copyFrom 缺口 | libs/kdbxweb/.../format/kdbx-entry.ts:457-488；kdbx-group.ts:332-346 |
| 本地颜色编辑/渲染现状 | entry/.../pages/EntryEdit.ets:64-65,469-475；DatabaseView.ets:2482-2590 |
| 本地置顶/收藏 tag 模式（TAN 工具参照） | entry/.../common/utils/KdbxUtils.ets:53-55,508-561 |
