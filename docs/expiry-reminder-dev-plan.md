# 条目到期提醒开发计划

> 功能：数据库解锁后，提醒用户"已过期 / N 天内即将过期"的条目，并支持一键查看这些条目。
>
> 对应 `docs/feature-gap-analysis.md` 中 P0-4 项。
>
> 编写日期：2026-10-26 | 目标版本：2.3.0

---

## 一、背景与目标

KeePassHO 目前对过期条目只有**被动展示**（列表过期图标 + 标题删除线，见 `DatabaseView.ets:2548`、`TotpView.ets:283-303`），没有任何主动提醒。用户在桌面端修改了过期时间，或长期未轮换密码时，移动端用户感知不到。

**目标**：

1. 数据库解锁成功后，若存在"已过期或 N 天内到期"的条目，给出**轻量提示条**（不打断操作），显示数量并支持一键查看；
2. 点击后进入"临期/过期条目"列表，可直接跳转条目详情编辑；
3. 提醒频率可控（防打扰），开关与天数可配置；
4. 预留搜索语法 `is:expired` / `is:expired-N`，与 KeePassXC 对齐。

**非目标（本期不做）**：

- 锁定状态下的后台系统通知（涉及未加密元数据缓存的安全权衡，见 6.3 节，列入三期评估）；
- 密码健康检查联动扣分（依赖健康检查功能，见 `feature-gap-analysis.md` P0-2）。

---

## 二、参考库实现调研结论

### 2.1 三家实现对比

| 维度 | KeePassXC | KeePass 2.x | keepass2android |
|---|---|---|---|
| 解锁后提醒 | ✅ 默认开启，自动搜索 `is:expired-3` | ✅ 默认关闭，可配"已过期"+"7天内到期" | ❌ 无 |
| 提醒 UI 形式 | 预置搜索结果（主视图内） | 临时结果分组列表页 | — |
| 手工过滤 | `is:expired-N` 搜索 + 侧栏"Expired"虚拟标签 | Find→Expired 及 1/2/3/7/14/30/60 天子菜单 | 搜索页"排除过期"复选框 |
| 过期视觉标记 | 原图标 + Expired 角标 | Expired 图标 + 删除线字体 | 图标整体替换 + 删除线 |
| 系统通知/推送 | ❌ | ❌ | ❌（三家都没有） |
| 配置项 | `GUI_ShowExpiredEntriesOnDatabaseUnlock`（默认 true）+ `...OffsetDays`（默认 3） | `ShowExpiredEntries`（默认 false）+ `ExpirySoonDays`（默认 7） | — |

### 2.2 关键源码位置（可借鉴实现）

| 要点 | 位置 | 说明 |
|---|---|---|
| 统一判定方法 `willExpireInDays(days)` | keepassxc `src/core/Entry.cpp:477-484` | `isExpired()` = `willExpireInDays(0)`；一个方法同时覆盖"已过期"与"N 天内将过期"，**强烈建议照搬此设计** |
| 解锁触发时机 | keepassxc `src/gui/DatabaseWidget.cpp:1323-1349` | 解锁完成、进入主视图后触发；仅首次解锁（非重复解锁） |
| `is:expired-N` 搜索语法解析 | keepassxc `src/core/EntrySearcher.cpp:203-211` | split '-' 取天数；匹配 `willExpireInDays(N) && !isRecycled()`（排除回收站） |
| 打开库后自动展示 | KeePass `src/Forms/MainForm_Functions.cs:2631-2641, 2331-2392` | 排除条件参考：`!Expires`、条目禁用搜索、TAN 条目；时间上限取当天 23:59:59 本地时间再比较（"按天"语义） |
| 配置默认值 | keepassxc `src/core/Config.cpp:131-132` | 开关默认 true、天数默认 3 |
| 移动端防打扰 | 三家均未解决 | 移动端 App 频繁热启动/解锁，"每次解锁都提醒"会打扰 → 本项目需增加**按库 + 时间间隔**的防打扰机制（改进点） |

