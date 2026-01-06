import { PromptAction, Router } from '@kit.ArkUI';
import { FileInfo, FileType } from '../../storage';
import { KdbxFileManager } from '../../services/kdbx/KdbxFileManager';
import { DateUtils, FileUtils, ResourceManager } from '../../common/utils';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { LocationInfo, LocationMode, LocationParam } from '../../services/beans/LocationParam';
import { BasicDataSource } from '../../services/beans/BasicDataSource';
import { UrlUtils } from '../../common/utils/UrlUtils';
import { FilenameUtils } from '../../common/utils/FilenameUtils';

const DOMAIN = 0x0000;
const TAG = 'FileList';


export interface PathPart {
  name: string;
  path: string;
}

export class FileListDataSource extends BasicDataSource<FileInfo> {
  private dataArray: FileInfo[] = [];

  public totalCount(): number {
    return this.dataArray.length;
  }

  public getData(index: number): FileInfo {
    return this.dataArray[index];
  }

  public getAll(): FileInfo[] {
    return this.dataArray;
  }

  public pushData(data: FileInfo): void {
    this.dataArray.push(data);
    this.notifyDataAdd(this.dataArray.length - 1);
  }

  public clear(): void {
    this.dataArray = [];
    this.notifyDataReload();
  }
}

@Entry
@Component
struct FileList {
  @State currentPath: string = '/';
  @State itemData: FileListDataSource = new FileListDataSource();
  @State isLoading: boolean = false;
  @State isError: boolean = false;
  @State errorMessage: string = '';
  @State sortType: 'name' | 'date' | 'size' = 'name';
  @State sortOrder: 'asc' | 'desc' = 'asc';
  @State pathLength: number = 0;
  @State showSortMenu: boolean = false; // 添加状态控制排序菜单显示
  @State isEnableConfirm: boolean = false;
  @State selectFileIndex: number = -1;
  @State saveFileName: string = '';
  @State fileSuffix: string[] = [];
  private router: Router = this.getUIContext().getRouter();
  private locationInfo: LocationInfo | undefined = undefined;
  private pathScroller: Scroller = new Scroller();
  private dataCache: Map<string, Array<FileInfo>> = new Map();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();

  aboutToAppear(): void {
    const params = this.router.getParams() as LocationInfo;
    if (params) {
      this.locationInfo = params;
      this.currentPath = this.getLocationPath();
      hilog.debug(DOMAIN, TAG, 'currentPath: %{public}s', this.currentPath);
      this.saveFileName = this.locationInfo?.fileName || '';
      this.fileSuffix = this.locationInfo?.fileSuffix || [];
      this.loadItems(this.currentPath);
    } else {
      this.showError();
    }
  }

  private isSaveMode(): boolean {
    return this.locationInfo?.mode === LocationMode.SAVE;
  }

  private isSelectMode(): boolean {
    return this.locationInfo?.mode === LocationMode.SELECT;
  }

  /**
   * 获取当前目录路径
   */
  private getLocationPath(): string {
    if (!this.locationInfo) {
      return "/";
    }
    const filePath = this.locationInfo.filePath;
    return filePath.replace(UrlUtils.getHost(filePath), "");
  }

