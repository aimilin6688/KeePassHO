import { fileIo as fs } from '@kit.CoreFileKit';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AesGcm, ByteUtils } from 'kdbxweb';
import { CommonUtils } from '../../common/utils';

const DOMAIN = 0x0000;
const TAG = 'SessionFileService';

const SESSION_KEY_BYTES = 32;
/** 会话目录保留期（毫秒）：超期目录启动时清扫（设计文档 §8） */
const SESSION_DIR_MAX_AGE_MS = 24 * 60 * 60 * 1000;

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