### 2.3 设计取舍

- **提醒形式选"提示条"而非"跳转搜索结果"**：KeePassXC 解锁后直接把主视图切到搜索结果，对移动端过于强势（用户想先看列表时被劫持）。本项目已有成熟的提示条模式（子库配置提示条 `DatabaseView.ets:2711-2747`），采用"提示条 + 点击跳转"更符合移动端习惯，且实现可完全复用现有模式。
- **防打扰是移动端必做项**：默认"每库每 24 小时最多提醒一次"，提供"每次解锁都提醒"选项。
- **天数收敛为单设置项**：不做 KeePass 的 1/2/3/7/14/30/60 天菜单，学 KeePassXC 的单数字设置（默认 3，可选 1/3/7/14/30）。

---

## 三、现状分析（可复用的基础）

| 已有能力 | 位置 | 复用方式 |
|---|---|---|
| 过期判定 `DateUtils.isExpired(expires, expiryTime)` | `common/utils/DateUtils.ets:57-62` | 保留；新增 `willExpireInDays` 统一判定，`isExpired` 改为语义等价委托 |
| 数据模型 `entry.times.expires` / `entry.times.expiryTime` | kdbxweb `KdbxEntry.times` | 直接读取，无需改 kdbxweb |
| 过期视觉标记（C45_Expired 图标 + 删除线） | `DatabaseView.ets:2548`、`TotpView.ets:283-303`、`EntryView.ets:341-342` | 新列表页直接复用 |
| 提示条 UI 模式（含"不再提示"按库记忆） | `DatabaseView.ets:799-832`（逻辑）+ `:2711-2747`（UI） | 到期提醒提示条完全对齐此模式 |
| 设置项规范（`KEY_*` + `*_DEFAULT` 成对常量） | `services/SettingsService.ets:37-74` | 新增 4 组常量对 |
| 安全设置页 UI 模式 | `pages/setting/SettingSecurity.ets:72-139` | 新增开关 + 天数选择器 |
| 路由表注册模式 | `resources/base/profile/route_map.json` + `NavigationManager`/`PageConstants` | 新增临期列表页 |
| 搜索基础设施（`searchInGroup`/`searchInEntries`） | `common/utils/KdbxUtils.ets:155-257` | 扩展支持 `is:expired` 语法 |
| 解锁完成时机 | `DatabaseView.loadDatabase()`（`DatabaseView.ets:542-562`，Password 页 `KdbxLoadService.loadDatabase` 完成后进入） | 提醒判定的唯一触发点，在 `initData` 完成后调用 |
| 回收站排除 | `Kdbx.isInRecycleBin(entry)`（`searchInGroup` 已用） | 临期收集时同样排除 |

---

## 四、方案设计

### 4.1 核心判定逻辑（照搬 KeePassXC）

在 `DateUtils` 中新增统一判定，一个方法覆盖两种语义：

```typescript
/**
 * 条目是否在 N 天内到期（含已过期）。
 * 对齐 KeePassXC Entry::willExpireInDays（Entry.cpp:482-484）。
 * @param expires 条目 times.expires
 * @param expiryTime 条目 times.expiryTime
 * @param days 天数；0 表示仅已过期
 */
public static willExpireInDays(expires: boolean, expiryTime: Date | undefined, days: number): boolean {
  if (!expires || !expiryTime) {
    return false;
  }
  return expiryTime.getTime() < new Date().getTime() + days * 24 * 60 * 60 * 1000;
}

public static isExpired(expires: boolean, expiryTime: Date | undefined): boolean {
  return DateUtils.willExpireInDays(expires, expiryTime, 0);
}
```

> 注意：现有 `isExpired(isEnableExpire, date)` 签名两参语义与 KeePassXC 相同，改为委托 `willExpireInDays(..., 0)` 后所有现有调用点（`DatabaseView`/`TotpView`/`EntryView`/`AutoOpenService` 等）无需修改。

### 4.2 提醒策略（防打扰，本项目改进点）

