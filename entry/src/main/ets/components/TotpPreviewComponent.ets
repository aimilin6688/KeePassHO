/**
 * TOTP令牌预览组件
 * 显示当前TOTP令牌及倒计时
 */
import { TotpConfig, TotpService } from '../services/TotpService';

@Component
export struct TotpPreviewComponent {
  @Prop totpConfig: TotpConfig;
  @State previewToken: string = '';
  @State remainingSeconds: number = 30;
  @State isGeneratingToken: boolean = false;
  @State errorMessage: string = '';

  private totpService: TotpService = TotpService.getInstance();
  private tokenUpdateTimer: number = -1;

  aboutToAppear() {
    // 更新预览令牌
    this.updatePreviewToken();
    // 开始令牌更新定时器
    this.startTokenUpdateTimer();
  }

  aboutToDisappear() {
    // 清除定时器
    this.clearTokenUpdateTimer();
  }

  build() {
    Column() {
      Text('令牌预览')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 10 })

      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor(Color.Red)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ bottom: 10 })
      }

      Row() {
        Text(this.previewToken)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')

        // 倒计时进度条
        Progress({ value: this.remainingSeconds, total: this.totpConfig.period || 30, type: ProgressType.Ring })
          .width(30)
          .height(30)
          .margin({ left: 15 })
      }
      .width('100%')
      .justifyContent(FlexAlign.Center)
      .margin({ bottom: 10 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(10)
    .backgroundColor('#F5F5F5')
    .borderRadius(8)
  }

  /**
   * 更新预览令牌
   */
  public async updatePreviewToken() {
    if (!this.totpConfig.secret) {
      this.previewToken = '';
      return;
    }

    try {
      this.isGeneratingToken = true;
      this.errorMessage = '';

      // 生成令牌
      const token = await this.totpService.generateToken(this.totpConfig);
      this.previewToken = token;

      // 更新剩余秒数
      this.remainingSeconds = this.totpService.getRemainingSeconds(this.totpConfig);

      this.isGeneratingToken = false;
    } catch (error) {
      console.error('生成令牌错误:', error);
      this.previewToken = '';
      this.errorMessage = '生成令牌失败，请检查密钥格式';
      this.isGeneratingToken = false;
    }
  }

  /**
   * 开始令牌更新定时器
   */
  private startTokenUpdateTimer() {
    // 每秒更新剩余时间
    this.tokenUpdateTimer = setInterval(() => {
      if (this.totpConfig.secret) {
        // 更新剩余秒数
        this.remainingSeconds = this.totpService.getRemainingSeconds(this.totpConfig);

        // 如果剩余时间为0，重新生成令牌
        if (this.remainingSeconds === 0 || this.remainingSeconds === this.totpConfig.period) {
          this.updatePreviewToken();
        }
      }
    }, 1000);
  }

  /**
   * 清除令牌更新定时器
   */
  private clearTokenUpdateTimer() {
    if (this.tokenUpdateTimer !== -1) {
      clearInterval(this.tokenUpdateTimer);
      this.tokenUpdateTimer = -1;
    }
  }

  /**
   * 验证配置是否有效
   */
  public isConfigValid(): boolean {
    // 检查密钥是否为空
    if (!this.totpConfig.secret) {
      this.errorMessage = '密钥不能为空';
      return false;
    }

    // 如果当前正在生成令牌，等待完成
    if (this.isGeneratingToken) {
      this.errorMessage = '正在验证配置，请稍候';
      return false;
    }

    // 如果预览令牌为空且没有错误消息，可能是生成失败
    if (!this.previewToken && !this.errorMessage) {
      this.errorMessage = '无法生成有效令牌，请检查配置';
      return false;
    }

    return true;
  }
}
