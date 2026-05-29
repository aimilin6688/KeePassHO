# TOTP EntryView 兼容层适配实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 EntryView 页面使用 OtpCompatibilityManager 兼容层，支持多种数据库格式的 TOTP 字段显示。

**Architecture:** 新增 `extractOtpUrlsWithProcessedFields` 方法返回已处理的字段名集合，修改 `EntryView.loadFields()` 使用该方法获取 TOTP URLs 并跳过已处理的原始字段。

**Tech Stack:** HarmonyOS ArkTS, kdbxweb 库

---

## 文件结构

| 文件 | 职责 | 操作 |
|------|------|------|
| `entry/src/main/ets/common/utils/KdbxUtils.ets` | 新增 FIELD_TOTP 常量和工具方法 | 修改 |
| `entry/src/main/ets/services/otp/OtpCompatibilityManager.ets` | 新增返回已处理字段的方法 | 修改 |
| `entry/src/main/ets/pages/EntryView.ets` | 修改字段加载逻辑 | 修改 |

---

### Task 1: 在 OtpCompatibilityManager 新增 extractOtpUrlsWithProcessedFields 方法

**Files:**
- Modify: `entry/src/main/ets/services/otp/OtpCompatibilityManager.ets`

- [ ] **Step 1: 新增 extractOtpUrlsWithProcessedFields 方法**

在 `extractOtpUrls` 方法后添加新方法：

```typescript
/**
 * 从条目中提取所有 OTP URL 及已处理的字段名
 * @param entry KeePass 条目
 * @returns 包含 OTPURL 数组和已处理字段名集合的对象
 */
public extractOtpUrlsWithProcessedFields(entry: KdbxEntry): { urls: string[], processedFields: Set<string> } {
  const urls: string[] = [];
  const processedFields = new Set<string>();

  // 遍历所有解析器
  for (const parser of this.parsers) {
    entry.fields.forEach((value, key) => {
      // 跳过已处理的字段
      if (processedFields.has(key)) {
        return;
      }

      const valueStr = KdbxUtils.getValueString(value);
      if (parser.canParse(key, valueStr)) {
        try {
          const parsedUrls = parser.parse(key, valueStr, entry);
          urls.push(...parsedUrls);
          processedFields.add(key);
        } catch (error) {
          // 静默忽略解析错误
        }
      }
    });
  }

  return { urls, processedFields };
}
```

- [ ] **Step 2: 提交更改**

```bash
git add entry/src/main/ets/services/otp/OtpCompatibilityManager.ets
git commit -m "$(cat <<'EOF'
feat(otp): add extractOtpUrlsWithProcessedFields method

Add new method to OtpCompatibilityManager that returns both
OTP URLs and the set of processed field names for better
integration with EntryView.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: 在 KdbxUtils 新增常量和工具方法

**Files:**
- Modify: `entry/src/main/ets/common/utils/KdbxUtils.ets`

- [ ] **Step 1: 新增 FIELD_TOTP 常量**

在 `FIELD_EXPIRY_TIME` 常量后添加：

```typescript
public static readonly FIELD_EXPIRY_TIME = 'expiryTime';
public static readonly FIELD_TOTP = 'TOTP';
public static readonly GROUP_NAME = 'GroupName';
```

- [ ] **Step 2: 新增 getTotpUrlWithProcessedFields 方法**

在 `getTotpUrl` 方法后添加：

```typescript
/**
 * 从条目中获取TOTP URL及已处理的字段名
 * @param itemEntry 条目
 * @returns 包含 TOTP URL 数组和已处理字段名集合的对象
 */
public static getTotpUrlWithProcessedFields(itemEntry: KdbxEntry): { urls: string[], processedFields: Set<string> } {
  if (!itemEntry) {
    return { urls: [], processedFields: new Set() };
  }
  // 使用兼容层管理器提取 OTP URL 及已处理字段
  return OtpCompatibilityManager.getInstance().extractOtpUrlsWithProcessedFields(itemEntry);
}
```

- [ ] **Step 3: 提交更改**

```bash
git add entry/src/main/ets/common/utils/KdbxUtils.ets
git commit -m "$(cat <<'EOF'
feat(utils): add FIELD_TOTP constant and getTotpUrlWithProcessedFields

Add FIELD_TOTP constant for TOTP field identification and
getTotpUrlWithProcessedFields utility method that wraps
OtpCompatibilityManager for EntryView integration.

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: 修改 EntryView.loadFields() 方法

**Files:**
- Modify: `entry/src/main/ets/pages/EntryView.ets`

- [ ] **Step 1: 修改 loadFields 方法**

替换整个 `loadFields()` 方法：

