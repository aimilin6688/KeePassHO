import { ByteUtils } from '../../../../main/ets/index';
import fs from '@ohos.file.fs';
import util from '@ohos.util';


export class TestResources {
  static demoKdbx: ArrayBuffer = TestResources.readFile('demo.kdbx');
  static demoKey: ArrayBuffer = TestResources.readFile('demo.key');
  static demoXml: ArrayBuffer = TestResources.readFile('demo.xml');
  static cyrillicKdbx: ArrayBuffer = TestResources.readFile('cyrillic.kdbx');
  static binKeyKdbx: ArrayBuffer = TestResources.readFile('binkey.kdbx');
  static binKeyKey: ArrayBuffer = TestResources.readFile('binkey.key');
  static emptyPass: ArrayBuffer = TestResources.readFile('EmptyPass.kdbx');
  static emptyPassWithKeyFile: ArrayBuffer = TestResources.readFile('EmptyPassWithKeyFile.kdbx');
  static emptyPassWithKeyFileKey: ArrayBuffer = TestResources.readFile('EmptyPassWithKeyFile.key');
  static noPassWithKeyFile: ArrayBuffer = TestResources.readFile('NoPassWithKeyFile.kdbx');
  static noPassWithKeyFileKey: ArrayBuffer = TestResources.readFile('NoPassWithKeyFile.key');
  static key32: ArrayBuffer = TestResources.readFile('Key32.kdbx');
  static key32KeyFile: ArrayBuffer = TestResources.readFile('Key32.key');
  static key64: ArrayBuffer = TestResources.readFile('Key64.kdbx');
  static key64KeyFile: ArrayBuffer = TestResources.readFile('Key64.key');
  static keyWithBom: ArrayBuffer = TestResources.readFile('KeyWithBom.kdbx');
  static keyWithBomKeyFile: ArrayBuffer = TestResources.readFile('KeyWithBom.key');
  static keyV2: ArrayBuffer = TestResources.readFile('KeyV2.kdbx');
  static keyV2KeyFile: ArrayBuffer = TestResources.readFile('KeyV2.keyx');
  static argon2: ArrayBuffer = TestResources.readFile('Argon2.kdbx');
  static argon2id: ArrayBuffer = TestResources.readFile('Argon2id.kdbx');
  static argon2ChaCha: ArrayBuffer = TestResources.readFile('Argon2ChaCha.kdbx');
  static aesChaCha: ArrayBuffer = TestResources.readFile('AesChaCha.kdbx');
  static aesKdfKdbx4: ArrayBuffer = TestResources.readFile('AesKdfKdbx4.kdbx');
  static yubikey3: ArrayBuffer = TestResources.readFile('YubiKey3.kdbx');
  static yubikey4: ArrayBuffer = TestResources.readFile('YubiKey4.kdbx');
  static emptyUuidXml: ArrayBuffer = TestResources.readFile('empty-uuid.xml');
  static kdbx41: ArrayBuffer = TestResources.readFile('KDBX4.1.kdbx');

  public static readFile(name: string): ArrayBuffer {
    let path = '../../../resources/rawfile/' + name;

    // 3. 打开文件
    const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
    // 4. 获取文件大小
    const stats: fs.Stat = fs.statSync(path);
    const bufferSize: number = stats.size;

    // 5. 创建缓冲区并读取文件
    const arrayBuffer: ArrayBuffer = new ArrayBuffer(bufferSize);
    const readLen: number = fs.readSync(file.fd, arrayBuffer);
    // 6. 转换为base64
    const base64Str: string = ByteUtils.bytesToBase64(arrayBuffer);

    // 7. 关闭文件
    fs.closeSync(file);
    return  ByteUtils.arrayToBuffer(ByteUtils.base64ToBytes(base64Str));
  }
}

