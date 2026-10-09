#Requires -Version 5.1
<#
.SYNOPSIS
    e2e 存储回归测试 hdc 反向隧道自动 setup（S3 / WebDAV / SFTP），Windows(PowerShell) 版。
.DESCRIPTION
    为已连接的真机/模拟器建立 hdc 反向隧道，使设备侧 127.0.0.1:<dport> 转发到宿主 127.0.0.1:<hport>。
    逻辑与 docs/e2e/e2e-tunnels.sh 保持一致：双条件判定 + 僵尸监听清理 + 幂等。
.PARAMETER Containers
    宿主端口不通时，自动调用 e2e-fileserver.ps1 拉起容器文件服务器。
.PARAMETER Reset
    强制清理重建（含僵尸监听清理）。
.PARAMETER Target
    仅处理指定设备，如 -Target 192.168.3.6:42755（真机网络调试）或 -Target 127.0.0.1:5555（模拟器）。
.EXAMPLE
    .\e2e-tunnels.ps1                              # 为所有已连接设备幂等建立缺失隧道
    .\e2e-tunnels.ps1 -Containers                 # 宿主端口不通时自动拉起容器
    .\e2e-tunnels.ps1 -Reset                      # 强制清理重建
    .\e2e-tunnels.ps1 -Target 192.168.3.6:42755   # 仅针对某台真机
