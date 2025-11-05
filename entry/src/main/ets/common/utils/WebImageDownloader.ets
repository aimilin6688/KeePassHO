import { rcp } from '@kit.RemoteCommunicationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import image from '@ohos.multimedia.image';
import KdbxUtils from './KdbxUtils';
import ResourceManager from './ResourceManager';
import { UrlUtils } from './UrlUtils';

const DOMAIN = 0x0000;
const TAG = 'WebImageDownloader';

/**
 * 网络图片下载工具类
 */
export class WebImageDownloader {
  /**
   * 从URL下载图片并转换为base64
   * @param url 图片URL
   * @param size 图片尺寸
   * @returns base64编码的图片数据
   */
  public static async downloadImage(url: string, size: number = 64): Promise<string | null> {
    if (!url || !UrlUtils.isValidUrl(url)) {
      throw new Error(ResourceManager.getString($r("app.string.download_image_url_invalid_message")));
    }

    let session: rcp.Session | null = null;
    try {
      // 创建HTTP会话
      session = rcp.createSession({
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Accept': 'image/*'
        },
        requestConfiguration: {
          transfer: {
            timeout: { connectMs: 10000 }
          }
        }
      });

      // 发送GET请求
      const response = await session.get(url);

      if (response.statusCode !== 200) {
        throw new Error(`HTTP ${response.statusCode}: ${response.toString()}`);
      }

      // 获取响应数据
      const arrayBuffer = response.body as ArrayBuffer;
      if (!arrayBuffer || arrayBuffer.byteLength === 0) {
        throw new Error('Empty response');
      }

      // 检查图片类型
      const contentType = response.headers?.['content-type'] || '';
      if (!WebImageDownloader.isValidImageType(contentType)) {
        throw new Error('Unsupported image type: ' + contentType);
      }

      // 处理图片
      const base64Image = await WebImageDownloader.processImageData(arrayBuffer, contentType, size);

      return base64Image;

    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Download image failed: ' + error.message);
      throw new Error(error.message);
    } finally {
      // 确保会话被关闭
      if (session) {
        try {
          session.close();
        } catch (closeError) {
          hilog.warn(DOMAIN, TAG, 'Close session failed: ' + closeError.message);
        }
      }
    }
  }

  /**
   * 验证图片类型
   * @param contentType 内容类型
   * @returns 是否支持
   */
  private static isValidImageType(contentType: string): boolean {
    const supportedTypes = [
      'image/jpeg',
      'image/jpg',
      'image/png',
      'image/gif',
      'image/webp',
      'image/bmp'
    ];
    return supportedTypes.some(type => contentType.includes(type));
  }

  /**
   * 处理图片数据
   * @param arrayBuffer 图片数据
   * @param contentType 图片类型
   * @param size 目标尺寸
   * @returns base64编码的图片
   */
  private static async processImageData(arrayBuffer: ArrayBuffer, contentType: string, size: number): Promise<string> {
    try {
      // 创建图片源
      const imageSource = image.createImageSource(arrayBuffer);
      if (!imageSource) {
        throw new Error('Failed to create image source');
      }

      // 配置解码选项
      const decodingOptions: image.DecodingOptions = {
        editable: true,
        desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
        desiredSize: {
          width: size,
          height: size
        }
      };

      // 解码图片
      const pixelMap = await imageSource.createPixelMap(decodingOptions);

      // 确定图片格式
      let format = 'image/jpeg';
      if (contentType.includes('png')) {
        format = 'image/png';
      } else if (contentType.includes('gif')) {
        format = 'image/gif';
      } else if (contentType.includes('webp')) {
        format = 'image/webp';
      } else if (contentType.includes('bmp')) {
        format = 'image/bmp';
      }
      // 创建图片包
      const imagePackerOptions: image.PackingOption = {
        format: format,
        quality: 90
      };

      const imagePacker = image.createImagePacker();
      const imageData = await imagePacker.packToData(pixelMap, imagePackerOptions);

      // 转换为base64
      const base64Image = KdbxUtils.toImgBase64Url(imageData);

      // 释放资源
      await pixelMap.release();
      await imagePacker.release();
      await imageSource.release();

      if (!base64Image) {
        throw new Error('Failed to convert image to base64');
      }

      return base64Image;

    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Process image data failed: ' + error.message);
      throw new Error(error.message);
    }
  }
}