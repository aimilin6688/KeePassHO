# HarmonyOS 分栏开发、响应式布局与响应式应用架构分析

> 本文基于 HarmonyOS 官方开发文档与官方最佳实践整理，涵盖：**分栏开发**、**响应式布局**、**响应式（多设备/“一多”）应用架构**三大主题。
>
> 主要参考文档：
> - 开发指南 · Navigation 分栏开发
> - 开发指南 · 栅格布局 GridRow/GridCol
> - 开发指南 · 媒体查询 @ohos.mediaquery
> - 开发指南 · 容器断点 ContainerReader
> - 最佳实践 · 布局概述
> - 最佳实践 · 响应式布局
> - 最佳实践 · 页面布局场景
> - 最佳实践 · 组件布局场景
> - 最佳实践 · 多设备新闻阅读界面

---

## 目录

1. [概念总览：自适应布局 vs 响应式布局](#1-概念总览自适应布局-vs-响应式布局)
2. [响应式布局的四大能力](#2-响应式布局的四大能力)
3. [断点详解（横向 + 纵向）](#3-断点详解横向--纵向)
4. [分栏开发（Navigation 分栏 + SideBarContainer）](#4-分栏开发navigation-分栏--sidebarcontainer)
5. [媒体查询](#5-媒体查询)
6. [栅格布局（GridRow/GridCol）](#6-栅格布局gridrowgridcol)
7. [容器断点 ContainerReader](#7-容器断点-containerreader)
8. [响应式布局的四种常见样式](#8-响应式布局的四种常见样式)
9. [响应式（“一多”）应用架构：三层分层工程](#9-响应式一多应用架构三层分层工程)
10. [关键 API / 实践要点速查](#10-关键-api--实践要点速查)

---

## 1. 概念总览：自适应布局 vs 响应式布局

官方将布局能力分为两类，用途不同：

| 名称 | 简介 | 数量 | 变化特点 |
| --- | --- | --- | --- |
| **自适应布局** | 外部容器变化时，元素依据**相对关系**（占比、固定宽高比、显示优先级等）自动连续变化 | **7 种能力**：拉伸、均分、占比、缩放、延伸、隐藏、折行 | **连续变化**，多用于解决**页面各区域内部**的布局差异 |
| **响应式布局** | 外部容器变化时，元素依据**断点、栅格或特定特征**（屏幕方向、窗口宽高）自动变化 | **4 种能力**：断点、媒体查询、栅格、响应式组件 | **不连续变化**（跨断点差异明显），多用于解决**页面各区域之间**的布局差异 |

### 自适应布局（7 种能力）

| 能力 | 容器组件 | 实现方式 |
| --- | --- | --- |
| 拉伸 | Row/Column | 增加 `Blank` 子组件 |
| 均分 | Row/Column/Flex | `justifyContent` 设为 `FlexAlign.SpaceEvenly` |
| 占比 | Row/Column/Flex | 百分比宽高，或配置子组件 `layoutWeight` |
| 缩放 | Row/Column/Flex | 配置 `aspectRatio` 属性 |
| 延伸 | Row/Column | 增加 `Scroll` 父组件 |
| 隐藏 | Row/Column/Flex | 配置子组件 `displayPriority` 属性 |
| 折行 | Flex | 将 `wrap` 设置为 `FlexWrap.Wrap` |

> 自适应布局常借助 `Row` / `Column` / `Flex` 实现。

### 响应式布局常用容器

| 容器组件 | 说明 | 响应式方式 |
| --- | --- | --- |
| **GridRow** | 栅格容器，配合 `GridCol` | 自身即具备响应式布局能力 |
| **Grid** | 网格容器，配合 `GridItem` | 配合断点，改不同断点下 `rowsTemplate`/`columnsTemplate` |
| **List** | 列表容器，配合 `ListItem` | 配合断点，改 `lanes` 等属性 |
| **Swiper** | 轮播容器 | 配合断点，改 `displayCount`/`indicator` 等 |
| **Tabs** | 页签容器，配合 `TabContent` | 配合断点，改 `vertical`/`barPosition` 等 |

---

## 2. 响应式布局的四大能力

| 能力 | 简介 |
| --- | --- |
| **断点** | 将窗口宽度划分为不同范围（断点），监听窗口尺寸变化，断点改变时同步调整布局 |
| **媒体查询** | 监听窗口宽度、横竖屏、深浅色、设备类型等媒体特征，变化时同步调整布局 |
| **栅格** | 栅格组件将区域划分为多列，通过不同断点下的参数及子组件列数实现差异布局 |
| **响应式组件** | 系统组件（Tabs、Swiper、Grid、List、GridRow）内建响应式能力，配合断点渲染不同效果 |

---

## 3. 断点详解（横向 + 纵向）

响应式设计核心围绕“窗口宽度”与“窗口高宽比”，对应**横向断点**与**纵向断点**。

### 3.1 设计原则

- **原则一**：两个宽度相近的窗口，布局相同 → **断点归一**。
- **原则二**：高度相对宽度较小的窗口（横向/类方形），差异化设计 → **增加断点**。

### 3.2 横向断点（按应用窗口宽度，单位 vp）

| 断点 | 窗口宽度（vp） |
| --- | --- |
| xs | (0, 320) |
| sm | [320, 600) |
| md | [600, 840) |
| lg | [840, 1440) |
| xl | [1440, +∞) |

### 3.3 纵向断点（按应用窗口高宽比）

| 断点 | 高宽比 |
| --- | --- |
| sm | (0, 0.8) —— 横向/宽扁窗口 |
| md | [0.8, 1.2) —— 类方形窗口 |
| lg | [1.2, +∞) —— 纵向窗口 |

> 断点**面向窗口而非设备类型**：同一设备上的全屏、分屏、自由窗口可能落入不同断点、展示不同布局。

### 3.4 主流设备断点区间示例

| 产品 | 窗口全屏尺寸（vp） | 横向 | 纵向 |
| --- | --- | --- | --- |
| 手机（竖屏） | 827 × 374 | sm | lg |
| 双折叠（内屏） | 798 × 711 | md | md |
| 三折叠（G 态横屏） | 1107 × 776 | lg | sm |
| 平板（横屏） | 1137 × 711 | lg | sm |
| 电脑 | 1642 × 1094 | xl | sm |
| 智慧屏 | 1280 × 720 | lg | sm |

### 3.5 通过断点刷新 UI 的两种方式

1. **断点环境变量 `@Env`**（API 22+）：窗口尺寸变化时，断点环境变量更新并触发关联组件刷新。适用于 BuilderNode 切换窗口、横竖屏/折叠切换等场景。
2. **主动监听窗口变化**：
   - 自定义 `@Observed` 的 `WindowInfo` 类保存窗口断点信息。
   - 用 `getWindowWidthBreakpoint()` / `getWindowHeightBreakpoint()` 获取横向/纵向断点。
   - 用 `on('windowSizeChange')` 监听窗口尺寸变化，在回调中重新获取断点并刷新 UI。

```
@Observed
export class WindowInfo {
  public widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_XS;
  public heightBp: HeightBreakpoint = HeightBreakpoint.HEIGHT_SM;
  // ...
}

export class WindowUtil {
  public mainWindowInfo: WindowInfo = new WindowInfo();
  public onWindowSizeChange = (windowSize: window.Size) => {
    this.mainWindowInfo.widthBp  = this.uiContext.getWindowWidthBreakpoint();
    this.mainWindowInfo.heightBp = this.uiContext.getWindowHeightBreakpoint();
  };
}
```

---

## 4. 分栏开发（Navigation + SideBarContainer）

### 4.1 Navigation 分栏

`Navigation` 提供 **单栏** 与 **分栏** 两种核心布局，分栏适合宽屏设备：导航栏（navBar）固定显示，子页面（NavDestination）通过 `NavPathStack` 切换，两者间有可拖拽分割线。

#### 分栏相关接口

| 接口 | 说明 |
| --- | --- |
| `mode` | 显示模式：`NavigationMode.Stack`（单栏）、`NavigationMode.Split`（分栏）、`NavigationMode.Auto`（自适应）、`NavigationMode.AUTO_WITH_ASPECT_RATIO`（按高宽比自适应） |
| `navBarPosition` | 导航栏位置 `Start`/`End`，受系统语言 LTR/RTL 影响 |
| `enableDragBar` | 是否显示分栏拖动按钮 |
| `navBarWidth` | 导航栏宽度 |
| `navBarWidthRange` | 导航栏宽度可调整范围（如 `[100, 700]`） |
| `minContentWidth` | 分栏子页面最小宽度 |
| `hideNavBar` | 是否隐藏导航栏（Split + hide 实际等同单栏） |
| `enableModeChangeAnimation` | 是否开启单双栏切换动画（默认开） |
| `splitPlaceholder` | 分栏空栈时内容区默认占位页（仅 UI 展示，不收路由、不可获焦/响应） |

### 4.2 Navigation 分栏示例

```
Navigation(this.stack) {
  NewsHome().width('100%').height('100%')
}
.mode(NavigationMode.Split)      // 分栏模式
.enableDragBar(true)
.hideNavBar(false)
.navBarWidthRange([100, 700])    // NavBar 宽度范围
.minContentWidth(100)            // 子页最小宽度
.hideTitleBar(true)
.hideToolBar(true)
.height('100%')
.width(`${this.navWidth}%`)
```

路由表（`router_map.json`）：

```json
{
  "routerMap": [
    {
      "name": "NewsDetail",
      "pageSourceFile": "src/main/ets/pages/navigation/splitmode/NewsDetail.ets",
      "buildFunction": "NewsDetailPageBuilder",
      "data": { "description": "NewsDetail" }
    }
  ]
}
```

子页通过 `@Builder export function XxxBuilder()` + `NavDestination` 展示，`onReady` 中从 `ctx.pathInfo.param` 取参数，点击左侧列表 `stack?.pushPath({ name, param })` 即可在右侧打开详情。

### 4.3 SideBarContainer（侧边栏分栏）

侧边栏基于横向断点动态控制显隐与宽度，实现二分栏：

```ts
SideBarContainer(
  this.mainWindowInfo.widthBp === WidthBreakpoint.WIDTH_SM
    ? SideBarContainerType.Overlay   // 手机上：浮在内容区上，占 80%
    : SideBarContainerType.Embed     // 大屏：与内容并列，50%/40%
) {
  // 侧边栏
  // 内容区
}
```

典型断点行为：
- **sm**：默认不显示侧边栏，侧边栏浮于内容区上，宽 80%。
- **md**：默认显示侧边栏，并列展示，宽 50%。
- **lg**：默认显示侧边栏，并列展示，宽 40%。

可通过断点动态配置 `showSideBar`、`sideBarWidth`。

---

## 5. 媒体查询

### 5.1 使用流程

```ts
import { mediaquery } from '@kit.ArkUI';

listener = this.getUIContext().getMediaQuery()
  .matchMediaSync('(orientation: landscape)');

aboutToAppear() {
  this.listener.on('change', (r: mediaquery.MediaQueryResult) => {
    if (r.matches) {
      // 命中条件时的布局/业务逻辑
    }
  });
}
aboutToDisappear() {
  this.listener.off('change');   // 务必解绑
}
```

### 5.2 语法规则

```
[media-type] [media-logic-operations] [(media-feature)]
```

- **媒体类型**：`screen`（默认）。
- **逻辑操作符**：`and`、`or`、`not`（需配 screen）、`only`、逗号 `,`。
- **范围操作符**：`<=`、`>=`、`<`、`>`。

### 5.3 常用媒体特征

| 特征 | 说明 |
| --- | --- |
| `height` / `width` | 页面可绘制区域高/宽 |
| `min/max-height` / `min/max-width` | 应用显示区域的最小/最大高宽 |
| `resolution` | 设备分辨率（dpi/dppx/dpcm） |
| `orientation` | `portrait` 竖屏 / `landscape` 横屏 |
| `device-type` | 设备类型：default、phone、tablet、tv、car、wearable、2in1 |
| `device-width` | 设备宽度（仅初始化时保存一次，不随折叠实时更新） |
| `round-screen` | 是否圆形屏幕 |
| `dark-mode` | 深色 true / 浅色 false |

> 数值型特征比较支持 vp / px，默认 px；需要考虑浮点数精度。卡片中仅支持 `height`、`width`。
> **约束**：`device-width` 不会随折叠屏开合动态更新，需用断点监听等其他手段。

---

## 6. 栅格布局（GridRow/GridCol）

### 6.1 概述与优势

- 提供可循规律，划分等宽行列，解决多尺寸设备动态布局问题。
- 统一定位标注，保证多设备布局一致性。
- 灵活调整行列间距。
- 自动换行与自适应（一对多）。

### 6.2 默认断点

栅格容器以**宽度（vp）**为断点，默认分 xs / sm / md / lg：

| 断点 | 取值范围（vp） |
| --- | --- |
| xs | [0, 320) |
| sm | [320, 600) |
| md | [600, 840) |
| lg | [840, +∞) |

可用 `BreakPoints` 自定义断点（默认数组 `["320vp","600vp","840vp"]`，最多支持 6 个断点 xs~xxl）：

```ts
GridRow({
  columns: { xs: 2, sm: 4, md: 8, lg: 12, xl: 12, xxl: 12 },  // 各断点列数
  breakpoints: {
    value: ['320vp', '600vp', '840vp', '1440vp', '1600vp'],  // 自定义断点
    reference: BreakpointsReference.WindowSize                // 以窗口为参照（vs 容器）
  }
}) {
  ForEach(colors, (c) => {
    GridCol({ span: 1 }) { Row() { Text(`...`) } }
  })
}
.onBreakpointChange((bp) => { this.currentBp = bp })
```

> `columns` 默认值（API 20+）：`{ xs: 2, sm: 4, md: 8, lg: 12, xl: 12, xxl: 12 }`。
> `reference` 支持 `BreakpointsReference.WindowSize`（窗口）或 `ContainerSize`（容器）。

### 6.3 常用属性

- `columns`：栅格总列数（number 或按断点的 `GridRowColumnOption`）。
- `breakpoints`：自定义断点及参照物。
- `onBreakpointChange`：断点变化回调。
- `GridCol`：`span`（跨列）、`offset`（偏移）：均可按断点细化（如 `span: { sm: 12, md: 10, lg: 8 }`）。
- 栅格可**嵌套**使用以应对复杂布局。

---

## 7. 容器断点 ContainerReader

> 从 **API 26.0.0** 开始提供。基于**容器自身尺寸**而非窗口尺寸的响应式布局方案，比窗口断点更细粒度。

### 7.1 核心能力

- **容器级尺寸感知**：基于组件自身尺寸确定断点值。
- **双向绑定实时获取**：通过状态变量实时获取容器尺寸与断点。
- **宽度/高度双模式**：同时支持宽度断点与高度断点。
- **自定义断点阈值**：通过 `breakpointConfig` 配置各尺寸区间的布局策略。

### 7.2 用法与约束

```ts
import { ContainerReader, Size, WidthBreakpoint } from '@kit.ArkUI';

@State containerSize: Size = { width: 0, height: 0 };
@State widthBp: WidthBreakpoint = WidthBreakpoint.WIDTH_MD;

ContainerReader({
  size: this.containerSize!!,        // 必须用 !! 触发双向绑定（V2 语法）
  widthBreakpoint: this.widthBp!!
}) {
  Column() { Text('Adaptive Content') }
    .width('100%').height('100%')
}
```

**约束**：
- 所有参数必须是 **状态变量** 且 **必须使用 `!!` 触发双向绑定**，用普通变量或去掉 `!!` 均不生效。
- 常配合 Flex/Row/Column 使用；有兄弟节点时撑满父容器剩余空间，可用 `layoutWeight` 平分剩余空间。
- 父容器为 Flex/Row/Column 时占满剩余空间；其他容器撑满父容器。

---

## 8. 响应式布局的四种常见样式

| 样式 | 场景 | 典型实现 |
| --- | --- | --- |
| **分栏布局** | 导航与内容同屏左右 | SideBarContainer / Navigation + 断点 |
| **重复布局** | 同属性组件横向并列 | List / WaterFlow / Swiper / Grid + 断点 |
| **挪移布局** | 上下布局变为左右（横屏） | GridRow/GridCol + 断点 + 栅格 |
| **缩进布局** | 宽屏差异化缩进（文本/卡片） | GridRow/GridCol（6/8 columns 缩进） |

### 8.1 重复布局示例（按断点动态调整）

```ts
// List：按断点分列
List({ space: new WidthBreakpointType(8, 12, 16, 16).getValue(bp) })
  .lanes(new WidthBreakpointType(1, 2, 3, 3).getValue(bp), 12)

// Grid：columnsTemplate
Grid().columnsTemplate(`repeat(${new WidthBreakpointType(2, 3, 4, 4).getValue(bp)}, 1fr)`)

// Swiper
Swiper().displayCount(new WidthBreakpointType(1, 2, 3, 3).getValue(bp))
  .indicator(bp === WIDTH_SM ? Indicator.dot()... : false)
```

---

## 9. 响应式（“一多”）应用架构：三层分层工程

官方推荐采用 **分层架构** 组织“一次开发，多端部署”工程，将项目划分成三层，权责清晰、便于复用与扩展。

### 三层架构（common / features / products）

| 层级 | 职责 | 工程形态 |
| --- | --- | --- |
| **products 产品定制层** | 不同设备的应用入口（如 PC 与手机布局差异大 → 独立 HAP） | 入口 HAP（`pc`、`default` 等） |
| **features 基础特性层** | 独立业务模块，按模块拆分、互不依赖、便于迭代 | HAR（如 `recommendation`、`newsdetail`） |
| **common 公共能力层** | 公共常量、组件、工具（断点取值器、窗口管理、日志等） | 基础能力 HAR |

### 工程结构示例（新闻阅读应用）

```
├── common                                // 公共能力层
│   └── src/main/ets
│       ├── components                    // 公共 UI 组件（NewsCard 等）
│       ├── constants                     // 公共常量（断点等）
│       ├── types                         // 数据契约接口
│       └── utils                         // 窗口、断点、日志等工具
├── features                              // 基础特性层
│   ├── recommendation                    // 首页推荐 HAR
│   └── newsdetail                        // 新闻详情 HAR
└── products                              // 产品定制层
    ├── default                            // 直板机/折叠屏/平板 统一入口
    └── pc                                 // 电脑端独立入口
```

### 落地要点

- **窗口适配**：不同设备/窗口模式（全屏、分屏、悬浮窗、自由窗口）通过监听窗口尺寸变化 + 断点刷新 UI 自动适配。
- **窗口方向**：`setPreferredOrientation()` 配合 `FOLLOW_DESKTOP`（大屏四方向自由旋转，小屏默认竖屏）。
- **沉浸式**：`setWindowLayoutFullscreen()` 实现状态栏全局沉浸，并做动态安全区避让。
- **断点封装**：在 common 层封装 `WindowInfo` + `WindowUtil`（`@Observed` 窗口信息类 + `getWindowWidthBreakpoint` / `getWindowHeightBreakpoint` / `on('windowSizeChange')`），供所有页面复用。
- **页面开发**：以页面为基本单元，利用自适应 + 响应式能力，实现“一套代码、多端部署”。可配合 `WidthBreakpointType(sm, md, lg, xl)` 这类断点取值器，同一属性值按断点取不同值。

---

## 10. 关键 API / 实践要点速查

### 断点 / 尺寸

| 能力 | API | 说明 |
| --- | --- | --- |
| 获取横向断点 | `getUIContext().getWindowWidthBreakpoint()` | 返回 `WidthBreakpoint` |
| 获取纵向断点 | `getUIContext().getWindowHeightBreakpoint()` | 返回 `HeightBreakpoint` |
| 监听窗口尺寸 | `window.on('windowSizeChange')` | 回调中重新获取断点 |
| 断点环境变量 | `@Env`（API 22+） | 窗口尺寸变化时自动刷新 UI |
| 显示缩放 | `on('densityUpdate')` / `setDefaultDensityEnabled()` | 控制是否随系统显示缩放重排布局 |

### 分栏 / 导航

| 组件 | 关键属性 | 场景 |
| --- | --- | --- |
| Navigation | `mode`、`navBarPosition`、`enableDragBar`、`navBarWidthRange`、`minContentWidth` | 单/双栏 |
| SideBarContainer | `SideBarContainerType.Overlay/Embed`、`showSideBar`、`sideBarWidth` | 侧边栏（二分） |
| 三分栏 | SideBarContainer + Navigation + 断点 | 宽屏三栏 |

### 响应式布局

| 组件 | 关键属性 |
| --- | --- |
| GridRow/GridCol | `columns`、`breakpoints`（`reference`）、`span`、`offset` |
| Grid | `columnsTemplate`、`rowsTemplate` |
| List | `lanes`、`space` |
| Swiper | `displayCount`、`indicator`、`prevMargin`/`nextMargin` |
| Tabs | `vertical`、`barPosition` |
| ContainerReader（API 26+） | `size`、`widthBreakpoint`（`!!` 双向绑定） |

---

## 附：文档来源

| 主题 | 官方文档（目录） |
| --- | --- |
| 分栏 | 开发指南 · ArkUI · Navigation 分栏开发 |
| 自适应/响应式布局概览 | 最佳实践 · 多设备界面开发 · 布局概述 |
| 断点 / 媒体查询 / 栅格 / 响应式组件 | 最佳实践 · 响应式布局；开发指南（媒体查询、栅格布局、容器断点） |
| 页面布局场景（重复/分栏/挪移/缩进） | 最佳实践 · 页面布局场景 |
| 组件布局场景 | 最佳实践 · 组件布局场景 |
| 三层架构案例 | 最佳实践 · 多设备新闻阅读界面（common/features/products） |