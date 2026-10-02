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
 
import fs from '@ohos.file.fs';
import socket from '@ohos.net.socket';
import { UploadOptions } from './Client'
import { describeAddress, describeTLS, ipIsPrivateV4Address } from './netUtils'
import { ClientError, FTPContext, FTPResponse, TaskResolver } from './FtpContext'
import { ProgressTracker, ProgressType } from './ProgressTracker'
import { positiveCompletion, positiveIntermediate } from './parseControlResponse'
import { to } from './PathUtil'
import buffer from '@ohos.buffer';
import ArrayList from '@ohos.util.ArrayList';

export type UploadCommand = "STOR" | "APPE"

class CacheResponseError {
  private response: ArrayList<ArrayBuffer> = new ArrayList<ArrayBuffer>();
  private errInfo: Error;
  private enCoding: string = 'utf8';

  constructor() {
  }

  public setResponse(data: ArrayList<ArrayBuffer>) {
    this.response = data;
  }

  public addResponse(data: ArrayBuffer) {
    if (!this.response) {
      this.response = new ArrayList<ArrayBuffer>();
    }
    if (!data) {
      return
    }
    this.response.add(data);
  }

  public getResponse(): ArrayList<ArrayBuffer> {
    if (!this.response) {
      this.response = new ArrayList<ArrayBuffer>();
    }
    return this.response;
  }

  public setErrorInfo(info: Error) {
    this.errInfo = info;
  }

  public getErrorInfo(): Error {
    return this.errInfo;
  }

  public setEnCoding(encode: string) {
    this.enCoding = encode;
  }

  public getEnCoding(): string {
    return this.enCoding;
  }
}

const cacheData: CacheResponseError = new CacheResponseError()
/**
 * Prepare a data socket using passive mode over IPv6.
 */
export async function enterPassiveModeIPv6(ftp: FTPContext): Promise<FTPResponse> {
  let  startTime1 = new Date().getTime();
  const res = await ftp.request("EPSV")
  const port = parseEpsvResponse(res.message)
  if (!port) {
    throw new Error("Can't parse EPSV response: " + res.message)
  }
  const [hostErr, controlHost] = await to<socket.NetAddress>(ftp.socket.getRemoteAddress())
  if (hostErr || controlHost === undefined) {
    throw new Error("Control socket is disconnected, can't get remote address.")
  }
  await connectForPassiveTransfer(controlHost.address, port, ftp)
  let endTime1 = new Date().getTime();
  let averageTime1 = ((endTime1 - startTime1) * 1000) / 1;
  console.log("BasicFtpTest : enterPassiveModeIPv6 averageTime : " + averageTime1 + "us")
  return res
}

/**
 * Parse an EPSV response. Returns only the port as in EPSV the host of the control connection is used.
 */
export function parseEpsvResponse(message: string): number {
  // Get port from EPSV response, e.g. "229 Entering Extended Passive Mode (|||6446|)"
  // Some FTP Servers such as the one on IBM i (OS/400) use ! instead of | in their EPSV response.
  const groups = message.match(/[|!]{3}(.+)[|!]/)
  if (groups === null || groups[1] === undefined) {
    throw new Error(`Can't parse response to 'EPSV': ${message}`)
  }
  const port = parseInt(groups[1], 10)
  if (Number.isNaN(port)) {
    throw new Error(`Can't parse response to 'EPSV', port is not a number: ${message}`)
  }
  return port
}

/**
 * Prepare a data socket using passive mode over IPv4.
 */
