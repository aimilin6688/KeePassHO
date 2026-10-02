/*
 * Copyright (C) 2023 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import fs from '@ohos.file.fs'
import socket from '@ohos.net.socket'
import { join, to } from './PathUtil'
import { FileInfo } from './FileInfo'
import { ClientError, FTPContext, FTPError, FTPResponse } from './FtpContext'
import { parseList as parseListAutoDetect } from './parseList'
import { ProgressHandler, ProgressTracker } from './ProgressTracker'
import { parseMLSxDate } from './parseListMLSD'
import { describeAddress, describeTLS, upgradeSocket } from './netUtils'
import { downloadTo, enterPassiveModeIPv4, enterPassiveModeIPv6, UploadCommand, uploadFrom } from './transfer'
import { isMultiline, positiveCompletion } from './parseControlResponse'

import buffer from '@ohos.buffer'

const BASE_COUNT = 1

export interface AccessOptions {
  /** Host the client should connect to. Optional, default is "localhost". */
  readonly host?: string
  /** Port the client should connect to. Optional, default is 21. */
  readonly port?: number
  /** Username to use for login. Optional, default is "anonymous". */
  readonly user?: string
  /** Password to use for login. Optional, default is "guest". */
  readonly password?: string
  /** Use FTPS over TLS. Optional, default is false. True is preferred explicit TLS, "implicit" supports legacy, non-standardized implicit TLS. */
  readonly secure?: boolean | "implicit"
  /** TLS options as in [tls.connect(options)](https://nodejs.org/api/tls.html#tls_tls_connect_options_callback), optional. */
  readonly secureOptions?: socket.TLSConnectOptions
}

/** Prepares a data connection for transfer. */
export type TransferStrategy = (ftp: FTPContext) => Promise<FTPResponse>

/** Parses raw directoy listing data. */
export type RawListParser = (rawList: string) => FileInfo[]

export interface UploadOptions {
  /** Offset in the local file to start uploading from. */
  localStart?: number
  /** Final byte position to include in upload from the local file. */
  localEndInclusive?: number
}

const LIST_COMMANDS_DEFAULT: readonly string[] = ["LIST -a", "LIST"]
const LIST_COMMANDS_MLSD: readonly string[] = ["MLSD", "LIST -a", "LIST"]

/**
 * High-level API to interact with an FTP server.
 */
export class Client {
  prepareTransfer: TransferStrategy
  parseList: RawListParser
  availableListCommands = LIST_COMMANDS_DEFAULT
  /** Low-level API to interact with FTP server. */
  readonly ftp: FTPContext
  /** Tracks progress of data transfers. */
  protected _progressTracker: ProgressTracker
  private context
  /**
   * Instantiate an FTP client.
   *
   * @param timeout  Timeout in milliseconds, use 0 for no timeout. Optional, default is 30 seconds.
   */
  constructor(uiContext: any, timeout = 30000) {
    if (!uiContext) {
      throw new Error('context can not be null')
    }
    if (!uiContext.cacheDir) {
      throw new Error('uiContext is not a Context object')
    }
    this.context = uiContext
    this.ftp = new FTPContext(timeout)
    this.prepareTransfer = this._enterFirstCompatibleMode([enterPassiveModeIPv6, enterPassiveModeIPv4])
    this.parseList = parseListAutoDetect
    this._progressTracker = new ProgressTracker()
  }

  /**
   * Close the client and all open socket connections.
   *
   * Close the client and all open socket connections. The client can’t be used anymore after calling this method,
   * you have to either reconnect with `access` or `connect` or instantiate a new instance to continue any work.
   * A client is also closed automatically if any timeout or connection error occurs.
   */
  async close(): Promise<void> {
    let startTime1 = new Date().getTime();
    await this.ftp.close()
    let endTime1 = new Date().getTime();
    let averageTime1 = ((endTime1 - startTime1) * 1000) / BASE_COUNT;
    console.log("BasicFtpTest : close averageTime : " + averageTime1 + "us")
    this._progressTracker.stop()
    return new Promise(function (resolve, reject) {
      resolve()
    })
  }

  /**
   * Returns true if the client is closed and can't be used anymore.
   */
  get closed(): boolean {
    let  startTime1 = new Date().getTime();
    let isClosed = this.ftp.closed;
    let endTime1 = new Date().getTime();
    let averageTime1 = ((endTime1 - startTime1) * 1000) / 1;
    console.log("BasicFtpTest : closed averageTime : " + averageTime1 + "us")
    return isClosed;
  }

