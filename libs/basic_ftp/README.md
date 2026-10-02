

## BasicFtp

## Introduction

BasicFtp is a client that supports FTP and FTPS transfer protocols.

## How to Install

```javascript
ohpm install @ohos/basic-ftp
```

OpenHarmony ohpm
For details about the OpenHarmony ohpm environment configuration, see [OpenHarmony HAR](https://gitcode.com/openharmony-tpc/docs/blob/master/OpenHarmony_har_usage.en.md).

## How to Use

Note: Globally search *xxx* in the project and replace them with the actual email address, account password, and server address. To test FTPS encrypted transfers, you need to place a self-signed certificate in **src/main/resources/rawfile** and replace the certificate name of **loginServer** in the **SamplePage.ets** file with the self-signed certificate name.

```
import { AccessOptions, FileInfo, FileType, FTPResponse, UnixPermissions } from '@ohos/basic-ftp'
import buffer from '@ohos.buffer'
import socket from '@ohos.net.socket';
import NoTlsUtil from '../utils/FtpApiUtil'
```


### Logging In to the FTP Server

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
	// FTPS with a certificate supports implicit TLS encryption transmission.
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
        // FTP without a certificate.
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

### Obtaining the File List

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

### Uploading a Single File

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

### Uploading a Folder

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
        let regex = new RegExp(`^(?!_)(?!.*?_$)[a-zA-Z0-9_u4e00-u9fa5]+$`); // Regular expression.
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

### Downloading a Single File

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

### Downloading a Folder

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

### Obtaining the File Size

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
### Obtaining Server Capabilities

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
### Obtaining the Last Modification Time

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
### Renaming a File

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
### Switching the Directory

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
### Confirming the Remote Path

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
        let regex = new RegExp(`^(?!_)(?!.*?_$)[a-zA-Z0-9_u4e00-u9fa5]+$`); // Regular expression.
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
### Deleting an Empty Directory

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
### Deleting a Single File

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

### Deleting All Files

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

### Deleting All Files in the Current Directory

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

### Setting a Working Directory

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

## Available APIs



| API              | Parameters                            | Return Value               | Description                                      |
| ----------------- | ------------------------------ | ------------------ | ---------------------------------------- |
| access    | AccessOptions                   | FTPResponse | Logs in to the FTP server.|
| list     | string                 | FileInfo | Obtains the file list.      |
| size | string                  | number | Obtains the file size.                      |
| uploadFrom    | string, string                  | FTPResponse | Uploads a file.                      |
| downloadTo   | string, string                 | FTPResponse | Downloads a file.                      |
| features       | NA| Map<string, string> | Obtains server capabilities.|
| cd             | string                             | FTPResponse | Sets a working directory.                           |
| cdup               | NA                           | FTPResponse | Switches from the current working directory to the parent directory.            |
| remove               | string                            | FTPResponse | Removes a file.                         |
| lastMod               | string                            | Date | Obtains the last modification time.                         |
| pwd               | NA                           | string | Obtains the current directory.                         |
| ensureDir               | string                            | void | Checks whether the remote directory exists. If the directory does not exist, it will be created.               |
| removeEmptyDir               | string                            | FTPResponse | Removes the selected folder. If the folder is not empty, an error is reported.      |
| removeDir               | string                            | void | Removes the selected folder and all subfolders and files in it. |
| clearWorkingDir               | NA                           | void | Removes all folders and files in the current working directory, but retains the directory itself. |
| rename               | string, string                            | FTPResponse | Renames a file.                         |
| uploadFromDir               | string, string                            | void | Uploads a directory.                         |
| downloadToDir               | string, string                            | void | Downloads a directory.                         |

## About obfuscation
- Code obfuscation, please see[Code Obfuscation](https://docs.openharmony.cn/pages/v5.0/zh-cn/application-dev/arkts-utils/source-obfuscation.md)
- If you want the library not to be obfuscated during code obfuscation, you need to add corresponding exclusion rules in the obfuscation rule configuration file obfuscation-rules.txt：
```
-keep
./oh_modules/@ohos/basic-ftp
```
## Constraints
This project has been verified in the following versions:
DevEco Studio: NEXT Beta1-5.0.3.806, SDK: API12 Release(5.0.0.66)
DevEco Studio: 4.0 Release (4.0.3.413), SDK: (4.0.10.3)

Currently, the library supports the FTP passive mode and FTPS with implicit TLS encryption, the parsing of directory lists in MLSD, Unix, and DOS formats, the file types supported by the **@ohos.file.fs** module, and data transmission in binary mode.

## Directory Structure

```javascript
|---- BasicFtp  
|     |---- entry  # Sample code
|     |---- BasicFtp  # BasicFtp library
|     |---- README.MD  # Readme                  
```

## How to Contribute

If you find any problem when using the project, submit an [issue](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/issues) or a [PR](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/pulls).

## License

This project is licensed under [MIT](https://gitcode.com/openharmony-tpc/openharmony_tpc_samples/blob/master/BasicFtp/LICENSE).