export async function enterPassiveModeIPv4(ftp: FTPContext): Promise<FTPResponse> {
  let  startTime1 = new Date().getTime();
  const res = await ftp.request("PASV")
  const target = parsePasvResponse(res.message)
  if (!target) {
    throw new Error("Can't parse PASV response: " + res.message)
  }
  // If the host in the PASV response has a local address while the control connection hasn't,
  // we assume a NAT issue and use the IP of the control connection as the target for the data connection.
  // We can't always perform this replacement because it's possible (although unlikely) that the FTP server
  // indeed uses a different host for data connections.
  const [hostErr, controlHost] = await to<socket.NetAddress>(ftp.socket.getRemoteAddress())
  if (ipIsPrivateV4Address(target.host) && controlHost && !ipIsPrivateV4Address(controlHost.address)) {
    target.host = controlHost.address
  }
  await connectForPassiveTransfer(target.host, target.port, ftp)
  let endTime1 = new Date().getTime();
  let averageTime1 = ((endTime1 - startTime1) * 1000) / 1;
  console.log("BasicFtpTest : enterPassiveModeIPv4 averageTime : " + averageTime1 + "us")
  return res
}

/**
 * Parse a PASV response.
 */
export function parsePasvResponse(message: string): {
  host: string,
  port: number
} {
  // Get host and port from PASV response, e.g. "227 Entering Passive Mode (192,168,1,100,10,229)"
  const groups = message.match(/([-\d]+,[-\d]+,[-\d]+,[-\d]+),([-\d]+),([-\d]+)/)
  if (groups === null || groups.length !== 4) {
    throw new Error(`Can't parse response to 'PASV': ${message}`)
  }
  return {
    host: groups[1].replace(/,/g, "."),
    port: (parseInt(groups[2], 10) & 255) * 256 + (parseInt(groups[3], 10) & 255)
  }
}

export async function connectForPassiveTransfer(host: string, port: number, ftp: FTPContext): Promise<void> {
  if (!ftp) {
    return new Promise(function (resolve, reject) {
      reject(new Error('ftp can not be null'))
    })
  }
  let socket = await ftp._newSocket()
  if (!socket) {
    return new Promise(function (resolve, reject) {
      reject(new Error('socket can not be null'))
    })
  }

  const handleConnErr = function (err: Error) {
    err.message = "Can't open data connection in passive mode: " + err.message
    if (cacheData) {
      cacheData.setEnCoding(null);
      cacheData.setResponse(null);
      cacheData.setErrorInfo(err);
    }
    return new Promise(function (resolve, reject) {
      reject(err)
    })
  }
  const handleTimeout = async function () {
    await socket.close()
    return new Promise(function (resolve, reject) {
      reject(new Error(`Timeout when trying to open data connection to ${host}:${port}`))
    })
  }
  let [extraErr, ExtraInfo] = await to<void>(socket.setExtraOptions({
    socketTimeout: ftp.timeout,
    keepAlive: false,
    TCPNoDelay: true,
    reuseAddress: false
  }))
  if (extraErr) {
    return new Promise(function (resolve, reject) {
      reject(extraErr)
    })
  }
  socket.on("error", handleConnErr)
  // socket.on("timeout", handleTimeout)
  socket.on('message', (value) => {
    if (!cacheData) {
      return new Promise(function (resolve, reject) {
        reject(new Error('cacheData is null'))
      })
    }
    if (value) {
      cacheData.addResponse(value.message)
      cacheData.setErrorInfo(null)
    } else {
      let err = new Error('get data null');
      cacheData.setResponse(null);
      cacheData.setErrorInfo(err);
      return new Promise(function (resolve, reject) {
        reject(err)
      })
    }
  })
  socket.on('connect', () => {
    if (cacheData) {
      cacheData.setEnCoding(null);
      cacheData.setResponse(null);
      cacheData.setErrorInfo(null);
    }
  })
  socket.on('close', () => {
    if (cacheData) {
      cacheData.setErrorInfo(null);
    }
  })
  if ('getCipherSuite' in socket) {
    let tempSocket = socket as socket.TLSSocket;
    ftp.tlsOptions.address.port = port;
    ftp.tlsOptions.address.address = host;
    ftp.tlsOptions.address.family = ftp.ipFamily ? ftp.ipFamily : 1;
    let [connectErr, connectInfo] = await to<void>(tempSocket.connect(ftp.tlsOptions))
    if (connectErr) {
      return new Promise(function (resolve, reject) {
        reject(connectErr)
      })
    }
    tempSocket.off('error', handleConnErr);
    ftp.dataSocket = socket;
    return new Promise(function (resolve, reject) {
      resolve();
    })
  } else {
    let tempSocket = socket as socket.TCPSocket;
    let [connectErr, connectInfo] = await to<void>(tempSocket.connect({
      address: {
        address: host,
        port: port,
        family: ftp.ipFamily ? ftp.ipFamily : 1
      }
    }))
    if (connectErr) {
      return new Promise(function (resolve, reject) {
        reject(connectErr);
      })
    }
    tempSocket.off('error', handleConnErr);
    ftp.dataSocket = socket;
    return new Promise(function (resolve, reject) {
      resolve();
    })
  }
}

