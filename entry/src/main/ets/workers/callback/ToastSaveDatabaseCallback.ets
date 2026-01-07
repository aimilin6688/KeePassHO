import { CommonUtils } from '../../common/utils/CommonUtils';
import { LoadingDialog } from '../../components/loading/LoadingDialogUtils';
import { SuccessMessage } from '../WorkerParam';
import { SaveDatabaseCallback } from './SaveDatabaseCallback';

/**
 * 吐司消息回调
 */
export class ToastSaveDatabaseCallback implements SaveDatabaseCallback {
  private call: SaveDatabaseCallback | undefined = undefined;

  constructor(callback?: SaveDatabaseCallback) {
    this.call = callback;
  }

  onSuccess(message: SuccessMessage): void {
    LoadingDialog.hideLoading();
    CommonUtils.showToast($r("app.string.save_success"));
    if (this.call && this.call.onSuccess) {
      this.call.onSuccess(message);
    }
  }

  onError(message: string): void {
    LoadingDialog.hideLoading();
    CommonUtils.showToast(message);
    if (this.call && this.call.onError) {
      this.call.onError(message);
    }
  }

  onMessage(message: string): void {
    LoadingDialog.showLoading(message);
    if (this.call && this.call.onMessage) {
      this.call.onMessage(message);
    }
  }

  static wrap(callback?: SaveDatabaseCallback): SaveDatabaseCallback {
    return new ToastSaveDatabaseCallback(callback);
  }
}