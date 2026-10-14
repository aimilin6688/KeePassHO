---
name: uitest-dump-driving
description: >-
  真机 UI 自动化测试方法与 SM4 资产丢失 E2E 复现流程。当截图被隐私窗口模式/安全键盘防截屏保护弄黑、
  verify_ui 等截图驱动自动化在密码输入页"失明"时，用 `hdc shell uitest dumpLayout` 读 UI 树 +
  `uitest uiInput` 注入点击/输入，完成不依赖截图的精确驱动与断言。
  触发词：截图黑屏、页面全黑、UI 自动化、dumpLayout、uitest、uiInput、真机测试、E2E、
  复现、关键资产不存在、资产丢失、SM4 密钥、sm4_key、密码框黑屏、verify_ui 失败、无头驱动、
  Smoke FAIL_BLANK、隐私模式。
---

# uitest dumpLayout 驱动的真机 UI 自动化

## 0. 何时用本 skill

- 截图/`snapshot_display` 全黑但应用实际未崩：**隐私窗口模式**
  （`WindowUtils.setWindowPrivacyMode(true)`，本项目设置项 `Security_privacy_window` 默认开启）
  或安全键盘防窥保护，会把窗口在**截图**中渲染为纯黑，屏幕实际显示正常；
- 基于截图的自动化（verify_ui 等）在密码输入页变盲、误报"黑屏失败"；
- 需要精确坐标驱动与逐节点状态断言（text/checked/bounds）的 E2E。

**判定口诀：截图黑 ≠ 页面黑。先 dumpLayout 再下结论。**

## 1. hdc 路径与三板斧

本机 hdc 不在 PATH：

```powershell
$hdc = "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
$serial = "192.168.3.6:42755"   # 真机 connect-key，按实际填
```

| 动作 | 命令 |
|---|---|
| 导出 UI 树 | `& $hdc -t $serial shell "uitest dumpLayout -p /data/local/tmp/ui.json"` |
| 拉回本机 | `& $hdc -t $serial file recv /data/local/tmp/ui.json <本地路径>` |
| 点击 | `& $hdc -t $serial shell "uitest uiInput click <x> <y>"` |
| 输入文本 | `& $hdc -t $serial shell "uitest uiInput inputText <x> <y> <text>"` |
| 返回键（收键盘） | `& $hdc -t $serial shell "uinput -K -d 2 -u 2"` |

- 坐标取 dump JSON 中目标节点 `bounds`（`[x1,y1][x2,y2]`）的**中心点**；分辨率参考：Mate 60 Pro+ 为 1260×2720。
- `uiInput inputText` 直接注入文本（不经真实 IME），**对密码框等安全键盘页同样有效**；
  密码框 text 显示为 `*` 掩码，可断言掩码**长度**验证输入成功。

## 2. dump JSON 解析（PowerShell 片段）

```powershell
$j = Get-Content "<本地路径>\ui.json" -Raw | ConvertFrom-Json
$out = New-Object System.Collections.Generic.List[string]
function Walk($n) {
  $a = $n.attributes
  if ($null -ne $a) {
    $t = $a.type
    if ($a.text -or $t -in @('TextInput','TextArea','Button','Toggle','Radio','Checkbox','List','AlertDialog')) {
      $out.Add("$t | text=[$($a.text)] checked=[$($a.checked)] bounds=$($a.bounds)")
    }
  }
  foreach ($c in @($n.children)) { if ($null -ne $c) { Walk $c } }
}
Walk $j
$out | Select-Object -First 30
```

系统弹框（通知授权、AlertDialog）也是树节点，可定位可点击。

## 3. 标准驱动循环（每一步都走）

```
dump → 定位目标节点（text/checked）→ 算中心坐标 → click / inputText
→ 【inputText 后必须】back 键收起软键盘 → 重新 dump 校验结果 → 下一步
```

- **inputText 后软键盘可能挤压布局，节点坐标整体偏移**：不收键盘直接用旧坐标点按钮会点空；
- 不硬编码坐标：页面状态不同（键盘/弹框/滚动）bounds 会变，**每次行动前重新 dump**；
- 长流程（如解锁 5s+ 下载）在 click 后 `Start-Sleep` 足够秒数再 dump。

## 4. 黑屏诊断决策树

