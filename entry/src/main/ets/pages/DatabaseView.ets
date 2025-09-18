import { AddGroupDialog } from '../components/AddGroupDialog';
import { DatabaseShowParam, Icons, MoveParam } from '../services/TypeDefined';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FocusController } from '@ohos.arkui.UIContext';

import ThemeManager from '../common/utils/ThemeManager';
import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid } from 'kdbxweb';
import { PromptAction, Router } from '@kit.ArkUI';
import { FileService } from '../services/FileService';
import KdbxUtils from '../common/utils/KdbxUtils';
import { SortMode } from '../common/constants/SortConstants';
import { SettingsService } from '../services/SettingsService';
import { SupportService } from '../services/SupportService';
import DateUtils from '../common/utils/DateUtils';
import { EventBus } from '../services/EventBus';
import KdbxLoadService from '../services/kdbx/KdbxLoadService';
import { LoadDatabase } from '../workers/DatabaseLoadWorkerParam';
import { LoadMessage, SuccessMessage } from '../workers/WorkerParam';
import ResourceManager from '../common/utils/ResourceManager';
import { TotpPreviewComponent } from '../components/TotpPreviewComponent';
import { RecentFilesService } from '../services/RecentFilesService';
import { ToastSaveDatabaseCallback } from '../workers/callback/ToastSaveDatabaseCallback';

const DOMAIN = 0x0000;
const TAG = 'DatabaseView';

