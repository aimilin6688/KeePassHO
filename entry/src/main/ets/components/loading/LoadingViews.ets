import ResourceUtils from '../../common/utils/ResourceUtils'
import { loadingDialogGlobalSettings } from './LoadingDialogGlobalSettings'
import { LoadingSettings } from './LoadingSettings'
import { PromptActionBean } from './PromptActionUtils'

export enum LoadingState {
  LOADING = 'loading',
  SUCCESS = 'success',
  ERROR = 'error',
  INFO = 'info',
  WARN = 'warn',
  TOAST = 'toast',
  PROGRESS = 'progress',
}

export class LoadingActionOptions extends PromptActionBean {
  value: ResourceStr | LoadingSettings = ''
  progress: number = 0

  constructor(state: LoadingState, value: ResourceStr | LoadingSettings = '', progress: number = 0) {
    super(state)
    this.value = value
    this.progress = progress
  }
}

@Builder
export function LoadingDialogBuilder(options: LoadingActionOptions) {
  LoadingDialogView({
    value: options.value,
    state: options.dialogId as LoadingState,
    progress: options.progress
  })
}

@Component
struct LoadingDialogView {
  @Prop value: ResourceStr | LoadingSettings = ''
  @Prop state: LoadingState = LoadingState.LOADING
  @Prop progress: number = 0
  private msg: ResourceStr = ''
  private settings?: LoadingSettings
  private iconState: LoadingState[] = [LoadingState.LOADING, LoadingState.SUCCESS, LoadingState.ERROR, LoadingState.INFO, LoadingState.WARN, LoadingState.PROGRESS];

  aboutToAppear(): void {
    if (ResourceUtils.isResourceStr(this.value)) {
      this.msg = this.value as ResourceStr;
    } else {
      const setting = this.value as LoadingSettings;
      this.msg = setting.msg ?? loadingDialogGlobalSettings.msg
      this.settings = setting;
    }
  }

  build() {
    Column() {
      Row() {
        if (this.state == LoadingState.LOADING) {
          LoadingProgress()
            .color(this.settings?.tintColor ?? loadingDialogGlobalSettings.tintColor)
            .width(18)
            .height(18)
        } else if (this.state == LoadingState.SUCCESS) {
          Image(this.settings?.successSrc ?? loadingDialogGlobalSettings.successSrc)
            .fillColor(this.settings?.tintColor ?? loadingDialogGlobalSettings.tintColor)
            .width(16)
            .height(16)
        } else if (this.state == LoadingState.ERROR) {
          Image(this.settings?.failureSrc ?? loadingDialogGlobalSettings.failureSrc)
            .fillColor(this.settings?.tintColor ?? loadingDialogGlobalSettings.tintColor)
            .width(16)
            .height(16)
        } else if (this.state == LoadingState.INFO) {
          Image(this.settings?.infoSrc ?? loadingDialogGlobalSettings.infoSrc)
            .fillColor(this.settings?.tintColor ?? loadingDialogGlobalSettings.tintColor)
            .width(16)
            .height(16)
        } else if (this.state == LoadingState.WARN) {
          Image(this.settings?.warnSrc ?? loadingDialogGlobalSettings.warnSrc)
            .fillColor(this.settings?.tintColor ?? loadingDialogGlobalSettings.tintColor)
            .width(16)
            .height(16)
        } else if (this.state == LoadingState.PROGRESS) {
          Stack() {
            Progress({ value: this.progress, total: 100, type: ProgressType.Ring })
              .width('100%')
              .height('100%')
              .color(this.settings?.tintColor ?? loadingDialogGlobalSettings.tintColor)
              .backgroundColor(loadingDialogGlobalSettings.backgroundColor)
              .style({
                strokeWidth: 5,
                enableSmoothEffect: false,
              })

            Text(`${this.progress}%`)
              .width('100%')
              .height('100%')
              .fontSize('14fp')
              .fontColor(this.settings?.tintColor ?? loadingDialogGlobalSettings.tintColor)
              .textAlign(TextAlign.Center)
          }
          .width(48)
          .height(48)
        }

        if (this.msg != '') {
          if(this.iconState.includes(this.state)){
            Blank().width(10);
          }
          Text(this.msg)
            .fontColor(this.settings?.textColor ?? loadingDialogGlobalSettings.textColor)
            .fontSize(this.settings?.fontSize ?? loadingDialogGlobalSettings.fontSize)
        }
      }
      .padding({
        left: 16,
        right: 16,
        top: 10,
        bottom: 10
      })
      .margin({bottom: '16%'})
      .backgroundColor(this.settings?.backgroundColor ?? loadingDialogGlobalSettings.backgroundColor)
      .borderRadius(this.settings?.borderRadius ?? loadingDialogGlobalSettings.borderRadius)
      .shadow(ShadowStyle.OUTER_DEFAULT_MD)
    }
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}