  private async loadItems(path: string) {
    if (!this.locationInfo) {
      return;
    }

    this.isLoading = true;
    this.isError = false;
    this.errorMessage = '';

    try {
      // 获取目录内容
      let items = this.dataCache.get(path);
      if (items === undefined) {
        items = await KdbxFileManager.of(this.locationInfo).listDir(path);
        this.dataCache.set(path, items || []);
      }
      items = this.filterFile(items);
      this.sortItems(items);
      this.itemData.clear();
      items.forEach(item => {
        this.itemData.pushData(item);
      });
      if (this.locationInfo.mode === LocationMode.SAVE) {
        this.isEnableConfirm = true;
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load file items: %{public}s', error.message);
      this.errorMessage = error.message;
      this.isError = true;
    } finally {
      this.isLoading = false;
    }
  }

  private filterFile(items: Array<FileInfo>): Array<FileInfo> {
    if (this.isSelectMode() && this.fileSuffix.length > 0) {
      return items.filter(item => {
        return item.type === FileType.DIR || FilenameUtils.hasSuffix(item.name, this.fileSuffix);
      });
    }
    return items;
  }

  private sortItems(items: Array<FileInfo>) {
    items.sort((a, b) => {
      // 文件夹始终排在文件前面
      if (a.type !== b.type) {
        return a.type === FileType.DIR ? -1 : 1;
      }

      let result = 0;
      switch (this.sortType) {
        case 'name':
          result = a.name.localeCompare(b.name);
          break;
        case 'date':
          const dateA = a.modifiedTime || 0;
          const dateB = b.modifiedTime || 0;
          result = dateA - dateB;
          break;
        case 'size':
          const sizeA = a.size || 0;
          const sizeB = b.size || 0;
          result = sizeA - sizeB;
          break;
      }
      return this.sortOrder === 'asc' ? result : -result;
    });
  }

  private changeSort(type: 'name' | 'date' | 'size') {
    if (this.sortType === type) {
      // 切换排序顺序
      this.sortOrder = this.sortOrder === 'asc' ? 'desc' : 'asc';
    } else {
      // 更改排序类型，默认升序
      this.sortType = type;
      this.sortOrder = 'asc';
    }
    this.sortItems(this.itemData.getAll());
    this.itemData.notifyDataReload();
    this.showSortMenu = false; // 关闭菜单
  }

  private navigateToPath(path: string) {
    this.currentPath = path;
    this.selectFileIndex = -1;
    if (this.isSaveMode()) {
      this.isEnableConfirm = true;
    }
    this.loadItems(path);
    this.pathScroller.scrollEdge(Edge.End);
  }

  private handleItemClick(item: FileInfo, selectIndex: number) {
    // 选择目录
    if (item.type === FileType.DIR) {
      this.navigateToPath(item.path);
    }
    // 选择文件
    else if (item.type === FileType.FILE && this.isSelectMode()) {
      if (this.selectFileIndex === selectIndex) {
        this.selectFileIndex = -1;
        this.isEnableConfirm = false;
      } else {
        this.selectFileIndex = selectIndex;
        this.isEnableConfirm = true;
      }
    }
  }

  private formatFileSize(size: number | undefined): string {
    if (size === undefined) {
      return '-';
    }
    if (size < 1024) {
      return size + ' B';
    } else if (size < 1024 * 1024) {
      return (size / 1024).toFixed(1) + ' KB';
    } else if (size < 1024 * 1024 * 1024) {
      return (size / (1024 * 1024)).toFixed(1) + ' MB';
    } else {
      return (size / (1024 * 1024 * 1024)).toFixed(1) + ' GB';
    }
  }

  private getPathParts(): Array<PathPart> {
    const result: Array<PathPart> = [{ name: "$", path: "/" }];
    if (this.currentPath === '/') {
      this.pathLength = 1;
      return result;
    }

    const parts = this.currentPath.split('/').filter(part => part.length > 0);
    let currentPath = '';
    parts.forEach(part => {
      currentPath += '/' + part;
      result.push({ name: decodeURIComponent(part), path: currentPath + (currentPath.endsWith('/') ? '' : '/') });
    });
    this.pathLength = result.length;
    return result;
  }

  /**
   * 取消操作
   */
  public handleCancel() {
    this.router.back();
  }

  /**
   * 确认操作
   */
  private handleConfirm() {
    this.promptAction.showToast({ message: $r('app.string.handling') });
    let filePath = '';
    if (this.isSaveMode()) {
      filePath = FilenameUtils.getFilePath(UrlUtils.getHost(this.locationInfo?.filePath), this.currentPath, this.saveFileName);
    }
    if (this.isSelectMode()) {
      const selectFile = this.itemData.getAll()[this.selectFileIndex];
      filePath = FilenameUtils.getFilePath(UrlUtils.getHost(this.locationInfo?.filePath), selectFile.path);
    }
    hilog.debug(DOMAIN, TAG, 'filePath: %{public}s', filePath);
    // 回调位置信息
    if (this.locationInfo) {
      LocationParam.callOnLocation({
        mode: this.locationInfo.mode,
        filePath: filePath,
        fileName: FilenameUtils.getFileName(filePath),
        storageType: this.locationInfo.storageType,
        storageConfig: this.locationInfo.storageConfig
      });
    } else {
      this.showError();
    }
  }

  /**
   * 显示错误信息
   */
  private showError() {
    this.isError = true;
    this.errorMessage = ResourceManager.getString($r('app.string.invalid_data_file'));
    this.promptAction.showToast({ message: this.errorMessage });
    this.router.back();
  }

  @Builder
  SortMenu() {
    // 排序菜单
    Menu() {
      MenuItem() {
        Row() {
          Text($r('app.string.SortConstants_name'))
            .fontSize(16)
            .width("120")

          Blank()
          if (this.sortType === 'name') {
            Image(this.sortOrder === 'asc' ? $r("app.media.ic_sort_asc") : $r("app.media.ic_sort_desc"))
              .width(24)
              .height(24)
              .margin({ left: 16 })
              .fillColor($r('app.color.text_primary'))
          }
        }
      }
      .height(48)
      .onClick(() => this.changeSort('name'))

      MenuItem() {
        Row() {
          Text($r('app.string.Settings_sort_size'))
            .fontSize(16)
            .width("120")
          Blank()
          if (this.sortType === 'size') {
            Image(this.sortOrder === 'asc' ? $r("app.media.ic_sort_asc") : $r("app.media.ic_sort_desc"))
              .width(24)
              .height(24)
              .margin({ left: 16 })
              .fillColor($r('app.color.text_primary'))
          }
        }
      }
      .height(48)
      .onClick(() => this.changeSort('size'))

      MenuItem() {
        Row() {
          Text($r('app.string.SortConstants_modified'))
            .fontSize(16)
            .width("120")
          Blank()
          if (this.sortType === 'date') {
            Image(this.sortOrder === 'asc' ? $r("app.media.ic_sort_asc") : $r("app.media.ic_sort_desc"))
              .width(24)
              .height(24)
              .margin({ left: 16 })
              .fillColor($r('app.color.text_primary'))
              .bindMenu(this.SortMenu)
          }
        }
      }
      .onClick(() => this.changeSort('date'))
      .height(48)
    }
    .padding({ left: 16, right: 16 })
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Image($r("app.media.ic_angle_left"))
          .width(24)
          .height(24)
          .margin({ left: 16 })
          .fillColor($r('app.color.text_primary'))
          .onClick(() => {
            this.router.back();
          })

        Text(this.isSaveMode() ? $r('app.string.location_title_save') : $r('app.string.location_title_select'))
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .margin({ left: 16 })
          .fontColor($r('app.color.text_primary'))

        Blank()

        // 排序菜单按钮
        Image($r("app.media.ic_sort"))
          .width(24)
          .height(24)
          .margin({ right: 16 })
          .fillColor($r('app.color.text_primary'))
          .bindMenu(this.SortMenu)
      }
      .width('100%')
      .height(56)

      // 路径导航栏
      Column() {
        List({ scroller: this.pathScroller }) {
          ForEach(this.getPathParts(), (part: PathPart, index) => {
            ListItem() {
              Row() {
                Text(part.name)
                  .fontSize(16)
                  .fontColor($r('app.color.text_primary'))
                  .onClick(() => {
                    this.navigateToPath(part.path);
                  })

                // 添加分隔符（除了最后一个）
                if (index < this.pathLength - 1) {
                  Text('>')
                    .fontSize(16)
                    .height(16)
                    .margin({ left: 5, right: 5 })
                    .fontColor($r('app.color.text_secondary'))
                }
              }
              .height(46)
            }
          }, (item: PathPart) => item.path)
        }
        .width('100%')
        .height(50)
        .contentStartOffset(20)
        .contentEndOffset(20)
        .scrollBar(BarState.Off)
        .listDirection(Axis.Horizontal)
      }
      .width('100%')
      .backgroundColor($r("app.color.card_bg"))
      .height(46)

      // 保存模式文件名称
      if (this.isSaveMode()) {
        Column() {
          TextInput({ text: this.saveFileName, placeholder: $r('app.string.file_name_placeholder') })
            .width('100%')
            .onChange((text: string) => {
              this.saveFileName = text;
            })
        }
        .margin({ top: 6 })
        .width('100%')
        .backgroundColor($r("app.color.card_bg"))
        .height(50)
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)
      }

