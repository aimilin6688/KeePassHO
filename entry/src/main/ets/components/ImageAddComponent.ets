import { ImagePickerUtils } from '../common/utils/ImagePickerUtils';
import { FileService } from '../services/FileService';
import KdbxUtils from '../common/utils/KdbxUtils';
import { CommonUtils } from '../common/utils/CommonUtils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DownloadImageDialog } from './DownloadImageDialog';
import { common } from '@kit.AbilityKit';
import { ToastSaveDatabaseCallback } from '../workers/callback/ToastSaveDatabaseCallback';

const DOMAIN = 0x0000;
const TAG = 'ImageAddComponent';

/**
 * 图片添加组件
 * 统一封装图片添加功能，支持本地选择和网络下载
 */
@Component
export struct ImageAddComponent {
  // 是否正在上传
  @State isUploading: boolean = false;
  // 成功回调
  onSuccess: () => void = () => {
  };
  // 取消回调
  onCancel: () => void = () => {
  };
  // 异常回调
  onError: (error: Error) => void = () => {
  };
  private context = this.getUIContext().getHostContext() as common.UIAbilityContext;
  // 下载图片对话框控制器
  private downloadImageDialogController: CustomDialogController = new CustomDialogController({
    builder: DownloadImageDialog({
      onSuccess: (imageData: string) => {
        this.saveCustomIcon([imageData]);
      },
      onCancel: () => {
        if (this.onCancel) {
          this.onCancel();
        }
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false
  });

  /**
   * 上传自定义图片
   */
  private async uploadCustomIcon() {
    this.isUploading = true;
    ImagePickerUtils.selectImage(this.context, 64).then((images) => {
      this.saveCustomIcon(images);
    }).catch((error: Error) => {
      this.isUploading = false;
      if (this.onError) {
        this.onError(error);
      }
    });
  }

  /**
   * 保存图标
   * @param images 图片BASE64数组
   */
  private async saveCustomIcon(images: string[] | null) {
    try {
      if (!images || images.length === 0) {
        return;
      }
      // 添加自定义图标到数据库
      KdbxUtils.addCustomIcon(FileService.getDatabase(), images, ToastSaveDatabaseCallback.wrap({
        onSuccess: () => {
          this.isUploading = false;
          if (this.onSuccess) {
            this.onSuccess();
          }
        },
        onError: (error: string) => {
          this.isUploading = false;
          if (this.onError) {
            this.onError(new Error(error));
          }
        }
      }));
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Save web icon failed：' + error.message);
      CommonUtils.showToast(error.message);
      if (this.onError) {
        this.onError(error);
      }
    } finally {
      this.isUploading = false;
    }
  }

  @Builder
  AddMenu() {
    Menu() {
      MenuItem({
        startIcon: $r('app.media.ic_add'),
        content: $r('app.string.add_from_local'),
      }).onClick(() => {
        this.uploadCustomIcon();
      })
      MenuItem({
        startIcon: $r('app.media.ic_download'),
        content: $r('app.string.add_from_web'),
      }).onClick(() => {
        this.downloadImageDialogController.open();
      })
    }
    .subMenuExpandingMode(SubMenuExpandingMode.EMBEDDED_EXPAND)
    .backgroundColor($r("app.color.bg_secondary"))
    .fontColor($r('app.color.text_primary'))
  }

  build() {
    Image($r('app.media.ic_add'))
      .enabled(!this.isUploading)
      .bindMenu(this.AddMenu)
      .fillColor($r('app.color.text_primary'))
  }
}