import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AesGcm, ByteUtils, SequentialByteReader } from 'kdbxweb';
import { CommonUtils } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'SessionFileService';

const SESSION_KEY_BYTES = 32;
/** 会话目录保留期（毫秒）：超期目录启动时清扫（设计文档 §8） */
const SESSION_DIR_MAX_AGE_MS = 24 * 60 * 60 * 1000;
/** SFW1 流式会话包裹：manifest 头长度（magic4 + chunkSize4 + chunkCount4） */
const SFW1_HEADER_LENGTH = 12;
/** SFW1 固定分块大小（末块可短）；每块独立 [12B nonce][密文][16B authTag] */
const SFW1_CHUNK_SIZE = 4 * 1024 * 1024;

/**
 * SFW1 流式会话包裹写入器：明文按 4MB 分块独立 AES-256-GCM 包裹追加落盘，
 * 内存窗口 = 单块（大容器跨线程传递不再整缓冲驻留）。
 * 文件布局：[12B manifest 占位][chunk...（各 [12B nonce][ct][16B tag]）]，
 * close 时回写 manifest（chunkSize + chunkCount）并 fsync
 */
export class SessionWrapWriter {
  private readonly path: string;
  private fd: number;
  private readonly key: Uint8Array;
  private readonly chunkSize: number;
  private pending: Uint8Array = new Uint8Array(0);
  private chunkCount: number = 0;
  private closed: boolean = false;

  constructor(path: string, fd: number, key: Uint8Array, chunkSize: number) {
    this.path = path;
    this.fd = fd;
    this.key = key;
    this.chunkSize = chunkSize;
  }

  /**
   * 追加明文（内部按 chunkSize 分块逐块 GCM 包裹；任意大小均可）
   */
  async writeChunk(data: Uint8Array): Promise<void> {
    if (this.closed) {
      throw new Error('session wrap writer already closed');
    }
    if (data.length === 0) {
      return;
    }
    let buffer: Uint8Array;
    if (this.pending.length === 0) {
      buffer = data;
    } else {
      const merged = new Uint8Array(this.pending.length + data.length);
      merged.set(this.pending, 0);
      merged.set(data, this.pending.length);
      buffer = merged;
    }
    while (buffer.length >= this.chunkSize) {
      await this.sealBlock(buffer.subarray(0, this.chunkSize));
      buffer = buffer.subarray(this.chunkSize);
    }
    this.pending = buffer;
  }

  private async sealBlock(chunk: Uint8Array): Promise<void> {
    const sealed = AesGcm.seal(this.key, new Uint8Array(chunk));
    await fs.write(this.fd, sealed.buffer);
    this.chunkCount++;
  }

  /**
   * 收尾：包裹末尾短块 → 回写 manifest → fsync → 关闭；返回会话文件路径。
   * 不调用则文件残缺，由会话清扫兜底
   */
  async close(): Promise<string> {
    if (this.closed) {
      return this.path;
    }
    if (this.pending.length > 0) {
      await this.sealBlock(this.pending);
      this.pending = new Uint8Array(0);
    }
    const manifest = new ArrayBuffer(SFW1_HEADER_LENGTH);
    const view = new DataView(manifest);
    view.setUint8(0, 0x53); // 'S'
    view.setUint8(1, 0x46); // 'F'
    view.setUint8(2, 0x57); // 'W'
    view.setUint8(3, 0x31); // '1'
    view.setUint32(4, this.chunkSize, true);
    view.setUint32(8, this.chunkCount, true);
    fs.lseek(this.fd, 0, 0 /* SEEK_SET */);
    await fs.write(this.fd, manifest);
    await fs.fsync(this.fd);
    await fs.close(this.fd);
    this.closed = true;
    return this.path;
  }

  /**
   * 异常中止：仅关闭 fd（不回写 manifest，残缺文件不可解包，由会话清扫兜底）。
   * 供容器产出一半失败时释放资源（Worker 常驻防 fd 泄漏）
   */
  async abort(): Promise<void> {
    if (this.closed) {
      return;
    }
    this.closed = true;
    try {
      await fs.close(this.fd);
    } catch {
      // ignore
    }
  }
}

/**
 * 会话文件顺序读取器（kdbxweb SequentialByteReader 实现）：
 * 自动识别包裹格式——SFW1 分块流逐块解密按需供给（内存窗口 = 单块，
 * 主线程边解包边协作解析）；legacy 单封整缓冲解密后从内存供给（v1/v2 KPSN）
 */
export class SessionUnwrapReader implements SequentialByteReader {
  readonly isStreaming: boolean;
  private fd: number;
  private readonly key: Uint8Array;
  private readonly chunkSize: number;
  private readonly chunkCount: number;
  private readonly lastChunkSize: number;
  private chunkIndex: number = 0;
  private cursor: Uint8Array = new Uint8Array(0);
  private cursorPos: number = 0;
  private legacy: Uint8Array | null = null;
  private legacyPos: number = 0;
  private closed: boolean = false;

