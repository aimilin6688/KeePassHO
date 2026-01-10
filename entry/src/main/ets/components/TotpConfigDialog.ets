/**
 * TOTP配置弹框组件
 * 支持RFC6238令牌、Steam令牌、用户自定义令牌，与扫码方式生成
 */
import { TotpAlgorithm, TotpConfig, TotpService, TotpType } from '../services/TotpService';
import { ScanService } from '../services/ScanService';
import { TotpPreviewComponent, TotpPreviewController } from './TotpPreviewComponent';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ResourceManager } from '../common/utils';

const DOMAIN = 0x0000;
const TAG = 'TotpService';

@CustomDialog
export struct TotpConfigDialog {
  @State totpConfig: TotpConfig = {
    type: TotpType.RFC6238,
    secret: '',
    algorithm: TotpAlgorithm.SHA1,
    digits: 6,
    period: 30,
    name: '',
    issuer: ''
  };
  @State name: string = '';
  @State issuer: string = '';
  @State fieldName: string = 'otp';
  @State showFieldName: boolean = false;
  @State private selectedType: string = TotpType.RFC6238;
  @State private selectedAlgorithm: string = TotpAlgorithm.SHA1;
  @State private errorMessage: string = '';
  @State private showMarkOptions: boolean = false;
  // 确认前校验字段名称是否存在
  public checkFieldName: (fieldName: string) => boolean = () => {
    return false;
  };
  // 确认事件回调
  public onConfirm: (fieldName: string, otpUrl: string) => void = () => {
  };
  private tokenTypeOptions: Array<TokenTypeOption> = [
    { type: TotpType.RFC6238, value: $r('app.string.totp_type_rfc6238') },
    { type: TotpType.STEAM, value: $r('app.string.totp_type_steam') },
    { type: TotpType.CUSTOM, value: $r('app.string.totp_type_custom') },
  ];
  private controller: CustomDialogController;
  private totpService: TotpService = TotpService.getInstance();
  private scanService: ScanService = new ScanService(this.getUIContext());
  private previewController: TotpPreviewController = new TotpPreviewController();

  aboutToAppear() {
    this.totpConfig.name = this.name;
    this.totpConfig.issuer = this.issuer;
  }

  /**
   * 生成随机密钥
   */
  private async generateRandomSecret() {
    try {
      const secret = await this.totpService.generateRandomSecret();
      this.totpConfig.secret = secret;
      this.previewController.updatedToken();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Generate random secret error: ${error.message}')
      this.errorMessage = error.message;
    }
  }

