import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { UrlUtils } from '../../../../main/ets/common/utils/UrlUtils';

export default function UrlUtilsTest() {
  describe('UrlUtils', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    // ---------------- getHost ----------------
    it('getHost returns protocol + host for http url with path', 0, () => {
      expect(UrlUtils.getHost('http://www.aimilin.net/a/b/c')).assertEqual('http://www.aimilin.net');
    });

    it('getHost returns protocol + host for https url', 0, () => {
      expect(UrlUtils.getHost('https://example.com/path')).assertEqual('https://example.com');
    });

    it('getHost returns protocol + host for root url', 0, () => {
      expect(UrlUtils.getHost('http://example.com')).assertEqual('http://example.com');
    });

    it('getHost returns empty for undefined', 0, () => {
      expect(UrlUtils.getHost(undefined)).assertEqual('');
    });

    it('getHost returns empty for empty string', 0, () => {
      expect(UrlUtils.getHost('')).assertEqual('');
    });

    it('getHost returns a string for malformed input without throwing', 0, () => {
      const result = UrlUtils.getHost('not a url');
      expect(typeof result).assertEqual('string');
    });

    // ---------------- isValidUrl ----------------
    it('isValidUrl returns true for http', 0, () => {
      expect(UrlUtils.isValidUrl('http://example.com')).assertTrue();
    });

    it('isValidUrl returns true for https with query', 0, () => {
      expect(UrlUtils.isValidUrl('https://example.com/path?q=1')).assertTrue();
    });

    it('isValidUrl returns false for ftp', 0, () => {
      expect(UrlUtils.isValidUrl('ftp://example.com')).assertFalse();
    });

    it('isValidUrl returns false for invalid string', 0, () => {
      expect(UrlUtils.isValidUrl('not a url')).assertFalse();
    });

    it('isValidUrl returns false for empty string', 0, () => {
      expect(UrlUtils.isValidUrl('')).assertFalse();
    });

    // ---------------- encode / decode ----------------
    it('encode encodes space', 0, () => {
      expect(UrlUtils.encode('hello world')).assertEqual('hello%20world');
    });

    it('encode encodes special chars', 0, () => {
      expect(UrlUtils.encode('a/b?c=1&d=2')).assertEqual('a%2Fb%3Fc%3D1%26d%3D2');
    });

    it('encode does not change alphanumeric', 0, () => {
      expect(UrlUtils.encode('abc123')).assertEqual('abc123');
    });

    it('decode decodes space', 0, () => {
      expect(UrlUtils.decode('hello%20world')).assertEqual('hello world');
    });

    it('decode decodes special chars', 0, () => {
      expect(UrlUtils.decode('a%2Fb%3Fc%3D1%26d%3D2')).assertEqual('a/b?c=1&d=2');
    });

    it('encode then decode round trip for ascii', 0, () => {
      const original = 'string 123 !@#';
      const encoded = UrlUtils.encode(original);
      expect(UrlUtils.decode(encoded)).assertEqual(original);
    });

    it('encode then decode round trip for chinese', 0, () => {
      const original = '测试中文';
      const encoded = UrlUtils.encode(original);
      expect(UrlUtils.decode(encoded)).assertEqual(original);
    });
  });
}
