import { ComponentContent, promptAction } from '@kit.ArkUI'
import { JSON, util } from '@kit.ArkTS'
import { LoadingSettings } from './LoadingSettings'
import { loadingDialogGlobalSettings } from './LoadingDialogGlobalSettings'

import { hilog } from '@kit.PerformanceAnalysisKit'
import { CommonUtils } from '../../common/utils/CommonUtils'

const DOMAIN = 0x0000;
const TAG = 'PromptActionUtils';

export interface PromptActionOptions<T extends PromptActionBean> {
  builder: WrappedBuilder<[T]>
  params: T,
  options?: LoadingSettings
}

export abstract class PromptActionBean {
  dialogId: string

  constructor(dialogId: string = '') {
    if (dialogId === '') {
      dialogId = util.generateRandomUUID()
    }
    this.dialogId = dialogId
  }
}

interface PromptActionInfo {
  dialogId: string
  componentContent: ComponentContent<object>,
  dialogController: promptAction.DialogController
  openPromise: Promise<void>
}

let promptActionInfos: PromptActionInfo[] = [];

function getPromptActionInfoByDialogId(dialogId: string): PromptActionInfo | undefined {
  return promptActionInfos.find(item => dialogId == item.dialogId)
}

export class PromptActionUtils {
  /**
   * 弹出自定义弹窗
   */
  static async openCustomDialog<T extends PromptActionBean>(value: PromptActionOptions<T>): Promise<void> {
    try {
      if (PromptActionUtils.existsCustomDialog(value.params.dialogId)) {
        return;
      }
      const uiContext = CommonUtils.getUiContext();
      const uiPromptAction = uiContext.getPromptAction()
      const componentContent = new ComponentContent(uiContext, value.builder, value.params)

      let hideOnSystemBack = value.options?.hideOnSystemBack ?? loadingDialogGlobalSettings.hideOnSystemBack
      let hideOnTouchOutside = value.options?.hideOnTouchOutside ?? loadingDialogGlobalSettings.hideOnTouchOutside
      let options: promptAction.BaseDialogOptions = {
        alignment: value.options?.alignment ?? loadingDialogGlobalSettings.alignment,
        autoCancel: true,
        maskColor: value.options?.maskColor ?? loadingDialogGlobalSettings.maskColor,
        offset: value.options?.offset ?? loadingDialogGlobalSettings.offset,
        transition: value.options?.transition ?? loadingDialogGlobalSettings.transition,
        showInSubWindow: value.options?.showInSubWindow ?? loadingDialogGlobalSettings.showInSubWindow,
        keyboardAvoidMode: value.options?.keyboardAvoidMode ?? loadingDialogGlobalSettings.keyboardAvoidMode,
        isModal: value.options?.isModal ?? loadingDialogGlobalSettings.isModal,
        focusable: false,
        onWillDismiss: (action: DismissDialogAction) => {
          if (action.reason == DismissReason.PRESS_BACK && hideOnSystemBack) {
            action.dismiss()
          } else if (action.reason == DismissReason.TOUCH_OUTSIDE && hideOnTouchOutside) {
            action.dismiss()
          }
        },
        onWillDisappear: () => {
          PromptActionUtils.removeDialogInfo(value.params.dialogId);
        }
      }
      const dialogController = new promptAction.DialogController();
      // 打开完成 promise 随信息登记：closeCustomDialog 需等待其完成，防 close 先于 open 到达的竞态
      const openPromise: Promise<void> = uiPromptAction.openCustomDialogWithController(componentContent, dialogController, options).catch((error: Error) => {
        hilog.error(DOMAIN, TAG, ` openCustomDialog dialogId: ${value.params.dialogId}, error = ${JSON.stringify(error)}`);
        PromptActionUtils.removeDialogInfo(value.params.dialogId);
        return Promise.reject(error);
      });
      promptActionInfos.push({
        dialogId: value.params.dialogId,
        componentContent: componentContent,
        dialogController: dialogController,
        openPromise: openPromise
      })
      return openPromise;
    } catch (error) {
      hilog.error(DOMAIN, TAG, ` openCustomDialog dialogId: ${value.params.dialogId}, error = ${JSON.stringify(error)}`)
      return Promise.reject(error);
    }
  }

  /**
   * 关闭自定义弹窗
   */
  static async closeCustomDialog(dialogId?: string): Promise<void> {
    try {
      hilog.debug(DOMAIN, TAG, `closeCustomDialog dialogId = ${dialogId}`);
      const promptAction = CommonUtils.getUiContext().getPromptAction();
      let info: PromptActionInfo | undefined = undefined
      if (dialogId) {
        info = getPromptActionInfoByDialogId(dialogId)
      } else {
        info = promptActionInfos.length > 0 ? promptActionInfos[promptActionInfos.length - 1] : undefined
      }
      if (!info) {
        hilog.debug(DOMAIN, TAG, `closeCustomDialog ${dialogId} is not found`);
        return;
      }
      // 等待打开完成后再关闭：快任务（小文件下载）中 close 可能先于 open 完成到达，
      // 双通道 close 均会失败且异常被上层吞掉，弹窗随后完成打开将永久悬挂
      await info.openPromise.catch(() => {});
      // 通过控制器关闭弹窗
      try {
        info.dialogController.close();
      } catch (error) {
        hilog.info(DOMAIN, TAG, `closeCustomDialog use dialogController close error, dialogId: ${dialogId}, error = ${JSON.stringify(error)}`);
      }

      // 通过组件内容关闭弹窗
      return await promptAction.closeCustomDialog(info.componentContent);
    } catch (error) {
      hilog.info(DOMAIN, TAG, `closeCustomDialog dialogId: ${dialogId}, error = ${JSON.stringify(error)}`);
      return Promise.reject(error);
    }
  }

  /**
   * 刷新自定义弹窗
   */
  static updateCustomDialog<T extends PromptActionBean>(params: T) {
    let promptActionInfo: PromptActionInfo | undefined = getPromptActionInfoByDialogId(params.dialogId)
    if (promptActionInfo) {
      promptActionInfo.componentContent.update(params)
    }
  }

  /**
   * 是否存在自定义弹窗
   */
  static existsCustomDialog(dialogId: string): boolean {
    let info = getPromptActionInfoByDialogId(dialogId)
    return info != undefined
  }

  /**
   * 移除弹窗信息
   */
  private static removeDialogInfo(dialogId?: string) {
    if (!dialogId) {
      return;
    }
    const index = promptActionInfos.findIndex(item => item.dialogId == dialogId)
    if (index >= 0) {
      promptActionInfos.splice(index, 1)
    }
  }
}