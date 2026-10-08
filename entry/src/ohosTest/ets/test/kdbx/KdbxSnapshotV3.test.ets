import { beforeAll, afterAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import {
  Kdbx,
  KdbxBinaryWithHash,
  KdbxCredentials,
  KdbxError,
  KdbxSnapshot,
  KdbxUuid,
  ProtectedValue,
  Consts,
  ContainerChunkWriter,
  ErrorCodes,
  SequentialByteReader
} from 'kdbxweb';
import { SessionFileService } from '../../../../main/ets/services/kdbx/SessionFileService';
import { KdbxUtils } from '../../../../main/ets/common/utils/KdbxUtils';
import KdbxLoadService, { KdbxLoadServiceCallback } from '../../../../main/ets/services/kdbx/KdbxLoadService';
import { LoadDispatchCache } from '../../../../main/ets/services/kdbx/LoadDispatchCache';
import { KdbxFileManager } from '../../../../main/ets/services/kdbx/KdbxFileManager';
import { StorageType } from '../../../../main/ets/storage';
import { MessageType, SuccessMessage, LoadMessage } from '../../../../main/ets/workers/WorkerParam';
import { KdbxModeTestHelper } from '../workers/KdbxModeTestHelper';

const TEST_TIMEOUT_MS: number = 60000;

function withTimeout<T>(pending: Promise<T>, timeoutMs: number): Promise<T> {
  return new Promise<T>((resolve: (value: T) => void, reject: (reason: Error) => void) => {
    const timer = setTimeout(() => {
      reject(new Error('test timeout'));
    }, timeoutMs);
    pending.then((value: T) => {
      clearTimeout(timer);
      resolve(value);
    }, (error: Error) => {
      clearTimeout(timer);
      reject(error);
    });
  });
}

function concatBytes(parts: Uint8Array[]): Uint8Array {
  let total = 0;
  for (const part of parts) {
    total += part.length;
  }
  const out = new Uint8Array(total);
  let offset = 0;
  for (const part of parts) {
    out.set(part, offset);
    offset += part.length;
  }
  return out;
}

function patternBytes(size: number, seed: number): Uint8Array {
  const out = new Uint8Array(size);
  for (let i = 0; i < size; i++) {
    out[i] = (i * 7 + seed) % 256;
  }
  return out;
}

class MemoryChunkCollector implements ContainerChunkWriter {
  parts: Uint8Array[] = [];

  async writeChunk(data: Uint8Array): Promise<void> {
    this.parts.push(new Uint8Array(data));
  }

  toBytes(): Uint8Array {
    return concatBytes(this.parts);
  }
}

class MemorySequentialReader implements SequentialByteReader {
  private data: Uint8Array;
  private pos: number = 0;

  constructor(data: Uint8Array) {
    this.data = data;
  }

  async read(n: number): Promise<Uint8Array | null> {
    if (this.pos >= this.data.length) {
      return null;
    }
    const take = Math.min(n, this.data.length - this.pos);
    const out = this.data.subarray(this.pos, this.pos + take);
    this.pos += take;
    return out;
  }
}

async function createChaCha20Database(name: string): Promise<Kdbx> {
  const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
  const database = Kdbx.create(credentials, name);
  database.header.dataCipherUuid = new KdbxUuid(Consts.CipherId.ChaCha20);
  const entry = database.createEntry(database.getDefaultGroup());
  entry.fields.set('Title', 'v3-entry');
  entry.fields.set('Password', ProtectedValue.fromString('v3-secret-密码-Ω'));
  const attachmentData = patternBytes(2048, 11).buffer;
  const attachment = await database.createBinary(attachmentData);
  entry.binaries.set('attach.bin', attachment);
  const second = database.createEntry(database.getDefaultGroup());
  second.fields.set('Title', 'v3-entry-2');
  return database;
}

async function buildV3ContainerBytes(dbPath: string, t1Path: string, t2Path: string): Promise<Uint8Array> {
  const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
  const collector = new MemoryChunkCollector();
  await Kdbx.loadToContainerFile(dbPath, credentials, {
    t1Path: t1Path,
    t2Path: t2Path,
    containerWriter: collector
  });
  return collector.toBytes();
}

/**
 * M0 v3 直传容器单元测试（真实加密库 + 真实文件 + 真实 Worker）：
 * - v3 容器往返：loadToContainerFile → loadFromReader 与直接 loadFromFile 模型等价
 * - 错误密码原样抛 InvalidKey（不误判为格式不支持）
 * - loadFromReader CP2' 解压上限拒绝
 * - SFW1 流式会话包裹：跨块往返 / 篡改拒绝 / legacy 单封识别
 * - Worker 全链路：ChaCha20 走 v3 直传（会话文件消费后删除）；AES 回退全模型 KPSN
 */
export default function KdbxSnapshotV3Test() {
  describe('KdbxSnapshotV3Test', () => {
    let appContext: common.Context;
    let testDir: string;
    let dbPath: string;
    let aesDbPath: string;
    let fileManager: KdbxFileManager;

    beforeAll(async () => {
      appContext = KdbxModeTestHelper.initContext();
      testDir = appContext.filesDir + '/kdbx-snapshot-v3-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
      fileManager = new KdbxFileManager(StorageType.LOCAL);

      const database = await createChaCha20Database('V3Db');
      dbPath = testDir + '/v3-chacha20.kdbx';
      await fileManager.write(dbPath, await database.save());

      const aesDatabase = await KdbxModeTestHelper.createDatabase('V3AesDb', 'aes-entry');
      aesDbPath = testDir + '/v3-aes.kdbx';
      await fileManager.write(aesDbPath, await aesDatabase.save());
    });

    afterAll(() => {
      KdbxLoadService.stopWorker();
      LoadDispatchCache.clear();
      try {
        fs.unlinkSync(dbPath);
        fs.unlinkSync(aesDbPath);
        fs.rmdirSync(testDir);
      } catch {
        // ignore
      }
    });

    it('v3 container roundtrip restores model equal to direct load', 0, async () => {
      const t1 = testDir + '/v3rt-t1.tmp';
      const t2 = testDir + '/v3rt-t2.tmp';
      try {
        const containerBytes = await buildV3ContainerBytes(dbPath, t1, t2);
        expect(containerBytes.length > 0).assertTrue();

        const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
        const restored = await KdbxSnapshot.loadFromReader(new MemorySequentialReader(containerBytes), credentials);

        const direct = await Kdbx.loadFromFile(dbPath, credentials, { t1Path: t1 + '.d', t2Path: t2 + '.d' });

        const restoredTitles = KdbxModeTestHelper.collectEntryTitles(restored);
        const directTitles = KdbxModeTestHelper.collectEntryTitles(direct);
        expect(restoredTitles.length).assertEqual(directTitles.length);
        expect(restoredTitles.includes('v3-entry')).assertTrue();
        expect(restoredTitles.includes('v3-entry-2')).assertTrue();

        const restoredEntry = restored.getDefaultGroup().entries[0];
        const directEntry = direct.getDefaultGroup().entries[0];
        const restoredPassword = restoredEntry.fields.get('Password');
        const directPassword = directEntry.fields.get('Password');
        expect(restoredPassword instanceof ProtectedValue).assertTrue();
        expect(directPassword instanceof ProtectedValue).assertTrue();
        if (restoredPassword instanceof ProtectedValue && directPassword instanceof ProtectedValue) {
          expect(restoredPassword.getText()).assertEqual(directPassword.getText());
        }

        const restoredBinary = restoredEntry.binaries.get('attach.bin') as KdbxBinaryWithHash;
        const directBinary = directEntry.binaries.get('attach.bin') as KdbxBinaryWithHash;
        expect(restoredBinary !== undefined && directBinary !== undefined).assertTrue();
        if (restoredBinary !== undefined && directBinary !== undefined) {
          const restoredBytes = restoredBinary.value instanceof ArrayBuffer
            ? new Uint8Array(restoredBinary.value)
            : new Uint8Array((restoredBinary.value as ProtectedValue).getBinary());
          const directBytes = directBinary.value instanceof ArrayBuffer
            ? new Uint8Array(directBinary.value)
            : new Uint8Array((directBinary.value as ProtectedValue).getBinary());
          expect(restoredBytes.length).assertEqual(2048);
          expect(restoredBytes.length).assertEqual(directBytes.length);
          expect(concatBytes([restoredBytes]).toString()).assertEqual(concatBytes([directBytes]).toString());
        }
      } finally {
        try { fs.unlinkSync(t1); } catch { /* ignore */ }
        try { fs.unlinkSync(t2); } catch { /* ignore */ }
        try { fs.unlinkSync(t1 + '.d'); } catch { /* ignore */ }
        try { fs.unlinkSync(t2 + '.d'); } catch { /* ignore */ }
      }
    });

    it('v3 container rejects wrong password with InvalidKey (no fallback misjudgment)', 0, async () => {
      const t1 = testDir + '/v3wk-t1.tmp';
      const t2 = testDir + '/v3wk-t2.tmp';
      const collector = new MemoryChunkCollector();
      const wrongCredentials = new KdbxCredentials(ProtectedValue.fromString('wrong-password'));
      try {
        await Kdbx.loadToContainerFile(dbPath, wrongCredentials, {
          t1Path: t1,
          t2Path: t2,
          containerWriter: collector
        });
        expect(false).assertTrue();
      } catch (error) {
        const err = error as KdbxError;
        expect(err.code).assertEqual(ErrorCodes.InvalidKey);
      } finally {
        try { fs.unlinkSync(t1); } catch { /* ignore */ }
        try { fs.unlinkSync(t2); } catch { /* ignore */ }
      }
    });

    it('loadFromReader enforces CP2 decompressed limit', 0, async () => {
      const t1 = testDir + '/v3cp-t1.tmp';
      const t2 = testDir + '/v3cp-t2.tmp';
      try {
        const containerBytes = await buildV3ContainerBytes(dbPath, t1, t2);
        const credentials = new KdbxCredentials(ProtectedValue.fromString(KdbxModeTestHelper.DB_PASSWORD));
        try {
          await KdbxSnapshot.loadFromReader(new MemorySequentialReader(containerBytes), credentials,
            { maxDecompressedBytes: 8 });
          expect(false).assertTrue();
        } catch (error) {
          const err = error as KdbxError;
          expect(err.code).assertEqual(ErrorCodes.DecompressedTooLarge);
        }
      } finally {
        try { fs.unlinkSync(t1); } catch { /* ignore */ }
        try { fs.unlinkSync(t2); } catch { /* ignore */ }
      }
    });

    it('SFW1 stream wrap/unwrap roundtrip across chunk boundaries', 0, async () => {
      const part1 = patternBytes(3 * 1024 * 1024, 1);
      const part2 = patternBytes(2 * 1024 * 1024, 2);
      const part3 = patternBytes(100 * 1024, 3);
      const original = concatBytes([part1, part2, part3]);

      const writer = await SessionFileService.openWrapStream('m0_v3test_');
      await writer.writeChunk(part1);
      await writer.writeChunk(part2);
      await writer.writeChunk(part3);
      const path = await writer.close();

      const reader = await SessionFileService.openUnwrapReader(path);
      try {
        expect(reader.isStreaming).assertTrue();
        const chunks: Uint8Array[] = [];
        for (;;) {
          const chunk = await reader.read(65536);
          if (chunk === null) {
            break;
          }
          chunks.push(chunk);
        }
        const unwrapped = concatBytes(chunks);
        expect(unwrapped.length).assertEqual(original.length);
        expect(unwrapped.toString()).assertEqual(original.toString());
      } finally {
        reader.close();
        SessionFileService.removeFile(path);
      }
    });

    it('SFW1 tamper detection rejects modified chunk', 0, async () => {
      const data = patternBytes(5 * 1024 * 1024, 5);
      const writer = await SessionFileService.openWrapStream('m0_v3test_');
      await writer.writeChunk(data);
      const path = await writer.close();

      // 篡改首块密文区一个字节（manifest 12B + nonce 12B 之后）
      const stat = fs.statSync(path);
      const file = await fs.open(path, fs.OpenMode.READ_WRITE);
      try {
        const flip = new ArrayBuffer(1);
        const flipView = new DataView(flip);
        flipView.setUint8(0, 0xff);
        await fs.write(file.fd, flip, { offset: 25 });
      } finally {
        await fs.close(file.fd);
      }
      expect(stat.size > 100).assertTrue();

      const reader = await SessionFileService.openUnwrapReader(path);
      try {
        let rejected = false;
        try {
          await reader.read(1);
        } catch {
          rejected = true;
        }
        expect(rejected).assertTrue();
      } finally {
        reader.close();
        SessionFileService.removeFile(path);
      }
    });

    it('legacy single-seal session file detected as non-streaming', 0, async () => {
      const data = patternBytes(1024, 7);
      const legacyBuffer = new ArrayBuffer(data.length);
      new Uint8Array(legacyBuffer).set(data);
      const path = await SessionFileService.wrapToFile(legacyBuffer, 'm0_v3legacy_');
      const reader = await SessionFileService.openUnwrapReader(path);
      try {
        expect(reader.isStreaming).assertFalse();
        const unwrapped = await reader.readAll();
        expect(unwrapped.length).assertEqual(1024);
        expect(unwrapped.toString()).assertEqual(data.toString());
      } finally {
        reader.close();
        SessionFileService.removeFile(path);
      }
    });

    it('worker end-to-end v3 direct container (ChaCha20) consumes via successMessageToKdbx', 0, async () => {
      LoadDispatchCache.clear();
      KdbxLoadService.stopWorker();
      KdbxModeTestHelper.forceWorkerDispatch(dbPath);
      const loadParam = KdbxModeTestHelper.makeLoadParam(dbPath, 'v3-chacha20.kdbx', KdbxModeTestHelper.DB_PASSWORD);
      const message: SuccessMessage = await withTimeout(new Promise<SuccessMessage>(
        (resolve: (value: SuccessMessage) => void, reject: (reason: Error) => void) => {
          const callback: KdbxLoadServiceCallback = {
            onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
            onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
          };
          KdbxLoadService.loadDatabase(loadParam, callback);
        }), TEST_TIMEOUT_MS);
      expect(message.type).assertEqual(MessageType.SUCCESS);
      expect(message.m0Path !== undefined && message.m0Path.length > 0).assertTrue();

      const restored: Kdbx = await KdbxUtils.successMessageToKdbx(message, loadParam);
      const titles = KdbxModeTestHelper.collectEntryTitles(restored);
      expect(titles.includes('v3-entry')).assertTrue();
      expect(titles.includes('v3-entry-2')).assertTrue();
      const entry = restored.getDefaultGroup().entries[0];
      const password = entry.fields.get('Password');
      expect(password instanceof ProtectedValue).assertTrue();
      if (password instanceof ProtectedValue) {
        expect(password.getText()).assertEqual('v3-secret-密码-Ω');
      }
      // 消费后会话文件已删除
      if (message.m0Path) {
        expect(fs.accessSync(message.m0Path, fs.AccessModeType.EXIST)).assertFalse();
      }
      KdbxLoadService.stopWorker();
    });

    it('worker falls back to model path (KPSN) for AES database', 0, async () => {
      LoadDispatchCache.clear();
      KdbxLoadService.stopWorker();
      KdbxModeTestHelper.forceWorkerDispatch(aesDbPath);
      const loadParam = KdbxModeTestHelper.makeLoadParam(aesDbPath, 'v3-aes.kdbx', KdbxModeTestHelper.DB_PASSWORD);
      const message: SuccessMessage = await withTimeout(new Promise<SuccessMessage>(
        (resolve: (value: SuccessMessage) => void, reject: (reason: Error) => void) => {
          const callback: KdbxLoadServiceCallback = {
            onSuccessMessage: (msg: SuccessMessage) => { resolve(msg); },
            onErrorMessage: (msg: LoadMessage) => { reject(new Error(String(msg.message))); }
          };
          KdbxLoadService.loadDatabase(loadParam, callback);
        }), TEST_TIMEOUT_MS);
      expect(message.type).assertEqual(MessageType.SUCCESS);
      const restored: Kdbx = await KdbxUtils.successMessageToKdbx(message, loadParam);
      expect(KdbxModeTestHelper.collectEntryTitles(restored).includes('aes-entry')).assertTrue();
      KdbxLoadService.stopWorker();
    });
  });
}