/**
 * Helps resolving/rejecting transfers.
 *
 * This is used internally for all FTP transfers. For example when downloading, the server might confirm
 * with "226 Transfer complete" when in fact the download on the data connection has not finished
 * yet. With all transfers we make sure that a) the result arrived and b) has been confirmed by
 * e.g. the control connection. We just don't know in which order this will happen.
 */
class TransferResolver {
  protected response: FTPResponse | undefined = undefined
  protected dataTransferDone = false

  /**
   * Instantiate a TransferResolver
   */
  constructor(readonly ftp: FTPContext, readonly progress: ProgressTracker) {
  }

  /**
   * Mark the beginning of a transfer.
   *
   * @param name - Name of the transfer, usually the filename.
   * @param type - Type of transfer, usually "upload" or "download".
   */
  async onDataStart(name: string, type: ProgressType) {
    // Let the data socket be in charge of tracking timeouts during transfer.
    // The control socket sits idle during this time anyway and might provoke
    // a timeout unnecessarily. The control connection will take care
    // of timeouts again once data transfer is complete or failed.
    if (!this.ftp || !this.ftp.dataSocket) {
      throw new Error("Data transfer should start but there is no data connection.")
    }
    if (this.ftp.socket) {
      let [extraErr, extraInfo] = await to<void>(this.ftp.socket.setExtraOptions({
        socketTimeout: 0
      }))
      if (extraErr) {
        throw extraErr
      }
    }

    let [dataExtraErr, dataExtraInfo] = await to<void>(this.ftp.dataSocket.setExtraOptions({
      socketTimeout: this.ftp.timeout ? this.ftp.timeout : 0,
      keepAlive: false,
      TCPNoDelay: true,
      reuseAddress: false
    }))
    if (dataExtraErr) {
      throw dataExtraErr
    }
    if (this.progress) {
      this.progress.start(this.ftp.dataSocket, name, type)
    }

  }

  /**
   * The data connection has finished the transfer.
   */
  async onDataDone(task: TaskResolver): Promise<void> {
    this.progress.updateAndStop()
    // Hand-over timeout tracking back to the control connection. It's possible that
    // we don't receive the response over the control connection that the transfer is
    // done. In this case, we want to correctly associate the resulting timeout with
    // the control connection.
    if (this.ftp.socket) {
      let [stateErr, stateInfo] = await to<socket.SocketStateBase>(this.ftp.socket.getState())
      if (stateErr) {
        return new Promise<void>(function (resolve, reject) {
          reject(stateErr)
        })
      }
      if (!stateInfo) {
        return new Promise<void>(function (resolve, reject) {
          reject(new Error('get state is fail'))
        })
      }
      if (!stateInfo.isConnected) {
        return new Promise<void>(function (resolve, reject) {
          reject(new Error('socket is disconnected'))
        })
      }
      let [extraErr, extraInfo] = await to<void>(this.ftp.socket.setExtraOptions({
        socketTimeout: this.ftp.timeout ? this.ftp.timeout : 0
      }))
      if (extraErr) {
        return new Promise<void>(function (resolve, reject) {
          reject(extraErr)
        })
      }
    }

    if (this.ftp.dataSocket) {
      let [stateErr, stateInfo] = await to<socket.SocketStateBase>(this.ftp.dataSocket.getState())
      if (!stateErr && stateInfo && stateInfo.isConnected) {
        let [dataExtraErr, dataExtraInfo] = await to<void>(this.ftp.dataSocket.setExtraOptions({
          socketTimeout: 0,
          keepAlive: false,
          TCPNoDelay: true,
          reuseAddress: false
        }))
        if (dataExtraErr) {
          return new Promise<void>(function (resolve, reject) {
            reject(dataExtraErr)
          })
        }
      }
    }
    this.dataTransferDone = true
    this.tryResolve(task)
    return new Promise<void>(function (resolve, reject) {
      resolve()
    })
  }

