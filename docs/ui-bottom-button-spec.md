# 底部操作按钮开发规范

> **适用范围**：KeePassHO 所有页面的底部操作按钮区（取消 / 确定 / 删除 等成组的主要操作）。
> **基准实现**：`entry/src/main/ets/pages/setting/SettingCustomIcons.ets`（管理自定义图标页底部按钮区）
> **最新实践**：`entry/src/main/ets/pages/open/FileList.ets`（悬浮式变体）

新页面写底部按钮时，**直接套用本规范的模板**，不要另起一套样式。改造存量页面时也必须对齐到这里的尺寸、配色与布局方式。

---

## 一、视觉规格

| 项 | 值 | 说明 |
|---|---|---|
| 次要按钮（取消类） | `Color.Gray` 实心 + `button_text` 文字 | 深灰实心，**不要换成 `card_bg` 浅色** |
| 主按钮（确定类） | `button_bg_blue` + `button_text` 文字 | 禁用态靠 `.enabled(cond)` 控制 |
| 按钮宽 / 高 | `45%` / `40` | 两个按钮等宽，中间用 `Blank()` 撑开 |
| 圆角 | `20` | |
| 字号 | `16` | |
| 按钮行高度 | `60` | |
| 按钮行内边距 | `{ top: 8, bottom: 8, left: 16, right: 16 }` | 底部留白 8，避免贴底 |
| 行背景 | `Color.Transparent` | **必须显式声明**，透出页面底色 |
| 页面根容器安全区 | `.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])` | **必须加在页面根 Column 上**（见 `SettingCustomIcons.ets`）。单栏模式下 NavDestination 内容区会避让底部系统安全区，缺了它悬浮按钮会整体偏高一截；分栏模式无底部避让区，该属性为空操作，不影响既有布局 |

> **Button 必须用纯文本形式 `Button($r('...'))`**，禁止用 `Button() { Row() { Text() } }` 包一层纯文字。
> 带自定义子组件的 `Button` 会带出组件自带的默认样式背景层，`.backgroundColor()` 盖不住它——这就是历史上出现"按钮背景那一长条"的根因。

> **例外：按钮需要图标时**（图标 + 文字），只能用自定义内容形式 `Button() { Row() { Image(); Text() } }`，
> 但必须**显式设置 `backgroundColor`**（覆盖了默认背景层，不会有长条问题），其余尺寸/间距/行高照搬本规范。
> 项目中的例子：`UnLockDatabase.ets`（关闭/解锁）、`EntryView.ets`（回滚/删除）。

---

## 二、模板 A：常规页面（内容区与按钮区上下分区）

适用于内容区不需要延伸到按钮下方的页面，如设置类、表单类页面。

```ts
build() {
  Column() {
    // 内容区：必须 layoutWeight(1) 撑满剩余空间，把按钮顶到底部
    Column() {
      // ...页面内容
    }
    .width('100%')
    .layoutWeight(1)

    // 底部操作按钮
    Row() {
      Button($r('app.string.cancel_button_text'))
        .width('45%')
        .height(40)
        .fontSize(16)
        .fontColor($r('app.color.button_text'))
        .borderRadius(20)
        .backgroundColor(Color.Gray)
        .onClick(() => {
          this.handleCancel();
        })

      Blank()

      Button($r('app.string.confirm_button_text'))
        .width('45%')
        .height(40)
        .fontSize(16)
        .fontColor($r('app.color.button_text'))
        .borderRadius(20)
        .enabled(this.isEnableConfirm)
        .backgroundColor($r('app.color.button_bg_blue'))
        .onClick(() => {
          this.handleConfirm();
        })
    }
    .width('100%')
    .height(60)
    .backgroundColor(Color.Transparent)
    .padding({
      top: 8,
      bottom: 8,
      left: 16,
      right: 16
    })
  }
  .width('100%')
  .height('100%')
  .backgroundColor($r('app.color.bg_primary'))
}
```

**要点**：内容区必须 `.layoutWeight(1)`，否则按钮会紧跟内容而非固定在底部。

> **实测结论（2026-09-24）**：流式按钮行（不加 `.position()`/`.translate()`）在 Scroll/Grid 页面上，
> 按钮行与内容区之间会露出一条割裂的底色，即使 Row 已设 `Color.Transparent` 也无法消除——
> 透出的不是内容而是被按钮行"顶断"后的独立区域。**因此按钮行一律采用悬浮写法**
> （`.position({ x: 0, y: '100%' })` + `.translate({ y: -BOTTOM_BAR_HEIGHT })`），内容区 `layoutWeight(1)` 撑满，
> 内容自然延伸到按钮下方，问题即消失。模板 A 与模板 B 的唯一区别只剩：有列表的页面要加 `contentEndOffset`。

```ts
// 模板 A 的按钮行（悬浮写法，与模板 B 一致）
Row() {
  // ...两个 Button
}
.width('100%')
.height(60)
.backgroundColor(Color.Transparent)
.padding({
  top: 8,
  bottom: 8,
  left: 16,
  right: 16
})
// 脱离文档流悬浮，上移量 = 自身高度 60 + 底部留白 10
.position({ x: 0, y: '100%' })
.translate({ y: -70 })
```

**内容防遮挡（必须）**：按钮悬浮后盖在内容上方，内容区必须留出等高（70）的底部空间，否则最后的内容永远滚不到按钮上方：