  /**
   * 扫描二维码
   */
  private async scanQrCode() {
    try {
      const result = await this.scanService.scanTotpQrCode();

      if (result.success && result.content) {
        const config = this.totpService.parseUri(result.content);
        if (config) {
          this.totpConfig = config;
          this.selectedType = config.type;
          this.selectedAlgorithm = config.algorithm || TotpAlgorithm.SHA1;
          this.errorMessage = '';
          this.previewController.updatedToken();
        } else {
          this.errorMessage = ResourceManager.getString($r('app.string.totp_config_error_invalid_qr_code'));
        }
      } else {
        this.errorMessage = result.error || ResourceManager.getString($r('app.string.error_scan_qr_code'));
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Scan Qr Code error: ${error.message}')
      this.errorMessage = error.message;
    }
  }

  /**
   * 更新TOTP配置
   */
  private updateTotpConfig() {
    // 根据选择的类型更新配置
    this.totpConfig.type = this.selectedType as TotpType;

    // 如果是Steam令牌，设置固定参数
    if (this.totpConfig.type === TotpType.STEAM) {
      this.totpConfig.algorithm = TotpAlgorithm.SHA1;
      this.totpConfig.digits = 5;
    } else {
      // 对于其他类型，使用选择的算法
      this.totpConfig.algorithm = this.selectedAlgorithm as TotpAlgorithm;
    }
  }

  /**
   * 获取算法在选择器中的索引
   */
  private getAlgorithmIndex(): number {
    switch (this.selectedAlgorithm) {
      case TotpAlgorithm.SHA256:
        return 1;
      case TotpAlgorithm.SHA512:
        return 2;
      case TotpAlgorithm.SHA1:
      default:
        return 0;
    }
  }

  /**
   * 验证配置是否有效
   */
  private validateConfig(): boolean {
    // 检查密钥是否为空
    if (!this.totpConfig.secret) {
      this.errorMessage = ResourceManager.getString($r('app.string.totp_config_error_empty_secret'));
      return false;
    }
    return true;
  }

  /**
   * 关闭弹框
   */
  private close() {
    this.controller.close();
  }

  /**
   * 确定事件处理
   */
  private handlerConfirm() {
    if (this.validateConfig()) {
      if (this.checkFieldName(this.fieldName)) {
        this.errorMessage = ResourceManager.getString($r("app.string.field_name_exists"));
        this.showFieldName = true;
        return;
      }
      const optUrl = TotpService.getInstance().generateUri(this.totpConfig);
      this.controller.close();
      this.onConfirm(this.fieldName, optUrl);
    }
  }

  build() {
    Column() {
      // 顶部标题栏
      Row() {
        Text($r('app.string.totp_config_title'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
        Blank()
        Button() {
          Image($r('sys.media.ohos_ic_public_cancel_filled'))
            .width(24)
            .height(24)
            .fillColor($r('app.color.text_primary'))
        }
        .type(ButtonType.Circle)
        .backgroundColor('transparent')
        .onClick(() => {
          this.close();
        })
      }
      .width('100%')
      .height(56)
      .alignItems(VerticalAlign.Center)
      .borderRadius({ topLeft: 16, topRight: 16 })


      List() {
        // 字段名称
        if (this.showFieldName) {
          ListItemGroup() {
            ListItem() {
              Column() {
                Row() {
                  Text("*").fontColor($r('app.color.required'))
                  Text($r('app.string.custom_field_name')).fontSize(16).fontWeight(FontWeight.Medium)
                  Blank()
                  TextInput({ text: this.fieldName })
                    .height(40)
                    .fontSize(14)
                    .width("75%")
                    .onChange((value: string) => {
                      this.fieldName = value;
                    })
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
              }
              .padding({ left: 12, right: 12 })
              .width('100%')
            }
          }.backgroundColor($r("app.color.card_bg"))
          .margin({ top: 12, bottom: 12 })
          .borderRadius(12)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
          })
        }

        // 令牌字段
        ListItemGroup() {
          // 令牌类型
          ListItem() {
            Row() {
              Text($r("app.string.totp_type"))
                .fontSize(16)
                .flexGrow(1)
              Blank()
              Select(this.tokenTypeOptions)
                .value(this.tokenTypeOptions[this.tokenTypeOptions.findIndex((item) => item.type === this.selectedType)].value)
                .font({ size: 16 })
                .selectedOptionFont({ size: 16 })
                .optionFont({ size: 16 })
                .backgroundColor($r("app.color.card_bg"))
                .onSelect(async (index: number) => {
                  this.selectedType = this.tokenTypeOptions[index].type;
                  this.updateTotpConfig();
                })
            }
            .padding({ left: 12, right: 12 })
            .width('100%')
            .height(48)
          }

          // 令牌字段
          ListItem() {
            // 密钥
            Column() {
              Row() {
                Text("*").fontColor($r('app.color.required'))
                Text($r("app.string.totp_secret")).fontSize(16).fontWeight(FontWeight.Medium)
                Blank()
                // 生成
                Button($r("app.string.generate_button_text"), { type: ButtonType.Normal, stateEffect: true })
                  .fontSize(14)
                  .height(28)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r("app.color.bg_primary"))
                  .padding({ left: 12, right: 12 })
                  .margin({ right: 3 })
                  .borderRadius(12)
                  .onClick(() => this.generateRandomSecret())
                // 扫码
                Button($r("app.string.scan_qr_code"), { type: ButtonType.Normal, stateEffect: true })
                  .fontSize(14)
                  .height(28)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r("app.color.bg_primary"))
                  .padding({ left: 12, right: 12 })
                  .borderRadius(12)
                  .onClick(() => this.scanQrCode())
              }
              .width('100%')
              .padding({ top: 10, bottom: 5 })
              .margin({ bottom: 5 })

              TextInput({ text: this.totpConfig.secret })
                .height(40)
                .fontSize(14)
                .onChange((value: string) => {
                  this.totpConfig.secret = value.toUpperCase();
                })
            }
            .padding({ left: 12, right: 12, bottom: 5 })
            .width('100%')
          }

          // 算法选择（仅对RFC6238和自定义令牌有效）
          if (this.selectedType !== TotpType.STEAM) {
            // Hash算法
            ListItem() {
              Column() {
                Row() {
                  Text($r('app.string.totp_algorithm')).fontSize(16).fontWeight(FontWeight.Medium)
                  Blank()
                  Select([
                    { value: TotpAlgorithm.SHA1 },
                    { value: TotpAlgorithm.SHA256 },
                    { value: TotpAlgorithm.SHA512 }
                  ])
                    .selected(this.getAlgorithmIndex())
                    .value(this.selectedAlgorithm)
                    .font({ size: 14 })
                    .onSelect((index: number, value: string) => {
                      this.selectedAlgorithm = value as TotpAlgorithm;
                      this.updateTotpConfig();
                    })
                }
                .width('100%')
              }
              .padding({
                left: 12,
                right: 12,
                top: 10,
                bottom: 10
              })
              .width('100%')
            }
          }
          // 位数选择（仅对RFC6238和自定义令牌有效）
          if (this.selectedType !== TotpType.STEAM) {
            // 令牌位数
            ListItem() {
              Column() {
                Row() {
                  Text($r("app.string.totp_token_digits")).fontSize(16).fontWeight(FontWeight.Medium)
                  Blank()
                  Counter() {
                    Text(`${this.totpConfig.digits}`).fontSize(14)
                  }
                  .onInc(() => {
                    if (this.totpConfig.digits && this.totpConfig.digits < 10) {
                      this.totpConfig.digits++;
                    }
                  })
                  .onDec(() => {
                    if (this.totpConfig.digits && this.totpConfig.digits > 6) {
                      this.totpConfig.digits--;
                    }
                  })
                }
                .width('100%')
              }
              .padding({
                left: 12,
                right: 12,
                top: 10,
                bottom: 10
              })
              .width('100%')
            }
          }
          // 更新周期（秒）
          ListItem() {
            // 周期选择
            Column() {
              Row() {
                Text($r('app.string.totp_token_period')).fontSize(16).fontWeight(FontWeight.Medium)
                Blank()
                Counter() {
                  Text(`${this.totpConfig.period}`)
                    .fontSize(14)
                }
                .onInc(() => {
                  if (this.totpConfig.period && this.totpConfig.period < 60) {
                    this.totpConfig.period += 5;
                  }
                })
                .onDec(() => {
                  if (this.totpConfig.period && this.totpConfig.period > 15) {
                    this.totpConfig.period -= 5;
                  }
                })
              }
              .width('100%')
            }
            .padding({
              left: 12,
              right: 12,
              top: 10,
              bottom: 10
            })
            .width('100%')
          }
        }
        .backgroundColor($r("app.color.card_bg"))
        .margin({ bottom: 12 })
        .borderRadius(12)
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
        })


        // 标识信息（可折叠）
        ListItemGroup() {
          ListItem() {
            Column() {
              Row() {
                Text($r('app.string.totp_mark')).fontSize(16).fontWeight(FontWeight.Medium)
                Blank()
                Image(this.showMarkOptions ? $r('app.media.ic_angle_up') : $r('app.media.ic_angle_down'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .padding({ top: 10, bottom: 10 })
              .onClick(() => {
                this.showMarkOptions = !this.showMarkOptions;
              })
            }
            .padding({ left: 12, right: 12 })
            .width('100%')
          }

          // 标识信息
          if (this.showMarkOptions) {
            // 名称
            ListItem() {
              Column() {
                Row() {
                  Text($r('app.string.totp_name')).fontSize(16).fontWeight(FontWeight.Medium)
                  Blank()
                  TextInput({ text: this.totpConfig.name })
                    .height(40)
                    .fontSize(14)
                    .width("75%")
                    .onChange((value: string) => {
                      this.totpConfig.name = value;
                    })
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
              }
              .padding({ left: 12, right: 12 })
              .width('100%')
            }

            // 发行者
            ListItem() {
              Column() {
                Row() {
                  Text($r('app.string.issuer')).fontSize(16).fontWeight(FontWeight.Medium)
                  Blank()
                  TextInput({ text: this.totpConfig.issuer })
                    .height(40)
                    .fontSize(14)
                    .width("75%")
                    .onChange((value: string) => {
                      this.totpConfig.issuer = value;
                    })
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
              }
              .padding({ left: 12, right: 12 })
              .width('100%')
            }
          }
        }
        .backgroundColor($r("app.color.card_bg"))
        .margin({ bottom: 12 })
        .borderRadius(12)
        .divider({
          strokeWidth: 1,
          color: $r('app.color.divider'),
        })

        // 令牌预览
        if (this.totpConfig.secret) {
          ListItemGroup() {
            ListItem() {
              Column() {
                Row() {
                  Text($r('app.string.totp_preview')).fontSize(16).fontWeight(FontWeight.Medium)
                  Blank()
                  TotpPreviewComponent({ controller: this.previewController, totpConfig: this.totpConfig })
                }
                .width('100%')
                .padding({ top: 10, bottom: 10 })
              }
              .padding({ left: 12, right: 12 })
              .width('100%')
            }
          }
          .backgroundColor($r("app.color.card_bg"))
          .margin({ bottom: 12 })
          .borderRadius(12)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
          })
        }

        // 错误消息（如果有）
        if (this.errorMessage) {
          ListItemGroup() {
            ListItem() {
              Text(this.errorMessage)
                .fontSize(14)
                .fontColor(Color.Red)
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ bottom: 10 })
            }
          }
        }
        ListItemGroup() {
          ListItem() {
            // 底部按钮
            Row() {
              Button($r('app.string.cancel_button_text'))
                .width('48%')
                .height(40)
                .fontSize(16)
                .backgroundColor(Color.Gray)
                .fontColor($r('app.color.button_text'))
                .onClick(() => {
                  this.controller.close();
                })

              Button($r('app.string.confirm_button_text'))
                .width('48%')
                .height(40)
                .fontSize(16)
                .fontColor($r('app.color.button_text'))
                .backgroundColor($r("app.color.button_bg_blue"))
                .onClick(() => {
                  this.handlerConfirm();
                })
            }
            .width('100%')
            .justifyContent(FlexAlign.SpaceBetween)
          }
          .padding({ top: 16 })
        }
      }
      .width('100%')
      .height('auto')
    }
    .width('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .borderRadius(16)
    .padding({ left: 16, right: 16, bottom: 16 })
    .shadow(ShadowStyle.OUTER_DEFAULT_MD)
  }
}

export interface TokenTypeOption {
  type: TotpType;
  value: ResourceStr;
}