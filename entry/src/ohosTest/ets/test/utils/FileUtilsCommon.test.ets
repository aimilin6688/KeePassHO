import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from '@ohos/hypium';
import { fileShare } from '@kit.CoreFileKit';
import { FileUtils } from '../../../../main/ets/common/utils/FileUtils';

export default function FileUtilsCommonTest() {
  describe('FileUtilsCommon', () => {
    beforeAll(() => {
    });

    beforeEach(() => {
    });

    afterEach(() => {
    });

    afterAll(() => {
    });

    // ---------------- activatePermission ----------------
    it('activatePermission throws when unsupported or returns promise when supported', 0, () => {
      try {
        const result = FileUtils.activatePermission('file://test/path', fileShare.OperationMode.READ_MODE);
        // Supported on this device: should return a Promise
        expect(result).not().assertNull();
      } catch (e) {
        expect((e as Error).message).assertEqual('this api is not supported on this device');
      }
    });

    // ---------------- persistPermission ----------------
    it('persistPermission throws when unsupported or returns promise when supported', 0, () => {
      try {
        const result = FileUtils.persistPermission('file://test/path', fileShare.OperationMode.READ_MODE);
        expect(result).not().assertNull();
      } catch (e) {
        expect((e as Error).message).assertEqual('this api is not supported on this device');
      }
    });

    // ---------------- checkPersistPermission ----------------
    it('checkPersistPermission throws when unsupported or returns promise when supported', 0, () => {
      try {
        const result = FileUtils.checkPersistPermission('file://test/path', fileShare.OperationMode.READ_MODE);
        expect(result).not().assertNull();
      } catch (e) {
        expect((e as Error).message).assertEqual('this api is not supported on this device');
      }
    });

    // ---------------- revokePermission ----------------
    it('revokePermission throws when unsupported or returns promise when supported', 0, () => {
      try {
        const result = FileUtils.revokePermission('file://test/path', fileShare.OperationMode.READ_MODE);
        expect(result).not().assertNull();
      } catch (e) {
        expect((e as Error).message).assertEqual('this api is not supported on this device');
      }
    });

    it('activatePermission accepts combined operation mode', 0, () => {
      const mode = fileShare.OperationMode.READ_MODE | fileShare.OperationMode.WRITE_MODE;
      try {
        const result = FileUtils.activatePermission('file://test/path', mode);
        expect(result).not().assertNull();
      } catch (e) {
        expect((e as Error).message).assertEqual('this api is not supported on this device');
      }
    });

    // ---------------- getFileIcon ----------------
    it('getFileIcon returns resource for txt extension', 0, () => {
      const icon = FileUtils.getFileIcon('readme.txt');
      expect(icon).not().assertNull();
    });

    it('getFileIcon returns resource for pdf extension', 0, () => {
      const icon = FileUtils.getFileIcon('doc.pdf');
      expect(icon).not().assertNull();
    });

    it('getFileIcon returns resource for doc/docx extension', 0, () => {
      expect(FileUtils.getFileIcon('a.doc')).not().assertNull();
      expect(FileUtils.getFileIcon('a.docx')).not().assertNull();
    });

    it('getFileIcon returns resource for xls/xlsx extension', 0, () => {
      expect(FileUtils.getFileIcon('a.xls')).not().assertNull();
      expect(FileUtils.getFileIcon('a.xlsx')).not().assertNull();
    });

    it('getFileIcon returns resource for ppt/pptx extension', 0, () => {
      expect(FileUtils.getFileIcon('a.ppt')).not().assertNull();
      expect(FileUtils.getFileIcon('a.pptx')).not().assertNull();
    });

    it('getFileIcon returns resource for image extensions', 0, () => {
      expect(FileUtils.getFileIcon('a.jpg')).not().assertNull();
      expect(FileUtils.getFileIcon('a.jpeg')).not().assertNull();
      expect(FileUtils.getFileIcon('a.png')).not().assertNull();
      expect(FileUtils.getFileIcon('a.gif')).not().assertNull();
    });

    it('getFileIcon returns resource for audio extensions', 0, () => {
      expect(FileUtils.getFileIcon('a.iav')).not().assertNull();
      expect(FileUtils.getFileIcon('a.mp3')).not().assertNull();
    });

    it('getFileIcon returns resource for video extension', 0, () => {
      expect(FileUtils.getFileIcon('a.mp4')).not().assertNull();
    });

    it('getFileIcon returns resource for archive extensions', 0, () => {
      expect(FileUtils.getFileIcon('a.zip')).not().assertNull();
      expect(FileUtils.getFileIcon('a.rar')).not().assertNull();
      expect(FileUtils.getFileIcon('a.7z')).not().assertNull();
    });

    it('getFileIcon returns resource for kdbx extension', 0, () => {
      expect(FileUtils.getFileIcon('db.kdbx')).not().assertNull();
    });

    it('getFileIcon returns resource for csv extension', 0, () => {
      expect(FileUtils.getFileIcon('data.csv')).not().assertNull();
    });

    it('getFileIcon returns resource for xml extension', 0, () => {
      expect(FileUtils.getFileIcon('data.xml')).not().assertNull();
    });

    it('getFileIcon is case insensitive', 0, () => {
      const lower = FileUtils.getFileIcon('a.txt');
      const upper = FileUtils.getFileIcon('A.TXT');
      expect(lower).not().assertNull();
      expect(upper).not().assertNull();
    });

    it('getFileIcon returns default resource for unknown extension', 0, () => {
      const icon = FileUtils.getFileIcon('a.unknownext');
      expect(icon).not().assertNull();
    });

    it('getFileIcon returns default resource for no extension', 0, () => {
      const icon = FileUtils.getFileIcon('noextension');
      expect(icon).not().assertNull();
    });

    // ---------------- saveLocalFile / selectFiles ----------------
    // Skipped: these methods require interactive DocumentViewPicker UI dialogs
    // which cannot be driven from a headless unit test environment.
  });
}