```typescript
/**
 * 加载条目字段
 */
private loadFields() {
  if (!this.entry) {
    return;
  }

  this.fields = [];

  // 使用兼容层获取 TOTP URL 及已处理的字段名
  const { urls: totpUrls, processedFields } = KdbxUtils.getTotpUrlWithProcessedFields(this.entry);

  // 添加 TOTP 字段（通过兼容层解析，支持多种数据库格式）
  for (const totpUrl of totpUrls) {
    this.fields.push(new FieldView(KdbxUtils.FIELD_TOTP, totpUrl, false, true));
  }

  // 遍历条目的所有字段
  for (const field of this.entry.fields) {
    const key: string = field[0];
    // 跳过标题字段
    if (key === KdbxUtils.FIELD_TITLE) {
      continue;
    }
    // 跳过已被 TOTP 兼容层处理的字段
    if (processedFields.has(key)) {
      continue;
    }
    const value = field[1];
    const strValue = KdbxUtils.getValueString(value);
    if (strValue !== '') {
      this.fields.push(new FieldView(key, strValue, KdbxUtils.isProtectedValue(value), true));
    }
  }

  // 添加标签字段
  if (this.entry.tags && this.entry.tags.length > 0) {
    this.fields.push(new FieldView(KdbxUtils.FIELD_TAGS, this.entry.tags.join(', '), false, true));
  }

  // 添加覆盖URL
  if (this.entry.overrideUrl && this.entry.overrideUrl.length > 0) {
    this.fields.push(new FieldView(KdbxUtils.FIELD_OVERRIDE_URL, this.entry.overrideUrl, false, true));
  }

  // 字段排序
  this.fields.sort((a, b) => {
    // 将常用字段排在前面
    const commonFields =
      [KdbxUtils.FIELD_TITLE, KdbxUtils.FIELD_USERNAME, KdbxUtils.FIELD_PASSWORD, KdbxUtils.FIELD_TOTP, KdbxUtils.FIELD_URL, KdbxUtils.FIELD_NOTES, KdbxUtils.FIELD_TAGS,
        KdbxUtils.FIELD_OVERRIDE_URL];
    const aIndex = commonFields.indexOf(a.key);
    const bIndex = commonFields.indexOf(b.key);

    if (aIndex >= 0 && bIndex >= 0) {
      return aIndex - bIndex;
    } else if (aIndex >= 0) {
      return -1;
    } else if (bIndex >= 0) {
      return 1;
    } else {
      return this.fields.indexOf(a) - this.fields.indexOf(b);
    }
  });

  // 添加分组信息
  this.fields = [new FieldView(KdbxUtils.GROUP_NAME, this.getGroupName(), false, false), ...this.fields];

  // 展示附件
  this.addBinaries();

  // 过期时间
  if (this.entry.times.expires) {
    this.fields.push(new FieldView(KdbxUtils.FIELD_EXPIRY_TIME, DateUtils.format(this.entry.times.expiryTime), false, false));
  }

  // 增加创建时间和更新时间
  this.fields.push(new FieldView(KdbxUtils.FIELD_CREATION_TIME, DateUtils.format(this.entry.times.creationTime), false, false));
  this.fields.push(new FieldView(KdbxUtils.FIELD_LASTMOD_TIME, DateUtils.format(this.entry.times.lastModTime), false, false));
}
```

- [ ] **Step 2: 提交更改**

```bash
git add entry/src/main/ets/pages/EntryView.ets
git commit -m "$(cat <<'EOF'
feat(entry): integrate OtpCompatibilityManager in EntryView

Modify loadFields() to use OtpCompatibilityManager for TOTP
field extraction. This enables proper display of TOTP from
KeePass2 native, KeeOTP, and KeeTrayTotp formats.

- Extract TOTP URLs via compatibility layer
- Skip processed fields to avoid duplicate display
- Add FIELD_TOTP to field sort priority

Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: 验证构建

**Files:**
- 无文件修改

- [ ] **Step 1: 执行构建验证**

```bash
hvigorw --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
```

Expected: BUILD SUCCESSFUL

---

## 自审清单

**1. Spec 覆盖率检查：**
- [x] 新增 FIELD_TOTP 常量 - Task 2 Step 1
- [x] 新增 extractOtpUrlsWithProcessedFields 方法 - Task 1 Step 1
- [x] 新增 getTotpUrlWithProcessedFields 工具方法 - Task 2 Step 2
- [x] 修改 loadFields() 逻辑 - Task 3 Step 1
- [x] 字段排序添加 FIELD_TOTP - Task 3 Step 1

**2. 占位符扫描：** 无 TBD、TODO 或模糊描述 ✓

**3. 类型一致性：** 方法签名在各任务中一致 ✓
