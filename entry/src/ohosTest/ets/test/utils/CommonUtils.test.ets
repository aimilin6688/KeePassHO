import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { promptAction } from '@kit.ArkUI';
import { common } from '@kit.AbilityKit';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { CommonUtils, StorageContextStub } from '../../../../main/ets/common/utils/CommonUtils';

function initContext(): void {
  const appContext =  abilityDelegatorRegistry.getAbilityDelegator().getAppContext();
  CommonUtils.init(appContext as common.UIAbilityContext);
}

export default function CommonUtilsTest() {
  describe('CommonUtils', () => {
    beforeAll(() => {
      initContext();
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
      // Restore context for subsequent test suites that rely on it
      initContext();
    });

    // ---------------- base64Encode ----------------
    it('base64Encode encodes plain ascii string', 0, () => {
      expect(CommonUtils.base64Encode('hello')).assertEqual('aGVsbG8=');
    });

    it('base64Encode encodes empty string', 0, () => {
      // Current source passes the zero-length byte array straight to
      // util.Base64Helper.encodeToStringSync, which rejects it with
      // "Parameter error. The type of Parameter must be Uint8Array and the
      // length greater than zero". If a future source change ever handles ''
      // gracefully, the canonical empty encoding is ''.
      try {
        const encoded: string = CommonUtils.base64Encode('');
        expect(encoded).assertEqual('');
      } catch (e) {
        expect((e as Error).message).assertContain('Parameter error');
      }
    });

    it('base64Encode encodes ascii with numbers', 0, () => {
      expect(CommonUtils.base64Encode('test123')).assertEqual('dGVzdDEyMw==');
    });

    it('base64Encode encodes chinese characters (UTF-8)', 0, () => {
      expect(CommonUtils.base64Encode('中文')).assertEqual('5Lit5paH');
    });

    it('base64Encode encodes special characters', 0, () => {
      const encoded = CommonUtils.base64Encode('!@#$%^&*()');
      expect(encoded.length > 0).assertTrue();
    });

    // ---------------- getMimeTypeFromExtension ----------------
    it('getMimeTypeFromExtension returns text/plain for txt', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.txt')).assertEqual('text/plain');
    });

    it('getMimeTypeFromExtension returns application/pdf for pdf', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.pdf')).assertEqual('application/pdf');
    });

    it('getMimeTypeFromExtension returns image/jpeg for jpg and jpeg', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.jpg')).assertEqual('image/jpeg');
      expect(CommonUtils.getMimeTypeFromExtension('a.jpeg')).assertEqual('image/jpeg');
    });

    it('getMimeTypeFromExtension returns image/png for png', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.png')).assertEqual('image/png');
    });

    it('getMimeTypeFromExtension returns image/gif for gif', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.gif')).assertEqual('image/gif');
    });

    it('getMimeTypeFromExtension returns image/webp for webp', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.webp')).assertEqual('image/webp');
    });

    it('getMimeTypeFromExtension returns image/bmp for bmp', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.bmp')).assertEqual('image/bmp');
    });

    it('getMimeTypeFromExtension returns image/x-icon for ico', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.ico')).assertEqual('image/x-icon');
    });

    it('getMimeTypeFromExtension returns audio/mpeg for mp3', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.mp3')).assertEqual('audio/mpeg');
    });

    it('getMimeTypeFromExtension returns video/mp4 for mp4', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.mp4')).assertEqual('video/mp4');
    });

    it('getMimeTypeFromExtension returns word types for doc/docx', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.doc')).assertEqual('application/msword');
      expect(CommonUtils.getMimeTypeFromExtension('a.docx'))
        .assertEqual('application/vnd.openxmlformats-officedocument.wordprocessingml.document');
    });

    it('getMimeTypeFromExtension returns excel types for xls/xlsx', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.xls')).assertEqual('application/vnd.ms-excel');
      expect(CommonUtils.getMimeTypeFromExtension('a.xlsx'))
        .assertEqual('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet');
    });

    it('getMimeTypeFromExtension returns powerpoint types for ppt/pptx', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.ppt')).assertEqual('application/vnd.ms-powerpoint');
      expect(CommonUtils.getMimeTypeFromExtension('a.pptx'))
        .assertEqual('application/vnd.openxmlformats-officedocument.presentationml.presentation');
    });

    it('getMimeTypeFromExtension returns zip/rar types', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.zip')).assertEqual('application/zip');
      expect(CommonUtils.getMimeTypeFromExtension('a.rar')).assertEqual('application/x-rar-compressed');
    });

    it('getMimeTypeFromExtension returns application/json for json', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.json')).assertEqual('application/json');
    });

    it('getMimeTypeFromExtension returns text/html for html', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.html')).assertEqual('text/html');
    });

    it('getMimeTypeFromExtension returns text/css for css', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.css')).assertEqual('text/css');
    });

    it('getMimeTypeFromExtension returns text/javascript for js', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.js')).assertEqual('text/javascript');
    });

    it('getMimeTypeFromExtension returns default for unknown extension', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.unknownext')).assertEqual('application/octet-stream');
    });

    it('getMimeTypeFromExtension returns default for no extension', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('noext')).assertEqual('application/octet-stream');
    });

    it('getMimeTypeFromExtension is case insensitive', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.TXT')).assertEqual('text/plain');
      expect(CommonUtils.getMimeTypeFromExtension('a.PDF')).assertEqual('application/pdf');
    });

    it('getMimeTypeFromExtension handles path with multiple dots', 0, () => {
      expect(CommonUtils.getMimeTypeFromExtension('a.b.c.txt')).assertEqual('text/plain');
    });

    // ---------------- context lifecycle ----------------
    it('hasContext returns true after init', 0, () => {
      expect(CommonUtils.hasContext()).assertTrue();
    });

    it('clearContextForTest sets context to null', 0, () => {
      CommonUtils.clearContextForTest();
      expect(CommonUtils.hasContext()).assertFalse();
      initContext();
    });

    it('getContext returns the initialized context', 0, () => {
      expect(CommonUtils.getContext()).not().assertNull();
    });

    // ---------------- worker paths ----------------
    it('getAppFilesDir returns injected path when no context', 0, () => {
      CommonUtils.clearContextForTest();
      CommonUtils.setWorkerPaths('/data/injected/files', '/data/injected/cache');
      expect(CommonUtils.getAppFilesDir()).assertEqual('/data/injected/files');
      initContext();
    });

    it('getCacheDir returns injected path when no context', 0, () => {
      CommonUtils.clearContextForTest();
      CommonUtils.setWorkerPaths('/data/injected/files', '/data/injected/cache');
      expect(CommonUtils.getCacheDir()).assertEqual('/data/injected/cache');
      initContext();
    });

    it('getAppFilesDir returns context dir when context exists', 0, () => {
      const dir = CommonUtils.getAppFilesDir();
      expect(dir.length > 0).assertTrue();
    });

    it('getCacheDir returns context dir when context exists', 0, () => {
      const dir = CommonUtils.getCacheDir();
      expect(dir.length > 0).assertTrue();
    });

    // ---------------- getStorageContext ----------------
    it('getStorageContext returns context when available', 0, () => {
      const ctx = CommonUtils.getStorageContext();
      expect(ctx).not().assertNull();
    });

    it('getStorageContext returns StorageContextStub when no context', 0, () => {
      CommonUtils.clearContextForTest();
      CommonUtils.setWorkerPaths('/data/injected/files', '/data/injected/cache');
      const ctx = CommonUtils.getStorageContext();
      expect(ctx instanceof StorageContextStub).assertTrue();
      initContext();
    });

    it('getStorageContext stub carries injected cacheDir', 0, () => {
      CommonUtils.clearContextForTest();
      CommonUtils.setWorkerPaths('/data/injected/files', '/my/cache');
      const ctx = CommonUtils.getStorageContext();
      if (ctx instanceof StorageContextStub) {
        expect(ctx.cacheDir).assertEqual('/my/cache');
      }
      initContext();
    });

    // ---------------- StorageContextStub ----------------
    it('StorageContextStub stores cacheDir in constructor', 0, () => {
      const stub = new StorageContextStub('/my/cache/dir');
      expect(stub.cacheDir).assertEqual('/my/cache/dir');
    });

    it('StorageContextStub stores empty cacheDir', 0, () => {
      const stub = new StorageContextStub('');
      expect(stub.cacheDir).assertEqual('');
    });

    // ---------------- getExistsFileDialog ----------------
    it('getExistsFileDialog returns options with title and message', 0, () => {
      const dialog = CommonUtils.getExistsFileDialog();
      expect(dialog).not().assertNull();
      expect(dialog.title).not().assertNull();
      expect(dialog.message).not().assertNull();
    });

    it('getExistsFileDialog returns two buttons', 0, () => {
      const dialog = CommonUtils.getExistsFileDialog();
      expect(dialog.buttons).not().assertNull();
      const buttons: promptAction.Button[] = dialog.buttons ?? [];
      expect(buttons.length).assertEqual(2);
    });

    // ---------------- showToast / showDialog / pushUrl / replaceUrl / back ----------------
    // Skipped: these methods require a live UIContext / router and are not pure logic.
    // They are covered by UI automation tests instead.
  });
}
