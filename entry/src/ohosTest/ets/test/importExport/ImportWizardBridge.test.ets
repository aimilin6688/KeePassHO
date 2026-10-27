import { describe, expect, it, beforeEach } from '@ohos/hypium';
import {
  ImportWizardBridge,
  WizardPagePresenter
} from '../../../../main/ets/services/importExport/wizard/ImportWizardBridge';
import {
  ColumnMappingItem,
  ColumnMappingProfile,
  CsvMappingPreview
} from '../../../../main/ets/services/importExport/csvimport/CsvMappingModels';
import { CsvTargetField } from '../../../../main/ets/services/importExport/csvimport/CsvImportModels';
import { ImportError, ImportExportErrorCode } from '../../../../main/ets/services/importExport/common/ImportExportError';

/**
 * 接受呈现：模拟向导页成功推入（测试桥的挂起/回传流程）
 */
class AcceptingPresenter implements WizardPagePresenter {
  present(preview: CsvMappingPreview): boolean {
    return true;
  }
}

/**
 * 拒绝呈现：模拟无 UI 上下文（headless/后台）
 */
class RefusingPresenter implements WizardPagePresenter {
  present(preview: CsvMappingPreview): boolean {
    return false;
  }
}

/**
 * ImportWizardBridge 单元测试（M2-4，§4.3 交互桥）
 * 1. 无法呈现向导（无 UI 上下文）→ requestColumnMapping 以 null resolve，调用方回落建议映射直导
 * 2. 向导确认 → notifyComplete 回传档案 resolve
 * 3. 取消/页面销毁 → reject(CANCELLED)，防止 Promise 永久挂起
 * 4. 并发第二请求 → reject（已有请求进行中）
 */
export default function ImportWizardBridgeTest() {
  describe('ImportWizardBridge', () => {
    let bridge: ImportWizardBridge = ImportWizardBridge.getInstance();

    beforeEach(() => {
      bridge = ImportWizardBridge.getInstance();
      bridge.reset();
    });

    describe('buildPreview', () => {
      it('shouldBuildPreviewWithSuggestedMapping', 0, () => {
        // ColumnNameMapper：title→TITLE、username→USERNAME、password→PASSWORD、url→URL；未识别列 → CUSTOM（自定义字段，字段名回退源列名）
        const rows: string[][] = [
          ['title', 'username', 'password', 'url', 'customfield'],
          ['A', 'u1', 'p1', 'https://a.com', 'x1'],
          ['B', 'u2', 'p2', 'https://b.com', 'x2']
        ];
        const preview = ImportWizardBridge.buildPreview(rows, 'Detected Format');

        expect(preview.headers.length).assertEqual(5);
        expect(preview.detectedFormatName).assertEqual('Detected Format');
        expect(preview.totalRowEstimate).assertEqual(2);
        expect(preview.sampleRows.length).assertEqual(2);
        expect(preview.suggestedItems.length).assertEqual(5);

        expect(preview.suggestedItems[0].sourceColumnIndex).assertEqual(0);
        expect(preview.suggestedItems[0].sourceColumnName).assertEqual('title');
        expect(preview.suggestedItems[0].targetField).assertEqual(CsvTargetField.TITLE);

        expect(preview.suggestedItems[1].targetField).assertEqual(CsvTargetField.USERNAME);
        expect(preview.suggestedItems[2].targetField).assertEqual(CsvTargetField.PASSWORD);
        expect(preview.suggestedItems[3].targetField).assertEqual(CsvTargetField.URL);
        // 未识别列 → CUSTOM（自定义字段，字段名回退源列名）
        expect(preview.suggestedItems[4].targetField).assertEqual(CsvTargetField.CUSTOM);
      });

      it('shouldLimitSampleRowsToTwenty', 0, () => {
        const rows: string[][] = [['title']];
        for (let i = 0; i < 25; i++) {
          rows.push([`Entry${i}`]);
        }
        const preview = ImportWizardBridge.buildPreview(rows, '');

        expect(preview.sampleRows.length).assertEqual(20);
        expect(preview.totalRowEstimate).assertEqual(25);
        expect(preview.sampleRows[0][0]).assertEqual('Entry0');
        expect(preview.sampleRows[19][0]).assertEqual('Entry19');
      });

      it('shouldHandleHeaderOnlyFile', 0, () => {
        const preview = ImportWizardBridge.buildPreview([['title', 'url']], '');

        expect(preview.sampleRows.length).assertEqual(0);
        expect(preview.totalRowEstimate).assertEqual(0);
        expect(preview.suggestedItems.length).assertEqual(2);
      });
    });

    describe('requestColumnMapping', () => {
      it('shouldResolveNullWhenPresenterRefuses', 0, async () => {
        bridge.setPresenter(new RefusingPresenter());
        const preview = ImportWizardBridge.buildPreview([['title'], ['A']], '');

        const profile = await bridge.requestColumnMapping(preview);

        expect(profile).assertNull();
        expect(bridge.getPendingPreview()).assertNull();
      });

      it('shouldResolveProfileOnNotifyComplete', 0, async () => {
        bridge.setPresenter(new AcceptingPresenter());
        const preview = ImportWizardBridge.buildPreview([['title'], ['A']], '');
        const expected = new ColumnMappingProfile(
          [new ColumnMappingItem(0, 'title', CsvTargetField.TITLE)],
          'Imported'
        );

        const pendingPromise = bridge.requestColumnMapping(preview);
        // 挂起期间预览可被向导页读取
        expect(bridge.getPendingPreview()).assertEqual(preview);

        bridge.notifyComplete(expected);
        const resolved = await pendingPromise;

        expect(resolved === expected).assertTrue();
        expect(resolved?.importTargetGroupName).assertEqual('Imported');
        // 完成后桥清空挂起状态
        expect(bridge.getPendingPreview()).assertNull();
      });

      it('shouldRejectCancelledOnNotifyCancelled', 0, async () => {
        bridge.setPresenter(new AcceptingPresenter());
        const preview = ImportWizardBridge.buildPreview([['title'], ['A']], '');

        const pendingPromise = bridge.requestColumnMapping(preview);
        bridge.notifyCancelled();

        try {
          await pendingPromise;
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.CANCELLED);
          } else {
            expect().assertFail();
          }
        }
        expect(bridge.getPendingPreview()).assertNull();
      });

      it('shouldRejectSecondConcurrentRequest', 0, async () => {
        bridge.setPresenter(new AcceptingPresenter());
        const preview = ImportWizardBridge.buildPreview([['title'], ['A']], '');

        const firstPromise = bridge.requestColumnMapping(preview);
        try {
          await bridge.requestColumnMapping(preview);
          expect().assertFail();
        } catch (err) {
          const error = err as Error;
          if (error instanceof ImportError) {
            expect(error.code).assertEqual(ImportExportErrorCode.PARSE_ERROR);
          }
        }

        // 清理第一请求
        bridge.notifyCancelled();
        try {
          await firstPromise;
        } catch (err) {
          // 预期取消
        }
      });

      it('shouldIgnoreResultWhenNoPendingRequest', 0, () => {
        // 无挂起时回传结果应为空操作（如页面销毁兜底晚到）
        bridge.notifyCancelled();
        bridge.notifyComplete(new ColumnMappingProfile([], ''));
        expect(bridge.getPendingPreview()).assertNull();
      });
    });
  });
}
