/**
 * TOTP配置弹框组件
 * 支持RFC6238令牌、Steam令牌、用户自定义令牌，与扫码方式生成
 */
import { TotpAlgorithm, TotpConfig, TotpService, TotpType } from '../services/TotpService';
import { ScanService } from '../services/ScanService';
import { TotpPreviewComponent } from './TotpPreviewComponent';

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
  @State private selectedType: string = TotpType.RFC6238;
  @State private selectedAlgorithm: string = TotpAlgorithm.SHA1;
  @State private errorMessage: string = '';
  @State private showAdvancedOptions: boolean = false;

  private controller: CustomDialogController;
  private confirm: (config: TotpConfig) => void = () => {};
  private cancel: () => void = () => {};
  private totpService: TotpService = TotpService.getInstance();
  private scanService: ScanService = new ScanService(this.getUIContext());

  build() {
    Column() {
      // 标题
      Text('TOTP令牌配置')
        .fontSize(20)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 10, bottom: 20 })

      // 错误消息（如果有）
      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor(Color.Red)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 10 })
      }

      // 令牌类型选择
      Column() {
        Text('令牌类型')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 5 })

        Row() {
          Radio({ value: TotpType.RFC6238, group: 'tokenType' })
            .checked(this.selectedType === TotpType.RFC6238)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.selectedType = TotpType.RFC6238;
                this.updateTotpConfig();
              }
            })
          Text('RFC6238标准令牌').fontSize(14).margin({ left: 5 })
        }
        .width('100%')
        .margin({ bottom: 5 })

        Row() {
          Radio({ value: TotpType.STEAM, group: 'tokenType' })
            .checked(this.selectedType === TotpType.STEAM)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.selectedType = TotpType.STEAM;
                this.updateTotpConfig();
              }
            })
          Text('Steam令牌').fontSize(14).margin({ left: 5 })
        }
        .width('100%')
        .margin({ bottom: 5 })

        Row() {
          Radio({ value: TotpType.CUSTOM, group: 'tokenType' })
            .checked(this.selectedType === TotpType.CUSTOM)
            .onChange((isChecked: boolean) => {
              if (isChecked) {
                this.selectedType = TotpType.CUSTOM;
                this.updateTotpConfig();
              }
            })
          Text('自定义令牌').fontSize(14).margin({ left: 5 })
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
      .margin({ bottom: 15 })

      // 密钥输入
      Column() {
        Row() {
          Text('密钥').fontSize(16).fontWeight(FontWeight.Medium)
          Blank()
          Button('生成', { type: ButtonType.Normal, stateEffect: true })
            .height(28)
            .fontSize(14)
            .onClick(() => this.generateRandomSecret())
          Button('扫码', { type: ButtonType.Normal, stateEffect: true })
            .height(28)
            .fontSize(14)
            .margin({ left: 8 })
            .onClick(() => this.scanQrCode())
        }
        .width('100%')
        .margin({ bottom: 5 })

        TextInput({ text: this.totpConfig.secret })
          .height(40)
          .fontSize(14)
          .onChange((value: string) => {
            this.totpConfig.secret = value.toUpperCase();
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
      .margin({ bottom: 15 })

      // 名称和发行者
      Column() {
        Text('标识信息')
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 5 })

        Text('名称').fontSize(14).alignSelf(ItemAlign.Start)
        TextInput({ text: this.totpConfig.name })
          .height(40)
          .fontSize(14)
          .margin({ bottom: 10 })
          .onChange((value: string) => {
            this.totpConfig.name = value;
          })

        Text('发行者').fontSize(14).alignSelf(ItemAlign.Start)
        TextInput({ text: this.totpConfig.issuer })
          .height(40)
          .fontSize(14)
          .onChange((value: string) => {
            this.totpConfig.issuer = value;
          })
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
      .margin({ bottom: 15 })

      // 高级选项（可折叠）
      Column() {
        Row() {
          Text('高级选项')
            .fontSize(16)
            .fontWeight(FontWeight.Medium)
          Blank()
          Image(this.showAdvancedOptions ? $r('app.media.ic_angle_up') : $r('app.media.ic_angle_down'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.text_primary'))
        }
        .width('100%')
        .onClick(() => {
          this.showAdvancedOptions = !this.showAdvancedOptions;
        })

        if (this.showAdvancedOptions) {
          // 算法选择（仅对RFC6238和自定义令牌有效）
          if (this.selectedType !== TotpType.STEAM) {
            Column() {
              Text('哈希算法').fontSize(14).alignSelf(ItemAlign.Start).margin({ top: 10, bottom: 5 })

              Row() {
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
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // 位数选择（仅对RFC6238和自定义令牌有效）
          if (this.selectedType !== TotpType.STEAM) {
            Column() {
              Text('令牌位数').fontSize(14).alignSelf(ItemAlign.Start).margin({ top: 10, bottom: 5 })

              Row() {
                Counter() {
                  Text(`${this.totpConfig.digits}`)
                    .fontSize(14)
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
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }

          // 周期选择
          Column() {
            Text('更新周期（秒）').fontSize(14).alignSelf(ItemAlign.Start).margin({ top: 10, bottom: 5 })

            Row() {
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
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .padding(10)
      .backgroundColor('#F5F5F5')
      .borderRadius(8)
      .margin({ bottom: 15 })

      // 令牌预览
      if (this.totpConfig.secret) {
        TotpPreviewComponent({ totpConfig: this.totpConfig })
          .width('100%')
          .margin({ bottom: 15 })
      }

      // 按钮
      Row() {
        Button('取消', { type: ButtonType.Normal, stateEffect: true })
          .onClick(() => {
            this.controller.close();
            this.cancel();
          })
          .backgroundColor('#F0F0F0')
          .fontColor('#333333')

        Blank()

        Button('确定', { type: ButtonType.Normal, stateEffect: true })
          .onClick(() => {
            if (this.validateConfig()) {
              this.controller.close();
              this.confirm(this.totpConfig);
            }
          })
          .backgroundColor('#0A59F7')
          .fontColor(Color.White)
      }
      .width('100%')
    }
    .width('100%')
    .padding(15)
  }

  /**
   * 生成随机密钥
   */
  private async generateRandomSecret() {
    try {
      const secret = await this.totpService.generateRandomSecret();
      this.totpConfig.secret = secret;
    } catch (error) {
      console.error('生成随机密钥错误:', error);
      this.errorMessage = '生成随机密钥失败';
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
        } else {
          this.errorMessage = '无法解析TOTP二维码';
        }
      } else {
        this.errorMessage = result.error || '扫码失败';
      }
    } catch (error) {
      console.error('扫码错误:', error);
      this.errorMessage = '扫码过程中出错';
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
      this.errorMessage = '密钥不能为空';
      return false;
    }
      return true;
  }
}