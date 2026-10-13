import { asset } from '@kit.AssetStoreKit';
import { ByteUtils } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { CommonUtils } from '.';

const DOMAIN = 0x0000;
const TAG = 'AssetUtils';

/**
 * 关键资产工具类
 */
export class AssetUtils {
  /**
   * 查询关键资产
   * @param assetId 关键资产Id
   * @returns 关键资产内容；确认不存在（24000002）或资产库未创建（24000008）时返回 undefined
   * @throws 其他错误（服务不可用、锁屏状态不匹配、IPC 失败等瞬时/环境故障）原样上抛，
   *         调用方不得将其视为"资产不存在"而生成新数据（会使存量密文永久不可解密）
   */
  public static querySync(assetId: string): string | undefined {
    if (!assetId) {
      return undefined;
    }
    try {
      let query: asset.AssetMap = new Map();
      // 指定了关键资产别名，最多查询到一条满足条件的关键资产。
      query.set(asset.Tag.ALIAS, ByteUtils.stringToBytes(assetId));
      query.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
      // 查询关键资产
      const result: Array<asset.AssetMap> = asset.querySync(query);
      if (result.length > 0) {
        return ByteUtils.bytesToString(result[0].get(asset.Tag.SECRET) as Uint8Array);
      }
      return undefined;
    } catch (error) {
      // 24000002 资产不存在（从未写入/已删除）；24000008 资产库未创建（首次使用前查询）。
      // 两者均为"确认不存在"，静默返回 undefined 交由调用方决定是否生成。
      const ASSET_ERROR_CODE_NOT_FOUND = 24000002;
      const ASSET_ERROR_CODE_DB_NOT_CREATED = 24000008;
      if (error?.code === ASSET_ERROR_CODE_NOT_FOUND || error?.code === ASSET_ERROR_CODE_DB_NOT_CREATED) {
        return undefined;
      }
      hilog.error(DOMAIN, TAG, `queryAsset error:  Code is ${error?.code}, message is ${error?.message}`);
      throw error as Error;
    }
  }

  /**
   * 添加关键资产
   * @param assetId 关键资产Id
   * @param secret 关键资产内容
   */
  public static saveSync(assetId: string, secret: string): void {
    if (!assetId || !secret) {
      hilog.error(DOMAIN, TAG, `addAsset error: assetId or secret is empty`)
      return;
    }

    try {
      let attr: asset.AssetMap = new Map();
      attr.set(asset.Tag.ALIAS, ByteUtils.stringToBytes(assetId));
      attr.set(asset.Tag.SECRET, ByteUtils.stringToBytes(secret));
      attr.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      attr.set(asset.Tag.SYNC_TYPE, asset.SyncType.TRUSTED_ACCOUNT);
      attr.set(asset.Tag.IS_PERSISTENT, true);
      // 同别名已存在（24000003，如可信同步恢复/并发首写竞态）时覆盖写入，
      // 保证持久化结果与调用方内存态一致（官方冲突处理建议）
      attr.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
      asset.addSync(attr);
      hilog.info(DOMAIN, TAG, `addAsset success: assetId is ${assetId}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `addAsset error:  Code is ${error?.code}, message is ${error?.message}`);
      CommonUtils.showToast(`Add asset failed: ${error?.message}`, 5000);
    }
  }
}