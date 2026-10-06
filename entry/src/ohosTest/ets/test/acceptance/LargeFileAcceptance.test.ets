import { describe, expect, it, beforeAll } from '@ohos/hypium';
import { Kdbx, KdbxCredentials, KdbxUuid, ProtectedValue, Consts, KdbxError, KdbxEntry,
  KdbxBinaryDiskRef, KdbxBinaryWithHash, sha256FileRegion } from 'kdbxweb';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { worker } from '@kit.ArkTS';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';
import { SessionFileService } from '../../../../main/ets/services/kdbx/SessionFileService';
import { TempFileSweeper } from '../../../../main/ets/services/kdbx/TempFileSweeper';
import { AttachmentCacheService } from '../../../../main/ets/services/kdbx/AttachmentCacheService';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import { MessageType, SuccessMessage, WorkerMessage } from '../../../../main/ets/workers/WorkerParam';
import { ConflictStrategy } from '../../../../main/ets/workers/DatabaseSaveWorkerParam';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'LargeFileAcceptance';
const CHUNK = 8 * 1024 * 1024;
const PATTERN_BLOCK = 1024 * 1024;
const BIG_TIMEOUT = 600000;
const HEAVY_FLAG = '/heavy-acceptance.flag';
let gFilesDir: string = '';
let gCacheDir: string = '';

/** 1MB 基块（构建一次，后续 memcopy 拼装，避免逐字节大循环） */
function buildPatternBlock(): Uint8Array {
  const block = new Uint8Array(PATTERN_BLOCK);
  for (let i = 0; i < block.length; i++) {
    block[i] = (i * 31 + 7) % 256;
  }
  return block;
}

function patternByte(offset: number): number {
  return (offset * 31 + 7) % 256;
}

async function writePatternFile(path: string, size: number): Promise<void> {
  const block = buildPatternBlock();
  const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  try {
    for (let offset = 0; offset < size; offset += CHUNK) {
      const len = Math.min(CHUNK, size - offset);
      const buf = new ArrayBuffer(len);
      const view = new Uint8Array(buf);
      let filled = 0;
      while (filled < len) {
        const n = Math.min(PATTERN_BLOCK, len - filled);
        view.set(block.subarray(0, n), filled);
        filled += n;
      }
      await fs.write(file.fd, buf);
    }
    await fs.fsync(file.fd);
  } finally {
    await fs.close(file.fd);
  }
}

/**
 * 生成测试库（幂等缓存：产物存在即跳过重新生成，重复运行套件时秒级返回）。
 * 全程流式：附件经 sha256FileRegion + putFromFileRegion 落 AS，KDBX 经 saveToFile 落盘。
 */
