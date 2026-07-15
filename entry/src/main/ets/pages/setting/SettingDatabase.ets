import { KdbxUuid } from 'kdbxweb';
import { CipherId } from 'kdbxweb/src/main/ets/defs/consts';
import { CommonUtils, KdbxUtils, NavigationManager, ResourceManager } from '../../common/utils';
import { PageConstants } from '../../common/constants/PageConstants';
import { FileService } from '../../services/FileService';
import { ExportType } from '../../services/TypeDefined';
import {
  ImportExportViewModel,
  registerDefaultHandlers,
  FormatInfo
} from '../../services/importExport';
import { LocationParam, LocationInfo, LocationMode } from '../../services/beans/LocationParam';
import { SettingDialogWrapper } from '../../components/SettingDialogWrapper';
import { SettingDatabaseKeyFunctionContent } from './SettingDatabaseKeyFunction';
import { SettingDatabaseMetaContent } from './SettingDatabaseMeta';
import { SettingCustomIconsContent } from './SettingCustomIcons';
import { SettingDatabaseProtectedFiledContent } from './SettingDatabaseProtectedFiled';

// 对话框类型枚举
enum DialogType {
  NONE = 0,
  KEY_FUNCTION = 1,
  META = 2,
  CUSTOM_ICONS = 3,
  PROTECTED_FIELDS = 4
}

// SettingDatabase页面的Builder函数
@Builder
export function SettingDatabaseBuilder(name: string, param: Object): void {
  NavDestination() {
    SettingDatabaseContent()
  }
  .title($r('app.string.Settings_database'))
  .backgroundColor($r('app.color.bg_primary'))
}

/**
 * 格式选择选项
 */
interface FormatSelectOption {
  value: string;
  formatId: string;
}

@Component
struct SettingDatabaseContent {
  private navManager: NavigationManager = NavigationManager.getInstance();
  private navPathStack: NavPathStack = NavigationManager.getInstance().getNavPathStack()!;
  @State isDatabaseValid: boolean = false;
  @State algorithmType: ResourceStr = ResourceManager.getString($r("app.string.please_select"));

  // 新架构
  @State importFormats: FormatInfo[] = [];
  @State exportFormats: FormatInfo[] = [];
  @State isLoading: boolean = false;

  // 弹框控制器 - 使用统一的对话框类型
  @State currentDialogType: DialogType = DialogType.NONE;

  private promptAction = this.getUIContext().getPromptAction();
  private viewModel: ImportExportViewModel = new ImportExportViewModel();

  aboutToAppear(): void {
    // 注册处理器
    registerDefaultHandlers();

    // 获取支持的格式
    this.importFormats = this.viewModel.getImportFormatOptions();
    this.exportFormats = this.viewModel.getExportFormatOptions();

    // 检查数据库是否有效
    const dbFileParam = FileService.getDbFileParam();
    this.isDatabaseValid = dbFileParam && dbFileParam.database !== undefined;
    if (this.isDatabaseValid) {
      this.algorithmType =
        this.algorithmOptions[this.algorithmOptions.findIndex((item) => item.type === dbFileParam.database.header.dataCipherUuid?.id)].value;
    }
  }

  // 导入数据库
  private startImport(formatId: string): void {
    const extensions = this.viewModel.getFileExtensions(formatId);

    LocationParam.of({
      mode: LocationMode.SELECT,
      fileSuffix: extensions,
      onLocation: (location: LocationInfo) => this.doImport(location)
    });
    this.navPathStack.pushPathByName(PageConstants.PAGE_SELECT_LOCATION, null);
  }

  private async doImport(location: LocationInfo): Promise<void> {
    this.isLoading = true;

    const success = await this.viewModel.executeImport(location);

    this.isLoading = false;

    if (success) {
      CommonUtils.showToast(`导入成功，共 ${this.viewModel.lastImportedCount} 条记录`);
      this.navPathStack.pop();
    } else {
      CommonUtils.showToast(this.viewModel.errorMessage);
    }
  }

