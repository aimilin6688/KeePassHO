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

import socket from '@ohos.net.socket';
import { parseControlResponse } from './parseControlResponse'
import { StringEncoding } from './StringEncoding'
import { to } from './PathUtil'
import buffer from '@ohos.buffer';
import connection from '@ohos.net.connection';

interface Task {
  /** Handles a response for a task. */
  readonly responseHandler: ResponseHandler
  /** Resolves or rejects a task. */
  readonly resolver: TaskResolver
  /** Call stack when task was run. */
  readonly stack: string
}

export interface TaskResolver {
  resolve(args: any): void

  reject(err: Error): void
}

export interface FTPResponse {
  /** FTP response code */
  readonly code: number
  /** Whole response including response code */
  readonly message: string
}

export type ResponseHandler = (response: Error | FTPResponse, task: TaskResolver) => void

/**
 * Describes an FTP server error response including the FTP response code.
 */
export class FTPError extends Error {
  /** FTP response code */
  readonly code: number

  constructor(res: FTPResponse) {
    super(res.message)
    this.name = this.constructor.name
    this.code = res.code
  }
}

new Error()

export class ClientError extends Error {
  /** FTP response code */
  public code: string

  constructor(message?: string) {
    super(message)
    this.name = this.constructor.name
  }
}

function doNothing() {
  /** Do nothing */
}

/**
 * FTPContext holds the control and data sockets of an FTP connection and provides a
 * simplified way to interact with an FTP server, handle responses, errors and timeouts.
 *
 * It doesn't implement or use any FTP commands. It's only a foundation to make writing an FTP
 * client as easy as possible. You won't usually instantiate this, but use `Client`.
 */
export class FTPContext {
  /** Debug-level logging of all socket communication. */
  verbose = false
  /** IP version to prefer (4: IPv4, 6: IPv6, undefined: automatic). */
  ipFamily: number | undefined = undefined
  /** Options for TLS connections. */
  tlsOptions: socket.TLSConnectOptions = undefined
  /** Current task to be resolved or rejected. */
  protected _task: Task | undefined
  /** A multiline response might be received as multiple chunks. */
  protected _partialResponse = ""
  /** The reason why a context has been closed. */
  protected _closingError: ClientError | undefined

  /**
   * Instantiate an FTP context.
   *
   * @param timeout - Timeout in milliseconds to apply to control and data connections. Use 0 for no timeout.
   * @param encoding - Encoding to use for control connection. UTF-8 by default. Use "latin1" for older servers.
   */
  constructor(readonly timeout = 0, encoding: StringEncoding = "utf8") {
    this._encoding = encoding
    // Help Typescript understand that we do indeed set _socket in the constructor but use the setter method to do so.
    this.tlsOptions = undefined
    this._dataSocket = undefined
  }

  /** Encoding supported by Node applied to commands, responses and directory listing data. */
  protected _encoding: StringEncoding

  /**
   * Get the currently used encoding.
   */
  get encoding(): StringEncoding {
    return this._encoding
  }

  /**
   * Set the encoding used for the control socket.
   *
   * See https://nodejs.org/api/buffer.html#buffer_buffers_and_character_encodings for what encodings
   * are supported by Node.
   */
  set encoding(encoding: StringEncoding) {
    this._encoding = encoding
    // if (this.socket) {
    //   this.socket.setEncoding(encoding)
    // }
  }

  /** FTP control connection */
  protected _socket: socket.TCPSocket | socket.TLSSocket

  /**
   * Get the FTP control socket.
   */
  get socket(): socket.TCPSocket | socket.TLSSocket {
    return this._socket
  }