async function genDb(name: string, attachSize: number, entryCount: number,
  attachEvery: number, notesKB: number): Promise<string> {
  const x3 = gFilesDir + '/gen-' + name + '.kdbx';
  const marker = gFilesDir + '/gen-' + name + '.done';
  try {
    if (fs.accessSync(marker, fs.AccessModeType.EXIST) && fs.accessSync(x3, fs.AccessModeType.EXIST)) {
      hilog.info(DOMAIN, TAG, 'genDb %{public}s: cached', name);
      return x3;
    }
  } catch (e) {
    // 无缓存，继续生成
  }
  const t0 = Date.now();
  const cred = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
  const db = Kdbx.create(cred, name);
  db.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
  db.binaries.store = AttachmentCacheService.getStore();

  let attachHash = '';
  let attachLen = 0;
  if (attachSize > 0) {
    const attachPath = gFilesDir + '/gen-attach-' + name + '.bin';
    await writePatternFile(attachPath, attachSize);
    const fd = (await fs.open(attachPath, fs.OpenMode.READ_ONLY)).fd;
    try {
      attachHash = await sha256FileRegion(fd, 0, attachSize);
      await db.binaries.store!.putFromFileRegion(attachHash, fd, 0, attachSize);
    } finally {
      await fs.close(fd);
    }
    try { fs.unlinkSync(attachPath); } catch { /* ignore */ }
    attachLen = attachSize;
    const diskRef = new KdbxBinaryDiskRef(attachHash, attachLen, false);
    db.binaries.addWithHash({ hash: attachHash, value: diskRef });
    const first = db.createEntry(db.getDefaultGroup());
    first.fields.set('Title', 'attach-entry');
    first.binaries.set('attach.bin', { hash: attachHash, value: diskRef });
  }

  const notes = notesKB > 0 ? 'note-line-0123456789-'.repeat(notesKB * 32) : '';
  for (let i = 0; i < entryCount; i++) {
    const entry = db.createEntry(db.getDefaultGroup());
    entry.fields.set('Title', 'entry-' + i);
    if (notesKB > 0) {
      entry.fields.set('Notes', notes);
    }
    if (attachSize > 0 && i > 0 && i % attachEvery === 0) {
      entry.binaries.set('attach.bin', { hash: attachHash, value: new KdbxBinaryDiskRef(attachHash, attachLen, false) });
    }
  }

  const x1 = gCacheDir + '/save_x1_gen_' + Date.now() + '.tmp';
  const x2 = gCacheDir + '/save_x2_gen_' + Date.now() + '.tmp';
  try {
    await db.saveToFile(x3, { x1Path: x1, x2Path: x2 });
  } finally {
    try { fs.unlinkSync(x1); } catch { /* ignore */ }
    try { fs.unlinkSync(x2); } catch { /* ignore */ }
  }
  const markerFile = await fs.open(marker, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
  await fs.close(markerFile.fd);
  hilog.info(DOMAIN, TAG, 'genDb %{public}s: %{public}d ms, size=%{public}d',
    name, Date.now() - t0, fs.statSync(x3).size);
  return x3;
}

async function loadViaWorker(dbPath: string, password: string, timeoutMs: number): Promise<Kdbx> {
  const w: worker.ThreadWorker = KdbxModeTestHelper.createLoadWorker();
  try {
    const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, dbPath.substring(dbPath.lastIndexOf('/') + 1),
      password);
    const pending = KdbxModeTestHelper.waitWorkerResult(w, timeoutMs);
    w.postMessage(JSON.stringify(loadParam));
    const message: WorkerMessage = await pending;
    expect(message.type).assertEqual(MessageType.SUCCESS);
    const success = message as SuccessMessage;
    const m0Path: string | undefined = success.m0Path;
    expect(typeof m0Path === 'string' && m0Path.length > 0).assertTrue();
    if (!m0Path) {
      throw new Error('no m0 path');
    }
    const bytes: ArrayBuffer = await SessionFileService.unwrapFromFile(m0Path);
    SessionFileService.removeFile(m0Path);
    return await KdbxUtils.arrayBufferToKdbx(bytes,
      KdbxModeTestHelper.makeLoadParam(dbPath, 'a.kdbx', password));
  } finally {
    w.terminate();
  }
}

async function saveViaWorker(model: Kdbx, dbPath: string, version: string | null,
  contentHash: string | null, timeoutMs: number): Promise<SuccessMessage> {
  const saveMessage = KdbxModeTestHelper.makeSaveMessage(model, dbPath,
    dbPath.substring(dbPath.lastIndexOf('/') + 1), version, contentHash, ConflictStrategy.AUTO);
  saveMessage.data = await KdbxUtils.kdbxToArrayBuffer(model);
  const w: worker.ThreadWorker = KdbxModeTestHelper.createSaveWorker();
  try {
    const pending = KdbxModeTestHelper.waitWorkerResult(w, timeoutMs);
    w.postMessage(saveMessage, [saveMessage.data as ArrayBuffer]);
    const message: WorkerMessage = await pending;
    expect(message.type).assertEqual(MessageType.SUCCESS);
    return message as SuccessMessage;
  } finally {
    w.terminate();
  }
}

