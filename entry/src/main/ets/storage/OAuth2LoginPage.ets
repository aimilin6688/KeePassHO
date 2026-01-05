import { Router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'OAuth2LoginPage';

/**
 * 授权结果
 */
export interface AuthResult {
  /**
   * 授权码
   */
  code: string;
  /**
   * 状态参数
   */
  state: string;
}

/**
 * OAuth2配置（简化版，仅用于传递）
 */
interface OAuth2Config {
  /**
   * 重定向URI
   */
  redirectUri: string;
}

/**
 * Web页面加载事件
 */
interface WebPageEvent {
  /**
   * 页面URL
   */
  url?: string;
}

@Entry
@Component
export struct OAuth2LoginPage {
  /**
   * OAuth2配置
   */
  @State oauth2Config: OAuth2Config = {
    redirectUri: ''
  };
  /**
   * 授权URL
   */
  @State authUrl: string = '';
  /**
   * Web控制器
   */
  private webviewController: webview.WebviewController = new webview.WebviewController();
  /**
   * 路由
   */
  private router: Router = this.getUIContext().getRouter();
  /**
   * 是否已完成授权
   */
  private authCompleted: boolean = false;

  aboutToAppear(): void {
    // 获取页面参数
    const state = this.router.getState();
    if (state && state.params) {
      const params = state.params as Record<string, Object>;
      if (params) {
        if (params['oauth2Config']) {
          this.oauth2Config = params['oauth2Config'] as OAuth2Config;
        }
        if (params['authUrl']) {
          this.authUrl = params['authUrl'] as string;
        }
      }
    }
    
    hilog.info(DOMAIN, TAG, `OAuth2LoginPage initialized with authUrl: ${this.authUrl}`);
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back();
          })

        Text('OneDrive 授权')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(56)
      .backgroundColor($r('app.color.card_bg'))

      // Web组件
      Web({
        src: this.authUrl,
        controller: this.webviewController
      })
        .domStorageAccess(true)
        .javaScriptAccess(true)
        .mixedMode(MixedMode.All)
        .cacheMode(CacheMode.Default)
        .onPageEnd((event?: WebPageEvent) => {
          if (event && event.url) {
            hilog.info(DOMAIN, TAG, `Page loaded: ${event.url}`);
            this.handleUrlChange(event.url);
          }
        })
        .onErrorReceive((event) => {
          hilog.error(DOMAIN, TAG, `Web error: ${event.error.getErrorInfo()}`);
        })
        .layoutWeight(1)
        .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }

  /**
   * 处理URL变化
   * @param url 当前URL
   */
  private handleUrlChange(url: string): void {
    if (this.authCompleted) {
      return;
    }

    // 检查是否是重定向URI
    if (url.startsWith(this.oauth2Config.redirectUri)) {
      hilog.info(DOMAIN, TAG, `Redirect detected: ${url}`);
      
      // 提取授权码和状态
      const code = this.extractCodeFromUrl(url);
      const state = this.extractStateFromUrl(url);
      
      if (code) {
        this.authCompleted = true;
        
        // 使用AppStorage存储授权结果，然后返回
        AppStorage.setOrCreate('oauth2_auth_result', {
          code: code,
          state: state || ''
        } as AuthResult);
        
        this.router.back();
        
        hilog.info(DOMAIN, TAG, `Auth completed, code length: ${code.length}`);
      }
    }
  }

  /**
   * 从URL中提取授权码
   * @param url URL
   * @returns 授权码
   */
  private extractCodeFromUrl(url: string): string | undefined {
    if (!url || url.trim().length === 0) {
      return undefined;
    }

    try {
      const match = url.match(/[?&]code=([^&]+)/);
      if (match && match[1]) {
        return decodeURIComponent(match[1]);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to extract code: ${(error as Error).message}`);
    }

    return undefined;
  }

  /**
   * 从URL中提取状态参数
   * @param url URL
   * @returns 状态参数
   */
  private extractStateFromUrl(url: string): string | undefined {
    if (!url || url.trim().length === 0) {
      return undefined;
    }

    try {
      const match = url.match(/[?&]state=([^&]+)/);
      if (match && match[1]) {
        return decodeURIComponent(match[1]);
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `Failed to extract state: ${(error as Error).message}`);
    }

    return undefined;
  }
}
