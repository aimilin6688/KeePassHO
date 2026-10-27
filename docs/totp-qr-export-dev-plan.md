# KeePassHO TOTP 二维码导出开发设计

> 依据：`docs/feature-gap-analysis.md` §3.5（TOTP 二维码导出 ❌）、P1-5、快速见效清单 #3
>
> 参考：KeePassXC「Entry → TOTP → Show QR code」、KP2A 插件同款能力
>
> 约束：**不引入新第三方依赖、不改 `TotpService`/`OtpCompatibilityManager`/`KdbxUtils` 既有签名、不加新权限**；条目 TOTP 展示链路（`EntryView` → `FieldView` → `EntryViewFieldItem`）仅做入口追加。
>
> 设计日期：2026-10-28 | 预估工作量：~1 人周（M1 核心 ~3 人天 + M2 增强 ~1-2 人天）

---

## 一、背景与目标

### 1.1 差距结论

三大参考实现中 KeePassXC、KP2A（插件）均支持把条目的 TOTP 配置以 `otpauth://` URI 编码为二维码展示，供用户用另一台设备的认证器 App（Google Authenticator / Aegis / KeePassXC 等）扫码迁移。KeePassHO 已具备**扫码导入**（ScanKit，`ScanService` → `TotpService.parseUri`）与**全量 TOTP 生成**（RFC6238/Steam/5 种字段格式兼容），唯独缺逆向导出。

### 1.2 目标

1. 条目详情页 TOTP 字段行新增二维码入口，弹窗展示 `otpauth://` URI 二维码；
2. 复用兼容层已归一的 otpauth URI（5 种字段格式来源全部可导出）；
3. Steam 令牌、多 TOTP 条目、历史版本查看等场景全覆盖；
4. TOTP 独立列表页（`TotpView`）提供长按导出入口（M2）。

### 1.3 明确不做（本期范围外）

| 项 | 说明 | 归属 |
|---|---|---|
| `otpauth://` scheme 深链/分享接收 | P1-5 的另一半：module.json5 注册 skills/actions、want 处理建条目 | 独立任务，另行设计 |
| `TotpConfigDialog` 内嵌二维码预览 | 配置态预览，非导出刚需 | 后续增强 |
| 批量导出全部 TOTP | KeePassXC/KP2A 均无此能力 | 不做 |
| 保存二维码为图片文件 | 涉及 componentSnapshot + 图片落盘，价值中低 | M2 可选项，默认不做 |

---

## 二、现状盘点（实现依据）

### 2.1 TOTP 数据链路（全部已有，零改动复用）

```
KdbxEntry 字段（otp / TimeOtp-* / KeeOTP / KeeTrayTOTP / otpauth URL，5 种格式）
  └─ OtpCompatibilityManager.extractOtpUrls(entry)          [services/otp/]
      └─ 全部归一为 otpauth://totp/... URI 数组
          └─ KdbxUtils.getTotpUrlWithProcessedFields(entry)  [EntryView 用]
          └─ KdbxUtils.getTotpUrl(entry)                     [TotpView/DatabaseView 用]
```

- `EntryView.loadFields()`（`pages/EntryView.ets:157`）：每个 otpauth URI 生成一个 `FieldView(KdbxUtils.FIELD_TOTP, totpUrl, false, true)`；`FieldView` 构造函数判定 `KdbxUtils.isTotpUrl(value)` 后置 `isTotp = true`、`otpValue = value`（`components/EntryViewFieldItem.ets:52-58`）——**多 TOTP 条目天然是多行、每行一个 URI**。
- `TotpService.parseUri / generateUri`：URI ↔ `TotpConfig` 双向转换，已有单测覆盖（`TotpService.test.ets`）。
- `TotpPreviewComponent`：行内令牌预览，`onChange` 回写当前令牌到 `field.value`。

### 2.2 二维码渲染能力（系统内置，零新依赖）

ArkUI 内置 `QRCode(value: ResourceStr)` 组件（API 7+，`SystemCapability.ArkUI.ArkUI.Full`）：

