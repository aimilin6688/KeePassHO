# WebDAV SSL 证书验证支持实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为 WebDAV 存储添加完整的 SSL 证书验证支持，包括系统 CA 验证、跳过验证（需确认风险）、自定义 CA 证书三种模式。

**Architecture:** 在现有 WebDAV 配置层扩展证书验证模式枚举和配置字段，修改 WebDavClient 的安全配置构建逻辑，在 WebDAVPage UI 层新增证书验证模式选择、CA 证书文件选择和风险提示弹框。

**Tech Stack:** HarmonyOS ArkTS, rcp (Remote Communication Kit), @kit.ArkUI

---

## 文件结构

| 文件 | 职责 |
|------|------|
| `entry/src/main/ets/storage/webdav/WebDAVConfig.ets` | 定义 `CertValidationMode` 枚举，扩展 `WebDAVStorageConfig` 添加证书验证字段 |
| `entry/src/main/ets/common/utils/WebDavClient.ets` | 新增 `buildSecurityConfig()` 方法构建 SSL 安全配置，修改 `updateOptions()` |
| `entry/src/main/ets/storage/webdav/WebDAVStorage.ets` | 修改 `init()` 方法传递证书配置到 WebDavClient |
| `entry/src/main/ets/storage/webdav/WebDAVPage.ets` | 新增证书验证模式选择 UI、CA 证书选择、风险提示弹框 |
| `entry/src/main/resources/base/element/string.json` | 新增英文字符串资源 |
| `entry/src/main/resources/zh_CN/element/string.json` | 新增中文字符串资源 |

---

### Task 1: 添加国际化字符串资源

**Files:**
- Modify: `entry/src/main/resources/base/element/string.json`
- Modify: `entry/src/main/resources/zh_CN/element/string.json`

- [ ] **Step 1: 添加英文字符串资源**

在 `entry/src/main/resources/base/element/string.json` 的 `string` 数组末尾添加：

```json
    {
      "name": "ssl_cert_validation_title",
      "value": "SSL Certificate Validation"
    },
    {
      "name": "ssl_cert_validation_system",
      "value": "System CA (Default)"
    },
    {
      "name": "ssl_cert_validation_skip",
      "value": "Skip Validation (Insecure)"
    },
    {
      "name": "ssl_cert_validation_custom_ca",
      "value": "Custom CA Certificate"
    },
    {
      "name": "ssl_cert_no_certificate_selected",
      "value": "No certificate selected"
    },
    {
      "name": "ssl_cert_certificate_selected",
      "value": "Certificate selected"
    },
    {
      "name": "ssl_cert_select_failed",
      "value": "Failed to select certificate"
    },
    {
      "name": "ssl_cert_warning_title",
      "value": "Security Warning"
    },
    {
      "name": "ssl_cert_warning_message",
      "value": "Skipping SSL certificate validation reduces connection security and may lead to data leaks or man-in-the-middle attacks.\n\nThis is recommended only for testing environments or servers using self-signed certificates.\n\nDo you want to continue?"
    },
    {
      "name": "ssl_cert_warning_continue",
      "value": "Continue"
    }
```

- [ ] **Step 2: 添加中文字符串资源**

在 `entry/src/main/resources/zh_CN/element/string.json` 的 `string` 数组末尾添加：

```json
    {
      "name": "ssl_cert_validation_title",
      "value": "SSL 证书验证"
    },
    {
      "name": "ssl_cert_validation_system",
      "value": "系统 CA（默认）"
    },
    {
      "name": "ssl_cert_validation_skip",
      "value": "跳过验证（不安全）"
    },
    {
      "name": "ssl_cert_validation_custom_ca",
      "value": "自定义 CA 证书"
    },
    {
      "name": "ssl_cert_no_certificate_selected",
      "value": "未选择证书"
    },
    {
      "name": "ssl_cert_certificate_selected",
      "value": "已选择证书"
    },
    {
      "name": "ssl_cert_select_failed",
      "value": "选择证书失败"
    },
    {
      "name": "ssl_cert_warning_title",
      "value": "安全警告"
    },
    {
      "name": "ssl_cert_warning_message",
      "value": "跳过 SSL 证书验证会降低连接安全性，可能导致数据泄露或遭受中间人攻击。\n\n仅建议在测试环境或服务器使用自签名证书时使用。\n\n是否继续？"
    },
    {
      "name": "ssl_cert_warning_continue",
      "value": "继续"
    }
```