function countEntries(db: Kdbx): number {
  let n = 0;
  for (const g of db.groups) {
    n += g.entries.length;
  }
  return n;
}

function findEntryByTitle(db: Kdbx, title: string): KdbxEntry | undefined {
  for (const g of db.groups) {
    for (const e of g.entries) {
      if (e.fields.get('Title') === title) {
        return e;
      }
    }
  }
  return undefined;
}

function listPipelineTemps(): string[] {
  const found: string[] = [];
  const names: string[] = fs.listFileSync(gCacheDir);
  for (const name of names) {
    if (TempFileSweeper.isPipelineTemp(name)) {
      found.push(name);
    }
  }
  return found;
}

function listSessionM0Files(): string[] {
  const found: string[] = [];
  const sessionDir = SessionFileService.getSessionDir();
  const names: string[] = fs.listFileSync(sessionDir);
  for (const name of names) {
    if (name.startsWith('m0_')) {
      found.push(name);
    }
  }
  return found;
}

function heavyEnabled(): boolean {
  try {
    return fs.accessSync(gCacheDir + HEAVY_FLAG, fs.AccessModeType.EXIST);
  } catch (e) {
    return false;
  }
}

/**
 * §10/§12 大文件验收测试。
 * 快速用例（默认全量运行）覆盖：生成幂等缓存、4MB 磁盘化边界、共享附件池、
 * 保存→重载往返、None 压缩、M0 消费、临时文件清理、错误密码、CP2' 守卫、残留清扫。
 * 重载用例（att-100/300/500）需显式开启：先运行 heavy-flag-on，再运行本套件，
 * 结束后 heavy-flag-off 恢复（配合主机侧 hidumper 200ms RSS 采样）。
 */