- 最大支持 **512 字符**，超出截断——otpauth URI 典型 100~200 字符，无溢出风险，但仍需防御（见 §4.4）；
- `color()` 默认 `#ff000000`、`backgroundColor()` 默认 `#ffffffff`，均不随深浅色切换（API 11/12 起深色模式默认已为白底黑码）——**设计上仍显式指定黑码白底**，保证扫描可靠性；
- 卡片（API 9+）与元服务均支持，为 P2-1「TOTP 桌面卡片」预留复用可能。

### 2.3 弹窗与交互模式（沿用项目既有模式）

- `@CustomDialog` + `CustomDialogController`（`TotpConfigDialog`、`ImageViewerDialog` 同款）；
- 自适应宽度：`DialogWindowHelper.register()` + `UIUtils.calculateDialogWidth()`（两弹窗均在用）；
- 长按菜单：`.bindContextMenu(builder, ResponseType.LongPress)`（`DatabaseView` 已用 RightClick 形态）；
- 剪贴板：`ClipboardUtils.copyAutoClear()`（自动清除，TotpView 在用）。

---

## 三、总体方案

```
┌─ 入口层 ─────────────────────────────────────────────────────┐
│ EntryViewFieldItem（M1）        TotpView（M2）               │
│   TOTP 行右侧 QR 图标按钮  ──┐    行长按菜单「显示二维码」──┐ │
└──────────────────────────────┼──────────────────────────────┼─┘
                               ▼                              ▼
                        TotpQrDialog（新组件，@CustomDialog）
                               │
                               ▼
              TotpQrHelper.buildQrContent(otpauthUrl, entryTitle)
                ├─ parseUri 失败 → 错误态（不渲染二维码）
                ├─ name/issuer 均空 → name 补条目标题后 generateUri
                └─ 其余原样返回（含 Steam encoder=steam）
                               │
                               ▼
                 QRCode(uri)  白底黑码 ~260vp + 12vp 静区
                 + 参数摘要 + URI 文本 + 安全警告 + 操作按钮
```

数据源不新建：入口拿到的就是兼容层归一后的 `otpauth://` URI（`field.otpValue` / `KdbxUtils.getTotpUrl(item)`）。

---

## 四、详细设计

### 4.1 新组件 `TotpQrDialog.ets`

位置：`entry/src/main/ets/components/TotpQrDialog.ets`，`@CustomDialog` 结构体（V1 `@Component` 体系，与 `TotpConfigDialog` 一致）。

**入参**（builder 传入）：

| 属性 | 类型 | 说明 |
|---|---|---|
| `otpAuthUrl` | `string` | 兼容层归一的 otpauth URI（必填） |
| `entryTitle` | `string` | 条目标题，name/issuer 均空时补全用 |
| `controller` | `CustomDialogController` | 框架注入 |

**内部状态**：

```
@State qrContent: string = ''          // 最终编码进 QRCode 的 URI
@State parsedConfig: TotpConfig | null // 解析结果（参数摘要/标题展示用）
@State errorMessage: string = ''       // 非 QR 错误态
@State dialogWidth: string | number    // DialogWindowHelper 自适应
```

**生命周期**：`aboutToAppear` 中 `windowHelper.register(...)` + `updateDialogWidth()` + `buildQrContent()`（同步，纯字符串操作）；`aboutToDisappear` 中 `windowHelper.unregister()`。与 `TotpConfigDialog` 完全同构。

**布局**（自上而下）：

```
Column(dialogWidth)
 ├─ 标题行：Text(issuer ? `${issuer}` : entryTitle) + 关闭按钮(sys.media.ohos_ic_public_cancel_filled)
 ├─ 二维码卡片：QRCode(this.qrContent)
 │    .color('#ff000000').backgroundColor('#ffffffff')   // 显式黑码白底
 │    .width(260).height(260)
 │    外层 Column 白底 .padding(12)（静区）.borderRadius(12)
 ├─ 参数摘要行：issuer: name（text_secondary，Ellipsis）
 │    + 徽标行：算法(SHA1/256/512) · 位数 · 周期(s)；Steam 令牌单独徽标
 ├─ URI 文本：Text(qrContent).fontSize(12).copyOption(LocalDevice)
 │    .maxLines(2).textOverflow(Ellipsis)（长按可复制）
 ├─ 安全警告：Text($r('app.string.totp_qr_warning')).fontSize(12).fontColor($r('app.color.warn'))
 └─ 按钮行：复制URI(ClipboardUtils.copyAutoClear)  |  关闭(controller.close)
```

