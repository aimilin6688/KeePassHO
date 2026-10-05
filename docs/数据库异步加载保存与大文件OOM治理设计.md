# 数据库异步加载、流式解析与大文件 OOM 治理设计

> 状态：设计评审稿 v3
> v1：异步开关 + 守卫 + 副本削减（治标：OOM→报错）
> v2：+ 附件磁盘化（解决附件常驻，但原始文件/解压/XML 仍整缓冲，几百 MB 库瞬时峰值仍 1GB 级）
> v3：**全链路分块文件管道**——存储 IO、解密、解压、附件、XML 解析/序列化全部流式化，内存峰值与文件大小解耦（本期完整方案）
> 关联：`KDBX跨线程数据传输优化设计-二进制快照协议.md`（KPSN，v3 中演化为会话文件协议）、`storage-regression-test.md`

## 0. 背景与问题定位

### 0.1 现状：全主线程 + 整缓冲链

- `Constants.ets:5,9` 双异步开关均为 false，`KdbxLoadService.ets:21-25` / `KdbxSaveService.ets:55-59` 始终走同步分支，全部重计算在主线程。
- 整条链路以 **ArrayBuffer 整缓冲**为载体：`IFileStorage.read` 整文件读入 → 整体解密 → `@ohos/flate2` 整缓冲 ungzip（Rust 绑定，无流式接口，`libs/kdbxweb/oh_modules/@ohos/flate2/libs/index.d.ts`）→ xmldom 整棵 DOM → 模型。
- 附件逐个整体 `slice` 拷入模型常驻至锁定（`binary-stream.ts:22-26`、`kdbx-binaries.ts:9` `KdbxBinary = ArrayBuffer`）。
- 保存反向再来一遍，且异步路径 KPSN 往返使附件三重驻留（`KdbxSaveService.ets:206` + Worker `loadSnapshot`）。

### 0.2 内存峰值量化（以文件大小 F、解压后大小 X 为基准）

| 场景 | 峰值/驻留 | 几百 MB 库的后果 |
|---|---|---|
| 加载（附件型，X≈F） | 瞬时 3-4×F + 常驻 1-1.5×F | 500MB 库 → 瞬时 1.5-2GB，**必 OOM** |
| 加载（文本型，X=5-10×F） | 瞬时 8-10×F | 100MB 库即 1GB 级，**必 OOM** |
| 保存/MERGE | 4-8×F | 同上 |
| v2 方案（附件落盘） | 瞬时 F+X、常驻 O(1) | 500MB 库 → 瞬时 ~1GB，**低端设备仍 OOM** |
| **v3 方案（全链路管道）** | **峰值 ≈ 常数（100-150MB），与 F 无关** | 可用 |

### 0.3 问题清单

| 编号 | 问题 | 定位 |
|---|---|---|
| P1 | 重计算在主线程，大库冻结 UI 数百 ms~秒级 | 全链路 |
| P2 | 大文件 OOM 闪退 | 整缓冲链 |
| P3 | 异步路径存在但从未启用验证 | `KdbxLoadService`/`KdbxSaveService` |
| P4 | 并发保存 terminate 半途 Worker → 非原子存储残缺文件 | `KdbxSaveService` |
| P5 | 解密多余副本（HMAC 3×、ChaCha20 输出副本） | `hmac-block-transform.ts:38+`、`chacha20.ts:80` |
| P6 | 附件全量常驻内存 | `kdbx-binaries.ts:9`、`binary-stream.ts:22-26` |
| P7 | 异步保存 KPSN 往返附件三重驻留 | `KdbxSaveService.ets:206` |
| **P8** | **云存储读取受系统 http 栈 100MB 上限**：`@ohos.net.http` 整缓冲请求 `maxLimit` 上限 100MB（FAQ faqs-network-64），`WebDAVStorage.read:87` 等整缓冲实现下，几百 MB 文件**直接报 2300023，与内存无关** | 7 种云存储 read 实现 |
| P9 | 几百 MB 库的下载/上传过程本身整文件驻留 | 同上 |

### 0.4 成熟 KeePass 库的实现参考

