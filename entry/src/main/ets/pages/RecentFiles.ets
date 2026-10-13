import { PromptAction } from '@kit.ArkUI';
import { RecentFilesService } from '../services/RecentFilesService';
import { RecentFile } from '../services/TypeDefined';

import { hilog } from '@kit.PerformanceAnalysisKit';
import { common } from '@kit.AbilityKit';
import { CommonUtils, ConfigDecryptError, NavigationManager, WindowUtils } from '../common/utils';
import { FileStorage, PageConfig, StorageType } from '../storage';
import { LoadingDialog } from '../components/loading/LoadingDialogUtils';
import { Constants } from '../common/constants/Constants';
import { DataService } from '../services/DataService';

const DOMAIN = 0x0000;
const TAG = 'RecentFiles';

// 定义导航参数接口
interface PasswordNavParam {
  filePath: string;
}

// RecentFiles页面的Builder函数
@Builder
export function RecentFilesBuilder(name: string, param: Object): void {
  RecentFilesPage({
    source: (param as Record<string, string>)?.source || 'home'
  })
}

/**
 * 最近打开页面容器
 * 标题栏右侧通过 menus 自定义"清除全部"
 */
@Component
struct RecentFilesPage {
  @Prop source: string = 'home';
  // 点击"清除全部"自增，触发内容区弹出确认并清空
  @State clearSignal: number = 0;

  @Builder
  MenuBuilder() {
    Row() {
      Text($r('app.string.clear_all_button'))
        .fontSize(14)
        .fontColor('#E84026')
    }
    .height('100%')
    .padding({ right: 16 })
    .justifyContent(FlexAlign.Center)
    .onClick(() => {
      this.clearSignal++;
    })
  }

  build() {
    NavDestination() {
      RecentFilesContent({
        source: this.source,
        clearSignal: this.clearSignal
      })
    }
    .title($r('app.string.recent_files'))
    .menus(this.MenuBuilder)
    .backgroundColor($r('app.color.bg_primary'))
  }
}

@Component
struct RecentFilesContent {
  @Prop source: string = 'home';
  // 标题栏"清除全部"点击信号（由 Page 驱动）
  @Prop @Watch('onClearSignal') clearSignal: number = 0;
  private navManager = NavigationManager.getInstance();
  @State recentFiles: RecentFile [] = [];
  @State isLoading: boolean = true;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private allStorageConfig: Array<PageConfig> = FileStorage.getAllPageConfig();

  aboutToAppear() {
    this.loadRecentFiles();
  }

  /**
   * 标题栏"清除全部"触发：弹确认框后清空列表
   */
  onClearSignal(): void {
    CommonUtils.showConfirmDialog(this.getUIContext(), $r('app.string.dialog_confirm_title'), $r('app.string.confirm_clear_all_records_tips'), {
      onConfirm: () => {
        this.clearAllRecords();
      }
    });
  }

