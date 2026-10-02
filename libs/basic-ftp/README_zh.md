

## BasicFtp

## 简介

BasicFtp是一个提供FTP/FTPS传输协议的客户端。

## 下载安装

```javascript
ohpm install @ohos/basic-ftp
```

OpenHarmony ohpm
环境配置等更多内容，请参考[如何安装 OpenHarmony ohpm 包](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.md)



## 使用说明

注意：全局搜索项目中的‘xxx’，需要替换修改为真实的邮箱，账号密码,服务器地址。 如需测试ftps加密传输，需要提前准备好自签名证书放置于src/main/resources/rawfile文件夹下，同时替换SamplePage.ets文件的loginServer方法的证书名称。

```
import { AccessOptions, FileInfo, FileType, FTPResponse, UnixPermissions } from '@ohos/basic-ftp'
import buffer from '@ohos.buffer'
import socket from '@ohos.net.socket';
import NoTlsUtil from '../utils/FtpApiUtil'
```


### 登录FTP服务器

  ```javascript
	var loginInfo: AccessOptions = null
    let option: socket.TLSConnectOptions = {
    	ALPNProtocols: ["spdy/1", "http/1.1"],
    	address: {
     	 	address: '',
     	 	port: 50000,
      	 	family: 1
   		 },
    	secureOptions: {
     		 key: '',
      		 cert: '',
      		 ca: [''],
      		 password: '',
      		 protocols: [socket.Protocol.TLSv12, socket.Protocol.TLSv13],
     		 useRemoteCipherPrefer: true,
      		 signatureAlgorithms: "rsa_pss_rsae_sha256:ECDSA+SHA256",
     		 cipherSuite: "AES256-SHA256"
    	}
  	}
	// FTPS 带证书 支持隐式tls加密传输
    if (ctx.secure) {
      loginInfo = {
        host: 'x.x.x.x',
        user: 'xxxxx',
        port: 'xx',
        password: 'xxx',
        secure: 'implicit',
        secureOptions: option
      }
    } else {
        // FTP 不带证书 
      loginInfo = {
        host: 'x.x.x.x',
        user: 'xxxxx',
        port: 'xx',
        password: 'xxx',
        secure: false,
        secureOptions: undefined
      }
    }
  
  ftpUtil.doLogin(loginInfo, {
        onLoginStart(info) {
        },
        onLoginSuccess(result) {        
        },
        onLoginErr(err: Error) {
        }
      })
       
  ```

### 获取文件列表

```javascript
if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          return;
        }
        let startTime1 = new Date().getTime();
        ftpUtil.getCurrentDirectory({
          currentDirectoryErr(err: Error) {
          },
          currentDirectoryStart(info) {
          },
          currentDirectorySuccess(msg) {
            remoteRoot = msg
            let listName = '';
            if (remoteRoot == '' || remoteRoot == '\\' || remoteRoot == '/') {
              listName = ''
            } else {
              listName = msg
            }
            ftpUtil.getList(listName, {
              getListErr(err: Error) {
              },
              getListStart(info) {
              },
              getListSuccess(result: FileInfo[]) {
               
              }
            })

          }
        })
}
```

### upload单个文件

  ```javascript
if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          operationType = ''
          return
        }
        if (!localUploadFilePath || localUploadFilePath.length < 1) {
          operationType = ''
          return
        }
        if (!remoteRoot || remoteRoot.length < 1) {
          operationType = ''
          return
        }
        inputValue = "clientToServer.txt"
        if (!inputValue || inputValue.length < 1) {
          operationType = ''
          return
        }
        ftpUtil.uploadSingleFile(localUploadFilePath, inputValue, {
          uploadErr(err: Error) {
          },
          uploadStart(info) {
          },
          uploadSuccess(msg: FTPResponse) {
            
          },
          uploadProgress(currentSize: number, totalSize: number) {
          }
        })
}
  ```

### upload文件夹

```javascript
 if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          operationType = ''
          return
        }
        if (!localUploadFileDir || localUploadFileDir.length < 1) {
          operationType = ''
          return
        }
        if (!remoteRoot || remoteRoot.length < 1) {
          operationType = ''
          return
        }
        inputValue = "client"
        if (!inputValue || inputValue.length < 1) {
          operationType = ''
          return
        }
        let regex = new RegExp(`^(?!_)(?!.*?_$)[a-zA-Z0-9_u4e00-u9fa5]+$`); //正则表达式
        if (!regex.test(inputValue)) {
          operationType = ''
          return
        }
        ftpUtil.uploadDir(localUploadFileDir, inputValue, {
          uploadDirErr(err: Error) {
          },
          uploadDirStart(info) {
          },
          uploadDirSuccess(msg) {
          },
          uploadDirProgress(currentSize: number, totalSize: number) {
          }
        })
}
```

### 下载单个文件

