# 百度网盘（Baidu Netdisk）存储后端开发文档

| 项目 | 内容 |
| --- | --- |
| 文档类型 | 功能开发设计文档（调研 + 设计 + 实施计划） |
| 关联模块 | `entry/src/main/ets/storage/`、`entry/src/main/ets/common/oauth2/` |
| 对标实现 | OneDrive（OAuth 型，主要模板）、华为云盘、pCloud、WebDAV、S3 |
| 状态 | 待评审（评审通过后按第 6 章实施计划开发） |
| 参考资料 | 见附录 D |

---

## 1. 背景与目标

KeePassHO 已支持本地、WebDAV、FTP/SFTP、S3、OneDrive、华为云盘等多种存储后端。百度网盘是国内用户量最大的个人云盘，`change-log.md` 已声明"支持百度网盘"，`StorageType.BAIDU_NETDISK` 枚举亦已预置，但 `storage/baidu/` 实现目录尚不存在——本文档补齐这一空缺。

**目标**：基于百度网盘开放平台（xpan API + OAuth 2.0），按照现有 `IFileStorage` 插件化存储架构，实现百度网盘后端，支持：

1. OAuth 2.0 授权登录（access_token 30 天 + refresh_token 10 年自动续期）；
2. 浏览网盘目录、选择 `.kdbx` 数据库文件（复用共享 `FileList` 页面）；
3. 下载（filemetas + dlink）与上传（precreate + superfile2 + create 三步协议）；
4. 覆盖保存（rtype=3）与版本冲突检测（md5 预检）；
5. 与现有 Worker 加载/保存链路、CacheStorage 装饰器、RecentFiles 持久化无缝集成。

**非目标（本期不做）**：

- 断点续传进度持久化（kdbx 文件通常 KB~MB 级，单次全量上传即可，列为后续优化）；
- 动态上传域名（`locateupload` 接口，固定使用 `d.pcs.baidu.com`，列为后续优化）;
- 文件删除/移动/重命名 UI（`IFileStorage` 接口不要求，API 备忘见附录 A）；
- 会员级分片大小自适应（固定 4MB 分片，全会员类型兼容，见 5.1 决策 D6）。

---

## 2. 现状盘点：已预置但未实现

以下代码**已存在**，无需改动，新实现直接复用：

| 位置 | 内容 | 状态 |
| --- | --- | --- |
| `entry/src/main/ets/storage/StorageType.ets:39` | `StorageType.BAIDU_NETDISK = 'BAIDU_NETDISK'` | 已存在 |
| `entry/src/main/ets/common/oauth2/OAuth2Types.ets:35` | `OAuth2Provider.BAIDU_NETDISK` | 已存在 |
| `entry/src/main/ets/common/oauth2/OAuth2TokenStorageService.ets:168` | preferences→文件迁移白名单已含 BAIDU_NETDISK | 已存在 |
| `entry/src/ohosTest/ets/test/oauth2/*` | 多处测试已引用 BAIDU_NETDISK | 已存在 |
| `entry/change-log.md` | 已声明"支持百度网盘" | 待本功能兑现 |
| `entry/src/main/ets/storage/baidu/` | 实现目录 | **待新建（本文档）** |
| `FileStorageFactory` 构造函数 | 工厂注册 | 待添加一行 |
| `route_map.json` | BaiduNetdiskPage 路由 | 待添加 |
| `entry/build-profile.json5` | `BAIDU_NETDISK_*` buildProfileFields | 待添加 |
| `resources` | `ic_baidu.svg` + 三语言 string.json | 待添加 |

---

## 3. 百度网盘开放平台调研

### 3.1 平台接入流程（前置条件，需人工操作）

入口：百度网盘开放平台 `https://pan.baidu.com/union/`（文档 `https://pan.baidu.com/union/doc/`）。

1. **开发者注册**：个人或企业实名认证；
2. **创建应用**：获得 `AppKey`（即 OAuth `client_id`）与 `SecretKey`（即 `client_secret`）；
3. **申请 API 权限**（逐项审核，约数个工作日）：用户信息（uinfo）、文件列表（list）、文件信息（filemetas/dlink）、文件上传（precreate/superfile2/create）、文件管理（filemanager）；
4. **配置授权回调地址**（见 5.8 风险项 R1）；
5. **应用上线审核**：未上线的应用仅创建者测试账号可用；上线后正式用户可用。

> **结论**：代码实现不阻塞于上述流程，可用测试账号开发联调；正式发布前必须完成权限申请与上线审核。

### 3.2 OAuth 2.0 授权

百度 OAuth 端点（与网盘 API 域名不同）：

| 端点 | URL |
| --- | --- |
| 授权 | `https://openapi.baidu.com/oauth/2.0/authorize` |
| 令牌 | `https://openapi.baidu.com/oauth/2.0/token` |
| 设备码（可选） | `https://openapi.baidu.com/oauth/2.0/device/code` |

**授权码流程（本项目主方案）**：

```
authorize?response_type=code
        &client_id={AppKey}
        &redirect_uri={回调地址}
        &scope=basic,netdisk
        &display=mobile          # 移动端优化登录页
        &state={随机串}           # CSRF 防护，回调原样回传

回调: {redirect_uri}?code={授权码}&state={state}

token?grant_type=authorization_code
     &code={授权码}
     &client_id={AppKey}
     &client_secret={SecretKey}
     &redirect_uri={回调地址}     # 必须与授权时一致
```

**刷新流程**（关键：每次刷新返回**新的 refresh_token**，必须保存）：

```
token?grant_type=refresh_token
     &refresh_token={refresh_token}
     &client_id={AppKey}
     &client_secret={SecretKey}
```

**令牌响应字段**（两种 grant 一致）：

```json
{
  "expires_in": 2592000,
  "refresh_token": "2.385d55f...",
  "access_token": "1.54b56f...",
  "scope": "basic netdisk"
}
```

| 要素 | 值 | 说明 |
| --- | --- | --- |
| scope | `basic,netdisk` | basic=基本用户信息；netdisk=网盘读写（需权限审核） |
| access_token 有效期 | 30 天（`expires_in=2592000` 秒） | 过期返回 errno `-6`/`111`/`20016` |
| refresh_token 有效期 | 10 年 | 每次刷新会下发新值，旧值在有效期内仍可用（安全网：Worker 与主线程并发刷新不会互相失效） |
| 令牌端点错误格式 | `{"error":"invalid_grant","error_description":"..."}` | 非 `errno` 体系，注意区分 |
| token 端点请求方式 | 官方文档为 GET（查询参数）；POST form 亦被广泛实现支持（bypy/alist 均用 GET） | **本实现覆写为 GET**，见 5.4 |

**三种可行流程对比与选型**（详见 5.8）：

| 流程 | 回调依赖 | UX | 选型 |
| --- | --- | --- | --- |
| A. 授权码 + 自定义 scheme `keepassho://aimilin.com/baidu/redirect` | 需百度控制台接受自定义 scheme（**待实测**，风险 R1） | 最佳（与 OneDrive/PCloud 一致，静默回跳） | **主方案** |
| B. 授权码 + `oob`（`redirect_uri=oob`，授权页直接显示授权码，用户手动输入 App） | 无（bypy 即此方案） | 一般（手动复制粘贴） | **兜底方案**（自定义 scheme 被拒时启用） |
| C. 设备码（device/code → 用户访问 `openapi.baidu.com/device` 输入 user_code → 轮询 token） | 无 | 适合 TV/CLI；手机端体验一般 | 备选，暂不实现 |

### 3.3 核心 REST API 概览

