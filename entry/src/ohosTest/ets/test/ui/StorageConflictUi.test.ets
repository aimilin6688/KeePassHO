/**
 * 远程存储（SFTP/WebDAV/S3）保存冲突 UI 回归测试
 *
 * 覆盖保存冲突弹框四分支：合并 / 覆盖 / 重载 / 取消（弹框关闭，本地修改保留在内存）。
 * 每个存储独立真实数据库（Kdbx.create 运行时生成，主密码 KdbxModeTestHelper.DB_PASSWORD），
 * "他设备修改"由测试侧通过 IFileStorage 直连远端完成（KdbxModeTestHelper.writeRemoteModification），
 * 全程真实数据文件操作，不使用 mock。
 *
 * 前置环境（与单元测试回归环境一致）：
 *   1. docs/e2e/docker-compose.yml 三容器运行中（seaweedfs-e2e/webdav-e2e/sftp-e2e）
 *   2. 设备侧 rport 隧道已建：hdc rport tcp:2223 tcp:2222、tcp:9000 tcp:9000、tcp:8800 tcp:8800
 *   3. 应用为冷启动状态：先 hdc shell aa force-stop com.aimilin.keepassho 再执行
 *      （若应用残留运行中，startAbility 仅回前台不触发 onCreate 预载，种子不会生效）
 *
 * 运行方式（UI 套件不进全量回归，单独运行）：
 *   hdc shell aa test -b com.aimilin.keepassho -m entry_test \
 *     -s unittest OpenHarmonyTestRunner -s class StorageConflictUiTest -s timeout 900000
 *
 * 与 OpenDatabaseUiTest 相同的两个关键设计：
 *   1. 定位一律用控件 id（纯文本断言会被隐藏根栈干扰）
 *   2. 命中控件后校验其 bounds 落在窗口可视区内
 * 额外注意：EntryEdit 是压在 DatabaseView 之上的 NavDestination，
 * btn_add_fab 在编辑页仍可见，判断"回到数据库列表"必须用编辑页控件消失。
 * 冲突弹框为 promptAction 系统弹框（子窗口），文本匹配失败时回退到
 * 手工 E2E 校准过的等比例坐标（见 docs/ui/uitest-manual-driving-guide.md 阶段 F）。
 */

import { hilog } from '@kit.PerformanceAnalysisKit';
import { describe, beforeAll, afterAll, it, expect } from '@ohos/hypium';
import { Component, Driver, ON, On, Rect, UiWindow } from '@kit.TestKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Kdbx, KdbxCredentials, ProtectedValue } from 'kdbxweb';
import fileIo from '@ohos.file.fs';
import util from '@ohos.util';
import { FileContentInfo, StorageConfig, StorageType } from '../../../../main/ets/storage';
import { FTPStorageConfig, ProtocolType } from '../../../../main/ets/storage/ftp/FTPConfig';
import { WebDAVStorageConfig } from '../../../../main/ets/storage/webdav/WebDAVConfig';
import { S3TestConfig } from '../storage/s3/S3TestConfig';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

const DOMAIN: number = 0x0000;
const TAG: string = 'StorageConflictUiTest';

const BUNDLE_NAME: string = 'com.aimilin.keepassho';
const ABILITY_NAME: string = 'EntryAbility';

/** SFTP（podman sftp-e2e 容器，设备侧 rport 隧道 2223） */
const SFTP_HOST: string = '127.0.0.1';
const SFTP_PORT: number = 2223;
const SFTP_USER: string = 'e2e';
const SFTP_PASS: string = 'e2epass';
/** WebDAV（podman webdav-e2e 容器，8800） */
const WEBDAV_URL: string = 'http://127.0.0.1:8800/';
const WEBDAV_USER: string = 'e2e';
const WEBDAV_PASS: string = 'e2etest123';

/** 每次运行的唯一后缀，避免与历史运行遗留文件冲突 */
const RUN_TAG: string = String(Date.now());

/** 最近打开列表 preferences 文件（应用 UIAbilityContext 实际使用 el4 + per-module 路径，
 *  实测 EntryAbility 读取 dir=/data/storage/el4/base/haps/entry/preferences，见 init 日志） */
const RECENT_PREF_DIR: string = '/data/storage/el4/base/haps/entry/preferences';
const RECENT_PREF_FILE: string = RECENT_PREF_DIR + '/recent_files';

/** 冲突弹框文案（zh_CN / base 两语言兜底匹配） */
const CONFLICT_TITLE_ZH: string = '远端数据库已修改';
const CONFLICT_TITLE_EN: string = 'Remote database modified';
const MERGE_ZH: string = '合并';
const OVERWRITE_ZH: string = '覆盖';
const RELOAD_ZH: string = '重载';
const MERGE_EN: string = 'Merge';
const OVERWRITE_EN: string = 'Overwrite';
const RELOAD_EN: string = 'Reload';

/** 弹框按钮中心 y 坐标（绝对像素，弹框不随窗口高度缩放；
 *  实测 dump：合并[1434,1497]/覆盖[1582,1645]/重载[1730,1793]，与手工 E2E 一致） */
