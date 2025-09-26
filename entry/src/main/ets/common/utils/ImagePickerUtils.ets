import image from '@ohos.multimedia.image';
import common from '@ohos.app.ability.common';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { CommonUtils } from './CommonUtils';
import { fileIo as fs } from '@kit.CoreFileKit';
import KdbxUtils from './KdbxUtils';

const DOMAIN = 0x0000;
const TAG = 'ImagePickerUtils';

/**
 * 图片选择工具类
 */
export class ImagePickerUtils {
  /**
   * 选择图片
   * @param context 上下文
   * @returns 选择的图片的base64编码
   */
  public static async selectImage(context: common.UIAbilityContext, size: number): Promise<string[] | null> {
    const photoSelectOptions = new photoAccessHelper.PhotoSelectOptions();
    photoSelectOptions.MIMEType = photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE;
    photoSelectOptions.maxSelectNumber = 9;

    let uris: Array<string> = [];
    const photoViewPicker = new photoAccessHelper.PhotoViewPicker();
    return photoViewPicker.select(photoSelectOptions).then((photoSelectResult: photoAccessHelper.PhotoSelectResult) => {
      uris = photoSelectResult.photoUris;
      hilog.info(DOMAIN, TAG, 'photoViewPicker.select to file succeed and uris are:' + uris);
      return ImagePickerUtils.handlerImages(uris, size);
    }).catch((err: BusinessError) => {
      hilog.error(DOMAIN, TAG, `Invoke photoViewPicker.select failed, code is ${err.code}, message is ${err.message}`);
      return Promise.reject(err.message);
    })
  }

  /**
   * 处理选择的图片, 返回base64编码
   * @param context
   * @param uris
   * @returns
   */
  public static async handlerImages(uris: Array<string>, size: number): Promise<string[]> {
    let result: string[] = [];
    if (!uris || uris.length <= 0) {
      return result;
    }
    for (let i = 0; i < uris.length; i++) {
      let photoUri = uris[i];
      try {
        const file = await fs.open(photoUri, fs.OpenMode.READ_ONLY);
        // 创建图片源
        const imageSource: image.ImageSource = image.createImageSource(file.fd);
        if (!imageSource) {
          hilog.error(DOMAIN, TAG, 'Failed to create image source');
          continue;
        }

        // 配置解码选项参数。
        let decodingOptions: image.DecodingOptions = {
          editable: true,
          desiredPixelFormat: image.PixelMapFormat.RGBA_8888,
          desiredSize: {
            width: size,
            height: size
          }
        };

        // 解码图片
        let pixelMap: image.PixelMap = await imageSource.createPixelMap(decodingOptions);

        // 创建图片包
        const imagePackerOptions: image.PackingOption = {
          format: CommonUtils.getMimeTypeFromExtension(photoUri),
          quality: 90
        };
        const imagePacker = image.createImagePacker();
        const imageData = await imagePacker.packToData(pixelMap, imagePackerOptions);
        const imgBase64 = KdbxUtils.toImgBase64Url(imageData);
        if (imgBase64) {
          result.push(imgBase64);
        }
        // 释放资源
        await pixelMap.release();
        await imagePacker.release();
        await imageSource.release();
        if(uris.length >= 2){
          CommonUtils.showToast(`${i+1} / ${uris.length}`);
        }
      } catch (error) {
        hilog.error(DOMAIN, TAG, 'Failed to handler image:' + error.message);
        CommonUtils.showToast(error.message);
      }
    }
    return result;
  }
}
