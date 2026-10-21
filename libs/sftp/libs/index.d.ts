/*
 * sftp-ohos native module type declarations.
 *
 * Hand-written to match `libs/sftp-ohos/src/lib.rs` (napi-ohos binding).
 * On OHOS, napi Buffer values are surfaced as ArrayBuffer.
 *
 * Error convention: all rejected Promises throw `Error` whose message is
 * encoded as `[sftp:{code}] {detail}`; parse the code with the ArkTS-side
 * `SftpErrorCode` enum (see entry SFTPHandler.ets).
 */

/** Connection parameters. */
export interface ConnectOptions {
  /** Server hostname or IP. */
  host: string
  /** Server port. */
  port: number
  /** Connect+handshake+auth timeout in seconds. Default 10. */
  timeoutSec?: number | null
  /** Keepalive interval in seconds. Default 30; 0 disables. */
  keepaliveSec?: number | null
}

/** Remote file/directory entry info. `mtime` is Unix seconds. */
export interface FileStat {
  name: string
  size: number
  mtime: number
  isDir: boolean
  permissions: number
}

/**
 * SSH + SFTP client.
 *
 * Lifecycle: `connect` → `authenticatePassword` → `sftpInit` → sftp* ops →
 * `disconnect`. After `dispose` the instance must not be reused.
 * All async methods run on the native tokio thread pool.
 */
export declare class SshClient {
  constructor()
  connect(options: ConnectOptions): Promise<void>
  /** false = server rejected the credentials. */
  authenticatePassword(user: string, password: string): Promise<boolean>
  /** Idempotent. */
  disconnect(): Promise<void>
  /** true once never-connected / disconnected / disposed, or the peer dropped us. */
  isClosed(): boolean
  /** Release native resources; instance is unusable afterwards. */
  dispose(): void
  /** Open the SFTP subsystem session. Idempotent. */
  sftpInit(): Promise<void>
  /** Close the SFTP session. Idempotent. */
  sftpShutdown(): Promise<void>
  /**
   * false only when the server explicitly reports "no such file".
   * Network/timeout/permission errors reject (message carries `[sftp:{code}]`).
   */
  sftpExists(path: string): Promise<boolean>
  sftpStat(path: string): Promise<FileStat>
  /** Lists directory entries, skipping `.` and `..`. */
  sftpListDir(path: string): Promise<Array<FileStat>>
  /** Opens a remote file for reading; returns a handle id. */
  sftpOpenRead(path: string): Promise<number>
  /**
   * Reads up to `length` bytes sequentially from the handle.
   * Resolves an empty ArrayBuffer at EOF.
   */
  sftpRead(handle: number, length: number): Promise<ArrayBuffer>
  /** Opens (TRUNC|CREAT) a remote file for writing; returns a handle id. */
  sftpOpenWrite(path: string): Promise<number>
  /** Writes all data sequentially to the handle; returns the byte count. */
  sftpWrite(handle: number, data: ArrayBuffer): Promise<number>
  /** Closes a handle. Idempotent. */
  sftpClose(handle: number): Promise<void>
}