网盘数据 API 基础域名：`https://pan.baidu.com/rest/2.0/xpan`（下称 `PAN`）；上传分片域名：`https://d.pcs.baidu.com/rest/2.0/pcs`（下称 `PCS`）。除 superfile2 外全部走 `PAN`，均携带 `access_token`。

| 能力 | 方法 | 端点 |
| --- | --- | --- |
| 用户信息 | GET | `PAN/nas?method=uinfo` |
| 文件列表 | GET | `PAN/file?method=list` |
| 文件元信息+dlink | GET | `PAN/multimedia?method=filemetas` |
| 预上传 | POST | `PAN/file?method=precreate` |
| 分片上传 | POST | `PCS/superfile2?method=upload` |
| 创建文件/目录 | POST | `PAN/file?method=create` |
| 删除/移动/重命名 | POST | `PAN/file?method=filemanager&opera=delete|move|rename|copy` |

### 3.4 API 明细

#### 3.4.1 用户信息 uinfo

```
GET PAN/nas?method=uinfo&access_token={token}
→ { "errno": 0, "uk": 123, "baidu_name": "xx", "netdisk_name": "xx",
    "avatar_url": "https://...", "vip_type": 0, ... }
```

`vip_type`：0 普通用户 / 1 普通会员 / 2 超级会员。用途：登录页展示账号信息、token 连通性验证。

#### 3.4.2 文件列表 list

```
GET PAN/file?method=list&access_token={token}
    &dir=/path/to/dir        # 绝对路径，URL 编码
    &order=name|time|size    # 排序字段
    &desc=0|1
    &start=0&limit=200       # 分页，limit ≤ 1000
    &web=1                   # 返回缩略图等 web 字段
    &folder=0                # 0=全部，1=只要文件夹
→ { "errno": 0, "list": [ { "fs_id": 123, "path": "/a.kdbx", "server_filename": "a.kdbx",
      "isdir": 0, "size": 1024, "category": 6, "md5": "...",           # md5 可能为混淆值，见附录 C
      "server_ctime": 1600000000, "server_mtime": 1600000000,
      "local_ctime": ..., "local_mtime": ..., "thumbs": {...} } ], "request_id": ... }
```

- 目录不存在时返回 `errno: -9`（或 `50002`），**这是 `getInfoOrNull` 判定"确定不存在"的依据**；
- 每页默认 1000 条，分页循环聚合到 `start + limit >= 总数`（`list` 为空即到尾）。

#### 3.4.3 文件元信息 filemetas 与下载 dlink

```
GET PAN/multimedia?method=filemetas&access_token={token}
    &fsids=[123,456]     # JSON 数组字符串，fs_id 来自 list
    &dlink=1             # 要求返回下载直链
    &thumb=0
→ { "errno": 0, "list": [ { "fs_id": 123, "path": "/a.kdbx", "size": 1024,
      "md5": "...", "dlink": "https://d.pcs.baidu.com/file/xxx...", ... } ] }
```

**下载规则（三个硬性约束）**：

1. 请求 `{dlink}&access_token={token}`（dlink 后**拼接** access_token，不是 Header）；
2. 必须携带 `User-Agent: pan.baidu.com`，否则返回 **403**；
3. 服务端返回 **302** 重定向到实际下载地址，dlink 有效期 **8 小时**（每次下载现取，不缓存长于会话）。

```
GET {dlink}&access_token={token}
User-Agent: pan.baidu.com
→ 302 Location: https://d.pcs.baidu.com/file/...（实际内容）
```

Alist 的实现（`drivers/baidu_netdisk/util.go` linkOfficial）：先以不跟随重定向的 HEAD 请求拿到 `Location`，再对最终 URL 带 UA 请求。HarmonyOS rcp/http 跟随重定向时会保留自定义 Header，预期可直接跟随；**若实测 403，则采用 Alist 的两步法**（见 5.5 D3）。

#### 3.4.4 预上传 precreate

```
POST PAN/file?method=precreate&access_token={token}
Content-Type: application/x-www-form-urlencoded

path=/path/to/file.kdbx      # 绝对路径
size={字节数}
isdir=0
autoinit=1
rtype=3                       # 覆盖策略：3=覆盖同名文件
block_list=["<分片1md5>","<分片2md5>",...]   # 每 4MB 分片的 MD5（小写 hex），JSON 字符串
content-md5={整个文件的 MD5}    # 秒传匹配用
slice-md5={文件前 256KB 的 MD5} # 秒传匹配用
local_ctime={秒}              # 可选，文件创建时间
local_mtime={秒}              # 可选，文件修改时间
```

响应：

```jsonc
// return_type=1：正常上传，需上传 block_list 指出的分片（增量：服务器已有的分片不在列表中）
{ "errno": 0, "return_type": 1, "path": "/a.kdbx", "uploadid": "P1-xxx",
  "block_list": [0, 1], "request_id": ... }

// return_type=2：秒传成功（服务器已有相同 md5 的文件），info 即文件元信息，0 字节上传
{ "errno": 0, "return_type": 2, "info": { "fs_id": ..., "path": "...", "size": ..., "md5": ... } }
```

#### 3.4.5 分片上传 superfile2

```
POST PCS/superfile2?method=upload&access_token={token}
     &type=tmpfile
     &path={URL 编码后的绝对路径}
     &uploadid={precreate 返回}
     &partseq={0 基分片序号}
Content-Type: multipart/form-data; boundary=...
--...
Content-Disposition: form-data; name="file"; filename="a.kdbx"
<二进制分片数据>
→ { "md5": "<该分片 MD5>" }     # 成功响应
失败: { "error_code": ..., "error_msg": ... } 或含 "uploadid expired/invalid" 文本
```

- 分片大小：**固定 4MB**（普通用户上限 4MB；会员 16MB / SVIP 32MB 为"上限"而非要求，4MB 全兼容）；
- 末片为剩余字节数；分片数量上限 1024（官方文档）/ 2048（实测），4MB 分片即可支撑 4GB（普通用户单文件上限）——对 kdbx 场景充裕；
- 分片序号 `partseq` 从 0 开始；按 precreate 返回的 `block_list` 中**列出的序号**上传（续传时只传缺失片）；
- 失败重试：传输层错误指数退避重试；`uploadid` 过期（响应文本含 `uploadid` + `expired/invalid/not found`）→ 重新 precreate 全量重传（外层最多 2 轮，Alist 实践）。

#### 3.4.6 创建文件/目录 create

```
POST PAN/file?method=create&access_token={token}
path=/path/to/file.kdbx
size={字节数}
isdir=0
uploadid={precreate 返回的 uploadid}
block_list=["<完整分片 MD5 列表>"]     # 注意：与 precreate 相同的完整列表，不是缺失列表
rtype=3
local_ctime={秒} / local_mtime={秒}
→ { "errno": 0, "fs_id": 456, "path": "/a.kdbx", "size": 1024, "md5": "...", ... }
```

创建目录：同端点，`isdir=1` + `path`，已存在返回 `errno: -8`（幂等处理为成功）。

**已知坑（Alist 注释实证，2024-04）**：create/precreate 返回的时间字段是**当前时间**而非文件时间；真实存储时间为 local_ctime/local_mtime 参数值。因此写入后组装 `FileInfo.modifiedTime` 应使用本地传入值，而非响应值。

#### 3.4.7 文件管理 filemanager（本期不实现，备忘）

```
POST PAN/file?method=filemanager&access_token={token}&opera=delete|move|rename|copy
async=0&filelist=["/path"]&ondup=fail|newcopy|overwrite|skip
```