      // 加载状态或错误提示
      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(50)
            .height(50)
            .color($r('app.color.text_primary'))

          Text($r('app.string.loading_message'))
            .fontSize(16)
            .margin({ top: 16 })
            .fontColor($r('app.color.text_primary'))
        }
        .width('100%')
        .height('60%')
        .justifyContent(FlexAlign.Center)
      } else if (this.isError) {
        Column() {
          Text(this.errorMessage)
            .fontSize(16)
            .margin({ top: 16 })
            .fontColor($r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .padding({ left: 16, right: 16 })

          Button($r('app.string.retry_button_text'))
            .margin({ top: 24 })
            .backgroundColor($r('app.color.button_bg_blue'))
            .fontColor($r('app.color.button_text_blue'))
            .onClick(() => {
              this.loadItems(this.currentPath);
            })
        }
        .width('100%')
        .height('60%')
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          // 文件列表
          List() {
            LazyForEach(this.itemData, (item: FileInfo, index) => {
              ListItem() {
                Row() {
                  Column() {
                    // 图标
                    Image(item.type === FileType.DIR ? $r('app.media.ic_folder') : FileUtils.getFileIcon(item.name))
                      .width(36)
                      .height(36)
                      .fillColor(item.type === FileType.DIR ? '#FFD700' : $r('app.color.text_primary'))
                  }.width("15%")
                  .justifyContent(FlexAlign.Start)

                  Column() {
                    Row() {
                      // 文件名
                      Text(item.name)
                        .fontSize(16)
                        .layoutWeight(1)
                        .fontColor($r('app.color.text_primary'))
                        .maxLines(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                    }

                    Row() {
                      // 修改时间
                      Text(DateUtils.format(new Date(item.modifiedTime)))
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                      // 文件大小
                      Text(item.type === FileType.FILE ? this.formatFileSize(item.size) : item.childrenCount + "")
                        .fontSize(14)
                        .fontColor($r('app.color.text_secondary'))
                        .textAlign(TextAlign.End)
                        .padding({ right: 12 })
                    }
                    .width('100%')
                    .justifyContent(FlexAlign.SpaceBetween)
                  }.width('85%')
                }
                .width('100%')
                .padding({
                  top: 12,
                  bottom: 12
                })
                .backgroundColor(this.selectFileIndex == index ? $r("app.color.item_selected") : $r("app.color.card_bg"))
                .borderRadius(8)
                .onClick(() => {
                  this.handleItemClick(item, index);
                })
              }
              .margin({ bottom: 8 })
            }, (item: FileInfo) => item.path)
            ListItem() {
            }.height(170)
          }
          .layoutWeight(1)
          .width('100%')
          .height('auto')
          .padding({ left: 12, right: 12 })
        }.padding({ top: 12 })
      }

      // 操作按钮
      Row() {
        // 取消
        Button() {
          Row() {
            Text($r('app.string.cancel_button_text'))
              .fontSize(16)
              .fontColor($r('app.color.button_text'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('45%')
        .height(40)
        .borderRadius(16)
        .backgroundColor(Color.Gray)
        .onClick(() => {
          this.handleCancel();
        })

        Blank()
        // 保存
        Button() {
          Row() {
            Text($r('app.string.confirm_button_text'))
              .fontSize(16)
              .fontColor($r('app.color.button_text'))
          }
          .width('100%')
          .justifyContent(FlexAlign.Center)
        }
        .width('45%')
        .height(40)
        .borderRadius(16)
        .backgroundColor($r('app.color.button_bg_blue'))
        .enabled(this.isEnableConfirm)
        .onClick(() => {
          this.handleConfirm();
        })
      }
      .width('100%')
      .height(45)
      .padding({
        top: 12,
        bottom: 0,
        left: 16,
        right: 16
      })
      .position({ x: 0, y: '100%' })
      .translate({ y: -45 }) // 调整位置，确保正确显示
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}