import { beforeAll, describe, expect, it } from '@ohos/hypium';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { fileIo as fs } from '@kit.CoreFileKit';
import { ByteUtils } from 'kdbxweb';
import { LocationInfo, LocationMode } from '../../../../../main/ets/services/beans/LocationParam';
import { StorageType } from '../../../../../main/ets/storage';
import { OtpAuxFileService } from '../../../../../main/ets/services/otpkey/OtpAuxFileService';
import { HmacOtp } from '../../../../../main/ets/services/otpkey/HmacOtp';
import { OtpInfo } from '../../../../../main/ets/services/otpkey/OtpInfo';
import { OtpKeyProvService } from '../../../../../main/ets/services/otpkey/OtpKeyProvService';

/**
 * OTP 辅助文件读写服务测试：路径定位、经 LOCAL 存储的写入/读取往返、
 * 解锁成功后 Counter 写回（重加密 → 新一组 OTP 码生效、旧码失效）。
 */
export default function OtpAuxFileServiceTest() {
  describe('OtpAuxFileService', () => {
    let testDir: string;

    beforeAll(() => {
      const appContext = abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      testDir = (appContext as common.UIAbilityContext).filesDir + '/otp-aux-test';
      if (!fs.accessSync(testDir, fs.AccessModeType.EXIST)) {
        fs.mkdirSync(testDir, true);
      }
    });

    const buildLocation = (fileName: string): LocationInfo => {
      const location: LocationInfo = {
        mode: LocationMode.SELECT,
        filePath: testDir + '/' + fileName,
        fileName: fileName,
        storageType: StorageType.LOCAL,
        storageConfig: {}
      };
      return location;
    };

    /**
     * 数据库路径 → 同目录辅助文件路径（含 Windows 分隔符与无扩展名场景）
     */
    it('buildAuxFilePath derives co-located aux path', 0, () => {
      expect(OtpAuxFileService.buildAuxFilePath('/docs/db/test.kdbx')).assertEqual('/docs/db/test.otp.xml');
      expect(OtpAuxFileService.buildAuxFilePath('test.kdbx')).assertEqual('test.otp.xml');
      expect(OtpAuxFileService.buildAuxFilePath('/a.b/plainname')).assertEqual('/a.b/plainname.otp.xml');
      expect(OtpAuxFileService.buildAuxFilePath('C:\\db\\test.kdbx')).assertEqual('C:\\db\\test.otp.xml');
    });

    /**
     * 写入 → 读取往返：字段一致（Counter/OtpsRequired/加密数据）
     */
    it('writeOtpInfo then loadOtpInfo round-trip via local storage', 0, async () => {
      const location = buildLocation('roundtrip.otp.xml');
      const secret = ByteUtils.hexToBytes('000102030405060708090a0b0c0d0e0f');
      const info = new OtpInfo();
      info.otpsRequired = 2;
      info.otpLength = 8;
      info.counter = 7;
      await OtpKeyProvService.encryptOtpInfoSecret(info, secret);

      await OtpAuxFileService.writeOtpInfo(info, location);
      const loaded = await OtpAuxFileService.loadOtpInfo(location);

      expect(loaded.counter).assertEqual(7);
      expect(loaded.otpsRequired).assertEqual(2);
      expect(loaded.otpLength).assertEqual(8);
      expect(loaded.version).assertEqual('2.0');
      expect(loaded.encryptedSecrets.length).assertEqual(info.encryptedSecrets.length);
      expect(loaded.encryptedSecret).assertEqual('');
    });

    /**
     * 辅助文件缺失：读取抛错（UI 引导手动选择）
     */
    it('loadOtpInfo rejects when aux file missing', 0, async () => {
      const location = buildLocation('not-exist.otp.xml');
      let rejected = false;
      try {
        await OtpAuxFileService.loadOtpInfo(location);
      } catch (error) {
        rejected = true;
      }
      expect(rejected).assertTrue();
    });

    /**
     * 解锁全流程：创建辅助文件 → 派生（counterDelta=OtpsRequired）→ 写回 →
     * Counter 前进且以新 Counter 重新加密；新一组 OTP 码生效、旧码失效
     */
    it('saveAfterUnlock advances counter and re-encrypts secrets', 0, async () => {
      const location = buildLocation('unlock.otp.xml');
      const secret = ByteUtils.hexToBytes('101112131415161718191a1b1c1d1e1f');
      const info = new OtpInfo();
      info.otpsRequired = 2;
      info.otpLength = 8;
      info.counter = 0;
      await OtpKeyProvService.encryptOtpInfoSecret(info, secret);
      await OtpAuxFileService.writeOtpInfo(info, location);

      // 首次解锁：Counter 0/1 的码
      const loaded = await OtpAuxFileService.loadOtpInfo(location);
      const firstOtps: string[] = [
        await HmacOtp.generate(secret, 0, 8, false, -1),
        await HmacOtp.generate(secret, 1, 8, false, -1)
      ];
      const derived = await OtpKeyProvService.deriveSecretFromOtps(loaded, firstOtps);
      expect(derived.secretHex).assertEqual(ByteUtils.bytesToHex(secret));
      expect(derived.counterDelta).assertEqual(2);

      // 写回：Counter += 2 并以新 Counter 重新加密
      await OtpAuxFileService.saveAfterUnlock(loaded, derived.secret, derived.counterDelta, location);

      // 重读：Counter=2，旧码失效，新码（Counter 2/3）可派生同一 secret
      const reloaded = await OtpAuxFileService.loadOtpInfo(location);
      expect(reloaded.counter).assertEqual(2);

      let oldCodesRejected = false;
      try {
        await OtpKeyProvService.deriveSecretFromOtps(reloaded, firstOtps);
      } catch (error) {
        oldCodesRejected = true;
      }
      expect(oldCodesRejected).assertTrue();

      const secondOtps: string[] = [
        await HmacOtp.generate(secret, 2, 8, false, -1),
        await HmacOtp.generate(secret, 3, 8, false, -1)
      ];
      const derived2 = await OtpKeyProvService.deriveSecretFromOtps(reloaded, secondOtps);
      expect(derived2.secretHex).assertEqual(ByteUtils.bytesToHex(secret));
      expect(derived2.counterDelta).assertEqual(2);
    });
  });
}
