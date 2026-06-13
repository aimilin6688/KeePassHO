# WebDAV SSL 证书验证支持设计

## 1. 背景

用户反馈 WebDAV 不支持 HTTPS 连接。经分析，当前 `WebDavClient` 使用 `rcp.createSession` 时只配置了 Basic 认证，未配置 SSL 证书验证模式。HarmonyOS 的 `rcp.SecurityConfiguration.remoteValidation` 支持四种验证模式：

- `'system'`：使用系统 CA（默认）
- `'skip'`：跳过验证
- `CertificateAuthority`：指定 CA 证书
- `ValidationCallback`：自定义验证回调

自签名证书的服务器在使用默认系统 CA 验证时会失败。

## 2. 目标

支持完整的 SSL 证书验证模式：
1. 系统 CA 验证（默认，安全）
2. 跳过验证（用户需确认风险）
3. 自定义 CA 证书验证

## 3. 数据结构设计

### 3.1 新增枚举

文件：`entry/src/main/ets/storage/webdav/WebDAVConfig.ets`

```typescript
/**
 * SSL 证书验证模式
 */
export enum CertValidationMode {
  /** 使用系统 CA 验证（默认） */
  SYSTEM = 'system',
  /** 跳过证书验证（不安全） */
  SKIP = 'skip',
  /** 使用自定义 CA 证书 */
  CUSTOM_CA = 'custom_ca'
}
```

### 3.2 配置类扩展

文件：`entry/src/main/ets/storage/webdav/WebDAVConfig.ets`

```typescript
export class WebDAVStorageConfig implements StorageConfig {
  url: string;
  username: string;  // 加密存储
  password: string;  // 加密存储
  rootPath?: string;
  timeout?: number;

  // 新增字段
  /** SSL 证书验证模式，默认为 SYSTEM */
  certValidationMode?: CertValidationMode;
  /** 自定义 CA 证书内容（PEM 格式） */
  customCaCertContent?: string;
}
```

**设计说明**：
- `certValidationMode`：存储用户选择的验证模式
- `customCaCertContent`：存储 CA 证书内容（PEM 格式字符串），而非文件路径，避免文件路径在不同会话中失效

## 4. 核心组件设计

### 4.1 WebDavClient 改造

文件：`entry/src/main/ets/common/utils/WebDavClient.ets`

**接口变更**：

```typescript
export interface WebDavClientOptions {
  url: string;
  username: string;
  password: string;
  /** SSL 证书验证模式 */
  certValidationMode?: CertValidationMode;
  /** 自定义 CA 证书内容（PEM 格式） */
  customCaCertContent?: string;
}
```

**新增方法**：

```typescript
/**
 * 构建安全配置
 */
private buildSecurityConfig(): rcp.SecurityConfiguration {
  const mode = this.config.certValidationMode || CertValidationMode.SYSTEM;

  let remoteValidation: 'system' | 'skip' | rcp.CertificateAuthority;

  switch (mode) {
    case CertValidationMode.SKIP:
      remoteValidation = 'skip';
      break;
    case CertValidationMode.CUSTOM_CA:
      if (this.config.customCaCertContent) {
        remoteValidation = {
          content: this.config.customCaCertContent
        } as rcp.CertificateAuthority;
      } else {
        // 未提供证书时回退到系统验证
        remoteValidation = 'system';
      }
      break;
    case CertValidationMode.SYSTEM:
    default:
      remoteValidation = 'system';
      break;
  }

  return {
    remoteValidation: remoteValidation,
    serverAuthentication: {
      credential: {
        username: this.config.username,
        password: this.config.password
      },
      authenticationType: "basic"
    }
  };
}
```

**修改 updateOptions 方法**：

```typescript
public updateOptions(options: WebDavClientOptions) {
  this.config = options;
  this.close();
  try {
    this.session = rcp.createSession({
      baseAddress: this.config.url,
      headers: { "Accept": "text/plain,application/xml" },
      requestConfiguration: {
        transfer: {
          timeout: { connectMs: 3000 }
        },
        security: this.buildSecurityConfig()
      }
    });
  } catch (error) {
    hilog.error(DOMAIN, TAG, "createSession error: %{public}s", error.message);
    CommonUtils.showToast(error.message);
  }
}
```

### 4.2 WebDAVStorage 改造

文件：`entry/src/main/ets/storage/webdav/WebDAVStorage.ets`

修改 `init` 方法，传递证书配置到 `WebDavClient`：

```typescript
public init(config: WebDAVStorageConfig) {
  const parsedConfig = this.parseConfig(config);
  if (this.isSameConfig(parsedConfig)) {
    this.config = parsedConfig;
    return;
  }
  this.config = parsedConfig;
  this.closeClient();
  this.client = new WebDavClient({
    url: this.config.url,
    username: this.config.getUserNameText(),
    password: this.config.getPasswordText(),
    certValidationMode: this.config.certValidationMode,
    customCaCertContent: this.config.customCaCertContent
  });
}
```

## 5. UI 设计

### 5.1 WebDAVPage 布局

