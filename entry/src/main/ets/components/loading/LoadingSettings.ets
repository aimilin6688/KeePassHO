export interface LoadingSettings {
  /**
   * msg default is ''
   */
  msg?: ResourceStr
  /**
   * alignment default is center
   */
  alignment?: DialogAlignment
  /**
   * offset default is （0，0）
   */
  offset?: Offset
  /**
   * tintColor, image & LoadingProgress color, default is white
   */
  tintColor?: ResourceColor
  /**
   * textColor default is white
   */
  textColor?: ResourceColor
  /**
   * hideDelay default is 2000 ms
   */
  hideDelay?: number
  /**
   * fontSize default is 16fp
   */
  fontSize?: number | string | Resource
  /**
   * backgroundColor default is #cc000000
   */
  backgroundColor?: ResourceColor
  /**
   * maskColor default is Transparent
   */
  maskColor?: ResourceColor
  /**
   * borderRadius default is 10
   */
  borderRadius?: Length | BorderRadiuses
  /**
   * transition default is undefined
   */
  transition?: TransitionEffect
  /**
   * success image 最好是svg格式
   */
  successSrc?: PixelMap | ResourceStr | DrawableDescriptor
  /**
   * failure image 最好是svg格式
   */
  failureSrc?: PixelMap | ResourceStr | DrawableDescriptor
  /**
   * info image 最好是svg格式
   */
  infoSrc?: PixelMap | ResourceStr | DrawableDescriptor
  /**
   * warn image 最好是svg格式
   */
  warnSrc?: PixelMap | ResourceStr | DrawableDescriptor
  /**
   * 点击弹框外部是否隐藏hud 默认是false
   */
  hideOnTouchOutside?: boolean
  /**
   * 系统返回时是否隐藏hud 默认是false
   */
  hideOnSystemBack?: boolean
  /**
   * 是否显示在subWindow之上 默认是false
   */
  showInSubWindow?: boolean
  /**
   * 是否是模态窗口，模态窗口有蒙层，非模态窗口无蒙层， 默认是 true
   */
  isModal?: boolean,

  /**
   * 键盘弹起时，弹窗是否自动上移，默认是true
   */
  keyboardAvoidMode?: KeyboardAvoidMode
}