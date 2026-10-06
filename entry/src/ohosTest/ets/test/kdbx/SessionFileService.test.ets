import { describe, expect, it, beforeAll } from '@ohos/hypium';
import { SessionFileService } from '../../../../main/ets/services/kdbx/SessionFileService';
import { CommonUtils } from '../../../../main/ets/common/utils/CommonUtils';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';
import { fileIo as fs } from '@kit.CoreFileKit';

/**
 * §7.4 会话文件协议单元测试：
 * 会话密钥包裹/解包裹往返、分块大缓冲往返、消费后删除、超期目录清扫
 */
export default function SessionFileServiceTest() {
  describe('SessionFileServiceTest', () => {
    beforeAll(() => {
      const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      CommonUtils.init(appContext as common.UIAbilityContext);
    });

    it('wrap and unwrap roundtrip preserves content', 0, async () => {
      const data = new ArrayBuffer(1024);
      const view = new Uint8Array(data);
      for (let i = 0; i < view.length; i++) {
        view[i] = i % 251;
      }
      const path = await SessionFileService.wrapToFile(data, 'm0_test_');
      try {
        expect(fs.accessSync(path, fs.AccessModeType.EXIST)).assertTrue();
        const unwrapped = await SessionFileService.unwrapFromFile(path);
        expect(unwrapped.byteLength).assertEqual(data.byteLength);
        const a = new Uint8Array(unwrapped);
        let mismatch = false;
        for (let i = 0; i < a.length; i++) {
          if (a[i] !== view[i]) {
            mismatch = true;
            break;
          }
        }
        expect(mismatch).assertFalse();
      } finally {
        SessionFileService.removeFile(path);
      }
    });

    it('wrap and unwrap handles multi-chunk large buffer', 0, async () => {
      // >4MB 触发分块密钥流路径（跨块 ChaCha20 状态连续性）
      const size = 4 * 1024 * 1024 + 12345;
      const data = new ArrayBuffer(size);
      const view = new Uint8Array(data);
      let seed = 0x12345678;
      for (let i = 0; i < size; i++) {
        seed ^= seed << 13;
        seed ^= seed >>> 17;
        seed ^= seed << 5;
        view[i] = seed & 0xff;
      }
      const path = await SessionFileService.wrapToFile(data, 'm0_big_');
      try {
        const unwrapped = await SessionFileService.unwrapFromFile(path);
        expect(unwrapped.byteLength).assertEqual(size);
        const a = new Uint8Array(unwrapped);
        let mismatch = false;
        for (let i = 0; i < size; i++) {
          if (a[i] !== view[i]) {
            mismatch = true;
            break;
          }
        }
        expect(mismatch).assertFalse();
      } finally {
        SessionFileService.removeFile(path);
      }
    });

    it('removeFile deletes session file', 0, async () => {
      const data = new ArrayBuffer(16);
      const path = await SessionFileService.wrapToFile(data, 'm0_rm_');
      expect(fs.accessSync(path, fs.AccessModeType.EXIST)).assertTrue();
      SessionFileService.removeFile(path);
      let exists = false;
      try {
        exists = fs.accessSync(path, fs.AccessModeType.EXIST);
      } catch {
        exists = false;
      }
      expect(exists).assertFalse();
    });

    it('session dir lives under filesDir with session- prefix', 0, () => {
      const dir = SessionFileService.getSessionDir();
      expect(dir.indexOf('/session-') > 0).assertTrue();
      expect(dir.indexOf(CommonUtils.getAppFilesDir()) === 0).assertTrue();
      expect(fs.accessSync(dir, fs.AccessModeType.EXIST)).assertTrue();
    });
  });
}