**弹窗配置**：`alignment: DialogAlignment.Bottom`、`customStyle: true`、`autoCancel: true`（点空白即关，缩短密钥暴露时长），与 `ImageViewerDialog` 一致。

**错误态**：`parseUri` 返回 null 或 URI > 512 字符时，二维码区域替换为错误文案（`totp_qr_invalid_uri`），仍展示参数区已知信息，不渲染残缺二维码。

### 4.2 QR 内容构建：`TotpQrHelper`（纯静态，单测友好）

位置：`entry/src/main/ets/common/utils/TotpQrHelper.ets`（或并入 `TotpService` 静态方法，实现期二选一，倾向独立类保持 `TotpService` 零改动）。

```ts
export class TotpQrHelper {
  /**
   * 构建可导出的二维码内容
   * @param otpAuthUrl 兼容层归一的 otpauth URI
   * @param entryTitle 条目标题（name/issuer 均空时兜底）
   * @returns 成功返回最终 URI；解析失败返回 null
   */
  public static buildQrContent(otpAuthUrl: string, entryTitle: string): string | null {
    // 1. 解析失败（含空串/非 otpauth://totp/ 前缀）→ null
    // 2. parsed.name 与 parsed.issuer 均为空 → name = entryTitle（去首尾空白；空标题则不补）
    //    其余情况一律原样使用，不篡改用户数据
    // 3. 重新 generateUri(config) 仅在发生补全时执行（parse/generate 已有 round-trip 单测）
    // 4. 结果 > 512 字符 → null（QRCode 组件会静默截断，截断 URI 不可扫，宁可报错）
  }
}
```

**规则说明**：

- **补全触发条件收紧到「name 与 issuer 均空」**：KeeOTP/KeeTrayTOTP 来源经兼容层生成的 URI 可能无标签，此时认证器 App 扫码后条目无名；仅补 `name`（条目标题），不动 `issuer`——避免与用户显式配置冲突。有任一标签则完全原样导出（与 KeePassXC 行为一致）。
- **Steam**：URI 含 `encoder=steam`，原样导出；KeePassXC/Aegis 等支持该参数，Steam 官方 App 本身不扫 otpauth 码（三端参考实现行为相同，不做特殊转换）。
- **SHA256/SHA512、8 位、60 秒**：`generateUri` 已按「非默认值才携带参数」输出，扫码端按 URI 参数还原，无需处理。
- **禁止日志**：helper 与弹窗均不得以 hilog 输出 URI/secret。

### 4.3 入口改造

#### M1：`EntryViewFieldItem`（条目详情页 TOTP 行）

`components/EntryViewFieldItem.ets`：

1. 新增成员（与既有 `imageViewerDialogController` 同构，仅 TOTP 字段行构造）：

```ts
private totpQrDialogController: CustomDialogController = new CustomDialogController({
  builder: TotpQrDialog({
    otpAuthUrl: this.field?.otpValue ?? '',
    entryTitle: ''   // 由父级 EntryView 传入条目标题，见下
  }),
  alignment: DialogAlignment.Bottom,
  customStyle: true,
  autoCancel: true
});
```

   - `FieldView.otpValue` 在构造时已固化该行 URI，多 TOTP 条目每行独立弹窗，天然正确。
   - `entryTitle` 补全所需标题：`EntryViewFieldItem` 已持有 `@State entry: KdbxEntry | null`，builder 传 `KdbxUtils.getFieldValueString(this.entry?.fields, KdbxUtils.FIELD_TITLE)`。

2. 右侧操作区追加 QR 按钮（`field.isTotp` 时渲染，位于复制按钮左侧）：

```
if (this.field.isTotp) {
  Image($r('app.media.ic_qrcode')).width(24).height(24)
    .fillColor($r('app.color.text_primary')).margin({ left: 8 })
    .onClick(() => { this.totpQrDialogController.open(); return false; })
}
```

3. **设计决策**：「条目显示 TOTP 字段」开关（`KEY_SECURITY_ITEM_SHOW_TOTP`）关闭时**不隐藏 QR 入口**——QR 是用户显式点击的导出动作（等同 KeePassXC），令牌明文不外泄，仅 QR 内容含密钥且在弹窗内有警告。历史版本视图（`selectedHistoryIndex >= 0`）同样可用，数据取自历史条目字段，无特殊处理。

