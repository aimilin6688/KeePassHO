# TOTP 兼容层在 EntryView 页面的适配设计

## 问题背景

`DatabaseView` 页面已正确使用 `OtpCompatibilityManager` 兼容层来显示多种数据库格式的 TOTP 字段，但 `EntryView` 页面直接遍历原始字段创建 `FieldView`，未使用兼容层，导致 KeePass2 原生、KeeOTP、KeeTrayTotp 等格式的 TOTP 字段无法正确显示。

## 支持的 OTP 格式

| 解析器 | 格式 | 字段名 |
|--------|------|--------|
| `OtpUrlParser` | 标准 OTP URL | 任意包含 `otpauth://totp/` 值的字段 |
| `KeePass2Parser` | KeePass 2.x 原生 | `TimeOtp-Secret-Base32`, `TimeOtp-Secret-Hex`, `TimeOtp-Secret-Base64`, `TimeOtp-Secret` |
| `KeeOtpParser` | KeeOTP 插件 | `otp`, `KeeOTP` (包含 `key=` 参数) |
| `KeeTrayTotpParser` | KeeTrayTotp 插件 | `TOTP Seed` (配合 `TOTP Settings`) |

## 设计目标

将所有格式的 TOTP 统一显示为 "TOTP" 字段，隐藏原始技术字段，与 `DatabaseView` 保持一致的显示方式。

## 实现方案

### 1. 新增常量

**文件：** `entry/src/main/ets/common/utils/KdbxUtils.ets`

```typescript
public static readonly FIELD_TOTP = 'TOTP';
```

### 2. 新增 API

**文件：** `entry/src/main/ets/services/otp/OtpCompatibilityManager.ets`

新增方法，返回 TOTP URLs 和已处理的字段名集合：

```typescript
public extractOtpUrlsWithProcessedFields(entry: KdbxEntry): 
  { urls: string[], processedFields: Set<string> }
```

**文件：** `entry/src/main/ets/common/utils/KdbxUtils.ets`

封装工具方法：

```typescript
public static getTotpUrlWithProcessedFields(itemEntry: KdbxEntry): 
  { urls: string[], processedFields: Set<string> }
```

### 3. 修改字段加载逻辑

**文件：** `entry/src/main/ets/pages/EntryView.ets`

修改 `loadFields()` 方法：

1. 调用兼容层获取 TOTP URLs 和已处理字段名
2. 为每个 TOTP URL 创建 `FieldView(FIELD_TOTP, otpUrl, ...)`
3. 遍历原始字段时跳过已处理的字段
4. 字段排序中添加 `FIELD_TOTP` 优先级

## 数据流

```
EntryView.loadFields()
    │
    ▼
KdbxUtils.getTotpUrlWithProcessedFields(entry)
    │
    ▼
OtpCompatibilityManager.extractOtpUrlsWithProcessedFields(entry)
    │
    ├── OtpUrlParser
    ├── KeePass2Parser
    ├── KeeOtpParser
    └── KeeTrayTotpParser
    │
    ▼
{ urls: [...], processedFields: Set<string> }
    │
    ▼
FieldView(FIELD_TOTP, otpUrl, ...)
    │
    ▼
TotpPreviewComponent 渲染
```

## 涉及文件

1. `entry/src/main/ets/common/utils/KdbxUtils.ets` - 新增常量和工具方法
2. `entry/src/main/ets/services/otp/OtpCompatibilityManager.ets` - 新增返回已处理字段的方法
3. `entry/src/main/ets/pages/EntryView.ets` - 修改 `loadFields()` 逻辑