const BRANCH_ABS_Y: Record<string, number> = {
  'merge': 1465,
  'overwrite': 1613,
  'reload': 1761
};

/** 页面切换等待时长（ms） */
const SHORT_WAIT: number = 1500;
const NORMAL_WAIT: number = 3000;
/** 解锁含远端下载，单独放宽 */
const UNLOCK_WAIT: number = 20000;
/** 控件查找超时（ms） */
const FIND_TIMEOUT: number = 8000;
/** 保存触发远端下载后弹框出现的超时（ms） */
const DIALOG_WAIT: number = 20000;
/** 合并/覆盖上传、重载下载等远端操作的超时（ms） */
const REMOTE_OP_WAIT: number = 30000;
/** 最大返回次数 */
const MAX_BACK_TIMES: number = 6;

/** 窗口可视区（beforeAll 中填充） */
let windowRect: Rect = { left: 0, top: 0, right: 0, bottom: 0 };
let driver: Driver = Driver.create();

/**
 * 每个存储的测试目标
 */
class ConflictTarget {
  label: string;
  storageType: StorageType;
  fileName: string;
  remotePath: string;
  firstEntryTitle: string;
  fileManager: KdbxFileManager;
  storageConfig: StorageConfig;

  constructor(label: string, storageType: StorageType, remotePath: string, firstEntryTitle: string,
    fileManager: KdbxFileManager, storageConfig: StorageConfig) {
    this.label = label;
    this.storageType = storageType;
    this.remotePath = remotePath;
    this.fileName = remotePath.substring(remotePath.lastIndexOf('/') + 1);
    this.firstEntryTitle = firstEntryTitle;
    this.fileManager = fileManager;
    this.storageConfig = storageConfig;
  }
}

/**
 * 冲突分支执行结果（各 it 按分支语义断言）
 */
class ConflictResult {
  localTitle: string = '';
  remoteTitle: string = '';
  /** 他设备修改是否写回远端成功 */
  remoteModified: boolean = false;
  /** UI 添加本地条目并点击保存成功 */
  added: boolean = false;
  /** 冲突弹框出现 */
  dialogShown: boolean = false;
  /** 分支按钮点击/弹框取消成功 */
  branchHandled: boolean = false;
  /** 数据库列表可见本地条目 */
  uiLocalVisible: boolean = false;
  /** 数据库列表可见远端条目 */
  uiRemoteVisible: boolean = false;
  /** 远端文件包含本地条目 */
  remoteHasLocal: boolean = false;
  /** 远端文件包含远端条目 */
  remoteHasRemote: boolean = false;
}

let sftpTarget: ConflictTarget;
let appContext: common.Context;
let webdavTarget: ConflictTarget;
let s3Target: ConflictTarget;

/**
 * 空串构造绕过 Sm4 加密（encryptWithPrefix 对空串短路），再覆写明文字段。
 * 与 SFTPStorageRealFile.test / WebDav.test 中已验证的模式一致。
 */
function makeSftpConfig(): FTPStorageConfig {
  const config: FTPStorageConfig =
    new FTPStorageConfig('', '', '', { protocol: ProtocolType.SFTP, port: SFTP_PORT, timeout: 30000 });
  config.host = SFTP_HOST;
  config.username = SFTP_USER;
  config.password = SFTP_PASS;
  return config;
}

function makeWebdavConfig(): WebDAVStorageConfig {
  const config: WebDAVStorageConfig = new WebDAVStorageConfig(WEBDAV_URL, '', '');
  config.username = WEBDAV_USER;
  config.password = WEBDAV_PASS;
  return config;
}

/**
 * 创建真实数据库并上传到远端存储
 */
async function buildTarget(label: string, storageType: StorageType, remotePath: string,
  firstEntryTitle: string, storageConfig: StorageConfig): Promise<ConflictTarget> {
  const database: Kdbx = await KdbxModeTestHelper.createDatabase('UiConflict' + label, firstEntryTitle);
  const saved: ArrayBuffer = await database.save();
  const fileManager: KdbxFileManager = new KdbxFileManager(storageType, storageConfig);
  await fileManager.write(remotePath, saved);
  hilog.info(DOMAIN, TAG, 'target ready: %{public}s -> %{public}s (%{public}d bytes)',
    label, remotePath, saved.byteLength);
  return new ConflictTarget(label, storageType, remotePath, firstEntryTitle, fileManager, storageConfig);
}

/**
 * 读取远端文件并收集全部条目标题（远端内容核对用）
 */
async function readRemoteTitles(target: ConflictTarget): Promise<string[]> {
  try {
    const content: FileContentInfo = await target.fileManager.read(target.remotePath);
    const credentials: KdbxCredentials =
      new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
    const database: Kdbx = await Kdbx.load(content.content, credentials);
    return KdbxModeTestHelper.collectEntryTitles(database);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'read remote titles failed: %{public}s', JSON.stringify(err));
    return [];
  }
}

/**
 * XML 转义（preferences 文件为 XML 存储，值内引号等需转义）
 */