### 3.5 上传协议要点汇总

写入一个文件的完整决策树（对 kdbx 覆盖保存场景）：

```
write(content):
  1. content 为空(0字节) → 直接报错（百度不允许上传空文件）
  2. 计算:
     content-md5 = MD5(整个 content)
     slice-md5   = MD5(content 前 256KB)
     block_list  = [MD5(content[0:4M]), MD5(content[4M:8M]), ...]
  3. precreate(rtype=3, 带 content-md5/slice-md5)
     ├─ return_type=2 → 秒传命中，直接得到文件元信息，结束（0 字节流量）
     └─ return_type=1 → 得到 uploadid + 待传分片序号列表
  4. 逐片 superfile2 上传（partseq ∈ 待传列表），失败按 3.4.5 重试
  5. create(uploadid + 完整 block_list) → 返回新文件元信息
```

- **秒传**仅在 precreate 携带 `content-md5`/`slice-md5` 时参与匹配；文件 < 256KB 时无法秒传（正常走分片上传，无影响）；
- `rtype=3` 覆盖语义覆盖**同名同路径**文件，无 etag 类条件写能力（条件写模拟方案见 5.11）。

### 3.6 错误码与频次限制

- 通用响应：`{"errno": <code>, ...}`；上传分片错误为 `{"error_code": ..., "error_msg": ...}`；OAuth 端点为 `{"error", "error_description"}`——**三套错误格式并存**，需分别处理；
- **频次限制**：`errno 31034`（用户级）/ `31064`（应用级）→ 指数退避重试；
- 完整错误码处理表见**附录 B**；
- **下载限速**：官方 dlink 下载对非会员账号有限速（SVIP 不限）。kdbx 文件体积小，实测影响预计可接受，列入真机联调验证项。

### 3.7 关键限制与风险清单

| # | 风险/限制 | 影响 | 缓解 |
| --- | --- | --- | --- |
| R1 | 百度控制台能否配置自定义 scheme 回调 `keepassho://aimilin.com/baidu/redirect` **待实测** | 阻塞主授权方案 | 兜底方案 B：`oob` 手动输码 UI（100% 可行，bypy 验证多年） |
| R2 | API 权限逐项审核 + 应用上线审核周期 | 正式用户不可用（测试账号可用） | Phase 0 人工流程尽早启动；代码不阻塞 |
| R3 | list 返回的 md5 可能是混淆值（含非 hex 字符） | version 字段不可信 | 附录 C `decryptBaiduMd5` 还原算法（Alist 实证） |
| R4 | 下载 UA 强校验（非 `pan.baidu.com` → 403） + 302 | 下载链路失败 | 固定 UA；若 rcp 跟随重定向丢 UA 则改两步法（5.5） |
| R5 | 空文件不可上传（errno/业务校验） | write 空内容报错 | 前置校验给出明确错误文案（kdbx 永不为空，实际影响小） |
| R6 | create 返回时间为当前时间而非文件时间 | FileInfo.modifiedTime 失真 | 写入后用本地 mtime 组装（3.4.6） |
| R7 | 频次限制 31034/31064 | 列目录/上传偶发失败 | 统一退避重试（1s/2s/4s，3 次） |
| R8 | token 30 天过期；Worker 与主线程可能并发刷新 | 401 期间操作失败 | `refreshingPromise` 并发去重（OneDrive 模式）+ 百度旧 refresh_token 复用期长，天然容错 |
| R9 | dlink 8 小时有效 | 下载失败 | 每次下载现取 dlink，不长期缓存 |
| R10 | 未上线应用仅测试账号可用 | 联调期只能自测账号 | Phase 0 完成上线审核 |

---

## 4. 现有存储架构分析（结合 WebDAV / S3 / OneDrive / 华为云盘）

### 4.1 存储抽象体系

所有远端存储实现 `IFileStorage`（`storage/IFileStorage.ets`），继承 `BaseFileStorage`（`storage/BaseFileStorage.ets`）后**只需实现 6 个抽象原语**：

```
getPageConfig(): PageConfig                        # 入口卡片（图标/标题/描述/页面路由）
init(config: StorageConfig): void                  # 注入配置（worker 内也会调用）
read(path): Promise<ArrayBuffer>                   # 整缓冲读
write(path, content, option?, onProgress?): Promise<void>   # 整缓冲写，option.expectedVersion 条件写
getInfoOrNull(path): Promise<FileInfo | null>      # 存在性唯一权威原语：确定不存在→null；无法判定→抛
listDir(path): Promise<Array<FileInfo>>            # 列目录
```

基类免费派生：`getInfo`（null→FILE_INFO_ERROR）、`exists`、`readToFile`/`writeFromFile`（整缓冲默认实现，走 `FileTransfer`）、`supportsVersionFastPath()`（默认 false）、`readCacheToFile`（恒 false）。

关键约束：

- `getInfoOrNull` **禁止把一切异常映射为 null**（网络错误必须上抛，否则会误判"文件不存在"）；
- `write` 的 `option.expectedVersion` 不一致时必须抛 `StorageError(VERSION_CONFLICT)`；
- 错误统一抛 `StorageError`，码表见 `storage/StorageError.ets`：`FILE_READ_ERROR / FILE_WRITE_ERROR / FILE_INFO_ERROR / CONNECT_ERROR / AUTH_EXPIRED / VERSION_CONFLICT / UPLOAD_TOO_LARGE` 等；
- 单请求体积上限 `HTTP_UPLOAD_MAX_BYTES = 100MB`（http 协议栈限制）——百度 4MB 分片天然满足。

### 4.2 工厂注册与缓存装饰

`storage/FileStorageFactory.ets`：私有构造函数中注册各实现；`getStorage(type)` 对**非 LOCAL 类型自动包裹 `CacheStorage` 装饰器**（本地内容缓存 + 版本失效）。新后端注册一行：

```ts
this.registerStorage(StorageType.BAIDU_NETDISK, new BaiduNetdiskStorage());
```

注册后自动获得：`SelectLocation` 页卡片（遍历 `FileStorage.getAllPageConfig()`）、`PageConfigManager` 页面样式、RecentFiles 探活（`probeFileInfo` → `KdbxFileManager.getInfoOrNull`）。**SelectLocation / StorageNavigation / FileList / PageConfigManager 均无需改动。**

### 4.3 OAuth2 通用框架

`common/oauth2/`（7 个文件，`index.ets` 统一导出）：

| 组件 | 职责 | 与本功能关系 |
| --- | --- | --- |
| `BaseOAuth2Provider` | 授权 URL 拼装（response_type=code、scope、state、authExtraParams）、authorize/refreshToken（POST form）、`parseTokenResponse`、sendHttpRequest（@ohos http） | 百度 token 端点为 GET 风格 → **覆写 authorize/refreshToken 为 GET 查询参数**（5.4） |
| `OAuth2AuthService` | `loadToken/saveToken/deleteToken(provider)`（加密）+ `exchangeCodeForToken(provider, code, state)` = authorize + saveToken | 页面登录回调后一次调用 |
| `OAuth2TokenStorageService` | 令牌持久化到 filesDir JSON（huks 加密值），**文件形态保证 Worker 可读**；迁移白名单已含 BAIDU_NETDISK | 直接复用 |
| `OAuth2Error` | 错误码（TOKEN_REFRESH_FAILED / AUTHORIZATION_FAILED / STATE_MISMATCH...） | 直接复用 |

Provider 实现与所属存储同目录（如 `storage/onedrive/OneDriveOAuth2Provider.ets`），本项目照此放置 `storage/baidu/BaiduNetdiskOAuth2Provider.ets`。