- [ ] **Step 3: 提交字符串资源**

```bash
git add entry/src/main/resources/base/element/string.json entry/src/main/resources/zh_CN/element/string.json
git commit -m "feat(i18n): add SSL certificate validation strings

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 2: 扩展 WebDAVConfig 数据结构

**Files:**
- Modify: `entry/src/main/ets/storage/webdav/WebDAVConfig.ets`

- [ ] **Step 1: 添加 CertValidationMode 枚举**

在 `WebDAVConfig.ets` 文件顶部，`WebDAVStorageConfigOptions` 接口之前添加：

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

- [ ] **Step 2: 扩展 WebDAVStorageConfigOptions 接口**

修改 `WebDAVStorageConfigOptions` 接口，添加证书相关选项：

```typescript
/**
 * WebDAV存储配置选项类
 */
export interface WebDAVStorageConfigOptions {
  rootPath?: string;
  timeout?: number;
  /** SSL 证书验证模式 */
  certValidationMode?: CertValidationMode;
  /** 自定义 CA 证书内容（PEM 格式） */
  customCaCertContent?: string;
}
```

- [ ] **Step 3: 扩展 WebDAVStorageConfig 类**

在 `WebDAVStorageConfig` 类中添加新字段，修改构造函数：

```typescript
/**
 * WebDAV存储配置类
 */
export class WebDAVStorageConfig implements StorageConfig {
  /**
   * 服务器URL
   */
  url: string;
  /**
   * 用户名, 加密后的Base64字符串
   */
  username: string;
  /**
   * 密码, 加密后的Base64字符串
   */
  password: string;
  /**
   * 根路径（可选）
   */
  rootPath?: string;
  /**
   * 超时时间（毫秒，可选）
   */
  timeout?: number;
  /**
   * SSL 证书验证模式
   */
  certValidationMode?: CertValidationMode;
  /**
   * 自定义 CA 证书内容（PEM 格式）
   */
  customCaCertContent?: string;

  constructor(url: string, username: string, password: string, options?: WebDAVStorageConfigOptions) {
    this.url = url;
    this.username = Sm4Utils.encryptWithPrefix(username);
    this.password = Sm4Utils.encryptWithPrefix(password);
    this.rootPath = options?.rootPath;
    this.timeout = options?.timeout;
    this.certValidationMode = options?.certValidationMode;
    this.customCaCertContent = options?.customCaCertContent;
  }

  public getUserNameText(): string {
    return Sm4Utils.decryptWithPrefix(this.username);
  }

  public getPasswordText(): string {
    return Sm4Utils.decryptWithPrefix(this.password);
  }
}
```

- [ ] **Step 4: 提交数据结构变更**

```bash
git add entry/src/main/ets/storage/webdav/WebDAVConfig.ets
git commit -m "feat(webdav): add CertValidationMode enum and extend WebDAVStorageConfig

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 3: 修改 WebDavClient 支持证书验证配置

**Files:**
- Modify: `entry/src/main/ets/common/utils/WebDavClient.ets`

- [ ] **Step 1: 添加 CertValidationMode 导入**

在文件顶部的 import 区域添加：

```typescript
import { CertValidationMode } from '../../storage/webdav/WebDAVConfig';
```

- [ ] **Step 2: 扩展 WebDavClientOptions 接口**

修改 `WebDavClientOptions` 接口，添加证书验证字段：

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

- [ ] **Step 3: 添加 buildSecurityConfig 方法**

在 `WebDavClient` 类中，`updateOptions` 方法之前添加：

