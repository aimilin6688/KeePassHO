# Worker 常驻池化设计（性能优化 #3）

> 状态：评审中 v1（2026-10-08）
> 优先级：**P0 —— 两项优化中先开发**（理由见 §0.1）
> 关联：《数据库异步加载保存与大文件OOM治理设计.md》（§2.2 加载管道 / §11.1 Worker 环境注入 / S3 存储流式化）、《rcp会话复用与断线自动重连设计.md》（#4，其复用收益依赖本文档落地）
> 优化编号承接《性能优化盘点》：#3 Worker 池化
> 拆分自原合并版《Worker常驻池化与rcp会话复用设计》（v1 2026-10-07），拆分后原文档废弃

## 0. 目标与非目标

### 0.1 优先级理由（为何 #3 先于 #4 开发）

| 维度 | 说明 |
|---|---|
| 收益确定性最高 | 每次加载/保存都省 isolate 冷启动（模块图加载 + INIT 注入，粗估 50-200ms）：打开库、自动保存、MERGE 全路径受益，不依赖网络条件 |
| 是 #4 收益的前提 | 数据库加载/保存的 rcp 调用发生在 Worker isolate 内，isolate 每操作重建则 session 无法跨操作复用（公网 HTTPS 每操作 TLS 握手 100-300ms 的节省无法兑现）。#3 落地后 #4 复用部分**零新代码自动生效** |
| 改动面小、风险低 | 集中在 2 个服务 + 1 个页面 + 2 个 Worker 壳 + 消息协议/工厂，无网络协议改动 |
| 顺带修复两个既有隐患 | 双击打开"kill 重来"（改为拒绝语义）；forceRefresh 一次性语义在常驻模式下的粘连 |

### 0.2 目标

1. 加载/保存 Worker 由"每操作 terminate + 重建"改为**进程级常驻复用**，消除每次操作的 isolate 冷启动。
2. 缓存策略快照随任务消息注入，修复 forceRefresh 一次性语义在常驻模式下的粘连。
3. Worker 壳任务串行（taskChain），防常驻后消息交错。
4. 全程可回滚：新增 `Constants.POOL_DATABASE_WORKER` 开关，false 时完整恢复旧行为。

### 0.3 非目标

- 不做多 Worker 并发池（加载/保存各自单常驻 Worker，加载/保存之间仍并行）。
- 不做 rcp 会话复用与断线自动重连（属 #4，见《rcp会话复用与断线自动重连设计.md》）。
- 不改 KDBX 格式与既有错误码语义；不新增权限。

## 1. 现状与证据（已核实）

| 事实 | 位置 |
|---|---|
| 每次加载 terminate 旧 Worker → 新建 | `KdbxLoadService.ets:34-37`（`stopWorker()` + `createLoadWorker()`） |
| 每次保存 terminate 旧 Worker → 新建 | `KdbxSaveService.ets:223-231,254` |
| INIT_WORKER 携带**一次性** forceRefresh 与缓存策略快照 | `DatabaseWorkerFactory.ets:36-49`、`DatabaseLoadWorker.ets:22-31`、`DatabaseSaveWorker.ets:22-31` |
| `onexit` 唯一业务消费点：关 loading 弹框兜底 | `Password.ets:552`（success/error/onAllErrors 三路径均已自行关框） |
| `Password.aboutToDisappear` 调 `stopWorker()`（解锁跳转后即销毁刚建好的 Worker） | `Password.ets:167` |
| 保存互斥链（Promise 串行）已保证保存单飞 | `KdbxSaveService.ets:29-33,59-83` |
| Worker 消息壳按 FIFO 处理，但任务未 await 串联（复用后需防并发任务交错） | `DatabaseLoadWorker.ets:18-38`、`DatabaseSaveWorker.ets:18-38` |
| Worker 内存储客户端每 isolate 重建（= #4 session 复用失效的根因） | 证据见《rcp会话复用与断线自动重连设计.md》§1 |

## 2. 方案总览

```
┌─ 主线程 ─────────────────────────────────────────────┐
│ KdbxLoadService ──┐                                   │
│  （busy 拒绝）     ├─ PersistentWorker 复用（常驻 isolate）│
│ KdbxSaveService ──┘   ├─ INIT_WORKER 仅一次（路径/密钥）  │
│  （saveLock 串行）     ├─ 每任务：attachCachePolicy 附带策略 │
│                       └─ Worker 壳：taskChain 串行防交错   │
└──────────────────────────────────────────────────────┘
```

- **回滚开关**（`Constants.ets` 追加，沿用双异步开关先例）：`POOL_DATABASE_WORKER = true`（false → 恢复每操作 terminate+重建）。
- **与 #4 联动**：isolate 常驻后 Worker 内 `FileStorageFactory`/存储客户端实例持久 → `isSameConfig` 命中即复用 rcp session，#4 的复用收益自动兑现（详见 #4 文档）。

