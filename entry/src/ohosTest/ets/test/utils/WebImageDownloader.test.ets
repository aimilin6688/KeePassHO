import { describe, expect, it } from '@ohos/hypium';
import { WebImageDownloader } from '../../../../main/ets/common/utils/WebImageDownloader';

async function expectDownloadRejects(url: string): Promise<void> {
  let threw = false;
  try {
    await WebImageDownloader.downloadImage(url);
  } catch {
    threw = true;
  }
  expect(threw).assertTrue();
}

export default function WebImageDownloaderTest() {
  describe('WebImageDownloader', () => {
    // ---------------- URL validation (rejects before any network I/O) ----------------
    it('downloadImage rejects empty url', 0, async () => {
      await expectDownloadRejects('');
    });

    it('downloadImage rejects malformed url', 0, async () => {
      await expectDownloadRejects('not-a-url');
    });

    it('downloadImage rejects url without scheme', 0, async () => {
      await expectDownloadRejects('example.com/icon.png');
    });

    it('downloadImage rejects non-http scheme', 0, async () => {
      await expectDownloadRejects('ftp://example.com/icon.png');
      await expectDownloadRejects('file://local/icon.png');
    });

    it('downloadImage rejects https url with invalid host', 0, async () => {
      await expectDownloadRejects('https:// /bad host/icon.png');
    });

    // NOTE: happy-path download + image processing (isValidImageType /
    // processImageData are private) require real network + image codec access
    // and are covered by integration/UI flows instead.
  });
}
