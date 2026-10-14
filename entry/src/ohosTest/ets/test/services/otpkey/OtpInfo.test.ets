import { describe, expect, it } from '@ohos/hypium';
import { OtpEncryptedData, OtpInfo } from '../../../../../main/ets/services/otpkey/OtpInfo';

/**
 * 辅助文件 .otp.xml 解析/序列化测试：
 * - v2（EncryptedSecrets[]）与 v1（EncryptedSecret）双格式解析；
 * - 缺失字段取 .NET XmlSerializer 默认值（12000/8/4/0）；
 * - toXml → fromXml 往返一致；Counter 写回后序列化正确。
 */
export default function OtpInfoTest() {
  describe('OtpInfo', () => {
    const v2Xml = '<?xml version="1.0" encoding="utf-8"?>\n' +
      '<OtpInfo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" ' +
      'xmlns:xsd="http://www.w3.org/2001/XMLSchema">\n' +
      '\t<Type>OATH HOTP / RFC 4226</Type>\n' +
      '\t<Version>2.0</Version>\n' +
      '\t<Generator>OtpKeyProv KeePass Plugin</Generator>\n' +
      '\t<EncryptedSecret />\n' +
      '\t<EncryptedSecrets>\n' +
      '\t\t<EncryptedData>\n' +
      '\t\t\t<CipherText>s20://IQ7Y3d0kVrXOk+6qgdcP595cd83SbK+I6S6jergcfBg=</CipherText>\n' +
      '\t\t\t<IV>MDEyMzQ1Njc4OTo7PD0+Pw==</IV>\n' +
      '\t\t\t<TransformationKey>EBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8=</TransformationKey>\n' +
      '\t\t\t<TransformationRounds>10000</TransformationRounds>\n' +
      '\t\t\t<PlainTextHash>nr9EWld3C/C3fyykGJtwlEUy9tpy9pZq56AJC6vYsGs=</PlainTextHash>\n' +
      '\t\t\t<PlainTextHashTransformationKey>ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=</PlainTextHashTransformationKey>\n' +
      '\t\t\t<PlainTextHashTransformationRounds>10000</PlainTextHashTransformationRounds>\n' +
      '\t\t</EncryptedData>\n' +
      '\t</EncryptedSecrets>\n' +
      '\t<EncryptionIV />\n' +
      '\t<TransformationKey />\n' +
      '\t<TransformationRounds>12000</TransformationRounds>\n' +
      '\t<Counter>4</Counter>\n' +
      '\t<OtpLength>8</OtpLength>\n' +
      '\t<OtpsRequired>4</OtpsRequired>\n' +
      '\t<LookAheadCount>2</LookAheadCount>\n' +
      '</OtpInfo>';

    it('v2 parse: all fields mapped, nested EncryptedData parsed', 0, () => {
      const info = OtpInfo.fromXml(v2Xml);
      expect(info.type).assertEqual('OATH HOTP / RFC 4226');
      expect(info.version).assertEqual('2.0');
      expect(info.generator).assertEqual('OtpKeyProv KeePass Plugin');
      expect(info.encryptedSecret).assertEqual('');
      expect(info.encryptedSecrets.length).assertEqual(1);
      expect(info.encryptionIV).assertEqual('');
      expect(info.transformationKey).assertEqual('');
      expect(info.transformationRounds).assertEqual(12000);
      expect(info.counter).assertEqual(4);
      expect(info.otpLength).assertEqual(8);
      expect(info.otpsRequired).assertEqual(4);
      expect(info.lookAheadCount).assertEqual(2);

      const d = info.encryptedSecrets[0];
      expect(d.cipherText).assertEqual('s20://IQ7Y3d0kVrXOk+6qgdcP595cd83SbK+I6S6jergcfBg=');
      expect(d.iv).assertEqual('MDEyMzQ1Njc4OTo7PD0+Pw==');
      expect(d.transformationKey).assertEqual('EBESExQVFhcYGRobHB0eHyAhIiMkJSYnKCkqKywtLi8=');
      expect(d.transformationRounds).assertEqual(10000);
      expect(d.plainTextHash).assertEqual('nr9EWld3C/C3fyykGJtwlEUy9tpy9pZq56AJC6vYsGs=');
      expect(d.plainTextHashTransformationKey).assertEqual('ICEiIyQlJicoKSorLC0uLzAxMjM0NTY3ODk6Ozw9Pj8=');
      expect(d.plainTextHashTransformationRounds).assertEqual(10000);
    });

    it('v1 parse: deprecated EncryptedSecret fields', 0, () => {
      const v1Xml = '<?xml version="1.0" encoding="utf-8"?>\n' +
        '<OtpInfo>\n' +
        '\t<Type>OATH HOTP / RFC 4226</Type>\n' +
        '\t<Version>1.0</Version>\n' +
        '\t<EncryptedSecret>s20://kX+X9jfmfc7gjXTvvLII4Q==</EncryptedSecret>\n' +
        '\t<EncryptionIV>UFFSU1RVVldYWVpbXF1eXw==</EncryptionIV>\n' +
        '\t<TransformationKey>QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8=</TransformationKey>\n' +
        '\t<TransformationRounds>6000</TransformationRounds>\n' +
        '\t<Counter>9</Counter>\n' +
        '\t<OtpLength>7</OtpLength>\n' +
        '\t<OtpsRequired>2</OtpsRequired>\n' +
        '</OtpInfo>';
      const info = OtpInfo.fromXml(v1Xml);
      expect(info.version).assertEqual('1.0');
      expect(info.encryptedSecret).assertEqual('s20://kX+X9jfmfc7gjXTvvLII4Q==');
      expect(info.encryptedSecrets.length).assertEqual(0);
      expect(info.encryptionIV).assertEqual('UFFSU1RVVldYWVpbXF1eXw==');
      expect(info.transformationKey).assertEqual('QEFCQ0RFRkdISUpLTE1OT1BRUlNUVVZXWFlaW1xdXl8=');
      expect(info.transformationRounds).assertEqual(6000);
      expect(info.counter).assertEqual(9);
      expect(info.otpLength).assertEqual(7);
      expect(info.otpsRequired).assertEqual(2);
      expect(info.lookAheadCount).assertEqual(0);
    });

    it('defaults: minimal xml takes .NET serializer defaults', 0, () => {
      const info = OtpInfo.fromXml('<OtpInfo><Counter>1</Counter></OtpInfo>');
      expect(info.transformationRounds).assertEqual(12000);
      expect(info.otpLength).assertEqual(8);
      expect(info.otpsRequired).assertEqual(4);
      expect(info.lookAheadCount).assertEqual(0);
      expect(info.counter).assertEqual(1);
      expect(info.encryptedSecrets.length).assertEqual(0);
    });

    it('toXml → fromXml round-trip preserves all fields (v2)', 0, () => {
      const source = OtpInfo.fromXml(v2Xml);
      const restored = OtpInfo.fromXml(source.toXml());
      expect(restored.type).assertEqual(source.type);
      expect(restored.version).assertEqual(source.version);
      expect(restored.generator).assertEqual(source.generator);
      expect(restored.encryptedSecret).assertEqual(source.encryptedSecret);
      expect(restored.encryptionIV).assertEqual(source.encryptionIV);
      expect(restored.transformationKey).assertEqual(source.transformationKey);
      expect(restored.transformationRounds).assertEqual(source.transformationRounds);
      expect(restored.counter).assertEqual(source.counter);
      expect(restored.otpLength).assertEqual(source.otpLength);
      expect(restored.otpsRequired).assertEqual(source.otpsRequired);
      expect(restored.lookAheadCount).assertEqual(source.lookAheadCount);
      expect(restored.encryptedSecrets.length).assertEqual(source.encryptedSecrets.length);
      const a = restored.encryptedSecrets[0];
      const b = source.encryptedSecrets[0];
      expect(a.cipherText).assertEqual(b.cipherText);
      expect(a.iv).assertEqual(b.iv);
      expect(a.transformationKey).assertEqual(b.transformationKey);
      expect(a.transformationRounds).assertEqual(b.transformationRounds);
      expect(a.plainTextHash).assertEqual(b.plainTextHash);
      expect(a.plainTextHashTransformationKey).assertEqual(b.plainTextHashTransformationKey);
      expect(a.plainTextHashTransformationRounds).assertEqual(b.plainTextHashTransformationRounds);
    });

    it('counter write-back: parsed + delta → serialized counter', 0, () => {
      const info = OtpInfo.fromXml(v2Xml);
      info.counter += 4 + 2;
      const xml = info.toXml();
      expect(xml.includes('<Counter>10</Counter>')).assertTrue();
      expect(OtpInfo.fromXml(xml).counter).assertEqual(10);
    });
  });
}
