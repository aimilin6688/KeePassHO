import { describe, expect, it } from '@ohos/hypium';
import { AutoOpenPathResolver } from '../../../../../main/ets/services/autoopen/AutoOpenPathResolver';

/**
 * AutoOpen URL 占位符展开与相对路径处理测试
 */
export default function AutoOpenPathResolverTest() {
  describe('AutoOpenPathResolver', () => {
    it('getDirName: plain path', 0, () => {
      expect(AutoOpenPathResolver.getDirName('/data/docs/db/shared.kdbx')).assertEqual('/data/docs/db');
    });

    it('getDirName: file uri keeps scheme prefix', 0, () => {
      expect(AutoOpenPathResolver.getDirName('file://docs/db/shared.kdbx')).assertEqual('file://docs/db');
    });

    it('getDirName: root and empty edge cases', 0, () => {
      expect(AutoOpenPathResolver.getDirName('/a.kdbx')).assertEqual('/');
      expect(AutoOpenPathResolver.getDirName('a.kdbx')).assertEqual('');
      expect(AutoOpenPathResolver.getDirName('')).assertEqual('');
    });

    it('resolveUrl: empty url returns empty', 0, () => {
      expect(AutoOpenPathResolver.resolveUrl('', '/docs/parent.kdbx')).assertEqual('');
      expect(AutoOpenPathResolver.resolveUrl('   ', '/docs/parent.kdbx')).assertEqual('');
    });

    it('resolveUrl: expands {DB_DIR} and {ENV_DIRSEP}', 0, () => {
      const resolved = AutoOpenPathResolver.resolveUrl('{DB_DIR}{ENV_DIRSEP}child.kdbx', '/docs/parent.kdbx');
      expect(resolved).assertEqual('/docs/child.kdbx');
    });

    it('resolveUrl: expands placeholders with file uri parent', 0, () => {
      const resolved = AutoOpenPathResolver.resolveUrl('{DB_DIR}{ENV_DIRSEP}sub/child.kdbx', 'file://docs/parent.kdbx');
      expect(resolved).assertEqual('file://docs/sub/child.kdbx');
    });

    it('resolveUrl: absolute path unchanged', 0, () => {
      expect(AutoOpenPathResolver.resolveUrl('/other/child.kdbx', '/docs/parent.kdbx')).assertEqual('/other/child.kdbx');
    });

    it('resolveUrl: absolute uri unchanged', 0, () => {
      const url = 'webdav://host/remote/child.kdbx';
      expect(AutoOpenPathResolver.resolveUrl(url, '/docs/parent.kdbx')).assertEqual(url);
    });

    it('resolveUrl: bare relative path resolved against parent dir', 0, () => {
      expect(AutoOpenPathResolver.resolveUrl('child.kdbx', '/docs/parent.kdbx')).assertEqual('/docs/child.kdbx');
      expect(AutoOpenPathResolver.resolveUrl('sub/child.kdbx', '/docs/parent.kdbx')).assertEqual('/docs/sub/child.kdbx');
    });

    it('resolveUrl: kdbx prefix stripped, absolute remainder unchanged', 0, () => {
      expect(AutoOpenPathResolver.resolveUrl('kdbx:///docs/child.kdbx', '/docs/parent.kdbx'))
        .assertEqual('/docs/child.kdbx');
    });

    it('resolveUrl: kdbx prefix with relative remainder resolves against parent dir', 0, () => {
      expect(AutoOpenPathResolver.resolveUrl('kdbx://sub/child.kdbx', '/docs/parent.kdbx'))
        .assertEqual('/docs/sub/child.kdbx');
    });

    it('resolveUrl: kdbx prefix with empty remainder returns empty', 0, () => {
      expect(AutoOpenPathResolver.resolveUrl('kdbx://', '/docs/parent.kdbx')).assertEqual('');
    });

    it('resolveUrl: uppercase KDBX prefix is not stripped (XC startsWith is case-sensitive)', 0, () => {
      expect(AutoOpenPathResolver.resolveUrl('KDBX://child.kdbx', '/docs/parent.kdbx'))
        .assertEqual('KDBX://child.kdbx');
    });

    it('resolveUrl: relative path with no parent dir stays as-is', 0, () => {
      expect(AutoOpenPathResolver.resolveUrl('child.kdbx', 'parent.kdbx')).assertEqual('child.kdbx');
    });

    it('makeRelative: same dir produces {DB_DIR}{ENV_DIRSEP} form', 0, () => {
      const made = AutoOpenPathResolver.makeRelative('/docs/child.kdbx', '/docs/parent.kdbx');
      expect(made).assertEqual('{DB_DIR}{ENV_DIRSEP}child.kdbx');
    });

    it('makeRelative: different dir keeps absolute path', 0, () => {
      const made = AutoOpenPathResolver.makeRelative('/other/child.kdbx', '/docs/parent.kdbx');
      expect(made).assertEqual('/other/child.kdbx');
    });

    it('makeRelative: empty child path returns empty', 0, () => {
      expect(AutoOpenPathResolver.makeRelative('', '/docs/parent.kdbx')).assertEqual('');
    });

    it('makeRelative → resolveUrl round-trip', 0, () => {
      const child = '/docs/sub/child.kdbx';
      const parent = '/docs/parent.kdbx';
      const made = AutoOpenPathResolver.makeRelative(child, parent);
      expect(AutoOpenPathResolver.resolveUrl(made, parent)).assertEqual(child);
    });
  });
}
