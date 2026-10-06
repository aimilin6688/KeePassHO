# 数据库异步加载、流式解析与大文件 OOM 治理设计

> 状态：实施中 v5（S1-S5 已落地，S6 保存管道流式已落地（XmlWriter/拉取解析器/KPSN 退役未实施），S7 部分落地（S7-b 清扫 + S7-a OneDrive session 完成），详见 §11.2 实施状态追踪）
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

| 阶段 | 内容 | 修 | 预估 | 状态（2026-10-06 核对） |
|---|---|---|---|---|
| S1 | 异步开关 + 保存互斥 + 弹框兜底验证 + 打点 | P1,P3,P4 | 0.5-1 天 | ✅ 已实现（含 §11.1 Worker 环境注入） |
| S2 | CP1/CP2'/CP-DISK/CP-UP 守卫 + 错误码文案 + 设置项 | P2 安全网 | 1 天 | ✅ 已实现（偏差见 §11.2） |
| S3 | `IFileStorage.readToFile/writeFromFile` + Local/WebDAV 下载/S3/FTP 适配 + 流式 sha256 冲突检测 | P8,P9 | 2-3 天 | ✅ 存储侧完成（读写双向流化：S3 上传改文件分片 multipart + etag 条件写入；剩 WebDAV 上传/OneDrive/pCloud/华为云盘归 S7，保存链路 writeFromFile 接线归 S6） |
| S4 | 流式解密管道（HMAC 块文件版 + in-place）+ 附件落盘（AttachmentRef/Store/双模式）+ UI 三处适配 | P5,P6 | 2-3 天 | ✅ 基本实现（saveV4 加密侧仍整缓冲，encryptFromFile 未接线；EntryEdit 新增附件仍入内存） |
| S5 | NDK zlib 流式 inflate/deflate 模块（含备选 pako 评估）+ 会话包裹 | X 窗口 | 2-3 天 | ✅ 已实现（NDK 原生模块 + T0/T1/T2 加载侧全链路接线 + 6 用例；deflate 保存侧接线随 S6） |
| S6 | 流式拉取解析器 + XmlWriter + 差分测试开关 + 会话文件协议（KPSN 退役） | P2 主力,P7 | 3-4 天 | 🔄 部分实现（保存管道流式已落地：saveToFile+writeFromFile+encryptFromFile+deflateFile 接线；拉取解析器/XmlWriter/KPSN 退役未实施） |
| S7 | OneDrive upload session + pCloud/华为云盘调研 + 临时文件生命周期/清扫 + 大文件验收报告 | 收尾 | 1.5-2 天 | 🔄 部分实现（S7-b 临时文件清扫 + S7-a OneDrive upload session 已落地；剩 pCloud/华为云盘流式调研 + 验收报告） |

合计 **12-17 天**。依赖关系：S4/S5 可并行；S6 依赖 S5（从文件流解析）；每阶段结束跑存储 12 套件 + UI 2 套件 + 该阶段专项用例。

### 11.1 S1 落地补充：Worker 环境注入机制（2026-10-05 实施时发现并落地）

异步开关启用后暴露的前置事实：**Actor 模型下 Worker 线程没有 Context、AppStorage、preferences**（跨 isolate 静态不共享），远程存储读取链路（CacheStorage 装饰器 → `getApplicationContext()`、FTPClient(context)、`AppStorage` 标志）在 Worker 内全部 NPE。落地机制：

- **注入协议**：`DatabaseWorkerFactory` 创建 Worker 后立即投递 `INIT_WORKER` 消息（filesDir/cacheDir 路径字符串 + 缓存策略快照），FIFO 保证先于任务消息；两个 Worker 壳（加载/保存）处理 INIT 后才受理任务。
- **路径助手**：`CommonUtils.setWorkerPaths / getAppFilesDir / getCacheDir / getStorageContext`——主线程取自 Context，Worker 取注入值；`StorageContextStub`（仅含 cacheDir）供 basic-ftp 的 FTPClient 等鸭式类型库在 Worker 内使用。
- **缓存策略快照**：`enableLocalCache/onlyUseCache` 由主线程在**每次创建 Worker 时**快照注入（Worker 每操作重建，快照≈实时值）；`forceRefresh` 为主线程一次性标志，在创建点消费并随快照传入，避免 Worker 无法回写 AppStorage 导致标志粘连；`CacheConstants` 全部 AppStorage 访问 try/catch 回退。
- **验证**：StorageConflictUiTest（SFTP/WebDAV/S3 加载保存全链路 Worker 化）15/15 全绿；非 UI 全量 447/447。