  /**
   * The control connection reports the transfer as finished.
   */
  onControlDone(task: TaskResolver, response: FTPResponse) {
    this.response = response
    this.tryResolve(task)
  }

  /**
   * An error has been reported and the task should be rejected.
   */
  async onError(task: TaskResolver, err: Error) {
    this.progress.updateAndStop()
    if (this.ftp && this.ftp.socket) {
      await this.ftp.socket.setExtraOptions({
        socketTimeout: this.ftp.timeout
      })
    }
    this.ftp.dataSocket = undefined
    task.reject(err)
  }

  /**
   * Control connection sent an unexpected request requiring a response from our part. We
   * can't provide that (because unknown) and have to close the contrext with an error because
   * the FTP server is now caught up in a state we can't resolve.
   */
  onUnexpectedRequest(response: FTPResponse) {
    const err = new ClientError(`Unexpected FTP response is requesting an answer: ${response.message}`)
    this.ftp.closeWithError(err)
  }

  protected tryResolve(task: TaskResolver) {
    // To resolve, we need both control and data connection to report that the transfer is done.
    const canResolve = this.dataTransferDone && this.response !== undefined
    if (canResolve) {
      this.ftp.dataSocket = undefined
      task.resolve(this.response)
    }
  }
}

export interface TransferConfig {
  command: string
  remotePath: string
  type: ProgressType
  ftp: FTPContext
  tracker: ProgressTracker,
  fileSize?: number,
}