文件：`entry/src/main/ets/storage/webdav/WebDAVPage.ets`

**新增状态变量**：

```typescript
@State certValidationMode: CertValidationMode = CertValidationMode.SYSTEM;
@State customCaCertPath: string = '';  // 用于显示已选择的文件名
@State customCaCertContent: string = '';  // 证书内容
@State showSkipCertWarning: boolean = false;  // 是否显示风险提示弹框
```

**UI 布局**（在密码输入框下方添加）：

```
SSL 证书验证
┌─────────────────────────────────────────┐
│ ○ 系统 CA（默认）                        │
│ ○ 跳过验证（不安全）                     │
│ ○ 自定义 CA 证书                         │
└─────────────────────────────────────────┘

[当选择"自定义 CA 证书"时显示]
┌─────────────────────────────────────────┐
│ 未选择证书              [选择证书]       │
└─────────────────────────────────────────┘
```

### 5.2 选择证书流程

```typescript
/**
 * 选择 CA 证书文件
 */
private async selectCaCert() {
  // 使用 DocumentViewPicker 选择 .pem/.crt/.cer 文件
  let documentPicker = new picker.DocumentViewPicker();
  try {
    const result = await documentPicker.select({
      maxSelectNumber: 1,
      fileSuffixFilters: ['.pem', '.crt', '.cer', '.cert']
    });
    if (result.length > 0) {
      const uri = result[0];
      // 读取证书内容
      const content = await this.readCertContent(uri);
      this.customCaCertContent = content;
      this.customCaCertPath = this.extractFileName(uri);
    }
  } catch (error) {
    CommonUtils.showToast({ message: '选择证书失败' });
  }
}
```

### 5.3 风险提示弹框

当用户选择「跳过验证」时，显示确认弹框：

```typescript
/**
 * 显示跳过证书验证的风险提示
 */
private showSkipWarningDialog() {
  AlertDialog.show({
    title: '安全警告',
    message: '跳过 SSL 证书验证会降低连接安全性，可能导致数据泄露或遭受中间人攻击。\n\n仅建议在测试环境或服务器使用自签名证书时使用。\n\n是否继续？',
    autoCancel: true,
    alignment: DialogAlignment.CENTER,
    buttons: [
      {
        value: '取消',
        action: () => {
          // 恢复到系统 CA 模式
          this.certValidationMode = CertValidationMode.SYSTEM;
        }
      },
      {
        value: '继续',
        action: () => {
          // 保持跳过验证模式
        }
      }
    ]
  });
}
```

### 5.4 配置保存

```typescript
private getStorageConfig(): StorageConfig {
  return new WebDAVStorageConfig(this.url, this.username, this.password, {
    certValidationMode: this.certValidationMode,
    customCaCertContent: this.customCaCertContent
  });
}
```

### 5.5 编辑模式初始化

在 `initSaveParam` 方法中，从已有配置恢复证书设置：

```typescript
if (storageConfig) {
  // ... 现有代码 ...
  this.certValidationMode = storageConfig.certValidationMode || CertValidationMode.SYSTEM;
  this.customCaCertContent = storageConfig.customCaCertContent || '';
  this.customCaCertPath = this.customCaCertContent ? '已选择证书' : '';
}
```

## 6. 文件修改清单

| 文件路径 | 修改类型 | 说明 |
|----------|----------|------|
| `entry/src/main/ets/storage/webdav/WebDAVConfig.ets` | 修改 | 新增 `CertValidationMode` 枚举，扩展 `WebDAVStorageConfig` |
| `entry/src/main/ets/common/utils/WebDavClient.ets` | 修改 | 新增 `buildSecurityConfig` 方法，修改 `updateOptions` 和 `WebDavClientOptions` |
| `entry/src/main/ets/storage/webdav/WebDAVStorage.ets` | 修改 | 修改 `init` 方法传递证书配置 |
| `entry/src/main/ets/storage/webdav/WebDAVPage.ets` | 修改 | 新增证书验证模式选择 UI、CA 证书选择、风险提示弹框 |

## 7. 测试要点

1. **系统 CA 模式**：使用有效 HTTPS 证书的 WebDAV 服务器，应正常连接
2. **跳过验证模式**：使用自签名证书的服务器，选择跳过后应能连接
3. **自定义 CA 模式**：导入正确的 CA 证书后应能连接
4. **风险提示**：选择跳过验证时必须显示风险提示，取消后应恢复系统 CA 模式
5. **配置持久化**：重新打开已保存的 WebDAV 配置，证书设置应正确恢复
6. **错误处理**：无效证书内容时应回退到系统 CA 并提示用户

## 8. 安全考虑

1. **默认安全**：默认使用系统 CA 验证，不跳过验证
2. **用户知情**：跳过验证前必须确认风险提示
3. **证书内容存储**：CA 证书内容存储在加密的配置中（SM4 加密），不存储明文文件路径
4. **日志安全**：证书内容不输出到日志

## 9. 后续扩展

- 可考虑支持 `ValidationCallback` 模式，允许用户自定义更复杂的验证逻辑
- 可增加证书指纹显示，让用户确认证书正确性