该机制是 S3+ 流式管道的前置基础设施（Worker 侧文件 IO 同样依赖注入路径），后续阶段不得绕过 `CommonUtils` 路径助手直接访问 Context。

### 11.2 实施状态追踪（2026-10-06 核对，随实施持续更新）

落地提交：S1+S2 = `f507bd36`（2026-10-05，非 UI 全量 447/447 + StorageConflictUiTest 15/15）。

**S1 异步化（✅ 全部完成）**

| 项 | 状态 | 实现位置 |
|---|---|---|
| 双异步开关启用 | ✅ 均为 true | `Constants.ets:5,9` |
| 保存互斥（Promise 链串行） | ✅ 锁内重取最新模型，全终态路径释放 | `KdbxSaveService.ets:29-33,59-82` |
| Worker 环境注入（INIT_WORKER） | ✅ 路径/缓存策略/附件密钥三注入 | `DatabaseWorkerFactory.ets:18-47`、`WorkerParam.ets:38,51-76` |
| Worker 壳处理 INIT | ✅ FIFO 先于任务消息 | `DatabaseLoadWorker.ets:17-35`、`DatabaseSaveWorker.ets:17-35` |

**S2 守卫（✅ 全部完成，与设计有命名/细节偏差）**

| 项 | 状态 | 偏差说明 |
|---|---|---|
| CP1 文件大小 | ✅ | 常量名实为设置项 `SettingsService.KEY_DATABASE_MAX_SIZE`（默认 512MB，暂无 UI 入口）；fail-open |
| CP-DISK 磁盘 | ✅ | `statfs.getFreeSize`，阈值 4×F（未加附件池项）；fail-open |
| CP2' 模型 | ✅ | 公式 `appMemory × 0.55 ÷ 1.3`；ISIZE 预检已随 S5 落地（`prepareInnerFileStreaming`，守卫错误不回退整缓冲）；kdbxweb 侧 `assertDecompressedLimit` 4 处调用 + 流式 XML 区断言 |
| CP-UP 上传上限 | ✅ | WebDAV/OneDrive/pCloud/华为云盘 4 处；FTP（文件式上传）与 S3（multipart）合理豁免 |
| 错误码 i18n | ✅ | base + zh_CN 双语 4 个错误码齐全 |

**S3 流式存储 IO（✅ 存储侧完成；保存链路 writeFromFile 接线已随 S6 落地）**

| 项 | 状态 | 实现位置 |
|---|---|---|
| `readToFile`/`writeFromFile` 接口 + 默认包装 | ✅ | `IFileStorage.ets:37,57`、`FileTransfer.ets` |
| Local | ✅ | `fs.copyFile` + 临时文件 `fsync+rename` 原子替换（顺带修复非原子写） |
| WebDAV 下载 | ✅ | 实际用 `rcp.session.downloadToFile`（响应体不驻内存），非设计的 requestInStream，效果等价 |
| WebDAV 上传 | ❌ | 整缓冲 PUT，受 CP-UP 100MB 约束（rcps 流式上传仍为调研项） |
| S3 下载 | ✅ | Range GET 循环 8MB 段（`S3Client.getObjectRangeToFile`） |
| S3 上传 | ✅ | `S3Client.putObjectSmartFromFile`：小文件单次 PUT，大文件 multipart 由 worker 按任务区间 `fs.read(fd, buf, {offset})` 从源文件分片读取后 uploadPart（内存窗口=单分片，短读走重试）；`S3Storage.writeFromFile` 改走此路径并返回 getInfo；`write` 补 `option` 参数 + HEAD etag 写前复核（不一致抛 VERSION_CONFLICT，对齐 FTP 模式）；`getInfo` 透出 `version=etag`（去引号）激活保存链路基线 A 快速路径 |
| FTP/SFTP | ✅ | socket 分块读写（SFTP 显式 256KB 循环）；SFTP 无独立类，由 `FTPStorage` 按 protocol 分发 |
| OneDrive | ✅ | `writeFromFile` 走 Graph upload session（S7-a，见 S7 表）；`write` 仍整缓冲 PUT（CP-UP 100MB 守卫） |
| pCloud/华为云盘 | ❌ | 均默认整缓冲（S7 调研项） |
| 流式 sha256 冲突检测 | ✅ | `HashUtils.sha256HexFile`（cryptoFramework Md 4MB 分块 updateSync） |
| S3 专项测试 | ✅ | `S3ClientMultipart.test.ets` S3Client_Multipart_FromFile 3 用例（1MB 简单 PUT / 6MB multipart 进度单调+逐字节读回 / 恰 5MB 阈值边界）；`S3Storage.test.ets` StreamingAndConditionalWrite 4 用例（writeFromFile 返回 etag 版本+读回一致、小文件简单 PUT、write 匹配 expectedVersion 成功/过期拒绝 VERSION_CONFLICT、writeFromFile 过期拒绝且远端未覆盖）；均注册 List.test.ets |
| 保存链路写回 | ✅ | `DatabaseSave.writeSavedContent` 流式路径走 `KdbxFileManager.writeFromFile`（分块上传 + WriteOption 条件写），回退路径走 `write`；`postSuccess` 用 `sha256HexFile` 分块哈希落盘文件 |