  /**
   * Connect (or reconnect) to an FTP server.
   *
   * This is an instance method and thus can be called multiple times during the lifecycle of a `Client`
   * instance. Whenever you do, the client is reset with a new control connection. This also implies that
   * you can reopen a `Client` instance that has been closed due to an error when reconnecting with this
   * method. In fact, reconnecting is the only way to continue using a closed `Client`.
   *
   * @param host  Host the client should connect to. Optional, default is "localhost".
   * @param port  Port the client should connect to. Optional, default is 21.
   */
  async connect(host = "localhost", port = 21): Promise<FTPResponse> {
    // if (this.ftp && this.ftp.socket) {
    //   await this.ftp.closeOldSocket(this.ftp.socket)
    // }
    let startTime1 = new Date().getTime();
    await this.ftp.reset();
    let endTime1 = new Date().getTime();
    let averageTime1 = ((endTime1 - startTime1) * 1000) / BASE_COUNT;
    console.log("BasicFtpTest : reset averageTime : " + averageTime1 + "us")

    if (!this.ftp.socket) {
      throw new Error('socket can not be null')
    }
    let startTime0 = new Date().getTime();
    let tempSocket = this.ftp.socket as socket.TCPSocket
    let endTime0 = new Date().getTime();
    let averageTime0 = ((endTime0 - startTime0) * 1000) / 1;
    console.log("BasicFtpTest : socket 不带带参数接口时长 : " + averageTime0 + "us")

    let option: socket.TCPConnectOptions = {
      address: {
        address: host,
        port: port,
        family: this.ftp.ipFamily ? this.ftp.ipFamily : 1
      },
      timeout: this.ftp.timeout ? this.ftp.timeout : 30000
    }
    let [connectErr, connectInfo] = await to<void>(tempSocket.connect(option))
    if (connectErr) {
      throw connectErr
    }
    let [tlsErr, data] = await to<string>(describeTLS(tempSocket))
    if (tlsErr) {
      throw tlsErr
    }
    let [addressErr, result] = await to<string>(describeAddress(tempSocket))
    if (addressErr) {
      throw addressErr
    }
    this.ftp.log(`Connected to ${result} (${data})`)

    return this._handleConnectResponse()
  }

  async connectTLS(port = 21, host: string = 'localhost', options: socket.TLSConnectOptions, secureConnectListener?: () => void): Promise<socket.TLSSocket> {
    if (port < 0 || port > 65535) {
      throw new Error('port must limit between 0 and 65535')
    }
    if (!host || host.length < 1) {
      throw new Error('host can not be empty')
    }
    if (!options || !options.address || !options.secureOptions) {
      throw new Error('tlsOptions param must be a valid data')
    }
    if (!this.ftp) {
      throw new Error('this.ftp can not be null')
    }
    this.ftp.tlsOptions = options;

    let startTime1 = new Date().getTime();
    await this.ftp.reset();
    let endTime1 = new Date().getTime();
    let averageTime1 = ((endTime1 - startTime1) * 1000) / BASE_COUNT;
    console.log("BasicFtpTest : reset averageTime : " + averageTime1 + "us")
    if (!this.ftp.socket) {
      throw new Error('socket can not be null')
    }
    let startTime2 = new Date().getTime();
    let tempSocket = this.ftp.socket as socket.TLSSocket
    let endTime2 = new Date().getTime();
    let averageTime2 = ((endTime2 - startTime2) * 1000) / BASE_COUNT;
    console.log("BasicFtpTest : socket不带参数 averageTime : " + averageTime2 + "us")

    let [connectErr, connectInfo] = await to<void>(tempSocket.connect(options))
    if (connectErr) {
      throw connectErr
    }
    if (secureConnectListener) {
      secureConnectListener()
    }
    let data = await to<string>(describeTLS(tempSocket))
    let result = await to<string>(describeAddress(tempSocket))
    this.ftp.log(`Connected to ${result} (${data})`)
    return tempSocket
  }

  /**
   * As `connect` but using implicit TLS. Implicit TLS is not an FTP standard and has been replaced by
   * explicit TLS. There are still FTP servers that support only implicit TLS, though.
   */
  async connectImplicitTLS(host = "localhost", port = 21, tlsOptions: socket.TLSConnectOptions): Promise<FTPResponse> {
    this.ftp.socket = await this.connectTLS(
      port,
      host,
      tlsOptions,
      () => this.ftp.log(`Connected to ${describeAddress(this.ftp.socket)} (${describeTLS(this.ftp.socket)})`)
    )

    this.ftp.tlsOptions = tlsOptions
    return this._handleConnectResponse()
  }

  /**
   * Handles the first reponse by an FTP server after the socket connection has been established.
   */
  private _handleConnectResponse(): Promise<FTPResponse> {
    return this.ftp.handle(undefined, (res, task) => {
      if (res instanceof Error) {
        // The connection has been destroyed by the FTPContext at this point.
        task.reject(res)
      }
      else if (positiveCompletion(res.code)) {
        task.resolve(res)
      }
      // Reject all other codes, including 120 "Service ready in nnn minutes".
      else {
        // Don't stay connected but don't replace the socket yet by using reset()
        // so the user can inspect properties of this instance.
        task.reject(new FTPError(res))
      }
    })
  }

  /**
   * Send an FTP command and handle the first response.
   */
  send(command: string, ignoreErrorCodesDEPRECATED = false): Promise<FTPResponse> {
    if (ignoreErrorCodesDEPRECATED) { // Deprecated starting from 3.9.0
      this.ftp.log("Deprecated call using send(command, flag) with boolean flag to ignore errors. Use sendIgnoringError(command).")
      return this.sendIgnoringError(command)
    }
    return this.ftp.request(command)
  }

  /**
   * Send an FTP command and ignore an FTP error response. Any other kind of error or timeout will still reject the Promise.
   *
   * @param command
   */
  sendIgnoringError(command: string): Promise<FTPResponse> {
    return this.ftp.handle(command, (res, task) => {
      if (res instanceof FTPError) {
        task.resolve({ code: res.code, message: res.message })
      }
      else if (res instanceof Error) {
        task.reject(res)
      }
      else {
        task.resolve(res)
      }
    })
  }

