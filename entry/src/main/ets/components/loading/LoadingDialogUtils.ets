import { ResourceUtils } from '../../common/utils'
import { LoadingDialogGlobalSettings, loadingDialogGlobalSettings } from './LoadingDialogGlobalSettings'
import { LoadingSettings } from './LoadingSettings'
import { LoadingActionOptions, LoadingDialogBuilder, LoadingState } from './LoadingViews'
import { PromptActionUtils } from './PromptActionUtils'

export class LoadingDialogUtils {
  private timeoutMap: Map<string, number> = new Map();
  private loadingList: Array<ResourceStr | LoadingSettings> = [];

  /**
   * 设置全局默认参数
   */
  setGlobalSettings(configs: (settings: LoadingDialogGlobalSettings) => void): void {
    configs(loadingDialogGlobalSettings)
  }

  /**
   * 显示 loading hud
   * @param value 可不传
   */
  async showLoading(value: ResourceStr | LoadingSettings = ''): Promise<void> {
    this.loadingList.push(value);
    // 延时100ms，避免loading闪烁
    setTimeout(() => {
      const param = this.loadingList.pop();
      if (param) {
        let loading = new LoadingActionOptions(LoadingState.LOADING, param)
        if (PromptActionUtils.existsCustomDialog(LoadingState.LOADING)) {
          this.updateDialog(loading)
        } else {
          this.showDialog(loading)
        }
      }
    }, 100);
  }


  /**
   * 隐藏 hud
   */
  async hideLoading(): Promise<void> {
    if (this.loadingList.length > 0) {
      this.loadingList = [];
    }
    this.hide(LoadingState.LOADING).catch(() => {
      this.hideDialogDelay(LoadingState.LOADING, { hideDelay: 100 });
    })
  }


  /**
   * 显示 success hud
   * @param value 可不传
   */
  async showSuccess(value: ResourceStr | LoadingSettings = ''): Promise<void> {
    await this.showDialog(new LoadingActionOptions(LoadingState.SUCCESS, value))
    this.hideDialogDelay(LoadingState.SUCCESS, value)
  }

  /**
   * 显示 failure hud
   * @param value 可不传
   */
  async showError(value: ResourceStr | LoadingSettings = ''): Promise<void> {
    await this.showDialog(new LoadingActionOptions(LoadingState.ERROR, value))
    this.hideDialogDelay(LoadingState.ERROR, value)
  }

  /**
   * 显示 info hud
   * @param value 可不传
   */
  async showInfo(value: ResourceStr | LoadingSettings = ''): Promise<void> {
    await this.showDialog(new LoadingActionOptions(LoadingState.INFO, value))
    this.hideDialogDelay(LoadingState.INFO, value)
  }

  /**
   * 显示 warn hud
   * @param value
   */
  async showWarn(value: ResourceStr | LoadingSettings = ''): Promise<void> {
    await this.showDialog(new LoadingActionOptions(LoadingState.WARN, value))
    this.hideDialogDelay(LoadingState.WARN, value)
  }

  /**
   * 显示 toast hud
   * @param value
   */
  async showToast(value: ResourceStr | LoadingSettings = ''): Promise<void> {
    await this.showDialog(new LoadingActionOptions(LoadingState.TOAST, value))
    this.hideDialogDelay(LoadingState.TOAST, value)
  }

  /**
   * 显示 progress hud
   * @param value 可不传
   * @param progress 取值 0 ~ 100
   */
  async showProgress(value: ResourceStr | LoadingSettings = '', progress: number = 0): Promise<void> {
    let options = new LoadingActionOptions(LoadingState.PROGRESS, value, progress)
    if (PromptActionUtils.existsCustomDialog(LoadingState.PROGRESS)) {
      return this.updateDialog(options)
    } else {
      return await this.showDialog(options)
    }
  }

  /**
   * 隐藏 hud
   */
  async hide(dialogId?: string): Promise<void> {
    return PromptActionUtils.closeCustomDialog(dialogId)
  }

  /////////////////////////////////  privates  /////////////////////////////////
  private async showDialog(options: LoadingActionOptions): Promise<void> {
    let settings: LoadingSettings = ResourceUtils.isResourceStr(options.value) ? {} : options.value as LoadingSettings;
    if (options.dialogId == LoadingState.PROGRESS) {
      settings.transition = TransitionEffect.IDENTITY
    } else {
      await this.hide(options.dialogId);
    }
    return PromptActionUtils.openCustomDialog<LoadingActionOptions>({
      builder: wrapBuilder(LoadingDialogBuilder),
      params: options,
      options: settings
    })
  }

  private updateDialog(options: LoadingActionOptions): void {
    PromptActionUtils.updateCustomDialog<LoadingActionOptions>(options)
  }

  private hideDialogDelay(dialogId?: string, value: ResourceStr | LoadingSettings = ''): void {
    let hideDelay: number
    if (ResourceUtils.isResourceStr(value)) {
      hideDelay = loadingDialogGlobalSettings.hideDelay
    } else {
      hideDelay = (value as LoadingSettings).hideDelay ?? loadingDialogGlobalSettings.hideDelay
    }
    if (dialogId && this.timeoutMap.has(dialogId)) {
      clearTimeout(this.timeoutMap.get(dialogId));
      this.timeoutMap.delete(dialogId);
    }
    const timeout = setTimeout(() => {
      this.hide(dialogId);
    }, hideDelay);

    if (dialogId) {
      this.timeoutMap.set(dialogId, timeout);
    }
  }
}

let LoadingDialog = new LoadingDialogUtils()

export { LoadingSettings, LoadingState, LoadingDialog };