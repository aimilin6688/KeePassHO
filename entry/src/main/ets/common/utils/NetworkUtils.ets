import { connection } from '@kit.NetworkKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

const DOMAIN = 0x0000;
const TAG = 'NetworkUtils';

/**
 * 网络状态工具类
 */
export class NetworkUtils {
  /**
   * 是否有可用网络（存在默认网络即视为在线，不保证服务端可达）
   * @returns true=在线，false=离线或查询失败
   */
  static async hasNetwork(): Promise<boolean> {
    try {
      return await connection.hasDefaultNet();
    } catch (error) {
      hilog.warn(DOMAIN, TAG, 'hasDefaultNet failed: %{public}s', (error as Error).message);
      return false;
    }
  }
}
