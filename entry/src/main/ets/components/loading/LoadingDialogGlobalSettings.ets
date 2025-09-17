export class LoadingDialogGlobalSettings {
  msg: ResourceStr = ''
  alignment: DialogAlignment = DialogAlignment.Bottom
  offset: Offset = { dx: 0, dy: 0 }
  tintColor: ResourceColor = $r('app.color.text_primary')
  textColor: ResourceColor = $r('app.color.text_primary')
  hideDelay: number = 2000
  fontSize: number | string | Resource = '16'
  backgroundColor: ResourceColor = $r("app.color.toast_bg")
  maskColor: ResourceColor = Color.Transparent
  borderRadius: Length | BorderRadiuses = 20
  transition: TransitionEffect | undefined = undefined
  successSrc: PixelMap | ResourceStr | DrawableDescriptor = $r('app.media.loading_success')
  failureSrc: PixelMap | ResourceStr | DrawableDescriptor = $r('app.media.loading_error')
  infoSrc: PixelMap | ResourceStr | DrawableDescriptor = $r('app.media.loading_info')
  warnSrc: PixelMap | ResourceStr | DrawableDescriptor = $r('app.media.loading_warn')
  hideOnTouchOutside: boolean = false
  hideOnSystemBack: boolean = false
  showInSubWindow: boolean = false
  isModal: boolean = false
}

export let loadingDialogGlobalSettings = new LoadingDialogGlobalSettings()