**S4 流式解密 + 附件磁盘化（✅ 基本完成）**

| 项 | 状态 | 实现位置 |
|---|---|---|
| HMAC 块文件版 | ✅ | `decryptFromFile`/`encryptFromFile`（`hmac-block-transform.ts:127,198`）；原整缓冲接口保留 |
| ChaCha20 就地加解密 | ✅ | 命名为 `xorInPlace`（`chacha20.ts:55`），对称同一方法 |
| 附件磁盘化 | ✅ | 类型含 `KdbxBinaryDiskRef`（设计的 AttachmentRef）双模式；`AttachmentStore` 内容寻址加密缓存（HMAC(storeKey,hash) 文件名，[12B nonce][ChaCha20 密文]）；对外读取收敛为 `binaries.readDiskRef(ref)`；KPSN v2 支持 FLAG_STORE_REF |
| UI 三处适配 | ✅ | `EntryView.ets:248-275` 异步回填、`EntryEdit.ets:60,241`、`KdbxUtils.ets:346-349,679-685` |
| 新增附件即写 AS | ✅ | `EntryEdit.addAttachment`：`database.binaries.add(content)` 注册进附件池（保存时 `writeBinaries` 据 `getRefByHash` 写 `<Value Ref="n"/>`，不再 `setBytes` base64 内联进 XML）；`maybeConvertToDiskRefs(ATTACH_DISK_THRESHOLD_BYTES)` + `rebindEntryBinaries` 镜像加载侧磁盘化语义（修原 bug：裸 ArrayBuffer 入 entry.binaries → base64 内联 + 永不磁盘化） |
| 保存加密侧接线 | ✅ | `saveToFile`（`kdbx-format.ts`）调 `HmacBlockTransform.encryptFromFile`（X2→X3，ChaCha20 `xorInPlace` 作为 encryptBlock，内存窗口=1MB 块）；v3/AES-CBC 回退整缓冲 `save()`；`encryptFromFile` 已接线 |

**S5 流式解压加载侧（✅ 已落地，2026-10-06）**

