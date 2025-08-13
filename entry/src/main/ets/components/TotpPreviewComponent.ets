/**
 * TOTP令牌预览组件
 * 显示当前TOTP令牌及倒计时
 */
import { TotpConfig, TotpService } from '../services/TotpService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import ResourceManager from '../common/utils/ResourceManager';

const DOMAIN = 0x0000;
const TAG = 'TotpPreviewComponent';

export class TotpPreviewController {
  updatedToken = () => {
  };
}

@Component
export struct TotpPreviewComponent {
  @Prop totpConfig: TotpConfig | undefined = undefined;
  @Prop totpUrl: string | undefined = undefined;
  @State previewToken: string = '';
  @State remainingSeconds: number = 30;
  @State isGeneratingToken: boolean = false;
  @State errorMessage: string = '';
  onChange: (value: string) => void = () => {};
  controller: TotpPreviewController | undefined = undefined;
  private totpService: TotpService = TotpService.getInstance();
  private tokenUpdateTimer: number = -1;

  aboutToAppear() {
    if (this.controller) {
      this.controller.updatedToken = this.updatedToken;
    }
    this.updatedToken();
  }

  aboutToDisappear() {
    // 清除定时器
    this.clearTokenUpdateTimer();
  }

  /**
   * 更新令牌
   */
  private updatedToken = () => {
    // 清除定时器
    this.clearTokenUpdateTimer();
    // 更新预览令牌
    this.updatePreviewToken();
    // 开始令牌更新定时器
    this.startTokenUpdateTimer();
  }

  build() {
    Column() {
      Row() {
        Text(this.previewToken)
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontFamily('monospace')
        // 倒计时进度条
        Progress({ value: this.remainingSeconds, total: this.totpConfig?.period || 30, type: ProgressType.Ring })
          .width(30)
          .height(30)
          .margin({ left: 15 })
      }

      if (this.errorMessage) {
        Text(this.errorMessage)
          .fontSize(14)
          .fontColor(Color.Red)
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: 10 })
      }
    }
    .width('auto')
  }

  private parseTotpUrl(totpUrl: string) {
    let totpConfig = this.totpService.parseUri(totpUrl);
    if (totpConfig == null) {
      throw new Error(ResourceManager.getString($r("app.string.totp_invalid_uri")));
    }
    this.totpConfig = totpConfig;
  }

  /**
   * 更新预览令牌
   */
  public async updatePreviewToken() {
    if (!this.totpUrl && !this.totpConfig) {
      this.previewToken = '';
      return;
    }
    if (this.totpUrl !== undefined) {
      this.parseTotpUrl(this.totpUrl);
    }

    if(!this.totpConfig || !this.totpConfig.secret){
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
      // token 修改回调
      this.onChange(token);

      this.isGeneratingToken = false;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'GenerateToken error: ' + error);
      this.previewToken = '';
      this.errorMessage = ResourceManager.getString($r('app.string.error_generate_token'));
      this.isGeneratingToken = false;
    }
  }

  /**
   * 开始令牌更新定时器
   */
  private startTokenUpdateTimer() {
    // 每秒更新剩余时间
    this.tokenUpdateTimer = setInterval(() => {
      if (this.totpConfig && this.totpConfig.secret) {
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
    if(!this.totpConfig) {
      this.errorMessage = ResourceManager.getString($r('app.string.totp_config_error_empty_secret'));
      return false;
    }
    // 检查密钥是否为空
    if (!this.totpConfig.secret) {
      this.errorMessage = ResourceManager.getString($r('app.string.totp_config_error_empty_secret'));
      return false;
    }

    // 如果当前正在生成令牌，等待完成
    if (this.isGeneratingToken) {
      this.errorMessage = ResourceManager.getString($r('app.string.totp_config_error_generating_token'));
      return false;
    }

    // 如果预览令牌为空且没有错误消息，可能是生成失败
    if (!this.previewToken && !this.errorMessage) {
      this.errorMessage = ResourceManager.getString($r('app.string.totp_config_error_generate_token_failed'));
      return false;
    }

    return true;
  }
}