  constructor(isStreaming: boolean, fd: number, key: Uint8Array, chunkSize: number,
    chunkCount: number, lastChunkSize: number, legacy: Uint8Array | null) {
    this.isStreaming = isStreaming;
    this.fd = fd;
    this.key = key;
    this.chunkSize = chunkSize;
    this.chunkCount = chunkCount;
    this.lastChunkSize = lastChunkSize;
    this.legacy = legacy;
  }

  /**
   * 顺序读 n 字节；EOF 返回 null（SFW1 逐块按需解密，块间为真实 IO 边界）
   */
  async read(n: number): Promise<Uint8Array | null> {
    if (this.closed) {
      return null;
    }
    if (n <= 0) {
      return new Uint8Array(0);
    }
    if (this.legacy !== null) {
      if (this.legacyPos >= this.legacy.length) {
        return null;
      }
      const take = Math.min(n, this.legacy.length - this.legacyPos);
      const out = this.legacy.subarray(this.legacyPos, this.legacyPos + take);
      this.legacyPos += take;
      return out;
    }
    if (this.cursorPos >= this.cursor.length) {
      if (this.chunkIndex >= this.chunkCount) {
        return null;
      }
      await this.loadNextBlock();
      if (this.cursor.length === 0) {
        return null;
      }
    }
    const available = this.cursor.length - this.cursorPos;
    const take = Math.min(n, available);
    const out = this.cursor.subarray(this.cursorPos, this.cursorPos + take);
    this.cursorPos += take;
    return out;
  }

  /**
   * 整量读取（legacy 单封模式；SFW1 模式不支持）
   */
  async readAll(): Promise<Uint8Array> {
    if (this.legacy === null) {
      throw new Error('readAll only supported for legacy single-seal session files');
    }
    return this.legacy;
  }

  private async loadNextBlock(): Promise<void> {
    const plainSize = this.chunkIndex === this.chunkCount - 1
      ? this.lastChunkSize : this.chunkSize;
    const sealedSize = 12 + plainSize + 16;
    const sealedBuf = new ArrayBuffer(sealedSize);
    const got = await fs.read(this.fd, sealedBuf);
    if (got !== sealedSize) {
      throw new Error('session stream short read');
    }
    const plain = AesGcm.open(this.key, new Uint8Array(sealedBuf));
    this.cursor = plain;
    this.cursorPos = 0;
    this.chunkIndex++;
  }

  close(): void {
    if (this.closed) {
      return;
    }
    this.closed = true;
    if (this.legacy === null) {
      try {
        fs.closeSync(this.fd);
      } catch {
        // ignore
      }
    }
  }
}

/**
 * 会话文件服务（设计文档 §7.4 / §8：KPSN 跨线程 ArrayBuffer 协议退役）
 *
 * 跨线程模型传输改为会话文件：Worker 把模型序列化字节经会话密钥
 * AES-256-GCM（cryptoFramework 原生实现）包裹后落盘 M0 文件，
 * 仅向主线程传文件路径；主线程解包裹后还原模型。
 * 大缓冲不再跨线程、不再随消息驻留线程队列。
 *
 * 安全语义（§8）：
 * - 会话密钥 32B 随机，仅内存，随进程消亡；进程被杀后残留会话文件为不可解密废数据
 * - GCM authTag 提供完整性校验，文件损坏/密钥不符在解包裹时即失败
 * - 目录 filesDir/session-<bootId>/（避开 cacheDir 系统回收窗口）
 * - 启动清扫超 24h 的 session-* 目录；onDestroy 全清
 */
export class SessionFileService {
  /** 进程级会话密钥（仅内存，随进程消亡） */
  private static sessionKey: Uint8Array | null = null;
  /** 本次进程的会话目录（懒创建） */
  private static sessionDir: string | null = null;
  /** Worker 线程注入的会话密钥快照（base64，经 INIT_WORKER 传入） */
  private static injectedKeyBase64: string | null = null;
  /** Worker 线程注入的会话目录（与主线程一致，便于统一清扫） */
  private static injectedSessionDir: string | null = null;

  /**
   * Worker 线程：注入主线程会话密钥与会话目录快照（INIT_WORKER 时调用）
   */
  public static setWorkerSession(keyBase64: string, dirPath: string): void {
    SessionFileService.injectedKeyBase64 = keyBase64;
    SessionFileService.injectedSessionDir = dirPath;
    SessionFileService.sessionDir = dirPath;
  }