| 项 | 状态 | 实现位置 |
|---|---|---|
| NDK zlib 流式模块 | ✅ | `libs/kdbxweb/src/main/cpp/zlib_stream.cpp`（inflateInit2(15+32)/deflate 流式分块，native 模块注册） |
| JS 包装 | ✅ | `zlib-file.ts`：`inflateFile`/`deflateFile`/`readGzipIsize`（文件到文件，内部 1MB 分块） |
| T2 内部头流式解析 | ✅ | `kdbx-header.ts:readInnerHeaderFromFile`（5 字节字段头循环；Binary 字段 ≥4MB 且 store 可用 → `sha256FileRegion`+`putFromFileRegion` 落盘 `KdbxBinaryDiskRef`，否则内存模式；末尾 validateInner）；抽出 `applyField` 复用整缓冲分支校验 |
| 附件池文件区域接口 | ✅ | `attachment-store.ts:sha256FileRegion`（4MB 分块 cryptoFramework Md，空区域返回空串 SHA-256 常量）/`putFromFileRegion`（4MB 分块 ChaCha20 → tmp → fsync → rename，已存在 touch 复用） |
| parseDecryptedFile 流式分发 | ✅ | `kdbx-format.ts`：`prepareInnerFileStreaming`（ISIZE 预检 + `checkDiskForStreamInflate` statfs 预检 fail-open + inflateFile；非 GZip 直用 T1）+ `parseInnerFileStreaming`（xmlLength=stat.size−xmlStart，CP2' 仅约束 XML 区；fd 双路径 close）；仅解压阶段失败回退整缓冲（守卫错误 DecompressedTooLarge/NotEnoughDisk 直接抛出），inner 解析开始后不回退（附件池已部分落盘，重放会状态重复） |
| Worker T2 接线 | ✅ | `DatabaseLoad.ets`：T2=`load_t2_<ts>.tmp` 传入 `Kdbx.load`，finally 三文件清理；`kdbx.ts` loadFromFile options 增 `t2Path` |
| 错误映射 | ✅ | `consts.ts` ErrorCodes 增 `NotEnoughDisk`；`KdbxUtils.ets` → `app.string.database_not_enough_disk`（base+zh_CN 既有资源） |
| 专项测试 | ✅ | `kdbx-streaming-load.test.ets` 6 用例（zlib 往返/ISIZE、T2 与整缓冲等价、≥4MB 附件落盘 disk ref、小附件留内存、未压缩库走 T1、超限拒绝），已注册 List.test.ets；⚠️ 测试库须显式 `dataCipherUuid=ChaCha20`（KdbxHeader.create 默认 AES） |
| 保存侧 deflate 接线 | ✅ | `saveToFile`（`kdbx-format.ts`）GZip 时调 `ZlibFile.deflateFile`（X1→X2，1MB in/4MB out 窗口）；未压缩时 X1 即载荷；`deflateFile` 已接线 |

**S7（🔄 部分实现）**

| 项 | 状态 | 实现位置 |
|---|---|---|
| S7-b 临时文件清扫 | ✅ | `TempFileSweeper.ets`：启动 `sweep()` 异步清扫 + onDestroy `sweepSync()` 兜底（挂 `EntryAbility.init/onDestroy`）；覆盖 `load_t0_/load_t1_/load_t2_/save_remote_/save_x1_/save_x2_/save_x3_*.tmp` 全部管道临时前缀；POSIX unlink 活动文件安全（fd 仍有效，不影响进行中任务）；4 用例注册 entry List.test.ets |
| S7-a OneDrive upload session | ✅ | `OneDriveClient.uploadFromFile`：`createUploadSession`（conflictBehavior=replace）→ 分片 PUT 到预授权 uploadUrl（5MiB=16×320KiB 对齐，Content-Range 头，202 受理/200·201 完成）；分片带 3 次重试（404 会话过期直接失败），失败/短读 `DELETE` 取消会话；<4MB 简单 PUT；`OneDriveStorage.writeFromFile` 接线并返回 getInfo（CP-UP 豁免：内存窗口=单分片）；`OneDriveUploadSession.test.ets` 未初始化拒绝 3 常驻用例 + 真实 Graph API 3 门控用例（令牌缺省不注册），已注册 List.test.ets |
| pCloud/华为云盘流式调研 | ❌ | 未实施 |
| 大文件验收报告 | ❌ | 待 S6 完成后执行（§12 指标） |

**S6 保存管道流式（🔄 部分实现，2026-10-06）**