```
解锁成功（DatabaseView.loadDatabase → initData 完成后）
  └─ ExpiryRemindService.evaluate(database, iocKey)
       ├─ 设置开关关闭 → 不提醒
       ├─ 收集临期条目（willExpireInDays(N)，N=设置天数；排除回收站）→ 为 0 → 不提醒
       ├─ 防打扰：lastRemindTime[iocKey] 距今 < 间隔（默认 24h，可选"每次"）→ 不提醒
       └─ 通过 → 返回条目数与列表，DatabaseView 显示提示条；记录 lastRemindTime[iocKey]
```

- **按库记忆**：`iocKey` 作为键（与 `childDbHintHiddenKey(iocKey)` 模式一致，见 `SettingsService.ets`），多库切换互不干扰；
- **点击提示条"查看"** → 跳转临期列表页；点击"不再提示" → 本库隐藏至下一天（不清 `lastRemindTime`，单独 `hidden` 标记，语义与子库提示条一致）；
- **跳过本次**（用户不点提示条，仅离开页面）→ `lastRemindTime` 已更新，24h 内不再弹；下次进入库若仍有临期条目会再次提示。

### 4.3 UI 设计

**1. 提示条（DatabaseView 根组视图底部，复用子库提示条样式）**：

```
┌──────────────────────────────────────────┐
│ ⚠ 3 个条目已过期或将在 7 天内到期  [查看] │
│                        不再提示(今日)      │
└──────────────────────────────────────────┘
```

- 位置、避让逻辑（面包屑 36vp 上移、移动/选择模式隐藏）与子库提示条（`DatabaseView.ets:2711-2747`）完全一致；
- 仅根组视图显示（与子库提示条相同判定 `currentGroup.parentGroup === undefined`）；
- 两条提示条共存时，到期提醒条显示在子库提示条上方。

**2. 临期/过期条目列表页（新页面 `ExpiryReport`）**：

- 标题："到期提醒"；两个分段：`已过期` | `N 天内到期`（Tab 或 SegButton）；
- 条目行复用现有样式（图标含 C45_Expired 替换 + 标题删除线 + 分组路径），点击进入 `EntryView`；
- 支持按剩余天数排序（过期最久的在前 / 最紧急的在前）；
- 搜索框可过滤本列表（复用 `KdbxUtils.searchInEntries`）。

**3. 安全设置页新增（SettingSecurity）**：

| 设置项 | 控件 | 默认值 |
|---|---|---|
| 到期提醒 | Toggle | 开 |
| 提醒天数 | 选择器（1/3/7/14/30 天） | 7 天 |
| 提醒频率 | 选择器（每次解锁 / 每 24 小时一次） | 每 24 小时一次 |

> 天数默认值取 KeePass（7）与 KeePassXC（3）折中：**7 天**更符合密码轮换周期直觉；开关默认开启（对齐 KeePassXC）。

### 4.4 搜索语法增强（二期，对齐 KeePassXC）

- `is:expired` → 已过期；`is:expired-7` → 7 天内到期；
- 在 `KdbxUtils.searchInGroup` 入口处识别 `is:expired` 前缀语法（不进入文本匹配路径），过滤条件 `willExpireInDays(N) && !isInRecycleBin(entry)`；
- 搜索历史可正常记录（无需特殊处理）；
- 借鉴 KeePassXC `TagModel.cpp:32` 的虚拟标签思路，二期可在搜索页放"已过期"快捷 chip。

### 4.5 EntryView 增强（二期，小改动）

条目详情页过期时间字段旁展示"剩余 N 天"（`<0` 显示"已过期 X 天"），并在临期（≤7 天）时字段文案着警示色。

---

## 五、详细改动清单

### 5.1 新增文件

