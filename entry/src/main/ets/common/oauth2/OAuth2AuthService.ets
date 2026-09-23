import { hilog } from '@kit.PerformanceAnalysisKit';
import { IOAuth2Provider } from './IOAuth2Provider';
import { OAuth2AuthRequest, OAuth2Provider, OAuth2Token } from './OAuth2Types';
import { OAuth2TokenStorageService } from './OAuth2TokenStorageService';

const DOMAIN = 0x0000;
const TAG = 'OAuth2AuthService';

/**
 * OAuth2 令牌读写与授权码交换的公共封装
 * 各云存储页面只需传入不同的 OAuth2Provider，
 * 避免在每个页面重复实现「加载 / 保存 / 删除令牌」与「授权码换令牌」的流程
 */
export class OAuth2AuthService {
  /**
   * 加载指定提供者的令牌（加密存储）
   * @param provider OAuth2提供者
   * @return 令牌，不存在或加载失败返回 null
   */
  static async loadToken(provider: OAuth2Provider): Promise<OAuth2Token | null> {
    try {
      const token: OAuth2Token | null =
        await OAuth2TokenStorageService.getInstance().loadToken({ provider: provider, encrypt: true });
      if (token) {
        hilog.info(DOMAIN, TAG, 'Token loaded for provider: %{public}s', provider);
      } else {
        hilog.debug(DOMAIN, TAG, 'No token found for provider: %{public}s', provider);
      }
      return token;
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load token: %{public}s', (error as Error).message);
      return null;
    }
  }

  /**
   * 保存指定提供者的令牌（加密存储）
   * @param provider OAuth2提供者
   * @param token 令牌，为空时忽略
   */
  static async saveToken(provider: OAuth2Provider, token: OAuth2Token | null): Promise<void> {
    if (!token) {
      return;
    }
    try {
      await OAuth2TokenStorageService.getInstance().saveToken(token, { provider: provider, encrypt: true });
      hilog.info(DOMAIN, TAG, 'Token saved for provider: %{public}s', provider);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to save token: %{public}s', (error as Error).message);
    }
  }

  /**
   * 删除指定提供者的令牌
   * @param provider OAuth2提供者
   */
  static async deleteToken(provider: OAuth2Provider): Promise<void> {
    try {
      await OAuth2TokenStorageService.getInstance().deleteToken({ provider: provider, encrypt: true });
      hilog.info(DOMAIN, TAG, 'Token deleted for provider: %{public}s', provider);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to delete token: %{public}s', (error as Error).message);
    }
  }

  /**
   * 使用授权码换取访问令牌并保存
   * @param oauth2Provider OAuth2提供者实例
   * @param code 授权码
   * @param state 状态参数
   * @param provider 令牌归属的提供者（用于持久化）
   * @return 访问令牌
   */
  static async exchangeCodeForToken(oauth2Provider: IOAuth2Provider, code: string, state: string,
    provider: OAuth2Provider): Promise<OAuth2Token> {
    const authRequest: OAuth2AuthRequest = {
      code: code,
      state: state
    };
    const token: OAuth2Token = await oauth2Provider.authorize(authRequest);
    await OAuth2AuthService.saveToken(provider, token);
    hilog.info(DOMAIN, TAG, `Token obtained by authorization code, expires at: ${token.expiresAt}`);
    return token;
  }
}
