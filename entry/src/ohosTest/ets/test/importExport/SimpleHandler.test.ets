import { describe, expect, it } from '@ohos/hypium';
import { CsvFamilyDispatcherImportHandler } from '../../../../main/ets/services/importExport/handlers/import/CsvFamilyDispatcherImportHandler';

/**
 * 简单测试 - 验证 CsvFamilyDispatcherImportHandler 是否可以正确导入和实例化
 */
export default function SimpleHandlerTest() {
  describe('SimpleHandler', () => {
    it('shouldImportHandlerClass', 0, () => {
      console.log('CsvFamilyDispatcherImportHandler type: ' + typeof CsvFamilyDispatcherImportHandler);
      console.log('CsvFamilyDispatcherImportHandler: ' + CsvFamilyDispatcherImportHandler);
      expect(CsvFamilyDispatcherImportHandler).not().assertUndefined();
    });

    it('shouldCreateHandlerInstance', 0, () => {
      const handler = new CsvFamilyDispatcherImportHandler();
      console.log('Handler instance: ' + handler);
      console.log('Handler canHandle: ' + handler.canHandle);
      expect(handler).not().assertUndefined();
      expect(handler.canHandle).not().assertUndefined();
    });

    it('shouldCallCanHandle', 0, () => {
      const handler = new CsvFamilyDispatcherImportHandler();
      const result = handler.canHandle('.csv');
      expect(result).assertTrue();
    });
  });
}
