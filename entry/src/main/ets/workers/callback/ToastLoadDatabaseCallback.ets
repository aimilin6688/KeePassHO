import { ErrorEvent } from '@kit.ArkTS';
import { CommonUtils, ResourceManager, StringUtils } from '../../common/utils';
import { LoadingDialog, LoadingState } from '../../components/loading/LoadingDialogUtils';
import { LoadMessage, ProgressMessage, SuccessMessage } from '../WorkerParam';
import { KdbxLoadServiceCallback } from '../../services/kdbx/KdbxLoadService';

/**
 * 吐司加载回调（KdbxLoadServiceCallback 的公共默认实现）
 * 默认驱动统一 Loading/线性进度 HUD：阶段消息切加载弹框、传输进度切线性进度条、终态自动关闭并吐司；
 * 调用方通过 wrap 仅覆盖关心的方法（业务逻辑在默认行为之后执行），未覆盖的方法走默认行为。
 * 注意：接口方法必须为箭头函数属性——KdbxLoadService/DatabaseLoad 会以方法引用方式提取回调，
 * 普通方法脱钩后 this 为 undefined
 */
export class ToastLoadDatabaseCallback implements KdbxLoadServiceCallback {
  private call: KdbxLoadServiceCallback | undefined = undefined;
  /** 最近一次阶段文案（进度条前缀，onLoadMessage 持续刷新） */
  private lastStageText: string = '';
  /** 线性进度 HUD 是否在展示（切回阶段文案/终态时需关闭） */
  private progressVisible: boolean = false;

  constructor(callback?: KdbxLoadServiceCallback) {
    this.call = callback;
  }

  onLoadMessage = (message: LoadMessage): void => {
    // 阶段切换：关闭线性进度 HUD，回到阶段加载弹框
    this.hideProgress();
    this.lastStageText = ResourceManager.getMessage(message.message);
    LoadingDialog.showLoading(this.lastStageText);
    if (this.call && this.call.onLoadMessage) {
      this.call.onLoadMessage(message);
    }
  };

  onProgressMessage = (message: ProgressMessage): void => {
    // 首个进度事件：关闭阶段加载弹框，切换为线性进度条
    if (!this.progressVisible) {
      LoadingDialog.hideLoading();
      this.progressVisible = true;
    }
    LoadingDialog.showLinearProgress(this.buildProgressText(message), message.percent);
    if (this.call && this.call.onProgressMessage) {
      this.call.onProgressMessage(message);
    }
  };

  onSuccessMessage = (message: SuccessMessage): void => {
    // 终态：关闭全部 HUD（成功后的展示由调用方决定，不做默认吐司）
    this.hideAllDialogs();
    if (this.call && this.call.onSuccessMessage) {
      this.call.onSuccessMessage(message);
    }
  };

  onErrorMessage = (message: LoadMessage): void => {
    this.hideAllDialogs();
    CommonUtils.showToast(ResourceManager.getMessage(message.message));
    if (this.call && this.call.onErrorMessage) {
      this.call.onErrorMessage(message);
    }
  };

  onAllErrors = (err: ErrorEvent): void => {
    this.hideAllDialogs();
    CommonUtils.showToast(err.message);
    if (this.call && this.call.onAllErrors) {
      this.call.onAllErrors(err);
    }
  };

  onexit = (e: number): void => {
    // Worker 销毁兜底：之后不再有回调，确保 HUD 不悬挂
    this.hideAllDialogs();
    if (this.call && this.call.onexit) {
      this.call.onexit(e);
    }
  };

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
      });
    }
  }

  /**
   * 关闭全部加载 HUD（线性进度 + 阶段加载弹框）
   */
  private hideAllDialogs(): void {
    this.hideProgress();
    LoadingDialog.hideLoading();
  }

  static wrap(callback?: KdbxLoadServiceCallback): KdbxLoadServiceCallback {
    return new ToastLoadDatabaseCallback(callback);
  }
}