## 3. 详细设计

### 3.1 生命周期

| 事件 | 行为 |
|---|---|
| 首次加载/保存 | 懒创建 Worker → INIT_WORKER（路径、附件密钥、会话密钥/目录 —— 均进程级稳定，仅注入一次） |
| 后续每次操作 | 复用现有 Worker；任务消息附带缓存策略快照（见 3.2）；重新绑定 onmessage 回调（单飞语义不变） |
| 任务终态（SUCCESS/ERROR/CONFLICT） | 主线程置 idle，Worker 保留 |
| Worker 异常（onAllErrors / 非预期 onexit） | 主线程置 `databaseWorker = null` + idle → 下次操作重建（崩溃自愈）；在途回调照常收 onAllErrors/onexit |
| 显式 `stopWorker()` | API 保留（单测/紧急清理用）；不再被业务例行调用 |
| 进程退出 | isolate 随进程消亡（无需额外清理） |

**忙判定**：
- 加载：`workerBusy` 标志，忙时**立即拒绝**（onErrorMessage 回 `worker_busy` 资源名，新增 i18n），不排队——避免双击"打开"导致两次成功导航（旧行为是 kill 重来，池化后 kill 不复存在，拒绝语义更安全）。
- 保存：saveLock 互斥链已天然串行，无需新标志。

### 3.2 缓存策略随任务注入（修 forceRefresh 一次性语义）

INIT 的策略快照在常驻模式下会过期（用户中途改设置、forceRefresh 一次性标志）。方案：**策略 volatile 部分随任务消息走**，路径/密钥保持 INIT 一次。

- 新增接口 `CachePolicyCarrier`（`WorkerParam.ets`）：`enableLocalCache?/onlyUseCache?/forceRefresh?: boolean`；`LoadDatabase`、`SaveDatabaseMessage` 实现之（可选字段，旧消息不受影响）。
- `DatabaseWorkerFactory.attachCachePolicy(msg)`：主线程读取 `CacheConstants` 并**就地消费 forceRefresh**（读+clear），写入 msg 三字段；服务层在 postMessage 前调用。
- Worker 壳：收到 LOAD_DATABASE/SAVE_DATABASE 时，若三字段非 undefined → `CacheConstants.setWorkerCachePolicy(...)` 覆盖 INIT 快照，再执行任务。

### 3.3 Worker 壳防交错

常驻后消息 FIFO 不再被"每次重建"隔断，两个任务消息可能先后到达同一 isolate。壳内加 `taskChain: Promise<void>` 串联任务（`.then(() => handler(req)).catch(log)`），与主线程 busy/saveLock 双保险。旧格式消息（测试直接构造、无策略字段）行为不变。

### 3.4 调用点变更清单

| 位置 | 变更 |
|---|---|
| `KdbxLoadService.ets` | `asyncLoadDatabase` 去 `stopWorker()`；`databaseWorker === null` 才创建；busy 拒绝；SUCCESS/ERROR 释放 busy；onAllErrors/onexit 置空 Worker+释放 busy；`POOL_DATABASE_WORKER=false` 时保留旧行为（先 stopWorker 再创建） |
| `KdbxSaveService.ets` | `saveDatabaseAsync` 删除 terminate 块（223-231）；`saveDatabaseWorker` 仅在 `null` 时创建；attachCachePolicy；onAllErrors 置空 Worker；开关 false 时保留旧行为 |
| `Password.ets:167` | 删除 `aboutToDisappear` 中的 `KdbxLoadService.stopWorker()`（否则解锁跳转即杀掉常驻 Worker，池化失效）；loading 弹框关闭不依赖 onexit（三终态路径已覆盖） |
| `Constants.ets` | 新增 `POOL_DATABASE_WORKER = true` |
| 资源 | `worker_busy`：base "A database operation is in progress, please try again later" / zh_CN "数据库操作进行中，请稍后再试" |

**内存代价（如实声明）**：两个常驻 isolate（模块图 + 基线堆，估 20-40MB）常驻；换取每操作省冷启动。

## 4. 文件清单

- 新建：`entry/src/ohosTest/ets/test/workers/WorkerPoolPolicy.test.ets`
- 修改：`Constants.ets`、`WorkerParam.ets`、`DatabaseLoadWorkerParam.ets`、`DatabaseSaveWorkerParam.ets`、`DatabaseWorkerFactory.ets`、`KdbxLoadService.ets`、`KdbxSaveService.ets`、`Password.ets`、`DatabaseLoadWorker.ets`、`DatabaseSaveWorker.ets`、`resources/base/element/string.json`、`resources/zh_CN/element/string.json`、ohosTest `List.test.ets`
- 不动：kdbxweb、存储接口层（`IFileStorage`）、存储客户端网络层（#4 范畴）、临时文件清扫、M0 协议