function xmlEscape(text: string): string {
  return text.replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

/**
 * 构造单条最近文件记录（纯字面量，规避 preferences API 在测试进程的
 * 401 "context is invalid" 与同进程多实例写入可见性问题，直接落盘 XML）
 */
function buildSeedRecord(target: ConflictTarget): Record<string, Object> {
  let config: Record<string, Object>;
  if (target.storageType === StorageType.FTP) {
    config = {
      'host': SFTP_HOST,
      'port': SFTP_PORT,
      'username': SFTP_USER,
      'password': SFTP_PASS,
      'timeout': 30000,
      'protocol': 'SFTP'
    };
  } else if (target.storageType === StorageType.WEBDAV) {
    config = {
      'url': WEBDAV_URL,
      'username': WEBDAV_USER,
      'password': WEBDAV_PASS,
      'timeout': 30000
    };
  } else {
    config = {
      'endpoint': S3TestConfig.ENDPOINT,
      'accessKeyId': S3TestConfig.ACCESS_KEY_ID,
      'secretAccessKey': S3TestConfig.SECRET_ACCESS_KEY,
      'region': S3TestConfig.REGION,
      'bucket': S3TestConfig.BUCKET,
      'pathStyle': S3TestConfig.PATH_STYLE,
      'timeout': 30000
    };
  }
  const record: Record<string, Object> = {
    'filePath': target.remotePath,
    'fileName': target.fileName,
    'storageType': target.storageType.toString(),
    'storageConfig': config
  };
  return record;
}

/**
 * 直接写 preferences XML 文件（绕开 preferences API 的进程内实例缓存问题：
 * 应用冷启动首次 getPreferencesSync 会从磁盘完整加载该文件）
 */
async function writeRecentFilesXml(records: Array<Record<string, Object>>): Promise<void> {
  const json: string = JSON.stringify(records);
  const xml: string = '<?xml version="1.0" encoding="UTF-8"?>\n' +
    '<preferences version="1.0"><string key="recent_files_list">' + xmlEscape(json) + '</string></preferences>';
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
 * 清理种子：从 preferences XML 中移除本次运行的记录
 */
async function removeSeedFromXml(targets: Array<ConflictTarget>): Promise<void> {
  try {
    const stat: fileIo.Stat = fileIo.statSync(RECENT_PREF_FILE);
    const file: fileIo.File = fileIo.openSync(RECENT_PREF_FILE, fileIo.OpenMode.READ_ONLY);
    const buf: ArrayBuffer = new ArrayBuffer(stat.size);
    fileIo.readSync(file.fd, buf);
    fileIo.closeSync(file);
    const content: string = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf));
    const start: number = content.indexOf('recent_files_list">') + 'recent_files_list">'.length;
    const end: number = content.indexOf('</string>');
    if (start < 'recent_files_list">'.length || end < 0) {
      return;
    }
    const raw: string = content.substring(start, end)
      .replace(/&quot;/g, '"').replace(/&apos;/g, '\'').replace(/&lt;/g, '<').replace(/&gt;/g, '>')
      .replace(/&amp;/g, '&');
    const parsed: Object = JSON.parse(raw);
    const list: Array<Record<string, Object>> = parsed as Array<Record<string, Object>>;
    const kept: Array<Record<string, Object>> = [];
    for (let i: number = 0; i < list.length; i++) {
      const filePath: string = list[i]['filePath'] as string;
      let isOurs: boolean = false;
      for (let j: number = 0; j < targets.length; j++) {
        if (filePath === targets[j].remotePath) {
          isOurs = true;
          break;
        }
      }
      if (!isOurs) {
        kept.push(list[i]);
      }
    }
    await writeRecentFilesXml(kept);
  } catch (err) {
    hilog.warn(DOMAIN, TAG, 'cleanup seed fail: %{public}s', (err as BusinessError).message);
  }
}

/**
 * 轮询等待最近文件种子真正落盘（写后立即读回校验）
 */
async function waitSeedOnDisk(sftpPath: string, timeout: number): Promise<boolean> {
  for (let waited: number = 0; waited <= timeout; waited += 500) {
    try {
      const stat: fileIo.Stat = fileIo.statSync(RECENT_PREF_FILE);
      const file: fileIo.File = fileIo.openSync(RECENT_PREF_FILE, fileIo.OpenMode.READ_ONLY);
      const buf: ArrayBuffer = new ArrayBuffer(stat.size);
      fileIo.readSync(file.fd, buf);
      fileIo.closeSync(file);
      const content: string = new util.TextDecoder('utf-8').decodeToString(new Uint8Array(buf));
      if (content.indexOf(sftpPath) >= 0) {
        hilog.info(DOMAIN, TAG, 'seed file content: %{public}s', content.substring(0, 300));
        return true;
      }
      hilog.warn(DOMAIN, TAG, 'seed not on disk yet (waited %{public}d ms), size=%{public}d',
        waited, stat.size);
    } catch (err) {
      hilog.warn(DOMAIN, TAG, 'seed file not ready (waited %{public}d ms): %{public}s',
        waited, (err as BusinessError).message);
    }
    await driver.delayMs(500);
  }
  return false;
}

/**
 * 判断控件 bounds 是否落在窗口可视区内
 */
