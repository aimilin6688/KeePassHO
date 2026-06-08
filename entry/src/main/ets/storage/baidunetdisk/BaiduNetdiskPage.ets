import { BaiduNetdiskConfig } from './BaiduNetdiskConfig';
import { BaiduNetdiskOAuth2Provider } from './BaiduNetdiskOAuth2Provider';
import { StorageType } from '../StorageType';

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
  @State private isAuthorizing: boolean = false;
  @State private authStep: number = 0; // 0=未开始, 1=等待授权, 2=授权成功
  @State private statusMessage: string = '';

  private config: BaiduNetdiskConfig = new BaiduNetdiskConfig();
  private provider: BaiduNetdiskOAuth2Provider = new BaiduNetdiskOAuth2Provider(this.config);

  async aboutToAppear() {
    // 加载已有配置
    this.config = await BaiduNetdiskConfig.load();
    this.appKey = this.config.pageConfig.appKey;
    this.appSecret = this.config.pageConfig.appSecret;
    this.redirectUri = this.config.pageConfig.redirectUri || 'https://localhost/callback';
    this.rootPath = this.config.pageConfig.rootPath || '/apps/kee-pass-ho/';
    if (this.config.isConfigured()) {
      this.authStep = 2;
      this.statusMessage = '已授权';
    }
  }

  build() {
    Column({ space: 16 }) {
      Text('百度网盘配置')
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .margin({ top: 24, bottom: 8 });

      // ---- 应用配置 ----
      TextInput({ placeholder: 'App Key', text: this.appKey })
        .onChange((value: string) => { this.appKey = value; });
      TextInput({ placeholder: 'App Secret', text: this.appSecret })
        .onChange((value: string) => { this.appSecret = value; });
      TextInput({ placeholder: '回调地址', text: this.redirectUri })
        .onChange((value: string) => { this.redirectUri = value; });
      TextInput({ placeholder: '根路径（网盘目录）', text: this.rootPath })
        .onChange((value: string) => { this.rootPath = value; });

      // ---- 授权按钮 ----
      Button(this.authStep === 2 ? '重新授权' : '开始授权')
        .onClick(() => this.startAuthorization())
        .enabled(!this.isAuthorizing);

      // ---- 状态提示 ----
      if (this.statusMessage) {
        Text(this.statusMessage)
          .fontSize(14)
          .fontColor(this.authStep === 2 ? '#00a870' : '#e6a23c');
      }

      // ---- 保存按钮 ----
      Button('保存配置')
        .onClick(() => this.saveConfig())
        .margin({ top: 16 });
    }
    .padding(24);
  }

  private async startAuthorization() {
    this.isAuthorizing = true;
    this.statusMessage = '正在打开授权页面...';
    // 保存当前配置（App Key/Secret）
    this.config.pageConfig.appKey = this.appKey;
    this.config.pageConfig.appSecret = this.appSecret;
    this.config.pageConfig.redirectUri = this.redirectUri;
    this.config.pageConfig.rootPath = this.rootPath;
    await this.config.save();

    // 获取授权 URL（实际应使用 WebView 加载此 URL）
    const authUrl = this.provider.getAuthorizationUrl();
    this.statusMessage = `请在浏览器中打开以下链接授权：\n${authUrl}`;
    this.authStep = 1;
    this.isAuthorizing = false;

    // TODO: 实际实现应使用 WebView 组件加载 authUrl，
    // 并监听重定向到 redirectUri，从中提取 authorization code
  }

  private async handleAuthCallback(code: string) {
    try {
      this.statusMessage = '正在交换 Token...';
      await this.provider.handleAuthorizationCode(code);
      this.authStep = 2;
      this.statusMessage = '授权成功！';
    } catch (e) {
      this.statusMessage = `授权失败：${(e as Error).message}`;
    }
  }

  private async saveConfig() {
    try {
      this.config.pageConfig.appKey = this.appKey;
      this.config.pageConfig.appSecret = this.appSecret;
      this.config.pageConfig.redirectUri = this.redirectUri;
      this.config.pageConfig.rootPath = this.rootPath;
      await this.config.save();

      // 同时保存到 StorageConfigManager
      await BaiduNetdiskOAuth2Provider.createAndSaveStorage(this.config);

      this.statusMessage = '配置已保存';
    } catch (e) {
      this.statusMessage = `保存失败：${(e as Error).message}`;
    }
  }
}
