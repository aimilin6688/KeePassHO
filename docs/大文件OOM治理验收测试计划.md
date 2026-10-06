# 大文件 OOM 治理验收测试计划

> 关联设计：`数据库异步加载保存与大文件OOM治理设计.md` §10 内存预算与验收 / §12 验收标准汇总
> 状态：待执行（需真机/模拟器 + hdc，本地仅编译验证）
> 前置：S1-S6 保存管道流式 + S7-b 清扫 + S7-a OneDrive + pCloud/华为下载流式 均已落地

## 1. 测试矩阵

| 用例 ID | 库类型 | 大小 | 附件 | 条目 | 预期 | 守卫 |
|---|---|---|---|---|---|---|
| att-100 | 附件型 | ~100MB | 1×96MB | 100 | 加载/保存峰值 ≤150MB | — |
| att-300 | 附件型 | ~300MB | 1×290MB | 300 | 加载/保存峰值 ≤150MB | — |
| att-500 | 附件型 | ~500MB | 1×480MB | 10k | 加载/保存峰值 ≤150MB | — |
| text-1k | 文本型 | ~5MB | 0 | 1k | 行为回归基准 | — |
| text-10k | 文本型 | ~50MB | 0 | 10k | 加载峰值与 F 解耦 | — |
| text-huge-300 | 文本型 | ~300MB | 0 | 60k | CP2' 拒绝零闪退 | CP2' |
| webdav-200 | 附件型 | ~200MB | 1×190MB | 100 | CP-UP 报错引导换 S3/OneDrive/Local | CP-UP |
| residual | 任意 | 任意 | 任意 | 任意 | 杀进程后启动清扫残留 | — |

## 2. 测试库生成脚本

```typescript
// 在 kdbxweb ohosTest 或 entry ohosTest 中生成测试库
// att-500: 1×480MB 附件 + 10k 条目
async function genAtt500(credentials: KdbxCredentials): Promise<ArrayBuffer> {
  const db = Kdbx.create(credentials, 'att-500');
  db.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
  const big = new ArrayBuffer(480 * 1024 * 1024);
  // 填充可压缩模式数据（模拟真实附件）
  const bytes = new Uint8Array(big);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = (i * 31 + 7) % 256;
  }
  const binary = await db.binaries.add(big);
  for (let i = 0; i < 10000; i++) {
    const entry = db.createEntry(db.getDefaultGroup());
    entry.fields.set('Title', `entry-${i}`);
    if (i % 10 === 0) {
      entry.binaries.set(`attach-${i}.bin`, binary);
    }
  }
  return db.save();
}
```

## 3. 执行命令

### 3.1 单元测试（已有套件）
```bash
# entry 全量单元测试（含 S6 流式保存、TempFileSweeper、AttachmentStore 等）
hdc shell aa test -b com.aimilin.keepassho -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 60000

# kdbxweb 单元测试（含 saveToFile、streaming-load、attachment-store 等）
hdc shell aa test -b com.aimilin.keepassho -m kdbxweb_test -s unittest OpenHarmonyTestRunner -s timeout 60000
```

### 3.2 内存采样脚本（hidumper 200ms 间隔）
```bash
# 后台采样进程 RSS（加载/保存期间持续运行）
PID=$(hdc shell pidof com.aimilin.keepassho)
while true; do
  hdc shell hidumper --mem $PID | grep "RSS:" | head -1
  sleep 0.2
done > mem-samples.log
```

### 3.3 大文件验收流程
1. 生成测试库 → 推送到设备 `/data/storage/el2/base/haps/entry/files/`
2. 启动 hidumper 采样
3. App 打开测试库（加载）→ 记录峰值 RSS
4. 修改一个条目 → 保存 → 记录峰值 RSS
5. 停止采样 → `awk` 求峰值：`sort -t= -k2 -n mem-samples.log | tail -1`
6. 验证峰值 ≤ 150MB

## 4. 验收标准映射（§12）

| §12 条款 | 验收方法 | 通过标准 |
|---|---|---|
| 1. 功能：存储回归 12 套件 + UI 2 套件全绿 | §3.1 命令执行 | 全部 PASS |
| 1. 功能：小库行为一致 | att-100 加载后条目/附件内容校验 | 与生成数据一致 |
| 1. 功能：KDBX 格式不变 | att-500 保存产物用桌面 KeePass 2.x / KeePassXC 打开 | 可打开 |
| 2. 内存：att-500 峰值 RSS | §3.3 流程 | ≤150MB |
| 2. 内存：加载完成 30s 后 RSS 增量 | §3.3 采样 | ≤50MB |
| 3. 稳定性：超限零闪退 | text-huge-300 加载 / webdav-200 保存 | 明确报错不闪退 |
| 3. 稳定性：并发保存 | 快速连续触发 2 次保存 | 互斥排队无异常 |
| 4. XML 流式 | 差分测试（待拉取解析器落地后） | — |
| 5. 安全：杀进程残留 | 残留用例：加载中 kill app → 重启 | TempFileSweeper 清理 session-* + load_t*/save_x*/merge_t* |
| 6. 可观测：hilog 打点 | `hdc hilog | grep -E 'save stage\|load stage\|save total\|load total'` | 各阶段耗时/字节数齐全 |

## 5. hilog 打点清单（§12.6 已落地）

### 加载管道（DatabaseLoad）
```
load stage download: <ms>, bytes=<n>       — readToFile 流式下载
load stage parse(decrypt+inflate+xml): <ms> — loadFromFile 解密+解压+解析
load stage sha256: <ms>, bytes=<n>          — sha256HexFile 冲突检测基线
load total: <ms>                            — 全程耗时
```

### 保存管道（DatabaseSave）
```
save stage download: <ms>, bytes=<n>        — readToFile 流式下载远端
save stage sha256: <ms>, bytes=<n>          — sha256HexFile 双基线冲突检测
save stage build(stream): <ms>              — saveToFile 流式加密压缩（X1→X2→X3）
save stage build(buffer): <ms>              — save() 整缓冲回退（v3/AES）
save stage upload(stream): <ms>             — writeFromFile 流式上传
save stage upload(buffer): <ms>, bytes=<n>  — write 整缓冲上传
save stage merge-load: <ms>                 — MERGE loadFromFile 流式加载远端
save total (no-conflict): <ms>, mode=stream|buffer  — 无冲突全程
save total (overwrite): <ms>, mode=...      — OVERWRITE 全程
save total (merge): <ms>, mode=...          — MERGE 全程
```

## 6. 互操作验证

att-500 保存产物需由桌面客户端双向打开验证：
1. 设备上 att-500 库保存 → `hdc file recv` 拉到主机
2. KeePass 2.x（官方）打开 → 验证条目/附件可读
3. KeePassXC 打开 → 验证条目/附件可读
4. 桌面修改一个条目 → 保存 → 推回设备 → App 重新加载 → 验证修改可见

## 7. 已知限制

- **text-huge-300**：CP2' 守卫拒绝（设计文档 §1 非目标，模型必须驻 RAM）
- **WebDAV 上传 >100MB**：CP-UP 拒绝（rcps 流式上传为调研项）
- **pCloud/华为上传流式**：仍走整缓冲 + CP-UP（upload session 需官方 API 文档）
- **DOM 峰值 ③a**：att-500 3MB XML DOM ~15MB，在 150MB 预算内；text-10k 受 CP2' 约束