| 库 | XML 读取 | XML 写出 | 附件 | 加解密/压缩 IO | 可借鉴点 |
|---|---|---|---|---|---|
| **KeePass 2.x**（C#，官方） | `XmlReader` 拉取流式（无 DOM） | XmlDocument 内存 + 二进制**逐个流写** | 常驻内存（ProtectedBinary） | CryptoStream/GZipStream 连续流 | 拉取式 XML 解析思路；保存时附件不拼大缓冲 |
| **KeePassXC**（C++/Qt） | `QXmlStreamReader` 流式 | `QXmlStreamWriter` 流式 | 常驻内存 | QIODevice 管道：文件→流式解密→流式解压→解析器 | **管道架构蓝本**：本设计将其连续流适配为"临时文件分块管道"（flate2 无流式的落地形态） |
| **keeweb**（JS，本项目前身） | xmldom DOM 整缓冲 | DOM→字符串 | 常驻内存 | 全量 ArrayBuffer | 反例：即本项目问题根源，v3 刻意分道 |
| **结论** | 官方系解决了 DOM 放大与保存双缓冲，但**附件常驻各家均未解决** | | | | v3 的附件磁盘化 + 文件管道在参考实现之上再进一步 |

### 0.5 关键 API 事实（已核实）

| 事实 | 依据 |
|---|---|
| `@ohos.net.http` 流式下载：`requestInStream` + `on('dataReceive', (data: ArrayBuffer))` + `on('dataEnd')` | FAQ faqs-network-81 |
| http 整缓冲请求 maxLimit 上限 100MB，超过应使用 requestInStream | FAQ faqs-network-64 |
| `@ohos/flate2` 为 Rust 绑定，仅整缓冲 gzip/ungzip | `oh-package.json5`："ArkTS binding for rust flate2" |
| `@ohos.zlib`（ArkTS）为 zip 归档 compressFile/decompressFile，**不适用**单成员 gzip 载荷 | API 文档 js-apis-zlib |
| NDK sysroot 自带 zlib C API（inflate/deflate 流式） | API 文档「API参考/zlib」 |
| 项目已有原生依赖先例：`@ohos-rs/argon2`（kdbxweb/oh-package.json5:50）、libflate2.so | 原生模块链路已打通 |
| kdbxweb 支持 v3+v4：v3 附件为 XML 内 base64，v4 附件在 inner header | `kdbx-format.ts:40-42,52,66` |

## 1. 目标与非目标

**目标**
1. 异步化：重计算全部移入 Worker，主线程无长阻塞（继承 v2 Phase 1）。
2. **内存与文件大小解耦**：全链路分块文件管道，任意时刻内存只有 8-16MB 工作窗口 + 模型本身；几百 MB 附件型库峰值 RSS ≤ 150MB。
3. XML 解析/序列化分块流式：无 DOM、无整棵 XML 字符串；v3 格式 XML 内 base64 附件边解析边落盘。
4. 序列化/反序列化全程附件不整读：分块落盘、分块回读、分块上传/下载。
5. 超限场景（文本型模型超 RAM、磁盘不足、WebDAV 上限）一律明确报错，零闪退。

**非目标（如实声明）**
- 不改 KDBX 磁盘格式（与桌面 KeePass 互认不变）；KPSN 仅内部演化。
- **文本型超大库**（纯文本解压后数百 MB）本期不支持：模型必须整体驻 RAM 供 UI 遍历，这是 UI 架构的物理极限（桌面 KeePass 同样受制，只是桌面内存大）。CP2' 守卫兜底报错。
- WebDAV 等 HTTP 单请求上传 >100MB 受系统 http 栈限制（无流式上传 API），本期明确报错；rcps（Remote Communication Kit）流式上传列为调研项。
- 密码跨线程 JSON 形态不变。

## 2. 总体架构：分块文件管道

### 2.1 核心原则