## 5. 实施任务分解（T1-T5）

> 每个任务独立可交付、可评审、带提交。#4 的任务见《rcp会话复用与断线自动重连设计.md》§6。

### Task 1：缓存策略随任务注入（协议 + 工厂）

**Files**：`WorkerParam.ets`、`DatabaseLoadWorkerParam.ets`、`DatabaseSaveWorkerParam.ets`、`DatabaseWorkerFactory.ets`、新建 `WorkerPoolPolicy.test.ets`

- [ ] 新增 `CachePolicyCarrier` 接口与三可选字段；`LoadDatabase`/`SaveDatabaseMessage` 实现
- [ ] `DatabaseWorkerFactory.attachCachePolicy(msg: CachePolicyCarrier): void`（读策略 + 消费 forceRefresh）
- [ ] 单测：三字段正确写入；`setForceRefresh(true)` 后 attach 一次即被消费（getForceRefresh 复为 false）；未设置时不影响旧消息
- [ ] `hvigorw assembleHap` 通过 → commit `feat(worker): 缓存策略快照随任务消息注入`

### Task 2：Worker 壳串行 + 每任务策略生效

**Files**：`DatabaseLoadWorker.ets`、`DatabaseSaveWorker.ets`

- [ ] 两壳加模块级 `taskChain` 串联任务；LOAD/SAVE 分支先按消息字段（非 undefined 时）`CacheConstants.setWorkerCachePolicy(...)` 再执行
- [ ] 单测：构造带策略的 LoadDatabase 经 JSON 序列化往返后字段保留（JSON 通道兼容性）
- [ ] 构建 + 既有 DatabaseWorkerMode.test 回归 → commit `feat(worker): 常驻壳任务串行与每任务缓存策略`

### Task 3：加载服务池化

**Files**：`KdbxLoadService.ets`、`Password.ets`、`Constants.ets`、`string.json`(base/zh_CN)

- [ ] `Constants` 增 `POOL_DATABASE_WORKER = true`
- [ ] `asyncLoadDatabase`：busy 拒绝（`worker_busy`）→ `POOL_DATABASE_WORKER=false` 时保留旧行为 → 复用/懒建 → attachCachePolicy → 终态释放 busy → onAllErrors/onexit 置空 Worker
- [ ] 删除 `Password.ets:167` 的 `stopWorker()` 调用；新增 `worker_busy` i18n
- [ ] 构建 → commit `feat(worker): 加载 Worker 常驻复用`

### Task 4：保存服务池化

**Files**：`KdbxSaveService.ets`

- [ ] 删 terminate 块；null 才创建；attachCachePolicy；onAllErrors 置空；开关回退路径
- [ ] 构建 + StorageConflictUiTest 15/15 回归 → commit `feat(worker): 保存 Worker 常驻复用`

### Task 5：真机验证

- [ ] 连续两次加载：hilog 第二次无 "worker terminated"/冷启动 axios 日志，总时长下降
- [ ] 双击打开：第二次 toast `worker_busy`，无重复导航
- [ ] 锁定→再解锁（跨库切换）：复用 Worker 成功
- [ ] commit（如有修正）`fix(worker): 池化真机问题修正`

## 6. 风险与对策

| 风险 | 对策 |
|---|---|
| 常驻 isolate 内存上涨 20-40MB | 如实声明；开关可关；后续可加锁定时 stopWorker（本期不做） |
| forceRefresh 粘连（快照过期） | 策略随任务注入（§3.2），单测覆盖消费一次语义 |
| 双击打开两次成功导航 | busy 立即拒绝，行为从"kill 重来"变为"拒绝"，无重复导航 |
| Worker 崩溃后在途任务无响应 | onAllErrors/onexit 同时置空 Worker + 释放 busy + 既有回调报错 |
| onexit 不再触发导致依赖方异常 | 唯一消费点 Password 仅作兜底关框，三终态路径已覆盖；删除 Password 例行 stopWorker |

## 7. 验收标准

1. 第二次起加载/保存不再出现 Worker 冷启动（hilog 无 "worker terminated"/重建痕迹），实测每次操作节省 ≥50ms。
2. 双击"打开"：第二次 toast `worker_busy`，无重复导航。
3. 锁定→再解锁（跨库切换）复用 Worker 成功；Worker 异常后下次操作自动重建（自愈）。
4. 回归：DatabaseWorkerMode、StorageConflictUiTest 15/15 全绿；`POOL_DATABASE_WORKER=false` 完整回退旧行为。
5. 无新增权限、无 KDBX 格式改动、错误码语义不变（`worker_busy` 为唯一新增用户可见文案）。
