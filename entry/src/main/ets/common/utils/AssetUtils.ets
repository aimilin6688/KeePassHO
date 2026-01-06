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
   * @returns 关键资产内容
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
      hilog.error(DOMAIN, TAG, `queryAsset error:  Code is ${error?.code}, message is ${error?.message}`);
      CommonUtils.showToast(`Query asset failed: ${error?.message}`, 5000);
      return undefined;
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
      asset.addSync(attr);
      hilog.info(DOMAIN, TAG, `addAsset success: assetId is ${assetId}`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `addAsset error:  Code is ${error?.code}, message is ${error?.message}`);
      CommonUtils.showToast(`Add asset failed: ${error?.message}`, 5000);
    }
  }
}