1. **大对象只存在于磁盘**：阶段间传递临时文件，内存只有工作窗口（下载/解密 1-16MB、解析 256KB-1MB）。
2. **跨线程传路径不传缓冲**：Worker 协议从 ArrayBuffer transfer 演化为会话文件路径传递。
3. **明文落盘必加密**：所有承载明文的临时文件用会话密钥 ChaCha20 分块加密（密钥仅存内存）。
4. **每阶段独立可测**：管道各段为纯函数式 `file→file` 变换，配金标文件差分测试。

### 2.2 加载管道（反序列化）

```
[存储] ══8-16MB分块══▶ T0: raw.kdbx(密文)          ← requestInStream/Range GET/socket
T0 ──读头部64KB──▶ 头部字段 + argon2 派生(小)
T0 ══HMAC块逐块验证+就地解密(1MB块)══▶ T1: inner.gz(密文包裹*)
T1 ══NDK zlib流式inflate(1MB in/4MB out)══▶ T2: inner.bin(密文包裹*)
T2 ──inner header逐字段──▶ AS: 附件会话文件(密文包裹*) + AttachmentRef表
T2[XML区] ══拉取解析器(256KB块)══▶ 模型(RAM)  ← Worker内完成, 产出 M0 会话文件
Worker ──{M0路径, 引用表}──▶ 主线程: 拉取解析 M0 ══▶ 模型(RAM, 常驻O(文本量))
T0/T1/T2 删除; AS 保留至会话结束
```

*密文包裹：内容为明文的临时文件统一用会话密钥加密（§8）。

| 阶段 | 输入→输出 | 内存窗口 | 说明 |
|---|---|---|---|
| 下载 | 存储→T0 | 8-16MB | §3 适配矩阵 |
| 头部+KDF | T0 前 64KB | ~KB 级 | 不变 |
| 解密 | T0→T1 | ~4MB | §4 逐块 |
| 解压 | T1→T2 | ~8MB | §5 NDK zlib |
| 附件落盘 | T2→AS | 4MB | §6 |
| XML 解析 | T2[XML区]→模型 | 1MB + 模型 | §7 |
| 常驻 | 模型 + UI | 模型=O(文本量) | 与附件总量无关 |

### 2.3 保存管道（序列化）

```
主线程: 模型 ══XmlWriter流式产出(8MB刷新)══▶ X0: xml.bin(密文包裹*)
主线程 ──{X0路径, 引用表, AS路径, 凭证, 头部}──▶ Worker:
X0 + AS ══拼装inner流: 头部字段+附件4MB分块回读+X0追加══▶ X1: inner.bin(密文包裹*)
X1 ══NDK zlib流式deflate══▶ X2: inner.gz(密文包裹*)
X2 ══HMAC块+加密(1MB块)══▶ X3: saved.kdbx(标准KDBX密文, 不需包裹)
X3 ──▶ [存储]: Local=fs替换 / S3=既有multipart / FTP=socket流 / OneDrive=upload session / 其余≤100MB整缓冲PUT
X0/X1/X2 删除; 模型不动(MERGE见§7.5)
```

主线程仅剩 XmlWriter 模型遍历（O(条目数)，10k 条目 ≈ 数十 ms），v2 的"KPSN 主线程序列化热点"自然消失。

### 2.4 会话临时文件清单

| 文件 | 内容 | 大小 | 加密 | 生命周期 |
|---|---|---|---|---|
| T0 raw.kdbx | KDBX 原文 | F | 否（本身密文） | 加载完删 |
| T1 inner.gz | gz 明文 | ≈F | 会话密钥 | 解压完删 |
| T2 inner.bin | inner 明文 | ≈X | 会话密钥 | 解析完删 |
| AS attach.bin | 附件池明文 | ≈附件总量 | 会话密钥 | 会话（锁定/切换删） |
| M0 model.xml | 模型 XML（Worker→主线程） | ≈XML | 会话密钥 | 主线程解析完删 |
| X0/X1/X2 | 保存中间态 | ≈XML / X / F | 会话密钥 | 保存完删 |
| X3 saved.kdbx | 成品 KDBX | F | 否 | 上传完删 |

全部位于 `filesDir/session-<id>/`（不用 cacheDir：系统低空间回收可能打断进行中的会话；清扫责任由应用承担，§8）。