function inWindow(r: Rect): boolean {
  return r.right > r.left && r.bottom > r.top &&
    r.left >= windowRect.left && r.right <= windowRect.right &&
    r.top >= windowRect.top && r.bottom <= windowRect.bottom;
}

/**
 * 在可见控件中查找第一个匹配项
 */
async function findVisible(on: On): Promise<Component | undefined> {
  try {
    const list: Array<Component> = await driver.findComponents(on);
    for (let i: number = 0; i < list.length; i++) {
      const r: Rect = await list[i].getBounds();
      if (inWindow(r)) {
        return list[i];
      }
    }
  } catch (err) {
    return undefined;
  }
  return undefined;
}

/**
 * 不做窗口过滤的查找（弹框位于子窗口时使用）
 */
async function findAnywhere(on: On): Promise<Component | undefined> {
  try {
    const list: Array<Component> = await driver.findComponents(on);
    if (list.length > 0) {
      return list[0];
    }
  } catch (err) {
    return undefined;
  }
  return undefined;
}

/**
 * 可见控件是否存在
 */
async function exists(on: On): Promise<boolean> {
  const found: Component | undefined = await findVisible(on);
  return found !== undefined;
}

/**
 * 轮询等待可见控件出现
 */
async function waitFor(on: On, timeout: number): Promise<boolean> {
  for (let waited: number = 0; waited <= timeout; waited += 500) {
    if (await exists(on)) {
      return true;
    }
    await driver.delayMs(500);
  }
  return false;
}

/**
 * 轮询等待可见控件消失
 */
async function waitGone(on: On, timeout: number): Promise<boolean> {
  for (let waited: number = 0; waited <= timeout; waited += 500) {
    if (!await exists(on)) {
      return true;
    }
    await driver.delayMs(500);
  }
  return false;
}

/**
 * 等待可见控件出现并点击
 */
async function click(on: On, timeout: number): Promise<boolean> {
  for (let waited: number = 0; waited <= timeout; waited += 500) {
    const target: Component | undefined = await findVisible(on);
    if (target !== undefined) {
      try {
        await target.click();
        return true;
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'click error: %{public}s', JSON.stringify(err));
        return false;
      }
    }
    await driver.delayMs(500);
  }
  hilog.error(DOMAIN, TAG, 'click timeout, no visible component');
  return false;
}

/**
 * 连续返回，直到目标控件消失（用于从编辑页回到数据库列表）
 */
async function pressBackUntilGone(on: On, maxTimes: number): Promise<boolean> {
  for (let i: number = 0; i < maxTimes; i++) {
    if (!await exists(on)) {
      return true;
    }
    await driver.pressBack();
    await driver.delayMs(SHORT_WAIT);
  }
  return !await exists(on);
}

/**
 * 冲突弹框是否出现（标题文本唯一；弹框可能在子窗口，找不到时放开窗口过滤）
 */
async function conflictDialogShown(): Promise<boolean> {
  if (await exists(ON.text(CONFLICT_TITLE_ZH))) {
    return true;
  }
  if (await exists(ON.text(CONFLICT_TITLE_EN))) {
    return true;
  }
  if (await findAnywhere(ON.text(CONFLICT_TITLE_ZH)) !== undefined) {
    return true;
  }
  if (await findAnywhere(ON.text(CONFLICT_TITLE_EN)) !== undefined) {
    return true;
  }
  return false;
}

async function waitConflictDialog(timeout: number): Promise<boolean> {
  for (let waited: number = 0; waited <= timeout; waited += 500) {
    if (await conflictDialogShown()) {
      return true;
    }
    await driver.delayMs(500);
  }
  return false;
}

async function conflictDialogAbsent(timeout: number): Promise<boolean> {
  for (let waited: number = 0; waited <= timeout; waited += 500) {
    if (!await conflictDialogShown()) {
      return true;
    }
    await driver.delayMs(500);
  }
  return false;
}

/**
 * 按文本查找弹框按钮。弹框位于独立子窗口，合并模式下被遮挡节点会被过滤，
 * 弹框自身节点可见；同名文本在隐藏根栈中已被过滤，无需宽度甄别。
 */
async function findDialogButton(zhText: string, enText: string): Promise<Component | undefined> {
  const candidates: Array<string> = [zhText, enText];
  for (let c: number = 0; c < candidates.length; c++) {
    const visible: Component | undefined = await findVisible(ON.text(candidates[c]));
    if (visible !== undefined) {
      return visible;
    }
    const anywhere: Component | undefined = await findAnywhere(ON.text(candidates[c]));
    if (anywhere !== undefined) {
      return anywhere;
    }
  }
  return undefined;
}

/**
 * 点击冲突弹框分支按钮；文本匹配失败时回退到等比例坐标
 */