1. `snapshot_display` 截屏拉回本机，System.Drawing 算平均亮度（≈0 为全黑）；
2. **dumpLayout 有正常节点** → 隐私模式/安全键盘所致，属预期，继续用本 skill 驱动；
3. dumpLayout 也无应用节点 → 查 `hilog -x | grep <bundle>` 与 faultlog，按崩溃处理；
4. `devecocli run` 的 `Smoke: FAIL_BLANK` 同理：应用含隐私页（解锁页）时属预期，
   用 dumpLayout 确认真实页面即可，不要当崩溃排查。

亮度分析片段：

```powershell
Add-Type -AssemblyName System.Drawing
$img=[System.Drawing.Image]::FromFile($path); $bmp=New-Object System.Drawing.Bitmap($img)
$sum=0.0;$n=0
for($y=0;$y -lt $bmp.Height;$y+=20){for($x=0;$x -lt $bmp.Width;$x+=20){
  $c=$bmp.GetPixel($x,$y);$sum+=($c.R+$c.G+$c.B)/3.0;$n++}}
"avg brightness: {0:N1}" -f ($sum/$n)   # 0=纯黑
```

## 5. 构建 / 部署 / 日志

```powershell
devecocli build                                     # 构建
devecocli run --skip-build --device $serial         # 覆盖安装并启动
& $hdc -t $serial shell "hilog -x | grep -E '<关键词>'"   # 日志（滚动的尽快抓）
```

- **严禁卸载**（`hdc uninstall` / `bm uninstall`）：会同时删除应用数据与 Asset Kit 资产；
  只允许覆盖安装（`devecocli run` / `hdc install -r`）；
- 隧道：`.\docs\e2e\e2e-tunnels.ps1 -Target $serial`（幂等；hdc 重启/设备重连后重跑）；
  设备侧校验 `netstat -tln` 有无 `LISTEN`，僵尸监听见 `docs/e2e/e2e-tunnels.md` §3。

## 6. 实战流程：SM4 资产丢失三阶段 E2E 复现

> 完整指南：`docs/e2e/s3/sm4-asset-loss-e2e.md`；S3 服务：`docs/e2e/s3/seaweedfs-server.md`。

环境：podman SeaweedFS（宿主 9000，桶 `e2e-test`）+ 反向隧道（设备访问 `127.0.0.1:9000`）。

**阶段 A —— 建 S3 最近记录**：主页→新建数据库（名 `keepass-e2e`、密码两遍）→存储选
「S3 存储」→填端点 `127.0.0.1:9000`、AK `e2e`、SK `e2etest123`、开「高级设置」填默认桶
`e2e-test`、URL 样式选「路径样式」→确定→保存→输入主密码解锁成功→重启应用直达该库解锁页即证明记录已建。

**阶段 B —— 模拟资产丢失**：`Sm4Utils.ASSET_SM4_KEY_NAME` 临时改 `'sm4_key_repro'`→
build + 覆盖安装→断言：

| 断言 | 手段 |
|---|---|
| 新钥生成 | hilog：`sm4_key not found in asset store, generating NEW key` |
| 旧密文解密失败 | hilog：`crypto failed, code:17630001 ... bad decrypt` |
| 引导弹框 | dump：`AlertDialog`「连接配置已过期，请重新编辑」+「重新编辑」按钮 |
| 重新编辑跳转 | 点「重新编辑」→ dump：TitleBar 变「S3 存储」 |

**阶段 C —— 还原**：别名改回 `'sm4_key'`→build + 覆盖安装→原资产未动→
解锁成功进入库主界面（dump：库名 + 回收站/条目列表）即恢复。

## 7. 踩坑记录（勿重复踩）

- verify_ui 等截图自动化在密码输入页必然失明（安全键盘防截屏），此类页面一律改用本 skill；
  verify_ui 同一目标最多 3 次调用，黑屏页别浪费次数；
- `kdbxErrorPayload` 跨线程错误契约：Worker 中 `$r` 可用，`ConfigDecryptError.message`
  已是本地化文案，主线程只认资源名 `storage_config_decrypt_failed`——已在 KdbxUtils
  特判映射（2026-10-14 修复），同类"Worker 抛错→主线程按名识别"的设计必须走资源名；
- S3 网关必须**路径样式**且**填默认桶**，否则 `NOT_IMPLEMENTED: The specified bucket does not exist`；
- 系统弹框（通知授权、赞助弹框）会挡住页面，出现即处理，别对着被挡坐标空点；
- MinIO 已归档（dl.min.io 410 Gone），S3 模拟一律用 SeaweedFS（podman）；
- `uitest dumpLayout` 输出路径必须 `/data/local/tmp/` 下，其他目录可能无权限。
