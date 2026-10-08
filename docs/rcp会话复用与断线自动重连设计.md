# rcp 会话复用与断线自动重连设计（性能优化 #4）

> 状态：评审中 v1（2026-10-08）
> 优先级：**P1 —— 在《Worker常驻池化设计.md》（#3）之后实施**（理由见 §0.1）
> 依赖关系：复用部分（§3）依赖 #3 落地（Worker isolate 常驻）；重连部分（§4）无强依赖，如可靠性需求紧急可先行交付 T1+T2
> 关联：《Worker常驻池化设计.md》（#3）、《数据库异步加载保存与大文件OOM治理设计.md》（S3 存储流式化）
> 优化编号承接《性能优化盘点》：#4 rcp Session 复用 + 断线自动重连
> 拆分自原合并版《Worker常驻池化与rcp会话复用设计》（v1 2026-10-07），拆分后原文档废弃

## 0. 目标与非目标

### 0.1 排序理由（为何排在 #3 之后）

| 维度 | 说明 |
|---|---|
| 复用收益依赖 #3 | 数据库加载/保存的 rcp 调用发生在 Worker isolate 内；isolate 每操作 terminate+重建时，Worker 内 session 无法跨操作复用。#3 落地前，公网 HTTPS 每操作 TLS 握手 100-300ms 的节省在 Worker 侧无法兑现（主线程已有复用） |
| 重连收益为可靠性 | 断网恢复后操作自愈（用户明确要求），价值无法用 ms 量化；实现无强依赖，但为保持回归聚焦排在 #3 之后 |
| 可独立先行 | 若断线自愈需求紧急，T1（NetworkRetry 组件）+ T2（WebDAV 接入）不依赖 #3，可提前交付 |

### 0.2 目标

1. Worker 侧 rcp Session 随常驻 isolate 跨操作复用（依赖 #3，零新代码），免每次 TCP+TLS 握手。
2. 四个云存储客户端（WebDAV/PCloud/华为云盘/S3）网络层异常时**自动重建会话并重试**，断网恢复后操作可自愈。
3. 全程可回滚：新增 `Constants.RETRY_NETWORK_ENABLED` 开关，false 时 NetworkRetry 直通。

### 0.3 非目标

- 不做断点续传（重试粒度 = 整请求；下载半截文件删除重下）。
- 不覆盖 axios 请求（华为元数据小 JSON）与 request.agent 旧接口（`uploadByFilePath`）。
- 不做多 Worker 并发池与 Worker 生命周期改造（属 #3，见《Worker常驻池化设计.md》）。
- 不改 KDBX 格式与既有错误码语义；不新增权限。

## 1. 现状与证据（已核实）

| 事实 | 位置 |
|---|---|
| Worker 内存储客户端每 isolate 重建 → `rcp.createSession` 每操作新建（TLS 重握手）；根因：Worker 每操作 terminate+重建（#3 解决，证据见其文档 §1） | `DatabaseLoad.ets:108`、`DatabaseSave.ets:87` → `FileStorageFactory`（isolate 级新单例）→ `WebDAVStorage.ets:38` |
| 主线程存储客户端已复用（isSameConfig 命中即不重建 session） | `WebDAVStorage.ets:31-44`、`FileStorageFactory.ets:24` |
| rcp 连接复用条件：同一 session + 同域名 + 网络未切换；session.close() 释放；单线程上限 1024（超限 1007900994） | 官方文档 remote-communication-pre-connect / faqs-remote-communication-5 |
| 网络层异常无重试：fetch 抛错直接映射失败；`connection()` 重连方法存在但 0 调用点 | `WebDavClient.ets:176-252,158-162`；`downloadToFile` 失败不清半截文件 `WebDavClient.ets:393-417` |
| rcp fetch 调用点分布 | WebDAV：`request:180`、`downloadToFile:402`；PCloud：140/212/253/364；华为：934（仅 UploadFromFile PATCH，其余 axios）；S3：14 处 `getSession()?.fetch` |

## 2. 方案总览