async function clickConflictBranch(branch: string): Promise<boolean> {
  let zhText: string = MERGE_ZH;
  let enText: string = MERGE_EN;
  if (branch === 'overwrite') {
    zhText = OVERWRITE_ZH;
    enText = OVERWRITE_EN;
  } else if (branch === 'reload') {
    zhText = RELOAD_ZH;
    enText = RELOAD_EN;
  }
  const button: Component | undefined = await findDialogButton(zhText, enText);
  if (button !== undefined) {
    try {
      await button.click();
      hilog.info(DOMAIN, TAG, 'conflict branch %{public}s clicked by text', branch);
      return true;
    } catch (err) {
      hilog.error(DOMAIN, TAG, 'dialog button click error: %{public}s', JSON.stringify(err));
    }
  }
  // 坐标兜底：绝对像素坐标（实测弹框按钮不随窗口缩放），uitest 坐标必须为整数
  const absY: number = BRANCH_ABS_Y[branch];
  if (absY === undefined) {
    return false;
  }
  const x: number = Math.round((windowRect.left + windowRect.right) / 2);
  const y: number = Math.round(windowRect.top + absY);
  try {
    await driver.click(x, y);
    hilog.info(DOMAIN, TAG, 'conflict branch %{public}s clicked by coordinate (%{public}d, %{public}d)',
      branch, Math.round(x), Math.round(y));
    return true;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'coordinate click error: %{public}s', JSON.stringify(err));
    return false;
  }
}

/**
 * 取消冲突弹框（返回键关闭），验证弹框确实消失。
 * 若保存前输入法/安全键盘仍打开，第一次 Back 会先收键盘，需要重试。
 */
async function dismissConflictDialog(): Promise<boolean> {
  for (let i: number = 0; i < 3; i++) {
    await driver.pressBack();
    if (await conflictDialogAbsent(3000)) {
      return true;
    }
  }
  hilog.error(DOMAIN, TAG, 'conflict dialog still visible after 3 pressBack');
  return false;
}

/**
 * UI 添加本地条目：添加球 -> 添加条目 -> 填标题 -> 点保存
 */
async function addLocalEntryViaUi(localTitle: string): Promise<boolean> {
  // fab 位于可拖拽容器内（带 PanGesture），解锁/切换后首次点击可能被手势竞争吞掉；
  // 菜单展开时 fab 隐藏（visibility Hidden），重试点击不会误关菜单
  let menuOpened: boolean = false;
  for (let i: number = 0; i < 3; i++) {
    if (await exists(ON.id('btn_add_entry'))) {
      menuOpened = true;
      break;
    }
    if (!await click(ON.id('btn_add_fab'), FIND_TIMEOUT)) {
      hilog.error(DOMAIN, TAG, 'add entry fail: btn_add_fab click, try %{public}d', i);
      continue;
    }
    if (await waitFor(ON.id('btn_add_entry'), 3000)) {
      menuOpened = true;
      break;
    }
    hilog.info(DOMAIN, TAG, 'fab click no effect, retry %{public}d', i);
    await driver.delayMs(SHORT_WAIT);
  }
  if (!menuOpened) {
    hilog.error(DOMAIN, TAG, 'add entry fail: btn_add_entry not shown after fab clicks');
    return false;
  }
  if (!await click(ON.id('btn_add_entry'), FIND_TIMEOUT)) {
    hilog.error(DOMAIN, TAG, 'add entry fail: btn_add_entry click');
    return false;
  }
  if (!await waitFor(ON.id('input_entry_title'), FIND_TIMEOUT)) {
    hilog.error(DOMAIN, TAG, 'add entry fail: input_entry_title not shown');
    return false;
  }
  const input: Component | undefined = await findVisible(ON.id('input_entry_title'));
  if (input === undefined) {
    hilog.error(DOMAIN, TAG, 'add entry fail: input_entry_title not visible');
    return false;
  }
  try {
    await input.inputText(localTitle);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'input entry title error: %{public}s', JSON.stringify(err));
    return false;
  }
  await driver.delayMs(SHORT_WAIT);
  // 保存按钮仅在条目修改后可用，轮询确认可用后再点击
  for (let i: number = 0; i < 3; i++) {
    const saveBtn: Component | undefined = await findVisible(ON.id('btn_entry_save'));
    if (saveBtn === undefined) {
      await driver.delayMs(SHORT_WAIT);
      continue;
    }
    let enabled: boolean = false;
    try {
      enabled = await saveBtn.isEnabled();
    } catch (err) {
      enabled = false;
    }
    if (enabled) {
      try {
        await saveBtn.click();
        return true;
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'entry save click error: %{public}s', JSON.stringify(err));
        return false;
      }
    }
    await driver.delayMs(SHORT_WAIT);
  }
  hilog.error(DOMAIN, TAG, 'entry save button not enabled after input');
  return false;
}

/**
 * 冲突场景通用流程：
 * 他设备远端修改 -> UI 添加本地条目保存 -> 冲突弹框 -> 分支处理 -> UI/远端双端核对
 */