  /**
   * Set the socket for the control connection. This will only close the current control socket
   * if the new one is not an upgrade to the current one.
   */
  set socket(sockets: socket.TCPSocket | socket.TLSSocket) {
    // No data socket should be open in any case where the control socket is set or upgraded.
    this.dataSocket = undefined
    // This being a reset, reset any other state apart from the socket.
    // this.tlsOptions = undefined
    this._partialResponse = ""
    if (this._socket) {
      // const newSocketUpgradesExisting = sockets.localPort === this._socket.localPort TODO 无法获取本地绑定的端口号 只能判断两个对象是否为同一个
      const newSocketUpgradesExisting = (sockets === this._socket)
      if (newSocketUpgradesExisting) {
        this._removeSocketListeners(this.socket)
      } else {
        this._closeControlSocket()
      }
    }
    if (sockets) {
      // Setting a completely new control socket is in essence something like a reset. That's
      // why we also close any open data connection above. We can go one step further and reset
      // a possible closing error. That means that a closed FTPContext can be "reopened" by
      // setting a new control socket.
      this._closingError = undefined
      // Don't set a timeout yet. Timeout for control sockets is only active during a task, see handle() below.
      let extraOptions: socket.TCPExtraOptions = {
        keepAlive: false,
        socketTimeout: 0,
        reuseAddress: false,
        TCPNoDelay: true,
      }
      sockets.setExtraOptions(extraOptions).catch((err) => {
        throw err
      })
      sockets.on("message", data => {
        if (!this._encoding || this._encoding.length < 1) {
          this._encoding = 'utf8'
        }
        if (data) {
          let serverData = buffer.from(data.message).toString(this._encoding)
          this._onControlSocketData(serverData)
        } else {
          throw new Error('get data null')
        }
      })
      // Server sending a FIN packet is treated as an error.
      // sockets.on("end", () => this.closeWithError(new Error("Server sent FIN packet unexpectedly, closing connection."))) TODO 没有end回调
      // Control being closed without error by server is treated as an error.
      sockets.on("close", () => {
        this.closeWithError(new ClientError("Server closed connection unexpectedly."))
      })
      this._setupDefaultErrorHandlers(sockets, "control socket")
    }
    this._socket = sockets
  }

  /** FTP data connection */
  protected _dataSocket: socket.TCPSocket | socket.TLSSocket | undefined

  /**
   * Get the current FTP data connection if present.
   */
  get dataSocket(): socket.TCPSocket | socket.TLSSocket | undefined {
    return this._dataSocket
  }

  /**
   * Set the socket for the data connection. This will automatically close the former data socket.
   */
  set dataSocket(socket: socket.TCPSocket | socket.TLSSocket | undefined) {
    this._closeSocket(this._dataSocket)
    if (socket) {
      // Don't set a timeout yet. Timeout data socket should be activated when data transmission starts
      // and timeout on control socket is deactivated.
      socket.setExtraOptions({
        socketTimeout: 0
      }).catch((err) => {
        throw err
      })
      this._setupDefaultErrorHandlers(socket, "data socket")
    }
    this._dataSocket = socket
  }

  /**
   * Returns true if this context has been closed or hasn't been connected yet. You can reopen it with `access`.
   */
  get closed(): boolean {
    // return this.socket.remoteAddress === undefined || this._closingError !== undefined
    try {
      this.socket.getState()
    } catch (err) {
      return true;
    }
    return this._closingError !== undefined
  }

  /**
   * Return true if the control socket is using TLS. This does not mean that a session
   * has already been negotiated.
   */
  get hasTLS(): boolean {
    return "getCipherSuite" in this._socket
  }

  /**
   * Close the context.
   */
  async close(): Promise<void> {
    // Internally, closing a context is always described with an error. If there is still a task running, it will
    // abort with an exception that the user closed the client during a task. If no task is running, no exception is
    // thrown but all newly submitted tasks after that will abort the exception that the client has been closed.
    // In addition the user will get a stack trace pointing to where exactly the client has been closed. So in any
    // case use _closingError to determine whether a context is closed. This also allows us to have a single code-path
    // for closing a context making the implementation easier.
    try {
      const message = this._task ? "User closed client during task" : "User closed client"
      const err = new ClientError(message)
      await this.closeWithError(err)
      return new Promise(function (resolve, reject) {
        resolve()
      })
    } catch (err) {
      return new Promise(function (resolve, reject) {
        reject(err)
      })
    }
  }

