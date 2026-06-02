import { Router } from '@kit.ArkUI';
import { webview } from '@kit.ArkWeb';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'OAuth2Login';

/**
 * Code Flow 授权结果
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
  /**
   * 错误信息（如用户拒绝授权）
   */
  error?: string;
}

/**
 * Token Flow (Implicit) 授权结果
 * 适用于 pCloud 等支持 Implicit Grant 的 OAuth2 提供者
 */
export interface TokenFlowResult {
  /**
   * 访问令牌
   */
  accessToken: string;
  /**
   * 令牌类型
   */
  tokenType: string;
  /**
   * 用户ID
   */
  uid?: string;
  /**
   * 状态参数
   */
  state?: string;
  /**
   * 数据中心位置ID（pCloud 特有）
   */
  locationid?: string;
  /**
   * API服务器主机名（pCloud 特有）
   */
  hostname?: string;
  /**
   * 错误信息
   */
  error?: string;
}

/**
 * 统一的授权回调结果
 * 支持 Code Flow 和 Token Flow 两种模式
 */
export interface AuthCallbackResult {
  /**
   * Code Flow 结果
   */
  codeFlow?: AuthResult;
  /**
   * Token Flow 结果
   */
  tokenFlow?: TokenFlowResult;
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
struct OAuth2Login {
  @State oauth2Config: OAuth2Config = {
    redirectUri: ''
  };
  @State authUrl: string = '';
  @State pageTitle: string = 'OAuth2 授权';
  private webviewController: webview.WebviewController = new webview.WebviewController();
  private router: Router = this.getUIContext().getRouter();
  private authCompleted: boolean = false;

  aboutToAppear(): void {
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
        if (params['pageTitle']) {
          this.pageTitle = params['pageTitle'] as string;
        }
      }
    }
    hilog.info(DOMAIN, TAG, `OAuth2Login initialized with authUrl: ${this.authUrl}`);
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

        Text(this.pageTitle)
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))
      }
      .width('100%')
      .height(40)
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
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }

  /**
   * 处理URL变化
   * 支持 Code Flow（?code=xxx）和 Token Flow（#access_token=xxx）
   */
  private handleUrlChange(url: string): void {
    if (this.authCompleted) {
      return;
    }

    if (!url.startsWith(this.oauth2Config.redirectUri)) {
      return;
    }

    hilog.info(DOMAIN, TAG, `Redirect detected: ${url}`);
    this.authCompleted = true;

    // 检查是否有错误
    const error = this.extractErrorFromUrl(url);
    if (error) {
      hilog.warn(DOMAIN, TAG, `Auth error: ${error}`);
      AppStorage.setOrCreate('oauth2_auth_result', {
        codeFlow: { code: '', state: '', error: error }
      } as AuthCallbackResult);
      this.router.back();
      return;
    }

    // 优先检查 Token Flow（fragment 中有 access_token）
    const tokenFlowResult = this.extractTokenFromFragment(url);
    if (tokenFlowResult) {
      hilog.info(DOMAIN, TAG, `Token Flow completed`);
      AppStorage.setOrCreate('oauth2_auth_result', {
        tokenFlow: tokenFlowResult
      } as AuthCallbackResult);
      this.router.back();
      return;
    }

    // 检查 Code Flow（query 中有 code）
    const code = this.extractQueryParam(url, 'code');
    if (code) {
      const state = this.extractQueryParam(url, 'state') || '';
      hilog.info(DOMAIN, TAG, `Code Flow completed`);
      AppStorage.setOrCreate('oauth2_auth_result', {
        codeFlow: { code: code, state: state }
      } as AuthCallbackResult);
      this.router.back();
    }
  }

  /**
   * 从URL中提取错误信息
   * 同时检查 query 参数和 fragment
   */
  private extractErrorFromUrl(url: string): string | undefined {
    // 检查 query 参数
    const queryError = this.extractQueryParam(url, 'error');
    if (queryError) {
      return queryError;
    }

    // 检查 fragment
    const fragmentIndex = url.indexOf('#');
    if (fragmentIndex >= 0) {
      const fragment = url.substring(fragmentIndex + 1);
      const params = this.parseParams(fragment);
      const fragmentError = params.get('error');
      if (fragmentError) {
        return fragmentError;
      }
    }

    return undefined;
  }

  /**
   * 从 URL fragment 中提取 Token Flow 结果
   */
  private extractTokenFromFragment(url: string): TokenFlowResult | undefined {
    const fragmentIndex = url.indexOf('#');
    if (fragmentIndex < 0) {
      return undefined;
    }

    const fragment = url.substring(fragmentIndex + 1);
    if (!fragment || fragment.trim().length === 0) {
      return undefined;
    }

    const params = this.parseParams(fragment);
    const accessToken = params.get('access_token');
    if (!accessToken || accessToken.trim().length === 0) {
      return undefined;
    }

    hilog.info(DOMAIN, TAG, `Token extracted from fragment`);
    return {
      accessToken: accessToken,
      tokenType: params.get('token_type') || 'bearer',
      uid: params.get('uid'),
      state: params.get('state'),
      locationid: params.get('locationid'),
      hostname: params.get('hostname')
    };
  }

  /**
   * 从 URL query 中提取指定参数
   */
  private extractQueryParam(url: string, paramName: string): string | undefined {
    const regex = new RegExp(`[?&]${paramName}=([^&]+)`);
    const match = url.match(regex);
    if (match && match[1]) {
      try {
        return decodeURIComponent(match[1]);
      } catch (e) {
        return match[1];
      }
    }
    return undefined;
  }

  /**
   * 解析参数字符串为 Map
   */
  private parseParams(paramString: string): Map<string, string> {
    const params = new Map<string, string>();
    const pairs = paramString.split('&');

    for (const pair of pairs) {
      const equalIndex = pair.indexOf('=');
      if (equalIndex > 0) {
        const key = pair.substring(0, equalIndex);
        const value = pair.substring(equalIndex + 1);
        try {
          params.set(decodeURIComponent(key), decodeURIComponent(value));
        } catch (e) {
          params.set(key, value);
        }
      }
    }

    return params;
  }
}