  onPageShow(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  /**
   * 加载最近打开的文件列表
   */
  async loadRecentFiles() {
    try {
      this.isLoading = true;
      this.recentFiles = await RecentFilesService.getRecentFiles();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'load recent file error: %{public}s', error.message);
      CommonUtils.showToast({
        message: $r('app.string.load_recent_files_failed'),
        duration: 2000
      });
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 打开选中的文件
   * @param filePath 文件路径
   * @param fileName 文件名
   */
  async openFile(recentFile: RecentFile) {
    LoadingDialog.showLoading($r('app.string.loading_message'));
    let recentFilesService: RecentFilesService = RecentFilesService.getInstance();
    let errorMessage: string = '';
    let decryptFailed: boolean = false;
    // 检查文件是否存在
    const fileExists = await recentFilesService.checkFileExists(recentFile).catch((e: Error) => {
      hilog.error(DOMAIN, TAG, 'check file exists error: %{public}s', e.message);
      errorMessage = e.message;
      decryptFailed = e instanceof ConfigDecryptError;
    });
    LoadingDialog.hideLoading();
    // 存储配置解密失败（密钥变更，密文不可恢复）：保留记录，引导重新编辑连接配置
    if (decryptFailed) {
      this.showReEditConfigGuide(recentFile.storageType);
      return;
    }
    if (!fileExists) {
      CommonUtils.showToast({
        message: errorMessage || $r('app.string.file_not_exists'),
        duration: 2000
      });
      CommonUtils.showConfirmDialog(this.getUIContext(), $r('app.string.dialog_confirm_title'), $r('app.string.confirm_remove_record_tips'), {
        onConfirm: async () => {
          // 移除不存在的文件记录
          await recentFilesService.removeRecentFile(recentFile);
          // 重新加载列表
          this.loadRecentFiles();
        }
      });
      return;
    } else {
      // 使用整个窗口方式打开数据库（清空当前导航栈）
      // 清除可能残留的位置信息（如上次通过 URL 打开后未消费），避免 Password 页面优先读到旧库信息
      AppStorage.delete(Constants.APP_STORAGE_LOCATION_INFO);
      const navParam: PasswordNavParam = { filePath: recentFile.filePath };
      this.navManager.replaceAll('Password', navParam);
    }
  }

  /**
   * 存储配置解密失败引导：弹框确认后跳转对应存储的连接配置页，
   * 用户重新填写连接信息并再次选中该文件后，最近记录会被新配置覆盖（见 DataService.toPasswordPage）
   */
  private showReEditConfigGuide(storageType: StorageType): void {
    this.getUIContext().showAlertDialog({
      title: $r('app.string.dialog_prompt_title'),
      message: $r('app.string.storage_config_decrypt_failed'),
      autoCancel: true,
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.re_edit_connection_config'),
        action: () => {
          DataService.reEditStorageConfig(storageType);
        }
      }
    });
  }

  /**
   * 清除所有记录
   */
  async clearAllRecords() {
    try {
      await RecentFilesService.getInstance().clearRecentFiles();
      this.recentFiles = [];
      CommonUtils.showToast({
        message: $r('app.string.all_records_cleared'),
        duration: 2000
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'clear records error: %{public}s', error.message);
      CommonUtils.showToast({
        message: $r('app.string.clear_records_failed'),
        duration: 2000
      });
    }
  }

  /**
   * 移除单个记录
   * @param filePath 文件路径
   */
  async removeRecord(recentFile: RecentFile) {
    try {
      await RecentFilesService.getInstance().removeRecentFile(recentFile);
      // 重新加载列表
      this.loadRecentFiles();
      CommonUtils.showToast({
        message: $r('app.string.record_removed'),
        duration: 2000
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'remove records error: %{public}s', error.message);
      CommonUtils.showToast({
        message: $r('app.string.remove_record_failed'),
        duration: 2000
      });
    }
  }

  private getStorageTypeIcon(storageType: string): ResourceStr {
    for (let i = 0; i < this.allStorageConfig.length; i++) {
      if (this.allStorageConfig[i].storageType === storageType) {
        return this.allStorageConfig[i].icon;
      }
    }
    return $r('app.media.ic_file');
  }

  build() {
    Column() {
      // 文件列表
      if (this.isLoading) {
        LoadingProgress()
          .width(50)
          .height(50)
      } else if (this.recentFiles.length === 0) {
        Column() {
          Image($r('app.media.ic_empty'))
            .width(100)
            .height(100)
            .margin({ bottom: 16 })
            .fillColor(Color.Gray)
          Text($r('app.string.no_recent_files'))
            .fontSize(16)
            .fontColor(Color.Gray)
        }
        .width('100%')
        .height('80%')
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.recentFiles, (file: RecentFile) => {
            ListItem() {
              Row() {
                Image(this.getStorageTypeIcon(file.storageType))
                  .width(32)
                  .height(32)
                  .fillColor($r('app.color.text_primary'))
                  .margin({ right: 16 })
                Column() {
                  Text(file.fileName)
                    .fontSize(16)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .fontWeight(FontWeight.Medium)
                    .maxLines(1)
                    .margin({ bottom: 4 })
                  Text(file.storageType + ": " + file.filePath)
                    .fontSize(14)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .maxLines(1)
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Button() {
                  Image($r('app.media.ic_delete'))
                    .width(24)
                    .height(24)
                    .fillColor($r('app.color.text_primary'))
                }
                .backgroundColor(Color.Transparent)
                .onClick(() => {
                  CommonUtils.showDeleteConfirm(this.getUIContext(), {
                    onConfirm: () => {
                      this.removeRecord(file);
                    }
                  });
                })
              }
              .width('100%')
              .height(60)
              .padding({ left: 10, right: 10 })
              .borderRadius(8)
              .backgroundColor($r("app.color.card_bg"))
                .onClick(() => {
                  this.openFile(file);
                })
              }
              .id('recent_file_item')
              .margin({ bottom: 8 })
          })
        }
        .width('100%')
        .height('100%')
        .layoutWeight(1)
        .padding({
          left: 12,
          right: 12,
          top: 4
        })
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