  /**
   * Close the context with an error.
   */
  async closeWithError(err: ClientError): Promise<void> {
    // If this context already has been closed, don't overwrite the reason.
    let startTime1 = new Date().getTime();
    if (this._closingError) {
      let endTime1 = new Date().getTime();
      let averageTime1 = ((endTime1 - startTime1) * 1000) / 1;
      console.log("BasicFtpTest : closeWithError averageTime : " + averageTime1 + "us")
      return new Promise(function (resolve, reject) {
        resolve()
      })
    }
    this._closingError = err
    // Close the sockets but don't fully reset this context to preserve `this._closingError`.
    await this._closeControlSocket()
    await this._closeSocket(this._dataSocket)
    // Give the user's task a chance to react, maybe cleanup resources.
    this._passToHandler(err)
    // The task might not have been rejected by the user after receiving the error.
    this._stopTrackingTask()
    let endTime1 = new Date().getTime();
    let averageTime1 = ((endTime1 - startTime1) * 1000) / 1;
    console.log("BasicFtpTest : closeWithError averageTime : " + averageTime1 + "us")
    return new Promise(function (resolve, reject) {
      resolve()
    })
  }

  /**
   * Reset this contex and all of its state.
   */
  async reset(): Promise<void> {
    let startTime0 = new Date().getTime();
    this.socket = await this._newSocket()
    let endTime0 = new Date().getTime();
    let averageTime0 = ((endTime0 - startTime0) * 1000) / 1;
    console.log("BasicFtpTest : socket 带参数接口时长 : " + averageTime0 + "us")
    return new Promise(function (resolve, reject) {
      resolve()
    })
  }

  /**
   * Send an FTP command without waiting for or handling the result.
   */
  send(command: string): Promise<void> {
    const containsPassword = command.startsWith("PASS")
    const message = containsPassword ? "> PASS ###" : `> ${command}`
    this.log(message)
    if (!this._socket) throw new Error('socket can not be null')
    if ('getCertificate' in this._socket) {
      let tempSocket = this._socket as socket.TLSSocket
      return tempSocket.send(command + "\r\n")
    } else {
      let tempSocket = this._socket as socket.TCPSocket
      return tempSocket.send({
        data: command + "\r\n",
        encoding: this.encoding
      })
    }

  }

  /**
   * Send an FTP command and handle the first response. Use this if you have a simple
   * request-response situation.
   */
  request(command: string): Promise<FTPResponse> {
    return this.handle(command, (res, task) => {
      if (res instanceof Error) {
        task.reject(res)
      }
      else {
        task.resolve(res)
      }
    })
  }

  /**
   * Send an FTP command and handle any response until you resolve/reject. Use this if you expect multiple responses
   * to a request. This returns a Promise that will hold whatever the response handler passed on when resolving/rejecting its task.
   */
  handle(command: string | undefined, responseHandler: ResponseHandler): Promise<any> {
    if (this._task) {
      const err = new ClientError("User launched a task while another one is still running. Forgot to use 'await' or '.then()'?")
      err.stack += `\nRunning task launched at: ${this._task.stack}`
      let startTime1 = new Date().getTime();
      this.closeWithError(err)
      let endTime1 = new Date().getTime();
      let averageTime1 = ((endTime1 - startTime1) * 1000) / 1;
      console.log("BasicFtpTest : closeWithError averageTime : " + averageTime1 + "us")
      // Don't return here, continue with returning the Promise that will then be rejected
      // because the context closed already. That way, users will receive an exception where
      // they called this method by mistake.
    }
    return new Promise(async (resolveTask, rejectTask) => {
      this._task = {
        stack: new Error().stack || "Unknown call stack",
        responseHandler,
        resolver: {
          resolve: arg => {
            this._stopTrackingTask()
            resolveTask(arg)
          },
          reject: err => {
            this._stopTrackingTask()
            rejectTask(err)
          }
        }
      }
      if (this._closingError) {
        // This client has been closed. Provide an error that describes this one as being caused
        // by `_closingError`, include stack traces for both.
        const err = new ClientError(`Client is closed because ${this._closingError.message}`) // Type 'Error' is not correctly defined, doesn't have 'code'.
        err.stack += `${'\n'}Closing reason: ${this._closingError.stack}`
        err.code = this._closingError.code !== undefined ? this._closingError.code : "0"
        this._passToHandler(err)
        return
      }
      // Only track control socket timeout during the lifecycle of a task. This avoids timeouts on idle sockets,
      // the default socket behaviour which is not expected by most users.
      // this.socket.setTimeout(this.timeout)
      let [extraErr, extraInfo] = await to<void>(this.socket.setExtraOptions({ socketTimeout: 0 }))
      if (extraErr) throw extraErr
      if (command) {
        let startTime1 = new Date().getTime();
        this.send(command)
        let endTime1 = new Date().getTime();
        let averageTime1 = ((endTime1 - startTime1) * 1000) / 1;
        console.log("BasicFtpTest : send averageTime : " + averageTime1 + "us")
      }
    })
  }

