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
import { to } from './PathUtil'

/**
 * Returns a string describing the encryption on a given socket instance.
 */
export async function describeTLS(socket: socket.TCPSocket | socket.TLSSocket): Promise<string> {
  if ('getProtocol' in socket) {
    const [protocolErr, protocol] = await to<string>(socket.getProtocol())
    return new Promise(function (resolve, reject) {
      if (protocolErr) {
        reject("getProtocol fail")
      }
        protocol ? resolve(protocol) : reject("Server socket or disconnected client socket")
    })
  } else {
    return new Promise(function (resolve, reject) {
      resolve("No encryption")
    })
  }

}

/**
 * Returns a string describing the remote address of a socket.
 */
export async function describeAddress(socket: socket.TCPSocket | socket.TLSSocket): Promise<string> {
  if ('getRemoteAddress' in socket) {
    const [remoteAddressErr, remoteAddress] = await to<socket.NetAddress>(socket.getRemoteAddress())
    if (remoteAddressErr || !remoteAddress) {
      return new Promise(function (resolve, reject) {
        reject("getRemoteAddress fail")
      })
    }
    if (remoteAddress.family === 2) {
      return new Promise(function (resolve, reject) {
        resolve(`[${remoteAddress.address}]:${remoteAddress.port}`)
      })
    } else {
      return new Promise(function (resolve, reject) {
        resolve(`${remoteAddress.address}:${remoteAddress.port}`)
      })
    }
  }
  return new Promise(function (resolve, reject) {
    reject('socket is not have getRemoteAddress api')
  })
}

/**
 * Upgrade a socket connection with TLS.
 * 不支持tcpSocket转tlsSocket
 */
export function upgradeSocket(socket: socket.TLSSocket, options: socket.TLSConnectOptions): Promise<socket.TLSSocket> {
  return new Promise(async (resolve, reject) => {
    const [err, tlsSocket] = await to<socket.TLSSocket>(connectTLS(socket, options, null));
    if (err) {
      return new Promise(function (resolve, reject) {
        reject(err)
      })
    }
    tlsSocket.off("error")
    return new Promise<socket.TLSSocket>(function (resolve, reject) {
      resolve(tlsSocket)
    })
  })
}

/**
 * Returns true if an IP is a private address according to https://tools.ietf.org/html/rfc1918#section-3.
 * This will handle IPv4-mapped IPv6 addresses correctly but return false for all other IPv6 addresses.
 *
 * @param ip  The IP as a string, e.g. "192.168.0.1"
 */
export function ipIsPrivateV4Address(ip = ""): boolean {
  // Handle IPv4-mapped IPv6 addresses like ::ffff:192.168.0.1
  if (ip.startsWith("::ffff:")) {
    ip = ip.substr(7) // Strip ::ffff: prefix
  }
  const octets = ip.split(".").map(o => parseInt(o, 10))
  return octets[0] === 10 // 10.0.0.0 - 10.255.255.255
  || (octets[0] === 172 && octets[1] >= 16 && octets[1] <= 31) // 172.16.0.0 - 172.31.255.255
  || (octets[0] === 192 && octets[1] === 168) // 192.168.0.0 - 192.168.255.255
  || ip === "127.0.0.1"
}


async function connectTLS(localSocket: socket.TLSSocket, options: socket.TLSConnectOptions, secureConnectListener?: () => void): Promise<socket.TLSSocket> {
  if (localSocket) {
    if (!options || !options.address || !options.secureOptions) {
      return new Promise(function (resolve, reject) {
        reject(new Error('tlsOptions param must be a valid data'))
      })
    }
    this.ftp.tlsOptions = options;
    let [connectErr, connectInfo] = await to<void>(localSocket.connect(options))
    if (connectErr) {
      throw connectErr
    }
    if (secureConnectListener && typeof secureConnectListener === 'function') {
      secureConnectListener()
    }
    let data = await to<string>(describeTLS(localSocket))
    let result = await to<string>(describeAddress(localSocket))
    this.ftp.log(`Connected to ${result} (${data})`)
    return new Promise(function (resolve, reject) {
      resolve(localSocket)
    })
  }else {
    return new Promise(function (resolve, reject) {
      reject(new Error('socket params is null'))
    })
  }
}