| 文件 | 内容 |
|---|---|
| `entry/src/main/ets/services/ExpiryRemindService.ets` | 提醒判定服务（单例）：`evaluate(database: Kdbx, iocKey: string): ExpiryRemindResult`；内部读取设置、收集条目、防打扰判定、写 `lastRemindTime`。`ExpiryRemindResult` 类：`expiredCount`、`expiringCount`、`expiredEntries: KdbxEntry[]`、`expiringEntries: KdbxEntry[]` |
| `entry/src/main/ets/pages/ExpiryReport.ets` | 临期/过期条目列表页（`@Entry` 之外的普通页面组件，NavDestination 根节点），含分段、排序、搜索、条目行；`ExpiryReportBuilder` 导出 |
| `entry/src/ohosTest/ets/test/DateUtilsWillExpire.test.ets` | `willExpireInDays` 边界单测（见 7.1） |
| `entry/src/ohosTest/ets/test/ExpiryRemindService.test.ets` | 防打扰/收集逻辑单测（见 7.2） |

### 5.2 修改文件

| 文件 | 改动 |
|---|---|
| `common/utils/DateUtils.ets` | 新增 `willExpireInDays()`；`isExpired()` 改为委托实现（签名不变） |
| `services/SettingsService.ets` | 新增常量对：`KEY_SECURITY_EXPIRE_REMIND_ENABLE`（默认 true）、`KEY_SECURITY_EXPIRE_REMIND_DAYS`（默认 7）、`KEY_SECURITY_EXPIRE_REMIND_FREQUENCY`（默认 24h 枚举）、`expiryRemindLastTimeKey(iocKey)`/`expiryRemindHiddenKey(iocKey)` 动态键方法（对齐 `childDbHintHiddenKey`） |
| `services/ExpiryRemindService.ets`（新增，见 5.1） | — |
| `common/constants/PageConstants.ets` | 新增 `PAGE_EXPIRY_REPORT = 'ExpiryReport'` |
| `common/constants/NavigationConstants.ets` | 如有页面标题常量则补充 |
| `resources/base/profile/route_map.json` | 注册 `ExpiryReport` 路由 |
| `pages/DatabaseView.ets` | ① 新增 `@State expiryRemindResult`/`@State showExpiryHint`；② `loadDatabase()` 的 `initData` 完成后调用 `updateExpiryHint()`（对齐 `updateChildDbHint()` 调用时机：`initData`、`navigateToParentGroup`、子分组导航处）；③ 提示条 UI（复制子库提示条结构，位于其上方）；④ `dismissExpiryHint()`（按库写 hidden 标记） |
| `pages/setting/SettingSecurity.ets` | 新增"到期提醒"设置区块：开关 + 天数选择器 + 频率选择器（对齐现有 `quickLockPasswordLength` 选择器模式） |
| `pages/ExpiryReport.ets`（新增，见 5.1） | — |
| `common/utils/KdbxUtils.ets`（二期） | `searchInGroup`/`searchInEntries` 识别 `is:expired(-N)?` 语法；新增 `collectExpiring(group, days, database): KdbxEntry[]`（其实现在一期由 ExpiryRemindService 内部实现，二期提升到 KdbxUtils 供搜索复用） |
| `pages/EntryView.ets`（二期） | 过期字段旁"剩余 N 天"展示 |
| 资源文件 `resources/base/element/string.json` + `zh_CN/` + `en_US/` | 新增字符串：`expiry_remind_banner_text`（带 `%d` 占位）、`expiry_remind_view`、`expiry_remind_dismiss_today`、`expiry_report_title`、`expiry_report_tab_expired`、`expiry_report_tab_expiring`、`expiry_report_remaining_days`、设置页标题/选项文案等 |

### 5.3 不需要修改的部分

- **kdbxweb 模块**：`times.expires/expiryTime` 数据完整，无需改动；
- **现有 `isExpired` 调用点**（`DatabaseView`/`TotpView`/`EntryView`/`AutoOpenService`）：签名不变，零改动；
- **module.json5**：无新权限（不涉及通知/后台任务，那在三期）。

---

## 六、分阶段开发计划

### M1 — 核心提醒（一期，预计 5-7 人天）