  // 导出数据库
  private startExport(formatId: string): void {
    const fileName = this.viewModel.getExportFileName(formatId);

    LocationParam.of({
      mode: LocationMode.SAVE,
      fileName: fileName,
      onLocation: (location: LocationInfo) => this.doExport(formatId, location)
    });
    this.navPathStack.pushPathByName(PageConstants.PAGE_SELECT_LOCATION, null);
  }

  private async doExport(formatId: string, location: LocationInfo): Promise<void> {
    this.isLoading = true;

    const success = await this.viewModel.executeExport(formatId, location);

    this.isLoading = false;

    if (success) {
      CommonUtils.showToast('导出成功');
      this.navPathStack.pop();
    } else {
      CommonUtils.showToast(this.viewModel.errorMessage);
    }
  }

  // 重新加密算法
  private resetDatabaseAlgorithm(algorithmId: string) {
    FileService.getDatabase().header.dataCipherUuid = new KdbxUuid(algorithmId);
    // 保存数据库
    KdbxUtils.saveDatabase();
  }

  // 加密算法选项
  private algorithmOptions: Array<AlgorithmOptions> = [
    { value: $r('app.string.Settings_database_algorithm_aes'), type: CipherId.Aes },
    { value: $r('app.string.Settings_database_algorithm_chacha20'), type: CipherId.ChaCha20 }
  ];

