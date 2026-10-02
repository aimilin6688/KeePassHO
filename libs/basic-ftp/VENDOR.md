# basic-ftp vendored 副本说明

## 来源

- 上游库：`@ohos/basic-ftp@1.0.3`（ohpm 仓库，keeweb/kdbxweb 生态同作者维护的鸿蒙移植版 basic-ftp）
- vendor 时间：2026-10-02（提交 `ca2b68e0`）
- vendor 原因：上游缺陷 D——`transfer.ts downloadTo()` 把二进制 ArrayBuffer 先 `toString('utf-8')`
  再写盘，任何非 UTF-8 安全的二进制文件（kdbx）下载必损坏，且上游无源码仓库无法提 PR。

## 引入方式

- `entry/oh-package.json5`：`"@ohos/basic-ftp": "file:../libs/basic-ftp"`（目录依赖，对齐 kdbxweb 的 file: 模式）
- 根 `build-profile.json5`：modules 注册 `basic_ftp`（模块名不含连字符，schema `^[a-zA-Z][0-9a-zA-Z_.]*$`）
- 本目录 `src/main/module.json5`：vendor 时补建（上游 ohpm 包内含，源码发布缺）

## 与上游 1.0.3 的本地补丁清单

升级上游版本时需重新套用以下补丁：

| # | 文件:行 | 缺陷 | 补丁内容 |
|---|---|---|---|
| FIX(D) | `src/main/ets/transfer.ts` downloadTo() 两处 writeSync（628/650 行） | 下载路径二进制不安全：`buffer.from(data).toString('utf-8')` 有损转字符串后 `writeSync(string)` | 直写 ArrayBuffer：`writeSync(tempData)` |
| FIX(D-upload) | `src/main/ets/transfer.ts` uploadFrom() TLS 分支（cast 516 行 / send 517 行） | 上传路径 FTPS（TLSSocket）同样把 ArrayBuffer 有损转字符串再 send | 直发 ArrayBuffer：`localTlsSocket.send(trueData)`（SDK 确认 TLSSocket.send 支持 `string \| ArrayBuffer`） |
| FIX(A) | `src/main/ets/FtpContext.ts` handle()（401 行） | 控制信道 socketTimeout 全局禁用（0）导致 greeting/命令等待永久挂起 | 恢复 `socketTimeout: this.timeout ? this.timeout : 0`；数据传输期由 TransferResolver 单独管理（onDataStart 置 0 / onDataDone 恢复） |
| FIX(A2) | `src/main/ets/FtpContext.ts` handle()（402-408 行） | async executor 内 `throw extraErr` 不会 settle 外层 Promise → task 永久挂起（存储层操作队列会放大为全部后续 op 阻塞） | 显式 `rejectTask(extraErr); return` |

## 已知保留的上游问题

- 上游遗留的 `BasicFtpTest` 计时 `console.log`（FtpContext/Client 多处）未清理——升级时一并处理。
- TCP 半开连接（无 FIN 的非优雅 kill）`Client.closed` 无法感知，需下次 send 失败暴露（TCP 固有局限，非上游 bug）。
- FtpContext.handle() 的偶发 stall（时序敏感、无法稳定复现）——30s fail-fast 缓解，详见
  `docs/SFTP客户端Rust绑定开发计划.md` §9.3 缺陷 A 根因调查结论。