| 内容区类型 | 做法 |
|---|---|
| `List` | `.contentEndOffset(70)`（见模板 B） |
| `Scroll` | 给 **Scroll 内部的内容容器** 加 `padding({ bottom: 70 })`（不要加在 Scroll 自身上） |
| `Grid` | `.padding({ bottom: 70 })` |
| 固定内容（无滚动） | 内容区 `.padding({ bottom: 70 })` |

数值必须与按钮行的 `BOTTOM_BAR_HEIGHT` 一致（当前 70 = 自身高度 60 + 底部留白 10）。

---

## 三、模板 B：列表页（按钮悬浮，列表延伸至按钮下方）

适用于文件列表等长列表页面——列表内容要一直延伸到页面底部，按钮悬浮覆盖其上。**这是 `FileList.ets` 采用的方案。**

```ts
// 底部悬浮按钮栏总高度（自身高度 60 + 底部留白 10）
private readonly BOTTOM_BAR_HEIGHT: number = 70;

build() {
  Column() {
    // 内容区（列表）：layoutWeight(1) 占满整个高度，不被按钮挤压
    Column() {
      List() {
        // ...
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 12, right: 12 })
      // 底部按钮为悬浮层，留出等高的内容偏移，保证最后一项能滚动到按钮上方
      .contentEndOffset(this.BOTTOM_BAR_HEIGHT)
    }
    .layoutWeight(1)
    .padding({ top: 12 })

    // 底部操作按钮：脱离文档流悬浮，列表得以延伸至按钮下方
    Row() {
      // ...同模板 A 的两个 Button
    }
    .width('100%')
    .height(60)
    .backgroundColor(Color.Transparent)
    .padding({
      top: 8,
      bottom: 8,
      left: 16,
      right: 16
    })
    // 悬浮在列表之上（脱离文档流），使列表内容可延伸至按钮下方
    .position({ x: 0, y: '100%' })
    .translate({ y: -this.BOTTOM_BAR_HEIGHT })
  }
  .width('100%')
  .height('100%')
  .backgroundColor($r('app.color.bg_primary'))
}
```

**要点**：

1. `.position()` 使按钮行脱离文档流，兄弟节点（列表区）才能占满整个高度。
2. `.translate({ y: -BOTTOM_BAR_HEIGHT })` 中 `BOTTOM_BAR_HEIGHT = 自身高度 60 + 底部留白 10`。想调底部间距只改这一个常量。
3. **必须给 List 加 `.contentEndOffset(BOTTOM_BAR_HEIGHT)`**，否则最后一项永远被悬浮按钮遮住、滚不出来。
4. 曾经用空 `ListItem().height(170)` 占位给浮层让位——**不要再用这种写法**，`contentEndOffset` 是正确解法。

---

## 四、禁止事项

| 禁止 | 原因 |
|---|---|
| `Button() { Row() { Text() } }` 自定义内容形式 | 带出 Button 自带背景层，`.backgroundColor()` 盖不住 |
| 次要按钮用 `card_bg` / 白底浅色 | 曾被明确指出与项目其余页面不一致 |
| 按钮行用 `.height(45)` 等小于内容实际高度的值 | 内容 40+上边距 8 已被 `(8+40+8)=56` 挤出，按钮底部会被裁切 |
| 去掉按钮行的 `Color.Transparent` / 改设 `bg_primary` | 会形成一条独立的浅灰色底栏，与列表区割裂 |
| 悬浮模式下省略 `contentEndOffset` | 列表最后一项被永久遮挡 |

---

## 五、颜色约定

| 资源 | 值（浅色） | 用途 |
|---|---|---|
| `bg_primary` | `#F1F3F5` | 页面底色（**全项目统一，所有页面一致**） |
| `card_bg` | `#FFFFFF` | 卡片 / 输入框底色 |
| `button_bg_blue` | `#007DFF` | 主按钮 |
| `button_text` | | 按钮文字色（灰 / 蓝按钮通用） |

**不要为了"去掉那条底色"去动页面底色 `bg_primary`**：它是全项目统一的页面底色，改了会让整个页面（含列表间隙）一起变白。底部按钮区的浅灰看起来"有一条"，是因为它透出的就是页面底色——正确做法是让列表/内容延伸过来（模板 B），而不是把底色删掉。

---

## 六、落地检查清单

改完底部按钮后自查：

- [ ] `Button` 是否为纯文本形式
- [ ] 尺寸：`.width('45%')` `.height(40)` `.fontSize(16)` `.borderRadius(20)`
- [ ] 配色：次要 `Color.Gray`、主按钮 `button_bg_blue`，文字 `button_text`
- [ ] 按钮行：`.height(60)` + `.backgroundColor(Color.Transparent)` + padding `{8,8,16,16}`
- [ ] 内容区是否 `.layoutWeight(1)`（否则按钮不贴底）
- [ ] 按钮行已悬浮：有 `.position()` + `.translate()`（**所有页面必须**，流式会露出割裂底条）
- [ ] 页面根容器已加 `.expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])`（单栏模式悬浮按钮贴底的关键）
- [ ] 内容防遮挡：List 有 `.contentEndOffset(70)`；Scroll/Grid/固定内容有 `bottom: 70` 的 padding
- [ ] 悬浮高度与防遮挡空间数值一致（均为 70）
- [ ] 已执行 **编译 → 安装到设备 → 启动应用 → `pidof` 确认**（见 `.codebuddy/rules/harmony-deploy.md`）
