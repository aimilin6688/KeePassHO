# 鸿蒙 UI 自动化测试指南（KeePassHO 实测版）

> 调研 + 设备实测：2026-09-24，设备 `127.0.0.1:5555`，`uitest` 版本 **6.0.2.3**
> 官方文档：[UI测试框架使用指导](https://device.harmonyos.com/cn/docs/apiref/harmonyos-guides/uitest-guidelines)、[js-apis-uitest](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-uitest)

HarmonyOS 官方提供**两套** UI 自动化能力，底层是同一套 UITest 框架（客户端在应用进程，服务端是独立进程 SA 5502，通过 IPC 通信）：

| | A. 命令行 `hdc shell uitest` | B. ArkTS 脚本（`@kit.TestKit`） |
|---|---|---|
| 上手成本 | 零代码，立即可用 | 需写用例，放进 `entry/src/ohosTest` |
| 定位方式 | **坐标驱动**（物理像素） | **控件属性驱动**：text / id / type / 相对位置 |
| 断言 | 无，需自己解析控件树 | 有：`assertComponentExist`、`waitForComponent`、`expect()` |
| 事件监听 | 无 | 有：`createUIEventObserver()` 监听 toast / dialog |
| 录制回放 | 有：`uiRecord record/read` | 无 |
| 适合场景 | 临时验证、AI 核对 UI、探索性操作 | CI 回归、正式 UI 测试用例 |

**结论：日常改完 UI 快速核对用 A；要沉淀成可回归的测试用例用 B。**

---

## A. 命令行方式（已在本机实测通过）

### 命令全景（`hdc shell uitest help` 实测输出）

| 命令 | 参数 | 说明 |
|---|---|---|
| `screenCap` | `-p <savePath>` `-d <displayId>` | 截图 |
| `dumpLayout` | `-p` `-i` `-a` `-b <bundle>` `-w <windowId>` `-m` `-d` | 导出控件树 JSON |
| `uiRecord` | `record` / `read`（`-W` `-l` `-c`） | 录制界面操作到 `/data/local/tmp/record.csv` |
| `uiInput` | `click` `doubleClick` `longClick` `fling` `swipe` `drag` `dircFling` `inputText` `text` `keyEvent` | 注入模拟操作 |
| `start-daemon` | `<token>` | 拉起测试进程 |
| `--version` | — | 版本 |

### 常用命令

```bash
HDC="D:/Software/HarmonyOS/command-line-tools/sdk/default/openharmony/toolchains/hdc.exe"
DEV="-t 127.0.0.1:5555"

# 控件树（推荐按包名过滤，只拿当前应用的窗口）
"$HDC" $DEV shell "uitest dumpLayout -b com.aimilin.keepassho -p /data/local/tmp/layout.json"

# 取回本地（必须带 MSYS_NO_PATHCONV=1，且用相对路径，否则 Git Bash 会做路径转换）
cd .workbuddy && MSYS_NO_PATHCONV=1 "$HDC" $DEV file recv /data/local/tmp/layout.json ./layout.json

# 点击 / 双击 / 长按
"$HDC" $DEV shell "uitest uiInput click 819 1327"
"$HDC" $DEV shell "uitest uiInput doubleClick 819 1327"
"$HDC" $DEV shell "uitest uiInput longClick 819 1327"

# 滑动 / 拖拽（velocity 200-40000，默认 600）
"$HDC" $DEV shell "uitest uiInput swipe 100 1000 900 1000 600"
"$HDC" $DEV shell "uitest uiInput drag 10 10 100 100 500"
"$HDC" $DEV shell "uitest uiInput dircFling 3"        # 0左 1右 2上 3下

# 文本输入（指定坐标点 / 当前获焦处）
"$HDC" $DEV shell "uitest uiInput inputText 1889 347 hello"
"$HDC" $DEV shell "uitest uiInput text hello"

# 按键：Back / Home / Power，或 KeyCode（组合键：Ctrl+V = 2072 2038，Shift+V = 2047 2038）
"$HDC" $DEV shell "uitest uiInput keyEvent Back"
"$HDC" $DEV shell "uitest uiInput keyEvent 2047 2038"

# 录制（Ctrl+C 结束）
"$HDC" $DEV shell "uitest uiRecord record -W true -l"
"$HDC" $DEV shell "uitest uiRecord read"
```

### 控件树结构（实测）

导出的是嵌套 JSON，每层 `{"attributes": {...}, "children": [...]}`，关键属性：

```
bounds      "[499,1274][1139,1380]"   物理像素，中心点即点击坐标
type        "Text" / "ListItem" / "TextInput" / "Select" / "Checkbox" / "BackButton" ...
text        可见文本
id          组件 id（本项目大量为空，见下方"落地建议"）
clickable   "true" / "false"
enabled / checked / selected / scrollable / focused
pagePath    "pages/AppNavigation"  所属页面
bundleName / abilityName / hostWindowId / hierarchy
```

### 本次实测记录（真实输出，非推断）

| 步骤 | 命令 | 实测结果 |
|---|---|---|
| 导出控件树 | `dumpLayout -b com.aimilin.keepassho` | 成功，76KB，命中 49 个可交互/有文本节点 |
| 点击导航「关于」 | `uiInput click 819 1327` | 返回 `No Error` |
| 验证页面跳转 | 再次 `dumpLayout` | 主区文本从「修改主密码」变为「关于 / 版本: 1.10.0 / 意见反馈 / 给个好评 / 支持作者」✅ |
| 点击「安全设置」 | `uiInput click 819 553` | 主区变为「启用下拉刷新数据库 / 启用搜索历史 / 启用隐私窗口 …」✅ |

**即：命令行方式已能完整跑通「导航 → 点击 → 验证页面结果」的闭环。**

---

## B. ArkTS 脚本方式（正式 UI 测试用例）

### 依赖与位置

```typescript
import { describe, expect, it, Level, TestType, Size } from '@ohos/hypium';
import { abilityDelegatorRegistry, Driver, ON, Component, UiWindow,
         PointerMatrix, UiDirection, MouseButton, UIElementInfo,
         DisplayRotation, Point } from '@kit.TestKit';
import { UIAbility, Want } from '@kit.AbilityKit';
import { KeyCode } from '@kit.InputKit';
```

用例放在 `entry/src/ohosTest/ets/test/`，并在 `List.test.ets` 里 import + 调用注册。

### 标准用例骨架（拉起应用 → 查找 → 点击 → 断言）

```typescript
const delegator = abilityDelegatorRegistry.getAbilityDelegator();

export default function SettingsNavigationTest() {
  describe('SettingsNavigationTest', () => {
    it('navigateToAbout', Level.LEVEL3, async (done: Function) => {
      const driver: Driver = Driver.create();
      const bundleName: string = abilityDelegatorRegistry.getArguments().bundleName;

      await delegator.startAbility({ bundleName: bundleName, abilityName: 'EntryAbility' });
      await driver.waitForIdle(4000, 5000);

      const ability: UIAbility = await delegator.getCurrentTopAbility();
      expect(ability.context.abilityInfo.name).assertEqual('EntryAbility');

      // 按文本定位并点击
      const about = await driver.findComponent(ON.text('关于'));
      await about.click();
      await driver.waitForIdle(4000, 5000);

      // 断言目标页面内容出现
      await driver.assertComponentExist(ON.text('版本: 1.10.0'));
      await driver.pressBack();
      done();
    })
  })
}
```

### Driver 核心 API

| 类别 | API |
|---|---|
| 查找 | `findComponent(On)` `findComponents(On)` `waitForComponent(On, timeout)` `findWindow({active:true})` |
| 断言/等待 | `assertComponentExist(On)` `waitForIdle(timeout, interval)` `delayMs(ms)` `pressBack()` |
| 触摸（坐标） | `click(x,y)` `swipe(...)` `fling(...)` `drag(...)` `injectMultiPointerAction(PointerMatrix)`；`clickAt/swipeBetween/dragBetween`（API 20+ 支持指定 displayId） |
| 文本输入 | `inputText(point, text)` / `inputText(point, text, {paste, addition})`（API 20+） |
| 键鼠 | `triggerKey(KeyCode)` `triggerCombineKeys(k1,k2)` `mouseClick(point, MouseButton)` `mouseMoveTo` `mouseDrag` `mouseScroll` `mouseLongClick` |
| 触摸板/手写笔/表冠 | `touchPadMultiFingerSwipe(3, UiDirection.UP)` `penClick/penSwipe` `crownRotate`（仅智能表） |
| 屏幕 | `getDisplaySize()` `getDisplayDensity()` `wakeUpDisplay()` `setDisplayRotation()` |
| 截图 | `screenCapture(path, {left,top,right,bottom})`、`screenCap(path, displayId)`（API 20+） |
| 事件监听 | `createUIEventObserver()` → `observer.once('toastShow', cb)` |

### On 匹配器（链式构造）

```typescript
ON.text('关于')                              // 按文本
ON.id('my_button')                          // 按 id
ON.type('Button')                           // 按类型
ON.text('123').within(ON.type('Scroll'))    // 在 Scroll 内查找
ON.text('456').isBefore(ON.text('123'))     // 相对位置：在 text=123 之前的第一个 456
ON.text('abc').isAfter(ON.text('def'))
```
多属性可组合（如同时指定 text 和 id）。**On 全是同步接口**，Driver/Component 全是异步（必须 `await`）。

### Component 方法

`click()` `doubleClick()` `longClick()` `pinchOut(scale)` `inputText(text[, opts])` `getBoundsCenter()` `getText()` `getId()` `getType()` `isEnabled()` …

### 运行用例

```bash
# 全量
"$HDC" $DEV shell "aa test -b com.aimilin.keepassho -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000"
# 指定测试类
"$HDC" $DEV shell "aa test -b com.aimilin.keepassho -m entry_test -s unittest OpenHarmonyTestRunner -s class SettingsNavigationTest -s timeout 60000"
```

---

## 事件触发验证怎么做

「确定某个事件是否触发」有四种手段，按可靠性排序：

1. **断言目标控件出现/消失** — `driver.assertComponentExist(ON.text('保存成功'))`、`waitForComponent(...)`
2. **监听 toast / dialog** — `driver.createUIEventObserver()` + `observer.once('toastShow', cb)`，回调拿到 `UIElementInfo`（bundleName / text / type）。**这是验证「事件是否触发」最直接的手段。**
3. **对比控件树/属性** — 操作前后各 dump 一次，diff `text` / `checked` / `enabled`（命令行方式只能这么做）
4. **截图比对** — `screenCap` 前后对比（最弱，只做兜底）

---

## 已知限制与坑（官方文档明确 + 实测）

1. **异步接口必须 `await`**，否则报 `uitest-api does not allow calling concurrently`。
2. **不支持多进程跑 UI 用例**；也不要和其它依赖 UITest 的工具同时跑，否则报 `Cannot connect to AAMS, RET_ERR_CONNECTION_EXIST`。
3. **控件对象会因页面变化失效**：`does not exist on current UI! Check if the UI has changed after you got the widget object`。每次页面跳转后重新 `findComponent`。
4. **命令行 `dumpLayout` / `screenCap` 的保存路径只能是 `/data/local/tmp/`**；ArkTS 里 `screenCapture` 的路径必须是应用沙箱（normal 级 HAP 用 `/data/storage/el2/base/cache/xxx.png`）。
5. **坐标是设备物理像素**（本机 3120x2080），不是 vp。
6. `dumpLayout` 的 `-a` 与 `-i` 不能同时使用。
7. 大写锁定键（KeyCode 2074）注入无效，用组合键代替。
8. 输入文本含中文/特殊字符时只能走粘贴，`paste` 字段不生效；纯英文且 ≤200 字符才逐字键入。
9. 窗口最小化、触摸板手势在不支持的设备上抛错误码 `17000005`；表冠抛 `801`。
10. Git Bash 下取回文件必须 `MSYS_NO_PATHCONV=1` + 相对路径（否则路径被转换报 `operation not permitted`）。

---

## 本项目落地建议

### 实测更正：项目已有 39 个 `.id()`

【2026-09-24 更正】上一版我基于单次 `dumpLayout` 采样（当时停在设置页）得出「业务控件 id 几乎全为空」——**这个结论不准确**。全量 grep 后，项目已在关键交互控件上定义了 **39 个 id**：

| 页面 | 已有 id |
|---|---|
| Password | `select_auth_type` `input_password` `btn_unlock` `btn_change_database` `btn_select_key_file` |
| UnLockDatabase | `input_quick_password` `btn_quick_unlock` `btn_close_database` |
| DatabaseView | `input_search` `btn_add_fab` `btn_add_group` `btn_add_entry` `btn_move_here` `btn_cancel_move` `btn_batch_move` `btn_batch_delete` `btn_cancel_selection` |
| EntryView | `btn_rollback` `btn_delete_history` |
| FileList | `btn_retry` `btn_cancel` `btn_confirm` |
| ChangePassword | `input_old_password` `input_new_password` `input_confirm_password` `btn_create_key_file` `btn_cancel` `btn_confirm` |
| SettingDatabaseMeta / KeyFunction | `btn_cancel` `btn_save` `input_iterations` `input_memory` `input_parallelism` `input_rounds` |
| SettingCustomIcons | `key_<iconId>` `btn_delete_unused` `btn_delete_icons` |

**这些页面可以直接用 `ON.id()` 稳定定位。** 真正缺 id 的是：Settings 各菜单项、`MoreActionsMenu`（收藏/置顶/编辑/选择/删除）、左滑快捷按钮 —— 这些目前只能靠 `ON.text()`，文案变更或多语言会导致用例失效。

**建议补 id 的范围**（按优先级）：Settings 菜单项、DatabaseView 更多菜单与左滑按钮、各存储配置页的输入框与「测试连接」按钮。

```typescript
ListItem() { ... }
  .id('nav_about')        // 导航：关于
Button($r('app.string.save'))
  .id('btn_save')         // 主按钮
TextInput({ placeholder: ... })
  .id('input_server_url')
```

### 推荐的分工

| 场景 | 用哪套 |
|---|---|
| 改完 UI 立刻看效果（当前已在用） | 命令行 `dumpLayout` + `uiInput` |
| AI 自主核对深层页面 | 命令行 + Python 解析控件树 |
| 沉淀核心流程回归（导航、创建/打开数据库、保存） | ArkTS + Hypium，加进 `List.test.ets` |
| 验证 toast / 弹窗是否触发 | ArkTS `createUIEventObserver()` |

### 建议优先覆盖的流程

1. 导航到各设置页并断言标题控件存在
2. 打开/创建数据库 → 输入主密码 → 断言进入数据库视图
3. 修改主密码 → 断言 toast「修改成功」
4. 切换主题 → 断言背景色属性变化

---

## 已落地的控件 id 清单（2026-09-24 全量补齐）

命名约定：`<前缀>_<语义>`，前缀 `input_` 输入框 / `btn_` 按钮 / `select_` 下拉 / `key_` 动态键（图标）。测试里用 `ON.id('...')` 定位。

### 解锁链路

| 文件 | id | 控件 |
|---|---|---|
| Password.ets | `select_auth_type` | 认证方式下拉 |
| Password.ets | `input_password` | 主密码输入框 |
| Password.ets | `btn_change_database` | 更换数据库 |
| Password.ets | `btn_unlock` | 解锁数据库 |
| Password.ets | `btn_select_key_file` | 选择密钥文件 |
| UnLockDatabase.ets | `input_quick_password` | 快速解锁密码输入 |
| UnLockDatabase.ets | `btn_close_database` | 关闭数据库 |
| UnLockDatabase.ets | `btn_quick_unlock` | 快速解锁 |

### DatabaseView（数据库视图）

| 文件 | id | 控件 |
|---|---|---|
| DatabaseView.ets | `input_search` | 搜索框 |
| DatabaseView.ets | `btn_add_fab` | 悬浮添加球 |
| DatabaseView.ets | `btn_add_group` | 添加分组 |
| DatabaseView.ets | `btn_add_entry` | 添加条目 |
| DatabaseView.ets | `btn_batch_move` | 选择模式-移动 |
| DatabaseView.ets | `btn_batch_delete` | 选择模式-删除 |
| DatabaseView.ets | `btn_cancel_selection` | 选择模式-取消 |
| DatabaseView.ets | `btn_move_here` | 移动模式-移动到此处 |
| DatabaseView.ets | `btn_cancel_move` | 移动模式-取消 |

### 条目 / 修改主密码

| 文件 | id | 控件 |
|---|---|---|
| EntryView.ets | `btn_rollback` | 回滚到历史 |
| EntryView.ets | `btn_delete_history` | 删除历史 |
| ChangePassword.ets | `input_old_password` / `input_new_password` / `input_confirm_password` | 三个密码输入框 |
| ChangePassword.ets | `btn_create_key_file` | 创建新密钥文件 |
| ChangePassword.ets | `btn_cancel` / `btn_confirm` | 取消 / 确认 |

### 文件列表 / 设置页

| 文件 | id | 控件 |
|---|---|---|
| FileList.ets | `btn_retry` | 加载失败重试 |
| FileList.ets | `btn_cancel` / `btn_confirm` | 取消 / 确认 |
| SettingDatabaseMeta.ets | `btn_cancel` / `btn_save` | 取消 / 保存 |
| SettingDatabaseKeyFunction.ets | `input_iterations` / `input_memory` / `input_parallelism` / `input_rounds` | KDF 参数输入框 |
| SettingDatabaseKeyFunction.ets | `btn_cancel` / `btn_save` | 取消 / 保存 |
| SettingCustomIcons.ets | `btn_delete_unused` / `btn_delete_icons` | 清理未引用 / 删除图标 |
| SettingCustomIcons.ets | `key_<iconId>`（原有） | 图标项 |

**新增控件时请在对应表格补登记**；同名语义（取消/确认）跨页复用同名 id，`ON.id` 配合 `ON.type` 或页面上下文区分。

---

## 实战踩坑（2026-09-25：首个 UI 用例「打开本地数据库」落地）

首个 UI 用例在 `entry/src/ohosTest/ets/test/ui/OpenDatabaseUiTest.ets`，9 个用例全通过。过程中踩到的坑，写新用例前务必先读：

### 坑 1：`ON.text()` 会被隐藏根栈干扰，产生假阳性

`AppNavigation.ets` 用 `Stack` 常驻 **4 个根导航栈**（Index / DatabaseView / TotpView / Settings），靠 `visibility` 切换。UITest 的匹配树**包含未显示的栈**，所以：

- 在解锁页也能 `ON.text('打开数据库')` → 命中 Index 栈（隐藏）
- 在解锁页也能 `ON.text('更换数据库')` → 解锁页本身就有这个按钮

**结果**：断言永远为真，测试假通过。

**解法**：定位一律用 `ON.id()`；命中后再校验 `getBounds()` 落在窗口可视区内（`driver.findWindow({bundleName}).getBounds()`）。隐藏栈的控件 bounds 会落在窗口之外。

### 坑 2：`Image` 的 `id` 不进匹配树

`Image(...).id('xxx')` 无效——`ON.id('xxx')` 找不到，且 `Image` 的 `isClickable()` 恒为 false（即使挂了 `onClick`）。

**解法**：用 `Stack`/`Row` 包一层，把 `id` 和 `onClick` 挂到容器上：

```typescript
Stack() {
  Image($r('app.media.ic_settings'))
    .width(24).height(24)
}
.id('btn_open_settings')
.onClick(() => { /* ... */ })
```

### 坑 3：锚点控件必须是「无条件渲染」的

`DatabaseView.ets` 的 `input_search` 只在 `isSearching === true` 时才渲染，**不能作为「已进入数据库页」的判据**。选锚点前先确认它没有 `if` 包裹——`btn_add_fab` 可用。

### 坑 4：设置页是导航根页，连按返回键会退出应用

从 Settings 栈内的子页（位置选择 → 本地文件）返回时，pop 到 Settings 后再 `pressBack()` 会**直接退出应用**，后续所有查找失败。

**解法**：pop 掉子页后，点设置页左上角的返回按钮（`btn_settings_back`）回首页。

### 坑 5：本地文件选取是系统 `DocumentViewPicker`，跨应用不可达

`storage/local/LocalFilePage.ets` 用 `picker.DocumentViewPicker` 拉起系统文件选择器。点「选择本地文件」后应用窗口被遮挡，`dumpLayout` 返回空，UI 测试无法继续。

**解法**：用例覆盖到「拉起系统选择器之前」（断言 `btn_select_local_file` 可见），随后从「最近打开的数据库」选 `test-1.kdbx` 走完解锁流程。

### 坑 6：冷启动会停在解锁页

有最近文件时，`EntryAbility` 预加载后**自动跳转解锁页**，不停留在首页。用例要按此设计前置状态。

### 运行命令

```bash
HDC="D:/Software/HarmonyOS/command-line-tools/sdk/default/openharmony/toolchains/hdc.exe"

# 编译（主包 + 测试包）
NODE_OPTIONS= "D:/Software/HarmonyOS/command-line-tools/bin/hvigorw.bat" \
  --mode module -p product=default -p buildMode=debug assembleHap --no-daemon
NODE_OPTIONS= "D:/Software/HarmonyOS/command-line-tools/bin/hvigorw.bat" \
  --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap --no-daemon

# 安装
"$HDC" -t 127.0.0.1:5555 install -r entry/build/default/outputs/default/entry-default-signed.hap
"$HDC" -t 127.0.0.1:5555 install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap

# 执行（只跑 UI 套件，别和单元测试混跑）
"$HDC" -t 127.0.0.1:5555 shell "aa test -b com.aimilin.keepassho -m entry_test \
  -s unittest OpenHarmonyTestRunner -s class OpenDatabaseUiTest -s timeout 180000"
```

> 改了主包业务代码（补 id）后，**主包和测试包都要重新安装**，否则测试跑的是旧控件树。
