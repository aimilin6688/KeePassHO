import { XmlUtils } from 'kdbxweb';

/**
 * OtpKeyProv 辅助文件（<数据库名>.otp.xml）中单项加密数据，
 * 对齐 addons/OtpKeyProv/OtpInfo.cs 的 OtpEncryptedData（v2.0+，支持前瞻窗口）。
 */
export class OtpEncryptedData {
  public static readonly DEFAULT_TRANSFORMATION_ROUNDS: number = 10000;

  /** 's20://' + Base64（Salsa20 加密） */
  public cipherText: string = '';
  /** Base64 的 16 字节 IV（Salsa20 取前 8 字节） */
  public iv: string = '';
  /** Base64 的 32 字节 AES-KDF 变换密钥 */
  public transformationKey: string = '';
  public transformationRounds: number = OtpEncryptedData.DEFAULT_TRANSFORMATION_ROUNDS;
  /** Base64 的 PlainTextHash（HashAndTransform(secret)） */
  public plainTextHash: string = '';
  public plainTextHashTransformationKey: string = '';
  public plainTextHashTransformationRounds: number = OtpEncryptedData.DEFAULT_TRANSFORMATION_ROUNDS;
}

/**
 * OtpKeyProv 辅助文件模型，对齐 addons/OtpKeyProv/OtpInfo.cs：
 * - v1（< v2.0）：EncryptedSecret / EncryptionIV / TransformationKey / TransformationRounds（无 PlainTextHash 校验）；
 * - v2（>= 2.0）：EncryptedSecrets[]（每项 OtpEncryptedData，支持 LookAheadCount 前瞻窗口）。
 * 元素名与 .NET XmlSerializer 输出一致，保证与 KeePass 桌面版插件互操作。
 */
export class OtpInfo {
  public static readonly DEFAULT_TRANSFORMATION_ROUNDS: number = 12000;

  public type: string = '';
  public version: string = '';
  public generator: string = '';
  /** v1 加密 secret（'s20://' + Base64），v2 为空 */
  public encryptedSecret: string = '';
  /** v2 加密 secret 列表（长度 = 1 + LookAheadCount） */
  public encryptedSecrets: OtpEncryptedData[] = [];
  /** v1 Base64 IV */
  public encryptionIV: string = '';
  /** v1 Base64 变换密钥 */
  public transformationKey: string = '';
  /** v1 变换轮数（默认 12000） */
  public transformationRounds: number = OtpInfo.DEFAULT_TRANSFORMATION_ROUNDS;
  /** HOTP 计数器（解锁成功后 += OtpsRequired(+i) 写回） */
  public counter: number = 0;
  /** 单码位数（默认 8） */
  public otpLength: number = 8;
  /** 所需码数（默认 4） */
  public otpsRequired: number = 4;
  /** 前瞻数（默认 0） */
  public lookAheadCount: number = 0;

  /**
   * 解析 .otp.xml（对齐 XmlSerializer 反序列化，缺失字段取默认值）。
   * 节点遍历全部依赖类型推断（entry 不直接依赖 @xmldom 类型声明），
   * EncryptedSecrets 二级结构内联解析。
   */
  public static fromXml(xml: string): OtpInfo {
    const doc = XmlUtils.parse(xml);
    const root = doc.documentElement;
    if (!root) {
      throw new Error('bad otp aux xml: no root element');
    }
    const info = new OtpInfo();
    for (let i = 0; i < root.childNodes.length; i++) {
      const node = root.childNodes[i];
      const name = node.nodeName;
      if (!name || name.indexOf('#') === 0) {
        continue;
      }
      if (name === 'EncryptedSecrets') {
        // v2：<EncryptedSecrets><EncryptedData>…</EncryptedData></EncryptedSecrets>
        for (let j = 0; j < node.childNodes.length; j++) {
          const item = node.childNodes[j];
          if (!item.nodeName || item.nodeName !== 'EncryptedData') {
            continue;
          }
          const d = new OtpEncryptedData();
          for (let k = 0; k < item.childNodes.length; k++) {
            const field = item.childNodes[k];
            const fieldName = field.nodeName;
            if (!fieldName || fieldName.indexOf('#') === 0) {
              continue;
            }
            const text = XmlUtils.getText(field) ?? '';
            switch (fieldName) {
              case 'CipherText':
                d.cipherText = text;
                break;
              case 'IV':
                d.iv = text;
                break;
              case 'TransformationKey':
                d.transformationKey = text;
                break;
              case 'TransformationRounds':
                d.transformationRounds =
                  OtpInfo.parseUInt(text, OtpEncryptedData.DEFAULT_TRANSFORMATION_ROUNDS);
                break;
              case 'PlainTextHash':
                d.plainTextHash = text;
                break;
              case 'PlainTextHashTransformationKey':
                d.plainTextHashTransformationKey = text;
                break;
              case 'PlainTextHashTransformationRounds':
                d.plainTextHashTransformationRounds =
                  OtpInfo.parseUInt(text, OtpEncryptedData.DEFAULT_TRANSFORMATION_ROUNDS);
                break;
              default:
                break;
            }
          }
          info.encryptedSecrets.push(d);
        }
        continue;
      }
      const text = XmlUtils.getText(node) ?? '';
      switch (name) {
        case 'Type':
          info.type = text;
          break;
        case 'Version':
          info.version = text;
          break;
        case 'Generator':
          info.generator = text;
          break;
        case 'EncryptedSecret':
          info.encryptedSecret = text;
          break;
        case 'EncryptionIV':
          info.encryptionIV = text;
          break;
        case 'TransformationKey':
          info.transformationKey = text;
          break;
        case 'TransformationRounds':
          info.transformationRounds = OtpInfo.parseUInt(text, OtpInfo.DEFAULT_TRANSFORMATION_ROUNDS);
          break;
        case 'Counter':
          info.counter = OtpInfo.parseUInt(text, 0);
          break;
        case 'OtpLength':
          info.otpLength = OtpInfo.parseUInt(text, 8);
          break;
        case 'OtpsRequired':
          info.otpsRequired = OtpInfo.parseUInt(text, 4);
          break;
        case 'LookAheadCount':
          info.lookAheadCount = OtpInfo.parseUInt(text, 0);
          break;
        default:
          break;
      }
    }
    return info;
  }

