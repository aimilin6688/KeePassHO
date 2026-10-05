import { beforeAll, describe, expect, it } from '@ohos/hypium';
import {
  AttachmentStore,
  ByteUtils,
  Consts,
  CryptoEngine,
  Kdbx,
  KdbxBinary,
  KdbxBinaryDiskRef,
  KdbxBinaries,
  KdbxCredentials,
  KdbxEntry,
  KdbxError,
  KdbxGroup,
  ProtectedValue
} from 'kdbxweb';
import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

/**
 * S4 附件磁盘化单元测试（真实加密数据库 + 真实磁盘缓存目录，无 mock）。
 *
 * 覆盖：
 * - AttachmentStore 内容寻址加密缓存（写入/读取/命中复用/篡改校验/缺失/LRU 清理）
 * - 加载阈值触发附件池转磁盘引用 + entry.binaries 同步重绑
 * - 阈值以下零行为差异（纯内存模式）
 * - 磁盘引用数据库 save / saveXml / KPSN 快照 v2 全链路保真
 * - v3 数据库不参与磁盘化
 */

const DB_PASSWORD = 'Attach-Disk-Ref-Pass-123';

/**
 * 生成确定性测试数据（非随机，便于逐字节比对）
 */
function makePatternData(length: number): ArrayBuffer {
  const arr = new Uint8Array(length);
  for (let i = 0; i < length; i++) {
    arr[i] = i % 251;
  }
  return arr.buffer;
}

/**
 * 附件值规范化为 ArrayBuffer（ProtectedValue → 解码字节）
 */
function binaryBytes(value: KdbxBinary): ArrayBuffer {
  if (value instanceof ProtectedValue) {
    return ByteUtils.arrayToBuffer(value.getBinary());
  }
  if (value instanceof ArrayBuffer) {
    return value;
  }
  throw new Error('unexpected KdbxBinaryDiskRef in memory-mode pool');
}

/**
 * 按标题递归查找条目
 */
function findEntryByTitle(database: Kdbx, title: string): KdbxEntry | null {
  return findEntryInGroup(database.getDefaultGroup(), title);
}

function findEntryInGroup(group: KdbxGroup, title: string): KdbxEntry | null {
  for (let i = 0; i < group.entries.length; i++) {
    if (group.entries[i].fields.get('Title') === title) {
      return group.entries[i];
    }
  }
  for (let i = 0; i < group.groups.length; i++) {
    const found = findEntryInGroup(group.groups[i], title);
    if (found !== null) {
      return found;
    }
  }
  return null;
}

interface LoadedAttachment {
  db: Kdbx;
  data: ArrayBuffer;
  hash: string;
  saved: ArrayBuffer;
}

/**
 * 构造带单个真实附件的 v4 数据库并加密落盘
 */
async function createDatabaseWithAttachment(
  credentials: KdbxCredentials,
  name: string,
  data: ArrayBuffer
): Promise<LoadedAttachment> {
  const db = Kdbx.create(credentials, name);
  const entry = db.createEntry(db.getDefaultGroup());
  entry.fields.set('Title', 'has-attachment');
  const binary = await db.binaries.add(data);
  entry.binaries.set('pattern.bin', binary);
  const saved = await db.save();
  return { db, data, hash: binary.hash, saved };
}

/**
 * 清空目录内全部文件（store 密钥随机化导致文件名跨执行不同，需清理保证用例幂等）
 */
function cleanDir(path: string): void {
  try {
    const names = fs.listFileSync(path);
    for (let i = 0; i < names.length; i++) {
      try {
        fs.unlinkSync(`${path}/${names[i]}`);
      } catch (e) {
        // best effort
      }
    }
  } catch (e) {
    // 目录不存在
  }
}

/**
 * 独立子目录 store，避免用例间文件污染
 */
function makeStore(baseDir: string, sub: string): AttachmentStore {
  const dir = `${baseDir}/${sub}`;
  cleanDir(dir);
  return new AttachmentStore(dir, ByteUtils.randomData(32));
}

