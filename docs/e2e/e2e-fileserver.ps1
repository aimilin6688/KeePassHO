#Requires -Version 5.1
<#
.SYNOPSIS
    Windows(PowerShell) 版 e2e 文件服务器拉起脚本，等价于 e2e-fileserver.sh。
.DESCRIPTION
    切到脚本所在目录，用 podman 或 docker 的 compose 拉起 S3 / WebDAV / SFTP 容器。
    优先 podman，其次 docker。
#>
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
Push-Location $ScriptDir
try {
    $composeFile = Join-Path $ScriptDir "docker-compose.yml"
    if (-not (Test-Path $composeFile)) {
        Write-Host "[错误] 未找到 docker-compose.yml（$composeFile）" -ForegroundColor Red
        exit 1
    }
    $runner = $null
    if (Get-Command podman -ErrorAction SilentlyContinue) { $runner = "podman" }
    elseif (Get-Command docker -ErrorAction SilentlyContinue) { $runner = "docker" }

    if (-not $runner) {
        Write-Host "[错误] 未找到 podman 或 docker，无法拉起容器文件服务器" -ForegroundColor Red
        exit 1
    }
    Write-Host "[容器] 使用 $runner compose 拉起 e2e 文件服务器..."
    & $runner compose -f $composeFile up -d
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[错误] 容器启动失败（exit $LASTEXITCODE）" -ForegroundColor Red
        exit $LASTEXITCODE
    }
    Write-Host "[容器] 容器已拉起（S3:9000 / WebDAV:8800 / SFTP:2222）" -ForegroundColor Green
} finally {
    Pop-Location
}