## 3. 流式存储 IO 层

### 3.1 IFileStorage 接口扩展

```
readToFile(path: string, destPath: string, progress?): Promise<FileInfo>   // 分块下载/复制
writeFromFile(path: string, srcPath: string): Promise<FileInfo>            // 分块上传/复制
```

基类默认实现包装现有 `read()/write()`（整缓冲），适配器逐个迁移；迁移完成后 `read()` 保留给小文件（设置导入等场景）。

### 3.2 适配矩阵（修 P8/P9）

| 存储 | readToFile | writeFromFile | 备注 |
|---|---|---|---|
| Local | fs copy（分块） | fs 写临时+rename 原子替换 | 顺带修复非原子写 |
| WebDAV | `requestInStream` + `dataReceive` 分块追加 | PUT 整缓冲，**≤100MB**（http maxLimit 硬限）；超限报 `storage_upload_too_large` | rcps 流式上传调研项 |
| S3 | Range GET 循环（8MB 段） | 既有 multipart upload | 已具备 |
| FTP | socket 分块读 | socket 分块写 | 已具备 |
| OneDrive | requestInStream | Graph **upload session**（createSession + 5-10MB 分片 PUT） | 需新增 |
| pCloud | 分块下载（API 调研：getfilelink+Range 或流式接口） | upload_write 分块（API 调研） | 调研项，先走默认整缓冲 |
| 华为云盘 | Range GET | 断点续传上传（API 调研） | 调研项，先走默认整缓冲 |

### 3.3 流式冲突检测

保存前远端 `readToFile` → **cryptoFramework 增量 sha256**（Md.update 分块喂入，替代整缓冲哈希）+ 既有 `FileInfo.version`（ETag）比对不变。MERGE 触发逻辑与重试（`MAX_CONFLICT_RETRY=3`）不变。

## 4. 流式解密/加密管道（kdbxweb，修 P5）

- T0→T1：按 HMAC block（默认 1MB/块）循环：`fs.read` 块 → 块 HMAC 验证 → ChaCha20/AES **就地解密** → 会话密钥包裹 → `fs.write` 追加。窗口 = 2×块 + 包裹缓冲 ≈ 4MB。
- X2→X3 反向：逐块加密 + HMAC 签名追加。
- `chacha20.ts` 新增 `encryptInPlace`；`hmac-block-transform.ts` 增加分块文件版（原整缓冲接口保留供小文件内联模式）。
- argon2/KDF 不变（输入输出均为小定长）。

## 5. 流式压缩：NDK zlib 原生模块（关键依赖）

- flate2 整缓冲、`@ohos.zlib` 仅 zip 归档（§0.5），均不可用；**NDK sysroot zlib C API** 提供 `inflateInit/inflate/deflateInit/deflate` 流式原语。
- 新增原生模块（项目已有 @ohos-rs/argon2、libflate2.so 先例，工具链现成），暴露两个 napi 接口：
  - `inflateFile(inPath, outPath, opts, onProgress): Promise<void>` — 1MB in / 4MB out 窗口，gzip 单成员模式
  - `deflateFile(inPath, outPath, opts): Promise<void>` — 同参反向
- 与会话密钥包裹合并为同遍处理（read chunk → inflate → chacha → write），避免中间文件二次读写的性能税（可选优化，接口预留 `cipherKey` 参数）。
- **备选方案**（原生模块受阻时）：纯 TS pako 流式移植进 kdbxweb（无原生依赖，速度慢 2-5×，Worker 内 500MB ≈ 5-10s，可接受但非首选）。

## 6. 附件磁盘化（继承 v2，窗口化改造，修 P6/P7）

