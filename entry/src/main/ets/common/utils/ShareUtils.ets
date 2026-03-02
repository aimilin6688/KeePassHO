import { systemShare } from '@kit.ShareKit';
import { uniformTypeDescriptor as utd } from '@kit.ArkData';
import { fileUri } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const DOMAIN = 0x0000;
const TAG = 'ShareUtils';

/**
 * 分享结果回调类型
 */
export type ShareCompletedCallback = (result: systemShare.ShareOperationResult) => void;

/**
 * 分享工具类
 * 用于分享文件到其他应用（如邮件）
 * 参考: https://developer.huawei.com/consumer/cn/doc/harmonyos-references/share-system-share
 */
export class ShareUtils {
  /**
   * 分享文件到其他应用（带分享完成回调）
   * @param context UIAbility上下文
   * @param filePath 文件路径
   * @param onShareCompleted 分享完成回调（用户真正完成分享时触发）
   * @param title 分享标题（可选）
   * @returns 是否成功发起分享
   */
  public static async shareFileWithCallback(
    context: common.UIAbilityContext,
    filePath: string,
    onShareCompleted: ShareCompletedCallback,
    title?: string
  ): Promise<boolean> {
    try {
      // 创建文件URI
      const uri = fileUri.getUriFromPath(filePath);
      hilog.info(DOMAIN, TAG, 'Share file uri: %{public}s', uri);

      // 构造分享数据记录
      const record: systemShare.SharedRecord = {
        utd: utd.UniformDataType.FILE,
        uri: uri,
        title: title
      };

      // 创建分享数据对象
      const shareData: systemShare.SharedData = new systemShare.SharedData(record);

      // 创建分享控制器
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);

      // 注册分享完成事件监听
      controller.on('shareCompleted', (result: systemShare.ShareOperationResult) => {
        hilog.info(DOMAIN, TAG, 'Share completed, target: %{public}s', result.targetAbilityInfo.name);
        onShareCompleted(result);
      });

      // 创建分享控制器配置项
      const options: systemShare.ShareControllerOptions = {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      };

      // 显示分享面板
      await controller.show(context, options);
      hilog.info(DOMAIN, TAG, 'Share panel shown successfully');
      return true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to share file. code: %{public}d, message: %{public}s',
        err.code, err.message);
      return false;
    }
  }

  /**
   * 分享文件到其他应用
   * @param context UIAbility上下文
   * @param filePath 文件路径
   * @param title 分享标题（可选）
   * @returns 是否成功发起分享
   */
  public static async shareFile(
    context: common.UIAbilityContext,
    filePath: string,
    title?: string
  ): Promise<boolean> {
    try {
      // 创建文件URI
      const uri = fileUri.getUriFromPath(filePath);
      hilog.info(DOMAIN, TAG, 'Share file uri: %{public}s', uri);

      // 构造分享数据记录
      const record: systemShare.SharedRecord = {
        utd: utd.UniformDataType.FILE,
        uri: uri,
        title: title
      };

      // 创建分享数据对象
      const shareData: systemShare.SharedData = new systemShare.SharedData(record);

      // 创建分享控制器
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);

      // 创建分享控制器配置项
      const options: systemShare.ShareControllerOptions = {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.SINGLE
      };

      // 显示分享面板
      await controller.show(context, options);
      hilog.info(DOMAIN, TAG, 'Share panel shown successfully');
      return true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to share file. code: %{public}d, message: %{public}s',
        err.code, err.message);
      return false;
    }
  }

  /**
   * 分享多个文件到其他应用
   * @param context UIAbility上下文
   * @param filePaths 文件路径数组
   * @param title 分享标题（可选）
   * @returns 是否成功发起分享
   */
  public static async shareFiles(
    context: common.UIAbilityContext,
    filePaths: string[],
    title?: string
  ): Promise<boolean> {
    try {
      if (filePaths.length === 0) {
        hilog.error(DOMAIN, TAG, 'No files to share');
        return false;
      }

      // 创建第一条分享数据记录
      const firstUri = fileUri.getUriFromPath(filePaths[0]);
      const firstRecord: systemShare.SharedRecord = {
        utd: utd.UniformDataType.FILE,
        uri: firstUri,
        title: title
      };

      // 创建分享数据对象
      const shareData: systemShare.SharedData = new systemShare.SharedData(firstRecord);

      // 添加其他文件记录
      for (let i = 1; i < filePaths.length; i++) {
        const uri = fileUri.getUriFromPath(filePaths[i]);
        const record: systemShare.SharedRecord = {
          utd: utd.UniformDataType.FILE,
          uri: uri
        };
        shareData.addRecord(record);
      }

      // 创建分享控制器
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);

      // 创建分享控制器配置项
      const options: systemShare.ShareControllerOptions = {
        previewMode: systemShare.SharePreviewMode.DETAIL,
        selectionMode: systemShare.SelectionMode.BATCH
      };

      // 显示分享面板
      await controller.show(context, options);
      hilog.info(DOMAIN, TAG, 'Share panel shown successfully for multiple files');
      return true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to share files. code: %{public}d, message: %{public}s',
        err.code, err.message);
      return false;
    }
  }

  /**
   * 分享文本内容
   * @param context UIAbility上下文
   * @param text 文本内容
   * @param title 分享标题（可选）
   * @returns 是否成功发起分享
   */
  public static async shareText(
    context: common.UIAbilityContext,
    text: string,
    title?: string
  ): Promise<boolean> {
    try {
      // 构造分享数据记录
      const record: systemShare.SharedRecord = {
        utd: utd.UniformDataType.TEXT,
        content: text,
        title: title
      };

      // 创建分享数据对象
      const shareData: systemShare.SharedData = new systemShare.SharedData(record);

      // 创建分享控制器
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);

      // 创建分享控制器配置项
      const options: systemShare.ShareControllerOptions = {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      };

      // 显示分享面板
      await controller.show(context, options);
      hilog.info(DOMAIN, TAG, 'Share text panel shown successfully');
      return true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to share text. code: %{public}d, message: %{public}s',
        err.code, err.message);
      return false;
    }
  }

  /**
   * 分享链接
   * @param context UIAbility上下文
   * @param url 链接地址
   * @param title 链接标题
   * @param description 链接描述（可选）
   * @returns 是否成功发起分享
   */
  public static async shareLink(
    context: common.UIAbilityContext,
    url: string,
    title: string,
    description?: string
  ): Promise<boolean> {
    try {
      // 构造分享数据记录
      const record: systemShare.SharedRecord = {
        utd: utd.UniformDataType.HYPERLINK,
        content: url,
        title: title,
        description: description
      };

      // 创建分享数据对象
      const shareData: systemShare.SharedData = new systemShare.SharedData(record);

      // 创建分享控制器
      const controller: systemShare.ShareController = new systemShare.ShareController(shareData);

      // 创建分享控制器配置项
      const options: systemShare.ShareControllerOptions = {
        previewMode: systemShare.SharePreviewMode.DEFAULT,
        selectionMode: systemShare.SelectionMode.SINGLE
      };

      // 显示分享面板
      await controller.show(context, options);
      hilog.info(DOMAIN, TAG, 'Share link panel shown successfully');
      return true;
    } catch (error) {
      const err = error as BusinessError;
      hilog.error(DOMAIN, TAG, 'Failed to share link. code: %{public}d, message: %{public}s',
        err.code, err.message);
      return false;
    }
  }
}