  /**
   * Upgrade the current socket connection to TLS.
   *
   * @param options  TLS options as in `tls.connect(options)`, optional.
   * @param command  Set the authentication command. Optional, default is "AUTH TLS".
   */
  async useTLS(options: socket.TLSConnectOptions, command = "AUTH TLS"): Promise<FTPResponse> {
    if (!options || !options.address || !options.secureOptions) {
      throw new Error('tlsOptions param must be a valid data')
    }
    const ret = await this.send(command)
    this.ftp.socket = await upgradeSocket(this.ftp.socket as socket.TLSSocket, options)
    this.ftp.tlsOptions = options // Keep the TLS options for later data connections that should use the same options.
    this.ftp.log(`Control socket is using: ${describeTLS(this.ftp.socket)}`)
    return ret
  }

  /**
   * Login a user with a password.
   *
   * @param user  Username to use for login. Optional, default is "anonymous".
   * @param password  Password to use for login. Optional, default is "guest".
   */
  login(user = "anonymous", password = "guest"): Promise<FTPResponse> {
    this.ftp.log(`Login security: ${describeTLS(this.ftp.socket)}`)
    return this.ftp.handle("USER " + user, (res, task) => {
      if (res instanceof Error) {
        task.reject(res)
      }
      else if (positiveCompletion(res.code)) { // User logged in proceed OR Command superfluous
        task.resolve(res)
      }
      else if (res.code === 331) { // User name okay, need password
        this.ftp.send("PASS " + password)
      }
      else { // Also report error on 332 (Need account)
        task.reject(new FTPError(res))
      }
    })
  }

  /**
   * Set the usual default settings.
   *
   * Settings used:
   * * Binary mode (TYPE I)
   * * File structure (STRU F)
   * * Additional settings for FTPS (PBSZ 0, PROT P)
   */
  async useDefaultSettings(): Promise<void> {
    const features = await this.features()
    // Use MLSD directory listing if possible. See https://tools.ietf.org/html/rfc3659#section-7.8:
    // "The presence of the MLST feature indicates that both MLST and MLSD are supported."
    const supportsMLSD = features.has("MLST")
    this.availableListCommands = supportsMLSD ? LIST_COMMANDS_MLSD : LIST_COMMANDS_DEFAULT
    await this.send("TYPE I") // Binary mode
    await this.sendIgnoringError("STRU F") // Use file structure
    await this.sendIgnoringError("OPTS UTF8 ON") // Some servers expect UTF-8 to be enabled explicitly and setting before login might not have worked.
    if (supportsMLSD) {
      await this.sendIgnoringError("OPTS MLST type;size;modify;unique;unix.mode;unix.owner;unix.group;unix.ownername;unix.groupname;") // Make sure MLSD listings include all we can parse
    }
    if (this.ftp.hasTLS) {
      await this.sendIgnoringError("PBSZ 0") // Set to 0 for TLS
      await this.sendIgnoringError("PROT P") // Protect channel (also for data connections)
    }
  }

  /**
   * Convenience method that calls `connect`, `useTLS`, `login` and `useDefaultSettings`.
   *
   * This is an instance method and thus can be called multiple times during the lifecycle of a `Client`
   * instance. Whenever you do, the client is reset with a new control connection. This also implies that
   * you can reopen a `Client` instance that has been closed due to an error when reconnecting with this
   * method. In fact, reconnecting is the only way to continue using a closed `Client`.
   */
  async access(options: AccessOptions = {}): Promise<FTPResponse> {
    let welcome
    try {
      const useExplicitTLS = options.secure === true
      const useImplicitTLS = options.secure === "implicit"

      if (useImplicitTLS) {
        let startTime0 = new Date().getTime();
        welcome = await this.connectImplicitTLS(options.host, options.port, options.secureOptions)
        let endTime0 = new Date().getTime();
        let averageTime0 = ((endTime0 - startTime0) * 1000) / BASE_COUNT;
        console.log("BasicFtpTest : connectImplicitTLS averageTime : " + averageTime0 + "us")
      }
      else {
        let startTime1 = new Date().getTime();
        welcome = await this.connect(options.host, options.port)
        let endTime1 = new Date().getTime();
        let averageTime1 = ((endTime1 - startTime1) * 1000) / 1;
        console.log("BasicFtpTest : connect 接口 averageTime : " + averageTime1 + "us")
      }
      if (useExplicitTLS) {
        // Fixes https://github.com/patrickjuchli/basic-ftp/issues/166 by making sure
        // host is set for any future data connection as well.
        const secureOptions = options.secureOptions
        await this.useTLS(secureOptions)
      }
      // Set UTF-8 on before login in case there are non-ascii characters in user or password.
      // Note that this might not work before login depending on server.
      let startTime1 = new Date().getTime();
      await this.sendIgnoringError("OPTS UTF8 ON")
      let endTime1 = new Date().getTime();
      let averageTime1 = ((endTime1 - startTime1) * 1000) / BASE_COUNT;
      console.log("BasicFtpTest : sendIgnoringError averageTime : " + averageTime1 + "us")
      let startTime2 = new Date().getTime();
      await this.login(options.user, options.password)
      let endTime2 = new Date().getTime();
      let averageTime2 = ((endTime2 - startTime2) * 1000) / BASE_COUNT;
      console.log("BasicFtpTest : login averageTime : " + averageTime1 + "us")
      let startTime3 = new Date().getTime();
      await this.useDefaultSettings()
      let endTime3 = new Date().getTime();
      let averageTime3 = ((endTime3 - startTime3) * 1000) / BASE_COUNT;
      console.log("BasicFtpTest : useDefaultSettings averageTime : " + averageTime3 + "us")
    } catch (err) {
      throw err
    }
    return welcome
  }

