import { BaiduNetdiskConfig } from './BaiduNetdiskConfig';
import { BaiduNetdiskOAuth2Provider } from './BaiduNetdiskOAuth2Provider';
import { CommonUtils } from '../../common/utils/CommonUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'BaiduNetdiskPage';

/**
 * 百度网盘配置页面
 * 提供 OAuth2.0 授权和应用配置 UI
 */
@Entry
@Component
export struct BaiduNetdiskPage {
  @State private appKey: string = '';
  @State private appSecret: string = '';
  @State private redirectUri: string = 'https://localhost/callback';
  @State private rootPath: string = '/apps/kee-pass-ho/';
  @State private authUrl: string = '';
  @State private authCode: string = '';
  @State private isAuthorizing: boolean = false;
  @State private authStep: number = 0; // 0=未开始, 1=等待授权, 2=授权成功
  @State private statusMessage: string = '';

  private config: BaiduNetdiskConfig = new BaiduNetdiskConfig();
  private provider: BaiduNetdiskOAuth2Provider = new BaiduNetdiskOAuth2Provider(this.config);

  async aboutToAppear(): Promise<void> {
    // 加载已有配置
    this.config = await BaiduNetdiskConfig.load();
    this.appKey = this.config.appKey;
    this.appSecret = this.config.appSecret;
    this.redirectUri = this.config.redirectUri;
    this.rootPath = this.config.rootPath;
    const isConfigured = await this.config.isConfigured();
    if (isConfigured) {
      this.authStep = 2;
      this.statusMessage = '已授权';
    }
  }

  build() {
    Column() {
      Text('百度网盘配置')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 24, bottom: 16 });

      // ---- 应用配置 ----
      Text('应用信息')
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .alignSelf(ItemAlign.Start)
        .margin({ bottom: 8 });

      TextInput({ placeholder: 'App Key', text: this.appKey })
        .margin({ bottom: 8 })
        .onChange((value: string) => {
          this.appKey = value;
        });

      TextInput({ placeholder: 'App Secret', text: this.appSecret })
        .margin({ bottom: 8 })
        .onChange((value: string) => {
          this.appSecret = value;
        });

      TextInput({ placeholder: '回调地址', text: this.redirectUri })
        .margin({ bottom: 8 })
        .onChange((value: string) => {
          this.redirectUri = value;
        });

      TextInput({ placeholder: '根路径（网盘目录）', text: this.rootPath })
        .margin({ bottom: 16 })
        .onChange((value: string) => {
          this.rootPath = value;
        });

      Divider().margin({ top: 8, bottom: 16 });

      // ---- 授权按钮 ----
      Button(this.authStep === 2 ? '重新授权' : '开始授权')
        .width('100%')
        .onClick(() => this.startAuthorization())
        .enabled(!this.isAuthorizing)
        .margin({ bottom: 8 });

      // ---- 授权 URL 显示 ----
      if (this.authUrl !== '') {
        Text('请在浏览器中打开以下链接：')
          .fontSize(14)
          .alignSelf(ItemAlign.Start)
          .margin({ top: 8, bottom: 4 });

        Text(this.authUrl)
          .fontSize(12)
          .fontColor('#1890ff')
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 12 });

        Text('授权后将获得授权码，请粘贴到下方：')
          .fontSize(14)
          .alignSelf(ItemAlign.Start)
          .margin({ bottom: 4 });

        TextInput({ placeholder: '粘贴授权码（code）', text: this.authCode })
          .margin({ bottom: 8 })
          .onChange((value: string) => {
            this.authCode = value;
          });

        Button('交换 Token')
          .width('100%')
          .onClick(() => this.handleExchangeToken())
          .margin({ bottom: 8 });
      }

      // ---- 状态提示 ----
      if (this.statusMessage !== '') {
        Text(this.statusMessage)
          .fontSize(14)
          .fontColor(this.authStep === 2 ? '#00a870' : '#e6a23c')
          .alignSelf(ItemAlign.Start)
          .margin({ top: 8 });
      }

      Divider().margin({ top: 16, bottom: 16 });

      // ---- 保存按钮 ----
      Button('保存配置')
        .width('100%')
        .onClick(() => this.saveConfig())
        .margin({ bottom: 24 });
    }
    .padding(24)
    .width('100%')
    .height('100%');
  }

  private async startAuthorization(): Promise<void> {
    this.isAuthorizing = true;
    this.statusMessage = '正在生成授权链接...';

    // 保存当前配置
    this.config.appKey = this.appKey;
    this.config.appSecret = this.appSecret;
    this.config.redirectUri = this.redirectUri;
    this.config.rootPath = this.rootPath;
    await this.config.save();

    // 获取授权 URL
    this.authUrl = this.provider.getAuthorizationUrl();
    this.authStep = 1;
    this.statusMessage = '请复制上方链接，在浏览器中完成授权';
    this.isAuthorizing = false;
  }

  private async handleExchangeToken(): Promise<void> {
    if (!this.authCode) {
      this.statusMessage = '请输入授权码';
      return;
    }
    this.statusMessage = '正在交换 Token...';
    try {
      await this.provider.handleAuthorizationCode(this.authCode);
      this.authStep = 2;
      this.statusMessage = '授权成功！点击保存配置';
    } catch (e) {
      this.statusMessage = '授权失败：' + (e as Error).message;
      hilog.error(DOMAIN, TAG, 'Token exchange failed: %{public}s', (e as Error).message);
    }
  }

  private async saveConfig(): Promise<void> {
    try {
      this.config.appKey = this.appKey;
      this.config.appSecret = this.appSecret;
      this.config.redirectUri = this.redirectUri;
      this.config.rootPath = this.rootPath;
      await this.config.save();

      // 同时创建存储实例
      await BaiduNetdiskOAuth2Provider.createStorage(this.config);

      this.statusMessage = '配置已保存';
      CommonUtils.showToast('百度网盘配置已保存');
    } catch (e) {
      this.statusMessage = '保存失败：' + (e as Error).message;
    }
  }
}