  build() {
    Column() {
      // 设置内容（弹框中显示，无需导航栏）

      List() {
        // 密码相关功能
        if (this.isDatabaseValid) {
          ListItemGroup() {
            // 修改主密码
            ListItem() {
              Row() {
                Text($r("app.string.change_password"))
                  .fontSize(16)
                  .flexGrow(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                CommonUtils.pushUrl({ url: 'pages/ChangePassword' });
              })
            }

            // 数据库算法
            ListItem() {
              Row() {
                Text($r("app.string.Settings_database_algorithm"))
                  .fontSize(16)
                  .flexGrow(1)
                Blank()
                Column() {
                  Select(this.algorithmOptions)
                    .value(this.algorithmType)
                    .font({ size: 16 })
                    .selectedOptionFont({ size: 16 })
                    .optionFont({ size: 16 })
                    .backgroundColor($r("app.color.card_bg"))
                    .onSelect(async (index: number) => {
                      this.resetDatabaseAlgorithm(this.algorithmOptions[index].type);
                    })
                    .padding({ right: 0 })
                }.width('70%')
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding({
                left: 16,
                right: 16,
                top: 9,
                bottom: 9
              })
            }

            // 密钥派生函数
            ListItem() {
              Row() {
                Text($r("app.string.Settings_database_encryption_key"))
                  .fontSize(16)
                  .flexGrow(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                this.currentDialogType = DialogType.KEY_FUNCTION;
              })
            }
          }
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(12)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
          })

          // 数据库元数据设置
          ListItemGroup() {
            ListItem() {
              Row() {
                Text($r("app.string.Settings_database_metadata"))
                  .fontSize(16)
                  .flexGrow(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                this.currentDialogType = DialogType.META;
              })
            }

            // 自定义图标
            ListItem() {
              Row() {
                Text($r("app.string.Settings_custom_icons"))
                  .fontSize(16)
                  .flexGrow(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                this.currentDialogType = DialogType.CUSTOM_ICONS;
              })
            }

            // 默认保护字段
            ListItem() {
              Row() {
                Text($r("app.string.Settings_default_protected_field"))
                  .fontSize(16)
                  .flexGrow(1)
                Image($r('app.media.ic_arrow_right'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.text_primary'))
              }
              .width('100%')
              .padding(16)
              .onClick(() => {
                this.currentDialogType = DialogType.PROTECTED_FIELDS;
              })
            }
          }
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(12)
          .divider({
            strokeWidth: 1,
            color: $r('app.color.divider'),
          })


          // 数据库导出
          ListItemGroup() {
            ListItem() {
              Row() {
                Text($r("app.string.Settings_database_import"))
                  .fontSize(16)
                  .flexGrow(1)
                Blank()
                Column() {
                  Select(this.importFormats.map((f: FormatInfo): FormatSelectOption => ({ value: f.formatName, formatId: f.formatId })))
                    .value($r("app.string.please_select"))
                    .font({ size: 16 })
                    .selectedOptionFont({ size: 16 })
                    .optionFont({ size: 16 })
                    .backgroundColor($r("app.color.card_bg"))
                    .onSelect(async (index: number) => {
                      this.startImport(this.importFormats[index].formatId);
                    })
                    .padding({ right: 0 })
                }
                .width('70%')
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding({
                left: 16,
                right: 16,
                top: 9,
                bottom: 9
              })
            }

            ListItem() {
              Row() {
                Text($r("app.string.Settings_database_export"))
                  .fontSize(16)
                  .flexGrow(1)
                Blank()
                Column() {
                  Select(this.exportFormats.map((f: FormatInfo): FormatSelectOption => ({ value: f.formatName, formatId: f.formatId })))
                    .value($r("app.string.please_select"))
                    .font({ size: 16 })
                    .selectedOptionFont({ size: 16 })
                    .optionFont({ size: 16 })
                    .backgroundColor($r("app.color.card_bg"))
                    .onSelect(async (index: number) => {
                      this.startExport(this.exportFormats[index].formatId);
                    })
                    .padding({ right: 0 })
                }
                .width('70%')
                .alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding({
                left: 16,
                right: 16,
                top: 9,
                bottom: 9
              })
            }
          }
          .margin({ top: 12, bottom: 12 })
          .backgroundColor($r("app.color.card_bg"))
          .borderRadius(12)
          .divider({ strokeWidth: 1, color: $r('app.color.divider') })
        } else {
          ListItem() {
            Text($r('app.string.database_not_opened'))
              .fontSize(16)
              .margin({ top: 20, bottom: 12 })
              .textAlign(TextAlign.Center)
              .width('100%')
              .fontColor($r('app.color.text_secondary'))
          }
        }
      }
      .width('100%')
      .height('auto')
      .layoutWeight(1)
      .padding({ left: 12, right: 12, top: 4 })
      .clipContent(ContentClipMode.SAFE_AREA)
    }
      .width('100%')
      .height('100%')
      .backgroundColor($r("app.color.bg_primary"))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindSheet(this.currentDialogType !== DialogType.NONE, this.DialogBuilder(), {
        height: SheetSize.FIT_CONTENT,
        backgroundColor: Color.Transparent,
        dragBar: false,
        onDisappear: () => { this.currentDialogType = DialogType.NONE; }
      })
  }

  @Builder
  DialogBuilder() {
    if (this.currentDialogType === DialogType.KEY_FUNCTION) {
      SettingDialogWrapper({
        title: $r('app.string.Settings_database_encryption_key'),
        context: this.getUIContext(),
        onClose: () => { this.currentDialogType = DialogType.NONE; }
      }) {
        SettingDatabaseKeyFunctionContent({ onClose: () => { this.currentDialogType = DialogType.NONE; } })
      }
    } else if (this.currentDialogType === DialogType.META) {
      SettingDialogWrapper({
        title: $r('app.string.Settings_database_metadata'),
        context: this.getUIContext(),
        onClose: () => { this.currentDialogType = DialogType.NONE; }
      }) {
        SettingDatabaseMetaContent({ onClose: () => { this.currentDialogType = DialogType.NONE; } })
      }
    } else if (this.currentDialogType === DialogType.CUSTOM_ICONS) {
      SettingDialogWrapper({
        title: $r('app.string.Settings_custom_icons'),
        context: this.getUIContext(),
        onClose: () => { this.currentDialogType = DialogType.NONE; }
      }) {
        SettingCustomIconsContent()
      }
    } else if (this.currentDialogType === DialogType.PROTECTED_FIELDS) {
      SettingDialogWrapper({
        title: $r('app.string.Settings_default_protected_field'),
        context: this.getUIContext(),
        onClose: () => { this.currentDialogType = DialogType.NONE; }
      }) {
        SettingDatabaseProtectedFiledContent()
      }
    }
  }
}

export interface AlgorithmOptions {
  value: ResourceStr;
  type: string;
}