- `AttachmentRef { id, hash, offset, length, protected, source: 'disk'|'memory' }`；`KdbxBinaries` 值类型切换为 ref，对外收敛 `readBinary(id): Promise<ArrayBuffer>`。
- **加载**：inner header 逐 Binary 字段 4MB 分块 T2→AS（窗口内完成 base64 无关的字节搬运）；会话附件总量 < 16MB 收尾读回内联并删 AS（小库零行为差异）。
- **v3 格式兼容**（用户明确要求）：v3 数据库附件是 XML 内 `<Binary>` base64 文本 → 拉取解析器（§7.2）遇 Binary 元素时**增量 base64 解码直接分块写 AS**，全程不 materialize 整个附件字符串。
- **保存**：X1 拼装时按 ref 从 AS 4MB 分块回读；删除的附件不回读（pool 按存活 ref 重建，hash 去重语义不变）。
- **运行时**：`AttachmentStore.read(ref)` 按区间分块读 + 解密；首版不做内存 LRU（附件预览低频）。UI 消费点 3 处适配（`EntryEdit.ets:60,241`、`EntryView.ets`、`KdbxUtils.ets`）。
- **新增附件**（EntryEdit 选文件）：即写 AS 再建 ref，大附件不进内存常驻。

## 7. 流式 XML 解析与序列化（修 DOM 放大，用户核心诉求）

### 7.1 为什么必须弃用 DOM

xmldom 路径 = 整棵 XML 字符串 X（UTF-16 双倍）+ DOM 节点 2-5×X + 模型，是文本型 8-10×F 放化的元凶；DOM 亦无法从文件增量喂数据。KeePass 2.x 读取侧早已用 XmlReader 拉取模型，KeePassXC 双向 QXmlStream——本项目对齐官方做法。

### 7.2 流式拉取解析器（Pull Parser，反序列化）

- KDBX XML schema 固定且浅层（Meta/Group/Entry/Times/CustomData…）→ **手写状态机解析器**（~600-900 行，对齐 KeePass XmlReader 思路），非通用 SAX 库移植。
- 输入：`FileChunkReader`（T2 XML 区 / M0，256KB-1MB 块，跨块标签/实体缓冲拼接）。
- 输出：直接构建模型对象，事件式（startElement/endElement/text），无中间节点树。
- **ProtectedValue**：内流（ChaCha20/Salsa20）按需产 key stream，文本块边解边 XOR（密钥流状态跨块保持）。
- **v3 Binary**：base64 增量解码 → 分块写 AS（§6）。
- **进度回调**：按已解析字节上报加载进度（替代当前粗粒度 loading 文案）。
- RSS = 模型 + 1MB 窗口。
- **风险控制**：`STREAMING_XML_PARSE` 开关；差分测试（既有全部测试库 × DOM 路径 vs 流式路径，模型 JSON 深比对）一个里程碑全绿后，DOM 读取路径退役。

### 7.3 流式 XML 写出器（XmlWriter，序列化）

- 遍历模型直接产出 UTF-8 字节流 → 会话包裹 → X0 文件（8MB 刷新缓冲），消除"DOM 构建 + 字符串序列化"双份峰值。
- ProtectedValue 边写边 XOR 内流；v3 格式附件反向：从 AS 分块读 → 增量 base64 编码直写（v4 不经过 XML）。
- 输出与 KeePass 2.x 产物做 XML 规范化差分（属性顺序/空白对齐既有 saveV4 语义）。

### 7.4 跨线程协议：KPSN 内存协议 → 会话文件协议（修 P7 残留）

- **加载**：Worker 完成存储→T0→T1→T2→AS→**XML 预解析**，把模型 XML + 引用表写为 M0（会话包裹）；向主线程 post `{M0 路径, AS 路径, 引用表}`；主线程拉取解析 M0 → 模型。**大缓冲不再跨线程**，文本型大库的跨线程传输也不再吃内存。
- **保存**：主线程 XmlWriter → X0；post `{X0 路径, 引用表, AS 路径, 凭证}`；Worker 完成拼装→压缩→加密→上传。
- KPSN ArrayBuffer 协议退役；`KdbxSnapshotTest` 迁移为会话文件协议往返测试。

### 7.5 MERGE

远端 readToFile → 走完整加载管道（Worker 内产出远端 M0' + AS'）→ Worker 内解析两个模型执行 merge（文本型时 Worker 内短暂 2×模型，受 CP2' 约束；附件型仅引用表合并，零字节拷贝）→ merged X0 → 正常保存管道 → 通知主线程按 M0 重新装载。