#### M2：`TotpView`（TOTP 独立列表页，增强项）

`pages/TotpView.ets` 行容器追加：

```
.bindContextMenu(this.TotpQrMenu(itemEntry), ResponseType.LongPress)

@Builder TotpQrMenu(item: KdbxEntry) {
  Menu() {
    MenuItem({ symbol: $r('app.media.ic_qrcode'), content: $r('app.string.totp_qr_menu_show') })
      .onClick(() => { this.openQrDialog(item); })
  }
}
```

- 页面级持有一个 `CustomDialogController` + `@State currentQrUrl/currentQrTitle`，`openQrDialog` 先赋值再 `open()`（对话框单例复用，避免每行一个 controller）；
- 行点击仍为复制令牌/进详情，长按为增量入口，不改变既有交互。

### 4.4 资源与国际化

**新增图标**：`entry/src/main/resources/base/media/ic_qrcode.svg`（24dp 线性二维码 glyph，`fillColor` 可染，风格对齐 `ic_copy`/`ic_download` 现有 24px 线性图标）。

**新增字符串**（`resources/base/element/string.json` + `zh_CN`，`en_US` 如有同步）：

| key | base (en) | zh_CN |
|---|---|---|
| `totp_qr_dialog_title` | TOTP QR Code | TOTP 二维码 |
| `totp_qr_warning` | The QR code contains your TOTP secret. Only show it when scanning to import, and avoid screenshots or peeping. | 二维码包含 TOTP 密钥，仅在需要扫码导入时展示，谨防截图与窥视。 |
| `totp_qr_copy_uri` | Copy URI | 复制链接 |
| `totp_qr_invalid_uri` | Invalid TOTP configuration, unable to generate QR code. | 无效的 TOTP 配置，无法生成二维码。 |
| `totp_qr_menu_show` | Show QR code | 显示二维码 |
| `totp_qr_steam` | Steam | Steam 令牌 |

参数摘要复用 `TotpConfigDialog` 既有 `totp_type_*` 等字符串，不重复新增。

### 4.5 安全设计

| 风险 | 对策 |
|---|---|
| QR 即密钥明文的视觉形态 | 弹窗固定展示警告文案（§4.4）；仅显式点击进入；`autoCancel: true` 点空白即关 |
| 剪贴板复制 URI 残留 | 用 `ClipboardUtils.copyAutoClear()`（自动清除），不用裸 copy |
| 日志泄露 | helper/弹窗/入口全链路禁止 hilog 输出 URI 与 secret |
| 截屏泄露 | 依赖全局「隐私窗口」既有设置（PRIVACY_WINDOW），本功能不额外豁免或加强；警告文案已提示 |
| 弹窗滞留 | 关闭按钮 + autoCancel + 页面销毁随 `CustomDialogController` 生命周期回收，无定时器/事件订阅（无需 EventBus，无泄漏面） |

### 4.6 边界与异常场景

| 场景 | 行为 |
|---|---|
| 条目无 TOTP | 行非 `isTotp`，无 QR 按钮（不渲染） |
| URI 解析失败（理论不可达：URL 来自兼容层；防御） | 弹窗错误态，不渲染二维码 |
| URI > 512 字符（超长 secret/issuer） | helper 返回 null → 错误态，杜绝组件静默截断 |
| 多 TOTP 条目 | 每行独立 URI → 独立 QR 按钮/弹窗 |
| Steam / SHA256 / SHA512 / 8 位 / 60 秒 | URI 原样携带参数，扫码端还原 |
| 历史版本条目 | `getTotpUrlWithProcessedFields` 作用于历史 entry，行为一致 |
| 深色模式 | 显式黑码白底，不随主题反转 |
| 窗口尺寸变化（折叠屏/PC） | `DialogWindowHelper` 自适应宽度（既有机制） |

---

## 五、文件变更清单

**新增**：