export default function AttachmentDiskRefTest() {
  describe('AttachmentDiskRef', () => {
    let credentials: KdbxCredentials;
    let baseDir: string;

    beforeAll(() => {
      const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      KdbxModeTestHelper.initContext();
      credentials = new KdbxCredentials(ProtectedValue.fromString(DB_PASSWORD));
      baseDir = `${appContext.filesDir}/attach-disk-ref-test`;
      try {
        if (!fs.accessSync(baseDir, fs.AccessModeType.EXIST)) {
          fs.mkdirSync(baseDir, true);
        }
      } catch (e) {
        // 目录已存在
      }
    });

    it('storePutGetRoundTrip', 0, async () => {
      const store = makeStore(baseDir, 'roundtrip');
      const data = makePatternData(8 * 1024);
      const digest = await CryptoEngine.sha256(data);
      const hash = ByteUtils.bytesToHex(new Uint8Array(digest));
      await store.put(hash, data);
      expect(await store.has(hash)).assertTrue();
      const read = await store.get(hash);
      expect(ByteUtils.arrayBufferEquals(read, data)).assertTrue();
    });

    it('storePutSameHashTwiceReusesSingleDiskFile', 0, async () => {
      const dir = `${baseDir}/reuse`;
      cleanDir(dir);
      const store = new AttachmentStore(dir, ByteUtils.randomData(32));
      const data = makePatternData(4096);
      const digest = await CryptoEngine.sha256(data);
      const hash = ByteUtils.bytesToHex(new Uint8Array(digest));
      await store.put(hash, data);
      await store.put(hash, makePatternData(4096));
      const names = fs.listFileSync(dir).filter((name: string) => name.endsWith('.bin'));
      expect(names.length).assertEqual(1);
      const read = await store.get(hash);
      expect(ByteUtils.arrayBufferEquals(read, data)).assertTrue();
    });

    it('storeGetTamperedFileThrowsFileCorrupt', 0, async () => {
      const dir = `${baseDir}/tamper`;
      cleanDir(dir);
      const store = new AttachmentStore(dir, ByteUtils.randomData(32));
      const data = makePatternData(2048);
      const digest = await CryptoEngine.sha256(data);
      const hash = ByteUtils.bytesToHex(new Uint8Array(digest));
      await store.put(hash, data);
      const names = fs.listFileSync(dir).filter((name: string) => name.endsWith('.bin'));
      expect(names.length > 0).assertTrue();
      const file = fs.openSync(`${dir}/${names[0]}`, fs.OpenMode.READ_WRITE);
      try {
        const size = fs.statSync(file.fd).size;
        const offset = Math.max(13, Math.floor(size / 2));
        const buf = new ArrayBuffer(1);
        fs.readSync(file.fd, buf, { offset: offset });
        const flip = new Uint8Array(buf);
        flip[0] = flip[0] ^ 0xff;
        fs.writeSync(file.fd, buf, { offset: offset });
      } finally {
        fs.closeSync(file);
      }
      try {
        await store.get(hash);
        expect(false).assertTrue();
      } catch (e) {
        expect(e instanceof KdbxError).assertTrue();
        expect((e as KdbxError).code).assertEqual(Consts.ErrorCodes.FileCorrupt);
      }
    });

    it('storeGetMissingHashThrowsAttachmentStoreError', 0, async () => {
      const store = makeStore(baseDir, 'missing');
      const missingHash = 'ff'.repeat(32);
      try {
        await store.get(missingHash);
        expect(false).assertTrue();
      } catch (e) {
        expect(e instanceof KdbxError).assertTrue();
        expect((e as KdbxError).code)
          .assertEqual(Consts.ErrorCodes.AttachmentStoreError);
      }
    });

    it('storeSweepRemovesFilesBeyondBudget', 0, async () => {
      const store = makeStore(baseDir, 'sweep');
      const hashes: string[] = [];
      for (let i = 0; i < 3; i++) {
        const data = makePatternData(1024 + i);
        const digest = await CryptoEngine.sha256(data);
        const hash = ByteUtils.bytesToHex(new Uint8Array(digest));
        await store.put(hash, data);
        hashes.push(hash);
      }
      await store.sweep(0);
      for (let i = 0; i < hashes.length; i++) {
        expect(await store.has(hashes[i])).assertFalse();
      }
    });

    it('loadBelowThresholdKeepsMemoryMode', 0, async () => {
      const store = makeStore(baseDir, 'below');
      const made = await createDatabaseWithAttachment(credentials, 'BelowThresholdDb', makePatternData(4096));
      const db = await Kdbx.load(made.saved, credentials, {
        attachmentStore: store,
        attachmentsDiskThreshold: 1024 * 1024
      });
      const pool = db.binaries.getAllWithHashes();
      expect(pool.length).assertEqual(1);
      expect(pool[0].hash).assertEqual(made.hash);
      expect(pool[0].value instanceof KdbxBinaryDiskRef).assertFalse();
      expect(await store.has(made.hash)).assertFalse();
    });

    it('loadAboveThresholdConvertsPoolAndRebindsEntries', 0, async () => {
      const store = makeStore(baseDir, 'convert');
      const made = await createDatabaseWithAttachment(credentials, 'ConvertDb', makePatternData(4096));
      const db = await Kdbx.load(made.saved, credentials, {
        attachmentStore: store,
        attachmentsDiskThreshold: 1
      });
      const pool = db.binaries.getAllWithHashes();
      expect(pool.length).assertEqual(1);
      expect(pool[0].value instanceof KdbxBinaryDiskRef).assertTrue();
      const ref = pool[0].value as KdbxBinaryDiskRef;
      expect(ref.hash).assertEqual(made.hash);
      expect(ref.byteLength).assertEqual(made.data.byteLength);
      expect(await store.has(made.hash)).assertTrue();

      const entry = findEntryByTitle(db, 'has-attachment');
      expect(entry !== null).assertTrue();
      if (entry !== null) {
        const entryValue = entry.binaries.get('pattern.bin');
        expect(entryValue !== undefined).assertTrue();
        if (entryValue !== undefined && KdbxBinaries.isKdbxBinaryWithHash(entryValue)) {
          expect(entryValue.hash).assertEqual(made.hash);
          expect(entryValue.value instanceof KdbxBinaryDiskRef).assertTrue();
        }
      }
    });

    it('convertedDatabaseSaveReloadKeepsAttachmentBytes', 0, async () => {
      const store = makeStore(baseDir, 'saveroundtrip');
      const made = await createDatabaseWithAttachment(credentials, 'SaveRoundTripDb', makePatternData(4096));
      const db = await Kdbx.load(made.saved, credentials, {
        attachmentStore: store,
        attachmentsDiskThreshold: 1
      });
      const resaved = await db.save();
      const reloaded = await Kdbx.load(resaved, credentials);
      const pool = reloaded.binaries.getAllWithHashes();
      expect(pool.length).assertEqual(1);
      expect(pool[0].hash).assertEqual(made.hash);
      expect(ByteUtils.arrayBufferEquals(binaryBytes(pool[0].value), made.data)).assertTrue();
    });

    it('snapshotV2CarriesDiskRefsAndRejectsWithoutStore', 0, async () => {
      const store = makeStore(baseDir, 'snapshotv2');
      const made = await createDatabaseWithAttachment(credentials, 'SnapshotV2Db', makePatternData(4096));
      const db = await Kdbx.load(made.saved, credentials, {
        attachmentStore: store,
        attachmentsDiskThreshold: 1
      });
      const snapshot = await db.saveSnapshot();

      const restored = await Kdbx.loadSnapshot(snapshot, credentials, { attachmentStore: store });
      const pool = restored.binaries.getAllWithHashes();
      expect(pool.length).assertEqual(1);
      expect(pool[0].value instanceof KdbxBinaryDiskRef).assertTrue();
      const ref = pool[0].value as KdbxBinaryDiskRef;
      const bytes = await store.get(ref.hash);
      expect(ByteUtils.arrayBufferEquals(bytes, made.data)).assertTrue();

      try {
        await Kdbx.loadSnapshot(snapshot, credentials);
        expect(false).assertTrue();
      } catch (e) {
        expect(e instanceof KdbxError).assertTrue();
        expect((e as KdbxError).code)
          .assertEqual(Consts.ErrorCodes.InvalidState);
      }
    });

    it('saveXmlMaterializesDiskRefsForExport', 0, async () => {
      const store = makeStore(baseDir, 'savexml');
      const made = await createDatabaseWithAttachment(credentials, 'SaveXmlDb', makePatternData(4096));
      const db = await Kdbx.load(made.saved, credentials, {
        attachmentStore: store,
        attachmentsDiskThreshold: 1
      });
      const xml = await db.saveXml(true, true);
      expect(xml.length > 0).assertTrue();
      expect(xml.includes('KeePassFile')).assertTrue();
      expect(xml.includes('pattern.bin')).assertTrue();
    });

    it('v3DatabaseIsNeverConvertedToDiskRefs', 0, async () => {
      const store = makeStore(baseDir, 'v3');
      const data = makePatternData(4096);
      const db = Kdbx.create(credentials, 'V3AttachDb');
      db.setVersion(3);
      const entry = db.createEntry(db.getDefaultGroup());
      entry.fields.set('Title', 'v3-attachment');
      const binary = await db.binaries.add(data);
      entry.binaries.set('legacy.bin', binary);
      const saved = await db.save();

      const loaded = await Kdbx.load(saved, credentials, {
        attachmentStore: store,
        attachmentsDiskThreshold: 1
      });
      expect(loaded.header.versionMajor).assertEqual(3);
      const pool = loaded.binaries.getAllWithHashes();
      expect(pool.length).assertEqual(1);
      expect(pool[0].value instanceof KdbxBinaryDiskRef).assertFalse();
      expect(await store.has(binary.hash)).assertFalse();

      const resaved = await loaded.save();
      const reloaded = await Kdbx.load(resaved, credentials);
      expect(reloaded.header.versionMajor).assertEqual(3);
      const reloadedPool = reloaded.binaries.getAllWithHashes();
      expect(reloadedPool.length).assertEqual(1);
      expect(ByteUtils.arrayBufferEquals(binaryBytes(reloadedPool[0].value), data)).assertTrue();
    });
  });
}