```typescript
/**
 * 构建安全配置
 * @returns rcp 安全配置
 */
private buildSecurityConfig(): rcp.SecurityConfiguration {
  const mode = this.config?.certValidationMode || CertValidationMode.SYSTEM;

  let remoteValidation: 'system' | 'skip' | rcp.CertificateAuthority;

  switch (mode) {
    case CertValidationMode.SKIP:
      remoteValidation = 'skip';
      break;
    case CertValidationMode.CUSTOM_CA:
      if (this.config?.customCaCertContent) {
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
        username: this.config?.username ?? '',
        password: this.config?.password ?? ''
      },
      authenticationType: "basic"
    }
  };
}
```

- [ ] **Step 4: 修改 updateOptions 方法**

将原有的 `updateOptions` 方法替换为：

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

- [ ] **Step 5: 提交 WebDavClient 变更**

```bash
git add entry/src/main/ets/common/utils/WebDavClient.ets
git commit -m "feat(webdav): add SSL certificate validation support in WebDavClient

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 4: 修改 WebDAVStorage 传递证书配置

**Files:**
- Modify: `entry/src/main/ets/storage/webdav/WebDAVStorage.ets`

- [ ] **Step 1: 修改 init 方法传递证书配置**

将 `init` 方法中创建 `WebDavClient` 的部分修改为：

```typescript
public init(config: WebDAVStorageConfig) {
  const parsedConfig = this.parseConfig(config);
  // 配置相同，复用现有连接，避免 close 导致进行中的请求被取消
  if (this.isSameConfig(parsedConfig)) {
    this.config = parsedConfig;
    return;
  }
  // 配置不同，关闭旧连接，创建新连接
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

- [ ] **Step 2: 提交 WebDAVStorage 变更**

```bash
git add entry/src/main/ets/storage/webdav/WebDAVStorage.ets
git commit -m "feat(webdav): pass cert validation config to WebDavClient

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 5: 修改 WebDAVPage UI 添加证书验证选择

**Files:**
- Modify: `entry/src/main/ets/storage/webdav/WebDAVPage.ets`

- [ ] **Step 1: 添加必要的 import**

在文件顶部添加：

```typescript
import { picker, fs } from '@kit.CoreFileKit';
import { CertValidationMode } from './WebDAVConfig';
```

- [ ] **Step 2: 添加状态变量**

在 `WebDAV` 组件的状态变量区域添加：

```typescript
  @State certValidationMode: CertValidationMode = CertValidationMode.SYSTEM;
  @State customCaCertPath: string = '';
  @State customCaCertContent: string = '';
```

- [ ] **Step 3: 修改 initSaveParam 方法恢复证书配置**

修改 `initSaveParam` 方法，在已有的 `storageConfig` 处理逻辑中添加证书配置恢复：

```typescript
  // 导出数据初始化
  private initSaveParam() {
    if (!LocationParam.isSaveMode()) {
      return;
    }
    // 初始化导出
    const dbFileParam = FileService.getDbFileParam();
    if (!(dbFileParam.storageType === StorageType.WEBDAV)) {
      this.url = LocationParam.getFileName();
      return;
    }
    let storageConfig = dbFileParam.storageConfig as WebDAVStorageConfig;
    if (storageConfig) {
      storageConfig = new WebDAVStorageConfig(storageConfig.url, storageConfig.username, storageConfig.password, {
        rootPath: storageConfig.rootPath,
        timeout: storageConfig.timeout,
        certValidationMode: storageConfig.certValidationMode,
        customCaCertContent: storageConfig.customCaCertContent
      });
      this.url = FilenameUtils.replaceFileName(dbFileParam.filePath, LocationParam.getFileName());
      this.username = storageConfig.getUserNameText();
      this.password = storageConfig.getPasswordText();
      // 恢复证书配置
      this.certValidationMode = storageConfig.certValidationMode || CertValidationMode.SYSTEM;
      this.customCaCertContent = storageConfig.customCaCertContent || '';
      this.customCaCertPath = this.customCaCertContent ?
        ResourceManager.getString($r('app.string.ssl_cert_certificate_selected')) : '';
    }
  }
```

- [ ] **Step 4: 添加选择 CA 证书方法**

在组件方法区域添加：

```typescript
  /**
   * 选择 CA 证书文件
   */
  private async selectCaCert() {
    let documentPicker = new picker.DocumentViewPicker();
    try {
      const result = await documentPicker.select({
        maxSelectNumber: 1
      });
      if (result && result.length > 0) {
        const uri = result[0];
        // 读取证书内容
        const content = await this.readCertContent(uri);
        this.customCaCertContent = content;
        this.customCaCertPath = ResourceManager.getString($r('app.string.ssl_cert_certificate_selected'));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Select CA cert error: %{public}s', error.message);
      CommonUtils.showToast({ message: $r('app.string.ssl_cert_select_failed') });
    }
  }

  /**
   * 读取证书文件内容
   */
  private async readCertContent(uri: string): Promise<string> {
    try {
      const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
      const stat = fs.statSync(file.fd);
      const buf = new ArrayBuffer(stat.size);
      fs.readSync(file.fd, buf);
      fs.closeSync(file);
      // 将 ArrayBuffer 转换为字符串
      const decoder = new util.TextDecoder('utf-8');
      return decoder.decodeToString(new Uint8Array(buf));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Read cert content error: %{public}s', error.message);
      return '';
    }
  }
```

- [ ] **Step 5: 添加 util 导入和风险提示方法**

在 import 区域添加 `util`：

```typescript
import { util } from '@kit.ArkTS';
```

添加风险提示弹框方法：

```typescript
  /**
   * 处理证书验证模式变更
   */
  private onCertValidationModeChange(mode: CertValidationMode) {
    if (mode === CertValidationMode.SKIP) {
      // 显示风险提示
      AlertDialog.show({
        title: $r('app.string.ssl_cert_warning_title'),
        message: $r('app.string.ssl_cert_warning_message'),
        autoCancel: true,
        alignment: DialogAlignment.CENTER,
        buttons: [
          {
            value: $r('app.string.cancel_button_text'),
            action: () => {
              // 取消，恢复到系统 CA 模式
              this.certValidationMode = CertValidationMode.SYSTEM;
            }
          },
          {
            value: $r('app.string.ssl_cert_warning_continue'),
            action: () => {
              // 确认，保持跳过验证模式
              this.certValidationMode = CertValidationMode.SKIP;
            }
          }
        ]
      });
    } else {
      this.certValidationMode = mode;
    }
  }
```

- [ ] **Step 6: 修改 getStorageConfig 方法**

修改 `getStorageConfig` 方法，添加证书配置：

```typescript
  private getStorageConfig(): StorageConfig {
    return new WebDAVStorageConfig(this.url, this.username, this.password, {
      certValidationMode: this.certValidationMode,
      customCaCertContent: this.customCaCertContent
    });
  }
```

- [ ] **Step 7: 在 build 方法中添加证书验证 UI**

在 `build` 方法的 `Scroll` 组件内部，密码输入框之后、连接状态之前添加证书验证 UI：

```typescript
          // SSL 证书验证
          Text($r('app.string.ssl_cert_validation_title'))
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
            .margin({ top: 20, left: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Start)

          Column() {
            Row() {
              Radio({ value: CertValidationMode.SYSTEM, group: 'certValidation' })
                .checked(this.certValidationMode === CertValidationMode.SYSTEM)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.certValidationMode = CertValidationMode.SYSTEM;
                  }
                })
              Text($r('app.string.ssl_cert_validation_system'))
                .fontSize(14)
                .margin({ left: 8 })
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.certValidationMode = CertValidationMode.SYSTEM;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })

            Row() {
              Radio({ value: CertValidationMode.SKIP, group: 'certValidation' })
                .checked(this.certValidationMode === CertValidationMode.SKIP)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.onCertValidationModeChange(CertValidationMode.SKIP);
                  }
                })
              Text($r('app.string.ssl_cert_validation_skip'))
                .fontSize(14)
                .margin({ left: 8 })
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.onCertValidationModeChange(CertValidationMode.SKIP);
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })

            Row() {
              Radio({ value: CertValidationMode.CUSTOM_CA, group: 'certValidation' })
                .checked(this.certValidationMode === CertValidationMode.CUSTOM_CA)
                .onChange((isChecked: boolean) => {
                  if (isChecked) {
                    this.certValidationMode = CertValidationMode.CUSTOM_CA;
                  }
                })
              Text($r('app.string.ssl_cert_validation_custom_ca'))
                .fontSize(14)
                .margin({ left: 8 })
                .fontColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.certValidationMode = CertValidationMode.CUSTOM_CA;
                })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 8, bottom: 8 })

            // 自定义 CA 证书选择（仅当选择自定义 CA 模式时显示）
            if (this.certValidationMode === CertValidationMode.CUSTOM_CA) {
              Row() {
                Text(this.customCaCertPath || $r('app.string.ssl_cert_no_certificate_selected'))
                  .fontSize(14)
                  .fontColor($r('app.color.text_secondary'))
                  .layoutWeight(1)

                Button($r('app.string.select_button'))
                  .height(32)
                  .fontSize(14)
                  .backgroundColor($r('app.color.button_bg_blue'))
                  .fontColor($r('app.color.button_text_blue'))
                  .onClick(() => {
                    this.selectCaCert();
                  })
              }
              .width('100%')
              .padding({ left: 32, right: 16, top: 4, bottom: 8 })
            }
          }
          .width('100%')
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(8)
          .margin({ top: 8, left: 16, right: 16 })