### 4.4 配置模型与加密

- 每个存储一个 `XxxStorageConfig implements StorageConfig`，**凭据字段经 `Sm4Utils.encryptWithPrefix` 加密存储**（SM4-CBC，密钥存 HarmonyOS Asset Kit `'sm4_key'`，`'SM4:'` 前缀标识密文）；
- 配置对象随 `RecentFile.storageConfig` 持久化、随 `DbFileParam` 在 Worker 间传递（`services/FileService.ets`）；
- OneDrive 模式（`OneDriveConfig.ets`）：`accessToken/refreshToken` 加密字段 + `getAccessTokenText()/getRefreshTokenText()` 解密读 + `expiresAt` + `isTokenExpired()`（提前 5 分钟判过期）——**百度照抄此模式**；
- OAuth 登录态令牌另存 `OAuth2TokenStorageService`（供再次进入 App 时恢复"已登录"状态），与 StorageConfig 内嵌令牌双轨并存（OneDrive/Huawei 均如此）。

### 4.5 UI 集成链路（OneDrivePage 模板，515 行）

```
SelectLocation（动态遍历 getAllPageConfig）
  └→ 点击卡片 → 路由跳转 pageUrl 末段（route_map.json 注册的 BaiduNetdiskPage）
       ├→ aboutToAppear: initSaveParam() + loadTokenFromStorage()      # 恢复登录态
       ├→ 未登录: generateAuthUrl() → StorageNavigation.pushOAuth2Login(url, config, 标题)
       │    └→ pages/OAuth2Login.ets（内嵌 webview）
       │         redirect keepassho://aimilin.com/... → 解析 AuthCallbackResult
       │         → AppStorage.set('oauth2_auth_result') → 返回
       ├→ NavDestination.onShown: 读取 oauth2_auth_result
       │    → OAuth2AuthService.exchangeCodeForToken(provider, code, state, BAIDU_NETDISK)
       │    → 登录成功 → toFileList()
       └→ StorageNavigation.pushFileList(StorageType.BAIDU_NETDISK, '/', storageConfig)
            └→ pages/open/FileList.ets（共享文件浏览器）
                 └→ 选中 → LocationParam.callOnLocation(LocationInfo) 完成选择
```

保存（导出）模式复用同一页面：`LocationParam.isSaveMode()` → `initSaveParam()` 从 `FileService.getDbFileParam()` 还原配置。

### 4.6 Worker 线程约束

- `workers/DatabaseLoad.ets`：`readToFile` 流式下载到本地缓存后加载；`workers/DatabaseSave.ets`：`writeFromFile` 上传，处理 VERSION_CONFLICT/ConflictStrategy；
- Worker 通过 `KdbxFileManager` → `FileStorageFactory.getStorage(type)` 取存储并 `init(config)`——**存储实现必须 Worker 线程安全**：不得依赖 preferences/AppStorage，令牌/缓存读写走文件形态（OAuth2TokenStorageService、HuaweiDrivePathCacheStore 即为此设计）；
- 百度实现所有状态（token、uploadid 等）仅存活于单次 write 调用内，无跨调用可变共享状态，天然满足；token 刷新使用 `@ohos.net.http`（Worker 可用，HuaweiDrive 同模式）。

### 4.7 HTTP 客户端基建

无全局共享 HTTP 工具，各后端自选：WebDAV/S3 用 **rcp**（`@kit.RemoteCommunicationKit`，含 SessionPool 会话复用），OneDrive/Huawei 用 **axios + rcp**。本实现选择 **rcp**（理由见 5.1 D2）。可用工具：`UrlUtils`（host/校验/编解码）、`HashUtils`/`CryptoUtils`（MD5）、`ByteUtils`（kdbxweb 模块导出）、`NetworkUtils.hasNetwork()`。

### 4.8 横向对标表

| 维度 | WebDAV | S3 | OneDrive | 华为云盘 | FTP/SFTP | **百度网盘（本设计）** |
| --- | --- | --- | --- | --- | --- | --- |
| 认证 | Basic/Digest | SigV4 签名 | OAuth2 授权码（公开客户端） | OAuth2 授权码 | 账密 | **OAuth2 授权码** |
| HTTP 客户端 | rcp | rcp + SessionPool | axios + rcp | axios + rcp | basic-ftp / Rust | **rcp** |
| 读 | GET 整缓冲 | GET（Range） | GET | GET | RETR | **filemetas→dlink→GET（UA+302）** |
| 写 | PUT | 分片上传队列 | 上传会话（4MB 阈值） | 断点续传 | STOR | **precreate→superfile2×N→create** |
| 覆盖保存 | PUT 覆盖 | rtype 等价覆盖 | conflictBehavior | 覆盖 | STOR 覆盖 | **rtype=3 覆盖** |
| 版本标识 | etag+mtime 组合 | etag | etag | revision | mtime | **md5（附录 C 还原后）** |
| 条件写 | If-Match（原生） | HEAD etag 预检 | — | ensureVersionMatch 预检 | 上传前 stat 预检 | **md5 预检模拟（同 FTP/华为模式）** |
| 并发/续传 | — | multipart 队列 | 分片会话 | 分片续传 | op 队列串行 | **分片重传（MVP 不做持久续传）** |

---

## 5. 总体设计

### 5.1 关键决策记录

| # | 决策点 | 选择 | 理由 | 放弃的备选 |
| --- | --- | --- | --- | --- |
| D1 | 实现范式 | OAuth 型云盘后端，整体对标 OneDrive | 同为"OAuth + REST 文件 API"，页面/配置/token 模式可直接复制 | WebDAV/S3 的服务器配置型 |
| D2 | HTTP 客户端 | rcp（单 Session 复用，参照 HuaweiDriveClient `getRcpSession`） | 原生支持 multipart、自定义 Header（UA）、进度回调；仓库内已有成熟参照 | axios（需引依赖）；@ohos http（multipart/进度弱） |
| D3 | 下载 302 处理 | rcp 默认跟随重定向 + 固定 UA；若实测 403 切换两步法（先 HEAD 拿 Location 再 GET） | 跟随重定向 UX 简单；两步法为 Alist 验证的兜底 | — |
| D4 | 上传形态 | 整缓冲（write 收 ArrayBuffer）→ 4MB 切片 superfile2 | kdbx 体积小；`writeFromFile` 用基类默认实现（读源文件进内存再 write） | 流式分片（kdbx 场景收益低，YAGNI） |
| D5 | 秒传 | precreate 携带 content-md5/slice-md5，return_type=2 直接完成 | 零流量保存（内容未变场景）；Alist 同款 | 不传（浪费免费优化） |
| D6 | 分片大小 | 固定 4MB（不调 uinfo 里的 vip_type 自适应） | 4MB 是全会员类型合法值；kdbx 场景 1~2 片；避免为自适应引入 uinfo 强依赖 | 16/32MB 会员自适应（无收益） |
| D7 | 版本快速路径 | **MVP `supportsVersionFastPath()` = false**；version 字段填还原后的 md5；Phase 2 评估开启 + 预检条件写（5.11） | md5 理论可信（内容寻址），但 list 混淆 md5（R3）需真机充分验证；false 保持"全量校验"安全语义 | 直接 true（风险：混淆 md5 未还原干净时误判） |
| D8 | 条件写 | `option.expectedVersion` 存在时：写前 `getInfoOrNull` 比对 md5，不一致抛 VERSION_CONFLICT（FTP/华为同款模拟） | 防多端覆盖丢数据（密码管理器关键安全属性）；非原子竞态由保存链路全量校验兜底 | 忽略 expectedVersion（丢失冲突保护） |
| D9 | token 端点调用 | 覆写为 GET 查询参数（官方文档形态，bypy/alist 一致） | 兼容性最稳 | 基类 POST form |
| D10 | 授权方案 | A：自定义 scheme 为主；B：oob 手动输码为内置兜底开关 | 与 OneDrive/PCloud 体验一致；R1 被拒时不阻塞 | 设备码（UX 一般） |
| D11 | 上传域名 | 固定 `https://d.pcs.baidu.com` | Alist 默认同款；kdbx 体量无需 locateupload 动态域名 | 动态域名（后续优化） |

