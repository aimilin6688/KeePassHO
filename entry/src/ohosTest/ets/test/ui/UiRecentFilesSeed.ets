/**
 * 最近打开列表（recent_files preferences XML）种子注入共享工具（UI 套件复用）。
 *
 * 设计要点：
 * - 纯字面量直接落盘 XML：绕过 preferences API 在测试进程的
 *   401 "context is invalid" 与同进程多实例写入可见性问题；
 *   应用冷启动首次 getPreferencesSync 会从磁盘完整加载该文件
 * - key 与 RecentFilesService.RECENT_FILES_KEY 保持一致（recent_files_list）
 * - 记录字段与 RecentFile 接口对齐：filePath / fileName / storageType / storageConfig
 *   （storageType 为字符串枚举，JSON.parse 反序列化直接可用）
 *
 * 使用方：
 * - OpenDatabaseUiTest：本地库 test-1.kdbx 种子（upsertRecordToFront 置顶）
 * - StorageConflictUiTest：SFTP/WebDAV/S3 远程库种子（writeRecentFilesXml 覆盖式）
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';
import fileIo from '@ohos.file.fs';
import util from '@ohos.util';

const DOMAIN: number = 0x0000;
const TAG: string = 'UiRecentFilesSeed';

/** 最近打开列表 preferences 文件（应用 UIAbilityContext 实际使用 el4 + per-module 路径，
 *  实测 EntryAbility 读取 dir=/data/storage/el4/base/haps/entry/preferences，见 init 日志） */
export const RECENT_PREF_DIR: string = '/data/storage/el4/base/haps/entry/preferences';
export const RECENT_PREF_FILE: string = RECENT_PREF_DIR + '/recent_files';

/** preferences 文件内的 key（与 RecentFilesService.RECENT_FILES_KEY 一致） */
const RECENT_FILES_KEY: string = 'recent_files_list';

/** XML 转义（preferences 文件为 XML 存储，值内引号等需转义） */
export function xmlEscape(text: string): string {
  return text.replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/** 同步等待（Driver 不可用处的轻量 sleep） */
function sleep(ms: number): Promise<void> {
  return new Promise<void>((resolve) => {
    setTimeout(() => {
      resolve();
    }, ms);
  });
}

/** 读取现有全部记录（文件不存在或无记录时返回空数组） */
export async function readRecentRecords(): Promise<Array<Record<string, Object>>> {
  try {
    const stat: fileIo.Stat = fileIo.statSync(RECENT_PREF_FILE);
    const file: fileIo.File = fileIo.openSync(RECENT_PREF_FILE, fileIo.OpenMode.READ_ONLY);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buf);
    fileIo.closeSync(file);
    const content: string = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf));
    const keyOpen: string = RECENT_FILES_KEY + '">';
    const start: number = content.indexOf(keyOpen) + keyOpen.length;
    const end: number = content.indexOf('</string>');
    if (start < keyOpen.length || end < 0 || end <= start) {
      return [];
    }
    const raw: string = content.substring(start, end)
      .replace(/&quot;/g, '"').replace(/&apos;/g, '\'').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
    const parsed: Object = JSON.parse(raw);
    return parsed as Array<Record<string, Object>>;
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'read recent records failed: %{public}s', (err as BusinessError).message);
    return [];
  }
}

/** 整体写入记录数组（覆盖式） */
export async function writeRecentFilesXml(records: Array<Record<string, Object>>): Promise<void> {
  const json: string = JSON.stringify(records);
  const xml: string = '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<preferences version="1.0"><string key="' + RECENT_FILES_KEY + '">' + xmlEscape(json) +
    '</string></preferences>';
  // 全新安装时 el4/haps/entry 上级目录均不存在（平时由应用首次写 preferences 时创建），
  // 单级 mkdir 会 ENOENT，必须递归创建
  try {
    fileIo.mkdirSync(RECENT_PREF_DIR, true);
  } catch (err) {
    // 目录已存在时忽略
  }
  const file: fileIo.File =
    fileIo.openSync(RECENT_PREF_FILE, fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
  fileIo.writeSync(file.fd, xml);
  fileIo.closeSync(file);
  hilog.info(DOMAIN, TAG, 'recent_files xml written to %{public}s, size=%{public}d', RECENT_PREF_FILE, xml.length);
}

/**
 * 单条记录置顶合并（同 filePath 去重后 unshift）。
 * XML 数组顺序即读取顺序（无 unshift 语义），files[0] 为冷启动自动打开目标。
 */
export async function upsertRecordToFront(record: Record<string, Object>): Promise<void> {
  const filePath: string = record['filePath'] as string;
  const records: Array<Record<string, Object>> = await readRecentRecords();
  const kept: Array<Record<string, Object>> = [];
  for (let i: number = 0; i < records.length; i++) {
    if (records[i]['filePath'] !== filePath) {
      kept.push(records[i]);
    }
  }
  kept.unshift(record);
  await writeRecentFilesXml(kept);
}

/** 按 filePath 移除记录（种子清理用） */
export async function removeRecordsByPath(paths: Array<string>): Promise<void> {
  const records: Array<Record<string, Object>> = await readRecentRecords();
  const kept: Array<Record<string, Object>> = [];
  for (let i: number = 0; i < records.length; i++) {
    const filePath: string = records[i]['filePath'] as string;
    if (paths.indexOf(filePath) < 0) {
      kept.push(records[i]);
    }
  }
  await writeRecentFilesXml(kept);
}

/** 轮询等待最近文件种子真正落盘（写后立即读回校验） */
export async function waitSeedOnDisk(path: string, timeout: number): Promise<boolean> {
  for (let waited: number = 0; waited <= timeout; waited += 500) {
    try {
      const stat: fileIo.Stat = fileIo.statSync(RECENT_PREF_FILE);
      const file: fileIo.File = fileIo.openSync(RECENT_PREF_FILE, fileIo.OpenMode.READ_ONLY);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const content: string = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf));
      if (content.indexOf(path) >= 0) {
        hilog.info(DOMAIN, TAG, 'seed file content: %{public}s', content.substring(0, 300));
        return true;
      }
      hilog.warn(DOMAIN, TAG, 'seed not on disk yet (waited %{public}d ms), size=%{public}d',
        waited, stat.size);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'seed file not ready (waited %{public}d ms): %{public}s',
        waited, (err as BusinessError).message);
    }
    await sleep(500);
  }
  return false;
}