export default function LargeFileAcceptanceTest() {
  describe('LargeFileAcceptanceTest', () => {
    beforeAll(() => {
      KdbxModeTestHelper.initContext();
      const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      gFilesDir = appContext.filesDir;
      gCacheDir = appContext.cacheDir;
    });

    // ==================== 快速用例（全量运行） ====================

    it('gen-cache: idempotent generation skips rewrite', 0, async () => {
      const first = await genDb('gencache', 1024 * 1024, 5, 0, 0);
      const stat1 = fs.statSync(first);
      const t0 = Date.now();
      const second = await genDb('gencache', 1024 * 1024, 5, 0, 0);
      const elapsed = Date.now() - t0;
      expect(second).assertEqual(first);
      const stat2 = fs.statSync(second);
      expect(stat2.size).assertEqual(stat1.size);
      // 缓存命中应远快于重新生成（<1s）
      expect(elapsed < 1000).assertTrue();
    });

    it('attach-boundary: 4MB-1 memory mode vs 4MB disk-ref mode', 0, async () => {
      // 4MB-1：低于 LARGE_BINARY_STREAM_THRESHOLD，加载后附件驻内存
      const smallPath = await genDb('att3m', 4 * 1024 * 1024 - 1, 3, 0, 0);
      const smallDb = await loadViaWorker(smallPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      const smallEntry = findEntryByTitle(smallDb, 'attach-entry');
      expect(smallEntry !== undefined).assertTrue();
      const smallBin = smallEntry!.binaries.get('attach.bin') as KdbxBinaryWithHash;
      const smallIsDisk = smallBin!.value instanceof KdbxBinaryDiskRef;
      expect(smallIsDisk).assertFalse();

      // 4MB 整：达到阈值，加载后为磁盘引用
      const bigPath = await genDb('att4m', 4 * 1024 * 1024, 3, 0, 0);
      const bigDb = await loadViaWorker(bigPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      const bigEntry = findEntryByTitle(bigDb, 'attach-entry');
      expect(bigEntry !== undefined).assertTrue();
      const bigBin = bigEntry!.binaries.get('attach.bin') as KdbxBinaryWithHash;
      expect(bigBin!.value instanceof KdbxBinaryDiskRef).assertTrue();
    }, BIG_TIMEOUT);

    it('shared-pool: same content across entries yields single pool entry', 0, async () => {
      const dbPath = await genDb('sharedpool', 1024 * 1024, 6, 2, 0);
      const db = await loadViaWorker(dbPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      // 3 个条目引用同一附件（entry-2/entry-4 + attach-entry）
      const hashes: string[] = [];
      for (const g of db.groups) {
        for (const e of g.entries) {
          const bin = e.binaries.get('attach.bin') as KdbxBinaryWithHash | undefined;
          if (bin) {
            hashes.push(bin.hash);
          }
        }
      }
      expect(hashes.length === 3).assertTrue();
      expect(hashes[0] === hashes[1] && hashes[1] === hashes[2]).assertTrue();
      expect(db.binaries.getAllWithHashes().length === 1).assertTrue();
    }, BIG_TIMEOUT);

    it('roundtrip: save then reload keeps entries and attachment content', 0, async () => {
      const dbPath = await genDb('roundtrip', 2 * 1024 * 1024, 50, 10, 0);
      const model = await loadViaWorker(dbPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      const expectedCount = countEntries(model);
      // 新增标记条目（幂等：不依赖既有条目名，缓存命中也可重复运行）
      const markerTitle = 'rt-marker-' + Date.now();
      const markerEntry = model.createEntry(model.getDefaultGroup());
      markerEntry.fields.set('Title', markerTitle);
      const success = await saveViaWorker(model, dbPath, null, null, BIG_TIMEOUT);
      expect(success.contentHash !== null && success.contentHash !== '').assertTrue();

      const reloaded = await loadViaWorker(dbPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      expect(countEntries(reloaded) === expectedCount + 1).assertTrue();
      expect(findEntryByTitle(reloaded, markerTitle) !== undefined).assertTrue();
      // 2MB < 4MB 阈值：重载后为内存模式（ArrayBuffer），内容逐字节校验
      const bin = findEntryByTitle(reloaded, 'attach-entry')!.binaries.get('attach.bin') as KdbxBinaryWithHash;
      expect(bin !== undefined).assertTrue();
      const value = bin!.value;
      expect(value instanceof ArrayBuffer).assertTrue();
      const bytes = new Uint8Array(value as ArrayBuffer);
      expect(bytes.length).assertEqual(2 * 1024 * 1024);
      let prefixOk = true;
      for (let i = 0; i < 64; i++) {
        if (bytes[i] !== patternByte(i)) {
          prefixOk = false;
          break;
        }
      }
      expect(prefixOk).assertTrue();
    }, BIG_TIMEOUT);

    it('compression-none: roundtrip via worker pipeline', 0, async () => {
      const cred = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
      const db = Kdbx.create(cred, 'nozip');
      db.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
      db.header.compression = Consts.CompressionAlgorithm.None;
      for (let i = 0; i < 10; i++) {
        const entry = db.createEntry(db.getDefaultGroup());
        entry.fields.set('Title', 'entry-' + i);
      }
      const dbPath = gFilesDir + '/gen-nozip.kdbx';
      const x1 = gCacheDir + '/save_x1_gen_' + Date.now() + '.tmp';
      const x2 = gCacheDir + '/save_x2_gen_' + Date.now() + '.tmp';
      try {
        await db.saveToFile(dbPath, { x1Path: x1, x2Path: x2 });
      } finally {
        try { fs.unlinkSync(x1); } catch { /* ignore */ }
        try { fs.unlinkSync(x2); } catch { /* ignore */ }
      }
      const loaded = await loadViaWorker(dbPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      expect(countEntries(loaded) === 10).assertTrue();
    }, BIG_TIMEOUT);

    it('m0-consumed: session m0 files removed after load', 0, async () => {
      // 全量混跑时前序套件被 terminate 的 Worker 可能遗留 m0 文件（由清扫负责），
      // 本用例语义为「本次加载零残留」：只对比本次加载前后的 m0 增量
      const before = listSessionM0Files();
      const dbPath = await genDb('m0consume', 256 * 1024, 3, 0, 0);
      await loadViaWorker(dbPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      const after = listSessionM0Files();
      const leftover = after.filter((name) => !before.includes(name));
      expect(leftover.length === 0).assertTrue();
    }, BIG_TIMEOUT);

    it('save-cleanup: worker save leaves no pipeline temps', 0, async () => {
      const dbPath = await genDb('saveclean', 256 * 1024, 5, 0, 0);
      const model = await loadViaWorker(dbPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      await saveViaWorker(model, dbPath, null, null, BIG_TIMEOUT);
      // worker 的 finally 清理晚于 SUCCESS 消息送达，轮询等待至多 3s
      let remaining = listPipelineTemps();
      for (let i = 0; i < 30 && remaining.length > 0; i++) {
        await new Promise<void>((resolve) => setTimeout(resolve, 100));
        remaining = listPipelineTemps();
      }
      expect(remaining.length === 0).assertTrue();
    }, BIG_TIMEOUT);

    it('wrong-password: load error path without crash', 0, async () => {
      const dbPath = await genDb('wrongpass', 256 * 1024, 3, 0, 0);
      const w: worker.ThreadWorker = KdbxModeTestHelper.createLoadWorker();
      try {
        const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'wrongpass.kdbx', 'definitely-wrong');
        const pending = KdbxModeTestHelper.waitWorkerResult(w, BIG_TIMEOUT);
        w.postMessage(JSON.stringify(loadParam));
        const message: WorkerMessage = await pending;
        expect(message.type).assertEqual(MessageType.ERROR);
      } finally {
        w.terminate();
      }
    }, BIG_TIMEOUT);

    it('cp2-guard: oversized xml rejected without crash', 0, async () => {
      // 2000 条 × 1KB Notes → XML ~2-3MB，超过 1MB 测试上限，必须明确拒绝
      const dbPath = await genDb('cp2src', 0, 2000, 0, 1);
      const cred = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
      const t1 = gCacheDir + '/cp2_t1.tmp';
      const t2 = gCacheDir + '/cp2_t2.tmp';
      try {
        await Kdbx.loadFromFile(dbPath, cred, {
          t1Path: t1, t2Path: t2, maxDecompressedBytes: 1024 * 1024
        });
        expect(false).assertTrue();
      } catch (e) {
        expect(e instanceof KdbxError).assertTrue();
        expect((e as KdbxError).code).assertEqual(Consts.ErrorCodes.DecompressedTooLarge);
      } finally {
        try { fs.unlinkSync(t1); } catch { /* ignore */ }
        try { fs.unlinkSync(t2); } catch { /* ignore */ }
      }
    }, BIG_TIMEOUT);

    it('residual: sweep cleans pipeline temp files', 0, async () => {
      const stale: string[] = [];
      stale.push(gCacheDir + '/load_t0_stale_' + Date.now() + '.tmp');
      stale.push(gCacheDir + '/save_x3_stale_' + Date.now() + '.tmp');
      stale.push(gCacheDir + '/merge_t1_stale_' + Date.now() + '.tmp');
      for (const p of stale) {
        const f = await fs.open(p, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
        await fs.close(f.fd);
      }
      await TempFileSweeper.sweep();
      for (const p of stale) {
        let exists = false;
        try { exists = fs.accessSync(p, fs.AccessModeType.EXIST); } catch { exists = false; }
        expect(exists).assertFalse();
      }
    });

    // ==================== heavy 门控 ====================

    it('heavy-flag-on: enable heavy cases for next run', 0, async () => {
      const f = await fs.open(gCacheDir + HEAVY_FLAG,
        fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      await fs.write(f.fd, 'on');
      await fs.close(f.fd);
    });

    it('heavy-flag-off: disable heavy cases', 0, async () => {
      try { fs.unlinkSync(gCacheDir + HEAVY_FLAG); } catch { /* ignore */ }
    });

    // ==================== heavy 用例（flag 开启才执行，配合 hidumper 采样） ====================

    it('HEAVY att-100: gen+load+save 96MB attachment db', 0, async () => {
      if (!heavyEnabled()) {
        hilog.info(DOMAIN, TAG, 'HEAVY att-100 skipped (flag off)');
        return;
      }
      const dbPath = await genDb('att100', 96 * 1024 * 1024, 100, 10, 0);
      const t0 = Date.now();
      const model = await loadViaWorker(dbPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'HEAVY att-100 load: %{public}d ms', Date.now() - t0);
      expect(countEntries(model) === 101).assertTrue();

      const entry = findEntryByTitle(model, 'attach-entry');
      const bin = entry!.binaries.get('attach.bin') as KdbxBinaryWithHash;
      const content = await model.binaries.readDiskRef(bin!.value as KdbxBinaryDiskRef);
      expect(content.byteLength).assertEqual(96 * 1024 * 1024);
      const bytes = new Uint8Array(content);
      let prefixOk = true;
      for (let i = 0; i < 64; i++) {
        if (bytes[i] !== patternByte(i)) {
          prefixOk = false;
          break;
        }
      }
      expect(prefixOk).assertTrue();

      const tSave = Date.now();
      const success = await saveViaWorker(model, dbPath, null, null, BIG_TIMEOUT);
      hilog.info(DOMAIN, TAG, 'HEAVY att-100 save: %{public}d ms', Date.now() - tSave);
      expect(success.contentHash !== null && success.contentHash !== '').assertTrue();
      const stat = fs.statSync(dbPath);
      expect(stat.size > 90 * 1024 * 1024).assertTrue();
    }, BIG_TIMEOUT);

    it('HEAVY att-300: gen+load+save 290MB attachment db', 0, async () => {
      if (!heavyEnabled()) {
        hilog.info(DOMAIN, TAG, 'HEAVY att-300 skipped (flag off)');
        return;
      }
      const dbPath = await genDb('att300', 290 * 1024 * 1024, 300, 30, 0);
      const model = await loadViaWorker(dbPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      expect(countEntries(model) === 301).assertTrue();
      const success = await saveViaWorker(model, dbPath, null, null, BIG_TIMEOUT);
      expect(success.contentHash !== null && success.contentHash !== '').assertTrue();
      const stat = fs.statSync(dbPath);
      expect(stat.size > 280 * 1024 * 1024).assertTrue();
    }, BIG_TIMEOUT);

    it('HEAVY att-500: gen+load+save 480MB attachment db (10k entries)', 0, async () => {
      if (!heavyEnabled()) {
        hilog.info(DOMAIN, TAG, 'HEAVY att-500 skipped (flag off)');
        return;
      }
      const dbPath = await genDb('att500', 480 * 1024 * 1024, 10000, 1000, 0);
      const model = await loadViaWorker(dbPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      expect(countEntries(model) === 10001).assertTrue();
      const success = await saveViaWorker(model, dbPath, null, null, BIG_TIMEOUT);
      expect(success.contentHash !== null && success.contentHash !== '').assertTrue();
      const stat = fs.statSync(dbPath);
      expect(stat.size > 470 * 1024 * 1024).assertTrue();
    }, BIG_TIMEOUT);

    it('HEAVY text-10k: load 10k text entries regression', 0, async () => {
      if (!heavyEnabled()) {
        hilog.info(DOMAIN, TAG, 'HEAVY text-10k skipped (flag off)');
        return;
      }
      const dbPath = await genDb('text10k', 0, 10000, 0, 1);
      const model = await loadViaWorker(dbPath, KdbxModeTestHelper.DB_PASSWORD, BIG_TIMEOUT);
      expect(countEntries(model) === 10000).assertTrue();
      const first = findEntryByTitle(model, 'entry-0');
      const v = first!.fields.get('Notes');
      expect(typeof v === 'string' && (v as string).length > 0).assertTrue();
    }, BIG_TIMEOUT);
  });
}
