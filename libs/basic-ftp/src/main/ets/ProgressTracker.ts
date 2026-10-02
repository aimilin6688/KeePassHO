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

export type ProgressType = "upload" | "download" | "list"

/**
 * Describes progress of file transfer.
 */
export interface ProgressInfo {
  /** A name describing this info, e.g. the filename of the transfer. */
  readonly name: string
  /** The type of transfer, typically "upload" or "download". */
  readonly type: ProgressType
  /** Transferred bytes in current transfer. */
  readonly bytes: number
  /** Transferred bytes since last counter reset. Useful for tracking multiple transfers. */
  readonly bytesOverall: number
}

export type ProgressHandler = (info: ProgressInfo) => void

/**
 * Tracks progress of one socket data transfer at a time.
 */
export class ProgressTracker {
  bytesOverall = 0
  protected readonly intervalMs = 500
  protected onStop: (stopWithUpdate: boolean) => void = noop
  protected onHandle: ProgressHandler = noop
  private bytesRead: number = 0
  private bytesWritten: number = 0
  private cacheName: string = undefined
  private cacheType: ProgressType = undefined

  public setBytesRead(read: number) {
    this.bytesRead = read
    const ctx = this;
    if (ctx.cacheType && ctx.cacheType == "list") {
      ctx.bytesRead = 0;
      return
    }
    if (read > 0 && ctx.cacheName && ctx.cacheType && this.onHandle) {
      this.onHandle({
        name: ctx.cacheName,
        type: ctx.cacheType,
        bytes: (ctx.bytesRead + ctx.bytesWritten),
        bytesOverall: ctx.bytesOverall
      })
    }
  }

  public getBytesRead() {
    return this.bytesRead;
  }

  public setBytesWritten(write: number) {
    this.bytesWritten = write
    const ctx = this;
    if (ctx.cacheType && ctx.cacheType == "list") {
      ctx.bytesWritten = 0;
      return
    }
    if (write > 0 && ctx.cacheName && ctx.cacheType && this.onHandle) {
      this.onHandle({
        name: ctx.cacheName,
        type: ctx.cacheType,
        bytes: (ctx.bytesRead + ctx.bytesWritten),
        bytesOverall: ctx.bytesOverall
      })
    }
  }

  public getBytesWritten() {
    return this.bytesWritten;
  }
  /**
   * Register a new handler for progress info. Use `undefined` to disable reporting.
   */
  reportTo(onHandle: ProgressHandler = noop) {
    this.onHandle = onHandle
  }

  /**
   * Start tracking transfer progress of a socket.
   *
   * @param socket  The socket to observe.
   * @param name  A name associated with this progress tracking, e.g. a filename.
   * @param type  The type of the transfer, typically "upload" or "download".
   */
  start(socket: socket.TCPSocket | socket.TLSSocket, name: string, type: ProgressType) {
    let lastBytes = 0
    this.cacheName = name;
    this.cacheType = type;
    this.onStop = poll(this.intervalMs, () => {
      const bytes = this.bytesRead + this.bytesWritten
      this.bytesOverall += bytes - lastBytes
      lastBytes = bytes
      if (this.onHandle) {
        this.onHandle({
          name,
          type,
          bytes,
          bytesOverall: this.bytesOverall
        })
      }

    })
  }

  /**
   * Stop tracking transfer progress.
   */
  stop() {
    this.onStop(false)
  }

  /**
   * Call the progress handler one more time, then stop tracking.
   */
  updateAndStop() {
    this.cacheName = undefined;
    this.cacheType = undefined;
    this.onStop(true)
  }
}

/**
 * Starts calling a callback function at a regular interval. The first call will go out
 * immediately. The function returns a function to stop the polling.
 */
function poll(intervalMs: number, updateFunc: () => void): (stopWithUpdate: boolean) => void {
  const id = setInterval(updateFunc, intervalMs)
  const stopFunc = (stopWithUpdate: boolean) => {
    clearInterval(id)
    if (stopWithUpdate) {
      updateFunc()
    }
    // Prevent repeated calls to stop calling handler.
    updateFunc = noop
  }
  updateFunc()
  return stopFunc
}

function noop() { /*Do nothing*/
}