| 文件 | 内容 |
|---|---|
| `entry/src/main/ets/components/TotpQrDialog.ets` | 二维码导出弹窗 |
| `entry/src/main/ets/common/utils/TotpQrHelper.ets` | QR 内容构建纯静态类 |
| `entry/src/main/resources/base/media/ic_qrcode.svg` | 24dp 线性图标 |
| `entry/src/ohosTest/ets/test/utils/TotpQrHelper.test.ets` | 单测套件 |

**修改**（均为追加式）：

| 文件 | 改动 |
|---|---|
| `entry/src/main/ets/components/EntryViewFieldItem.ets` | TOTP 行追加 QR 按钮 + dialog controller |
| `entry/src/main/ets/pages/TotpView.ets`（M2） | 行长按菜单 + 页面级弹窗 |
| `resources/base/element/string.json`、`zh_CN`（及 `en_US` 如有） | 6 条新字符串 |
| `entry/src/ohosTest/ets/test/List.test.ets` | 注册新套件 |

**零改动**：`TotpService`、`OtpCompatibilityManager`、`KdbxUtils`、`EntryView`（fields 构建逻辑）、`module.json5`（无新权限——QRCode 为纯 UI 组件）、`oh-package.json5`（无新依赖）。

---

## 六、测试方案

### 6.1 单元测试（Hypium，`entry/src/ohosTest/ets/test/`）

`TotpQrHelper.test.ets`：

1. 标准 URI 原样返回（name/issuer 齐全、仅 name、仅 issuer 三种）；
2. name+issuer 均空 → 补 `entryTitle`，`parseUri(result).name === entryTitle`；
3. 空标题 + 空 name/issuer → 原样返回（不补空串）；
4. Steam URI（`encoder=steam`）原样返回；
5. 非法输入：空串、`invalid://` 前缀、非 otpauth → null；
6. 超长 URI（构造 > 512 字符）→ null；
7. 回归：`parseUri(buildQrContent(x))` 的 secret/algorithm/digits/period 与源一致。

既有 `TotpService.test.ets` round-trip 用例天然覆盖 generateUri 输出格式正确性。

### 6.2 真机手动验收（覆盖 §4.6 全部边界）

1. 条目详情页 TOTP 行出现 QR 按钮 → 弹窗展示二维码 + 参数摘要；
2. 用另一台设备认证器扫码（或本机 `ScanService.scanTotpQrCode` 自证回读），解析出的 secret/算法/位数/周期与原条目一致，生成的 6 位码实时相同；
3. TestDataGenerator 边界条目逐一验证：SHA1/SHA256/SHA512、8 位、60 秒、Steam、带 issuer、多 TOTP；
4. 历史版本详情页 QR 可用；「条目显示 TOTP」关闭时 QR 仍可用；
5. 深色模式下二维码为黑码白底、可扫；
6. 复制 URI 后剪贴板按既有超时自动清除；
7. M2：TotpView 长按菜单出现且弹窗内容正确。

---

## 七、里程碑

| 里程碑 | 内容 | 人日 |
|---|---|---|
| M1 | `TotpQrHelper` + `TotpQrDialog` + `EntryViewFieldItem` 入口 + 图标/字符串 + 单测 + 真机验收 | ~3 |
| M2（可选） | `TotpView` 長按入口；保存图片（componentSnapshot → ImagePacker → `FileUtils.saveLocalFile`，仅在有明确需求时排期） | 1-2 |

合计与 gap 分析 P1-5 预估（1 人周）一致。完成后更新 `feature-gap-analysis.md` §3.5 与缺失清单 #12、快速见效清单 #3 状态。

---

## 八、风险与缓解

| 风险 | 缓解 |
|---|---|
| 认证器 App 对非默认参数（SHA256/8 位/60 秒）支持不一 | 与 KeePassXC 导出行为一致，不做妥协转换；参数摘要明示用户 |
| QRCode 组件在部分低分屏上密度过高难扫 | 260vp 尺寸 + 12vp 静区；验收覆盖最低分辨率设备 |
| `CustomDialogController` 在列表项中构造的时序问题 | 复用 `ImageViewerDialog` 同位置同模式（已在生产验证）；`otpValue` 构造期固化 |
| 弹窗内容与行数据不同步（保存后 URI 变化） | `EntryView` 保存后 `loadEntry()` 重建 fields/行组件，弹窗随之重建（既有机制） |
