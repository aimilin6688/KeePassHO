import { AddGroupDialog } from '../components/AddGroupDialog';
import { DatabaseShowParam, Icons, MoveParam } from '../services/TypeDefined';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FocusController } from '@ohos.arkui.UIContext';
import { motion } from '@kit.MultimodalAwarenessKit';

import { ClipboardUtils, CommonUtils, DateUtils, KdbxUtils, ResourceManager, ThemeManager, WindowUtils } from '../common/utils';
import { Kdbx, KdbxEntry, KdbxGroup, KdbxUuid } from 'kdbxweb';
import { PromptAction, Router } from '@kit.ArkUI';
import { FileService } from '../services/FileService';
import { SortMode } from '../common/constants/SortConstants';
import { SettingsService } from '../services/SettingsService';
import { SupportService } from '../services/SupportService';
import { EventBus } from '../services/EventBus';
import KdbxLoadService from '../services/kdbx/KdbxLoadService';
import { LoadDatabase } from '../workers/DatabaseLoadWorkerParam';
import { LoadMessage, SuccessMessage } from '../workers/WorkerParam';
import { TotpPreviewComponent } from '../components/TotpPreviewComponent';
import { RecentFilesService } from '../services/RecentFilesService';
import { ToastSaveDatabaseCallback } from '../workers/callback/ToastSaveDatabaseCallback';
import { emitter } from '@kit.BasicServicesKit';
import display from '@ohos.display';
import { common } from '@kit.AbilityKit';
import { CacheConstants } from '../storage/cache/CacheConstants';

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
  @State items: Array<KdbxGroup | KdbxEntry> = []; // 合并后的条目和分组列表
  @State filteredItems: Array<KdbxGroup | KdbxEntry> = []; // 过滤后的条目和分组列表
  @State showBack: boolean = false;
  @State showAddButtons: boolean = false; // 控制是否显示添加分组和添加条目按钮
  @State searchText: string = ''; // 搜索文本
  @State isSearching: boolean = false; // 是否处于搜索状态
  @State sortBy: SortMode = SortMode.DEFAULT; // 排序方式：'default' | 'name' | 'modified' | 'created'
  @State moveParam: MoveParam | undefined = undefined; // 移动参数
  @State refreshText: ResourceStr = $r('app.string.refreshing_message');
  @State isPullToRefresh: boolean = SettingsService.KEY_SECURITY_PULL_REFRESH_DEFAULT;
  @State isListShowTotp: boolean = SettingsService.KEY_SECURITY_LIST_SHOW_TOTP_DEFAULT;
  @State isShowSearchHistory: boolean = SettingsService.KEY_SECURITY_SEARCH_HISTORY_ENABLE_DEFAULT;
  @State isHoldingHandEnable: boolean = SettingsService.KEY_APP_HOLDING_HAND_ENABLE_DEFAULT;
  @State searchHistory: Array<string> = [];
  @State currentGroup: KdbxGroup | undefined = undefined;
  @State headerHeight: number = 56;
  @State selectedItem: KdbxGroup | KdbxEntry | null = null; // 当前选中的条目或分组
  @State selectedItemIndex: number = -1; // 当前选中项的索引
  @State showMoreMenu: boolean = false; // 是否显示更多操作菜单
  @State moreMenuX: number = 0; // 更多菜单X坐标
  @State moreMenuY: number = 0; // 更多菜单Y坐标
  // 拖拽组件
  @StorageLink("containerX") containerX: number = 0; // 容器X坐标
  @StorageLink("containerY") containerY: number = 0; // 容器Y坐标
  @State isDragging: boolean = false; // 是否正在拖拽
  private screenWidth: number = 360; // 屏幕宽度（默认值）
  private screenHeight: number = 640; // 屏幕高度（默认值）
  private maxX: number = 0; // 可移动x轴最大值
  private maxY: number = 0; // 可移动y轴最大值
  private containerWidth: number = 75; // 容器宽度
  private containerHeight: number = 135; // 容器高度
  private oldContainerX: number = 0; // 容器X坐标
  private oldContainerY: number = 0; // 容器Y坐标
  // 其他参数
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
      selectedIconId: this.getSelectedGroupIcon(),
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
  /**
   *  数据库重载事件
   */
  onDatabaseReload: Callback<emitter.EventData> = (eventData: emitter.EventData) => {
    this.reloadDatabase();
  }
  /**
   * 数据库更新事件
   */
  onDatabaseUpdate: Callback<emitter.EventData> = (eventData: emitter.EventData) => {
    hilog.debug(DOMAIN, TAG, 'Receive database update event');
    this.updateUI();
  }

  aboutToAppear() {
    this.clearUrl();
    this.initSettings();
    // 注册数据库事件
    this.registerDatabaseEvent();
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
    // 初始化屏幕大小
    this.initScreenSize();
  }

  aboutToDisappear() {
    EventBus.off(EventBus.DATABASE_RELOAD, this.onDatabaseReload);
    EventBus.off(EventBus.DATABASE_UPDATE, this.onDatabaseUpdate);
    // 移除主题监听器
    ThemeManager.getInstance().removeThemeChangeListenerAll();
    // 移除配置监听器
    this.settingsService.unregisterObserver(this.onSettingChanged);
    this.unBindHoldingHandChange();
  }

  onPageShow(): void {
    this.moveParam = MoveParam.getInstance();
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  // 获取选中的分组图标
  private getSelectedGroupIcon(): number | string {
    return this.editingGroupIndex >= 0 && this.editingGroupIndex < this.items.length &&
      this.items[this.editingGroupIndex] instanceof KdbxGroup
      ? (this.items[this.editingGroupIndex] as KdbxGroup).customIcon?.toString() ||
      (this.items[this.editingGroupIndex] as KdbxGroup).icon || Icons.Folder : Icons.Folder;
  }

  /**
   * 初始化屏幕大小
   */
  private initScreenSize() {
    try {
      // 获取屏幕尺寸
      this.screenWidth = this.getUIContext().px2vp(display.getDefaultDisplaySync().width);
      this.screenHeight = this.getUIContext().px2vp(display.getDefaultDisplaySync().height);
    } catch (error) {
      hilog.error(DOMAIN, TAG, `获取屏幕尺寸失败: ${error?.code}, ${error?.message}`,);
    }
    this.maxX = this.screenWidth - this.containerWidth;
    this.maxY = this.screenHeight - this.containerHeight - this.headerHeight;

    // 第一次初始化执行一次
    if (this.containerX == 0) {
      this.containerX = this.maxX - 22;
      this.containerY = this.maxY - 32;
    }
    this.onHoldingHandChange();
  }

  /**
   * 订阅握持手感知
   */
  private onHoldingHandChange() {
    //订阅握持手感知
    try {
      if (!this.isHoldingHandEnable) {
        return;
      }
      if (canIUse("SystemCapability.MultimodalAwareness.Motion")) {
        motion.on('holdingHandChanged', (status: motion.HoldingHandStatus) => {
          // 检测到左手
          if (motion.HoldingHandStatus.LEFT_HAND_HELD == status) {
            this.containerX = 0 + 22;
          }
          // 检测到右手
          else if (motion.HoldingHandStatus.RIGHT_HAND_HELD == status) {
            this.containerX = this.maxX - 22;
          }
        });
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, `订阅握持手感知失败: ${err?.code}, ${err?.message}`);
    }
  }

  /**
   * 取消订阅握持手感知
   */
  private unBindHoldingHandChange() {
    try {
      if (canIUse("SystemCapability.MultimodalAwareness.Motion")) {
        motion.off('holdingHandChanged');
      }
    } catch (error) {
      hilog.info(DOMAIN, TAG, `取消订阅握持手感知失败: ${error?.code}, ${error?.message}`);
    }
  }

  /**
   * 监听数据库变化
   */
  private registerDatabaseEvent() {
    EventBus.on(EventBus.DATABASE_RELOAD, this.onDatabaseReload);
    EventBus.on(EventBus.DATABASE_UPDATE, this.onDatabaseUpdate);
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
    // 搜索历史改变
    this.settingsService.get(SettingsService.KEY_SECURITY_SEARCH_HISTORY_ENABLE, SettingsService.KEY_SECURITY_SEARCH_HISTORY_ENABLE_DEFAULT)
      .then(result => {
        this.isShowSearchHistory = result;
      });
    // 智感握姿
    this.settingsService.get(SettingsService.KEY_APP_HOLDING_HAND_ENABLE, SettingsService.KEY_APP_HOLDING_HAND_ENABLE_DEFAULT).then(result => {
      this.isHoldingHandEnable = result;
      this.unBindHoldingHandChange();
      this.onHoldingHandChange();
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
      CommonUtils.showToast({
        message: $r('app.string.invalid_database'),
        duration: 2000
      });
      this.routerBack();
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
        hilog.info(DOMAIN, TAG, '%{public}s', `Invalid group: ${dbShowParam?.groupId}`)
        CommonUtils.showToast({ message: $r('app.string.invalid_group'), duration: 2000 });
        return;
      }
      // 合并分组和条目到一个数组
      this.items = [...this.currentGroup.groups, ...this.currentGroup.entries];
      KdbxUtils.sortBy(this.items, this.sortBy);
      this.addFavorite();
      hilog.info(DOMAIN, TAG, '%{public}s', `Loaded ${this.items.length} items`);
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', `Failed to process database: ${error}`);
      CommonUtils.showToast({ message: $r("app.string.load_database_failed"), duration: 2000 });
      // 返回到密码输入页面
      setTimeout(() => {
        this.routerBack();
      }, 2000);
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 关闭所有条目左滑操作按钮
   */
  private closeAllSwipeActions() {
    try {
      this.listScroller.closeAllSwipeActions();
    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', `Failed to close all swipe actions: ${error}`);
    }
  }

  /**
   * 条目左滑操作按钮
   */
  @Builder
  EntrySwipeActionButtons(index: number, item: KdbxEntry) {
    Row() {
      // 复制用户名按钮
      if (KdbxUtils.getFieldValueString(item.fields, KdbxUtils.FIELD_USERNAME) !== '') {
        Button() {
          Text($r('app.string.copy_username'))
            .fontSize(14)
            .fontColor(Color.White)
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width(80)
        .height('100%')
        .backgroundColor($r("app.color.button_bg_blue"))
        .borderRadius(0)
        .onClick(() => {
          this.copyUsername(item);
          this.closeAllSwipeActions();
        })
      }

      // 复制密码按钮
      if (KdbxUtils.getFieldValueString(item.fields, KdbxUtils.FIELD_PASSWORD) !== '') {
        Button() {
          Text($r('app.string.copy_password'))
            .fontSize(14)
            .fontColor(Color.White)
            .maxLines(2)
            .textAlign(TextAlign.Center)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .width(80)
        .height('100%')
        .backgroundColor($r("app.color.error"))
        .borderRadius(0)
        .onClick(() => {
          this.copyPassword(item);
          this.closeAllSwipeActions();
        })
      }

      // 更多按钮
      Button($r('app.string.more_button_text'), { type: ButtonType.Normal })
        .width(80)
        .height('100%')
        .backgroundColor($r("app.color.warn"))
        .fontSize(14)
        .onClick((event: ClickEvent) => {
          this.closeAllSwipeActions();
          this.showMoreActions(item, index, event);
        })
    }
    .height('100%')
  }

  /**
   * 分组左滑操作按钮
   */
  @Builder
  GroupSwipeActionButtons(index: number, item: KdbxGroup) {
    Row() {
      // 复制分组名按钮
      Button() {
        Text($r('app.string.copy_group_name'))
          .fontSize(14)
          .fontColor(Color.White)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .textAlign(TextAlign.Center)
      }
      .width(80)
      .height('100%')
      .backgroundColor($r("app.color.button_bg_blue"))
      .borderRadius(0)
      .onClick(() => {
        this.copyGroupName(item);
        this.closeAllSwipeActions();
      })

      // 更多按钮
      Button($r('app.string.more_button_text'), { type: ButtonType.Normal })
        .width(80)
        .height('100%')
        .backgroundColor($r("app.color.warn"))
        .fontSize(14)
        .onClick((event: ClickEvent) => {
          this.closeAllSwipeActions();
          this.showMoreActions(item, index, event);
        })
    }
    .height('100%')
  }

  /**
   * 显示更多操作菜单
   * @param item 条目或分组
   * @param index 索引
   * @param event 手势事件或点击事件（用于获取长按时的触摸位置）
   */
  private showMoreActions(item: KdbxGroup | KdbxEntry, index: number, event?: ClickEvent | GestureEvent) {
    this.selectedItem = item;
    this.selectedItemIndex = index;

    // 计算菜单水平位置（右对齐）
    const menuWidth = 280; // 菜单宽度
    // 右对齐，确保不超出屏幕边界
    this.moreMenuX = this.screenWidth - menuWidth - 12;

    // 计算菜单垂直位置
    let itemTopY: number = this.headerHeight + 12 + index * (70 + 8);

    if (event && (event as GestureEvent).fingerList && (event as GestureEvent).fingerList.length > 0) {
      itemTopY = (event as GestureEvent).fingerList[0].globalY;
    } else if (event && (event as ClickEvent).windowY) {
      itemTopY = (event as ClickEvent).windowY;
    }

    const menuHeight = 100; // 菜单高度（图标+文字）
    // 始终显示在条目正上方，留出10px间距
    this.moreMenuY = itemTopY - menuHeight - 60;
    // 确保不超出顶部
    if (this.moreMenuY < this.headerHeight + 10) {
      this.moreMenuY = this.headerHeight + 10;
    }
    this.showMoreMenu = true;
  }

  /**
   * 隐藏更多操作菜单
   */
  private hideMoreMenu() {
    this.showMoreMenu = false;
    this.selectedItem = null;
    this.selectedItemIndex = -1;
  }

  /**
   * 复制用户名
   */
  private copyUsername(entry: KdbxEntry) {
    const username = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_USERNAME);
    if (username) {
      ClipboardUtils.copyAutoClear(username);
    }
  }

  /**
   * 复制密码
   */
  private copyPassword(entry: KdbxEntry) {
    const password = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_PASSWORD);
    if (password) {
      ClipboardUtils.copyAutoClear(password);
    }
  }

  /**
   * 复制分组名
   */
  private copyGroupName(group: KdbxGroup) {
    const groupName = KdbxUtils.getFieldName(group.name);
    if (groupName && typeof groupName === 'string') {
      ClipboardUtils.copyAutoClear(groupName);
    }
  }

  /**
   * 编辑条目
   */
  private editEntry(entry: KdbxEntry) {
    CommonUtils.pushUrl({
      url: 'pages/EntryEdit',
      params: {
        groupId: entry.parentGroup?.uuid.id,
        entryId: entry.uuid.id
      }
    });
    this.hideMoreMenu();
  }

  /**
   * 编辑分组
   */
  private editGroup(group: KdbxGroup, index: number) {
    this.editingGroupIndex = index;
    this.newGroupName = group.name;
    this.dialogController.open();
    this.hideMoreMenu();
  }

  /**
   * 移动条目或分组
   */
  private moveItem(item: KdbxGroup | KdbxEntry) {
    if (item instanceof KdbxGroup) {
      this.moveParam = new MoveParam(item.uuid.id);
    } else if (item instanceof KdbxEntry) {
      this.moveParam = new MoveParam(item.parentGroup?.uuid.id || '', item.uuid.id);
    }
    this.hideMoreMenu();
  }

  /**
   * 删除条目或分组
   */
  private deleteItem(index: number) {
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
          if (index >= 0 && index < this.items.length) {
            deleteObj = this.items[index];
            this.items.splice(index, 1);
          }
          this.database.remove(deleteObj);
          this.saveDatabase();
          this.hideMoreMenu();
        }
      }
    });
  }

  /**
   * 更多操作菜单弹框（类似微信风格）
   */
  @Builder
  MoreActionsMenu() {
    Stack() {
      // 点击背景隐藏菜单
      Column()
        .width('100%')
        .height('100%')
        // .backgroundColor(Color.Black.opacity(0.3))
        .onClick(() => {
          this.hideMoreMenu();
        })

      // 菜单内容（横向排列）
      Row({ space: 12 }) {
        // 收藏按钮
        Column({ space: 8 }) {
          Button() {
            Column() {
              Image($r('app.media.ic_favorite'))
                .width(28)
                .height(28)
                .fillColor(this.selectedItem && KdbxUtils.isFavorite(this.selectedItem) ? $r('app.color.warn') : $r('app.color.text_primary'))
              Text(this.selectedItem && KdbxUtils.isFavorite(this.selectedItem) ? $r('app.string.unfavorite_button_text') : $r('app.string.favorite_button_text'))
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Center)
          }
          .height(48)
          .width(52)
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .onClick(() => {
            this.toggleFavorite();
          })
        }

        // 置顶按钮
        Column({ space: 8 }) {
          Button() {
            Column() {
              Image($r('app.media.ic_top'))
                .width(28)
                .height(28)
                .fillColor(this.selectedItem && KdbxUtils.isPinned(this.selectedItem) ? $r('app.color.button_bg_blue') : $r('app.color.text_primary'))
              Text(this.selectedItem && KdbxUtils.isPinned(this.selectedItem) ? $r('app.string.unpin_button_text') : $r('app.string.pin_button_text'))
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Center)
          }
          .height(48)
          .width(52)
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .onClick(() => {
            this.togglePin();
          })
        }

        // 编辑按钮
        Column() {
          Button() {
            Column() {
              Image($r('app.media.ic_edit'))
                .width(28)
                .height(28)
                .fillColor($r('app.color.text_primary'))
              Text($r('app.string.edit_button_text'))
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Center)
          }
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .height(48)
          .width(52)
          .onClick(() => {
            if (this.selectedItem instanceof KdbxEntry) {
              this.editEntry(this.selectedItem as KdbxEntry);
            } else if (this.selectedItem instanceof KdbxGroup) {
              this.editGroup(this.selectedItem as KdbxGroup, this.selectedItemIndex);
            }
          })
        }

        // 移动按钮
        Column({ space: 8 }) {
          Button() {
            Column() {
              Image($r('app.media.ic_move'))
                .width(28)
                .height(28)
                .fillColor($r('app.color.text_primary'))
              Text($r('app.string.move_button_text'))
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Center)
          }
          .height(48)
          .width(52)
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .onClick(() => {
            this.moveItem(this.selectedItem!);
          })
        }

        // 删除按钮
        Column({ space: 8 }) {
          Button() {
            Column() {
              Image($r('app.media.ic_delete'))
                .width(28)
                .height(28)
                .fillColor($r('app.color.text_primary'))
              Text($r('app.string.delete_button_text'))
                .fontSize(12)
                .fontColor($r('app.color.text_primary'))
                .margin({ top: 4 })
            }
            .alignItems(HorizontalAlign.Center)
          }
          .height(48)
          .width(52)
          .backgroundColor(Color.Transparent)
          .borderRadius(8)
          .onClick(() => {
            this.deleteItem(this.selectedItemIndex);
          })
        }
      }
      .width('auto')
      .height('auto')
      .borderRadius(12)
      .backgroundColor($r("app.color.card_bg"))
      .padding(12)
      .justifyContent(FlexAlign.SpaceEvenly)
      .borderColor($r("app.color.toast_bg"))
      .shadow(ShadowStyle.OUTER_DEFAULT_MD)
      .position({
        x: this.moreMenuX,
        y: this.moreMenuY
      })
    }
    .width('100%')
    .height('100%')
    .position({ x: 0, y: 0 })
    .zIndex(1000)
  }

  /**
   * 重新加载数据库（强制与远端合并）
   */
  private refreshDatabase() {
    this.isRefreshing = true;
    // 设置强制从远端刷新标志，忽略仅使用本地缓存的设置
    CacheConstants.setForceRefresh(true);
    
    let loadParam = LoadDatabase.byDbFileParam(FileService.getDbFileParam());
    KdbxLoadService.loadDatabase(loadParam, {
      onSuccessMessage: (successMessage: SuccessMessage) => {
        KdbxUtils.arrayBufferToKdbx(successMessage.data, loadParam).then((database: Kdbx) => {
          FileService.resetDbFileParam(database, successMessage.modifiedTime);
          this.refreshText = $r('app.string.refreshing_message');
          EventBus.emit<void>(EventBus.DATABASE_RELOAD);
          CommonUtils.showToast({ message: $r('app.string.refresh_success') });
          this.isRefreshing = false;
        }).catch((error: Error) => {
          this.refreshText = error.message;
          CommonUtils.showToast({ message: this.refreshText });
          this.isRefreshing = false;
        });
      },
      onLoadMessage: (message: LoadMessage) => {
        this.refreshText = ResourceManager.getString(message.message);
      },
      onErrorMessage: (message: LoadMessage) => {
        this.refreshText = ResourceManager.getString(message.message);
        CommonUtils.showToast({ message: this.refreshText });
        this.isRefreshing = false;
      },
    });
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

  /**
   * 置顶或取消置顶条目/分组
   */
  private togglePin() {
    if (!this.selectedItem || !this.database) {
      return;
    }
    // 切换置顶状态
    KdbxUtils.togglePinned(this.selectedItem);
    // 更新时间戳
    this.selectedItem.times.update();
    // 隐藏菜单
    this.hideMoreMenu();
    // 保存数据库
    this.saveDatabase();
  }

  /**
   * 收藏或取消收藏条目/分组
   */
  private toggleFavorite() {
    if (!this.selectedItem || !this.database) {
      return;
    }
    // 切换收藏状态
    KdbxUtils.toggleFavorite(this.selectedItem);
    // 更新时间戳
    this.selectedItem.times.update();
    // 隐藏菜单
    this.hideMoreMenu();
    // 保存数据库
    this.saveDatabase();
  }

  /**
   * 添加收藏数据
   */
  private addFavorite() {
    // 如果是默认分组，添加收藏的数据到最上方
    if (this.database && !this.showBack) {
      const favoriteItems = KdbxUtils.getFavoriteItems(this.database);
      // 过滤掉当前分组中已有的收藏项，避免重复
      const currentItemsUuid = new Set(this.items.map(item => item.uuid.id));
      const uniqueFavoriteItems = favoriteItems.filter(item => !currentItemsUuid.has(item.uuid.id));
      // 将收藏项添加到列表最前面
      this.items = [...uniqueFavoriteItems, ...this.items];
    }
  }

  private handleAddGroup(iconId?: number | string) {
    if (this.newGroupName === undefined || !this.newGroupName.trim()) {
      return;
    }
    if (!this.database) {
      CommonUtils.showToast({
        message: $r("app.string.invalid_database")
      });
      return;
    }

    let group: KdbxGroup;
    // 编辑现有分组
    if (this.editingGroupIndex >= 0 && this.editingGroupIndex < this.items.length && this.items[this.editingGroupIndex] instanceof KdbxGroup) {
      group = this.items[this.editingGroupIndex] as KdbxGroup;
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
      CommonUtils.showToast({
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
        CommonUtils.showToast({
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
          CommonUtils.showToast({
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
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to move item: %{public}s', error.message);
      CommonUtils.showToast({
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
    hilog.debug(DOMAIN, TAG, 'Execute updateUI');
    // 保存当前滚动位置
    let savedScrollOffset = this.listScroller.currentOffset()?.yOffset || 0;
    // 强制刷新UI - 先清空数组，再重新加载
    this.items = [];
    // 延迟一帧后重新加载数据，确保UI更新
    setTimeout(() => {
      // 重新更新当前分组
      if (this.currentGroup) {
        this.currentGroup = this.database?.getGroup(this.currentGroup.uuid);
      }
      // 合并分组和条目到一个数组
      this.items = [...this.currentGroup?.groups || [], ...this.currentGroup?.entries || []];
      // 对合并后的数组进行排序
      KdbxUtils.sortBy(this.items, this.sortBy);
      // 如果在搜索状态，更新搜索结果
      if (this.isSearching && this.searchText.length > 0) {
        this.performSearch();
      } else if (this.isSearching) {
        this.filteredItems = [...this.items];
      } else {
        // 非搜索状态，添加收藏数据
        this.addFavorite();
      }
      // 恢复滚动位置
      setTimeout(() => {
        this.listScroller.scrollTo({ xOffset: 0, yOffset: savedScrollOffset, animation: { duration: 0 } });
      }, 50);
    }, 10);
  }

  /**
   * 执行搜索
   */
  private performSearch() {
    if (!this.searchText || this.searchText.trim() === '') {
      // 如果搜索文本为空，显示所有分组和条目
      this.filteredItems = [...this.items];
      return;
    }
    if (this.isSearching) {
      // 全局搜索模式：搜索整个数据库
      this.filteredItems = [];

      if (this.database) {
        let result = KdbxUtils.searchInGroup(this.database.getDefaultGroup(), this.searchText);
        // 合并搜索结果：分组在前，条目在后
        this.filteredItems.push(...result.filteredGroups, ...result.filteredEntries);
        KdbxUtils.sortBy(this.filteredItems, this.sortBy);
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
    CommonUtils.pushUrl({ url: 'pages/UnLockDatabase' })
  }

  /**
   * 执行搜索
   */
  private showSearch() {
    this.isSearching = true;
    this.searchText = '';
    this.filteredItems = [...this.items];
    // 获取搜索历史
    this.loadSearchHistory();
    this.showSearchAnimate();
  }

  /**
   * 显示搜索动画
   */
  private showSearchAnimate() {
    this.getUIContext().animateTo({ curve: Curve.Ease, duration: 200 }, () => {
      if (this.isShowHistory()) {
        this.headerHeight = 114;
      } else {
        this.headerHeight = 56;
      }
    });
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
    if (this.isShowSearchHistory) {
      RecentFilesService.getSearchHistory(this.filePath).then(history => {
        this.searchHistory = history;
      });
    }
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
    return this.isSearching && this.isShowSearchHistory;
  }

  private routerBack() {
    if (parseInt(this.router.getLength()) > 0) {
      this.router.back();
    }
  }

  build() {
    Stack() {
      // 更多操作菜单
      if (this.showMoreMenu) {
        this.MoreActionsMenu()
      }

      Column() {
        // 顶部导航栏
        Row() {
          if (this.isSearching) {
            Column() {
              Row() {
                // 搜索框
                Search({ placeholder: $r('app.string.search_placeholder'), value: this.searchText })
                  .margin({ left: 16 })
                  .height(40)
                  .layoutWeight(1)
                  .flexShrink(1)
                  .id("searchKey")
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
                Button($r('app.string.cancel_button_text'))
                  .width(70)
                  .height(40)
                  .fontSize(16)
                  .flexShrink(0)
                  .fontColor($r('app.color.text_primary'))
                  .backgroundColor($r("app.color.card_bg"))
                  .margin({ right: 16 })
                  .padding({ left: 5, right: 5 })
                  .onClick(() => {
                    this.isSearching = false;
                    this.showSearchAnimate();
                    this.searchText = '';
                    this.filteredItems = [];
                  })
              }
              .width('100%')

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
                    .width('100%')
                    .height('auto')

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
            }
            .margin({ top: 12 })
            .width('100%')
          } else {
            Row() {
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
              }
              .margin({ right: 25 })
              .layoutWeight(1)
              .flexShrink(1)

              Row() {
                // 搜索按钮
                Image($r('app.media.ic_search'))
                  .width(24)
                  .height(24)
                  .margin({ right: 12 })
                  .onClick(() => {
                    this.showSearch();
                  })
                // 锁定数据库
                Image($r('app.media.ic_lock'))
                  .width(24)
                  .height(24)
                  .margin({ right: 12 })
                  .fillColor($r('app.color.text_primary'))
                  .onClick(() => {
                    this.lockDatabase();
                  })
                Image($r('app.media.ic_settings'))
                  .width(24)
                  .height(24)
                  .margin({ right: 16 })
                  .onClick(() => {
                    CommonUtils.pushUrl({ url: 'pages/setting/Settings' }).catch(() => {
                      hilog.error(DOMAIN, TAG, 'pushUrl error: pages/setting/Settings');
                    });
                  })
              }
              .flexShrink(0)
              .width(112)
            }
            .alignItems(VerticalAlign.Center)
            .width('100%')
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height(this.headerHeight)

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
              if (this.items.length === 0) {
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
                ForEach(this.isSearching ? this.filteredItems : this.items, (item: KdbxGroup | KdbxEntry, index: number) => {
                  if (item instanceof KdbxGroup) {
                    ListItem() {
                      Stack({ alignContent: Alignment.TopEnd }) {
                        Row() {
                          Image(KdbxUtils.getIcon(item.icon, item.customIcon, $r('app.media.ic_folder_open')))
                            .width(36)
                            .height(36)
                            .margin(10)
                          Column() {
                            Text(KdbxUtils.getFieldName(item.name))
                              .fontSize(18)
                              .textAlign(TextAlign.Start)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .flexGrow(1)
                              .maxLines(1)
                            Text($r("app.string.group_items_message", this.groupItemCount(item)))
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
                            .width(28)
                            .height(28)
                            .margin({ right: 0 })
                            .fillColor($r('app.color.text_primary'))
                        }
                        .padding({ left: 2 })
                        .width('100%')

                        // 置顶标记
                        if (KdbxUtils.isPinned(item)) {
                          Polygon()
                            .points([[0, 0], [16, 0], [0, 16]])
                            .fill($r('app.color.button_bg_blue'))
                            .width(16)
                            .height(16)
                            .position({ x: 0, y: 6 })
                        }
                        // 收藏标记
                        if (KdbxUtils.isFavorite(item)) {
                          Image($r('app.media.ic_favorite'))
                            .width(16)
                            .height(16)
                            .fillColor($r('app.color.warn'))
                            .position({ x: -2, y: 24 })
                        }
                      }
                      .height(66)
                      .borderRadius(8)
                      .backgroundColor((this.moveParam && this.moveParam.isMoveItem(item.uuid.id)) ? $r("app.color.item_selected") :
                        $r("app.color.card_bg"))
                      .padding({ left: 6, right: 6 })
                      .onClick(() => {
                        CommonUtils.pushUrl({ url: 'pages/DatabaseView', params: { groupId: item.uuid.id } });
                      })
                      .gesture(
                        LongPressGesture({ repeat: false })
                          .onAction((event: GestureEvent) => {
                            this.showMoreActions(item, index, event);
                          })
                      )
                    }
                    .swipeAction({
                      end: {
                        builder: () => this.GroupSwipeActionButtons(index, item)
                      }
                    })
                  } else {
                    ListItem() {
                      Stack({ alignContent: Alignment.TopEnd }) {
                        Row() {
                          Image(DateUtils.isExpired(item.times.expires, item.times.expiryTime) ? $r('app.media.C45_Expired') :
                            KdbxUtils.getIcon(item.icon, item.customIcon, $r('app.media.ic_file')))
                            .width(36)
                            .height(36)
                            .margin(10)
                          Column() {
                            Text(KdbxUtils.getFieldValueString(item.fields, KdbxUtils.FIELD_TITLE))
                              .fontSize(18)
                              .textAlign(TextAlign.Start)
                              .flexGrow(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .maxLines(1)
                              .decoration({
                                type: (DateUtils.isExpired(item.times.expires, item.times.expiryTime) ? TextDecorationType.LineThrough :
                                  TextDecorationType.None)
                              })
                            Text(KdbxUtils.getFieldValueString(item.fields, KdbxUtils.FIELD_USERNAME))
                              .fontSize(12)
                              .textAlign(TextAlign.Start)
                              .flexGrow(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .maxLines(1)
                              .margin({ top: 4 })
                              .decoration({
                                type: (DateUtils.isExpired(item.times.expires, item.times.expiryTime) ? TextDecorationType.LineThrough :
                                  TextDecorationType.None)
                              })
                            // TOTP 字段展示
                            if (this.isListShowTotp) {
                              ForEach(KdbxUtils.getTotpUrl(item), (totpUrl: string, index: number) => {
                                TotpPreviewComponent({
                                  totpUrl: totpUrl,
                                  doClick: (value) => {
                                    ClipboardUtils.copyAutoClear(value);
                                    return false;
                                  }
                                })
                              });
                            }
                          }
                          .flexGrow(1)
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)

                          Image($r('app.media.ic_arrow_right'))
                            .width(28)
                            .height(28)
                            .margin({ right: 0 })
                            .fillColor($r('app.color.text_primary'))
                        }
                        .padding({ left: 2 })
                        .width('100%')

                        // 置顶标记
                        if (KdbxUtils.isPinned(item)) {
                          Polygon()
                            .points([[0, 0], [16, 0], [0, 16]])
                            .fill($r('app.color.button_bg_blue'))
                            .width(16)
                            .height(16)
                            .position({ x: 0, y: 0 })
                        }
                        // 收藏标记
                        if (KdbxUtils.isFavorite(item)) {
                          Image($r('app.media.ic_favorite'))
                            .width(16)
                            .height(16)
                            .fillColor($r('app.color.warn'))
                            .position({ x: -2, y: 18 })
                        }
                      }
                      .borderRadius(8)
                      .backgroundColor((this.moveParam && this.moveParam.isMoveItem(item.uuid.id)) ? $r("app.color.button_bg_blue") :
                        $r("app.color.card_bg"))
                      .padding({
                        left: 6,
                        right: 6,
                        top: 8,
                        bottom: 8
                      })
                      .onClick(() => {
                        CommonUtils.pushUrl({
                          url: 'pages/EntryView',
                          params: { entryId: item.uuid.id, groupId: item.parentGroup?.uuid.id }
                        });
                      })
                      .gesture(
                        LongPressGesture({ repeat: false })
                          .onAction((event: GestureEvent) => {
                            this.showMoreActions(item, index, event);
                          })
                      )
                    }
                    .swipeAction({
                      end: {
                        builder: () => this.EntrySwipeActionButtons(index, item)
                      }
                    })
                  }

                }, (item: KdbxGroup, index: number) => `${index}-${item.uuid.id}`)
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
          this.showAddButtons = false;
        })
        .visibility(this.showAddButtons ? Visibility.Visible : Visibility.None)

      // 可以拖拽的控制按钮
      Column() {
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
        .margin({ bottom: 8, top: 12 })
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
        .margin({ bottom: 8, top: 4 })
        .enabled(!this.isLoading)
        .visibility(this.showAddButtons ? Visibility.Visible : Visibility.None)
        .onClick(() => {
          this.showAddButtons = false;
          CommonUtils.pushUrl({
            url: 'pages/EntryEdit',
            params: {
              groupId: this.currentGroup?.uuid.id
            }
          });
        })

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
        .margin({ bottom: 8, top: 8 })
        .enabled(!this.isLoading)
        .opacity(this.isLoading ? 0.5 : 1)
        .visibility(this.showAddButtons ? Visibility.Hidden : Visibility.Visible)
        .onClick(() => {
          CommonUtils.pushUrl({ url: 'pages/TotpView' });
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
        .enabled(!this.isLoading)
        .opacity(this.isLoading ? 0.5 : 1)
        .visibility(this.showAddButtons ? Visibility.Hidden : Visibility.Visible)
        .onClick(() => {
          this.showAddButtons = true;
        })
      }
      .width(this.containerWidth)
      .height(this.containerHeight)
      .visibility(this.moveParam ? Visibility.None : Visibility.Visible)
      .zIndex(999)
      .gesture(
        // 拖拽手势
        PanGesture({ fingers: 1, direction: PanDirection.All })
          .onActionStart(() => {
            this.isDragging = true;
            this.oldContainerX = this.containerX;
            this.oldContainerY = this.containerY;
          })
          .onActionUpdate((event: GestureEvent) => {
            // 计算新位置
            if (this.isDragging) {
              this.containerX = Math.max(0, Math.min(this.oldContainerX + event.offsetX, this.maxX));
              this.containerY = Math.max(0, Math.min(this.oldContainerY + event.offsetY, this.maxY));
            }
          })
          .onActionEnd(() => {
            this.isDragging = false;
          })
      )
      .position({ x: this.containerX, y: this.containerY })
      .animation({
        duration: 200,
        curve: Curve.EaseInOut
      })

      // 移动模式下的底部浮动按钮
      if (this.moveParam) {
        Column() {
          Row() {
            Button($r('app.string.move_here'), { type: ButtonType.Normal })
              .width('45%')
              .height(40)
              .margin({ right: 8 })
              .borderRadius(20)
              .fontColor($r("app.color.button_text_blue"))
              .backgroundColor($r("app.color.button_bg_blue"))
              .onClick(() => {
                this.moveItemToCurrentGroup();
              })

            Button($r('app.string.cancel_button_text'), { type: ButtonType.Normal })
              .width('45%')
              .height(40)
              .backgroundColor(Color.Gray)
              .borderRadius(20)
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