  /**
   * Get the current working directory.
   */
  async pwd(): Promise<string> {
    const res = await this.send("PWD")
    // The directory is part of the return message, for example:
    // 257 "/this/that" is current directory.
    const parsed = res.message.match(/"(.+)"/)
    if (parsed === null || parsed[1] === undefined) {
      throw new Error(`Can't parse response to command 'PWD': ${res.message}`)
    }
    return parsed[1]
  }

  /**
   * Get a description of supported features.
   *
   * This sends the FEAT command and parses the result into a Map where keys correspond to available commands
   * and values hold further information. Be aware that your FTP servers might not support this
   * command in which case this method will not throw an exception but just return an empty Map.
   */
  async features(): Promise<Map<string, string>> {
    const res = await this.sendIgnoringError("FEAT")
    const features = new Map()
    // Not supporting any special features will be reported with a single line.
    if (res.code < 400 && isMultiline(res.message)) {
      // The first and last line wrap the multiline response, ignore them.
      res.message.split("\n").slice(1, -1).forEach(line => {
        // A typical lines looks like: " REST STREAM" or " MDTM".
        // Servers might not use an indentation though.
        const entry = line.trim().split(" ")
        features.set(entry[0], entry[1] || "")
      })
    }
    return features
  }

  /**
   * Set the working directory.
   */
  async cd(path: string): Promise<FTPResponse> {
    let startTime1 = new Date().getTime();
    const validPath = await this.protectWhitespace(path)
    let endTime1 = new Date().getTime();
    let averageTime1 = ((endTime1 - startTime1) * 1000) / BASE_COUNT;
    console.log("BasicFtpTest : protectWhitespace averageTime : " + averageTime1 + "us")
    return this.send("CWD " + validPath)
  }

  /**
   * Switch to the parent directory of the working directory.
   */
  async cdup(): Promise<FTPResponse> {
    return this.send("CDUP")
  }

  /**
   * Get the last modified time of a file. This is not supported by every FTP server, in which case
   * calling this method will throw an exception.
   */
  async lastMod(path: string): Promise<Date> {
    const validPath = await this.protectWhitespace(path)
    const res = await this.send(`MDTM ${validPath}`)
    const date = res.message.slice(4)
    return parseMLSxDate(date)
  }

  /**
   * Get the size of a file.
   */
  async size(path: string): Promise<number> {
    const validPath = await this.protectWhitespace(path)
    const command = `SIZE ${validPath}`
    const res = await this.send(command)
    // The size is part of the response message, for example: "213 555555". It's
    // possible that there is a commmentary appended like "213 5555, some commentary".
    const size = parseInt(res.message.slice(4), 10)
    if (Number.isNaN(size)) {
      throw new Error(`Can't parse response to command '${command}' as a numerical value: ${res.message}`)
    }
    return size
  }

  /**
   * Rename a file.
   *
   * Depending on the FTP server this might also be used to move a file from one
   * directory to another by providing full paths.
   */
  async rename(srcPath: string, destPath: string): Promise<FTPResponse> {
    const validSrc = await this.protectWhitespace(srcPath)
    const validDest = await this.protectWhitespace(destPath)
    await this.send("RNFR " + validSrc)
    return this.send("RNTO " + validDest)
  }

  /**
   * Remove a file from the current working directory.
   *
   * You can ignore FTP error return codes which won't throw an exception if e.g.
   * the file doesn't exist.
   */
  async remove(path: string, ignoreErrorCodes = false): Promise<FTPResponse> {
    const validPath = await this.protectWhitespace(path)
    if (ignoreErrorCodes) {
      return this.sendIgnoringError(`DELE ${validPath}`)
    }
    return this.send(`DELE ${validPath}`)
  }

  /**
   * Report transfer progress for any upload or download to a given handler.
   *
   * This will also reset the overall transfer counter that can be used for multiple transfers. You can
   * also call the function without a handler to stop reporting to an earlier one.
   *
   * @param handler  Handler function to call on transfer progress.
   */
  trackProgress(handler?: ProgressHandler) {
    let startTime1 = new Date().getTime();
    this._progressTracker.bytesOverall = 0
    this._progressTracker.reportTo(handler)
    let endTime1 = new Date().getTime();
    let averageTime1 = ((endTime1 - startTime1) * 1000) / BASE_COUNT;
    console.log("BasicFtpTest : trackProgress averageTime : " + averageTime1 + "us")
  }

  /**
   * Upload data from a readable stream or a local file to a remote file.
   *
   * @param source  Readable stream or path to a local file.
   * @param toRemotePath  Path to a remote file to write to.
   */
  async uploadFrom(source: fs.Stream | string, toRemotePath: string, options: UploadOptions = {
  }): Promise<FTPResponse> {
    return this._uploadWithCommand(source, toRemotePath, "STOR", options)
  }

  /**
   * Upload data from a readable stream or a local file by appending it to an existing file. If the file doesn't
   * exist the FTP server should create it.
   *
   * @param source  Readable stream or path to a local file.
   * @param toRemotePath  Path to a remote file to write to.
   */
  async appendFrom(source: fs.Stream | string, toRemotePath: string, options: UploadOptions = {
  }): Promise<FTPResponse> {
    let startTime1 = new Date().getTime();
    let result = this._uploadWithCommand(source, toRemotePath, "APPE", options)
    let endTime1 = new Date().getTime();
    let averageTime1 = ((endTime1 - startTime1) * 1000) / BASE_COUNT;
    console.log("BasicFtpTest : appendFrom averageTime : " + averageTime1 + "us")
    return result
  }

