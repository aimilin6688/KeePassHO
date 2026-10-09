import { CommonUtils, StringUtils } from '../../common/utils';
import { LoadingDialog, LoadingState } from '../../components/loading/LoadingDialogUtils';
import { ProgressMessage, SuccessMessage } from '../WorkerParam';
import { SaveDatabaseCallback } from './SaveDatabaseCallback';

/**
 * 吐司消息回调
 * 上传过程中收到进度消息时切换为线性进度 HUD，阶段文案/终态自动切回
 */
export class ToastSaveDatabaseCallback implements SaveDatabaseCallback {
  private call: SaveDatabaseCallback | undefined = undefined;
  /** 最近一次阶段文案（进度条前缀，onMessage 持续刷新） */
  private lastStageText: string = '';
  /** 线性进度 HUD 是否在展示（切回阶段文案/终态时需关闭） */
  private progressVisible: boolean = false;

  constructor(callback?: SaveDatabaseCallback) {
    this.call = callback;
  }

  onSuccess(message: SuccessMessage): void {
    this.hideProgress();
    LoadingDialog.hideLoading();
    CommonUtils.showToast($r("app.string.save_success"));
    if (this.call && this.call.onSuccess) {
      this.call.onSuccess(message);
    }
  }

  onError(message: string): void {
    this.hideProgress();
    LoadingDialog.hideLoading();
    CommonUtils.showToast(message);
    if (this.call && this.call.onError) {
      this.call.onError(message);
    }
  }

  onMessage(message: string): void {
    // 阶段切换：关闭线性进度 HUD，回到阶段加载弹框
    this.hideProgress();
    this.lastStageText = message;
    LoadingDialog.showLoading(message);
    if (this.call && this.call.onMessage) {
      this.call.onMessage(message);
    }
  }

  onProgress(message: ProgressMessage): void {
    // 首个进度事件：关闭阶段加载弹框，切换为线性进度条
    if (!this.progressVisible) {
      LoadingDialog.hideLoading();
      this.progressVisible = true;
    }
    LoadingDialog.showLinearProgress(this.buildProgressText(message), message.percent);
    if (this.call && this.call.onProgress) {
      this.call.onProgress(message);
    }
  }

  /**
   * 组合进度文案：阶段文案 + 字节明细（尺寸未知时仅阶段文案）
   * @param message 进度消息
   */
  private buildProgressText(message: ProgressMessage): string {
    if (message.totalBytes <= 0) {
      return this.lastStageText;
    }
    return `${this.lastStageText} ${StringUtils.formatFileSize(message.transferredBytes)} / ${StringUtils.formatFileSize(message.totalBytes)}`;
  }

  /**
   * 关闭线性进度 HUD（未展示时无操作）
   */
  private hideProgress(): void {
    if (this.progressVisible) {
      this.progressVisible = false;
      LoadingDialog.hide(LoadingState.LINEAR_PROGRESS).catch(() => {
        // 关闭失败兜底：延迟重试（对齐 hideLoading 的失败重试语义）
        setTimeout(() => {
          LoadingDialog.hide(LoadingState.LINEAR_PROGRESS).catch(() => {});
        }, 100);
      });
    }
  }

  static wrap(callback?: SaveDatabaseCallback): SaveDatabaseCallback {
    return new ToastSaveDatabaseCallback(callback);
  }
}