  /**
   * 序列化为 .otp.xml 文本（元素顺序/命名对齐 .NET XmlSerializer，tab 缩进对齐 KP2A XmlWriterSettings）
   */
  public toXml(): string {
    const lines: string[] = [];
    lines.push('<?xml version="1.0" encoding="utf-8"?>');
    lines.push('<OtpInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
      'xmlns:xsd="http://www.w3.org/2001/XMLSchema">');
    lines.push('\t<Type>' + OtpInfo.escapeXml(this.type) + '</Type>');
    lines.push('\t<Version>' + OtpInfo.escapeXml(this.version) + '</Version>');
    lines.push('\t<Generator>' + OtpInfo.escapeXml(this.generator) + '</Generator>');
    if (this.encryptedSecret.length > 0) {
      lines.push('\t<EncryptedSecret>' + OtpInfo.escapeXml(this.encryptedSecret) + '</EncryptedSecret>');
    } else {
      lines.push('\t<EncryptedSecret />');
    }
    if (this.encryptedSecrets.length === 0) {
      lines.push('\t<EncryptedSecrets />');
    } else {
      lines.push('\t<EncryptedSecrets>');
      for (let i = 0; i < this.encryptedSecrets.length; i++) {
        const d = this.encryptedSecrets[i];
        lines.push('\t\t<EncryptedData>');
        lines.push('\t\t\t<CipherText>' + OtpInfo.escapeXml(d.cipherText) + '</CipherText>');
        lines.push('\t\t\t<IV>' + OtpInfo.escapeXml(d.iv) + '</IV>');
        lines.push('\t\t\t<TransformationKey>' +
          OtpInfo.escapeXml(d.transformationKey) + '</TransformationKey>');
        lines.push('\t\t\t<TransformationRounds>' +
          d.transformationRounds.toString() + '</TransformationRounds>');
        lines.push('\t\t\t<PlainTextHash>' +
          OtpInfo.escapeXml(d.plainTextHash) + '</PlainTextHash>');
        lines.push('\t\t\t<PlainTextHashTransformationKey>' +
          OtpInfo.escapeXml(d.plainTextHashTransformationKey) + '</PlainTextHashTransformationKey>');
        lines.push('\t\t\t<PlainTextHashTransformationRounds>' +
          d.plainTextHashTransformationRounds.toString() + '</PlainTextHashTransformationRounds>');
        lines.push('\t\t</EncryptedData>');
      }
      lines.push('\t</EncryptedSecrets>');
    }
    if (this.encryptionIV.length > 0) {
      lines.push('\t<EncryptionIV>' + OtpInfo.escapeXml(this.encryptionIV) + '</EncryptionIV>');
    } else {
      lines.push('\t<EncryptionIV />');
    }
    if (this.transformationKey.length > 0) {
      lines.push('\t<TransformationKey>' +
        OtpInfo.escapeXml(this.transformationKey) + '</TransformationKey>');
    } else {
      lines.push('\t<TransformationKey />');
    }
    lines.push('\t<TransformationRounds>' + this.transformationRounds.toString() + '</TransformationRounds>');
    lines.push('\t<Counter>' + this.counter.toString() + '</Counter>');
    lines.push('\t<OtpLength>' + this.otpLength.toString() + '</OtpLength>');
    lines.push('\t<OtpsRequired>' + this.otpsRequired.toString() + '</OtpsRequired>');
    lines.push('\t<LookAheadCount>' + this.lookAheadCount.toString() + '</LookAheadCount>');
    lines.push('</OtpInfo>');
    return lines.join('\n') + '\n';
  }

  private static parseUInt(text: string, fallback: number): number {
    const trimmed = text.trim();
    if (!/^\d+$/.test(trimmed)) {
      return fallback;
    }
    const value = Number(trimmed);
    return Number.isFinite(value) && value >= 0 && value <= Number.MAX_SAFE_INTEGER ? value : fallback;
  }

  private static escapeXml(value: string): string {
    return value.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  }
}
