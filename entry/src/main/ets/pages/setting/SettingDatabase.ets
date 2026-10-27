import KdbxSaveService from '../../services/kdbx/KdbxSaveService';
import { KdbxUuid } from 'kdbxweb';
import { CipherId } from 'kdbxweb/src/main/ets/defs/consts';
import { CommonUtils, KdbxUtils, NavigationManager, ResourceManager } from '../../common/utils';
import { PageConstants } from '../../common/constants/PageConstants';
import { FileService } from '../../services/FileService';
import { ExportType } from '../../services/TypeDefined';
import {
  ImportExportViewModel,
  registerDefaultHandlers,
  FormatInfo,
  ImportFormatGroupInfo,
  ImportSubFormatInfo,
  ImportExportErrorCode
} from '../../services/importExport';
import { LocationParam, LocationInfo, LocationMode } from '../../services/beans/LocationParam';
import { SettingsService } from '../../services/SettingsService';
// SettingDatabase页面的Builder函数
@Builder
export function SettingDatabaseBuilder(name: string, param: Object): void {
  SettingDatabasePage()
}

@Component
struct SettingDatabasePage {
  build() {
    NavDestination() {
      SettingDatabaseContent()
    }
    .title($r('app.string.Settings_database'))
    .backgroundColor($r('app.color.bg_primary'))
  }
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

  // 导入格式提示（单一数据源 catalog，见 docs/import-format-hints-design.md）
  @State importCatalog: ImportFormatGroupInfo[] = [];
  @State csvSourceCount: number = 0;
  @State jsonSourceCount: number = 0;
  @State showImportFormatHelp: boolean = false;
  private jsonFormatNames: string[] = [];
  private selectedImportFormatId: string = '';

  private promptAction = this.getUIContext().getPromptAction();
  private viewModel: ImportExportViewModel = new ImportExportViewModel();

  aboutToAppear(): void {
    // 注册处理器
    registerDefaultHandlers();

    // 获取支持的格式
    this.importFormats = this.viewModel.getImportFormatOptions();
    this.exportFormats = this.viewModel.getExportFormatOptions();

    // 导入格式清单（帮助面板 + 副标题摘要 + JSON 失败引导共用）
    this.importCatalog = this.viewModel.getImportFormatCatalog();
    const csvGroup = this.findCatalogGroup('CSV');
    if (csvGroup !== null) {
      let knownCount = 0;
      for (const format of csvGroup.formats) {
        if (format.formatId !== 'GENERIC_CSV') {
          knownCount++;
        }
      }
      this.csvSourceCount = knownCount;
    }
    const jsonGroup = this.findCatalogGroup('JSON');
    if (jsonGroup !== null) {
      this.jsonSourceCount = jsonGroup.formats.length;
      this.jsonFormatNames = [];
      for (const format of jsonGroup.formats) {
        this.jsonFormatNames.push(format.formatName);
      }
    }

    // 检查数据库是否有效
    const dbFileParam = FileService.getDbFileParam();
    this.isDatabaseValid = dbFileParam && dbFileParam.database !== undefined;
    if (this.isDatabaseValid) {
      this.algorithmType =
        this.algorithmOptions[this.algorithmOptions.findIndex((item) => item.type === dbFileParam.database.header.dataCipherUuid?.id)].value;
    }
  }

  /** 按分组标识查 catalog 分组 */
  private findCatalogGroup(groupId: string): ImportFormatGroupInfo | null {
    for (const group of this.importCatalog) {
      if (group.groupId === groupId) {
        return group;
      }
    }
    return null;
  }

