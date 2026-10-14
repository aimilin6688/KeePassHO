import { afterAll, beforeAll, describe, expect, it } from '@ohos/hypium';
import { deviceInfo } from '@kit.BasicServicesKit';
import { TestContextHelper } from '../../TestContextHelper';
import { CommonUtils } from '../../../../../main/ets/common/utils/CommonUtils';
import { SettingsService } from '../../../../../main/ets/services/SettingsService';
import { DeviceIdentity } from '../../../../../main/ets/services/autoopen/DeviceIdentity';

/**
 * 设备身份标识（IfDevice 过滤用）单元测试
 */
export default function DeviceIdentityTest() {
  describe('DeviceIdentity', () => {
    beforeAll(async () => {
      const appContext = await TestContextHelper.getUIAbilityContext();
      CommonUtils.init(appContext);
      await SettingsService.getInstance().init(appContext);
    });

    afterAll(() => {
      DeviceIdentity.resetCache();
      SettingsService.getInstance().deleteSync(DeviceIdentity.KEY_DEVICE_LOCAL_UUID);
    });

    it('buildDeviceId: concatenates manufacturer, model and raw id', 0, () => {
      expect(DeviceIdentity.buildDeviceId('HUAWEI', 'P60', 'abcd-1234')).assertEqual('HUAWEI P60 (abcd-1234)');
    });

    it('buildDeviceId: replaces reserved characters with underscore', 0, () => {
      expect(DeviceIdentity.buildDeviceId('Ven,dor', 'Mo!del', 'x;y'))
        .assertEqual('Ven_dor Mo_del (x_y)');
    });

    it('buildDeviceId: empty parts still formatted', 0, () => {
      expect(DeviceIdentity.buildDeviceId('', '', '')).assertEqual('  ()');
    });

    it('getLocalDeviceUuid: generates and keeps a stable uuid within process', 0, () => {
      DeviceIdentity.resetCache();
      const first = DeviceIdentity.getLocalDeviceUuid();
      expect(first.length > 0).assertTrue();
      const second = DeviceIdentity.getLocalDeviceUuid();
      expect(second).assertEqual(first);
    });

    it('getLocalDeviceUuid: returns persisted value after cache reset', 0, async () => {
      const known = '11111111-2222-3333-4444-555555555555';
      await SettingsService.put(DeviceIdentity.KEY_DEVICE_LOCAL_UUID, known);
      DeviceIdentity.resetCache();
      expect(DeviceIdentity.getLocalDeviceUuid()).assertEqual(known);
    });

    it('getDeviceId: built from device info and local uuid, cached in process', 0, () => {
      DeviceIdentity.resetCache();
      const localUuid = DeviceIdentity.getLocalDeviceUuid();
      const expected = DeviceIdentity.buildDeviceId(deviceInfo.manufacture, deviceInfo.productModel, localUuid);
      const first = DeviceIdentity.getDeviceId();
      expect(first).assertEqual(expected);
      expect(DeviceIdentity.getDeviceId()).assertEqual(first);
    });
  });
}