```
┌─ Worker isolate（常驻 —— 依赖 #3）─────────────────────┐
│ FileStorageFactory（isolate 级单例，随常驻 isolate 持久） │
│   └─ WebDAVStorage / PCloudClient / HuaweiDriveClient / S3Client
│        └─ rcp session 跨操作复用（isSameConfig 命中不重建）
│             └─ NetworkRetry.run(op, rebuildSession) 断线自愈
└─────────────────────────────────────────────────────────┘
┌─ 主线程（既有复用不变，同样获得重连收益）─────────────────┐
│ FileStorageFactory 单例 → 客户端 → session 已复用        │
│   └─ NetworkRetry.run 包装同一套客户端 fetch 调用        │
└─────────────────────────────────────────────────────────┘
```

- **回滚开关**（`Constants.ets` 追加，沿用双异步开关先例）：`RETRY_NETWORK_ENABLED = true`（false → NetworkRetry 直通 `op()`）。
- **与 #3 联动**：#3 落地 → Worker isolate 常驻 → Worker 内 `FileStorageFactory`/客户端实例持久 → `isSameConfig`（WebDAV 既有逻辑）命中即复用 session，本专项复用收益自动兑现。

## 3. 复用（依赖 #3，零新代码）

Worker isolate 常驻 → Worker 内 `FileStorageFactory` 单例持久 → `WebDAVStorage.isSameConfig` 命中 → 不再每操作 `rcp.createSession`。PCloud/S3/华为客户端实例同理随 isolate 持久。主线程既有复用不变。

## 4. 断线自动重连设计

### 4.1 NetworkRetry 公共组件

新建 `entry/src/main/ets/common/utils/NetworkRetry.ets`：

```ts
export class NetworkRetry {
  static readonly MAX_RETRIES: number = 1;      // 额外重试次数
  static readonly RETRY_DELAY_MS: number = 500; // 重建后退避

  /**
   * 网络层异常重试：op 抛错 → rebuild 会话 → 退避 → 重试一次；
   * 重试仍失败抛出**原始错误**（由既有 catch 映射错误码，语义不变）。
   * HTTP 4xx/5xx 是正常响应不是异常，天然不触发重试。
   * @param beforeAttempt 每次尝试前回调（下载前清理半截文件）
   */
  static async run<T>(op: () => Promise<T>, rebuild: () => void, label: string,
    beforeAttempt?: () => void): Promise<T>
}
```

关键判定：**rcp 仅在网络层失败时抛异常**，HTTP 状态错误以响应返回——因此"抛错即网络层故障"无需维护错误码表（已知 1007900028 超时、1007900994 session 上限均适用）。`RETRY_NETWORK_ENABLED=false` 时直通 `op()`。

### 4.2 WebDavClient 接入（核心）

| 请求面 | 现状 | 改造 |
|---|---|---|
| `request()`（GET/PUT/PROPFIND/DELETE/MKCOL…全走此） | `this.session?.fetch(req)`，抛错被本方法 catch 映射 500 | fetch 调用改为 `NetworkRetry.run(() => this.fetchWithSession(req), () => this.rebuildSession(), 'webdav')`；重试耗尽后异常仍落既有 catch，错误映射不变 |
| `downloadToFile()` | 直接 `session.downloadToFile`，失败留半截文件 | 同上包裹；`beforeAttempt` 中 best-effort unlink destPath（清理半截）；upload/uploadFromFile 经 `request()` 自动获得重试 |
| `rebuildSession()`（新增私有） | `connection()` 存在但 0 调用 | `connection()` 改为 close+静默重建（抽 `createSessionInternal()`，去掉重建路径的 showToast——Worker isolate 无 UI）；`updateOptions` 保持公开行为（失败 toast 仅此一处） |
| session 为 null | `?.fetch` 返回 undefined → 500 | `fetchWithSession` 内先重建一次，再失败抛错（语义更明确） |

**写路径安全性**：PUT 为 replace 语义，整文件重试幂等可接受；`WebDAVStorage.write/writeFromFile` 的 `checkVersionUnchanged` 写前复核在首次尝试前执行，重试 TOCTOU 窗口由完成后的 `getInfo` 采样与上层冲突检测兜底（与现状一致，不新增风险）。

### 4.3 其余客户端接入（WebDAV 之后顺序执行，模式统一）

| 客户端 | 接入点 | 方式 |
|---|---|---|
| `PCloudClient` | 4 处 `this.session.fetch`（140/212/253/364） | 新增私有 `fetchWithRetry(req)`（含 session null 重建）替换 |
| `HuaweiDriveClient` | 1 处 rcp（934 UploadFromFile PATCH；axios 小 JSON 不在范围） | 同上单点包裹 |
| `S3Client` | 14 处 `getSession()?.fetch(request)` | 新增 `fetchWithRetry(request)` 私有 helper 统一替换（multipart 分片自身已有短读重试，二者叠加安全） |

