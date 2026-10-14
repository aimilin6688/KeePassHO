import { describe, expect, it } from '@ohos/hypium';
import { DeviceEnableState, IfDeviceParser } from '../../../../../main/ets/services/autoopen/IfDeviceParser';

/**
 * IfDevice 设备 CSV 过滤列表解析/生成/判定测试
 * 对齐 keepass2android KeeAutoExec.cs（GetIfDevice / BuildIfDevice / IsDeviceEnabled）
 */
export default function IfDeviceParserTest() {
  describe('IfDeviceParser', () => {
    it('parse: empty raw returns empty map', 0, () => {
      expect(IfDeviceParser.parse('').size).assertEqual(0);
      expect(IfDeviceParser.parse(undefined).size).assertEqual(0);
    });

    it('parse: inclusion entries', 0, () => {
      const devices = IfDeviceParser.parse('HUAWEI P60 (id1),Xiaomi 14 (id2)');
      expect(devices.size).assertEqual(2);
      expect(devices.get('HUAWEI P60 (id1)')).assertTrue();
      expect(devices.get('Xiaomi 14 (id2)')).assertTrue();
    });

    it('parse: exclusion entries with ! prefix', 0, () => {
      const devices = IfDeviceParser.parse('!HUAWEI P60 (id1)');
      expect(devices.size).assertEqual(1);
      expect(devices.get('HUAWEI P60 (id1)')).assertFalse();
    });

    it('parse: trims fields and trims after !', 0, () => {
      const devices = IfDeviceParser.parse('  Device A  , !   Device B  ');
      expect(devices.get('Device A')).assertTrue();
      expect(devices.get('Device B')).assertFalse();
      expect(devices.size).assertEqual(2);
    });

    it('parse: skips empty fields and bare !', 0, () => {
      const devices = IfDeviceParser.parse('A,, ,!,B');
      expect(devices.size).assertEqual(2);
      expect(devices.get('A')).assertTrue();
      expect(devices.get('B')).assertTrue();
    });

    it('parse: quoted field with comma keeps device intact', 0, () => {
      const devices = IfDeviceParser.parse('"Device, Special (id)",Plain (id2)');
      expect(devices.size).assertEqual(2);
      expect(devices.get('Device, Special (id)')).assertTrue();
      expect(devices.get('Plain (id2)')).assertTrue();
    });

    it('parse: escaped quote inside quoted field', 0, () => {
      const devices = IfDeviceParser.parse('"De\\"vice (id)"');
      expect(devices.get('De"vice (id)')).assertTrue();
    });

    it('isEnabled: empty raw enables all devices (not explicit)', 0, () => {
      const state = IfDeviceParser.isEnabled('', 'HUAWEI P60 (id1)');
      expect(state.enabled).assertTrue();
      expect(state.isExplicit).assertFalse();
    });

    it('isEnabled: explicit inclusion match returns enabled', 0, () => {
      const state = IfDeviceParser.isEnabled('HUAWEI P60 (id1)', 'HUAWEI P60 (id1)');
      expect(state.enabled).assertTrue();
      expect(state.isExplicit).assertTrue();
    });

    it('isEnabled: explicit exclusion match returns disabled', 0, () => {
      const state = IfDeviceParser.isEnabled('!HUAWEI P60 (id1)', 'HUAWEI P60 (id1)');
      expect(state.enabled).assertFalse();
      expect(state.isExplicit).assertTrue();
    });

    it('isEnabled: match is case-insensitive', 0, () => {
      const state = IfDeviceParser.isEnabled('huawei p60 (ID1)', 'HUAWEI P60 (id1)');
      expect(state.enabled).assertTrue();
      expect(state.isExplicit).assertTrue();
    });

    it('isEnabled: inclusion-only list disables unlisted devices', 0, () => {
      const state = IfDeviceParser.isEnabled('Device A (a)', 'Device B (b)');
      expect(state.enabled).assertFalse();
      expect(state.isExplicit).assertFalse();
    });

    it('isEnabled: exclusion-only list enables unlisted devices', 0, () => {
      const state = IfDeviceParser.isEnabled('!Device A (a)', 'Device B (b)');
      expect(state.enabled).assertTrue();
      expect(state.isExplicit).assertFalse();
    });

    it('isEnabled: mixed list without match enables (has exclusion)', 0, () => {
      const state = IfDeviceParser.isEnabled('Device A (a),!Device B (b)', 'Device C (c)');
      expect(state.enabled).assertTrue();
      expect(state.isExplicit).assertFalse();
    });

    it('build: single inclusion', 0, () => {
      const devices = new Map<string, boolean>();
      devices.set('Device A (a)', true);
      expect(IfDeviceParser.build(devices)).assertEqual('Device A (a)');
    });

    it('build: exclusion prefixed with !', 0, () => {
      const devices = new Map<string, boolean>();
      devices.set('Device A (a)', false);
      expect(IfDeviceParser.build(devices)).assertEqual('!Device A (a)');
    });

    it('build: drops disabled entries when enabled ones exist', 0, () => {
      const devices = new Map<string, boolean>();
      devices.set('Device A (a)', true);
      devices.set('Device B (b)', false);
      expect(IfDeviceParser.build(devices)).assertEqual('Device A (a)');
    });

    it('build: keeps disabled entries when no enabled ones exist', 0, () => {
      const devices = new Map<string, boolean>();
      devices.set('Device A (a)', false);
      devices.set('Device B (b)', false);
      expect(IfDeviceParser.build(devices)).assertEqual('!Device A (a),!Device B (b)');
    });

    it('build: quotes values containing comma/backslash/quote', 0, () => {
      const devices = new Map<string, boolean>();
      devices.set('A,B (id)', true);
      expect(IfDeviceParser.build(devices)).assertEqual('"A,B (id)"');

      devices.clear();
      devices.set('A\\B (id)', true);
      expect(IfDeviceParser.build(devices)).assertEqual('"A\\B (id)"');

      devices.clear();
      devices.set('A"B (id)', true);
      expect(IfDeviceParser.build(devices)).assertEqual('"A\\"B (id)"');
    });

    it('round-trip: build then parse preserves semantics', 0, () => {
      const devices = new Map<string, boolean>();
      devices.set('Device A (a)', true);
      devices.set('Device B (b)', false);
      const raw = IfDeviceParser.build(devices);
      const parsed = IfDeviceParser.parse(raw);
      expect(parsed.get('Device A (a)')).assertTrue();
      expect(parsed.size).assertEqual(1); // 禁用项在有启用项时被省略
    });

    it('setDeviceEnabled: adds device to empty raw', 0, () => {
      const raw = IfDeviceParser.setDeviceEnabled('', 'Device A (a)', true);
      expect(raw).assertEqual('Device A (a)');
      const state = IfDeviceParser.isEnabled(raw, 'Device A (a)');
      expect(state.enabled).assertTrue();
      expect(state.isExplicit).assertTrue();
    });

    it('setDeviceEnabled: disables existing device in list', 0, () => {
      const raw = IfDeviceParser.setDeviceEnabled('Device A (a),Device B (b)', 'Device A (a)', false);
      // Device B 仍启用 → A 的禁用项按规则被省略（等价于「仅 B 启用」）
      expect(IfDeviceParser.isEnabled(raw, 'Device A (a)').enabled).assertFalse();
      expect(IfDeviceParser.isEnabled(raw, 'Device B (b)').enabled).assertTrue();
    });

    it('DeviceEnableState: fields exposed', 0, () => {
      const state = new DeviceEnableState(false, true);
      expect(state.enabled).assertFalse();
      expect(state.isExplicit).assertTrue();
    });
  });
}
