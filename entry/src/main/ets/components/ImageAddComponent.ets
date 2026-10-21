import KdbxSaveService from '../services/kdbx/KdbxSaveService';
import { FileService } from '../services/FileService';
import { KdbxUtils, ImagePickerUtils, CommonUtils } from '../common/utils';
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
  // 添加后是否自动保存数据库：图标管理页无保存按钮需自动保存（true）；
  // 图标选择弹窗内由编辑页保存按钮统一持久化，传 false 不自动保存
  autoSave: boolean = true;
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
   * 保存图标（写入内存库，含去重复用；autoSave 为 true 时追加保存数据库）
   * @param images 图片BASE64数组
   */
  private saveCustomIcon(images: string[] | null): void {
    try {
      if (!images || images.length === 0) {
        this.isUploading = false;
        return;
      }
      // 添加自定义图标到数据库（仅内存库，不触发保存）
      const uuids: string[] = KdbxSaveService.addCustomIcon(FileService.getDatabase(), images);
      if (uuids.length === 0 || uuids[0] === '') {
        this.isUploading = false;
        if (this.onError) {
          this.onError(new Error('Invalid base64 image'));
        }
        return;
      }
      if (this.autoSave) {
        // 保存数据库
        KdbxSaveService.saveDatabaseFromUi(ToastSaveDatabaseCallback.wrap({
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
      } else {
        this.isUploading = false;
        if (this.onSuccess) {
          this.onSuccess();
        }
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Save web icon failed：' + error.message);
      CommonUtils.showToast(error.message);
      this.isUploading = false;
      if (this.onError) {
        this.onError(error);
      }
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