  /**
   * 主线程：导出会话密钥（base64），供 INIT_WORKER 注入 Worker
   */
  public static getWorkerKeyBase64(): string {
    return ByteUtils.bytesToBase64(SessionFileService.getSessionKey());
  }

  /**
   * 获取或生成进程会话密钥
   */
  private static getSessionKey(): Uint8Array {
    if (SessionFileService.sessionKey !== null) {
      return SessionFileService.sessionKey;
    }
    // Worker 线程：使用 INIT 消息注入的密钥快照（Worker isolate 静态与主线程不共享）
    if (SessionFileService.injectedKeyBase64 !== null) {
      const key = new Uint8Array(ByteUtils.base64ToBytes(SessionFileService.injectedKeyBase64));
      SessionFileService.sessionKey = key;
      return key;
    }
    try {
      const rand = cryptoFramework.createRandom();
      const data = rand.generateRandomSync(SESSION_KEY_BYTES).data;
      SessionFileService.sessionKey = new Uint8Array(data);
    } catch (error) {
      // cryptoFramework 不可用时退化为 Math.random（安全垫降低但不阻断）
      hilog.warn(DOMAIN, TAG, 'session key cryptoFramework fallback: %{public}s', (error as Error).message);
      const arr = new Uint8Array(SESSION_KEY_BYTES);
      for (let i = 0; i < arr.length; i++) {
        arr[i] = Math.floor(Math.random() * 256);
      }
      SessionFileService.sessionKey = arr;
    }
    return SessionFileService.sessionKey;
  }

