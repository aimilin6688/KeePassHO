import { ComponentContent, promptAction } from '@kit.ArkUI'
import { JSON, util } from '@kit.ArkTS'
import { LoadingSettings } from './LoadingSettings'
import { loadingDialogGlobalSettings } from './LoadingDialogGlobalSettings'
import { common } from '@kit.AbilityKit'

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
  componentContent: ComponentContent<object>
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
      const uiContext = CommonUtils.getUiContext();
      const promptAction = uiContext.getPromptAction()
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
        onWillDismiss: (action: DismissDialogAction) => {
          if (action.reason == DismissReason.PRESS_BACK && hideOnSystemBack) {
            action.dismiss()
          } else if (action.reason == DismissReason.TOUCH_OUTSIDE && hideOnTouchOutside) {
            action.dismiss()
          }
        },
        onWillDisappear: () => {
          const index = promptActionInfos.findIndex(item => item.dialogId == value.params.dialogId)
          if (index >= 0) {
            promptActionInfos.splice(index, 1)
          }
        }
      }

      if (!PromptActionUtils.existsCustomDialog(value.params.dialogId)) {
        promptActionInfos.push({
          dialogId: value.params.dialogId,
          componentContent: componentContent
        })
        return promptAction.openCustomDialog(componentContent, options);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, ` openCustomDialog error = ${JSON.stringify(error)}`)
    }
  }

  /**
   * 关闭自定义弹窗
   */
  static async closeCustomDialog(dialogId?: string): Promise<void> {
    try {
      const promptAction = CommonUtils.getUiContext().getPromptAction();
      let info: PromptActionInfo | undefined = undefined
      if (dialogId) {
        info = getPromptActionInfoByDialogId(dialogId)
      } else {
        info = promptActionInfos.length > 0 ? promptActionInfos[0] : undefined
      }
      if (info) {
        return promptAction.closeCustomDialog(info.componentContent)
      } else {
        hilog.debug(DOMAIN, TAG, ` closeCustomDialog error = info is undefined`)
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, ` closeCustomDialog error = ${JSON.stringify(error)}`)
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
}