### 5.2 模块与文件结构

```
entry/src/main/ets/storage/baidu/
├── BaiduNetdiskConfig.ets         # BaiduNetdiskStorageConfig（SM4 加密令牌）+ BaiduNetdiskPageConfig
├── BaiduNetdiskTypes.ets          # API 响应模型（BaiduFileMeta/ListResp/PrecreateResp/UserInfo...）+ 常量 + errno 表
├── BaiduNetdiskOAuth2Provider.ets # extends BaseOAuth2Provider（GET token 端点 + uinfo 用户信息）
├── BaiduNetdiskClient.ets         # xpan/pcs API 客户端（请求层/重试/错误映射/下载 UA）
├── BaiduNetdiskStorage.ets        # extends BaseFileStorage（6 原语 + token 刷新链）
└── BaiduNetdiskPage.ets           # 登录页（OneDrivePage 模板 + oob 兜底输入框）
```

需要改动的既有文件（均为少量追加）：

| 文件 | 改动 |
| --- | --- |
| `storage/FileStorageFactory.ets` | 构造函数加 `this.registerStorage(StorageType.BAIDU_NETDISK, new BaiduNetdiskStorage());` |
| `resources/base/profile/route_map.json` | 追加 BaiduNetdiskPage 路由项 |
| `entry/build-profile.json5` | buildProfileFields 追加 `BAIDU_NETDISK_CLIENT_ID/CLIENT_SECRET/REDIRECT_URI` |
| `resources/base|zh_CN|en_US/element/string.json` | 追加 baidu_netdisk_* 文案 |
| `resources/base/media/` | 新增 `ic_baidu.svg`（参照 ic_huawei_drive.svg 风格） |
| `entry/src/ohosTest/ets/test/` | 新增 Baidu 单测套件 + List.test.ets 挂载 |

### 5.3 数据模型设计

**BaiduNetdiskStorageConfig**（照抄 OneDriveConfig 模式）：

```ts
export class BaiduNetdiskStorageConfig implements StorageConfig {
  accessToken: string;      // Sm4Utils.encryptWithPrefix 密文
  refreshToken: string;     // Sm4Utils.encryptWithPrefix 密文
  expiresAt: number;        // 毫秒时间戳
  timeout?: number;         // 默认 30000
  tokenType?: string;
  scope?: string;

  constructor(accessToken, refreshToken, expiresAt, options?) { /* 构造即加密 */ }
  getAccessTokenText(): string;     // decryptWithPrefix
  getRefreshTokenText(): string;
  setAccessToken(v): void;          // encryptWithPrefix
  setRefreshToken(v): void;
  setExpiresAt(v): void;
  isTokenExpired(): boolean;        // 提前 5 分钟
}

export const BaiduNetdiskPageConfig: PageConfig = {
  icon: $r("app.media.ic_baidu"),
  title: '百度网盘',
  selectDesc: $r('app.string.baidu_netdisk_select_file'),
  saveDesc: $r('app.string.baidu_netdisk_save_file'),
  pageUrl: 'storage/baidu/BaiduNetdiskPage',
  storageType: StorageType.BAIDU_NETDISK
};
```

**响应模型（BaiduNetdiskTypes.ets，命名对齐后端字段）**：

```ts
export class BaiduNetdiskConstants {
  static readonly PAN_BASE: string = 'https://pan.baidu.com/rest/2.0';
  static readonly PCS_BASE: string = 'https://d.pcs.baidu.com/rest/2.0';
  static readonly SLICE_SIZE: number = 4 * 1024 * 1024;      // superfile2 分片
  static readonly RAPID_SLICE_MD5_SIZE: number = 256 * 1024;  // slice-md5 取前 256KB
  static readonly DOWNLOAD_UA: string = 'pan.baidu.com';
  static readonly LIST_PAGE_SIZE: number = 200;
  static readonly RTYPE_OVERWRITE: number = 3;
}

export interface BaiduFileMeta {
  fsId: number;             // fs_id
  path: string;
  serverFilename: string;   // server_filename
  isdir: number;
  size: number;
  md5: string;
  dlink?: string;
  serverCtime: number;      // 秒
  serverMtime: number;      // 秒
}

export interface BaiduListResp { errno: number; list: Array<BaiduFileMeta>; requestId: number; }
export interface BaiduUserInfo { errno: number; uk: number; baiduName: string; netdiskName: string; avatarUrl: string; vipType: number; }
export interface BaiduPrecreateResp {
  errno: number; returnType: number; uploadid: string; blockList: Array<number>; info?: BaiduFileMeta;
}
```

> JSON 解析遵循仓库 ArkTS 规范：`JSON.parse` 后按显式字段拷贝进上述 interface，禁止动态取键。

### 5.4 BaiduNetdiskOAuth2Provider 设计

```ts
export class BaiduNetdiskOAuth2Provider extends BaseOAuth2Provider {
  getProviderName(): string { return 'BaiduNetdisk'; }

  // 覆写：百度 token 端点为 GET 查询参数风格（D9）
  async authorize(authRequest: OAuth2AuthRequest): Promise<OAuth2Token>   // GET token?grant_type=authorization_code&...
  async refreshToken(refreshRequest: OAuth2RefreshRequest): Promise<OAuth2Token>  // GET token?grant_type=refresh_token&...

  // BaseOAuth2Provider 的 sendHttpRequest 为 POST form → 新增 protected GET 版本
  // 或直接用 @ohos http 手写两个 GET 请求，复用基类 parseTokenResponse()

  async getUserInfo(accessToken: string): Promise<OAuth2UserInfo> {
    // GET PAN/nas?method=uinfo&access_token= → { userId: uk, userName: netdisk_name, avatarUrl }
  }
}

export function createBaiduNetdiskOAuth2Config(clientId, clientSecret, redirectUri): OAuth2Config {
  return {
    clientId, clientSecret,
    authorizationEndpoint: 'https://openapi.baidu.com/oauth/2.0/authorize',
    tokenEndpoint: 'https://openapi.baidu.com/oauth/2.0/token',
    redirectUri,                                            // keepassho://aimilin.com/baidu/redirect
    scope: 'basic,netdisk',
    authExtraParams: { 'display': 'mobile' }                // 移动端登录页
  };
}
```

要点：

- 授权 URL 生成复用基类 `getAuthorizationUrl()`（response_type=code + scope + state 自动拼装）；
- `state` 校验沿用 `AuthCallbackResult.codeFlow.state` 链路（OneDrivePage 同款）；
- 刷新响应的**新 refresh_token 必须落库**（OAuth2TokenStorageService + StorageConfig 双轨，见 5.7）。

### 5.5 BaiduNetdiskClient 设计