```javascript
 if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          return
        }
        if (!remoteRoot || remoteRoot.length < 1) {
          return
        }
        selectFilePath = "clientToServer.txt";
        if (!selectFilePath || selectFilePath.length < 1) {
          return
        }
        ftpUtil.downloadSingleFile(localPath, selectFilePath, {
          downloadErr(err: Error) {
            expect(0).assertEqual(1)
            done()
          },
          downloadStart(info) {
          },
          downloadSuccess(msg: FTPResponse) {
          },
          downloadProgress(currentSize: number, totalSize: number) {
          }
        })
}
```

### 下载文件夹

```javascript
  if (ftpUtil) {
          if (!ftpUtil.getLogin()) {
            return
          }
          remoteRoot="/"
          if (!remoteRoot || remoteRoot.length < 1) {
            return
          }
          selectDirPath = "client"
          if (!selectDirPath || selectDirPath.length < 1) {
            return
          }
          ftpUtil.downloadDir(localDir, selectDirPath, {
            downloadDirErr(err: Error) {
            },
            downloadDirStart(info) {
            },
            downloadDirSuccess(msg) {
             
            },
            downloadDirProgress(currentSize: number, totalSize: number) {
            }
          })
}
```

### 获取文件大小

```javascript
if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          return
        }
        if (!remoteRoot || remoteRoot.length < 1) {
          return
        }
        selectFilePath = "clientToServer.txt";
        if (!selectFilePath || selectFilePath.length < 1) {
          return
        }
        ftpUtil.getFileSize(selectFilePath, {
          getSizeErr(err: Error) {
          },
          getSizeStart(info) {
          },
          getSizeSuccess(result: number) {
          }
        })
}
```
### 获取服务器能力

```javascript
 if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          return
        }
        ftpUtil.getServerFeatures({
          featuresErr(err: Error) {
          },
          featuresStart(info) {
          },
          featuresSuccess(msg: Map<string, string>) {
          }
        })
}
```
### 获取最后修改时间

```javascript
 if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          return
        }
        if (!remoteRoot || remoteRoot.length < 1) {
          return
        }
        selectFilePath = "clientToServer.txt";

        if (!selectFilePath || selectFilePath.length < 1) {
          return
        }
        ftpUtil.getLastModify(selectFilePath, {
          lastModifyErr(err: Error) {
          },
          lastModifyStart(info) {
          },
          lastModifySuccess(msg: Date) {
          }
        })
 }
```
### 重命名文件

```javascript
  if (ftpUtil) {
          if (!ftpUtil.getLogin()) {
            operationType = ''
            return
          }
          if (!remoteRoot || remoteRoot.length < 1) {
            operationType = ''
            return
          }

          inputValue = "clientToServerNew.txt"
          if (!inputValue || inputValue.length < 1) {
            operationType = ''
            return
          }
          selectFilePath = "clientToServer.txt";

          if (!selectFilePath || selectFilePath.length < 1) {
            return
          }
          ftpUtil.renameFile(inputValue, selectFilePath, {
            renameFileErr(err: Error) {
            },
            renameFileStart(info) {
              operationType = ''
            },
            renameFileSuccess(result: FTPResponse) {
            }
          })
        }
```
### 切换目录

```javascript
  if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          return
        }
        if (!remoteRoot || remoteRoot.length < 1) {
          return
        }
        ftpUtil.cdToParentDirectory({
          cdToParentDirectoryErr(err: Error) {

          },
          cdToParentDirectoryStart(info) {
          },
          cdToParentDirectorySuccess(res: FTPResponse) {
            
          }
        })
  }
```
### 确认远端路径

```javascript
  if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          operationType = ''
          return
        }
        if (!remoteRoot || remoteRoot.length < 1) {
          operationType = ''
          return
        }
        inputValue = "client"
        if (!inputValue || inputValue.length < 1) {
          operationType = ''
          return
        }
        let regex = new RegExp(`^(?!_)(?!.*?_$)[a-zA-Z0-9_u4e00-u9fa5]+$`); //正则表达式
        if (!regex.test(inputValue)) {
          operationType = ''
          return
        }
        ftpUtil.ensureRemotePath(inputValue, {
          ensureRemotePathErr(err: Error) {
          
          },
          ensureRemotePathStart(info) {
          },
          ensureRemotePathSuccess(result) {
           
          }
        })
      }
```
### 删除空目录

```javascript
if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          return
        }
        remoteRoot="/"
        if (!remoteRoot || remoteRoot.length < 1) {
          return
        }
        selectDirPath = "/testempty"
        if (!selectDirPath || selectDirPath.length < 1) {
          return
        }
        let startTime1 = new Date().getTime();
        ftpUtil.deleteEmptyDirectory(selectDirPath, {
          deleteEmptyDirectoryErr(err: Error) {

          },
          deleteEmptyDirectoryStart(info) {
          },
          deleteEmptyDirectorySuccess(result: FTPResponse) {
           
          }
        })
      }
```
### 删除单个文件

```javascript
 if (ftpUtil) {
          if (!ftpUtil.getLogin()) {
            return
          }
          remoteRoot="/"
          if (!remoteRoot || remoteRoot.length < 1) {
            return
          }
          selectFilePath = "/clientToServerNew.txt";

          if (!selectFilePath || selectFilePath.length < 1) {
            return
          }
          ftpUtil.deleteFile(selectFilePath, {
            deleteFileErr(err: Error) {
            },
            deleteFileStart(info) {
            },
            deleteFileSuccess(msg: FTPResponse) {
            }
          })
}
```