## 8. 临时文件安全与生命周期

- **会话密钥**：32B 随机，仅内存，随进程消亡；T1/T2/AS/M0/X0/X1/X2 统一 ChaCha20 分块包裹（纯 TS ~50-100MB/s，Worker 内可接受；§5 预留原生同遍加速）。进程被杀后所有会话文件为不可解密废数据。
- **目录**：`filesDir/session-<id>/`（避开 cacheDir 系统回收窗口）；T0/X3 为 KDBX 密文不包裹。
- **清理**：锁定 / 切换库 / 加载失败 / 保存完成 即时删除；启动清扫 `session-*` 超过 24h 的目录（沿用 `CacheConstants.ets:113-125` 模式）；`EntryAbility onDestroy` 全清。
- **残余风险如实声明**：闪存删除 ≠ 安全擦除（wear-leveling），密文包裹将该风险降为"需要同时攻破内存密钥"；与桌面版纯内存模型相比这是为能力（几百 MB 库）付出的边界扩展，文档与设置页说明。

## 9. 守卫与限制（更新 v2 的 CP1/CP2）

| 守卫 | 检查点 | 规则 | 报错 |
|---|---|---|---|
| CP1 文件大小 | 读取前（`getInfo().size`，`IFileStorage.ets:86`） | > `MAX_DATABASE_SIZE`（默认 **512MB**，v3 上调：约束已从内存转为磁盘/时间） | `database_too_large` |
| **CP-DISK 磁盘**（新增） | 管道启动前 | filesDir 剩余空间 < **4×F + 附件池** | `database_not_enough_disk` |
| **CP2' 模型**（替代 CP2） | inflate 后（可由 gzip 尾部 ISIZE 预判）+ 解析中累计文本量复核 | `X × 1.3 > appMemory × 0.55`（`appManager.getAppMemorySize()`） | `database_decompressed_too_large` |
| CP-UP 上传上限 | WebDAV 等整缓冲上传前 | F > 100MB（http maxLimit 硬限） | `storage_upload_too_large`（文案引导换 S3/OneDrive/本地） |
| 保存互斥 | `KdbxSaveService` 入口 | Promise 链串行（修 P4） | 排队 |

文本型超大库不支持的表达即 CP2'：模型必须驻 RAM 是 UI 架构物理极限（§1 非目标）。

## 10. 内存预算与验收

**目标场景：500MB 附件型库（附件 480MB / XML 3MB / 10k 条目）**

| 阶段 | v1 现状 | v3 目标 |
|---|---|---|
| 下载 | 500MB 驻留（且 WebDAV 直接 2300023 报错） | 窗口 16MB |
| 解密+解压 | 1-1.5GB 瞬时 | 窗口 ≤ 12MB |
| XML+附件 | +1GB 级 | 窗口 ≤ 5MB |
| 常驻 | 600MB+ | **模型 ~15MB（O(文本量)，与附件无关）** |
| **全程峰值 RSS** | **~2GB（必 OOM）** | **≤ 150MB（UI+模型+窗口），与 F 无关** |
| 磁盘占用峰值 | 0 | ~4×F（2GB，CP-DISK 守卫） |

**测试矩阵**：att-100 / att-300 / att-500（附件型）；text-1k / text-10k（文本型回归）；text-huge-300（CP2' 拒绝路径，零闪退）；WebDAV 200MB 上传（CP-UP 报错路径）；断电/杀进程残留清扫。采样：hdc 侧 `hidumper` 200ms 间隔采样脚本 + Worker 阶段打点，报告归档 `docs/`。

**互操作**：att-500 保存产物由桌面 KeePass 2.x 与 KeePassXC 双向打开验证（磁盘格式未变）。

## 11. 实施阶段（每步独立可交付、可回归）