| 项 | 状态 | 实现位置 |
|---|---|---|
| saveToFile 文件版管道 | ✅ | `kdbx.ts:saveToFile/canSaveToFile` + `kdbx-format.ts:saveToFile/saveV4ToFile/writeInnerToFile/checkDiskForStreamDeflate`：v4+ChaCha20 全链路 X1 inner→X2 deflate→X3 kdbx 落盘；buildXml+serialize 产 XML 字节写 X1，`writeInnerHeaderToFile` 流式分块回读磁盘引用附件直写 fd（`AttachmentStore.getToFile`/`binaries.readDiskRefToFile`），GZip 时 `deflateFile`，`encryptFromFile` 产 X3；v3/AES-CBC 回退 `save()` 整缓冲；`checkDiskForStreamDeflate` 磁盘余量守卫 |
| 保存写回 writeFromFile 接线 | ✅ | `DatabaseSave.ets`：`SavedContent` 双形态（filePath/buffer），`buildSavedContent` 据 `canSaveToFile()` 分流，`writeSavedContent` 流式走 `writeFromFile`+WriteOption 条件写、回退走 `write`；`postSuccess` 流式 `sha256HexFile`、回退 `sha256Hex`；非合并 data 传空缓冲（主线程不用） |
| 临时文件前缀 | ✅ | `TempFileSweeper.PREFIXES` 增 `save_x1_/save_x2_/save_x3_/merge_t1_/merge_t2_`；`DatabaseSave` finally 清理全部管道临时文件 |
| 专项测试 | ✅ | `kdbx-save-to-file.test.ets` 8 用例（canSaveToFile 判定、saveToFile 产物可加载、与 save 产物模型等价、compression None 往返、磁盘引用附件往返、缺参 InvalidArg、serializeToFile 模型等价+ProtectedValue/附件保真、serializeToFile 特殊字符转义）；`TempFileSweeper.test.ets` 增 save_x1/x2/x3 + merge_t1/t2 前缀断言与清扫用例；`DatabaseSaveStreaming.test.ets` 4 用例（流式无冲突/MERGE/OVERWRITE + AES 回退，含临时文件清理断言）；`kdbx-attachment-store.test.ets` +5 用例（getToFile 等价/大附件/篡改/缺失 + S6-d 新增附件注册池磁盘化） |
| 流式拉取解析器 | ❌ | 未实施（§7.2，后续会话） |
| 流式 XmlWriter | ✅ | `xml-utils.ts:serializeToFile`：DOM→文件 8MB 分块序列化器（消除 XML 字符串峰值 ③b + UTF-8 拷贝峰值 ③c；DOM 峰值 ③a 保留，att-500 3MB XML DOM ~15MB 在预算内）；`saveV4ToFile` 接线 `serializeToFile` 替代 `serialize`+`stringToBytes`+`write`；v3/saveXml 仍用 `serialize`（prettyPrint 不需文件版） |
| 会话文件协议 KPSN 退役 | ❌ | KPSN ArrayBuffer 协议仍在生产；无 session-* 目录、无会话密钥包裹、无 24h 清扫；`KdbxSnapshot.test.ets` 仍测 KPSN |
| MERGE 流式化 | ✅ | `DatabaseSave.mergeDatabase` 改用 `Kdbx.loadFromFile`（S4/S5 流式解密+解压+附件落盘管道），消除 peak ⑫（远端整缓冲 readFileToBuffer+Kdbx.load）；`merge_t1_/merge_t2_` 临时文件 + TempFileSweeper 覆盖；远端凭证变更仍抛 InvalidKey（错误语义不变） |
| 新增附件即写 AS | ✅ | `EntryEdit.addAttachment`：`binaries.add` 注册池（消除 base64 内联）+ `maybeConvertToDiskRefs` 阈值磁盘化 + `rebindEntryBinaries`；测试 `kdbx-attachment-store.test.ets` 增 'add attachment after load registers in pool and disk-refs on save' 用例 |

## 12. 验收标准汇总

1. **功能**：存储回归 12 套件 + UI 2 套件全绿；小库（<16MB 附件）行为与现状一致；KDBX 磁盘格式不变（桌面互认）；双开关 + `STREAMING_XML_PARSE` 可回滚。
2. **内存（核心指标）**：att-500 加载/保存全程峰值 RSS ≤ 150MB，且加载完成 30s 后 RSS 增量 ≤ 50MB；att-100/text-10k 同样与 F 解耦。
3. **稳定性**：全程无 AppFreeze/JsError；所有超限路径（CP1/CP2'/CP-DISK/CP-UP）明确报错零闪退；并发保存/保存中锁定解锁无异常。
4. **XML 流式**：流式与 DOM 路径差分测试全绿后 DOM 读取退役；v3 格式（base64 附件）大库可加载。
5. **安全**：会话目录外无明文落盘；锁定/切换/退出后 `session-*` 零残留；杀进程残留下次启动完成清扫且不可解密。
6. **可观测**：各管道阶段字节数/耗时/窗口占用 hilog 打点齐全，验收数据归档。