export function uploadFrom(source: fs.Stream, config: TransferConfig, options: UploadOptions, errCallback: Function): Promise<FTPResponse> {
  const resolver = new TransferResolver(config.ftp, config.tracker)
  const fullCommand = `${config.command} ${config.remotePath}`
  return config.ftp.handle(fullCommand, async (res, task) => {
    if (res instanceof Error) {
      resolver.onError(task, res)
    }
    else if (res.code === 150 || res.code === 125) { // Ready to upload
      const dataSocket = config.ftp.dataSocket
      if (!dataSocket) {
        resolver.onError(task, new Error("Upload should begin but no data connection is available."))
        return
      }
      // If we are using TLS, we have to wait until the dataSocket issued
      // 'secureConnect'. If this hasn't happened yet, getCipher() returns undefined.
      const isHttps = 'getCipherSuite' in dataSocket ? true : false
      let canUpload = false;
      let [stateErr, stateInfo] = await to<socket.SocketStateBase>(dataSocket.getState())
      if (stateErr || !stateInfo) {
        resolver.onError(task, new Error('get state is fail'))
        return
      }
      if (stateInfo.isBound && stateInfo.isConnected) {
        canUpload = true;
      } else {
        canUpload = false;
      }
      let cache = 0;
      if (config && config.tracker) {
        cache = config.tracker.getBytesRead() + config.tracker.getBytesWritten();
      }
      onConditionOrEvent(canUpload, dataSocket, "secureConnect", async () => {
        let [addressErr, addressInfo] = await to<string>(describeAddress(dataSocket))
        if (addressErr) {
          throw addressErr;
        }
        let [tlsErr, tlsInfo] = await to<string>(describeTLS(dataSocket))
        if (tlsErr) {
          throw tlsErr;
        }
        config.ftp.log(`Uploading to ${addressInfo} (${tlsInfo})`)
        resolver.onDataStart(config.remotePath, config.type)
        let readBuffer: ArrayBuffer = new ArrayBuffer(8192);
        try {
          dataSocket.on('error', err => {
            resolver.onError(task, err);
            errCallback(err);
          })
          let readSize = 0;
          let readLen = Number.MAX_VALUE;
          while (readLen > 0) {
            if (readLen === Number.MAX_VALUE) {
              readLen = 0;
            }
            let start = options.localStart + readSize;
            let end = options.localEndInclusive;

            let lastSize = 0;
            if (start + readBuffer.byteLength > end) {
              lastSize = end - start;
              if (lastSize > readBuffer.byteLength) {
                lastSize = 0;
              }
            }

            if (lastSize > 0) {
              readLen = await source.read(readBuffer, {
                offset: start,
                length: lastSize
              })
            } else {
              readLen = await  source.read(readBuffer, {
                offset: start
              })
            }
            await source.flush();
            if (readLen <= 0) {
              break;
            }
            let trueData = readBuffer.slice(0, readLen)
            if (isHttps) {
              let localTlsSocket = dataSocket as socket.TLSSocket;
              await localTlsSocket.send(trueData);
            } else {
              let localTlsSocket = dataSocket as socket.TCPSocket;
              await localTlsSocket.send({
                data: trueData,
                encoding: config.ftp.encoding ? config.ftp.encoding : 'utf8'
              });
            }
            readSize += readLen;
            if (config && config.tracker) {
              config.tracker.setBytesRead(readSize + cache)
              config.tracker.setBytesWritten(0)
            }
          }
          dataSocket.off('message');
          dataSocket.off('connect');
          dataSocket.off('error');
          await dataSocket.close();
          dataSocket.off('close');
          await resolver.onDataDone(task);
        } catch (err) {
          resolver.onError(task, err);
        }
      })
    }
    else if (positiveCompletion(res.code)) { // Transfer complete
      resolver.onControlDone(task, res)
    }
    else if (positiveIntermediate(res.code)) {
      resolver.onUnexpectedRequest(res)
    }
    // Ignore all other positive preliminary response codes (< 200)
  })
}