| # | 任务 | 涉及文件 | 工作量 | 验收标准 |
|---|---|---|---|---|
| 1.1 | `DateUtils.willExpireInDays` + `isExpired` 委托改造 | `DateUtils.ets` | 0.5 天 | 单测通过；现有调用点行为不变 |
| 1.2 | 设置项常量 + 动态键方法 | `SettingsService.ets` | 0.5 天 | 跨设备同步（`SyncSettingsService`）不报错 |
| 1.3 | `ExpiryRemindService`：收集 + 防打扰判定 | 新文件 | 1.5 天 | 单测通过（含防打扰边界） |
| 1.4 | DatabaseView 提示条 + 触发时机 | `DatabaseView.ets` | 1 天 | 解锁后正确显示/隐藏；与子库提示条共存正常；面包屑避让正常 |
| 1.5 | `ExpiryReport` 列表页 + 路由 | 新文件 + `route_map.json` + 常量 | 1.5 天 | 分段切换、排序、搜索、点击进条目详情、返回正常 |
| 1.6 | 设置页 UI | `SettingSecurity.ets` | 1 天 | 开关/天数/频率持久化生效；关闭开关后提示条不出现 |
| 1.7 | 多语言字符串 | string.json ×3 | 0.5 天 | 中英文无缺漏 |
| 1.8 | E2E 用例 | `docs/e2e` 扩展 | 0.5 天 | 场景脚本通过 |

### M2 — 搜索语法与详情增强（二期，预计 3-4 人天）

| # | 任务 | 验收标准 |
|---|---|---|
| 2.1 | `is:expired` / `is:expired-N` 搜索语法（`KdbxUtils`） | 搜索"已过期条目"准确；回收站条目不出现；与普通关键词搜索不冲突 |
| 2.2 | 搜索页"已过期"快捷 chip | 点击填入 `is:expired` |
| 2.3 | EntryView 剩余天数展示 + 临期着色 | 显示正确；过期条目显示"已过期 X 天" |

### M3 — 后台通知（三期，先评估再立项，预计 5+ 人天）

**前提与安全权衡**（对应调研结论"三家都没有系统通知"的原因）：

- 数据库锁定后主密钥不驻留内存，无法重新解密计算临期条目；
- 若要做，需在**解锁期间缓存"临期条目元数据"**（条目标题/到期时间/所属库），存在明文元数据落盘风险；
- 缓解方案：元数据经 HUKS/Asset Kit 加密（参考 `Sm4Utils` + `AssetUtils` 现有模式），缓存仅含标题与到期时间不含密码字段，**默认关闭、用户显式开启**；
- 触发：`@ohos.resourceschedule.workScheduler` 周期任务（约每日一次）→ 解密缓存 → `NotificationManager` 本地通知（参考 `SessionNotificationService` 发布模式）。

**验收标准（若立项）**：锁定状态下收到"3 个条目将于 7 天内到期"通知；点击通知拉起应用解锁页；缓存数据加密可审计；关闭开关后任务注销、缓存清除。

---

## 七、测试计划

### 7.1 `DateUtils.willExpireInDays` 单测（ohosTest，Hypium）

| 用例 | 输入 | 预期 |
|---|---|---|
| 未启用过期 | `expires=false, expiryTime=昨天` | false（任意 days） |
| expiryTime 为空 | `expires=true, undefined` | false |
| 已过期 | `expiryTime=昨天, days=0` | true |
| 刚好临界 | `expiryTime=当前时间+1ms, days=0` | false |
| N 天内 | `expiryTime=+6天, days=7` | true |
| 恰好第 N 天边界 | `expiryTime=+7天+1ms, days=7` | false |
| 大 N 含已过期 | `expiryTime=-30天, days=30` | true |
| 回归：isExpired 委托 | 原有调用语义 | 与改造前一致 |

### 7.2 `ExpiryRemindService` 单测