### 删除所有文件

```javascript
  if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          return
        }
        remoteRoot="/"
        if (!remoteRoot || remoteRoot.length < 1) {
          return
        }
        selectDirPath="/deleteAll"
        if (!selectDirPath || selectDirPath.length < 1) {
          return
        }
        let startTime1 = new Date().getTime();
        ftpUtil.deleteAll(selectDirPath, {
          deleteAllErr(err: Error) {

          },
          deleteAllStart(info) {
          },
          deleteAllSuccess(result) {
           
          }
        })
      }
```

### 删除当前目录下的所有文件

```javascript
  if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          return
        }
        remoteRoot="/"
        if (!remoteRoot || remoteRoot.length < 1) {
          return
        }
        remoteChildPath="/deleteSelfBuf"
        let startTime1 = new Date().getTime();
        ftpUtil.setWorkingDirectory(remoteChildPath, {
          setWorkingDirectoryErr(err: Error) {
   
          },
          setWorkingDirectoryStart(info) {
          },
          setWorkingDirectorySuccess(result: FTPResponse) {
            ftpUtil.deleteAllButSelf({
              deleteAllButSelfErr(err: Error) {
       
              },
              deleteAllButSelfStart(info) {
              },
              deleteAllButSelfSuccess(result) {

              }
            })
          }
        })
      }
```

### 设置工作目录

```javascript
   if (ftpUtil) {
        if (!ftpUtil.getLogin()) {
          return
        }
        remoteRoot="/"
        if (!remoteRoot || remoteRoot.length < 1) {
          return
        }
        remoteChildPath="/client"
        if (!remoteChildPath || remoteChildPath.length < 1) {
          return
        }
        ftpUtil.setWorkingDirectory(remoteChildPath, {
          setWorkingDirectoryErr(err: Error) {

          },
          setWorkingDirectoryStart(info) {
          },
          setWorkingDirectorySuccess(result: FTPResponse) {

          }
        })
  }
```

## 接口说明



| 接口名               | 参数                             | 返回值                | 说明                                       |
| ----------------- | ------------------------------ | ------------------ | ---------------------------------------- |
| access    | AccessOptions                   | FTPResponse | 登录FTP服务器|
| list     | string                 | FileInfo | 获取文件列表       |
| size | string                  | number | 获取文件大小                       |
| uploadFrom    | string, string                  | FTPResponse | 上传文件                       |
| downloadTo   | string, string                 | FTPResponse | 下载文件                       |
| features       | 无 | Map<string, string> | 获取服务器能力 |
| cd             | string                             | FTPResponse | 设置工作目录                            |
| cdup               | 无                            | FTPResponse | 从当前工作目录切换到父目录             |
| remove               | string                            | FTPResponse | 删除文件                          |
| lastMod               | string                            | Date | 获取最后修改的时间                          |
| pwd               | 无                            | string | 获取当前目录                          |
| ensureDir               | string                            | void | 确认远程是否存在目录，不存在则会自动创建                |
| removeEmptyDir               | string                            | FTPResponse | 删除选择的文件夹，文件夹不为空则会失败报错       |
| removeDir               | string                            | void | 删除选择的文件夹中所有子文件夹和文件，同时删除选择的文件夹  |
| clearWorkingDir               | 无                            | void | 清空当前文件夹中所有子文件夹和文件，但是保留当前的文件夹  |
| rename               | string, string                            | FTPResponse | 重命名文件                          |
| uploadFromDir               | string, string                            | void | 上传目录                          |
| downloadToDir               | string, string                            | void | 下载目录                          |

## 关于混淆
- 代码混淆，请查看[代码混淆简介](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- 如果希望三方库在代码混淆过程中不会被混淆，需要在混淆规则配置文件obfuscation-rules.txt中添加相应的排除规则：
```
-keep
./oh_modules/@ohos/basic-ftp
```
## 约束与限制
在下述版本验证通过：
DevEco Studio: NEXT Beta1-5.0.3.806, SDK: API12 Release(5.0.0.66)
DevEco Studio版本: 4.0 Release(4.0.3.413), SDK: (4.0.10.3)

本库当前支持ftp被动模式，不支持主动模式；支持FTP,隐式tls加密的FTPS。

本库支持MLSD、Unix、DOS格式的目录列表解析。

本库支持@ohos.file.fs模块支持的文件类型。

本库支持Binary模式传输数据。

## 目录结构

```javascript
|---- BasicFtp  
|     |---- entry  # 示例代码文件夹
|     |---- BasicFtp  # BasicFtp 库文件夹
|     |---- README.MD  # 安装使用方法                   
```

## 贡献代码

使用过程中发现任何问题都可以提 [Issue](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/issues) ，当然，也非常欢迎发 [PR](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/pulls) 共建。

## 开源协议

本项目基于 [MIT](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/blob/master/BasicFtp/LICENSE) ，请自由地享受和参与开源。