  /**
   * 获取本次进程的会话目录（懒创建）
   * 目录名 session-<bootId>：bootId 进程内随机，保证与其他进程实例隔离
   */
  public static getSessionDir(): string {
    if (SessionFileService.sessionDir !== null) {
      return SessionFileService.sessionDir;
    }
    const baseDir: string = CommonUtils.getAppFilesDir();
    const bootId: string = Date.now().toString(36) + Math.floor(Math.random() * 1e6).toString(36);
    SessionFileService.sessionDir = baseDir + '/session-' + bootId;
    try {
      if (!fs.accessSync(SessionFileService.sessionDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(SessionFileService.sessionDir, true);
      }
    } catch (error) {
      // 目录可能已被并发创建
    }
    return SessionFileService.sessionDir;
  }

  /**
   * 会话包裹落盘：公共 AesGcm.seal（AES-256-GCM 原生加密）→ [12B nonce][密文][16B authTag] 写入会话目录
   * @param data 待包裹字节（模型序列化产物）
   * @param prefix 文件名前缀（如 m0_load_ / m0_merge_）
   * @returns 会话文件路径（调用方用完应删除；残留由清扫兜底）
   */
  public static async wrapToFile(data: ArrayBuffer, prefix: string): Promise<string> {
    const sealed = AesGcm.seal(SessionFileService.getSessionKey(), new Uint8Array(data));

    const path = SessionFileService.getSessionDir() + '/' + prefix + Date.now() + '.tmp';
    const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    try {
      await fs.write(file.fd, sealed.buffer);
      await fs.fsync(file.fd);
    } finally {
      await fs.close(file.fd);
    }
    return path;
  }

  /**
   * 读取并解包裹会话文件：[12B nonce][密文][16B authTag] → 公共 AesGcm.open 原生解密
   * （authTag 校验失败抛错，文件损坏/密钥不符不会静默返回错数据）
   * @param path 会话文件路径
   */
  public static async unwrapFromFile(path: string): Promise<ArrayBuffer> {
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    let wrapped: ArrayBuffer;
    try {
      const stat = await fs.stat(file.fd);
      wrapped = new ArrayBuffer(stat.size);
      const read = await fs.read(file.fd, wrapped);
      if (read !== stat.size) {
        throw new Error('session file short read');
      }
    } finally {
      await fs.close(file.fd);
    }
    // authTag 校验失败抛 cryptoFramework 错误（17630001），会话文件即废弃
    return ByteUtils.bytesToBuffer(AesGcm.open(SessionFileService.getSessionKey(), new Uint8Array(wrapped)));
  }

  /**
   * 打开 SFW1 流式包裹写入器（Worker 产 M0 v3 直传容器用）：
   * 明文经 4MB 分块独立 GCM 包裹追加落盘，内存窗口 = 单块
   * @param prefix 文件名前缀（如 m0_load_）
   */
  public static async openWrapStream(prefix: string): Promise<SessionWrapWriter> {
    const path = SessionFileService.getSessionDir() + '/' + prefix + Date.now() + '.tmp';
    const file = await fs.open(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    // manifest 占位（close 时回写真实 chunkSize/chunkCount）
    await fs.write(file.fd, new ArrayBuffer(SFW1_HEADER_LENGTH));
    return new SessionWrapWriter(path, file.fd, SessionFileService.getSessionKey(), SFW1_CHUNK_SIZE);
  }

  /**
   * 打开会话文件顺序读取器：自动识别 SFW1 分块流（逐块按需解密）与
   * legacy 单封（整缓冲解密，v1/v2 KPSN 快照）两种包裹格式
   * @param path 会话文件路径
   */
  public static async openUnwrapReader(path: string): Promise<SessionUnwrapReader> {
    const key = SessionFileService.getSessionKey();
    const file = await fs.open(path, fs.OpenMode.READ_ONLY);
    const head = new ArrayBuffer(SFW1_HEADER_LENGTH);
    const headRead = await fs.read(file.fd, head);
    if (headRead !== SFW1_HEADER_LENGTH) {
      await fs.close(file.fd);
      throw new Error('session file short read');
    }
    const view = new DataView(head);
    if (view.getUint8(0) === 0x53 && view.getUint8(1) === 0x46 &&
      view.getUint8(2) === 0x57 && view.getUint8(3) === 0x31) {
      // SFW1 分块流
      const chunkSize = view.getUint32(4, true);
      const chunkCount = view.getUint32(8, true);
      const stat = await fs.stat(file.fd);
      const sealedOverhead = 12 + 16;
      const fullBlocksBytes = chunkCount > 1 ? (chunkCount - 1) * (sealedOverhead + chunkSize) : 0;
      const lastChunkSize = stat.size - SFW1_HEADER_LENGTH - fullBlocksBytes - sealedOverhead;
      if (chunkSize <= 0 || lastChunkSize < 0) {
        await fs.close(file.fd);
        throw new Error('bad session stream manifest');
      }
      // 文件位置在 manifest 后，块按序读取
      return new SessionUnwrapReader(true, file.fd, key, chunkSize, chunkCount,
        lastChunkSize, null);
    }
    // legacy 单封：整文件（含已读 12B nonce 前缀）解密到内存
    const stat = await fs.stat(file.fd);
    const wrapped = new ArrayBuffer(stat.size);
    const got = await fs.read(file.fd, wrapped, { offset: 0 });
    await fs.close(file.fd);
    if (got !== stat.size) {
      throw new Error('session file short read');
    }
    // authTag 校验失败抛 cryptoFramework 错误（17630001），会话文件即废弃
    const plain = AesGcm.open(key, new Uint8Array(wrapped));
    return new SessionUnwrapReader(false, -1, key, 0, 0, 0, plain);
  }

  /**
   * 删除单个会话文件（主线程消费 M0 后即删）
   */
  public static removeFile(path: string): void {
    try {
      fs.unlinkSync(path);
    } catch (error) {
      // best effort：残留由清扫兜底
    }
  }

  /**
   * 启动清扫：删除 filesDir 下超过保留期的 session-* 目录（保留当前进程目录）
   */
  public static async sweep(): Promise<number> {
    let removed = 0;
    try {
      const baseDir: string = CommonUtils.getAppFilesDir();
      const names: string[] = fs.listFileSync(baseDir);
      const now = Date.now();
      for (const name of names) {
        if (!name.startsWith('session-')) {
          continue;
        }
        const dirPath = baseDir + '/' + name;
        if (SessionFileService.sessionDir !== null && dirPath === SessionFileService.sessionDir) {
          continue;
        }
        try {
          const stat = fs.statSync(dirPath);
          if (now - stat.mtime * 1000 < SESSION_DIR_MAX_AGE_MS) {
            continue;
          }
          fs.rmdirSync(dirPath);
          removed++;
        } catch (error) {
          // 单目录清理失败：跳过
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'sweep failed: %{public}s', (error as Error).message);
    }
    if (removed > 0) {
      hilog.info(DOMAIN, TAG, 'sweep removed %{public}d stale session dirs', removed);
    }
    return removed;
  }

  /**
   * 全量清扫（onDestroy 用）：删除所有 session-* 目录（含当前进程目录）
   */
  public static clearAllSync(): number {
    let removed = 0;
    try {
      const baseDir: string = CommonUtils.getAppFilesDir();
      const names: string[] = fs.listFileSync(baseDir);
      for (const name of names) {
        if (!name.startsWith('session-')) {
          continue;
        }
        try {
          fs.rmdirSync(baseDir + '/' + name);
          removed++;
        } catch (error) {
          // best effort
        }
      }
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'clearAllSync failed: %{public}s', (error as Error).message);
    }
    SessionFileService.sessionDir = null;
    SessionFileService.sessionKey = null;
    if (removed > 0) {
      hilog.info(DOMAIN, TAG, 'clearAllSync removed %{public}d session dirs', removed);
    }
    return removed;
  }
}