  /**
   * Log message if set to be verbose.
   */
  log(message: string) {
    if (this.verbose) {
      // tslint:disable-next-line no-console
      console.log(message)
    }
  }

  /**
   * Provide a new socket instance.
   *
   * Internal use only, replaced for unit tests.
   */
  async _newSocket(): Promise<socket.TCPSocket | socket.TLSSocket> {
    let tempSocket;
    if (this.tlsOptions) {
      tempSocket = socket.constructTLSSocketInstance()
    } else {
      tempSocket = socket.constructTCPSocketInstance();
    }
    let [netHandleErr, netHandle] = await to<connection.NetHandle>(connection.getDefaultNet())
    if (netHandleErr) {
      return new Promise(function (resolve, reject) {
        reject(netHandleErr)
      })
    }
    if (!netHandle) {
      return new Promise(function (resolve, reject) {
        reject(new Error('get Default Net is fail'))
      })
    }
    let [netSyncErr, netSyncInfo] = await to<connection.ConnectionProperties>(connection.getConnectionProperties(netHandle))
    if (netSyncErr) {
      return new Promise(function (resolve, reject) {
        reject(netSyncErr)
      })
    }
    if (!netSyncInfo || !netSyncInfo.linkAddresses || netSyncInfo.linkAddresses.length < 1
    || !netSyncInfo.linkAddresses[0] || !netSyncInfo.linkAddresses[0].address) {
      return new Promise(function (resolve, reject) {
        reject(new Error('get local ip is fail'))
      })
    }

    if (!tempSocket) {
      return new Promise(function (resolve, reject) {
        reject(new Error('socket can not be null'))
      })
    }
    let [bindErr, bindInfo] = await to<void>(tempSocket.bind({
      address: netSyncInfo.linkAddresses[0].address.address,
      port: 0,
      family: 1
    }))
    if (bindErr) {
      return new Promise(function (resolve, reject) {
        reject(bindErr)
      })
    }
    return new Promise(function (resolve, reject) {
      resolve(tempSocket)
    })
  }

  /**
   * Removes reference to current task and handler. This won't resolve or reject the task.
   * @protected
   */
  protected _stopTrackingTask() {
    // Disable timeout on control socket if there is no task active.
    if (!this.socket) {
      this._task = undefined
      return;
    }
    this.socket.setExtraOptions({ socketTimeout: 0 }).then(() => {
    }).catch((err) => {
      throw err
    })
    this._task = undefined
  }

  /**
   * Handle incoming data on the control socket. The chunk is going to be of type `string`
   * because we let `socket` handle encoding with `setEncoding`.
   * @protected
   */
  protected _onControlSocketData(chunk: string) {
    this.log(`< ${chunk}`)
    // This chunk might complete an earlier partial response.
    const completeResponse = this._partialResponse + chunk
    const parsed = parseControlResponse(completeResponse)
    // Remember any incomplete remainder.
    this._partialResponse = parsed.rest
    // Each response group is passed along individually.
    for (const message of parsed.messages) {
      const code = parseInt(message.substr(0, 3), 10)
      const response = { code, message }
      const err = code >= 400 ? new FTPError(response) : undefined
      this._passToHandler(err ? err : response)
    }
  }

