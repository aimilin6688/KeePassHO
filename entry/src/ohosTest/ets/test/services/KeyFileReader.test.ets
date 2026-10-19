import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { ByteUtils } from 'kdbxweb';
import { isKdbxDatabaseBytes, KeyFileReader } from '../../../../main/ets/services/credentials/KeyFileReader';
import { AuthType, AuthTypeInfo, CredentialsParam } from '../../../../main/ets/services/TypeDefined';
import { LocationInfo, LocationMode } from '../../../../main/ets/services/beans/LocationParam';
import { LocalFileStorageConfig } from '../../../../main/ets/storage/local/LocalFileConfig';
import { StorageType } from '../../../../main/ets/storage';
import { ResourceManager } from '../../../../main/ets/common/utils';

/**
 * KeyFileReader 密钥文件防误选 KDBX 校验纯函数单元测试。
 *
 * 对齐 KeePass 桌面版 KcpKeyFile(bThrowIfDbFile) 签名集合：
 * - 第一签名（LE u32）：0x9AA2D903（正式版 / 预发布版 / 旧版 KDB 相同）
 * - 第二签名（LE u32）：0xB54BFB67（KDBX 4.x）/ 0xB54BFB66（预发布版）/ 0xB54BFB65（KeePass 1.x KDB）
 */

/** 以 LE u32 写入前 8 字节构造内容 */
function contentOf(sig1: number, sig2: number): ArrayBuffer {
  const buf = new ArrayBuffer(64);
  const view = new DataView(buf);
  view.setUint32(0, sig1, true);
  view.setUint32(4, sig2, true);
  return buf;
}

/** 测试用凭据参数（CredentialsParam 最小实现） */
class TestCredParam implements CredentialsParam {
  password: string = '';
  authType: AuthTypeInfo = AuthType.KEYFILE;
  keyLocation?: LocationInfo;
  keyFileDataBase64?: string;
}

export default function KeyFileReaderTest() {
  describe('KeyFileReader', () => {
    it('isKdbxDatabaseBytes detects kdbx4 release signature', 0, () => {
      expect(isKdbxDatabaseBytes(contentOf(0x9AA2D903, 0xB54BFB67))).assertTrue();
    });

    it('isKdbxDatabaseBytes detects kdbx pre-release signature', 0, () => {
      expect(isKdbxDatabaseBytes(contentOf(0x9AA2D903, 0xB54BFB66))).assertTrue();
    });

    it('isKdbxDatabaseBytes detects legacy kdb signature', 0, () => {
      expect(isKdbxDatabaseBytes(contentOf(0x9AA2D903, 0xB54BFB65))).assertTrue();
    });

    it('isKdbxDatabaseBytes rejects xml key file content', 0, () => {
      const xml = '<?xml version="1.0" encoding="utf-8"?><KeyFile><Meta><Version>2.0</Version></Meta></KeyFile>';
      const buf = new ArrayBuffer(xml.length);
      const bytes = new Uint8Array(buf);
      for (let i = 0; i < xml.length; i++) {
        bytes[i] = xml.charCodeAt(i) & 0xFF;
      }
      expect(isKdbxDatabaseBytes(buf)).assertFalse();
    });

    it('isKdbxDatabaseBytes rejects raw 32-byte key', 0, () => {
      expect(isKdbxDatabaseBytes(new ArrayBuffer(32))).assertFalse();
    });

    it('isKdbxDatabaseBytes rejects content shorter than 8 bytes', 0, () => {
      expect(isKdbxDatabaseBytes(new ArrayBuffer(7))).assertFalse();
      expect(isKdbxDatabaseBytes(new ArrayBuffer(0))).assertFalse();
    });

    it('isKdbxDatabaseBytes rejects non-kdbx first signature', 0, () => {
      expect(isKdbxDatabaseBytes(contentOf(0x11223344, 0xB54BFB67))).assertFalse();
      expect(isKdbxDatabaseBytes(contentOf(0x9AA2D904, 0xB54BFB67))).assertFalse();
    });
  });

  describe('KeyFileReader.requireAndRead', () => {
    beforeAll(() => {
      // 失败文案经 ResourceManager 本地化，测试环境需注入真实 context
      const appContext: common.Context = abilityDelegatorRegistry.getAbilityDelegator()
        .getAppContext().getApplicationContext();
      ResourceManager.getInstance().init(appContext as common.UIAbilityContext);
    });

    it('returns inline base64 content byte-identical', 0, async () => {
      const keyBytes = [0x21, 0x43, 0x65, 0x87];
      const param = new TestCredParam();
      param.keyFileDataBase64 = ByteUtils.bytesToBase64(new Uint8Array(keyBytes).buffer);
      const content = await KeyFileReader.requireAndRead(param, 'unit-test');
      expect(content.byteLength).assertEqual(keyBytes.length);
      const view = new Uint8Array(content);
      for (let i = 0; i < keyBytes.length; i++) {
        expect(view[i]).assertEqual(keyBytes[i]);
      }
    });

    it('inline content takes precedence over keyLocation', 0, async () => {
      const param = new TestCredParam();
      param.keyFileDataBase64 = ByteUtils.bytesToBase64(new Uint8Array([0x01, 0x02, 0x03]).buffer);
      // keyLocation 指向不存在文件：内联命中时不应触发文件读取
      param.keyLocation = {
        mode: LocationMode.SELECT,
        filePath: '/nonexistent/key.xml',
        fileName: 'key.xml',
        storageType: StorageType.LOCAL,
        storageConfig: new LocalFileStorageConfig()
      } as LocationInfo;
      const content = await KeyFileReader.requireAndRead(param, 'unit-test');
      expect(content.byteLength).assertEqual(3);
      expect(new Uint8Array(content)[0]).assertEqual(0x01);
    });

    it('rejects inline content that is a kdbx database', 0, async () => {
      const param = new TestCredParam();
      param.keyFileDataBase64 = ByteUtils.bytesToBase64(contentOf(0x9AA2D903, 0xB54BFB67));
      let threw = false;
      try {
        await KeyFileReader.requireAndRead(param, 'unit-test');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('empty inline string without keyLocation throws', 0, async () => {
      const param = new TestCredParam();
      param.keyFileDataBase64 = '';
      let threw = false;
      try {
        await KeyFileReader.requireAndRead(param, 'unit-test');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });

    it('missing keyLocation without inline throws', 0, async () => {
      const param = new TestCredParam();
      let threw = false;
      try {
        await KeyFileReader.requireAndRead(param, 'unit-test');
      } catch (e) {
        threw = true;
      }
      expect(threw).assertTrue();
    });
  });
}
