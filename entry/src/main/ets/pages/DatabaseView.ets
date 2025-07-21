import { AddGroupDialog } from '../components/AddGroupDialog';
import { DatabaseShowParam, Icons } from '../services/TypeDefined';
import ThemeManager from '../common/utils/ThemeManager';
import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid } from 'kdbxweb';
import { PromptAction, Router } from '@kit.ArkUI';
import { FileService } from '../services/FileService';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import KdbxUtils from '../common/utils/KdbxUtils';
import { SortMode } from '../common/constants/SortConstants';
import { SettingsService } from '../services/SettingsService';
import ResourceManager from '../common/utils/ResourceManager';

@Entry
@Component
struct DatabaseView {
  @State newGroupName: string | undefined = "";
  @State editingGroupIndex: number = -1;
  @State isLoading: boolean = false;
  @State titleName: string = '';
  @State groups: Array<KdbxGroup> = [];
  @State entries: Array<KdbxEntry> = [];
  @State showBack: boolean = false;
  @State showAddButtons: boolean = false; // 控制是否显示添加分组和添加条目按钮
  @State searchText: string = ''; // 搜索文本
  @State isSearching: boolean = false; // 是否处于搜索状态
  @State filteredGroups: Array<KdbxGroup> = []; // 过滤后的分组列表
  @State filteredEntries: Array<KdbxEntry> = []; // 过滤后的条目列表
  @State sortBy: SortMode = SortMode.DEFAULT; // 排序方式：'default' | 'name' | 'modified' | 'created'
  private database: Kdbx | null = null;
  private databaseShowParam: DatabaseShowParam | undefined = undefined;
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private currentGroup: KdbxGroup | undefined = undefined;
  private settingsService: SettingsService = SettingsService.getInstance();
  dialogController: CustomDialogController = new CustomDialogController({
    builder: AddGroupDialog({
      newGroupName: this.newGroupName,
      editingGroupIndex: this.editingGroupIndex,
      selectedIconId: this.editingGroupIndex >= 0 && this.editingGroupIndex < this.groups.length
        ? this.groups[this.editingGroupIndex].customIcon?.toString() || this.groups[this.editingGroupIndex].icon || Icons.Folder : Icons.Folder,
      onConfirm: (iconId: number | string): void => this.handleAddGroup(iconId),
      onCancel: (): void => {
        this.newGroupName = "";
        this.editingGroupIndex = -1;
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: true
  })

  aboutToAppear() {
    this.clearUrl();
    this.databaseShowParam = this.router.getParams() as DatabaseShowParam;
    // 获取从Password页面传递的参数
    const params = FileService.getInstance().getDbFileParam();
    this.titleName = params.fileName ?? '未知数据库';
    this.database = params.database ?? null;

    // 获取排序方式
    this.settingsService.getSortBy().then((sortBy: SortMode) => {
      this.sortBy = sortBy;
      this.initData(this.databaseShowParam);
    });

    // 监听主题变化
    ThemeManager.getInstance().addThemeChangeListener(() => {
      this.onThemeChanged();
    });
    // 监听排序方式变化
    this.settingsService.registerObserver(this.onSortChanged);
  }

  onPageShow(): void {
    console.log("Load DatabaseView Page: ", this.databaseShowParam);
    this.updateUI();
  }

  /**
   * 如果从 Password 页面过来直接清空历史记录
   */
  private clearUrl(){
    let pageNum = this.router.getLength();
    if(parseInt(pageNum) <= 0 ){
      return;
    }
    let prePage = this.router.getStateByIndex(parseInt(this.router.getLength()) -1);
    if(prePage && prePage.name == 'Password'){
      this.router.clear();
    }
  }

  /**
   * 监听主题变化
   */
  private onSortChanged = (key: string) => {
    console.log("配置项发生了变化：", key)
    if (key == SettingsService.KEY_SORT_BY) {
      SettingsService.getInstance().getSortBy().then((sortBy: SortMode) => {
        this.sortBy = sortBy;
        this.updateUI();
      });
    }
  }

  private initData(dbShowParam: DatabaseShowParam | undefined) {
    if (!this.database) {
      this.promptAction.showToast({
        message: $r('app.string.invalid_database'),
        duration: 2000
      });
      this.router.back();
      return;
    }
    if(this.isLoading == true){
      return;
    }

    this.isLoading = true;
    try {
      if (dbShowParam && dbShowParam.groupId) {
        this.currentGroup = this.database.getGroup(dbShowParam.groupId);
        this.titleName = this.currentGroup?.name || '';
        this.showBack = true;
      } else {
        // 获取根分组下的所有子分组
        this.currentGroup = this.database.getDefaultGroup();
        this.showBack = false;
      }

      // 判断分组是否有效
      if (this.currentGroup === undefined) {
        this.promptAction.showToast({
          message: $r('app.string.invalid_group'),
          duration: 2000
        });
        this.router.back();
        return;
      }
      KdbxUtils.sortBy(this.currentGroup.groups, this.currentGroup.entries, this.sortBy);
      this.groups = this.currentGroup.groups;
      this.entries = this.currentGroup.entries;
      console.info(`加载了 ${this.groups.length} 个分组, ${this.entries.length} 个条目`);
    } catch (error) {
      console.error(`处理数据库失败: ${error}`);
      this.promptAction.showToast({ message: ResourceManager.getInstance().getString($r('app.string.DatabaseView_process_failed')) + `: ${error}`, duration: 2000 });
      // 返回到密码输入页面
      setTimeout(() => {
        this.router.back();
      }, 2000);
    } finally {
      this.isLoading = false;
    }
  }

  @Builder
  SwipeActionButtons(index: number, item: KdbxGroup | KdbxEntry) {
    Row() {
      Button("编辑", { type: ButtonType.Normal })
        .width(80)
        .height(60)
        .backgroundColor($r("app.color.button_bg_blue"))
        .fontColor(Color.White)
        .fontSize(14)
        .onClick(() => {
          if (item instanceof KdbxEntry) {
            // 跳转到条目编辑页面
            this.router.pushUrl({
              url: 'pages/EntryEdit',
              params: {
                groupId: item.parentGroup?.uuid.id,
                entryId: item.uuid.id
              }
            });
          }
          if (item instanceof KdbxGroup) {
            this.editingGroupIndex = index
            this.newGroupName = this.groups[index].name;
            this.dialogController.open()
          }
        })

      Button("删除", { type: ButtonType.Normal })
        .width(80)
        .height(60)
        .backgroundColor($r('app.color.danger'))
        .fontColor($r('app.color.text_primary'))
        .fontSize(14)
        .onClick(() => {
          AlertDialog.show({
            title: $r('app.string.delete_confirm_title'),
            message: $r('app.string.delete_confirm_message'),
            primaryButton: {
              value: $r('app.string.cancel_button_text'),
              action: () => {
              }
            },
            secondaryButton: {
              value: $r('app.string.delete_button_text'),
              action: () => {
                if (this.database === null) {
                  return;
                }
                let deleteObj: KdbxGroup | KdbxEntry = null;
                if (item instanceof KdbxGroup) {
                  deleteObj = this.groups[index];
                  this.groups.splice(index, 1);
                }
                if (item instanceof KdbxEntry) {
                  deleteObj = this.entries[index];
                  this.entries.splice(index, 1);
                }
                this.database.remove(deleteObj);
                this.saveDatabase();
              }
            }
          })
        })
    }
  }

  /**
   * 保存数据库
   */
  private saveDatabase() {
    if (this.database) {
      const dbFileParam = FileService.getInstance().getDbFileParam();
      this.database.save().then(async savedDb => {
        const fileManager = new KdbxFileManager(dbFileParam.storageType);
        fileManager.saveKdbxFile(dbFileParam.filePath, savedDb).then(() => {
          this.promptAction.showToast({ message: $r('app.string.save_success_message') });
        }).catch((error: Error) => {
          console.error(`保存数据库失败: ${error}`);
          this.promptAction.showToast({ message: `${$r('app.string.save_failed_message')}: ${error.message}` });
        });
      }).catch((error: Error) => {
        console.error(`保存数据库失败: ${error}`);
        this.promptAction.showToast({ message: `${$r('app.string.save_failed_message')}: ${error.message}` });
      });
    }
  }

  private handleAddGroup(iconId?: number | string) {
    if (this.newGroupName === undefined || !this.newGroupName.trim()) {
      return;
    }
    if (!this.database) {
      this.promptAction.showToast({
        message: $r("app.string.invalid_database")
      });
      return;
    }

    let group: KdbxGroup;
    // 编辑现有分组
    if (this.editingGroupIndex >= 0 && this.editingGroupIndex < this.groups.length) {
      group = this.groups[this.editingGroupIndex];
      group.name = this.newGroupName.trim();
      group.times.update();
    } else {
      // 添加新分组
      group = this.database.createGroup(this.currentGroup, this.newGroupName.trim());
    }

    // 设置分组图标
    if (typeof iconId === 'string' && iconId.length > 0) {
      group.customIcon = new KdbxUuid(iconId);
    } else {
      group.icon = iconId as number;
    }
    // 保存数据库
    this.saveDatabase();
    this.updateUI();
    // 重置状态
    this.newGroupName = "";
    this.editingGroupIndex = -1;
  }

  aboutToDisappear() {
    // 移除监听器
    ThemeManager.getInstance().removeThemeChangeListenerAll();
    this.settingsService.unregisterObserver(this.onSortChanged);
  }
  // 强制组件刷新以应用新主题
  onThemeChanged() {
    this.updateUI();
  }

  /**
   * 强制组件刷新
   */
  private updateUI() {
    // 强制刷新UI - 先清空数组，再重新加载
    this.groups = [];
    this.entries = [];
    // 延迟一帧后重新加载数据，确保UI更新
    setTimeout(() => {
      // 获取分组和条目
      let groups = [...this.currentGroup?.groups || []];
      let entries = [...this.currentGroup?.entries || []];
      // 按照分组名称排序
      KdbxUtils.sortBy(groups, entries, this.sortBy);

      this.groups = groups;
      this.entries = entries;

      // 如果在搜索状态，更新搜索结果
      if (this.isSearching && this.searchText.length > 0) {
        this.performSearch();
      } else if (this.isSearching) {
        this.filteredGroups = [...this.groups];
        this.filteredEntries = [...this.entries];
      }
    }, 10);
  }

  /**
   * 执行搜索
   */
  private performSearch() {
    if (!this.searchText || this.searchText.trim() === '') {
      // 如果搜索文本为空，显示所有分组和条目
      this.filteredGroups = [...this.groups];
      this.filteredEntries = [...this.entries];
      return;
    }
    if (this.isSearching) {
      // 全局搜索模式：搜索整个数据库
      this.filteredGroups = [];
      this.filteredEntries = [];

      if (this.database) {
        let result = KdbxUtils.searchInGroup(this.database.getDefaultGroup(), this.searchText);
        this.filteredGroups.push(...result.filteredGroups);
        this.filteredEntries.push(...result.filteredEntries);
      }
    }
  }

  /**
   * 获取分组下的条目数量
   * @param kdbxGroup 分组
   * @returns 分组下的条目数量
   */
  private groupItemCount(kdbxGroup: KdbxGroup) {
    if (!kdbxGroup) {
      return 0;
    }
    return kdbxGroup.groups.length + kdbxGroup.entries.length;
  }

  // 已删除showAddOptions方法，改为使用固定按钮

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          if (this.showBack) {
            Image($r('app.media.ic_back'))
              .width(24)
              .height(24)
              .margin({ left: 16 })
              .fillColor($r('app.color.text_primary'))
              .onClick(() => {
                this.router.back();
              })
          }
          if (!this.isSearching) {
            Text(this.titleName)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .margin({ left: 16 })
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Blank()
            // 搜索按钮
            Image($r('app.media.ic_search'))
              .width(24)
              .height(24)
              .margin({ right: 16 })
              .fillColor($r('app.color.text_primary'))
              .onClick(() => {
                this.isSearching = true;
                this.searchText = '';
                this.filteredGroups = [...this.groups];
                this.filteredEntries = [...this.entries];
              })
            Image($r('app.media.ic_settings'))
              .width(24)
              .height(24)
              .margin({ right: 16 })
              .onClick(() => {
                this.router.pushUrl({ url: 'pages/Settings' })
              })
          } else {
            Blank()
            // 搜索框
            Search({ placeholder: $r('app.string.search_placeholder'), value: this.searchText })
              .width('70%')
              .margin({ left: 16 })
              .height(40)
              .searchIcon({
                src: $r('sys.media.ohos_ic_public_search_filled')
              })
              .cancelButton({
                style: CancelButtonStyle.CONSTANT,
                icon: {
                  src: $r('sys.media.ohos_ic_public_cancel_filled')
                },
              })
              .enterKeyType(EnterKeyType.Search)
              .padding({ left: 10, right: 10 })
              .onChange((value: string) => {
                this.searchText = value;
                this.performSearch();
              })
              .onSubmit((value: string) => {
                this.searchText = value;
                this.performSearch();
              })
            Button($r('app.string.cancel_button_text'))
              .width(70)
              .height(40)
              .fontSize(16)
              .fontColor($r('app.color.text_primary'))
              .backgroundColor($r("app.color.card_bg"))
              .margin({ right: 16 })
              .padding({ left: 5, right: 5 })
              .onClick(() => {
                this.searchText = '';
                this.isSearching = false;
                this.filteredGroups = [...this.groups];
                this.filteredEntries = [...this.entries];
              })
          }
        }
        .width('100%')
        .height(56)
        .backgroundColor($r("app.color.card_bg"))

        if (this.isLoading) {
          // 加载中状态
          Column() {
            LoadingProgress()
              .width(50)
              .height(50)
              .color($r('app.color.primary'))

            Text($r('app.string.loading_database_message'))
              .fontSize(16)
              .margin({ top: 16 })
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r("app.color.bg_primary"))
        } else {
          // 数据库内容
          List({ space: 8 }) {
            ForEach(this.isSearching ? this.filteredGroups : this.groups, (itemGroup: KdbxGroup, index: number) => {
              ListItem() {
                Row() {
                  Image(KdbxUtils.getIcon(itemGroup.icon, itemGroup.customIcon, $r('app.media.ic_folder_open')))
                    .width(28)
                    .height(28)
                    .margin(10)
                  Column() {
                    Text(itemGroup.name)
                      .fontSize(18)
                      .textAlign(TextAlign.Start)
                      .flexGrow(1)
                    Text($r('app.string.DatabaseView_group_items', this.groupItemCount(itemGroup)))
                      .fontSize(12)
                      .textAlign(TextAlign.Start)
                      .flexGrow(1)
                      .margin({ top: 4 })
                  }
                  .flexGrow(1)
                  .alignItems(HorizontalAlign.Start)

                  Image($r('app.media.ic_arrow_right'))
                    .width(20)
                    .height(20)
                    .margin({ right: 10 })
                    .fillColor($r('app.color.text_primary'))
                }
                .width('100%')
                .height(60)
                .borderRadius(8)
                .backgroundColor($r("app.color.card_bg"))
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.router.pushUrl({ url: 'pages/DatabaseView', params: { groupId: itemGroup.uuid.id } });
                })
              }
              .swipeAction({
                end: {
                  builder: this.SwipeActionButtons(index, itemGroup)
                }
              })
            }, (item: KdbxGroup, index: number) => `${index}-${item.uuid.id}`)

            ForEach(this.isSearching ? this.filteredEntries : this.entries, (itemEntry: KdbxEntry, index: number) => {
              ListItem() {
                Row() {
                  Image(KdbxUtils.getIcon(itemEntry.icon, itemEntry.customIcon, $r('app.media.ic_file')))
                    .width(28)
                    .height(28)
                    .margin(10)
                  Column() {
                    Text(KdbxUtils.getFieldValueString(itemEntry.fields, KdbxUtils.FIELD_TITLE))
                      .fontSize(18)
                      .textAlign(TextAlign.Start)
                      .flexGrow(1)
                    Text(KdbxUtils.getFieldValueString(itemEntry.fields, KdbxUtils.FIELD_USERNAME))
                      .fontSize(12)
                      .textAlign(TextAlign.Start)
                      .flexGrow(1)
                  }
                  .flexGrow(1)
                  .alignItems(HorizontalAlign.Start)

                  Image($r('app.media.ic_arrow_right'))
                    .width(20)
                    .height(20)
                    .margin({ right: 10 })
                    .fillColor($r('app.color.text_primary'))
                }
                .width('100%')
                .height(60)
                .borderRadius(8)
                .backgroundColor($r("app.color.card_bg"))
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.router.pushUrl({ url: 'pages/EntryView', params: { entryId: itemEntry.uuid.id, groupId: itemEntry.parentGroup?.uuid.id } });
                })
              }
              .swipeAction({
                end: {
                  builder: this.SwipeActionButtons(index, itemEntry)
                }
              })
            }, (item: KdbxEntry, index: number) => `${index}-${item.uuid.id}`)
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r("app.color.bg_primary"))
          .padding({ left: 12, right: 12, top: 12, bottom:40 })
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .height('100%')

      // 点击空白区域隐藏添加按钮
      Column()
        .width('100%')
        .height('100%')
        .onClick(() => {
          if (this.showAddButtons) {
            this.showAddButtons = false;
          }
        })
        .visibility(this.showAddButtons ? Visibility.Visible : Visibility.None)

      // 添加分组按钮
      Button() {
        Row() {
          Image($r('app.media.ic_folder'))
            .width(20)
            .height(20)
            .fillColor($r('app.color.button_text_blue'))
          Text($r('app.string.add_group_button'))
            .fontSize(14)
            .fontColor($r('app.color.button_text_blue'))
            .margin({ left: 8 })
        }
      }
      .width(120)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r("app.color.button_bg_blue"))
      .position({ right: 12, bottom: 72 })
      .enabled(!this.isLoading)
      .visibility(this.showAddButtons ? Visibility.Visible : Visibility.None)
      .onClick(() => {
        this.showAddButtons = false;
        this.editingGroupIndex = -1;
        this.newGroupName = "";
        this.dialogController.open();
      })

      // 添加条目按钮
      Button() {
        Row() {
          Image($r('app.media.ic_file'))
            .width(20)
            .height(20)
            .fillColor($r("app.color.button_text_blue"))
          Text($r('app.string.add_entry_button'))
            .fontSize(14)
            .fontColor($r("app.color.button_text_blue"))
            .margin({ left: 8 })
        }
      }
      .width(120)
      .height(40)
      .borderRadius(20)
      .backgroundColor($r("app.color.button_bg_blue"))
      .position({ right: 12, bottom: 120 })
      .enabled(!this.isLoading)
      .visibility(this.showAddButtons ? Visibility.Visible : Visibility.None)
      .onClick(() => {
        this.showAddButtons = false;
        this.router.pushUrl({
          url: 'pages/EntryEdit',
          params: {
            groupId: this.currentGroup?.uuid.id
          }
        });
      })

      // 主添加按钮
      Button() {
        Image($r('app.media.ic_add'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
      }
      .width(60)
      .height(60)
      .borderRadius(30)
      .backgroundColor($r("app.color.button_bg_blue"))
      .position({ right: 12, bottom: 12 })
      .enabled(!this.isLoading)
      .opacity(this.isLoading ? 0.5 : 1)
      .visibility(this.showAddButtons ? Visibility.None : Visibility.Visible)
      .onClick(() => {
        this.showAddButtons = true;
      })
    }
    .width('100%')
    .height('100%')
  }
}