- 开关关闭 → 不提醒；
- 天数=0（若允许）→ 仅已过期；无临期条目 → 不提醒；
- 回收站中的过期条目不计入；
- 防打扰：`lastRemindTime` 23h 前 → 不提醒；25h 前 → 提醒并更新时间戳；
- 频率=每次解锁 → 无视时间戳；
- 多库隔离：A 库提醒不影响 B 库。

### 7.3 E2E 场景（扩展 `docs/e2e`，真机 uitest）

1. 构造测试库：含 1 条已过期、1 条 3 天内到期、1 条 30 天后到期、回收站 1 条已过期条目；
2. 解锁 → 提示条显示"2 个条目…"；
3. 点"查看" → 列表页两分段分别为 1/1 条；回收站条目不出现；
4. 点条目 → 进入详情；返回 → 列表状态保持；
5. 点"不再提示(今日)" → 提示条消失；杀进程重启解锁 → 24h 内不再提示；
6. 设置改天数=30 → 重新解锁 → 提示"3 个条目"（30 天后到期条目计入）；
7. 关闭开关 → 提示条不出现。

### 7.4 手工回归清单

- 与子库提示条共存布局（分栏/单栏、面包屑上/下位置、移动/选择模式下均隐藏）；
- 多库切换后提示条按当前库正确显示/隐藏；
- 下拉刷新（`DATABASE_RELOAD` 路径）后提示条状态正确（刷新不应重复弹提醒——`loadDatabase` 会被 `reloadDatabase` 复用，需在 `updateExpiryHint` 中区分"首次加载"与"刷新"，仅首次触发防打扰计时与提示）；
- 主题切换、深色模式下提示条样式正常。

---

## 八、风险与注意事项

| 风险 | 影响 | 缓解 |
|---|---|---|
| `loadDatabase()` 复用于首次解锁与 `DATABASE_RELOAD` 刷新两条路径，刷新会重复触发提醒 | 防打扰时间戳被无意义消耗/提示条闪现 | `updateExpiryHint` 增加触发来源参数（对齐 `updateChildDbHint` 仅在分组导航时刷新显示、不重置记忆的做法）；提示条显示状态可刷新，但 `lastRemindTime` 仅在"解锁后的首次 initData"写入 |
| `DatabaseView.ets` 已 3100+ 行，继续膨胀 | 可维护性 | 提示条 UI 抽为 `@Builder` 或独立组件（放 `components/ExpiryHintBar.ets`），判定逻辑全部收敛在 `ExpiryRemindService` |
| 时间比较使用毫秒时间戳，设备时区/时间被用户改动 | 误报/漏报 | 与现有 `isExpired` 一致（直接比较 `Date.getTime()`），不做额外时区处理；KeePassXC 同样直接比较 |
| `willExpireInDays` 使用 `当前时间 + N*24h` 而非 KeePass 的"当天 23:59:59" | 边界语义差异（差几小时） | 可接受；如需对齐可在实现中取本地当日 23:59:59 为上界（在单测中固定该语义） |
| 提示条文案带数量占位符，多语言复数形态 | 翻译质量问题 | 中文无复数问题；英文用 "entry/entries" 简单处理（现有项目规模下可接受） |
| 设置项进入跨设备同步（`SyncSettingsService` 白名单） | 同步冲突 | 新键默认值稳定；若同步服务按键白名单同步则确认是否纳入（与现有 `KEY_SECURITY_*` 同策略） |

---

## 九、交付物清单

- [ ] `DateUtils.willExpireInDays` + 单测
- [ ] `ExpiryRemindService` + 单测
- [ ] `ExpiryReport` 页面 + 路由注册
- [ ] `DatabaseView` 提示条（含与子库提示条共存、面包屑避让）
- [ ] `SettingSecurity` 到期提醒设置区块（开关/天数/频率）
- [ ] 中英文字符串资源
- [ ] E2E 场景脚本（`docs/e2e`）
- [ ] 二期：`is:expired` 搜索语法 + EntryView 剩余天数
- [ ] 三期评估报告：后台通知安全方案（如立项）