```ts
export class BaiduNetdiskClient {
  constructor(private config: BaiduNetdiskStorageConfig,
              private onTokenRefreshed: (t: OAuth2Token) => void)

  // —— 请求层（核心） ——
  private async request(path, method, queryParams, form?): Promise<Object>
  //   1. ensureValidToken()
  //   2. rcp session 请求 PAN_BASE + path（access_token 注入 query）
  //   3. 解析 JSON → errno !== 0 → 错误映射（附录 B）：
  //      { -6, 111, 20016 } → 触发 token 刷新后重试 1 次 → 仍失败 StorageError(AUTH_EXPIRED)
  //      { 31034, 31064 }   → 指数退避 1s/2s/4s 重试 3 次 → 仍失败 StorageError(CONNECT_ERROR)
  //      其余               → FILE_READ/WRITE/INFO_ERROR（带 errno 与 error_msg 文案）
  //   4. 网络层错误（超时/断连）→ 退避重试 3 次

  // —— API 封装 ——
  getUinfo(): Promise<BaiduUserInfo>
  listDir(dir: string, start: number, limit: number): Promise<BaiduListResp>
  getFileMetas(fsIds: Array<number>): Promise<Array<BaiduFileMeta>>       // dlink=1
  resolveFileInfo(path: string): Promise<BaiduFileMeta | null>
  //    百度无"按路径取元信息"API → list 父目录（分页）+ server_filename 精确匹配
  //    父目录 errno -9/50002 → 文件确定不存在 → null
  download(dlink: string, onProgress?): Promise<ArrayBuffer>
  //    GET dlink + '&access_token=' + token，UA: pan.baidu.com，跟随 302（D3 兜底两步法）
  precreate(req: BaiduPrecreateRequest): Promise<BaiduPrecreateResp>
  uploadSlice(path: string, uploadid: string, partSeq: number, data: ArrayBuffer): Promise<string>  // → 分片 md5
  //    POST PCS_BASE/superfile2（multipart 字段名 "file"）；传输错误退避重试 3 次；
  //    响应含 "uploadid"+"expired|invalid|not found" 文本 → 抛专用 UploadIdExpiredError
  createFile(req: BaiduCreateRequest): Promise<BaiduFileMeta>
}
```

进度回调：`onProgress(transferredBytes, totalBytes)`——上传按成功分片累计（`片数×4MB`，末片按实长），下载按 rcp 数据到达回调。

### 5.6 BaiduNetdiskStorage 设计（6 原语映射）

| 原语 | 实现 | 涉及 API |
| --- | --- | --- |
| `getPageConfig()` | 返回 `BaiduNetdiskPageConfig` | — |
| `init(config)` | 构造 `BaiduNetdiskClient`；同配置复用已建 client（参照 WebDAV init 的 config 比对；注意 SM4-CBC 非确定性，**比对需比较解密后的明文**，参照 FTPStorage.init:57-73） | — |
| `read(path)` | resolveFileInfo → getFileMetas([fsId]) → download(dlink) | list + filemetas + dlink |
| `write(path, content, option?, onProgress?)` | 见下方伪代码 | precreate + superfile2 + create |
| `getInfoOrNull(path)` | resolveFileInfo；父目录 -9/50002 → null；网络/token 异常上抛（AUTH_EXPIRED 等） | list |
| `listDir(path)` | `list` 分页循环聚合（LIST_PAGE_SIZE=200），映射为 `FileInfo` | list |

`write` 伪代码：

```
write(path, content, option, onProgress):
  if content.byteLength === 0:
    throw StorageError(FILE_WRITE_ERROR, '百度网盘不支持上传空文件')

  // 1. 条件写预检（D8）
  if option?.expectedVersion:
    remote = await resolveFileInfo(path)
    if remote && toVersion(remote) !== option.expectedVersion:
      throw StorageError(VERSION_CONFLICT, ...)

  // 2. 计算 MD5（复用 HashUtils/CryptoUtils）
  contentMd5 = md5(content)
  sliceMd5   = md5(content[0 : 256KB])
  blockList  = 每 4MB 一片的 md5 数组（末片为余量）

  // 3. precreate（rtype=3 + 秒传参数）
  pre = await client.precreate({ path, size, blockList, contentMd5, sliceMd5,
                                 localCtime, localMtime })
  if pre.returnType === 2: return                        // 秒传命中

  // 4. 逐片上传（uploadid 过期 → 重新 precreate 全量重传，外层 ≤ 2 轮）
  for partSeq of pre.blockList:
    await client.uploadSlice(path, pre.uploadid, partSeq, sliceOf(content, partSeq))
    onProgress?.(累计字节, 总字节)

  // 5. create（完整 blockList + uploadid + rtype=3）
  meta = await client.createFile({ path, size, uploadid: pre.uploadid, blockList, ... })
  // 注意 R6：不使用 meta 中的时间字段
```

`FileInfo` 映射：

```
toFileInfo(meta: BaiduFileMeta): FileInfo = {
  name: meta.serverFilename || path 末段,
  size: meta.size,
  modifiedTime: meta.serverMtime * 1000,      // 秒 → 毫秒
  path: meta.path,
  type: meta.isdir === 1 ? FileType.DIR : FileType.FILE,
  version: meta.isdir === 1 ? null : decryptBaiduMd5(meta.md5),   // 附录 C；目录无版本
  childrenCount: undefined
}
```

### 5.7 Token 生命周期管理

```
                 ┌────────────────────────────────────────────┐
                 │  BaiduNetdiskPage（登录，主线程）             │
                 │  loadToken(BAIDU_NETDISK) ──────┐          │
                 │  exchangeCodeForToken ─┐        │          │
                 └────────────────────────┼────────┼──────────┘
                                          ▼        ▼
        OAuth2TokenStorageService（filesDir JSON + huks 加密，Worker 可读）
                                          │
                 ┌────────────────────────▼───────────────────┐
                 │  BaiduNetdiskStorageConfig（SM4 加密）       │
                 │  随 RecentFile.storageConfig 持久化          │
                 │  随 DbFileParam 传入 Worker                  │
                 └────────────────────────────────────────────┘

运行期（读/写前）:
  isTokenExpired()（提前 5 分钟）→ refreshToken（GET token 端点）
      ├─ 成功: setAccessToken/setRefreshToken/setExpiresAt 回写 config
      │        + onTokenRefreshed 通知（EventBus，参照 OneDrive notify 机制回写 DbFileParam/RecentFile）
      └─ refreshingPromise 并发去重（OneDriveStorage.refreshingPromise 模式，防 Worker/主线程并发刷新）
  刷新失败 → StorageError(AUTH_EXPIRED)，UI 引导重新登录
```

- 每次刷新返回**新 refresh_token**，双轨（TokenStorageService + StorageConfig）都要更新；
- 百度旧 refresh_token 在有效期内可重复使用 → Worker 内刷新成功、主线程尚持旧 token 的瞬态不致互斥失效（R8 缓解）；
- `logout`：`OAuth2AuthService.deleteToken(BAIDU_NETDISK)` + 清空页面状态（OneDrivePage.logout 同款）。

### 5.8 授权方案与兜底

**主方案 A（自定义 scheme）**：

- 回调地址：`keepassho://aimilin.com/baidu/redirect`（scheme 已在 `module.json5:84-89` 注册，`OAuth2Login` 页已解析该 scheme 的 code 回调，与 OneDrive/PCloud 完全同链路）；
- **Phase 0 必须先在百度控制台实测能否保存该回调地址**（风险 R1）。

**兜底方案 B（oob 手动输码）**：

