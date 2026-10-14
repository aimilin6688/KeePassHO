/**
 * IfDevice 设备 CSV 过滤列表解析/生成
 *
 * 与 KeeAutoExec 插件（PC）及 keepass2android（KeeAutoExec.cs）格式兼容：
 * - 逗号分隔，字段去首尾空白；空字段忽略；
 * - `!` 前缀 = 排除项（`!` 后再去左侧空白），无前缀 = 包含项；
 * - 设备 ID 大小写不敏感精确匹配；显式命中直接采用该项值；
 * - 无显式命中时：启用 ⇔（存在排除项 ∨ 不存在包含项）；
 * - 生成时若列表存在任一启用设备则省略禁用项；
 *   值含 `,` `\` `"` 时用 `"` 包裹并把 `"` 转义为 `\"`。
 */
export class DeviceEnableState {
  public readonly enabled: boolean;
  public readonly isExplicit: boolean;

  constructor(enabled: boolean, isExplicit: boolean) {
    this.enabled = enabled;
    this.isExplicit = isExplicit;
  }
}

export class IfDeviceParser {
  /**
   * 解析 IfDevice 原文为 设备 → 是否启用 映射
   * @param raw IfDevice 字段原文（可为空）
   */
  public static parse(raw: string | undefined): Map<string, boolean> {
    const result = new Map<string, boolean>();
    if (raw === undefined || raw === null) {
      return result;
    }
    const fields = IfDeviceParser.splitCsv(raw);
    for (const field of fields) {
      if (field.length === 0) {
        continue;
      }
      if (field.charCodeAt(0) === 0x21) { // '!' 排除项
        const key = field.substring(1).replace(/^\s+/, '');
        if (key.length > 0) {
          result.set(key, false);
        }
      } else {
        result.set(field, true);
      }
    }
    return result;
  }

  /**
   * 判断指定设备是否启用
   * @param raw IfDevice 字段原文
   * @param deviceId 本设备 ID
   * @returns 启用状态与是否显式命中
   */
  public static isEnabled(raw: string | undefined, deviceId: string): DeviceEnableState {
    const devices = IfDeviceParser.parse(raw);
    if (devices.size === 0 || deviceId.length === 0) {
      return new DeviceEnableState(true, false);
    }
    const target = deviceId.toLowerCase();
    let hasExclusion = false;
    let hasInclusion = false;
    const keys = Array.from(devices.keys());
    for (const key of keys) {
      if (key.length === 0) {
        continue;
      }
      if (target === key.toLowerCase()) {
        return new DeviceEnableState(devices.get(key) === true, true);
      }
      if (devices.get(key) === true) {
        hasInclusion = true;
      } else {
        hasExclusion = true;
      }
    }
    return new DeviceEnableState(hasExclusion || !hasInclusion, false);
  }

  /**
   * 生成 IfDevice 原文
   * @param devices 设备 → 是否启用 映射
   */
  public static build(devices: Map<string, boolean>): string {
    let hasEnabledDevices = false;
    const keys = Array.from(devices.keys());
    for (const key of keys) {
      if (devices.get(key) === true) {
        hasEnabledDevices = true;
        break;
      }
    }
    let result = '';
    for (const key of keys) {
      const enabled = devices.get(key) === true;
      // 与 KeeAutoExec 一致：列表中存在启用设备时省略禁用项
      if (hasEnabledDevices && !enabled) {
        continue;
      }
      let deviceValue = (enabled ? '' : '!') + key;
      if (deviceValue.indexOf(',') >= 0 || deviceValue.indexOf('\\') >= 0 || deviceValue.indexOf('"') >= 0) {
        deviceValue = '"' + deviceValue.split('"').join('\\"') + '"';
      }
      if (result.length > 0) {
        result += ',';
      }
      result += deviceValue;
    }
    return result;
  }

  /**
   * 设置指定设备的启用状态并返回新原文（启用；禁用则加 `!` 前缀）
   * @param raw 原 IfDevice 字段原文
   * @param deviceId 设备 ID
   * @param enabled 是否启用
   */
  public static setDeviceEnabled(raw: string | undefined, deviceId: string, enabled: boolean): string {
    if (deviceId.length === 0) {
      return raw ?? '';
    }
    const devices = IfDeviceParser.parse(raw);
    devices.set(deviceId, enabled);
    return IfDeviceParser.build(devices);
  }

  /**
   * CSV 拆分（TrimFields=true、反斜杠不转义；带引号字段支持 `\"` 与 `""` 两种引号转义）
   */
  private static splitCsv(line: string): string[] {
    const fields: string[] = [];
    let i = 0;
    while (i < line.length) {
      let value = '';
      if (line.charCodeAt(i) === 0x22) { // '"' 引号字段
        i++;
        while (i < line.length) {
          const ch = line[i];
          if (ch === '\\' && i + 1 < line.length && line[i + 1] === '"') {
            value += '"';
            i += 2;
          } else if (ch === '"' && i + 1 < line.length && line[i + 1] === '"') {
            value += '"';
            i += 2;
          } else if (ch === '"') {
            i++;
            // 关闭引号后跳到下一个分隔符（容忍后缀噪声，与宽松解析一致）
            while (i < line.length && line[i] !== ',') {
              i++;
            }
            break;
          } else {
            value += ch;
            i++;
          }
        }
      } else {
        while (i < line.length && line[i] !== ',') {
          value += line[i];
          i++;
        }
      }
      if (i < line.length && line[i] === ',') {
        i++;
      }
      fields.push(value.replace(/^\s+/, '').replace(/\s+$/, ''));
    }
    return fields;
  }
}