  /**
   * @protected
   */
  protected async _uploadWithCommand(source: fs.Stream | string, remotePath: string, command: UploadCommand, options: UploadOptions): Promise<FTPResponse> {
    if (typeof source === "string") {
      return this._uploadLocalFile(source, remotePath, command, options)
    }
    return this._uploadFromStream(source, remotePath, command, options)
  }

  /**
   * @protected
   */
  protected async _uploadLocalFile(localPath: string, remotePath: string, command: UploadCommand, options: UploadOptions): Promise<FTPResponse> {
    const [sourceErr, source] = await to<fs.Stream>(fs.createStream(localPath, 'a+'))
    if (sourceErr) throw sourceErr;
    if (!source) throw new Error('createStream fail');
    const [statErr, stat] = await to<fs.Stat>(fs.stat(localPath))
    if (statErr) throw statErr;
    if (!stat) throw new Error('file get stat fail');
    if (options) {
      if (!options.localStart) {
        options.localStart = 0;
      }
      if (!options.localEndInclusive || options.localEndInclusive == 0) {
        options.localEndInclusive = stat.size
      }
    } else {
      options = {
        localStart: 0,
        localEndInclusive: stat.size,
      }
    }
    try {
      return await this._uploadFromStream(source, remotePath, command, options)
    }
    finally {
      let [err, closeInfo] = await to<void>(ignoreError(() => {
        if (source) {
          return source.close()
        } else {
          return new Promise(function (resolve, reject) {
            reject('source is null,close fail')
          })
        }
      })
      )
      if (err) throw err;
    }
  }

  /**
   * @protected
   */
  protected async _uploadFromStream(source: fs.Stream, remotePath: string, command: UploadCommand, options: UploadOptions): Promise<FTPResponse> {
    let onError = (err: ClientError) => this.ftp.closeWithError(err)
    try {
      const validPath = await this.protectWhitespace(remotePath)
      await this.prepareTransfer(this.ftp)
      // Keep the keyword `await` or the `finally` clause below runs too early
      // and removes the event listener for the source stream too early.
      if (options) {
        if (!options.localStart) {
          options.localStart = 0;
        }
        if (!options.localEndInclusive || options.localEndInclusive == 0) {
          options.localEndInclusive = Number.MAX_VALUE;
        }
      } else {
        options = {
          localStart: 0,
          localEndInclusive: Number.MAX_VALUE,
        }
      }
      return await uploadFrom(source, {
        ftp: this.ftp,
        tracker: this._progressTracker,
        command,
        remotePath: validPath,
        type: "upload"
      },
        options,
        onError)
    }
    finally {
      if (this.ftp && this.ftp.dataSocket) {
        this.ftp.dataSocket.off('error')
        onError = null;
      }
    }
  }

  /**
   * Download a remote file and pipe its data to a writable stream or to a local file.
   *
   * You can optionally define at which position of the remote file you'd like to start
   * downloading. If the destination you provide is a file, the offset will be applied
   * to it as well. For example: To resume a failed download, you'd request the size of
   * the local, partially downloaded file and use that as the offset. Assuming the size
   * is 23, you'd download the rest using `downloadTo("local.txt", "remote.txt", 23)`.
   *
   * @param destination  Stream or path for a local file to write to.
   * @param fromRemotePath  Path of the remote file to read from.
   * @param startAt  Position within the remote file to start downloading at. If the destination is a file, this offset is also applied to it.
   */
  async downloadTo(destination: fs.Stream | string, fromRemotePath: string, startAt = 0) {
    if (typeof destination === "string") {
      return this._downloadToFile(destination, fromRemotePath, startAt)
    }
    return this._downloadToStream(destination, fromRemotePath, startAt)
  }

  /**
   * @protected
   */
  protected async _downloadToFile(localPath: string, remotePath: string, startAt: number) {
    const appendingToLocalFile = startAt > 0
    const [destinationErr, destination] = await to<fs.Stream>(fs.createStream(localPath, 'a+'))
    if (destinationErr) throw destinationErr
    if (!destination) throw new Error('createStream fail')
    try {
      let fileSize = 0;
      if (remotePath) {
        let [fileSizeErr, fileSizeNew] = await to<number>(this.size(remotePath))
        if (fileSizeErr) throw fileSizeErr
        fileSize = fileSizeNew
      }
      return await this._downloadToStream(destination, remotePath, startAt, fileSize)
    }
    catch (err) {
      const localFileStats = await ignoreError(() => {
        return fs.stat(localPath)
      })
      const hasDownloadedData = localFileStats && localFileStats.size > 0
      const shouldRemoveLocalFile = !appendingToLocalFile && !hasDownloadedData
      if (shouldRemoveLocalFile) {
        await ignoreError(() => {
          return fs.unlink(localPath)
        })
      }
      throw err
    }
    finally {
      let [err, closeInfo] = await to<void>(ignoreError(() => {
        if (destination) {
          return destination.close()
        } else {
          return new Promise(function (resolve, reject) {
            reject('destination is null,close fail')
          })
        }
      })
      )
      if (err) throw err;
    }
  }