  // 导入数据库
  private startImport(formatId: string): void {
    this.selectedImportFormatId = formatId;
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
      if (this.viewModel.lastImportFormatName !== '') {
        CommonUtils.showToast(ResourceManager.getString(
          $r('app.string.import_success_with_format'),
          this.viewModel.lastImportFormatName,
          this.viewModel.lastImportedCount
        ));
      } else {
        CommonUtils.showToast(`导入成功，共 ${this.viewModel.lastImportedCount} 条记录`);
      }
      this.navPathStack.pop();
    } else if (this.isJsonUnsupportedError()) {
      this.showJsonUnsupportedDialog();
    } else {
      CommonUtils.showToast(this.viewModel.errorMessage);
    }
  }

  /** JSON 导入未识别结构（用户所选顶层格式 + 错误码联合判定，见设计文档 §4.3） */
  private isJsonUnsupportedError(): boolean {
    return this.selectedImportFormatId === 'JSON'
      && (this.viewModel.lastErrorCode === ImportExportErrorCode.INVALID_FILE_FORMAT
        || this.viewModel.lastErrorCode === ImportExportErrorCode.INVALID_JSON_FORMAT);
  }

  /** JSON 未识别引导弹窗：内嵌支持清单（格式名从 catalog 动态取，不硬编码） */
  private showJsonUnsupportedDialog(): void {
    const firstName = this.jsonFormatNames.length > 0 ? this.jsonFormatNames[0] : 'Bitwarden JSON';
    const secondName = this.jsonFormatNames.length > 1 ? this.jsonFormatNames[1] : 'Proton Pass JSON';
    this.promptAction.showDialog({
      title: ResourceManager.getString($r('app.string.import_json_unsupported_title')),
      message: ResourceManager.getString(
        $r('app.string.import_json_unsupported_message'),
        firstName,
        secondName
      ),
      buttons: [
        {
          text: ResourceManager.getString($r('app.string.import_json_unsupported_confirm')),
          color: $r('app.color.button_bg_blue')
        }
      ]
    }).catch((error: Error) => {
      CommonUtils.showToast(error?.message);
    });
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
    KdbxSaveService.saveDatabaseFromUi();
  }

  // 加密算法选项
  private algorithmOptions: Array<AlgorithmOptions> = [
    { value: $r('app.string.Settings_database_algorithm_aes'), type: CipherId.Aes },
    { value: $r('app.string.Settings_database_algorithm_chacha20'), type: CipherId.ChaCha20 }
  ];

  /** 「支持的导入格式」帮助面板（半模态，数据全部来自 catalog，见设计文档 §4.1） */
  @Builder
  private importFormatHelpBuilder() {
    Scroll() {
      Column({ space: 12 }) {
        ForEach(this.importCatalog, (group: ImportFormatGroupInfo) => {
          Column({ space: 8 }) {
            Text(group.groupLabel)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.text_primary'))
            Text(group.description)
              .fontSize(13)
              .fontColor($r('app.color.text_secondary'))
            Flex({ wrap: FlexWrap.Wrap }) {
              ForEach(group.formats, (format: ImportSubFormatInfo) => {
                Text(format.formatName)
                  .fontSize(13)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r('app.color.bg_primary'))
                  .borderRadius(14)
                  .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                  .margin({ right: 8, bottom: 8 })
              }, (format: ImportSubFormatInfo) => format.formatId)
            }
            .width('100%')

            // 补充说明（通用 CSV 兜底条目）
            ForEach(group.formats, (format: ImportSubFormatInfo) => {
              if (format.note !== '') {
                Text(format.note)
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
              }
            }, (format: ImportSubFormatInfo) => `note-${format.formatId}`)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .backgroundColor($r('app.color.card_bg'))
          .borderRadius(12)
          .padding(16)
        }, (group: ImportFormatGroupInfo) => group.groupId)
      }
      .width('100%')
      .padding(16)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height('100%')
    .align(Alignment.TopStart)
    .backgroundColor($r('app.color.bg_primary'))
  }

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
                // 导航到修改主密码页面（右侧分栏展示）
                this.navPathStack.pushPathByName(PageConstants.PAGE_CHANGE_PASSWORD, null);
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
                // 与修改主密码一致：导航到独立页面而非弹框
                this.navManager.navigateTo(PageConstants.PAGE_SETTING_DATABASE_KEY_FUNCTION);
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
                // 导航到数据库元数据设置页面（右侧分栏展示）
                this.navPathStack.pushPathByName(PageConstants.PAGE_SETTING_DATABASE_META, null);
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
                // 导航到自定义图标管理页面（右侧分栏展示）
                this.navPathStack.pushPathByName(PageConstants.PAGE_SETTING_CUSTOM_ICONS, null);
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
                // 导航到默认保护字段设置页面（右侧分栏展示）
                this.navPathStack.pushPathByName(PageConstants.PAGE_SETTING_DATABASE_PROTECTED_FIELD, null);
              })
            }

            // 清理数据库
            ListItem() {
              Row() {
                Text($r("app.string.Settings_clean_database"))
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
                // 导航到清理数据库页面（右侧分栏展示）
                this.navPathStack.pushPathByName(PageConstants.PAGE_SETTING_DATABASE_CLEAN, null);
              })
            }

            // 子数据库管理（子数据库功能禁用时隐藏）
            if (SettingsService.isChildDbEnable()) {
              ListItem() {
                Row() {
                  Text($r("app.string.child_dbs_title"))
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
                  // 导航到子数据库管理页面（右侧分栏展示）
                  this.navPathStack.pushPathByName(PageConstants.PAGE_CHILD_DATABASES, null);
                })
              }
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
              Column() {
                Row() {
                  Text($r("app.string.Settings_database_import"))
                    .fontSize(16)
                    .flexGrow(1)
                  Image($r('app.media.ic_help_outline'))
                    .width(18)
                    .height(18)
                    .fillColor($r('app.color.text_secondary'))
                    .margin({ right: 8 })
                    .onClick(() => {
                      this.showImportFormatHelp = true;
                    })
                  Column() {
                    Select(this.importFormats.map((f: FormatInfo): FormatSelectOption => ({ value: this.viewModel.displayImportFormatLabel(f.formatId), formatId: f.formatId })))
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
                  .width('60%')
                  .alignItems(HorizontalAlign.End)
                }
                .width('100%')
                .padding({
                  left: 16,
                  right: 16,
                  top: 9,
                  bottom: 9
                })

                // 副标题：支持格式摘要（数量从 catalog 动态统计）
                Text(ResourceManager.getString(
                  $r('app.string.import_entry_format_hint'),
                  this.csvSourceCount,
                  this.jsonSourceCount
                ))
                  .fontSize(12)
                  .fontColor($r('app.color.text_secondary'))
                  .width('100%')
                  .padding({ left: 16, right: 16, bottom: 12 })
              }
              .width('100%')
              .bindSheet($$this.showImportFormatHelp, this.importFormatHelpBuilder(), {
                title: { title: ResourceManager.getString($r('app.string.import_format_help_title')) },
                height: SheetSize.MEDIUM,
                dragBar: true,
                showClose: true
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
  }
}

export interface AlgorithmOptions {
  value: ResourceStr;
  type: string;
}