async function runConflictScenario(target: ConflictTarget, scenario: string,
  branch: string): Promise<ConflictResult> {
  const result: ConflictResult = new ConflictResult();
  result.localTitle = target.label + '-' + scenario + '-Local';
  result.remoteTitle = target.label + '-' + scenario + '-Remote';

  // 1. 模拟他设备：在远端当前内容基础上追加条目并写回
  try {
    await KdbxModeTestHelper.writeRemoteModification(target.fileManager, target.remotePath, result.remoteTitle);
    result.remoteModified = true;
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'remote modification failed: %{public}s', JSON.stringify(err));
    return result;
  }

  // 2. UI 添加本地条目并保存（保存时下载远端 -> hash 不一致 -> 冲突弹框）
  result.added = await addLocalEntryViaUi(result.localTitle);
  if (!result.added) {
    return result;
  }

  // 3. 等待冲突弹框
  result.dialogShown = await waitConflictDialog(DIALOG_WAIT);
  if (!result.dialogShown) {
    hilog.error(DOMAIN, TAG, 'conflict dialog not shown for %{public}s %{public}s',
      target.label, scenario);
    return result;
  }

  if (branch === 'cancel') {
    // 取消：弹框关闭，本地修改保留在内存，页面停留在编辑页
    result.branchHandled = await dismissConflictDialog();
    if (!result.branchHandled) {
      return result;
    }
    result.branchHandled = await pressBackUntilGone(ON.id('input_entry_title'), MAX_BACK_TIMES);
    if (!result.branchHandled) {
      return result;
    }
    result.uiLocalVisible = await waitFor(ON.text(result.localTitle), FIND_TIMEOUT);
    result.uiRemoteVisible = await exists(ON.text(result.remoteTitle));
  } else {
    // 合并/覆盖/重载：点击分支按钮后等待保存/重载完成并返回数据库列表
    result.branchHandled = await clickConflictBranch(branch);
    if (!result.branchHandled) {
      return result;
    }
    // 编辑页控件消失 = 保存完成已返回数据库列表（btn_add_fab 在编辑页仍可见，不能作判据）
    const leftEdit: boolean = await waitGone(ON.id('input_entry_title'), REMOTE_OP_WAIT);
    if (!leftEdit) {
      hilog.error(DOMAIN, TAG, 'entry edit page not left after %{public}s branch', branch);
      return result;
    }
    if (branch === 'merge') {
      result.uiLocalVisible = await waitFor(ON.text(result.localTitle), FIND_TIMEOUT);
      result.uiRemoteVisible = await waitFor(ON.text(result.remoteTitle), REMOTE_OP_WAIT);
    } else if (branch === 'overwrite') {
      result.uiLocalVisible = await waitFor(ON.text(result.localTitle), FIND_TIMEOUT);
      result.uiRemoteVisible = await exists(ON.text(result.remoteTitle));
    } else {
      result.uiRemoteVisible = await waitFor(ON.text(result.remoteTitle), REMOTE_OP_WAIT);
      result.uiLocalVisible = await exists(ON.text(result.localTitle));
    }
  }

  // 4. 远端内容核对
  const titles: string[] = await readRemoteTitles(target);
  result.remoteHasLocal = titles.indexOf(result.localTitle) >= 0;
  result.remoteHasRemote = titles.indexOf(result.remoteTitle) >= 0;
  hilog.info(DOMAIN, TAG,
    'scenario done: %{public}s-%{public}s local=%{public}s/%{public}s remote=%{public}s/%{public}s remoteTitles=%{public}s',
    target.label, scenario, String(result.uiLocalVisible), String(result.remoteHasLocal),
    String(result.uiRemoteVisible), String(result.remoteHasRemote), JSON.stringify(titles));
  return result;
}

/**
 * 在解锁页输入主密码并解锁，校验进入数据库列表且种子条目可见
 */
async function unlockViaUi(target: ConflictTarget): Promise<boolean> {
  const input: Component | undefined = await findVisible(ON.id('input_password'));
  if (input === undefined) {
    return false;
  }
  try {
    await input.inputText(KdbxModeTestHelper.DB_PASSWORD);
  } catch (err) {
    hilog.error(DOMAIN, TAG, 'input password error: %{public}s', JSON.stringify(err));
    return false;
  }
  await driver.delayMs(SHORT_WAIT);
  // 密码框会拉起系统安全键盘（独立窗口），其遮挡会导致底层控件在控件树中被过滤，
  // 必须先按 Back 收起键盘再点击解锁（与手工 E2E 流程一致）
  await driver.pressBack();
  await driver.delayMs(SHORT_WAIT);
  if (!await click(ON.id('btn_unlock'), FIND_TIMEOUT)) {
    return false;
  }
  if (!await waitFor(ON.id('btn_add_fab'), UNLOCK_WAIT)) {
    return false;
  }
  return await waitFor(ON.text(target.firstEntryTitle), FIND_TIMEOUT);
}

/**
 * 切换数据库：锁定 -> 关闭数据库 -> 首页 -> 最近打开 -> 目标文件 -> 解锁
 */
async function switchDatabaseTo(next: ConflictTarget): Promise<boolean> {
  if (!await click(ON.id('btn_lock_database'), FIND_TIMEOUT)) {
    return false;
  }
  if (!await waitFor(ON.id('btn_close_database'), FIND_TIMEOUT)) {
    return false;
  }
  if (!await click(ON.id('btn_close_database'), FIND_TIMEOUT)) {
    return false;
  }
  if (!await waitFor(ON.id('btn_recent_files'), FIND_TIMEOUT)) {
    return false;
  }
  if (!await click(ON.id('btn_recent_files'), FIND_TIMEOUT)) {
    return false;
  }
  if (!await waitFor(ON.id('recent_file_item'), FIND_TIMEOUT)) {
    return false;
  }
  if (!await click(ON.text(next.fileName), FIND_TIMEOUT)) {
    return false;
  }
  if (!await waitFor(ON.id('input_password'), FIND_TIMEOUT)) {
    return false;
  }
  return await unlockViaUi(next);
}