- 控制台配置 `redirect_uri=oob` 时，授权页最终**直接展示授权码**；
- `BaiduNetdiskPage` 增加折叠的"手动输入授权码"入口：TextInput + 确认按钮 → 复用 `exchangeCodeForToken`（`redirect_uri=oob`）；
- 实现成本低（一个输入框 + 复用现有方法），**建议无条件内置**，作为方案 A 失败时的开关（常量或远端配置切换）。

### 5.9 BaiduNetdiskPage 与 UI 流程

完整复制 OneDrivePage 结构（约 515 行 → 预计 ~550 行）：

1. 顶部账号卡：头像（avatar_url）+ netdisk_name + vip 标签（uinfo）；
2. 登录按钮 → `generateAuthUrl()` → `pushOAuth2Login`；
3. `onShown` 处理 `oauth2_auth_result` → `exchangeCodeForToken` → `toFileList()`；
4. 已登录态：显示"进入文件列表 / 退出登录"；
5. 保存模式：`initSaveParam()` 还原 `DbFileParam.storageConfig`；
6. 兜底：oob 授权码输入区（5.8）。

文案资源（`baidu_netdisk_*` 前缀，base/zh_CN/en_US 三份，对齐 onedrive_* 键位）：

```
baidu_netdisk_title / baidu_netdisk_select_file / baidu_netdisk_save_file
baidu_netdisk_authenticating / baidu_netdisk_authentication_successful / baidu_netdisk_authentication_failed
baidu_netdisk_login_successful / baidu_netdisk_logout_successful
baidu_netdisk_empty_file_forbidden / baidu_netdisk_rate_limited / baidu_netdisk_auth_expired
baidu_netdisk_oob_input_hint / baidu_netdisk_oob_confirm
```

### 5.10 错误处理与重试策略

| 层 | 策略 |
| --- | --- |
| 网络层（超时/断连） | 指数退避重试 3 次（1s/2s/4s），`NetworkUtils.hasNetwork()` 前置判断 |
| token 失效（errno -6/111/20016） | 刷新一次后重试一次；仍失败 → `AUTH_EXPIRED`（UI 引导重新登录，不静默吞掉） |
| 频次限制（31034/31064） | 退避重试 3 次 → `CONNECT_ERROR` + "稍后再试"文案 |
| 分片传输错误 | 退避重试 3 次（cap 5s，Alist 参数） |
| uploadid 过期 | 重新 precreate 全量重传，外层 ≤ 2 轮 |
| 参数/权限错误（2/-7/6/31023） | 不重试，直接上抛带 errno 的 StorageError |
| `getInfoOrNull` | -9/50002 → null；其余异常**必须上抛**（禁止全量映射 null） |

### 5.11 版本与条件写策略（两阶段）

**Phase 1（本期 MVP）**：

- `supportsVersionFastPath()` 返回 **false**（基类默认）→ 保存链路走全量校验（下载比对），加载链路不走版本捷径——**语义最安全**；
- `FileInfo.version` 仍填充还原后的 md5（附录 C），供 UI/缓存比较使用；
- 条件写采用**预检模拟**（D8）：write 前 md5 比对，不一致抛 VERSION_CONFLICT。竞态窗口（预检通过到 create 完成之间他端覆盖）由全量校验兜底。

**Phase 2（真机验证后评估）**：

- 前提：附录 C 还原算法在真机 list/filemetas 实测中 100% 还原为合法 md5（R3 验证）；
- 开启 `supportsVersionFastPath() = true`：版本随内容变化（md5 内容寻址）+ 条件写预检已就绪 → 加载链路可跳过未变化文件的重复下载。

### 5.12 安全考量

1. **令牌加密**：accessToken/refreshToken 经 Sm4Utils（Asset Kit 密钥）加密后落盘；OAuth2TokenStorageService 侧 huks 加密——双轨均密文；
2. **client_secret 管理**：与华为云盘一致置于 `build-profile.json5` buildProfileFields（随包分发，接受与华为同级的暴露面；百度开放平台为标准做法）；
3. **scope 最小化**：仅申请 `basic,netdisk`，不申请额外个人信息 scope；
4. **state 校验**：授权回调 CSRF 校验沿用框架（STATE_MISMATCH）；
5. **日志**：access_token/refresh_token/授权码一律脱敏（hilog %{private}s 或截断），错误上报不含令牌；
6. **竞态**：`refreshingPromise` 并发去重，防止并发刷新竞态。

### 5.13 性能与体验

- kdbx 典型 100KB~5MB：上传 1~2 片、下载单请求，用户感知为"一次网络往返 + 一次覆盖写"；
- list 分页 200/页（Alist 实测值，兼顾首屏速度与请求次数）；
- 进度回调分片粒度即可（写路径），读路径 rcp 收包粒度；
- 下载限速（非会员）对小文件影响预计 < 2s，真机联调时实测确认。

---

## 6. 实施计划

### 6.1 阶段划分

| 阶段 | 内容 | 产出 | 依赖 |
| --- | --- | --- | --- |
| **Phase 0**（人工，并行） | 开放平台注册、建应用、申请 5 组 API 权限、配置回调地址（实测 R1）、上线审核、获取 AppKey/SecretKey | 可用的 `BAIDU_NETDISK_CLIENT_ID/SECRET/REDIRECT_URI` | 不阻塞编码 |
| **Phase 1** 数据模型与 Provider | `BaiduNetdiskConfig.ets`、`BaiduNetdiskTypes.ets`、`BaiduNetdiskOAuth2Provider.ets`、build-profile.json5 字段 | 编译通过 + OAuth 单测 | — |
| **Phase 2** Client 请求层与读链路 | `BaiduNetdiskClient.ets`：request 层（errno 映射/重试/刷新钩子）、uinfo/list/filemetas/download、附录 C md5 还原 | read/getInfoOrNull/listDir 可用 + 单测 | Phase 1 |
| **Phase 3** 上传链路 | md5 三元组计算、precreate/superfile2/create、秒传、uploadid 过期重传、进度回调 | write 可用 + 单测 | Phase 2 |
| **Phase 4** Storage 装配 | `BaiduNetdiskStorage.ets`：6 原语、条件写预检、token 刷新链（refreshingPromise）、错误映射 | 工厂可注册 + KdbxFileManager 链路可用 | Phase 3 |
| **Phase 5** UI 与资源 | `BaiduNetdiskPage.ets`、route_map、strings×3、ic_baidu.svg、工厂注册、（oob 兜底输入） | 全链路可操作 | Phase 4 |
| **Phase 6** 测试与发布 | 单测全量、真机 e2e（第 7 章）、`arkts_check` + `devecocli build`、`devecocli run --skip-build` 覆盖安装真机 | 验收通过 | Phase 5 + Phase 0（联调需测试账号） |

### 6.2 验收标准

1. `SelectLocation` 出现"百度网盘"卡片 → 登录（方案 A 或 B）→ 浏览目录 → 选择远端 `.kdbx` → 解锁成功；
2. 修改条目 → 保存 → 百度网盘文件 mtime/md5 更新；再次加载内容一致；
3. 双端制造版本冲突 → 保存端收到 VERSION_CONFLICT 提示（冲突策略 UI）；
4. 断网/令牌过期（改系统时间或等待）/频次限流场景给出可读错误，不崩溃、不误判"文件不存在"；
5. 退出登录后重新登录，RecentFiles 探活（`probeFileInfo`）正常；
6. `arkts_check` 无违规、`devecocli build` SUCCESS、真机覆盖安装（保留数据）运行正常；
7. 单测通过（`hdc shell aa test -b com.aimilin.keepassho -m entry_test ...`）。

---

## 7. 测试计划