```

- [ ] **Step 8: 提交 WebDAVPage 变更**

```bash
git add entry/src/main/ets/storage/webdav/WebDAVPage.ets
git commit -m "feat(webdav): add SSL certificate validation UI in WebDAVPage

- Add cert validation mode selection (System CA/Skip/Custom CA)
- Add CA certificate file picker
- Add security warning dialog for skip validation
- Persist cert config in WebDAVStorageConfig

Co-Authored-By: Claude <noreply@anthropic.com>"
```

---

### Task 6: 编译验证

**Files:**
- None

- [ ] **Step 1: 执行编译验证**

运行编译命令验证代码无语法错误：

```bash
cd /Users/liujunguang1/workspace/code/other/harmony/KeePassHO/kee-pass-ho
hvigorw --mode module -p product=default -p buildMode=debug assembleHap --analyze=normal --no-daemon --no-parallel
```

Expected: BUILD SUCCESSFUL

- [ ] **Step 2: 如果编译失败，修复错误**

如果编译报错，根据错误信息修复代码后重新编译。

---

## 规格覆盖检查

| 规格要求 | 对应任务 |
|----------|----------|
| 新增 `CertValidationMode` 枚举 | Task 2 |
| 扩展 `WebDAVStorageConfig` 添加证书字段 | Task 2 |
| WebDavClient 新增 `buildSecurityConfig` 方法 | Task 3 |
| WebDavClient 修改 `updateOptions` 方法 | Task 3 |
| WebDAVStorage 传递证书配置 | Task 4 |
| WebDAVPage 新增证书验证模式选择 UI | Task 5 |
| WebDAVPage 新增 CA 证书选择功能 | Task 5 |
| WebDAVPage 新增风险提示弹框 | Task 5 |
| WebDAVPage 配置持久化和恢复 | Task 5 |
| 国际化字符串（英文） | Task 1 |
| 国际化字符串（中文） | Task 1 |
| 复用现有字符串（cancel_button_text, select_button） | Task 5 |

---

## 无占位符检查

- ✅ 无 TBD、TODO 占位符
- ✅ 所有代码步骤都有完整代码
- ✅ 所有命令都有预期输出
- ✅ 无"类似 Task N"的引用
