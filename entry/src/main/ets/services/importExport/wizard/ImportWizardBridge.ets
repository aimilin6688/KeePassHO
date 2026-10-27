import { NavigationManager, ResourceManager } from '../../../common/utils';
import {
  ColumnMappingItem,
  ColumnMappingProfile,
  CsvMappingPreview,
  WizardTargetField,
  WizardTargetFieldConverter
} from '../csvimport/CsvMappingModels';
import { CsvColumnMappingEngine } from '../csvimport/CsvColumnMappingEngine';
import { ImportError, ImportExportErrorCode } from '../common/ImportExportError';

/** 预览采样行数上限（§5.1：前 20 行） */
const PREVIEW_SAMPLE_ROW_LIMIT = 20;

/**
 * 向导页面呈现器：把预览推到向导页
 * 返回 false 表示无法呈现（无导航栈 / 无 UI 上下文），桥以 null resolve 由调用方回落
 */
export interface WizardPagePresenter {
  present(preview: CsvMappingPreview): boolean;
}

/**
 * 默认呈现器：经 NavigationManager 推 ColumnMappingWizard 路由
 */
export class NavStackWizardPagePresenter implements WizardPagePresenter {
  present(preview: CsvMappingPreview): boolean {
    const stack = NavigationManager.getInstance().getNavPathStack();
    if (!stack) {
      return false;
    }
    stack.pushPathByName('ColumnMappingWizard', preview);
    return true;
  }
}

/**
 * 导入列映射交互桥（§4.3 交互桥）
 * handler 在 import() 内 await requestColumnMapping(preview) 挂起等待用户；
 * 向导页确认/取消后直接回调 notifyComplete/notifyCancelled（同进程同线程直连，
 * 不经 emitter —— 事件队列投递会序列化数据，类实例丢失原型导致 instanceof 收窄失效，
 * 曾致 Promise 永久挂起，见文档 §10.2 差异记录）；
 * 取消/页面销毁 reject(CANCELLED)，防止 Promise 永久挂起。
 * 无 UI 上下文时以 null resolve（调用方回落建议映射直导）。
 */
export class ImportWizardBridge {
  private static instance: ImportWizardBridge | null = null;

  private presenter: WizardPagePresenter = new NavStackWizardPagePresenter();
  private pending: boolean = false;
  private pendingPreview: CsvMappingPreview | null = null;
  private resolver: ((value: ColumnMappingProfile | null) => void) | null = null;
  private rejecter: ((error: ImportError) => void) | null = null;

  static getInstance(): ImportWizardBridge {
    if (ImportWizardBridge.instance === null) {
      ImportWizardBridge.instance = new ImportWizardBridge();
    }
    return ImportWizardBridge.instance;
  }

  /**
   * 注入自定义呈现器（测试用）
   */
  setPresenter(presenter: WizardPagePresenter): void {
    this.presenter = presenter;
  }

  /**
   * 恢复默认呈现器
   */
  resetPresenter(): void {
    this.presenter = new NavStackWizardPagePresenter();
  }

  /**
   * 当前挂起请求的预览数据（向导页 aboutToAppear 时取用）
   */
  getPendingPreview(): CsvMappingPreview | null {
    return this.pendingPreview;
  }

  /**
   * 请求列映射：推入向导页并挂起等待用户确认
   * @returns 用户确认的映射档案；无法呈现向导（无 UI 上下文）时返回 null
   * @throws ImportError 用户取消时抛出（CANCELLED）
   */
  requestColumnMapping(preview: CsvMappingPreview): Promise<ColumnMappingProfile | null> {
    return new Promise<ColumnMappingProfile | null>((resolve, reject) => {
      if (this.pending) {
        reject(new ImportError(
          ImportExportErrorCode.PARSE_ERROR,
          ResourceManager.getString($r('app.string.import_wizard_request_in_progress'))
        ));
        return;
      }
      if (!this.presenter.present(preview)) {
        resolve(null);
        return;
      }
      this.pending = true;
      this.pendingPreview = preview;
      this.resolver = resolve;
      this.rejecter = reject;
    });
  }

  /**
   * 向导页确认完成时回传档案（向导页直接调用，同线程同步 resolve）
   */
  notifyComplete(profile: ColumnMappingProfile): void {
    if (!this.pending) {
      return;
    }
    const resolver = this.resolver;
    this.cleanup();
    if (resolver !== null) {
      resolver(profile);
    }
  }

  /**
   * 向导页取消（用户点取消 / 返回键 / 页面销毁兜底）
   */
  notifyCancelled(): void {
    if (!this.pending) {
      return;
    }
    const rejecter = this.rejecter;
    this.cleanup();
    if (rejecter !== null) {
      rejecter(new ImportError(
        ImportExportErrorCode.CANCELLED,
        ResourceManager.getString($r('app.string.import_wizard_cancelled'))
      ));
    }
  }

  /**
   * 重置桥状态（测试用）
   */
  reset(): void {
    this.cleanup();
    this.resetPresenter();
  }

  /**
   * 由解析后的行构建向导预览（表头 + 采样行 + 建议映射 + 识别结果）
   */
  static buildPreview(rows: string[][], detectedFormatName: string): CsvMappingPreview {
    const headers = rows[0];
    const suggested = CsvColumnMappingEngine.buildSuggestedMapping(headers);
    const items: ColumnMappingItem[] = [];
    for (let i = 0; i < headers.length; i++) {
      let target = WizardTargetField.SKIP;
      for (const mapping of suggested) {
        if (mapping.columnIndex === i) {
          target = WizardTargetFieldConverter.fromCsvTargetField(mapping.target);
          break;
        }
      }
      items.push(new ColumnMappingItem(i, headers[i], target));
    }
    const sampleRows = rows.length > 1 ? rows.slice(1, 1 + PREVIEW_SAMPLE_ROW_LIMIT) : [];
    const totalRowEstimate = rows.length > 1 ? rows.length - 1 : 0;
    return new CsvMappingPreview(headers, sampleRows, items, detectedFormatName, totalRowEstimate);
  }

  private cleanup(): void {
    this.pending = false;
    this.pendingPreview = null;
    this.resolver = null;
    this.rejecter = null;
  }
}