| 层级 | 内容 |
| --- | --- |
| 单元测试（ohosTest） | ① md5 三元组计算（含 <4MB、恰 4MB、多片、末片余量）② 附录 C `decryptBaiduMd5`（合法 hex 原样返回 / 混淆串还原 / 双向互逆）③ precreate/create 响应解析（return_type 1/2 分支）④ errno → StorageError 映射表（含 -6 刷新重试路径，mock client）⑤ block_list 分片序号与 4MB 边界 ⑥ 空内容 write 报错 ⑦ OAuth provider：GET token 端点 URL 拼装、parseTokenResponse、新 refresh_token 落库 |
| 集成（真机 + 测试账号） | ① 登录（方案 A scheme 回跳 / 方案 B oob 输码）② uinfo 展示 ③ 列目录翻页 ④ 下载 dlink（UA/302）⑤ 上传（秒传命中 + 全量分片 + 覆盖 rtype=3）⑥ 条件写 VERSION_CONFLICT ⑦ token 过期自动刷新 ⑧ Worker 保存链路 ⑨ 退出登录 |
| e2e（可选增强） | 本地 mock server 模拟 xpan 契约（参照 `docs/e2e/e2e-fileserver.sh` 模式）做回归；因百度无本地服务可搭，主回归以真机 + 测试账号清单为准 |
| 回归 | 现有 oauth2 测试套件（已引用 BAIDU_NETDISK）保持通过；其余存储类型不受影响（工厂追加不影响既有注册） |

---

## 8. 附录

### 附录 A：API 速查表

| 能力 | 方法与端点 | 关键参数 |
| --- | --- | --- |
| 授权 | GET `openapi.baidu.com/oauth/2.0/authorize` | response_type=code, client_id, redirect_uri, scope=basic,netdisk, display=mobile, state |
| 令牌 | GET `openapi.baidu.com/oauth/2.0/token` | grant_type=authorization_code|refresh_token, code|refresh_token, client_id, client_secret, redirect_uri |
| 设备码 | GET `openapi.baidu.com/oauth/2.0/device/code` | client_id, response_type=device_code, scope（轮询 grant_type=device_token） |
| 用户信息 | GET `pan.baidu.com/rest/2.0/xpan/nas` | method=uinfo |
| 文件列表 | GET `pan.baidu.com/rest/2.0/xpan/file` | method=list, dir, order, desc, start, limit(≤1000), web, folder |
| 文件元信息 | GET `pan.baidu.com/rest/2.0/xpan/multimedia` | method=filemetas, fsids=[..], dlink=1, thumb |
| 下载 | GET `{dlink}&access_token=..` | Header `User-Agent: pan.baidu.com`；302 跟随；dlink 8h 有效 |
| 预上传 | POST `pan.baidu.com/rest/2.0/xpan/file` | method=precreate, path, size, isdir=0, autoinit=1, rtype=3, block_list, content-md5, slice-md5, local_ctime/mtime |
| 分片上传 | POST `d.pcs.baidu.com/rest/2.0/pcs/superfile2` | method=upload, type=tmpfile, path, uploadid, partseq；multipart 字段 `file`；4MB/片 |
| 创建 | POST `pan.baidu.com/rest/2.0/xpan/file` | method=create, path, size, isdir, uploadid, block_list(完整), rtype=3, local_ctime/mtime |
| 管理 | POST `pan.baidu.com/rest/2.0/xpan/file` | method=filemanager, opera=delete|move|rename|copy, filelist, async, ondup |

### 附录 B：错误码处理表

| errno / error_code | 含义 | 处理 |
| --- | --- | --- |
| 0 | 成功 | — |
| -6 / 111 / 20016 | access_token 失效 | 刷新 token 重试 1 次 → 仍失败 `AUTH_EXPIRED` |
| 2 / 31023 | 参数错误 | 不重试，上抛 |
| -7 | 文件名非法/无权限 | 不重试，上抛 |
| -8 | 文件/目录已存在 | mkdir 场景幂等成功 |
| -9 / 50002 / 42212 | 文件或目录不存在 | `getInfoOrNull`→null；list→`FILE_INFO_ERROR` |
| 6 | 无权限（scope/审核未过） | 不重试，提示检查应用权限 |
| 12 / 31061 | 文件已存在 | rtype=3 下不应出现，出现即上抛 |
| 31034 | 用户级频次限制 | 退避重试 3 次 |
| 31064 | 应用级频次限制 | 退避重试 3 次 + "稍后再试" |
| 31079 | md5 未找到（秒传未命中） | 正常走分片上传（precreate return_type=1） |
| 31081 | superfile 创建失败（404） | 重试当前分片 |
| 31363 | 分片缺失（403） | 重新 precreate 续传 |
| 36016 | 任务不存在 | 重新 precreate |
| HTTP 403（下载） | UA 校验失败 | 确认 UA=pan.baidu.com；切两步法 |
| 响应含 `uploadid`+`expired/invalid/not found` | uploadid 过期 | 重新 precreate 全量重传（≤2 轮） |
| OAuth `{"error":...}` | 授权/刷新失败 | 映射 `OAuth2Error`（TOKEN_REFRESH_FAILED 等） |

### 附录 C：MD5 混淆还原算法（decryptBaiduMd5）

背景（风险 R3）：list/filemetas 返回的 `md5` 字段部分情况下为**混淆值**（含 `g`~`z` 等非 hex 字符），需还原为真实内容 md5，否则 `FileInfo.version` 不可信。算法来自 Alist（`drivers/baidu_netdisk/util.go`，其 `fileToObj` 注释："直接获取的MD5是错误的"）：

```
decrypt(mixed):
  if mixed 是合法 32 位 hex → 原样返回（未混淆）
  decoded = ''
  for i in 0..len(mixed)-1:
      n = (i == 9) ? (lower(mixed[i]) - 'g')          // 第 10 位特殊：字母映射
                   : parseInt(mixed[i], 16)           // 其余按 hex 解析
      decoded += hex(n XOR (15 AND i))                // 每位异或其下标的低 4 位
  return decoded[8:16] + decoded[0:8] + decoded[24:32] + decoded[16:24]   // 4 段 8 字符重排
```

ArkTS 实现放 `BaiduNetdiskClient` 私有方法或 `BaiduNetdiskTypes` 静态方法；配套单测需覆盖：合法 hex 直返、混淆串还原、与 Alist Go 实现输出一致性（用相同测试向量）。

### 附录 D：参考资料

| 资料 | 位置 |
| --- | --- |
| 百度网盘开放平台（文档/控制台） | https://pan.baidu.com/union/ （doc: /union/doc/） |
| 百度 OAuth 2.0（账号连接） | https://openapi.baidu.com/wiki/ |
| Alist BaiduNetdisk 驱动（xpan 完整实现，本设计主要 API 依据） | https://github.com/AlistGo/alist/tree/main/drivers/baidu_netdisk |
| bypy（oob 授权、设备码流程、错误码实践） | https://github.com/houtianze/bypy |
| BaiduPCS-Go | https://github.com/iikira/BaiduPCS-Go |
| 本仓库对标实现 | `entry/src/main/ets/storage/onedrive/`（页面/OAuth 模板）、`huawei/`（token 刷新/路径缓存）、`webdav/`、`s3/`、`ftp/`（条件写预检模式） |
| 本仓库存储架构关键文件 | `storage/IFileStorage.ets`、`storage/BaseFileStorage.ets`、`storage/FileStorageFactory.ets`、`common/oauth2/*`、`workers/DatabaseLoad|DatabaseSave.ets` |
