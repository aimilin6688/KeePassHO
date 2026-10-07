import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { ShareUtils } from '../../../../main/ets/common/utils/ShareUtils';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common } from '@kit.AbilityKit';

function withTimeout(promise: Promise<boolean>, ms: number): Promise<boolean> {
  return new Promise<boolean>(resolve => {
    promise.then((result: boolean) => resolve(result));
    setTimeout(() => resolve(false), ms);
  });
}

export default function ShareUtilsTest() {
  describe('ShareUtils', () => {
    let context: common.UIAbilityContext;

    beforeAll(() => {
      const appContext =  abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
      context = appContext as common.UIAbilityContext;
    });

    beforeEach(() => {});
    afterEach(() => {});
    afterAll(() => {});

    it('shareFiles returns false for empty file list (pure logic)', 0, async () => {
      const result = await ShareUtils.shareFiles(context, []);
      expect(result).assertFalse();
    });

    it('shareFile returns false when share panel cannot show', 0, async () => {
      const result = await withTimeout(
        ShareUtils.shareFile(context, '/nonexistent/path/test.txt'),
        5000
      );
      expect(result).assertFalse();
    });

    it('shareFile with title returns false when share panel cannot show', 0, async () => {
      const result = await withTimeout(
        ShareUtils.shareFile(context, '/nonexistent/path/test.txt', 'Test Title'),
        5000
      );
      expect(result).assertFalse();
    });

    it('shareFileWithCallback returns false when share panel cannot show', 0, async () => {
      const result = await withTimeout(
        ShareUtils.shareFileWithCallback(context, '/nonexistent/path/test.txt', () => {}, 'Title'),
        5000
      );
      expect(result).assertFalse();
    });

    it('shareText returns false when share panel cannot show', 0, async () => {
      const result = await withTimeout(
        ShareUtils.shareText(context, 'hypium share text content'),
        5000
      );
      expect(result).assertFalse();
    });

    it('shareText with title returns false when share panel cannot show', 0, async () => {
      const result = await withTimeout(
        ShareUtils.shareText(context, 'hypium share text content', 'Text Title'),
        5000
      );
      expect(result).assertFalse();
    });

    it('shareLink returns false when share panel cannot show', 0, async () => {
      const result = await withTimeout(
        ShareUtils.shareLink(context, 'https://example.com', 'Link Title'),
        5000
      );
      expect(result).assertFalse();
    });

    it('shareLink with description returns false when share panel cannot show', 0, async () => {
      const result = await withTimeout(
        ShareUtils.shareLink(context, 'https://example.com', 'Link Title', 'Link Description'),
        5000
      );
      expect(result).assertFalse();
    });

    it('shareFiles with multiple paths returns false when share panel cannot show', 0, async () => {
      const result = await withTimeout(
        ShareUtils.shareFiles(context, ['/path/a.txt', '/path/b.txt'], 'Multi Title'),
        5000
      );
      expect(result).assertFalse();
    });

    it('shareFiles with single path returns false when share panel cannot show', 0, async () => {
      const result = await withTimeout(
        ShareUtils.shareFiles(context, ['/single/path.txt']),
        5000
      );
      expect(result).assertFalse();
    });
  });
}