  /**
   * Send the current handler a response. This is usually a control socket response
   * or a socket event, like an error or timeout.
   * @protected
   */
  protected _passToHandler(response: Error | FTPResponse) {
    if (this._task) {
      this._task.responseHandler(response, this._task.resolver)
    }
    // Errors other than FTPError always close the client. If there isn't an active task to handle the error,
    // the next one submitted will receive it using `_closingError`.
    // There is only one edge-case: If there is an FTPError while no task is active, the error will be dropped.
    // But that means that the user sent an FTP command with no intention of handling the result. So why should the
    // error be handled? Maybe log it at least? Debug logging will already do that and the client stays usable after
    // FTPError. So maybe no need to do anything here.
  }

  /**
   * Setup all error handlers for a socket.
   * @protected
   */
  protected _setupDefaultErrorHandlers(socket: socket.TCPSocket | socket.TLSSocket, identifier: string) {
    // socket.once("error", error => {
    //   error.message += ` (${identifier})`
    //   this.closeWithError(new ClientError(error.message))
    // })
    // socket.once("close", (hadError) => {
    //   if (hadError) {
    //     this.closeWithError(new Error(`Socket closed due to transmission error (${identifier})`))
    //   }
    // })
    // socket.once("timeout", () => {
    //   socket.destroy()
    //   this.closeWithError(new Error(`Timeout (${identifier})`))
    // })
  }

  /**
   * Close the control socket. Sends QUIT, then FIN, and ignores any response or error.
   */
  public async _closeControlSocket(): Promise<void> {
    if (!this._socket) {
      return new Promise(function (resolve, reject) {
        resolve()
      })
    }
    this._removeSocketListeners(this._socket)
    // this._socket.on("error", doNothing)
    let [stateErr, stateInfo] = await to<socket.SocketStateBase>(this._socket.getState())
    if (stateErr) {
      return new Promise(function (resolve, reject) {
        reject(stateErr)
      })
    }
    if (!stateInfo) {
      return new Promise(function (resolve, reject) {
        reject(new ClientError('get state fail'))
      })
    }
    if (stateInfo.isConnected) {
      await this.send("QUIT")
    }
    await this._closeSocket(this._socket)
    return new Promise(function (resolve, reject) {
      resolve()
    })
  }

  /**
   * Close a socket. Sends FIN and ignores any error.
   * @protected
   */
  public async _closeSocket(socket: socket.TCPSocket | socket.TLSSocket | undefined): Promise<void> {
    if (socket) {
      this._removeSocketListeners(socket)
      // socket.on("error", doNothing)
      // socket.on("timeout", () => socket.destroy())
      // socket.setTimeout(this.timeout)
      // socket.end()
      let [closeErr, closeInfo] = await to<void>(socket.close())
      if (closeErr) {
        return new Promise(function (resolve, reject) {
          reject(closeErr)
        })
      }
      socket = undefined;
      return new Promise(function (resolve, reject) {
        resolve()
      })
    }else{
      return new Promise(function (resolve, reject) {
        resolve()
      })
    }
  }

  public async closeOldSocket(socket: socket.TCPSocket | socket.TLSSocket | undefined) {
    if (socket) {
      socket.off('connect');
      socket.off('message');
      socket.off('error');
      let [closeErr, closeInfo] = await to<void>(socket.close())
      if (closeErr) throw closeErr
      socket.off('close');
    }
  }
  /**
   * Remove all default listeners for socket.
   * @protected
   */
  protected _removeSocketListeners(socket: socket.TCPSocket | socket.TLSSocket) {
    socket.off("connect", (data) => {

    })
    socket.off("message", (data) => {

    })
    socket.off("error", (err) => {
      if (err) throw err
    })
    socket.off("close", () => {

    })
  }
}
