#Requires -Version 7
<#
  下载品牌图标并生成图标选择器用的 SVG（品牌色图形，透明背景，128x128）
  图标来源（许可均允许内嵌再分发）：
    - simple-icons (CC0):        ..\其他库\simple-icons  (github.com/simple-icons/simple-icons)
    - lawnicons   (Apache-2.0):  ..\其他库\lawnicons     (github.com/LawnchairLauncher/lawnicons)
  输出: entry/src/main/resources/rawfile/brand_icons/*.svg
  清单数据: scripts/brand-icons-source.json（与跨平台 Node 版 download-brand-icons.mjs 共用）
  用法:
    pwsh scripts/download-brand-icons.ps1            # 生成全部
    pwsh scripts/download-brand-icons.ps1 -Find 微信 # 按关键词在两个图标库中查找
    node scripts/download-brand-icons.mjs 微信       # 跨平台 Node 等价版
#>
param([string]$Find = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$libRoot = Split-Path -Parent $root
$siDir = Join-Path $libRoot '其他库\simple-icons'
$lawnDir = Join-Path $libRoot '其他库\lawnicons'
$outDir = Join-Path $root 'entry/src/main/resources/rawfile/brand_icons'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

if (-not (Test-Path (Join-Path $siDir 'data\simple-icons.json'))) { throw "simple-icons 不存在: $siDir" }
if (-not (Test-Path (Join-Path $lawnDir 'app\assets\appfilter.xml'))) { throw "lawnicons 不存在: $lawnDir" }

# ---------------- 清单: file=输出文件名 group=分组 label=显示名 kw=搜索关键词 ----------------
# si=SI slug(优先，颜色取官方 hex) pkg=安卓包名(lawnicons 查找) pref=首选 drawable hex=lawn 来源品牌色
# 清单数据维护在 brand-icons-source.json（与跨平台 Node 版 download-brand-icons.mjs 共用）
$manifest = [IO.File]::ReadAllText((Join-Path $PSScriptRoot 'brand-icons-source.json')) | ConvertFrom-Json

# ---------------- simple-icons 索引（title -> slug 派生 + slugs.md 例外） ----------------
Write-Host '读取 simple-icons 索引...'
$siJson = [IO.File]::ReadAllText((Join-Path $siDir 'data\simple-icons.json')) | ConvertFrom-Json
$slugsMd = [IO.File]::ReadAllText((Join-Path $siDir 'slugs.md'))
$slugException = @{}
foreach ($m in [regex]::Matches($slugsMd, '^\|\s*`([^`]+)`\s*\|\s*`([a-z0-9\-]+)`\s*\|\s*$', 'Multiline')) {
  $slugException[$m.Groups[1].Value] = $m.Groups[2].Value
}
$siHex = @{}
$siTitle = @{}
foreach ($i in $siJson) {
  $slug = if ($slugException.ContainsKey($i.title)) { $slugException[$i.title] } else { $i.title.ToLower() -replace '[^a-z0-9]', '' }
  if ($slug) {
    $siHex[$slug] = if ($i.hex -match '^#') { $i.hex } else { '#' + $i.hex }
    $siTitle[$slug] = $i.title
  }
}
Write-Host "  simple-icons: $($siHex.Count) 个图标"

# ---------------- lawnicons 索引（pkg -> drawable 计数） ----------------
Write-Host '读取 lawnicons appfilter.xml...'
$appfilter = [IO.File]::ReadAllText((Join-Path $lawnDir 'app\assets\appfilter.xml'))
$pkgDrawables = @{}
foreach ($m in [regex]::Matches($appfilter, 'component="ComponentInfo\{([^/}]+)/[^}]+\}"\s+drawable="([^"]+)"')) {
  $pkg = $m.Groups[1].Value
  $d = $m.Groups[2].Value
  if (-not $pkgDrawables.ContainsKey($pkg)) { $pkgDrawables[$pkg] = @{} }
  if ($pkgDrawables[$pkg].ContainsKey($d)) { $pkgDrawables[$pkg][$d]++ } else { $pkgDrawables[$pkg][$d] = 1 }
}
Write-Host "  lawnicons: $($pkgDrawables.Count) 个应用包"

function Pick-Drawable([string]$pkg, [string]$pref) {
  if (-not $pkg -or -not $pkgDrawables.ContainsKey($pkg)) { return $null }
  $set = $pkgDrawables[$pkg]
  if ($pref -and $set.ContainsKey($pref)) { return $pref }
  $best = $null; $bestCount = -1
  foreach ($k in $set.Keys) {
    if ($set[$k] -gt $bestCount) { $best = $k; $bestCount = $set[$k] }
  }
  return $best
}

# ---------------- 查找模式 ----------------
if ($Find) {
  Write-Host "--- lawnicons 包名/drawable 匹配 '$Find' ---"
  foreach ($k in $pkgDrawables.Keys) {
    if ($k -like "*$Find*") {
      $top = ($pkgDrawables[$k].GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 2 | ForEach-Object { "$($_.Key)x$($_.Value)" }) -join ','
      Write-Host "  $k -> $top"
    }
  }
  Write-Host "--- simple-icons 匹配 '$Find' ---"
  foreach ($s in $siHex.Keys) {
    if ($s -like "*$Find*" -or $siTitle[$s] -like "*$Find*") { Write-Host "  $s ($($siTitle[$s])) $($siHex[$s])" }
  }
  return
}

# ---------------- SVG 处理 ----------------
# 提取原 svg 内部全部图形（path/circle/rect/g 等，支持 stroke 型），上品牌色，
# 按原 viewBox 等比缩放到 112x112 居中放入 128x128 透明画布（边距 8）
function Convert-ToBrandSvg([string]$svg, [string]$hex) {
  if (-not $svg) { return $null }
  $rootOpen = [regex]::Match($svg, '<svg\b[^>]*>')
  if (-not $rootOpen.Success) { return $null }
  $rootTag = $rootOpen.Value
  $start = $rootOpen.Index + $rootOpen.Length
  $end = $svg.LastIndexOf('</svg>')
  if ($end -lt $start) { return $null }
  $inner = $svg.Substring($start, $end - $start)
  $inner = [regex]::Replace($inner, '(?s)<!--.*?-->', '')
  $inner = [regex]::Replace($inner, '(?s)<title>.*?</title>', '')
  $inner = [regex]::Replace($inner, '(?s)<metadata>.*?</metadata>', '')
  $inner = [regex]::Replace($inner, '(?s)<desc>.*?</desc>', '')
  if ($inner -notmatch '<(path|circle|rect|ellipse|polygon|polyline|line|g)\b') { return $null }
  # 原始 viewBox（缺省时用 width/height，再缺省按 24x24）
  $minX = 0.0; $minY = 0.0; $w = 24.0; $h = 24.0
  $vb = [regex]::Match($rootTag, 'viewBox="([\-0-9.eE]+)\s+([\-0-9.eE]+)\s+([\-0-9.eE]+)\s+([\-0-9.eE]+)"')
  if ($vb.Success) {
    $minX = [double]$vb.Groups[1].Value; $minY = [double]$vb.Groups[2].Value
    $w = [double]$vb.Groups[3].Value; $h = [double]$vb.Groups[4].Value
  } else {
    $mw = [regex]::Match($rootTag, 'width="([0-9.]+)')
    $mh = [regex]::Match($rootTag, 'height="([0-9.]+)')
    if ($mw.Success -and $mh.Success) { $w = [double]$mw.Groups[1].Value; $h = [double]$mh.Groups[1].Value }
  }
  if ($w -le 0 -or $h -le 0) { return $null }
  # 根节点 fill/stroke 继承（stroke 型图标常把 stroke/stroke-width 定义在根 <svg> 上，丢弃根节点后需补回）
  $rootFill = [regex]::Match($rootTag, '(?i)\bfill\s*=\s*"([^"]*)"').Groups[1].Value
  $rootStroke = [regex]::Match($rootTag, '(?i)\bstroke\s*=\s*"([^"]*)"').Groups[1].Value
  if ($rootFill -or $rootStroke) {
    $wrapAttrs = ''
    if ($rootFill -ieq 'none') { $wrapAttrs += ' fill="none"' }
    elseif ($rootFill -and $rootFill -ine 'none') { $wrapAttrs += ' fill="' + $hex + '"' }
    if ($rootStroke -ieq 'none') { $wrapAttrs += ' stroke="none"' }
    elseif ($rootStroke) { $wrapAttrs += ' stroke="' + $hex + '"' }
    foreach ($sa in @('stroke-width', 'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit', 'stroke-dasharray', 'stroke-dashoffset', 'stroke-opacity')) {
      $mv = [regex]::Match($rootTag, '(?i)\b' + $sa + '\s*=\s*"([^"]*)"')
      if ($mv.Success) { $wrapAttrs += ' ' + $sa + '="' + $mv.Groups[1].Value + '"' }
    }
    $inner = '<g' + $wrapAttrs + '>' + $inner + '</g>'
  }
  # 上色：非 none 的 fill/stroke 全部替换为品牌色
  $inner = [regex]::Replace($inner, '(?i)fill\s*=\s*"(?!none)[^"]*"', 'fill="' + $hex + '"')
  $inner = [regex]::Replace($inner, '(?i)stroke\s*=\s*"(?!none)[^"]*"', 'stroke="' + $hex + '"')
  # 等比缩放居中（透明背景，图形区域 112x112，边距 8）
  $s = 112.0 / [Math]::Max($w, $h)
  $tx = 8 + (112 - $w * $s) / 2 - $minX * $s
  $ty = 8 + (112 - $h * $s) / 2 - $minY * $s
  $sf = '{0:0.####}' -f $s; $txf = '{0:0.####}' -f $tx; $tyf = '{0:0.####}' -f $ty
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">' +
    '<g transform="translate(' + $txf + ' ' + $tyf + ') scale(' + $sf + ')" fill="' + $hex + '">' + $inner + '</g></svg>'
}

# ---------------- 深色图标可见性处理 ----------------
# 近黑中性色品牌图标（apple/X/Notion/Steam 等官方色为纯黑）在深色主题下不可见：
# 通道差 ≤26（中性色）且亮度 <0.22（近黑）时统一提亮为 #737373 中性灰，保证双主题可见；
# 彩色深色（slack 紫、openai 蓝紫等）保留原色
function Normalize-Hex([string]$hex) {
  if ($hex -notmatch '^#[0-9a-fA-F]{6}$') { return $hex }
  $r = [Convert]::ToInt32($hex.Substring(1, 2), 16)
  $g = [Convert]::ToInt32($hex.Substring(3, 2), 16)
  $b = [Convert]::ToInt32($hex.Substring(5, 2), 16)
  $max = [Math]::Max($r, [Math]::Max($g, $b)); $min = [Math]::Min($r, [Math]::Min($g, $b))
  $lum = (0.2126 * $r + 0.7152 * $g + 0.0722 * $b) / 255.0
  if (($max - $min) -le 26 -and $lum -lt 0.22) { return '#737373' }
  return $hex
}

# ---------------- 生成 ----------------
$results = @()
foreach ($e in $manifest) {
  $svg = $null; $hex = $null; $src = ''
  $siPath = if ($e.si) { Join-Path $siDir ("icons\" + $e.si + ".svg") } else { $null }
  if ($siPath -and (Test-Path -LiteralPath $siPath) -and $siHex.ContainsKey($e.si)) {
    $svg = [IO.File]::ReadAllText($siPath)
    if ($svg) { $hex = if ($e.force) { $e.hex } else { $siHex[$e.si] }; $src = "si:$($e.si)" }
  }
  if (-not $svg) {
    $drawable = Pick-Drawable $e.pkg $e.pref
    if ($drawable) {
      $lawnPath = Join-Path $lawnDir ("svgs\" + $drawable + ".svg")
      if (Test-Path -LiteralPath $lawnPath) {
        $svg = [IO.File]::ReadAllText($lawnPath)
        if ($svg) { $hex = $e.hex; $src = "lawn:$drawable" }
      }
    }
  }
  if (-not $svg) {
    $results += [pscustomobject]@{ file = $e.file; label = $e.label; status = 'MISS'; source = '' }
    continue
  }
  $hex = Normalize-Hex $hex
  $out = Convert-ToBrandSvg $svg $hex
  if (-not $out) {
    $results += [pscustomobject]@{ file = $e.file; label = $e.label; status = 'NOPATH'; source = $src }
    continue
  }
  [IO.File]::WriteAllText((Join-Path $outDir "$($e.file).svg"), $out, [Text.UTF8Encoding]::new($false))
  $results += [pscustomobject]@{ file = $e.file; label = $e.label; status = 'OK'; source = $src }
}

Write-Host ''
$results | Format-Table -AutoSize
$okCount = ($results | Where-Object status -eq 'OK').Count
$failCount = ($results | Where-Object { $_.status -ne 'OK' }).Count
Write-Host "完成: OK=$okCount, 失败=$failCount, 输出目录: $outDir"

# 写出成功清单供 BrandIcons.ets 注册表参考
$okManifest = @()
foreach ($e in $manifest) {
  $r = $results | Where-Object file -eq $e.file | Select-Object -First 1
  if ($r -and $r.status -eq 'OK') {
    $okManifest += [pscustomobject]@{ file = $e.file; group = $e.group; label = $e.label; kw = $e.kw; source = $r.source }
  }
}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'brand-icons-manifest.json'),
  ($okManifest | ConvertTo-Json -Depth 3), [Text.UTF8Encoding]::new($false))
Write-Host "清单已写入: $PSScriptRoot\brand-icons-manifest.json"