#>
[CmdletBinding()]
param(
    [switch]$Containers,
    [switch]$Reset,
    [string]$Target = ""
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# 隧道清单：设备端口 / 宿主端口 / 名称（新增存储后端时在此追加）
$Ports = @(
    @{ Dport = 9000; Hport = 9000; Name = "S3" },
    @{ Dport = 8800; Hport = 8800; Name = "WebDAV" },
    @{ Dport = 2223; Hport = 2222; Name = "SFTP" }
)

# ---------- hdc 解析：环境变量 HDC > PATH > 常见 DevEco/SDK 安装位置 ----------
function Resolve-Hdc {
    if ($env:HDC -and (Test-Path $env:HDC)) { return $env:HDC }
    $cmd = Get-Command hdc.exe -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $candidates = @(
        "C:\Program Files\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe",
        "$env:LOCALAPPDATA\Huawei\Sdk\openharmony\*\toolchains\hdc.exe",
        "$env:USERPROFILE\AppData\Local\Huawei\Sdk\openharmony\*\toolchains\hdc.exe",
        "$env:ProgramFiles\Huawei\DevEco Studio\sdk\default\openharmony\toolchains\hdc.exe"
    )
    foreach ($pattern in $candidates) {
        $found = Resolve-Path -Path $pattern -ErrorAction SilentlyContinue
        if ($found) { return $found[0].Path }
    }
    return $null
}

$HDC = Resolve-Hdc
if (-not $HDC) {
    Write-Host "错误：未找到 hdc.exe。请将其加入 PATH，或通过环境变量 HDC 指定绝对路径" -ForegroundColor Red
    exit 1
}
Write-Host "hdc: $HDC"

# ---------- 设备清单 ----------
$raw = & $HDC list targets 2>$null
$Targets = ($raw | Where-Object { $_ -and -not $_.StartsWith('[Empty') }).Trim()
if (-not $Targets) {
    Write-Host "错误：无已连接设备（hdc list targets 为空）" -ForegroundColor Red
    exit 1
}
if ($Target) {
    $Targets = ($Targets | Where-Object { $_.Contains($Target) })
    if (-not $Targets) {
        Write-Host "错误：设备 $Target 不在线" -ForegroundColor Red
        exit 1
    }
}

# ---------- 基础探测 ----------
# 主机注册表是否含 <target> 的 <dport> 反向规则（fport ls 为全局表，按目标+端口过滤）
function Registry-Has([string]$target, [int]$dport) {
    $ls = & $HDC fport ls 2>$null
    foreach ($line in $ls) {
        $l = $line.ToLower()
        if ($l.Contains($target.ToLower()) -and $l.Contains("tcp:$dport")) { return $true }
    }
    return $false
}
# 设备侧是否 LISTEN 127.0.0.1:<dport>（锚定 LISTEN + 端口后随空白，规避残留客户端 socket）
function Device-Listening([string]$target, [int]$dport) {
    & $HDC -t $target shell "netstat -tln 2>/dev/null | grep 'LISTEN' | grep '127.0.0.1:$dport '" 2>$null >$null
    return ($LASTEXITCODE -eq 0)
}
# 宿主侧端口连通性（容器发布端口）
function Host-PortOk([int]$port) {
    $r = Test-NetConnection -ComputerName 127.0.0.1 -Port $port -InformationLevel Quiet -WarningAction SilentlyContinue
    return ($r -eq $true)
}

# 僵尸项用对象存储（target 本身含冒号，禁止用冒号切分）
$zombieTargets = New-Object System.Collections.Generic.List[object]

# ---------- 宿主侧连通性（容器发布端口） ----------
$containersDown = $false
foreach ($p in $Ports) {
    if (-not (Host-PortOk $p.Hport)) { $containersDown = $true }
}
if ($containersDown) {
    if ($Containers) {
        Write-Host "容器：宿主端口不通，自动拉起 e2e 容器..."
        $fs = Join-Path $ScriptDir "e2e-fileserver.ps1"
        if (Test-Path $fs) { & $fs } else { & (Join-Path $ScriptDir "e2e-fileserver.sh") }
        Start-Sleep -Seconds 3
    } else {
        Write-Host "警告：宿主侧存在不通的端口（容器未启动？）" -ForegroundColor Yellow
        Write-Host "        手动拉起：.\e2e-fileserver.ps1，或本脚本加 -Containers" -ForegroundColor Yellow
    }
}

# ---------- Pass 1：逐设备逐端口分类 ----------
# ready    = 注册表 + 设备监听双满足
# zombie   = 设备监听但注册表无（hdc 重启残留黑洞）
# missing  = 两侧皆无，需新建
foreach ($t in $Targets) {
    foreach ($p in $Ports) {
        if ((Registry-Has $t $p.Dport) -and (Device-Listening $t $p.Dport)) { continue }
        if (Device-Listening $t $p.Dport) {
            $zombieTargets.Add(@{ Target = $t; Dport = $p.Dport })
        }
    }
}

# ---------- Pass 2：清理僵尸监听 ----------
if ($zombieTargets.Count -gt 0 -or $Reset) {
    Write-Host "清理：检测到僵尸监听（hdc 重启残留黑洞），执行 hdc killall-sub（全局，异步生效）..."
    & $HDC killall-sub 2>$null >$null
    $cleared = $false
    $waitRounds = 0
    while ($waitRounds -lt 10) {
        Start-Sleep -Seconds 1
        $waitRounds++
        $allCleared = $true
        foreach ($item in $zombieTargets) {
            if (Device-Listening $item.Target $item.Dport) { $allCleared = $false }
        }
        if ($allCleared) { $cleared = $true; break }
    }
    if ($cleared) {
        Write-Host "清理：僵尸监听已清除（等待 ${waitRounds}s）"
    } else {
        Write-Host "警告：部分僵尸监听未在 10s 内消失，重建可能失败；可重跑本脚本或重启设备" -ForegroundColor Yellow
    }
}

# ---------- Pass 3：建立隧道并双条件校验 ----------
$failTotal = 0
foreach ($t in $Targets) {
    Write-Host ""
    Write-Host "=== 设备 $t ==="
    foreach ($p in $Ports) {
        if ((Registry-Has $t $p.Dport) -and (Device-Listening $t $p.Dport)) {
            Write-Host "  【$($p.Name)】 设备 $($p.Dport) -> 宿主 $($p.Hport) ：已就绪"
            continue
        }
        $result = & $HDC -t $t rport "tcp:$($p.Dport)" "tcp:$($p.Hport)" 2>&1
        if ($result -notmatch 'OK') {
            Write-Host "  【$($p.Name)】 建立失败：$result" -ForegroundColor Red
            $failTotal++
            continue
        }
        $ok = $false
        $checkRounds = 0
        while ($checkRounds -lt 5) {
            if ((Registry-Has $t $p.Dport) -and (Device-Listening $t $p.Dport)) {
                $ok = $true; break
            }
            Start-Sleep -Seconds 1
            $checkRounds++
        }
        if ($ok) {
            Write-Host "  【$($p.Name)】 设备 $($p.Dport) -> 宿主 $($p.Hport) ：建立成功"
        } else {
            Write-Host "  【$($p.Name)】 建立后校验未通过（注册表/设备监听缺一），请复查" -ForegroundColor Red
            $failTotal++
        }
    }
}

Write-Host ""
if ($failTotal -eq 0) {
    Write-Host "全部隧道就绪（Windows PowerShell 版）。hdc 重启/设备重连后需重跑本脚本" -ForegroundColor Green
    exit 0
}
Write-Host "存在 $failTotal 条失败隧道" -ForegroundColor Red
exit 1