export default function StorageConflictUiTest(): void {
  describe('StorageConflictUiTest', () => {
    beforeAll(async () => {
      // 测试进程上下文注入（ResourceManager / 存储临时目录依赖）
      appContext = KdbxModeTestHelper.initContext();

      // 创建并上传三个存储的真实数据库（路径带 RUN_TAG，避免历史遗留冲突）
      sftpTarget = await buildTarget('Sftp', StorageType.FTP,
        '/data/ui-conflict-sftp-' + RUN_TAG + '.kdbx', 'Sftp-Seed', makeSftpConfig());
      webdavTarget = await buildTarget('Webdav', StorageType.WEBDAV,
        '/ui-conflict-webdav-' + RUN_TAG + '.kdbx', 'Webdav-Seed', makeWebdavConfig());
      s3Target = await buildTarget('S3', StorageType.S3,
        'ui-conflict-s3-' + RUN_TAG + '.kdbx', 'S3-Seed', S3TestConfig.getStorageConfig());

      // 种子注入最近打开列表：XML 数组顺序即读取顺序（无 unshift 语义），
      // files[0] 为冷启动自动打开目标 -> SFTP 必须在最前
      const records: Array<Record<string, Object>> = [];
      const targets: Array<ConflictTarget> = [sftpTarget, webdavTarget, s3Target];
      for (let i: number = 0; i < targets.length; i++) {
        records.push(buildSeedRecord(targets[i]));
      }
      await writeRecentFilesXml(records);
      const seededToDisk: boolean = await waitSeedOnDisk(sftpTarget.remotePath, 10000);
      hilog.info(DOMAIN, TAG, 'seed on disk=%{public}s', String(seededToDisk));

      // 冷启动应用
      const delegator: abilityDelegatorRegistry.AbilityDelegator =
        abilityDelegatorRegistry.getAbilityDelegator();
      await delegator.startAbility({
        bundleName: BUNDLE_NAME,
        abilityName: ABILITY_NAME
      });
      driver = Driver.create();
      await driver.delayMs(NORMAL_WAIT);
      try {
        const window: UiWindow = await driver.findWindow({ bundleName: BUNDLE_NAME });
        windowRect = await window.getBounds();
      } catch (err) {
        hilog.error(DOMAIN, TAG, 'get window bounds failed');
      }
      hilog.info(DOMAIN, TAG, 'started, window=%{public}s',
        JSON.stringify({
          left: windowRect.left, top: windowRect.top,
          right: windowRect.right, bottom: windowRect.bottom
        }));
      await driver.delayMs(SHORT_WAIT);
    });

    afterAll(async () => {
      // 清理本次运行注入的最近打开记录（直接改写 XML）
      const targets: Array<ConflictTarget> = [sftpTarget, webdavTarget, s3Target];
      await removeSeedFromXml(targets);
      await driver.delayMs(SHORT_WAIT);
      hilog.info(DOMAIN, TAG, 'StorageConflictUiTest finished');
    });

    /**
     * 01 冷启动：最近文件为 SFTP 库时自动进入解锁页，解锁进入数据库列表
     */
    it('01_sftp_open_database_after_cold_start', 0, async () => {
      const onUnlock: boolean = await waitFor(ON.id('input_password'), FIND_TIMEOUT * 2);
      const unlocked: boolean = onUnlock ? await unlockViaUi(sftpTarget) : false;
      hilog.info(DOMAIN, TAG, 'sftp open: unlockPage=%{public}s unlocked=%{public}s',
        String(onUnlock), String(unlocked));
      expect(onUnlock).assertTrue();
      expect(unlocked).assertTrue();
    });

    /**
     * 02 SFTP 冲突-合并：列表与远端均同时包含双方条目
     */
    it('02_sftp_conflict_merge', 0, async () => {
      const r: ConflictResult = await runConflictScenario(sftpTarget, 'Merge', 'merge');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertTrue();
      expect(r.uiRemoteVisible).assertTrue();
      expect(r.remoteHasLocal).assertTrue();
      expect(r.remoteHasRemote).assertTrue();
    });

    /**
     * 03 SFTP 冲突-覆盖：本地条目保留，远端修改被丢弃
     */
    it('03_sftp_conflict_overwrite', 0, async () => {
      const r: ConflictResult = await runConflictScenario(sftpTarget, 'Overwrite', 'overwrite');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertTrue();
      expect(r.uiRemoteVisible).assertFalse();
      expect(r.remoteHasLocal).assertTrue();
      expect(r.remoteHasRemote).assertFalse();
    });

    /**
     * 04 SFTP 冲突-重载：以远端为准，本地修改丢弃且不写远端
     */
    it('04_sftp_conflict_reload', 0, async () => {
      const r: ConflictResult = await runConflictScenario(sftpTarget, 'Reload', 'reload');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertFalse();
      expect(r.uiRemoteVisible).assertTrue();
      expect(r.remoteHasLocal).assertFalse();
      expect(r.remoteHasRemote).assertTrue();
    });

    /**
     * 05 SFTP 冲突-取消：弹框关闭后本地条目仍在，远端保持他设备版本
     */
    it('05_sftp_conflict_cancel', 0, async () => {
      const r: ConflictResult = await runConflictScenario(sftpTarget, 'Cancel', 'cancel');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertTrue();
      expect(r.uiRemoteVisible).assertFalse();
      expect(r.remoteHasLocal).assertFalse();
      expect(r.remoteHasRemote).assertTrue();
    });

    /**
     * 06 切换到 WebDAV 数据库：锁定->关闭->最近打开->解锁
     */
    it('06_switch_to_webdav_and_open', 0, async () => {
      const switched: boolean = await switchDatabaseTo(webdavTarget);
      hilog.info(DOMAIN, TAG, 'webdav open: switched=%{public}s', String(switched));
      expect(switched).assertTrue();
    });

    /**
     * 07 WebDAV 冲突-合并
     */
    it('07_webdav_conflict_merge', 0, async () => {
      const r: ConflictResult = await runConflictScenario(webdavTarget, 'Merge', 'merge');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertTrue();
      expect(r.uiRemoteVisible).assertTrue();
      expect(r.remoteHasLocal).assertTrue();
      expect(r.remoteHasRemote).assertTrue();
    });

    /**
     * 08 WebDAV 冲突-覆盖
     */
    it('08_webdav_conflict_overwrite', 0, async () => {
      const r: ConflictResult = await runConflictScenario(webdavTarget, 'Overwrite', 'overwrite');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertTrue();
      expect(r.uiRemoteVisible).assertFalse();
      expect(r.remoteHasLocal).assertTrue();
      expect(r.remoteHasRemote).assertFalse();
    });

    /**
     * 09 WebDAV 冲突-重载
     */
    it('09_webdav_conflict_reload', 0, async () => {
      const r: ConflictResult = await runConflictScenario(webdavTarget, 'Reload', 'reload');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertFalse();
      expect(r.uiRemoteVisible).assertTrue();
      expect(r.remoteHasLocal).assertFalse();
      expect(r.remoteHasRemote).assertTrue();
    });

    /**
     * 10 WebDAV 冲突-取消
     */
    it('10_webdav_conflict_cancel', 0, async () => {
      const r: ConflictResult = await runConflictScenario(webdavTarget, 'Cancel', 'cancel');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertTrue();
      expect(r.uiRemoteVisible).assertFalse();
      expect(r.remoteHasLocal).assertFalse();
      expect(r.remoteHasRemote).assertTrue();
    });

    /**
     * 11 切换到 S3 数据库：锁定->关闭->最近打开->解锁
     */
    it('11_switch_to_s3_and_open', 0, async () => {
      const switched: boolean = await switchDatabaseTo(s3Target);
      hilog.info(DOMAIN, TAG, 's3 open: switched=%{public}s', String(switched));
      expect(switched).assertTrue();
    });

    /**
     * 12 S3 冲突-合并
     */
    it('12_s3_conflict_merge', 0, async () => {
      const r: ConflictResult = await runConflictScenario(s3Target, 'Merge', 'merge');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertTrue();
      expect(r.uiRemoteVisible).assertTrue();
      expect(r.remoteHasLocal).assertTrue();
      expect(r.remoteHasRemote).assertTrue();
    });

    /**
     * 13 S3 冲突-覆盖
     */
    it('13_s3_conflict_overwrite', 0, async () => {
      const r: ConflictResult = await runConflictScenario(s3Target, 'Overwrite', 'overwrite');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertTrue();
      expect(r.uiRemoteVisible).assertFalse();
      expect(r.remoteHasLocal).assertTrue();
      expect(r.remoteHasRemote).assertFalse();
    });

    /**
     * 14 S3 冲突-重载
     */
    it('14_s3_conflict_reload', 0, async () => {
      const r: ConflictResult = await runConflictScenario(s3Target, 'Reload', 'reload');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertFalse();
      expect(r.uiRemoteVisible).assertTrue();
      expect(r.remoteHasLocal).assertFalse();
      expect(r.remoteHasRemote).assertTrue();
    });

    /**
     * 15 S3 冲突-取消
     */
    it('15_s3_conflict_cancel', 0, async () => {
      const r: ConflictResult = await runConflictScenario(s3Target, 'Cancel', 'cancel');
      expect(r.remoteModified).assertTrue();
      expect(r.added).assertTrue();
      expect(r.dialogShown).assertTrue();
      expect(r.branchHandled).assertTrue();
      expect(r.uiLocalVisible).assertTrue();
      expect(r.uiRemoteVisible).assertFalse();
      expect(r.remoteHasLocal).assertFalse();
      expect(r.remoteHasRemote).assertTrue();
    });
  });
}