## 5. 文件清单

- 新建：`entry/src/main/ets/common/utils/NetworkRetry.ets`、`entry/src/ohosTest/ets/test/kdbx/NetworkRetry.test.ets`
- 修改：`Constants.ets`（`RETRY_NETWORK_ENABLED`）、`WebDavClient.ets`、`PCloudClient.ets`、`HuaweiDriveClient.ets`、`S3Client.ets`、ohosTest `List.test.ets`
- 不动：kdbxweb、存储接口层（`IFileStorage`）、axios 请求、request.agent 旧接口、Worker 生命周期（#3 范畴）、M0 协议

## 6. 实施任务分解（T1-T6）

> 每个任务独立可交付、可评审、带提交。#3 的任务见《Worker常驻池化设计.md》§5。

### Task 1：NetworkRetry 组件

**Files**：新建 `NetworkRetry.ets`、`NetworkRetry.test.ets`、`Constants.ets`（`RETRY_NETWORK_ENABLED`）、`List.test.ets`

- [ ] 实现 `run<T>(op, rebuild, label, beforeAttempt?)`（见 §4.1；含开关直通）
- [ ] 单测 5 例：首抛重试成功（rebuild 调用 1 次）/ 两次失败抛原始错误 / beforeAttempt 每次尝试前执行 / 开关关直通 / 退避间隔生效（计时）
- [ ] 构建 + commit `feat(net): 网络层断线重试组件`

### Task 2：WebDavClient 接入

**Files**：`WebDavClient.ets`

- [ ] 抽 `createSessionInternal()`；`connection()`/新增 `rebuildSession()` 静默重建；`updateOptions` 公开行为不变
- [ ] `request()` 与 `downloadToFile()` 的 rcp 调用包 `NetworkRetry.run`（downloadToFile 带 beforeAttempt 清理半截文件）；session null 先重建
- [ ] 单测不可行（依赖真服务）→ 真机：下载中断网（飞行模式开→关）→ 自动恢复或干净报错；4xx 不重试（错误码日志验证）
- [ ] 构建 + commit `feat(webdav): 断线自动重建会话并重试`

### Task 3-5：PCloud / 华为云盘 / S3 接入

各一任务：按 §4.3 表新增 `fetchWithRetry` 私有方法并替换列出的调用点（逐处一行 diff）；构建 + 既有存储套件回归；分别 commit `feat(pcloud|huawei|s3): 断线自动重试`。

### Task 6：验收与文档

- [ ] 全量存储 12 套件 + UI 2 套件真机回归；`hvigorw assembleHap` 最终构建
- [ ] 本设计文档状态改"已实施"，补实测数据（session 复用日志/重试命中记录）
- [ ] commit `docs: rcp 会话复用与断线重连验收记录`

## 7. 风险与对策

| 风险 | 对策 |
|---|---|
| PUT 重试重复上传 | replace 语义幂等；写前版本复核 + 完成后 getInfo 与上层冲突检测兜底（与现状一致） |
| rcp session 上限 1024（超限 1007900994） | #3 常驻后每 isolate session 数固定（1-2 个）；重连为 close+重建不累积，风险消除 |
| 重试放大弱网下的操作延迟 | MAX_RETRIES=1、退避 500ms，上限可控；`RETRY_NETWORK_ENABLED` 可关 |
| Worker isolate 无 UI，重建路径 toast 崩溃风险 | 重建统一走静默 `createSessionInternal()`；`updateOptions` 公开行为（toast）不变 |
| 下载重试残留半截文件 | beforeAttempt best-effort unlink；失败路径与现状一致干净报错 |

## 8. 验收标准

1. Worker 内 session 跨操作复用：同一 isolate 生命周期内 `createSession` 仅一次（依赖 #3 落地后验证）。
2. 断网→恢复后下一次 WebDAV 操作自动成功（重试日志命中）；4xx/5xx 不触发重试。
3. 全量回归：存储 12 套件 + UI 2 套件全绿；`RETRY_NETWORK_ENABLED` 可独立回滚。
4. 无新增权限、错误码语义不变、文件完整性不受重试影响（半截文件清理生效）。
