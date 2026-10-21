#!/usr/bin/env node
/**
 * 下载品牌图标并生成图标选择器用的 SVG（品牌色图形，透明背景，128x128）
 * download-brand-icons.ps1 的跨平台 Node 等价版，逻辑与输出保持一致，共用 brand-icons-source.json。
 * 图标来源（许可均允许内嵌再分发）：
 *   - simple-icons (CC0):        ../其他库/simple-icons  (github.com/simple-icons/simple-icons)
 *   - lawnicons   (Apache-2.0):  ../其他库/lawnicons     (github.com/LawnchairLauncher/lawnicons)
 * 输出: entry/src/main/resources/rawfile/brand_icons/*.svg
 * 用法:
 *   node docs/scripts/download-brand-icons.mjs            # 生成全部
 *   node docs/scripts/download-brand-icons.mjs 微信        # 按关键词在两个图标库中查找
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(scriptDir, '..', '..');
const libRoot = path.resolve(root, '..');
const siDir = path.join(libRoot, '其他库', 'simple-icons');
const lawnDir = path.join(libRoot, '其他库', 'lawnicons');
const outDir = path.join(root, 'entry/src/main/resources/rawfile/brand_icons');
fs.mkdirSync(outDir, { recursive: true });

const siDataPath = path.join(siDir, 'data', 'simple-icons.json');
const appfilterPath = path.join(lawnDir, 'app', 'assets', 'appfilter.xml');
if (!fs.existsSync(siDataPath)) { throw new Error(`simple-icons 不存在: ${siDir}`); }
if (!fs.existsSync(appfilterPath)) { throw new Error(`lawnicons 不存在: ${lawnDir}`); }

const findArg = process.argv[2] ?? '';

// ---------------- 清单: file=输出文件名 group=分组 label=显示名 kw=搜索关键词 ----------------
// si=SI slug(优先，颜色取官方 hex) pkg=安卓包名(lawnicons 查找) pref=首选 drawable hex=lawn 来源品牌色
// 清单数据维护在 brand-icons-source.json（与 PowerShell 版 download-brand-icons.ps1 共用）
const manifest = JSON.parse(fs.readFileSync(path.join(scriptDir, 'brand-icons-source.json'), 'utf8'));

// ---------------- simple-icons 索引（title -> slug 派生 + slugs.md 例外） ----------------
console.log('读取 simple-icons 索引...');
const siJson = JSON.parse(fs.readFileSync(siDataPath, 'utf8'));
const slugsMd = fs.readFileSync(path.join(siDir, 'slugs.md'), 'utf8');
const slugException = new Map();
for (const m of slugsMd.matchAll(/^\|\s*`([^`]+)`\s*\|\s*`([a-z0-9\-]+)`\s*\|\s*$/gm)) {
  slugException.set(m[1], m[2]);
}
const siHex = new Map();
const siTitle = new Map();
for (const i of siJson) {
  const slug = slugException.has(i.title) ? slugException.get(i.title) : i.title.toLowerCase().replace(/[^a-z0-9]/g, '');
  if (slug) {
    siHex.set(slug, /^#/.test(i.hex) ? i.hex : '#' + i.hex);
    siTitle.set(slug, i.title);
  }
}
console.log(`  simple-icons: ${siHex.size} 个图标`);

// ---------------- lawnicons 索引（pkg -> drawable 计数） ----------------
console.log('读取 lawnicons appfilter.xml...');
const appfilter = fs.readFileSync(appfilterPath, 'utf8');
const pkgDrawables = new Map();
for (const m of appfilter.matchAll(/component="ComponentInfo\{([^/}]+)\/[^}]+\}"\s+drawable="([^"]+)"/g)) {
  const pkg = m[1];
  const d = m[2];
  if (!pkgDrawables.has(pkg)) { pkgDrawables.set(pkg, new Map()); }
  const set = pkgDrawables.get(pkg);
  set.set(d, (set.get(d) ?? 0) + 1);
}
console.log(`  lawnicons: ${pkgDrawables.size} 个应用包`);

function pickDrawable(pkg, pref) {
  if (!pkg || !pkgDrawables.has(pkg)) { return null; }
  const set = pkgDrawables.get(pkg);
  if (pref && set.has(pref)) { return pref; }
  let best = null;
  let bestCount = -1;
  for (const [k, count] of set) {
    if (count > bestCount) { best = k; bestCount = count; }
  }
  return best;
}

// ---------------- 查找模式 ----------------
if (findArg) {
  const kw = findArg.toLowerCase();
  console.log(`--- lawnicons 包名/drawable 匹配 '${findArg}' ---`);
  for (const [pkg, set] of pkgDrawables) {
    if (pkg.toLowerCase().includes(kw)) {
      const top = [...set.entries()].sort((a, b) => b[1] - a[1]).slice(0, 2).map(([k, c]) => `${k}x${c}`).join(',');
      console.log(`  ${pkg} -> ${top}`);
    }
  }
  console.log(`--- simple-icons 匹配 '${findArg}' ---`);
  for (const [slug, hex] of siHex) {
    if (slug.includes(kw) || (siTitle.get(slug) ?? '').toLowerCase().includes(kw)) {
      console.log(`  ${slug} (${siTitle.get(slug)}) ${hex}`);
    }
  }
  process.exit(0);
}

// ---------------- SVG 处理 ----------------
// 提取原 svg 内部全部图形（path/circle/rect/g 等，支持 stroke 型），上品牌色，
// 按原 viewBox 等比缩放到 112x112 居中放入 128x128 透明画布（边距 8）
// PS '{0:0.####}' 等价：最多 4 位小数，去尾零
function fmtNum(x) {
  return String(Number(x.toFixed(4)));
}

function convertToBrandSvg(svg, hex) {
  if (!svg) { return null; }
  const rootOpen = svg.match(/<svg\b[^>]*>/);
  if (!rootOpen) { return null; }
  const rootTag = rootOpen[0];
  const start = rootOpen.index + rootOpen[0].length;
  const end = svg.lastIndexOf('</svg>');
  if (end < start) { return null; }
  let inner = svg.substring(start, end);
  inner = inner.replace(/<!--.*?-->/gs, '');
  inner = inner.replace(/<title>.*?<\/title>/gs, '');
  inner = inner.replace(/<metadata>.*?<\/metadata>/gs, '');
  inner = inner.replace(/<desc>.*?<\/desc>/gs, '');
  if (!/<(path|circle|rect|ellipse|polygon|polyline|line|g)\b/.test(inner)) { return null; }
  // 原始 viewBox（缺省时用 width/height，再缺省按 24x24）
  let minX = 0.0;
  let minY = 0.0;
  let w = 24.0;
  let h = 24.0;
  const vb = rootTag.match(/viewBox="([\-0-9.eE]+)\s+([\-0-9.eE]+)\s+([\-0-9.eE]+)\s+([\-0-9.eE]+)"/);
  if (vb) {
    minX = parseFloat(vb[1]);
    minY = parseFloat(vb[2]);
    w = parseFloat(vb[3]);
    h = parseFloat(vb[4]);
  } else {
    const mw = rootTag.match(/width="([0-9.]+)/);
    const mh = rootTag.match(/height="([0-9.]+)/);
    if (mw && mh) { w = parseFloat(mw[1]); h = parseFloat(mh[1]); }
  }
  if (w <= 0 || h <= 0) { return null; }
  // 根节点 fill/stroke 继承（stroke 型图标常把 stroke/stroke-width 定义在根 <svg> 上，丢弃根节点后需补回）
  const rootFill = rootTag.match(/\bfill\s*=\s*"([^"]*)"/i)?.[1] ?? '';
  const rootStroke = rootTag.match(/\bstroke\s*=\s*"([^"]*)"/i)?.[1] ?? '';
  if (rootFill || rootStroke) {
    let wrapAttrs = '';
    if (rootFill.toLowerCase() === 'none') { wrapAttrs += ' fill="none"'; }
    else if (rootFill) { wrapAttrs += ` fill="${hex}"`; }
    if (rootStroke.toLowerCase() === 'none') { wrapAttrs += ' stroke="none"'; }
    else if (rootStroke) { wrapAttrs += ` stroke="${hex}"`; }
    for (const sa of ['stroke-width', 'stroke-linecap', 'stroke-linejoin', 'stroke-miterlimit',
      'stroke-dasharray', 'stroke-dashoffset', 'stroke-opacity']) {
      const mv = rootTag.match(new RegExp(`\\b${sa}\\s*=\\s*"([^"]*)"`, 'i'));
      if (mv) { wrapAttrs += ` ${sa}="${mv[1]}"`; }
    }
    inner = `<g${wrapAttrs}>${inner}</g>`;
  }
  // 上色：非 none 的 fill/stroke 全部替换为品牌色
  inner = inner.replace(/fill\s*=\s*"(?!none)[^"]*"/gi, `fill="${hex}"`);
  inner = inner.replace(/stroke\s*=\s*"(?!none)[^"]*"/gi, `stroke="${hex}"`);
  // 等比缩放居中（透明背景，图形区域 112x112，边距 8）
  const s = 112.0 / Math.max(w, h);
  const tx = 8 + (112 - w * s) / 2 - minX * s;
  const ty = 8 + (112 - h * s) / 2 - minY * s;
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 128 128" width="128" height="128">' +
    `<g transform="translate(${fmtNum(tx)} ${fmtNum(ty)}) scale(${fmtNum(s)})" fill="${hex}">${inner}</g></svg>`;
}

// ---------------- 深色图标可见性处理 ----------------
// 近黑中性色品牌图标（apple/X/Notion/Steam 等官方色为纯黑）在深色主题下不可见：
// 通道差 ≤26（中性色）且亮度 <0.22（近黑）时统一提亮为 #737373 中性灰，保证双主题可见；
// 彩色深色（slack 紫、openai 蓝紫等）保留原色
function normalizeHex(hex) {
  if (!/^#[0-9a-fA-F]{6}$/.test(hex)) { return hex; }
  const r = parseInt(hex.substring(1, 3), 16);
  const g = parseInt(hex.substring(3, 5), 16);
  const b = parseInt(hex.substring(5, 7), 16);
  const max = Math.max(r, g, b);
  const min = Math.min(r, g, b);
  const lum = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0;
  if ((max - min) <= 26 && lum < 0.22) { return '#737373'; }
  return hex;
}

// ---------------- 生成 ----------------
const results = [];
for (const e of manifest) {
  let svg = null;
  let hex = null;
  let src = '';
  const siPath = e.si ? path.join(siDir, 'icons', `${e.si}.svg`) : null;
  if (siPath && fs.existsSync(siPath) && siHex.has(e.si)) {
    svg = fs.readFileSync(siPath, 'utf8');
    if (svg) { hex = e.force ? e.hex : siHex.get(e.si); src = `si:${e.si}`; }
  }
  if (!svg) {
    const drawable = pickDrawable(e.pkg, e.pref);
    if (drawable) {
      const lawnPath = path.join(lawnDir, 'svgs', `${drawable}.svg`);
      if (fs.existsSync(lawnPath)) {
        svg = fs.readFileSync(lawnPath, 'utf8');
        if (svg) { hex = e.hex; src = `lawn:${drawable}`; }
      }
    }
  }
  if (!svg) {
    results.push({ file: e.file, label: e.label, status: 'MISS', source: '' });
    continue;
  }
  hex = normalizeHex(hex);
  const out = convertToBrandSvg(svg, hex);
  if (!out) {
    results.push({ file: e.file, label: e.label, status: 'NOPATH', source: src });
    continue;
  }
  fs.writeFileSync(path.join(outDir, `${e.file}.svg`), out);
  results.push({ file: e.file, label: e.label, status: 'OK', source: src });
}

console.log('');
for (const r of results) {
  if (r.status !== 'OK') { console.log(`${r.status}\t${r.file}\t${r.label}\t${r.source}`); }
}
const okCount = results.filter(r => r.status === 'OK').length;
const failCount = results.length - okCount;
console.log(`完成: OK=${okCount}, 失败=${failCount}, 输出目录: ${outDir}`);

// 写出成功清单供 BrandIcons.ets 注册表参考（与 PS 版 ConvertTo-Json 输出格式一致: CRLF, 无尾换行）
const okManifest = [];
for (const e of manifest) {
  const r = results.find(r => r.file === e.file);
  if (r && r.status === 'OK') {
    okManifest.push({ file: e.file, group: e.group, label: e.label, kw: e.kw, source: r.source });
  }
}
fs.writeFileSync(path.join(scriptDir, 'brand-icons-manifest.json'),
  JSON.stringify(okManifest, null, 2).replace(/\n/g, '\r\n'));
console.log(`清单已写入: ${path.join(scriptDir, 'brand-icons-manifest.json')}`);