  /**
   * @protected
   */
  protected async _downloadToStream(destination: fs.Stream, remotePath: string, startAt: number, fileSize: number = 0): Promise<FTPResponse> {
    let onError = (err: ClientError) => this.ftp.closeWithError(err)
    try {
      const validPath = await this.protectWhitespace(remotePath)
      await this.prepareTransfer(this.ftp)
      // Keep the keyword `await` or the `finally` clause below runs too early
      // and removes the event listener for the source stream too early.
      return await downloadTo(destination, {
        ftp: this.ftp,
        tracker: this._progressTracker,
        command: startAt > 0 ? `REST ${startAt}` : `RETR ${validPath}`,
        remotePath: validPath,
        type: "download",
        fileSize: fileSize
      }, onError)
    }
    finally {
      if (this.ftp && this.ftp.dataSocket) {
        this.ftp.dataSocket.off('error')
        onError = null;
      }
      if (destination) {
        await destination.flush()
      }
    }
  }

  /**
   * List files and directories in the current working directory, or from `path` if specified.
   *
   * @param [path]  Path to remote file or directory.
   */
  async list(path = ""): Promise<FileInfo[]> {
    const validPath = await this.protectWhitespace(path)
    let lastError: any
    for (const candidate of this.availableListCommands) {
      const command = validPath === "" ? candidate : `${candidate} ${validPath}`
      await this.prepareTransfer(this.ftp)
      try {
        const parsedList = await this._requestListWithCommand(command)
        // Use successful candidate for all subsequent requests.
        this.availableListCommands = [candidate]
        return parsedList
      }
      catch (err) {
        const shouldTryNext = err instanceof FTPError
        if (!shouldTryNext) {
          return new Promise(function (resolve, reject) {
            reject(err)
          })
        }
        lastError = err
      }
    }
    return new Promise(function (resolve, reject) {
      reject(lastError)
    })
  }

  /**
   * @protected
   */
  protected async _requestListWithCommand(command: string): Promise<FileInfo[]> {
    if (!this.context || !this.context.cacheDir) {
      return new Promise(function (resolve, reject) {
        reject(new Error('can not cache temp data because not set global context'))
      })
    }

    let tempPath = this.context.cacheDir + '/' + (new Date().getTime()) + ".temp";
    let [outputStreamErr, outputStream] = await to<fs.Stream>(fs.createStream(tempPath, 'a+'))
    if (outputStreamErr) {
      return new Promise(function (resolve, reject) {
        fs.unlinkSync(tempPath)
        reject(inputStreamErr)
      })
    }
    if (!outputStream) {
      return new Promise(function (resolve, reject) {
        fs.unlinkSync(tempPath)
        reject(new Error('create outputStream fail'))
      })
    }

    let onError = (err) => {
      fs.unlinkSync(tempPath)
    }
    let [downloadToErr, downloadToInfo] = await to<FTPResponse>(downloadTo(outputStream, {
      ftp: this.ftp,
      tracker: this._progressTracker,
      command,
      remotePath: "",
      type: "list"
    }, onError)
    )
    if (downloadToErr) {
      return new Promise(function (resolve, reject) {
        fs.unlinkSync(tempPath)
        reject(downloadToErr)
      })
    }
    outputStream.closeSync()

    let buff = new ArrayBuffer(8192)
    let [statErr, total] = await to<fs.Stat>(fs.stat(tempPath))
    if (statErr) {
      return new Promise(function (resolve, reject) {
        fs.unlinkSync(tempPath)
        reject(statErr)
      })
    }
    if (!total) {
      return new Promise(function (resolve, reject) {
        fs.unlinkSync(tempPath)
        reject(new Error('get temp file stat fail'))
      })
    }
    let [inputStreamErr, inputStream] = await to<fs.Stream>(fs.createStream(tempPath, 'a+'))
    if (inputStreamErr) {
      return new Promise(function (resolve, reject) {
        fs.unlinkSync(tempPath)
        reject(inputStreamErr)
      })
    }
    if (!inputStream) {
      return new Promise(function (resolve, reject) {
        fs.unlinkSync(tempPath)
        reject(new Error('create inputStream fail'))
      })
    }

    let readSize = 0;
    let [readErr, readLen] = await to<number>(inputStream.read(buff, { offset: readSize }))
    if (readErr) {
      return new Promise(function (resolve, reject) {
        fs.unlinkSync(tempPath)
        reject(statErr)
      })
    }
    readSize += readLen;
    let text = ''
    let encodingStr = ''
    if (this.ftp && this.ftp.encoding) {
      encodingStr = this.ftp.encoding;
    } else {
      encodingStr = 'utf8';
    }
    let trueBuff = buff.slice(0, readLen)
    text += buffer.from(trueBuff).toString(encodingStr)
    while (readLen > 0) {
      readLen = await inputStream.read(buff, { offset: readSize })
      let trueBuff = buff.slice(0, readLen)
      text += buffer.from(trueBuff).toString(encodingStr)
      readSize += readLen;
    }
    this.ftp.log(text)
    inputStream.flushSync();
    inputStream.closeSync();
    fs.unlinkSync(tempPath)
    return this.parseList(text)
  }