@Entry
@Component
struct DatabaseView {
  @State newGroupName: string | undefined = "";
  @State editingGroupIndex: number = -1;
  @State isLoading: boolean = false;
  @State isRefreshing: boolean = false;
  @State titleName: ResourceStr = '';
  @State groups: Array<KdbxGroup> = [];
  @State entries: Array<KdbxEntry> = [];
  @State showBack: boolean = false;
  @State showAddButtons: boolean = false; // 控制是否显示添加分组和添加条目按钮
  @State searchText: string = ''; // 搜索文本
  @State isSearching: boolean = false; // 是否处于搜索状态
  @State filteredGroups: Array<KdbxGroup> = []; // 过滤后的分组列表
  @State filteredEntries: Array<KdbxEntry> = []; // 过滤后的条目列表
  @State sortBy: SortMode = SortMode.DEFAULT; // 排序方式：'default' | 'name' | 'modified' | 'created'
  @State moveParam: MoveParam | undefined = undefined; // 移动参数
  @State refreshText: ResourceStr = $r('app.string.refreshing_message');
  @State isPullToRefresh: boolean = SettingsService.KEY_SECURITY_PULL_REFRESH_DEFAULT;
  @State isListShowTotp: boolean = SettingsService.KEY_SECURITY_LIST_SHOW_TOTP_DEFAULT;
  @State searchHistory: Array<string> = [];
  @State currentGroup: KdbxGroup | undefined = undefined;
  private database: Kdbx | null = null;
  private databaseShowParam: DatabaseShowParam | undefined = undefined;
  private filePath: string = '';
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private settingsService: SettingsService = SettingsService.getInstance();
  private searchController: FocusController = new FocusController();
  private listScroller: ListScroller = new ListScroller();
  private clearHistoryUrlPage: Array<string> = ["Password", "UnLockDatabase"];
  private dialogController: CustomDialogController = new CustomDialogController({
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
    this.initSettings();
    // 注册数据库合并事件
    EventBus.on<void>(EventBus.DATABASE_RELOAD, () => {
      this.reloadDatabase();
    });
    EventBus.on<void>(EventBus.DATABASE_UPDATE, () => {
      this.updateUI();
    });
    this.databaseShowParam = this.router.getParams() as DatabaseShowParam;
    // 加载数据库信息
    this.loadDatabase();

    // 监听主题变化
    ThemeManager.getInstance().addThemeChangeListener(() => {
      this.onThemeChanged();
    });
    // 监听排序方式变化
    this.settingsService.registerObserver(this.onSettingChanged);
    // 显示支持弹框
    SupportService.showSupportDialog(this.getUIContext());
  }

  aboutToDisappear() {
    // 移除监听器
    EventBus.off<void>(EventBus.DATABASE_RELOAD);
    EventBus.off<void>(EventBus.DATABASE_UPDATE);
    ThemeManager.getInstance().removeThemeChangeListenerAll();
    this.settingsService.unregisterObserver(this.onSettingChanged);
  }

  onPageShow(): void {
    this.moveParam = MoveParam.getInstance();
  }

  /**
   * 初始化配置参数
   */
  private initSettings() {
    // 下拉刷新
    this.settingsService.get(SettingsService.KEY_SECURITY_PULL_REFRESH, SettingsService.KEY_SECURITY_PULL_REFRESH_DEFAULT).then(result => {
      this.isPullToRefresh = result;
      this.refreshText = result ? $r('app.string.refreshing_message') : $r('app.string.refreshing_disable');
    })
    // 列表显示TOTP
    this.settingsService.get(SettingsService.KEY_SECURITY_LIST_SHOW_TOTP, SettingsService.KEY_SECURITY_LIST_SHOW_TOTP_DEFAULT).then(result => {
      this.isListShowTotp = result;
    });
  }

  /**
   * 重新加载数据库信息
   */
  private reloadDatabase() {
    hilog.debug(DOMAIN, TAG, 'Receive reload database event');
    this.loadDatabase().then(() => {
      this.updateUI();
    });

  }

  /**
   * 加载数据库信息
   */
  private loadDatabase(): Promise<void> {
    // 获取从Password页面传递的参数
    const params = FileService.getDbFileParam();
    this.titleName = params.fileName ?? '';
    this.database = params.database ?? null;
    this.filePath = params.filePath ?? '';

    // 获取排序方式
    return this.settingsService.getSortBy().then((sortBy: SortMode): void => {
      this.sortBy = sortBy;
      return this.initData(this.databaseShowParam);
    });
  }

  /**
   * 如果从 Password 页面过来直接清空历史记录
   */
  private clearUrl() {
    let pageNum = this.router.getLength();
    if (parseInt(pageNum) <= 0) {
      return;
    }
    let prePage = this.router.getStateByIndex(parseInt(this.router.getLength()) - 1);
    if (prePage && this.clearHistoryUrlPage.includes(prePage.name)) {
      this.router.clear();
    }
  }

  /**
   * 监听主题变化
   */
  private onSettingChanged = (key: string) => {
    hilog.info(DOMAIN, TAG, '%{public}s', `Configuration changed: ${key}`);
    if (key == SettingsService.KEY_SORT_BY) {
      SettingsService.getInstance().getSortBy().then((sortBy: SortMode) => {
        this.sortBy = sortBy;
        this.updateUI();
      });
    }
    this.initSettings();
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
    if (this.isLoading == true) {
      return;
    }

    this.isLoading = true;
    try {
      if (dbShowParam && dbShowParam.groupId) {
        this.currentGroup = this.database.getGroup(dbShowParam.groupId);
        this.titleName = KdbxUtils.getFieldName(this.currentGroup?.name) || '';
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
      hilog.info(DOMAIN, TAG, '%{public}s', `Loaded ${this.groups.length} groups, ${this.entries.length} entries`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', `Failed to process database: ${error}`);
      this.promptAction.showToast({ message: $r("app.string.load_database_failed"), duration: 2000 });
      // 返回到密码输入页面
      setTimeout(() => {
        this.router.back();
      }, 2000);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 重新加载数据库
   */
  private refreshDatabase() {
    this.isRefreshing = true;
    let loadParam = LoadDatabase.byDbFileParam(FileService.getDbFileParam());
    KdbxLoadService.loadDatabase(loadParam, {
      onSuccessMessage: (successMessage: SuccessMessage) => {
        KdbxUtils.arrayBufferToKdbx(successMessage.data, loadParam).then((database: Kdbx) => {
          FileService.resetDbFileParam(database, successMessage.modifiedTime);
          this.refreshText = $r('app.string.refreshing_message');
          EventBus.emit<void>(EventBus.DATABASE_RELOAD);
          this.promptAction.showToast({ message: $r('app.string.refresh_success') });
          this.isRefreshing = false;
        });
      },
      onLoadMessage: (message: LoadMessage) => {
        this.refreshText = ResourceManager.getString(message.message);
      },
      onErrorMessage: (message: LoadMessage) => {
        this.refreshText = ResourceManager.getString(message.message);
        this.promptAction.showToast({ message: this.refreshText });
        this.isRefreshing = false;
      },
    });
  }

  @Builder
  SwipeActionButtons(index: number, item: KdbxGroup | KdbxEntry) {
    Row() {
      Button($r('app.string.edit_button_text'), { type: ButtonType.Normal })
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
          this.listScroller.closeAllSwipeActions();
        })
      Button($r('app.string.move_button_text'), { type: ButtonType.Normal })
        .width(80)
        .height(60)
        .fontColor($r('app.color.text_primary'))
        .backgroundColor($r("app.color.warn"))
        .fontSize(14)
        .onClick(() => {
          // 判断是分组还是条目
          if (item instanceof KdbxGroup) {
            this.moveParam = new MoveParam(item.uuid.id);
          } else if (item instanceof KdbxEntry) {
            this.moveParam = new MoveParam(item.parentGroup?.uuid.id || '', item.uuid.id);
          }
          this.listScroller.closeAllSwipeActions();
        })
      Button($r('app.string.delete_button_text'), { type: ButtonType.Normal })
        .width(80)
        .height(60)
        .backgroundColor($r("app.color.error"))
        .fontColor($r('app.color.text_primary'))
        .fontSize(14)
        .onClick(() => {
          this.listScroller.closeAllSwipeActions();
          this.getUIContext().showAlertDialog({
            title: $r("app.string.dialog_confirm_title"),
            message: $r("app.string.dialog_delete_confirm_message"),
            primaryButton: {
              value: $r('app.string.cancel_button_text'),
              action: () => {
              }
            },
            secondaryButton: {
              value: $r("app.string.delete_button_text"),
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
      KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
        onSuccess: () => {
          this.updateUI();
        }
      }));
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
      group.icon = undefined;
    } else {
      group.icon = iconId as number;
      group.customIcon = undefined;
    }
    // 保存数据库
    this.saveDatabase();
    this.updateUI();
    // 重置状态
    this.newGroupName = "";
    this.editingGroupIndex = -1;
  }

  // 强制组件刷新以应用新主题
  onThemeChanged() {
    this.updateUI();
  }

  /**
   * 移动条目/分组到当前分组
   */
  private moveItemToCurrentGroup() {
    if (!this.database || !this.currentGroup || !this.moveParam) {
      this.promptAction.showToast({
        message: $r('app.string.operation_failed'),
        duration: 2000
      });
      this.cancelMoving();
      return;
    }

    try {
      // 获取要移动的条目/分组
      let sourceItem: KdbxGroup | KdbxEntry | undefined | null = undefined;

      if (this.moveParam.isMoveGroup) {
        sourceItem = this.database.getGroup(this.moveParam.groupId);
      } else {
        sourceItem = KdbxUtils.getEntry(this.database, this.moveParam.groupId, this.moveParam.entryId || "");
      }

      if (!sourceItem) {
        this.promptAction.showToast({
          message: $r('app.string.entry_not_found'),
          duration: 2000
        });
        this.cancelMoving();
        return;
      }

      // 检查是否移动到自己或子分组
      if (this.moveParam.isMoveGroup) {
        const sourceGroup = sourceItem as KdbxGroup;
        // 不能移动到自己或子分组
        if (this.currentGroup.uuid.id === sourceGroup.uuid.id || KdbxUtils.isChildGroup(sourceGroup, this.currentGroup)) {
          this.promptAction.showToast({
            message: $r('app.string.cannot_move_to_child'),
            duration: 2000
          });
          this.cancelMoving();
          return;
        }
      }

      // 移动条目/分组
      this.database.move(sourceItem, this.currentGroup);
      // 保存数据库
      this.saveDatabase();
      // 更新UI
      this.updateUI();
      // 显示成功提示
      this.promptAction.showToast({
        message: $r('app.string.operation_success'),
        duration: 2000
      });
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to move item: %{public}s', error.message);
      this.promptAction.showToast({
        message: $r('app.string.operation_failed'),
        duration: 2000
      });
    } finally {
      // 取消移动模式
      this.cancelMoving();
    }
  }

  /**
   * 取消移动操作
   */
  private cancelMoving() {
    this.moveParam = undefined;
    MoveParam.clearInstance();
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

  /**
   * 锁定数据库
   */
  private lockDatabase() {
    this.router.pushUrl({ url: 'pages/UnLockDatabase' })
  }

  /**
   * 执行搜索
   */
  private showSearch() {
    this.isSearching = true;
    this.searchText = '';
    this.filteredGroups = [...this.groups];
    this.filteredEntries = [...this.entries];
    // 获取搜索历史
    this.loadSearchHistory();
  }

  /**
   * 添加搜索历史
   */
  private addAndGetSearchHistory() {
    if (!this.searchText) {
      return;
    }
    RecentFilesService.addSearchHistory(this.filePath, this.searchText).then(result => {
      this.loadSearchHistory();
    });
  }

  /**
   * 获取搜索历史
   */
  private loadSearchHistory() {
    RecentFilesService.getSearchHistory(this.filePath).then(history => {
      this.searchHistory = history;
    });
  }

  /**
   * 清空搜索历史
   */
  private clearSearchHistory() {
    if (!this.searchHistory) {
      return;
    }
    this.getUIContext().showAlertDialog({
      title: $r('app.string.dialog_confirm_title'),
      message: $r('app.string.dialog_delete_confirm_message'),
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.confirm_button_text'),
        action: () => {
          RecentFilesService.clearSearchHistory(this.filePath).then(result => {
            this.searchHistory = [];
          });
        }
      }
    });
  }

  private isShowHistory(): boolean {
    return this.isSearching && this.searchHistory && this.searchHistory.length > 0;
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          if (!this.isSearching) {
            Row() {
              if (this.showBack) {
                Image($r("app.media.ic_angle_left"))
                  .width(24)
                  .height(24)
                  .margin({ left: 16 })
                  .fillColor($r('app.color.text_primary'))
                  .onClick(() => {
                    this.router.back();
                  })
              }
              Text(this.titleName)
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .margin({ left: 16 })
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('55%')
              Blank()
              // 搜索按钮
              Image($r('app.media.ic_search'))
                .width(24)
                .height(24)
                .margin({ right: 16 })
                .onClick(() => {
                  this.showSearch();
                })
              // 锁定数据库
              Image($r('app.media.ic_lock'))
                .width(24)
                .height(24)
                .margin({ right: 16 })
                .fillColor($r('app.color.text_primary'))
                .onClick(() => {
                  this.lockDatabase();
                })
              Image($r('app.media.ic_settings'))
                .width(24)
                .height(24)
                .margin({ right: 16 })
                .onClick(() => {
                  this.router.pushUrl({ url: 'pages/setting/Settings' })
                })
            }
            .alignItems(VerticalAlign.Center)
            .width('auto')
            .layoutWeight(1)
          } else {
            Column() {
              Row() {
                if (this.showBack) {
                  Image($r("app.media.ic_angle_left"))
                    .width(24)
                    .height(24)
                    .margin({ left: 16 })
                    .fillColor($r('app.color.text_primary'))
                    .onClick(() => {
                      this.router.back();
                    })
                  Blank()
                }
                // 搜索框
                Search({ placeholder: $r('app.string.search_placeholder'), value: this.searchText })
                  .width('63%')
                  .margin({ left: 16 })
                  .height(40)
                  .key("searchKey")
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
                    this.addAndGetSearchHistory();
                  })
                  .onAppear(() => {
                    try {
                      this.searchController.requestFocus('searchKey'); // 传入组件key
                    } catch (error) {
                      hilog.error(DOMAIN, TAG, 'SearchKey con not get focus: %{public}s', error?.message);
                    }
                  })
                  .onBlur(() => {
                    this.addAndGetSearchHistory();
                  })
                Blank()
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
              }.width('100%')

              // 显示搜索历史
              if (this.isShowHistory()) {
                Row() {
                  RelativeContainer() {
                    List() {
                      ForEach(this.searchHistory, (searchItem: string, index: number) => {
                        ListItem() {
                          Button(searchItem)
                            .height(34)
                            .fontSize(16)
                            .fontColor($r('app.color.text_primary'))
                            .backgroundColor($r("app.color.card_bg"))
                            .padding({ left: 10, right: 10 })
                            .onClick(() => {
                              this.searchText = searchItem;
                              this.performSearch();
                            })
                        }
                      })
                    }
                    .padding({
                      left: 10,
                      right: 10,
                      top: 10,
                      bottom: 6
                    })
                    .listDirection(Axis.Horizontal)
                    .scrollBar(BarState.Off)

                    // 清空历史记录图标
                    Image($r('app.media.ic_delete'))
                      .width(22)
                      .height(22)
                      .margin({ right: 32, top: 16 })
                      .fillColor($r('app.color.button_bg_disabled'))
                      .borderRadius(4)
                      .alignRules({
                        middle: { anchor: "__container__", align: HorizontalAlign.End },
                        top: { anchor: "__container__", align: VerticalAlign.Top }
                      })
                      .onClick(() => {
                        this.clearSearchHistory();
                      })
                  }
                  .margin({ top: 4 })
                  .width('100%')
                  .backgroundColor($r("app.color.card_bg"))
                  .height(58)
                  .borderRadius(8)
                }.width('100%')
                .padding({ left: 12, right: 12 })
              }
            }.width('100%')
          }
        }
        .width('100%')
        .height(this.isShowHistory() ? 114 : 56)

        if (this.isLoading) {
          // 加载中状态
          Column() {
            LoadingProgress()
              .width(50)
              .height(50)
              .color($r('app.color.primary'))

            Text($r("app.string.loading_message"))
              .fontSize(16)
              .margin({ top: 16 })
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r("app.color.bg_primary"))
        } else {
          Refresh({ refreshing: $$this.isRefreshing, promptText: this.refreshText }) {
            // 数据库内容
            List({ space: 8, scroller: this.listScroller }) {
              // 没有数据
              if (this.currentGroup?.groups.length === 0 && this.currentGroup?.entries.length === 0) {
                ListItem() {
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
                }
              } else {
                // 分组信息显示
                ForEach(this.isSearching ? this.filteredGroups : this.groups, (itemGroup: KdbxGroup, index: number) => {
                  ListItem() {
                    Row() {
                      Image(KdbxUtils.getIcon(itemGroup.icon, itemGroup.customIcon, $r('app.media.ic_folder_open')))
                        .width(28)
                        .height(28)
                        .margin(10)
                      Column() {
                        Text(KdbxUtils.getFieldName(itemGroup.name))
                          .fontSize(18)
                          .textAlign(TextAlign.Start)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .flexGrow(1)
                          .maxLines(1)
                        Text($r("app.string.group_items_message", this.groupItemCount(itemGroup)))
                          .fontSize(12)
                          .textAlign(TextAlign.Start)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .flexGrow(1)
                          .margin({ top: 4 })
                          .maxLines(2)
                      }
                      .flexGrow(1)
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Image($r('app.media.ic_arrow_right'))
                        .width(20)
                        .height(20)
                        .margin({ right: 10 })
                        .fillColor($r('app.color.text_primary'))
                    }
                    .width('100%')
                    .height(60)
                    .borderRadius(8)
                    .backgroundColor((this.moveParam && this.moveParam.isMoveItem(itemGroup.uuid.id)) ? $r("app.color.item_selected") :
                    $r("app.color.card_bg"))
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

                // 条目数据展示
                ForEach(this.isSearching ? this.filteredEntries : this.entries, (itemEntry: KdbxEntry, index: number) => {
                  ListItem() {
                    Row() {
                      Image(DateUtils.isExpired(itemEntry.times.expires, itemEntry.times.expiryTime) ? $r('app.media.C45_Expired') :
                      KdbxUtils.getIcon(itemEntry.icon, itemEntry.customIcon, $r('app.media.ic_file')))
                        .width(28)
                        .height(28)
                        .margin(10)
                      Column() {
                        Text(KdbxUtils.getFieldValueString(itemEntry.fields, KdbxUtils.FIELD_TITLE))
                          .fontSize(18)
                          .textAlign(TextAlign.Start)
                          .flexGrow(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .maxLines(1)
                          .decoration({
                            type: (DateUtils.isExpired(itemEntry.times.expires, itemEntry.times.expiryTime) ? TextDecorationType.LineThrough :
                            TextDecorationType.None)
                          })
                        Text(KdbxUtils.getFieldValueString(itemEntry.fields, KdbxUtils.FIELD_USERNAME))
                          .fontSize(12)
                          .textAlign(TextAlign.Start)
                          .flexGrow(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .maxLines(1)
                          .margin({ top: 4 })
                          .decoration({
                            type: (DateUtils.isExpired(itemEntry.times.expires, itemEntry.times.expiryTime) ? TextDecorationType.LineThrough :
                            TextDecorationType.None)
                          })
                        // TOTP 字段展示
                        if (this.isListShowTotp) {
                          ForEach(KdbxUtils.getTotpUrl(itemEntry), (totpUrl: string, index: number) => {
                            TotpPreviewComponent({ totpUrl: totpUrl })
                          });
                        }
                      }
                      .flexGrow(1)
                      .alignItems(HorizontalAlign.Start)
                      .layoutWeight(1)

                      Image($r('app.media.ic_arrow_right'))
                        .width(20)
                        .height(20)
                        .margin({ right: 10 })
                        .fillColor($r('app.color.text_primary'))
                    }
                    .width('100%')
                    .borderRadius(8)
                    .backgroundColor((this.moveParam && this.moveParam.isMoveItem(itemEntry.uuid.id)) ? $r("app.color.button_bg_blue") :
                    $r("app.color.card_bg"))
                    .padding({
                      left: 10,
                      right: 10,
                      top: 8,
                      bottom: 8
                    })
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
              ListItem() {
                Row()
                  .height(100)
                  .width('100%')
                  .backgroundColor(Color.Transparent)
              }
            }
            .width('100%')
            .height('100%')
            .backgroundColor($r("app.color.bg_primary"))
            .padding({
              left: 12,
              right: 12,
              top: 12,
              bottom: 0
            })
            .scrollBar(BarState.Auto)
          }
          .backgroundColor($r("app.color.bg_primary"))
          .refreshOffset(90)
          .pullToRefresh(this.isPullToRefresh)
          .onRefreshing(() => {
            this.refreshDatabase();
          })
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

      if (!(this.showAddButtons || this.moveParam)) {
        // 显示TOTP
        Button() {
          Image($r('app.media.ic_clock'))
            .width(28)
            .height(28)
            .fillColor(Color.White)
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor($r("app.color.button_bg_blue"))
        .position({ right: 12, bottom: 80 })
        .enabled(!this.isLoading)
        .opacity(this.isLoading ? 0.5 : 1)
        .onClick(() => {
          this.router.pushUrl({ url: 'pages/TotpView' });
        })

        // 主添加按钮
        Button() {
          Image($r('app.media.ic_add'))
            .width(28)
            .height(28)
            .fillColor(Color.White)
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor($r("app.color.button_bg_blue"))
        .position({ right: 12, bottom: 12 })
        .enabled(!this.isLoading)
        .opacity(this.isLoading ? 0.5 : 1)
        .onClick(() => {
          this.showAddButtons = true;
        })
      }

      // 移动模式下的底部浮动按钮
      if (this.moveParam) {
        Column() {
          Row() {
            Button($r('app.string.move_here'), { type: ButtonType.Normal })
              .width('45%')
              .height(40)
              .margin({ right: 8 })
              .borderRadius(16)
              .fontColor($r("app.color.button_text_blue"))
              .backgroundColor($r("app.color.button_bg_blue"))
              .onClick(() => {
                this.moveItemToCurrentGroup();
              })

            Button($r('app.string.cancel_button_text'), { type: ButtonType.Normal })
              .width('45%')
              .height(40)
              .backgroundColor(Color.Gray)
              .borderRadius(16)
              .fontColor(Color.White)
              .onClick(() => {
                // 取消移动模式
                this.cancelMoving();
              })
          }
          .width('90%')
          .justifyContent(FlexAlign.SpaceAround)
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
        .translate({ y: -45 })
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