export function downloadTo(destination: fs.Stream, config: TransferConfig, errCallback: Function): Promise<FTPResponse> {
  if (!config.ftp.dataSocket) {
    throw new Error("Download will be initiated but no data connection is available.")
  }
  if (!destination) {
    throw new Error("Stream can not be null.")
  }
  const resolver = new TransferResolver(config.ftp, config.tracker)
  let cache = 0;
  if (config && config.tracker) {
    cache = config.tracker.getBytesRead() + config.tracker.getBytesWritten();
  }
  return config.ftp.handle(config.command, async (res, task) => {
    if (res instanceof Error) {
      resolver.onError(task, res)
    } else if (res.code === 150 || res.code === 125) { // Ready to download
      const dataSocket = config.ftp.dataSocket
      if (!dataSocket) {
        resolver.onError(task, new Error("Download should begin but no data connection is available."))
        return
      }
      let [addressErr, addressInfo] = await to<string>(describeAddress(dataSocket))
      if (addressErr) {
        throw addressErr;
      }
      let [tlsErr, tlsInfo] = await to<string>(describeTLS(dataSocket))
      if (tlsErr) {
        throw tlsErr;
      }
      config.ftp.log(`Downloading from ${addressInfo} (${tlsInfo})`)
      resolver.onDataStart(config.remotePath, config.type)
      let configTimeOut = (config.ftp.timeout <= 0) ? Number.MAX_VALUE : config.ftp.timeout
      let timeOut = 0;
      let cacheSize = 0; //记录当前下载以及写入的进度
      // 如果下载传入了文件路径，可以通过client的size获取服务器文件长度， 如果是list接口，获取的是目录无法获取文件长度，按照下方逻辑来做优化
      // 由于socket不返回需要下载的文件总长度，所以遇到fileSize为0的情况，onMessage那里就不知道何时数据传输结束，
      // 这里通过判断cacheData.getResponse()的集合长度，当长度为0的时候，下方定时器连续10次（以count来计数）都是0 那么判断onMessage没有回调 数据传输结束 可以结束数据传输 用于关闭dataSocket
      let count = 0;
      if (!config.fileSize) {
        config.fileSize = 0;
      }
      let [resultErr, resultPromise] = await to<CacheResponseError>(new Promise(function (resolve, reject) {
        let intervalId = setInterval(async function () {
          timeOut = timeOut + 20;
          if (!cacheData) {
            clearInterval(intervalId);
            reject(new Error('cache data is null'))
          }
          let data = cacheData.getResponse();
          let errInfo = cacheData.getErrorInfo();
          if (errInfo) {
            resolver.onError(task, errInfo)
            if (errCallback) {
              errCallback(errInfo)
            }
            clearInterval(intervalId);
            reject(errInfo)
          }

          if (config.fileSize > 0) {
            if (cacheSize >= config.fileSize) {
              count = 0;
              clearInterval(intervalId);
              resolve(cacheData)
            } else {
              while (data.length > 0) {
                count = 0;
                let tempData = data.removeByIndex(0)
                cacheSize += tempData.byteLength;
                if (config && config.tracker) {
                  config.tracker.setBytesRead(0)
                  config.tracker.setBytesWritten(cacheSize + cache)
                }
                // FIX(binary-safe download): upstream 1.0.3 decoded the raw ArrayBuffer to a UTF-8
                // string before writing, irreversibly corrupting any non-UTF-8 payload (e.g. kdbx).
                // Write the ArrayBuffer as-is; text consumers (Client.list) decode after reading back.
                destination.writeSync(tempData);
                destination.flushSync();
              }
            }
          } else {
            if (data.length == 0) {
              if (count >= 10) {
                count = 0;
                clearInterval(intervalId);
                resolve(cacheData)
              }
              count++;
            } else {
              while (data.length > 0) {
                count = 0;
                let tempData = data.removeByIndex(0)
                cacheSize += tempData.byteLength;
                if (config && config.tracker) {
                  config.tracker.setBytesRead(0)
                  config.tracker.setBytesWritten(cacheSize + cache)
                }
                // FIX(binary-safe download): see comment above.
                destination.writeSync(tempData);
                destination.flushSync();
              }
            }
          }
          // if (timeOut >= configTimeOut) {
          //   clearInterval(intervalId);
          //   reject(new Error('download task timeout'))
          // }
        }, 20)
      }))
      if (resultErr) {
        throw resultErr
      }
      timeOut = 0;
      cacheSize = 0;
      count = 0;
      await resolver.onDataDone(task);
    } else if (res.code === 350) { // Restarting at startAt.
      config.ftp.send("RETR " + config.remotePath)
    } else if (positiveCompletion(res.code)) { // Transfer complete
      resolver.onControlDone(task, res)
    } else if (positiveIntermediate(res.code)) {
      resolver.onUnexpectedRequest(res)
    }
    // Ignore all other positive preliminary response codes (< 200)
  })
}

/**
 * Calls a function immediately if a condition is met or subscribes to an event and calls
 * it once the event is emitted.
 *
 * @param condition  The condition to test.
 * @param emitter  The emitter to use if the condition is not met.
 * @param eventName  The event to subscribe to if the condition is not met.
 * @param action  The function to call.
 */
function onConditionOrEvent(condition: boolean, emitter: socket.TCPSocket | socket.TLSSocket, eventName: string, action: () => void) {
  if (condition === true) {
    action()
  }
  else {
    // emitter.once(eventName, () => action())
    emitter.on('connect', () => {
      action();
    })
  }
}