  /**
   * Remove a directory and all of its content.
   *
   * @param remoteDirPath  The path of the remote directory to delete.
   * @example client.removeDir("foo") // Remove directory 'foo' using a relative path.
   * @example client.removeDir("foo/bar") // Remove directory 'bar' using a relative path.
   * @example client.removeDir("/foo/bar") // Remove directory 'bar' using an absolute path.
   * @example client.removeDir("/") // Remove everything.
   */
  async removeDir(remoteDirPath: string): Promise<void> {
    return this._exitAtCurrentDirectory(async () => {
      await this.cd(remoteDirPath)
      await this.clearWorkingDir()
      if (remoteDirPath !== "/") {
        await this.cdup()
        //==============原库此处存在BUG，cd设置工作目录之后，远程路径需要裁剪掉路径和工作目录重合的部分，只传空文件夹名即可 否则路径不正确会报错=================
        let remoteDirName = ''
        if (remoteDirPath.indexOf('/') != -1) {
          let lastIndex = remoteDirPath.lastIndexOf('/')
          remoteDirName = remoteDirPath.substring(lastIndex + 1, remoteDirPath.length)
        } else if (remoteDirPath.indexOf('\\') != -1) {
          let lastIndex = remoteDirPath.lastIndexOf('\\')
          remoteDirName = remoteDirPath.substring(lastIndex + 1, remoteDirPath.length)
        } else if (remoteDirPath.indexOf('\\\\') != -1) {
          let lastIndex = remoteDirPath.lastIndexOf('\\\\')
          remoteDirName = remoteDirPath.substring(lastIndex + 1, remoteDirPath.length)
        } else {
          remoteDirName = remoteDirPath
        }
        //===============================
        await this.removeEmptyDir(remoteDirName)
      }
    })
  }

  /**
   * Remove all files and directories in the working directory without removing
   * the working directory itself.
   */
  async clearWorkingDir(): Promise<void> {
    for (const file of await this.list()) {
      if (file.isDirectory) {
        await this.cd(file.name)
        await this.clearWorkingDir()
        await this.cdup()
        await this.removeEmptyDir(file.name)
      }
      else {
        await this.remove(file.name)
      }
    }
  }

  /**
   * Upload the contents of a local directory to the remote working directory.
   *
   * This will overwrite existing files with the same names and reuse existing directories.
   * Unrelated files and directories will remain untouched. You can optionally provide a `remoteDirPath`
   * to put the contents inside a directory which will be created if necessary including all
   * intermediate directories. If you did provide a remoteDirPath the working directory will stay
   * the same as before calling this method.
   *
   * @param localDirPath  Local path, e.g. "foo/bar" or "../test"
   * @param [remoteDirPath]  Remote path of a directory to upload to. Working directory if undefined.
   */
  async uploadFromDir(localDirPath: string, remoteDirPath?: string): Promise<void> {
    return this._exitAtCurrentDirectory(async () => {
      if (remoteDirPath) {
        await this.ensureDir(remoteDirPath)
      }
      return await this._uploadToWorkingDir(localDirPath)
    })
  }

  /**
   * @protected
   */
  protected async _uploadToWorkingDir(localDirPath: string): Promise<void> {
    if (this._progressTracker) {
      this._progressTracker.setBytesRead(0)
      this._progressTracker.setBytesWritten(0)
    }
    const files = await fs.listFile(localDirPath)
    for (const file of files) {
      const fullPath = join(localDirPath, file)
      const stats = await fs.stat(fullPath)
      if (stats.isFile()) {
        // 此处属于对原库的优化 需要获取一下状态 一是为了阻塞进度 否则立马开启第二个会直接失败 而是确保socket处于连接状态
        if (this.ftp && this.ftp.socket) {
          let [err, stat] = await to<socket.SocketStateBase>(this.ftp.socket.getState())
          if (err) {
            throw err
          }
          if (!stat) {
            throw new Error('socket get state fail')
          }
          if (!stat.isConnected) {
            throw new Error('socket is not connecting')
          }
        }
        await this.uploadFrom(fullPath, file)
      }
      else if (stats.isDirectory()) {
        await this._openDir(file)
        await this._uploadToWorkingDir(fullPath)
        await this.cdup()
      }
    }
  }

  /**
   * Download all files and directories of the working directory to a local directory.
   *
   * @param localDirPath  The local directory to download to.
   * @param remoteDirPath  Remote directory to download. Current working directory if not specified.
   */
  async downloadToDir(localDirPath: string, remoteDirPath?: string): Promise<void> {
    return this._exitAtCurrentDirectory(async () => {
      if (remoteDirPath) {
        await this.cd(remoteDirPath)
      }
      return await this._downloadFromWorkingDir(localDirPath)
    })
  }

  /**
   * @protected
   */
  protected async _downloadFromWorkingDir(localDirPath: string): Promise<void> {
    if (this._progressTracker) {
      this._progressTracker.setBytesRead(0)
      this._progressTracker.setBytesWritten(0)
    }
    await ensureLocalDirectory(localDirPath)
    for (const file of await this.list()) {
      const localPath = join(localDirPath, file.name)
      if (file.isDirectory) {
        await this.cd(file.name)
        await this._downloadFromWorkingDir(localPath)
        await this.cdup()
      }
      else if (file.isFile) {
        // 此处属于对原库的优化 需要获取一下状态 一是为了阻塞进度 否则立马开启第二个会直接失败 而是确保socket处于连接状态
        if (this.ftp && this.ftp.socket) {
          let [err, stat] = await to<socket.SocketStateBase>(this.ftp.socket.getState())
          if (err) {
            throw err
          }
          if (!stat) {
            throw new Error('socket get state fail')
          }
          if (!stat.isConnected) {
            throw new Error('socket is not connecting')
          }
        }
        await this.downloadTo(localPath, file.name)
      }
    }
  }