| 阶段 | 内容 | 修 | 预估 |
|---|---|---|---|
| S1 | 异步开关 + 保存互斥 + 弹框兜底验证 + 打点 | P1,P3,P4 | 0.5-1 天 |
| S2 | CP1/CP2'/CP-DISK/CP-UP 守卫 + 错误码文案 + 设置项 | P2 安全网 | 1 天 |
| S3 | `IFileStorage.readToFile/writeFromFile` + Local/WebDAV 下载/S3/FTP 适配 + 流式 sha256 冲突检测 | P8,P9 | 2-3 天 |
| S4 | 流式解密管道（HMAC 块文件版 + in-place）+ 附件落盘（AttachmentRef/Store/双模式）+ UI 三处适配 | P5,P6 | 2-3 天 |
| S5 | NDK zlib 流式 inflate/deflate 模块（含备选 pako 评估）+ 会话包裹 | X 窗口 | 2-3 天 |
| S6 | 流式拉取解析器 + XmlWriter + 差分测试开关 + 会话文件协议（KPSN 退役） | P2 主力,P7 | 3-4 天 |
| S7 | OneDrive upload session + pCloud/华为云盘调研 + 临时文件生命周期/清扫 + 大文件验收报告 | 收尾 | 1.5-2 天 |

合计 **12-17 天**。依赖关系：S4/S5 可并行；S6 依赖 S5（从文件流解析）；每阶段结束跑存储 12 套件 + UI 2 套件 + 该阶段专项用例。

### 11.1 S1 落地补充：Worker 环境注入机制（2026-10-05 实施时发现并落地）

异步开关启用后暴露的前置事实：**Actor 模型下 Worker 线程没有 Context、AppStorage、preferences**（跨 isolate 静态不共享），远程存储读取链路（CacheStorage 装饰器 → `getApplicationContext()`、FTPClient(context)、`AppStorage` 标志）在 Worker 内全部 NPE。落地机制：

- **注入协议**：`DatabaseWorkerFactory` 创建 Worker 后立即投递 `INIT_WORKER` 消息（filesDir/cacheDir 路径字符串 + 缓存策略快照），FIFO 保证先于任务消息；两个 Worker 壳（加载/保存）处理 INIT 后才受理任务。
- **路径助手**：`CommonUtils.setWorkerPaths / getAppFilesDir / getCacheDir / getStorageContext`——主线程取自 Context，Worker 取注入值；`StorageContextStub`（仅含 cacheDir）供 basic-ftp 的 FTPClient 等鸭式类型库在 Worker 内使用。
- **缓存策略快照**：`enableLocalCache/onlyUseCache` 由主线程在**每次创建 Worker 时**快照注入（Worker 每操作重建，快照≈实时值）；`forceRefresh` 为主线程一次性标志，在创建点消费并随快照传入，避免 Worker 无法回写 AppStorage 导致标志粘连；`CacheConstants` 全部 AppStorage 访问 try/catch 回退。
- **验证**：StorageConflictUiTest（SFTP/WebDAV/S3 加载保存全链路 Worker 化）15/15 全绿；非 UI 全量 447/447。

该机制是 S3+ 流式管道的前置基础设施（Worker 侧文件 IO 同样依赖注入路径），后续阶段不得绕过 `CommonUtils` 路径助手直接访问 Context。

## 12. 验收标准汇总

1. **功能**：存储回归 12 套件 + UI 2 套件全绿；小库（<16MB 附件）行为与现状一致；KDBX 磁盘格式不变（桌面互认）；双开关 + `STREAMING_XML_PARSE` 可回滚。
2. **内存（核心指标）**：att-500 加载/保存全程峰值 RSS ≤ 150MB，且加载完成 30s 后 RSS 增量 ≤ 50MB；att-100/text-10k 同样与 F 解耦。
3. **稳定性**：全程无 AppFreeze/JsError；所有超限路径（CP1/CP2'/CP-DISK/CP-UP）明确报错零闪退；并发保存/保存中锁定解锁无异常。
4. **XML 流式**：流式与 DOM 路径差分测试全绿后 DOM 读取退役；v3 格式（base64 附件）大库可加载。
5. **安全**：会话目录外无明文落盘；锁定/切换/退出后 `session-*` 零残留；杀进程残留下次启动完成清扫且不可解密。
6. **可观测**：各管道阶段字节数/耗时/窗口占用 hilog 打点齐全，验收数据归档。
