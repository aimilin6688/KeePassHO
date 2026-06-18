/**
 * TOTP令牌预览组件
 * 显示当前TOTP令牌及倒计时
 */
import { TotpConfig, TotpService } from '../services/TotpService';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ResourceManager } from '../common/utils';

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
  @Prop isShow: boolean = true;
  @State previewToken: string = '';
  @State remainingSeconds: number = 30;
  @State isGeneratingToken: boolean = false;
  @State errorMessage: string = '';
  @State private currentCounter: number = -1; // 当前周期计数器
  onChange: (value: string) => void = () => {
  };
  doClick: (value: string, event?: ClickEvent) => boolean = () => {
    return true
  };
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
      if (this.isShow && this.previewToken) {
        Row() {
          Text(this.previewToken)
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontFamily('monospace')
          // 倒计时进度条
          Progress({ value: this.remainingSeconds, total: this.totpConfig?.period || 30, type: ProgressType.Ring })
            .width(24)
            .height(24)
            .margin({ left: 15 })
        }
      } else{
        Text('******')
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start)
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
    .onClick(event => {
      return this.doClick(this.previewToken, event);
    });
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

    if (!this.totpConfig || !this.totpConfig.secret) {
      this.previewToken = '';
      return;
    }

    try {
      this.isGeneratingToken = true;
      this.errorMessage = '';

      // 使用统一的时间戳，确保令牌生成和剩余时间计算一致
      const now = Date.now();
      const period = this.totpConfig.period || 30;

      // 更新当前周期计数器
      this.currentCounter = Math.floor(now / 1000 / period);

      // 生成令牌
      const token = await this.totpService.generateToken(this.totpConfig, now);
      this.previewToken = token;

      // 更新剩余秒数（使用同一个时间戳）
      this.remainingSeconds = this.totpService.getRemainingSeconds(this.totpConfig, now);
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
        const period = this.totpConfig.period || 30;
        const now = Date.now();

        // 计算当前周期计数器
        const newCounter = Math.floor(now / 1000 / period);

        // 更新剩余秒数
        this.remainingSeconds = this.totpService.getRemainingSeconds(this.totpConfig, now);

        // 如果周期计数器发生变化，重新生成令牌
        if (newCounter !== this.currentCounter) {
          this.currentCounter = newCounter;
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
    if (!this.totpConfig) {
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