  /**
   * Make sure a given remote path exists, creating all directories as necessary.
   * This function also changes the current working directory to the given path.
   */
  async ensureDir(remoteDirPath: string): Promise<void> {
    // If the remoteDirPath was absolute go to root directory.
    if (remoteDirPath.startsWith("/")) {
      await this.cd("/")
    }
    const names = remoteDirPath.split("/").filter(name => name !== "")
    for (const name of names) {
      await this._openDir(name)
    }
  }

  /**
   * Try to create a directory and enter it. This will not raise an exception if the directory
   * couldn't be created if for example it already exists.
   * @protected
   */
  protected async _openDir(dirName: string) {
    await this.sendIgnoringError("MKD " + dirName)
    await this.cd(dirName)
  }

  /**
   * Remove an empty directory, will fail if not empty.
   */
  async removeEmptyDir(path: string): Promise<FTPResponse> {
    const validPath = await this.protectWhitespace(path)
    return this.send(`RMD ${validPath}`)
  }

  /**
   * FTP servers can't handle filenames that have leading whitespace. This method transforms
   * a given path to fix that issue for most cases.
   */
  async protectWhitespace(path: string): Promise<string> {
    if (!path.startsWith(" ")) {
      return path
    }
    // Handle leading whitespace by prepending the absolute path:
    // " test.txt" while being in the root directory becomes "/ test.txt".
    let startTime1 = new Date().getTime();
    const pwd = await this.pwd()
    let endTime1 = new Date().getTime();
    let averageTime1 = ((endTime1 - startTime1) * 1000) / BASE_COUNT;
    console.log("BasicFtpTest : pwd averageTime : " + averageTime1 + "us")
    const absolutePathPrefix = pwd.endsWith("/") ? pwd : pwd + "/"
    return absolutePathPrefix + path
  }

  protected async _exitAtCurrentDirectory<T>(func: () => Promise<T>): Promise<T> {
    const userDir = await this.pwd()
    try {
      return await func()
    }
    finally {
      if (!this.closed) {
        await ignoreError(() => this.cd(userDir))
      }
    }
  }

  /**
   * Try all available transfer strategies and pick the first one that works. Update `client` to
   * use the working strategy for all successive transfer requests.
   *
   * @returns a function that will try the provided strategies.
   */
  protected _enterFirstCompatibleMode(strategies: TransferStrategy[]): TransferStrategy {
    return async (ftp: FTPContext) => {
      ftp.log("Trying to find optimal transfer strategy...")
      let lastError: Error | undefined = undefined
      for (const strategy of strategies) {
        try {
          const res = await strategy(ftp)
          ftp.log("Optimal transfer strategy found.")
          this.prepareTransfer = strategy // eslint-disable-line require-atomic-updates
          return res
        }
        catch (err: any) {
          // Try the next candidate no matter the exact error. It's possible that a server
          // answered incorrectly to a strategy, for example a PASV answer to an EPSV.
          lastError = err
        }
      }
      throw new Error(`None of the available transfer strategies work. Last error response was '${lastError}'.`)
    }
  }

  /**
   * DEPRECATED, use `uploadFrom`.
   * @deprecated
   */
  async upload(source: fs.Stream | string, toRemotePath: string, options: UploadOptions = {}): Promise<FTPResponse> {
    this.ftp.log("Warning: upload() has been deprecated, use uploadFrom().")
    return this.uploadFrom(source, toRemotePath, options)
  }

  /**
   * DEPRECATED, use `appendFrom`.
   * @deprecated
   */
  async append(source: fs.Stream | string, toRemotePath: string, options: UploadOptions = {}): Promise<FTPResponse> {
    this.ftp.log("Warning: append() has been deprecated, use appendFrom().")
    return this.appendFrom(source, toRemotePath, options)
  }

  /**
   * DEPRECATED, use `downloadTo`.
   * @deprecated
   */
  async download(destination: fs.Stream | string, fromRemotePath: string, startAt = 0) {
    this.ftp.log("Warning: download() has been deprecated, use downloadTo().")
    return this.downloadTo(destination, fromRemotePath, startAt)
  }

  /**
   * DEPRECATED, use `uploadFromDir`.
   * @deprecated
   */
  async uploadDir(localDirPath: string, remoteDirPath?: string): Promise<void> {
    this.ftp.log("Warning: uploadDir() has been deprecated, use uploadFromDir().")
    return this.uploadFromDir(localDirPath, remoteDirPath)
  }

  /**
   * DEPRECATED, use `downloadToDir`.
   * @deprecated
   */
  async downloadDir(localDirPath: string): Promise<void> {
    this.ftp.log("Warning: downloadDir() has been deprecated, use downloadToDir().")
    return this.downloadToDir(localDirPath)
  }

  public isClientLogin(): Promise<boolean> {
    const ctx = this;

    return new Promise(async function (resolve, reject) {
      if (ctx.ftp) {
        if (ctx.ftp.closed) {
          resolve(false);
        } else {
          if (ctx.ftp.dataSocket) {
            let [stateErr, state] = await to<socket.SocketStateBase>(ctx.ftp.dataSocket.getState())
            if (stateErr || !state) {
              resolve(false);
            } else {
              resolve(true);
            }
          }
          resolve(true)
        }
      } else {
        resolve(false)
      }

    })
  }
}

async function ensureLocalDirectory(path: string) {
  try {
    await fs.stat(path)
  }
  catch (err) {
    // await fsMkDir(path, { recursive: true })
    await fs.mkdir(path)
  }
}

async function ignoreError<T>(func: () => Promise<T | undefined>) {
  try {
    return await func()
  }
  catch (err) {
    // Ignore
    return undefined
  }
}


