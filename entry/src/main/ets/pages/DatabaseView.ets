import KdbxSaveService from '../services/kdbx/KdbxSaveService';
import { AddGroupDialog } from '../components/AddGroupDialog';
import { DatabaseShowParam, EntryParam, Icons, MoveParam, TemplateEntryCreateParam } from '../services/TypeDefined';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { FocusController } from '@ohos.arkui.UIContext';
import { motion } from '@kit.MultimodalAwarenessKit';
import { ClipboardUtils, CommonUtils, DateUtils, KdbxUtils, NavigationManager, ResourceManager, ThemeManager, WindowUtils, StringUtils } from '../common/utils';
import { WindowService, WindowInfo } from '../common/utils/WindowService';
import { PageConstants } from '../common/constants/PageConstants';
import { NavigationConstants } from '../common/constants/NavigationConstants';
import { Kdbx, KdbxEntry, KdbxFieldReference, KdbxGroup, KdbxUuid } from 'kdbxweb';
import { FileService } from '../services/FileService';
import { LockScreenService } from '../services/LockScreenService';
import { SortMode } from '../common/constants/SortConstants';
import { SettingsService, BreadcrumbPosition } from '../services/SettingsService';
import { SupportService } from '../services/SupportService';
import { EventBus } from '../services/EventBus';
import KdbxLoadService from '../services/kdbx/KdbxLoadService';
import { LoadDatabase } from '../workers/DatabaseLoadWorkerParam';
import { LoadMessage, ProgressMessage, SuccessMessage } from '../workers/WorkerParam';
import { TotpPreviewComponent } from '../components/TotpPreviewComponent';
import { RecentFilesService } from '../services/RecentFilesService';
import { ToastSaveDatabaseCallback } from '../workers/callback/ToastSaveDatabaseCallback';
import { emitter } from '@kit.BasicServicesKit';
import display from '@ohos.display';
import { common } from '@kit.AbilityKit';
import { CacheConstants } from '../storage/cache/CacheConstants';
import { TemplateSelectorDialog } from '../components/TemplateSelectorDialog';
import { ITemplate, isPresetTemplate, IPresetTemplate, IUserTemplate } from '../services/template/TemplateTypes';
import { UIUtils } from '@kit.ArkUI';
import window from '@ohos.window';

// 面包屑导航路径项接口
interface NavigationPathItem {
  id: string;
  name: string;
}

const DOMAIN = 0x0000;
const TAG = 'DatabaseView';

// DatabaseView页面的Builder函数
@Builder
export function DatabaseViewBuilder(name: string, param: Object): void {
  DatabaseView({ databaseShowParam: param as DatabaseShowParam })
}

@Component
export struct DatabaseView {
  private navManager: NavigationManager = NavigationManager.getInstance();
  private navPathStack: NavPathStack = NavigationManager.getInstance().getNavPathStackByRoot('DatabaseView')!;
  private databaseShowParam: DatabaseShowParam | undefined = undefined;
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
  // 使用 @StorageLink 持久化当前分组ID，用于从设置返回时恢复状态
  @StorageLink('databaseView_currentGroupId') currentGroupId: string = '';
  // 面包屑导航路径
  @State navigationPath: NavigationPathItem[] = []; // 导航路径：[{id: 'root', name: '/'}]
  @State isBreadcrumbVisible: boolean = SettingsService.KEY_APP_BREADCRUMB_VISIBLE_DEFAULT; // 面包屑导航可见性
  @State breadcrumbPosition: BreadcrumbPosition = SettingsService.KEY_APP_BREADCRUMB_POSITION_DEFAULT; // 面包屑导航位置
  @State headerHeight: number = 48;
  @State selectedItem: KdbxGroup | KdbxEntry | null = null; // 当前选中的条目或分组
  @State selectedItemIndex: number = -1; // 当前选中项的索引
  @State selectedEntryId: string = ''; // 分栏模式下当前右侧显示的条目ID
  @State showMoreMenu: boolean = false; // 是否显示更多操作菜单
  @State moreMenuX: number = 0; // 更多菜单X坐标
  @State moreMenuY: number = 0; // 更多菜单Y坐标
  // 批量操作相关状态
  @State isSelectionMode: boolean = false; // 是否处于选择模式
  @State selectedItems: Map<string, KdbxGroup | KdbxEntry> = new Map(); // 选中的条目或分组
  @State moveSourceGroupId: string = ''; // 移动操作的源分组ID
  // AlphabetIndexer 相关状态
  @State indexerSelected: number = 0; // AlphabetIndexer 选中索引
  @State indexerValues: string[] = []; // 索引字母数组
  @State indexerMap: Map<string, number> = new Map(); // 字母到列表索引的映射
  // 拖拽组件
  @StorageLink("containerX") containerX: number = 0; // 容器X坐标
  @StorageLink("containerY") containerY: number = 0; // 容器Y坐标
  @StorageLink("navBarWidth") @Watch('onNavBarWidthChanged') currentNavBarWidth: number = NavigationConstants.DEFAULT_NAV_BAR_WIDTH; // 当前导航栏实际宽度
  @State isDragging: boolean = false; // 是否正在拖拽
  private screenWidth: number = 360; // 屏幕宽度（默认值）
  private screenHeight: number = 640; // 屏幕高度（默认值）
  // 订阅响应式窗口信息：分栏/单栏判定的单一事实来源（与 Navigation 显示模式保持一致）
  @State windowInfo: WindowInfo = WindowService.getInstance().info;
  private maxX: number = 0; // 可移动x轴最大值
  private maxY: number = 0; // 可移动y轴最大值
  private containerWidth: number = 75; // 容器宽度
  private containerHeight: number = 135; // 容器高度
  private oldContainerX: number = 0; // 容器X坐标
  private oldContainerY: number = 0; // 容器Y坐标
  // 其他参数
  private database: Kdbx | null = null;
  private filePath: string = '';
  private settingsService: SettingsService = SettingsService.getInstance();
  // 模板选择对话框控制器
  private templateSelectorController: CustomDialogController = new CustomDialogController({
    builder: TemplateSelectorDialog({
      database: this.database,
      showUserTemplates: true,
      onTemplateSelected: (template: ITemplate) => {
        this.handleTemplateSelected(template);
      }
    }),
    alignment: DialogAlignment.Bottom,
    customStyle: true,
    autoCancel: false,
    keyboardAvoidMode: KeyboardAvoidMode.NONE
  });
  private searchController: FocusController = new FocusController();
  private listScroller: ListScroller = new ListScroller();
  private clearHistoryUrlPage: Array<string> = ["Password"];
  private windowClass: window.Window | undefined = undefined; // 窗口实例
  private dialogController: CustomDialogController = new CustomDialogController({
    builder: AddGroupDialog({
      newGroupName: this.newGroupName,
      editingGroupIndex: this.editingGroupIndex,
      selectedIconId: this.getSelectedGroupIcon(),
      initialFgColor: this.getSelectedGroupFgColor(),
      initialBgColor: this.getSelectedGroupBgColor(),
      onConfirm: (iconId: number | string, fgColor: string | undefined, bgColor: string | undefined): void => this.handleAddGroup(iconId, fgColor, bgColor),
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
  /**
   * 根页面变化监听器
   */
  private rootPageChangeListener = (rootPage: string): void => {
    hilog.info(DOMAIN, TAG, 'Root page changed to: %{public}s', rootPage);
    if (rootPage === 'DatabaseView') {
      // 切换到 DatabaseView 时检查是否需要加载数据库
      const params = FileService.getDbFileParam();
      // 数据库已切换：FileService 中的实例与当前列表持有的实例不同（切换数据库后 Password 会写入新实例）
      const isDatabaseSwitched = this.database !== undefined && this.database !== null
        && this.database !== params.database;
      if (params.database && (!this.database || isDatabaseSwitched)) {
        // 数据库已切换时重置分组状态，避免旧分组 ID 在新库中无效
        if (isDatabaseSwitched) {
          this.currentGroupId = '';
          this.currentGroup = undefined;
          this.navigationPath = [];
        }
        // 数据库已打开但当前组件还未加载，重新加载
        hilog.info(DOMAIN, TAG, 'Database available, loading...');
        this.loadDatabase();
        // 显示支持弹框（每天首次进入数据库页面时）
        SupportService.showSupportDialog(this.getUIContext());
      } else {
        // 恢复分组状态
        this.restoreGroupState();
      }
    }
  };

  /**
   * 系统返回键的上下文处理器。
   *
   * DatabaseView 内部进入子分组是「原位切换」（更新 currentGroup/items），
   * 并未压入 NavDestination 路由栈，因此系统返回无法被 Navigation 消费而被带到 Ability 层。
   * 这里在根页面为 DatabaseView 且处于子分组（存在父分组）时消费返回事件：向上返回一层分组。
   * 处于根分组、锁屏、或非 DatabaseView 根页面时返回 false：
   *   - 根分组：保持默认退出行为；
   *   - 非 DatabaseView 根页面（如 Settings/TotpView）：交由 NavigationManager.handleSystemBack
   *     的二级逻辑回到上一个根页面，避免直接退出应用。
   */
  private systemBackHandler: () => boolean = (): boolean => {
    if (this.navManager.getCurrentRootPage() !== PageConstants.PAGE_DATABASE_VIEW) {
      return false;
    }
    if (AppStorage.get<boolean>('isLocked')) {
      return false;
    }
    if (this.currentGroup && this.currentGroup.parentGroup) {
      this.navigateToParentGroup();
      return true;
    }
    return false;
  };

  aboutToAppear() {
    this.clearUrl();
    this.initSettings();
    // 注册数据库事件
    this.registerDatabaseEvent();
    // 注册根页面变化监听
    this.navManager.addRootPageChangeListener(this.rootPageChangeListener);
    // 注册系统返回键的上下文处理器（处理子分组原位导航的系统返回）
    this.navManager.setSystemBackHandler(this.systemBackHandler);
    // 不在这里调用 loadDatabase()，因为此时数据库可能还没打开
    // 数据库加载会在 rootPageChangeListener 中触发
    // 监听主题变化
    ThemeManager.getInstance().addThemeChangeListener(() => {
      this.onThemeChanged();
    });
    // 监听排序方式变化
    this.settingsService.registerObserver(this.onSettingChanged);
    // 初始化窗口大小并注册监听器（支持小窗模式）
    this.initWindowAndListener();
  }

  aboutToDisappear() {
    EventBus.off(EventBus.DATABASE_RELOAD, this.onDatabaseReload);
    EventBus.off(EventBus.DATABASE_UPDATE, this.onDatabaseUpdate);
    // 移除根页面变化监听
    this.navManager.removeRootPageChangeListener(this.rootPageChangeListener);
    // 注销系统返回键的上下文处理器
    this.navManager.setSystemBackHandler(null);
    // 移除主题监听器
    ThemeManager.getInstance().removeThemeChangeListenerAll();
    // 移除配置监听器
    this.settingsService.unregisterObserver(this.onSettingChanged);
    this.unBindHoldingHandChange();
    // 取消窗口大小变化监听
    this.unregisterWindowListener();
  }

  onPageShow(): void {
    this.moveParam = MoveParam.getInstance();
    // 页面显示时刷新设置，保证与最新配置一致
    this.initSettings();
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  // 获取选中的分组图标
  private getSelectedGroupIcon(): number | string {
    return this.editingGroupIndex >= 0 && this.editingGroupIndex < this.items.length &&
      this.items[this.editingGroupIndex] instanceof KdbxGroup
      ? (this.items[this.editingGroupIndex] as KdbxGroup).customIcon?.toString() ||
      (this.items[this.editingGroupIndex] as KdbxGroup).icon || Icons.Folder : Icons.Folder;
  }

  // 获取选中的分组前景色
  private getSelectedGroupFgColor(): string | undefined {
    return this.editingGroupIndex >= 0 && this.editingGroupIndex < this.items.length &&
      this.items[this.editingGroupIndex] instanceof KdbxGroup
      ? (this.items[this.editingGroupIndex] as KdbxGroup).fgColor : undefined;
  }

  // 获取选中的分组背景色
  private getSelectedGroupBgColor(): string | undefined {
    return this.editingGroupIndex >= 0 && this.editingGroupIndex < this.items.length &&
      this.items[this.editingGroupIndex] instanceof KdbxGroup
      ? (this.items[this.editingGroupIndex] as KdbxGroup).bgColor : undefined;
  }

  /**
   * 更新窗口尺寸和按钮位置
   * @param width 窗口宽度（px）
   * @param height 窗口高度（px）
   * @param isFirstInit 是否为第一次初始化
   */
  private updateWindowBounds(width: number, height: number, isFirstInit: boolean = false) {
    // 将px转换为vp
    this.screenWidth = this.getUIContext().px2vp(width);
    this.screenHeight = this.getUIContext().px2vp(height);

    // 在分栏模式下，按钮应该在左侧导航栏范围内定位
    // 判断是否处于分栏模式（与 Navigation 显示模式同源，见 WindowService）
    const isSplitMode = this.windowInfo.isSplitMode;

    // 计算按钮可移动的最大边界
    // 分栏模式下：限制在导航栏宽度范围内（使用实际宽度或默认宽度）
    // 非分栏模式下：限制在整个屏幕宽度范围内
    // 注意：在分栏模式下，导航栏宽度可能在 [240, 700] 范围内动态变化
    // 这里使用 currentNavBarWidth（通过 StorageLink 共享），如果没有设置则使用默认值
    const availableWidth = isSplitMode ? this.currentNavBarWidth : this.screenWidth;

    this.maxX = availableWidth - this.containerWidth;
    this.maxY = this.screenHeight - this.containerHeight - 16; // 距离底部保留16vp的安全距离

    // 首次初始化：设置默认位置（如果按钮未被移动过）
    if (isFirstInit && this.containerX === 0) {
      this.containerX = this.maxX - 22;
      this.containerY = this.maxY - 32;
    }

    // 窗口大小变化或导航栏宽度变化时：确保按钮在边界内
    if (!isFirstInit) {
      // 确保 X 坐标在有效范围内
      if (this.containerX > this.maxX) {
        this.containerX = Math.max(0, this.maxX - 22);
      } else if (this.containerX < 0) {
        this.containerX = 22;
      }
      // 确保 Y 坐标在有效范围内
      if (this.containerY > this.maxY) {
        this.containerY = Math.max(0, this.maxY - 32);
      } else if (this.containerY < 0) {
        this.containerY = 32;
      }
    }
  }

  /**
   * 初始化窗口大小并注册监听器（统一处理初始化和窗口变化）
   */
  private initWindowAndListener() {
    try {
      // 获取当前窗口实例
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      this.windowClass = context.windowStage.getMainWindowSync();

      if (this.windowClass) {
        // 获取当前窗口尺寸（支持小窗模式）
        const windowSize = this.windowClass.getWindowProperties().windowRect;
        
        // 第一次初始化窗口大小
        this.updateWindowBounds(windowSize.width, windowSize.height, true);

        // 注册窗口大小变化监听器
        this.windowClass.on('windowSizeChange', (size: window.Size) => {
          hilog.debug(DOMAIN, TAG, `Window size changed: ${size.width}x${size.height}`);
          // 窗口大小变化时更新边界
          this.updateWindowBounds(size.width, size.height, false);
        });
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `初始化窗口失败: ${error?.code}, ${error?.message}`);
      // 降级方案：使用屏幕尺寸
      try {
        const displayInfo = display.getDefaultDisplaySync();
        this.updateWindowBounds(displayInfo.width, displayInfo.height, true);
      } catch (displayError) {
        hilog.error(DOMAIN, TAG, `获取屏幕尺寸失败: ${displayError?.code}, ${displayError?.message}`);
      }
    }

    // 初始化握持手感知
    this.onHoldingHandChange();
  }

  /**
   * 取消监听窗口大小变化
   */
  private unregisterWindowListener() {
    try {
      if (this.windowClass) {
        this.windowClass.off('windowSizeChange');
      }
    } catch (error) {
      hilog.error(DOMAIN, TAG, `取消窗口监听失败: ${error?.code}, ${error?.message}`);
    }
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
      hilog.warn(DOMAIN, TAG, `订阅握持手感知失败: ${err?.code}, ${err?.message}`);
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
    // 列表显示TOTP（同步读取，避免异步回调晚于首帧渲染导致短暂显示）
    this.isListShowTotp = this.settingsService.getSync(
      SettingsService.KEY_SECURITY_LIST_SHOW_TOTP,
      SettingsService.KEY_SECURITY_LIST_SHOW_TOTP_DEFAULT
    );
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
    // 面包屑导航可见性
    this.isBreadcrumbVisible = this.settingsService.getSync(
      SettingsService.KEY_APP_BREADCRUMB_VISIBLE,
      SettingsService.KEY_APP_BREADCRUMB_VISIBLE_DEFAULT
    );
    // 面包屑导航位置
    this.breadcrumbPosition = this.settingsService.getSync(
      SettingsService.KEY_APP_BREADCRUMB_POSITION,
      SettingsService.KEY_APP_BREADCRUMB_POSITION_DEFAULT
    );
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

    // 重新读取设置：组件在应用启动阶段即创建，此时 SettingsService 可能尚未初始化完成，
    // 首次 initSettings 读到的可能是默认值，打开数据库时再次读取确保使用真实配置
    this.initSettings();

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
    // 在 Navigation 系统中,如果需要清空历史,可以调用 navPathStack.clear()
    // 暂时保留此方法的接口,具体逻辑需要根据业务需求调整
    // this.navPathStack.clear();
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

  /**
   * 监听导航栏宽度变化
   * 当用户拖拽调整分栏宽度时，更新按钮边界
   */
  private onNavBarWidthChanged() {
    hilog.info(DOMAIN, TAG, 'Navigation bar width changed to: %{public}d', this.currentNavBarWidth);

    // currentNavBarWidth 已是实际可用宽度（分栏=导航栏宽，单列=屏宽），直接计算边界
    this.maxX = this.currentNavBarWidth - this.containerWidth;

    // 确保按钮在新边界内
    if (this.containerX > this.maxX) {
      this.containerX = Math.max(0, this.maxX - 22);
    }
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

    // 读取面包屑导航可见性设置
    this.isBreadcrumbVisible = this.settingsService.getSync(
      SettingsService.KEY_APP_BREADCRUMB_VISIBLE,
      SettingsService.KEY_APP_BREADCRUMB_VISIBLE_DEFAULT
    );
    // 读取面包屑导航位置设置
    this.breadcrumbPosition = this.settingsService.getSync(
      SettingsService.KEY_APP_BREADCRUMB_POSITION,
      SettingsService.KEY_APP_BREADCRUMB_POSITION_DEFAULT
    );

    this.isLoading = true;
    try {
      // 优先使用保存的分组ID（从设置返回时恢复状态）
      if (this.currentGroupId && !dbShowParam?.groupId) {
        const savedGroup = this.database.getGroup(this.currentGroupId);
        if (savedGroup) {
          this.currentGroup = savedGroup;
          this.titleName = KdbxUtils.getFieldName(savedGroup.name) || '';
          this.showBack = savedGroup.parentGroup !== undefined &&
            savedGroup.uuid.id !== this.database.getDefaultGroup()?.uuid.id;
          hilog.info(DOMAIN, TAG, 'Restored group from saved state: %{public}s', this.currentGroupId);
        } else {
          // 保存的分组ID无效，使用根分组
          this.currentGroup = this.database.getDefaultGroup();
          this.titleName = KdbxUtils.getFieldName(this.currentGroup?.name) || '';
          this.showBack = false;
          this.currentGroupId = '';
        }
      } else if (dbShowParam && dbShowParam.groupId) {
        this.currentGroup = this.database.getGroup(dbShowParam.groupId);
        this.titleName = KdbxUtils.getFieldName(this.currentGroup?.name) || '';
        this.showBack = true;
        // 保存分组ID
        this.currentGroupId = this.currentGroup?.uuid.id || '';
      } else {
        // 获取根分组下的所有子分组
        this.currentGroup = this.database.getDefaultGroup();
        this.titleName = KdbxUtils.getFieldName(this.currentGroup?.name) || '';
        this.showBack = false;
        // 清空保存的分组ID
        this.currentGroupId = '';
      }

      // 判断分组是否有效
      if (this.currentGroup === undefined) {
        hilog.info(DOMAIN, TAG, '%{public}s', `Invalid group: ${dbShowParam?.groupId}`)
        CommonUtils.showToast({ message: $r('app.string.invalid_group'), duration: 2000 });
        return;
      }

      // 初始化面包屑导航
      this.updateBreadcrumb(this.currentGroup);

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
   * 导航到指定分组
   * 在分栏模式下，直接更新左侧列表内容
   */
  /**
   * 导航到指定分组
   * @param group 目标分组
   * @param updateBreadcrumb 是否更新面包屑导航（收藏条目点击不更新）
   */
  private navigateToGroup(group: KdbxGroup, updateBreadcrumb: boolean = true) {
    hilog.info(DOMAIN, TAG, `Navigate to group: ${group.uuid.id}`);
    this.currentGroup = group;
    this.titleName = KdbxUtils.getFieldName(group.name) || '';

    // 判断是否为根分组（没有父分组）
    const isRootGroup = !group.parentGroup;
    this.showBack = !isRootGroup;

    // 保存分组ID以支持状态恢复
    this.currentGroupId = isRootGroup ? '' : group.uuid.id;
    this.items = [...group.groups, ...group.entries];
    KdbxUtils.sortBy(this.items, this.sortBy);
    this.addFavorite();
    // 清除选中状态
    this.selectedItem = null;
    this.selectedItemIndex = -1;
    this.selectedEntryId = ''; // 清除选中的条目ID
    // 退出选择模式
    this.isSelectionMode = false;
    this.selectedItems.clear();

    // 更新面包屑导航
    if (updateBreadcrumb) {
      this.updateBreadcrumb(group);
    }
  }

  /**
   * 更新面包屑导航路径
   * @param group 当前分组
   */
  private updateBreadcrumb(group: KdbxGroup) {
    const path: NavigationPathItem[] = [];
    let current: KdbxGroup | undefined = group;

    // 从当前分组向上遍历到根分组
    while (current) {
      const groupName = current.name; // 直接使用 name 属性
      const nameStr = groupName || ''; // 处理 undefined 情况

      // 如果是根分组（没有父分组），显示为 '/'
      if (!current.parentGroup) {
        path.unshift({ id: current.uuid.id, name: '/' });
      } else {
        path.unshift({ id: current.uuid.id, name: nameStr });
      }

      current = current.parentGroup;
    }

    this.navigationPath = path;
    hilog.debug(DOMAIN, TAG, `Breadcrumb updated: ${path.length} levels`);
  }

  /**
   * 从面包屑导航到指定分组
   * @param groupId 分组ID
   */
  private navigateToBreadcrumb(groupId: string) {
    // 导航到指定分组
    if (this.database) {
      const group = this.database.getGroup(groupId);
      if (group) {
        this.navigateToGroup(group);
      }
    }
  }

  /**
   * 恢复分组状态
   * 从设置返回时恢复之前浏览的分组
   */
  private restoreGroupState() {
    if (!this.database) {
      return;
    }
    // 如果有保存的分组ID且当前不在该分组
    if (this.currentGroupId) {
      const savedGroup = this.database.getGroup(this.currentGroupId);
      if (savedGroup && this.currentGroup?.uuid.id !== this.currentGroupId) {
        hilog.info(DOMAIN, TAG, 'Restoring group from saved state: %{public}s', this.currentGroupId);
        this.currentGroup = savedGroup;
        this.titleName = KdbxUtils.getFieldName(savedGroup.name) || '';
        this.showBack = savedGroup.parentGroup !== undefined &&
          savedGroup.uuid.id !== this.database.getDefaultGroup()?.uuid.id;
        this.items = [...savedGroup.groups, ...savedGroup.entries];
        KdbxUtils.sortBy(this.items, this.sortBy);
        this.addFavorite();
      }
    }
  }

  /**
   * 返回到父分组
   * 在分栏模式下，左侧列表返回到上一级分组
   */
  private navigateToParentGroup() {
    hilog.info(DOMAIN, TAG, `Navigate to parent group`);
    if (this.currentGroup && this.currentGroup.parentGroup) {
      // 记录父分组
      const parentGroup = this.currentGroup.parentGroup;
      // 判断父分组是否是根分组
      const isRootGroup = !parentGroup.parentGroup || parentGroup.uuid.id === this.database?.getDefaultGroup()?.uuid.id;

      this.currentGroup = parentGroup;
      this.titleName = KdbxUtils.getFieldName(parentGroup.name) || '';
      this.showBack = !isRootGroup;
      // 保存分组ID以支持状态恢复
      this.currentGroupId = parentGroup.uuid.id;
      this.items = [...parentGroup.groups, ...parentGroup.entries];
      KdbxUtils.sortBy(this.items, this.sortBy);
      this.addFavorite();

      // 更新面包屑导航
      this.updateBreadcrumb(parentGroup);
    } else {
      // 没有父分组，返回到根分组
      const rootGroup = this.database?.getDefaultGroup();
      if (rootGroup) {
        this.currentGroup = rootGroup;
        this.titleName = KdbxUtils.getFieldName(rootGroup.name) || '';
        this.showBack = false;
        this.currentGroupId = '';
        this.items = [...rootGroup.groups, ...rootGroup.entries];
        KdbxUtils.sortBy(this.items, this.sortBy);
        this.addFavorite();

        // 更新面包屑导航
        this.updateBreadcrumb(rootGroup);
      }
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
   * 条目右键菜单（分栏模式下使用）
   */
  @Builder
  EntryContextMenu(item: KdbxEntry) {
    Menu() {
      // 复制用户名
      if (KdbxUtils.getFieldValueString(item.fields, KdbxUtils.FIELD_USERNAME) !== '') {
        MenuItem({
          startIcon: $r('app.media.ic_copy'),
          content: '复制用户名',
        }).onClick(() => {
          this.copyUsername(item);
        })
      }

      // 复制密码
      if (KdbxUtils.getFieldValueString(item.fields, KdbxUtils.FIELD_PASSWORD) !== '') {
        MenuItem({
          startIcon: $r('app.media.ic_copy'),
          content: '复制密码',
        }).onClick(() => {
          this.copyPassword(item);
        })
      }

      // 收藏/取消收藏
      MenuItem({
        startIcon: $r('app.media.ic_favorite'),
        content: KdbxUtils.isFavorite(item) ? '取消收藏' : '收藏',
      }).onClick(() => {
        this.selectedItem = item;
        this.toggleFavorite();
      })

      // 置顶/取消置顶
      MenuItem({
        startIcon: $r('app.media.ic_top'),
        content: KdbxUtils.isPinned(item) ? '取消置顶' : '置顶',
      }).onClick(() => {
        this.selectedItem = item;
        this.togglePin();
      })

      // 编辑
      MenuItem({
        startIcon: $r('app.media.ic_edit'),
        content: '编辑',
      }).onClick(() => {
        this.editEntry(item);
      })

      // 选择
      MenuItem({
        startIcon: $r('app.media.ic_check'),
        content: '选择',
      }).onClick(() => {
        this.selectedItem = item;
        this.enterSelectionMode(item);
      })

      // 删除
      MenuItem({
        startIcon: $r('app.media.ic_delete'),
        content: '删除',
      }).onClick(() => {
        this.selectedItem = item;
        this.deleteItem(item);
      })
    }
    .backgroundColor($r("app.color.card_bg"))
    .fontColor($r('app.color.text_primary'))
  }

  /**
   * 分组右键菜单（分栏模式下使用）
   */
  @Builder
  GroupContextMenu(item: KdbxGroup) {
    Menu() {
      // 复制分组名
      MenuItem({
        startIcon: $r('app.media.ic_copy'),
        content: '复制分组名',
      }).onClick(() => {
        this.copyGroupName(item);
      })

      // 收藏/取消收藏
      MenuItem({
        startIcon: $r('app.media.ic_favorite'),
        content: KdbxUtils.isFavorite(item) ? '取消收藏' : '收藏',
      }).onClick(() => {
        this.selectedItem = item;
        this.toggleFavorite();
      })

      // 置顶/取消置顶
      MenuItem({
        startIcon: $r('app.media.ic_top'),
        content: KdbxUtils.isPinned(item) ? '取消置顶' : '置顶',
      }).onClick(() => {
        this.selectedItem = item;
        this.togglePin();
      })

      // 编辑
      MenuItem({
        startIcon: $r('app.media.ic_edit'),
        content: '编辑',
      }).onClick(() => {
        this.editGroup(item);
      })

      // 选择
      MenuItem({
        startIcon: $r('app.media.ic_check'),
        content: '选择',
      }).onClick(() => {
        this.selectedItem = item;
        this.enterSelectionMode(item);
      })

      // 删除
      MenuItem({
        startIcon: $r('app.media.ic_delete'),
        content: '删除',
      }).onClick(() => {
        this.selectedItem = item;
        this.deleteItem(item);
      })
    }
    .backgroundColor($r("app.color.card_bg"))
    .fontColor($r('app.color.text_primary'))
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
    // 判断是否处于分栏模式
    const isSplitMode = this.windowInfo.isSplitMode;
    // 在分栏模式下使用导航栏宽度，非分栏模式下使用屏幕宽度
    const availableWidth = isSplitMode ? this.currentNavBarWidth : this.screenWidth;
    // 右对齐，确保不超出可用宽度边界
    this.moreMenuX = availableWidth - menuWidth - 12;

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
      ClipboardUtils.copyAutoClear(KdbxFieldReference.resolveFieldRefsInText(username, FileService.getDatabase(), entry));
    }
  }

  /**
   * 复制密码
   */
  private copyPassword(entry: KdbxEntry) {
    const password = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_PASSWORD);
    if (password) {
      ClipboardUtils.copyAutoClear(KdbxFieldReference.resolveFieldRefsInText(password, FileService.getDatabase(), entry));
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
    const entryParam: EntryParam = {
      groupId: entry.parentGroup?.uuid.id,
      entryId: entry.uuid.id
    };
    this.navPathStack.pushPathByName(PageConstants.PAGE_ENTRY_EDIT, entryParam);
    this.hideMoreMenu();
  }

  /**
   * 编辑分组
   * @param group 要编辑的分组对象
   */
  private editGroup(group: KdbxGroup) {
    // 通过 UUID 在 items 中找到索引
    this.editingGroupIndex = this.items.findIndex(i => i.uuid.id === group.uuid.id);
    this.newGroupName = group.name;
    this.dialogController.open();
    this.hideMoreMenu();
  }

  // ==================== 批量操作相关方法 ====================

  /**
   * 进入选择模式
   * @param item 可选的初始选中项
   */
  private enterSelectionMode(item?: KdbxGroup | KdbxEntry): void {
    const newMap = new Map<string, KdbxGroup | KdbxEntry>();
    if (item) {
      newMap.set(item.uuid.id, item);
    }
    this.selectedItems = newMap;
    this.isSelectionMode = true;
    this.hideMoreMenu();
  }

  /**
   * 退出选择模式
   */
  private exitSelectionMode(): void {
    this.selectedItems = new Map();
    this.isSelectionMode = false;
    this.moveSourceGroupId = '';
  }

  /**
   * 切换选中状态
   */
  private toggleSelection(item: KdbxGroup | KdbxEntry): void {
    const uuid = item.uuid.id;
    const newMap = new Map(this.selectedItems);
    if (newMap.has(uuid)) {
      newMap.delete(uuid);
    } else {
      newMap.set(uuid, item);
    }
    this.selectedItems = newMap;
  }

  /**
   * 全选当前列表
   */
  private selectAll(): void {
    const newMap = new Map<string, KdbxGroup | KdbxEntry>();
    this.items.forEach((item: KdbxGroup | KdbxEntry) => {
      newMap.set(item.uuid.id, item);
    });
    this.selectedItems = newMap;
  }

  /**
   * 取消全选
   */
  private deselectAll(): void {
    this.selectedItems = new Map();
  }

  /**
   * 是否全选
   */
  private isAllSelected(): boolean {
    return this.items.length > 0 && this.selectedItems.size === this.items.length;
  }

  /**
   * 获取选中的条目列表
   */
  private getSelectedEntries(): KdbxEntry[] {
    const entries: KdbxEntry[] = [];
    this.selectedItems.forEach((item: KdbxGroup | KdbxEntry, key: string) => {
      if (item instanceof KdbxEntry) {
        entries.push(item);
      }
    });
    return entries;
  }

  /**
   * 获取选中的分组列表
   */
  private getSelectedGroups(): KdbxGroup[] {
    const groups: KdbxGroup[] = [];
    this.selectedItems.forEach((item: KdbxGroup | KdbxEntry, key: string) => {
      if (item instanceof KdbxGroup) {
        groups.push(item);
      }
    });
    return groups;
  }

  /**
   * 开始批量移动
   * 保存源分组ID，导航到目标分组选择页面
   */
  private startBatchMove(): void {
    if (this.selectedItems.size === 0) {
      return;
    }
    // 保存源分组ID
    this.moveSourceGroupId = this.currentGroup?.uuid.id || '';
    // 创建批量移动参数
    const entries = this.getSelectedEntries();
    const groups = this.getSelectedGroups();

    if (entries.length > 0 || groups.length > 0) {
      this.moveParam = MoveParam.create(
        entries.map(e => e.uuid.id),
        groups.map(g => g.uuid.id),
        this.moveSourceGroupId
      );
    }

    // 清除选择状态并退出选择模式
    this.selectedItems = new Map();
    this.isSelectionMode = false;

    // 就地导航到根分组让用户选择目标（列表仍在当前页面，底部出现"移动到此处"栏）
    // 注意：不能往 databaseNavPathStack 再 push 一个 DatabaseView——宽屏分栏下它会
    // 被塞进右侧内容区，且新实例的数据库加载依赖 rootPageChangeListener（不会触发），
    // moveParam 也依赖 router 时代的 onPageShow 生命周期（NavDestination 下不回调），只会得到空白页
    if (this.database) {
      const rootGroup = this.database.getDefaultGroup();
      this.navigateToGroup(rootGroup);
    }
  }

  /**
   * 退出移动模式并返回源分组
   * 完成"移动到此处"或取消移动后调用，视图回到发起移动的分组
   */
  private exitMoveMode() {
    const sourceGroupId = this.moveSourceGroupId;
    this.cancelMoving();
    this.moveSourceGroupId = '';
    if (sourceGroupId && this.database) {
      const sourceGroup = this.database.getGroup(sourceGroupId);
      if (sourceGroup) {
        this.navigateToGroup(sourceGroup);
      }
    }
  }

  /**
   * 确认批量删除
   * 显示确认对话框
   */
  private confirmBatchDelete(): void {
    if (this.selectedItems.size === 0) {
      return;
    }

    const count = this.selectedItems.size;
    this.getUIContext().showAlertDialog({
      title: $r("app.string.dialog_confirm_title"),
      message: $r('app.string.batch_delete_confirm_message', count),
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {}
      },
      secondaryButton: {
        value: $r("app.string.delete_button_text"),
        action: () => {
          this.executeBatchDelete();
        }
      }
    });
  }

  /**
   * 执行批量删除
   */
  private executeBatchDelete(): void {
    if (this.database === null) {
      return;
    }
    
    const entries = this.getSelectedEntries();
    const groups = this.getSelectedGroups();
    
    // 删除所有选中的条目
    entries.forEach(entry => {
      this.database!.remove(entry);
    });
    
    // 删除所有选中的分组
    groups.forEach(group => {
      this.database!.remove(group);
    });
    
    // 保存数据库
    this.saveDatabase();
    
    // 刷新列表数据
    if (this.currentGroup) {
      this.currentGroup = this.database?.getGroup(this.currentGroup.uuid);
      this.items = [...this.currentGroup?.groups || [], ...this.currentGroup?.entries || []];
    }
    
    // 退出选择模式
    this.exitSelectionMode();
  }

  /**
   * 删除条目或分组 - 直接删除
   * @param item 要删除的条目或分组对象（使用对象引用而非索引，避免搜索模式下索引错位）
   */
  private deleteItem(item: KdbxGroup | KdbxEntry) {
    if (this.database === null) {
      return;
    }

    const deleteObj = item;
    const deleteUuid = item.uuid.id;

    const msg = this.database.isInRecycleBin(deleteObj) ? $r("app.string.dialog_delete_confirm_message_in_recycle_bin") : $r("app.string.dialog_delete_confirm_message");

    this.getUIContext().showAlertDialog({
      title: $r("app.string.dialog_confirm_title"),
      message: msg,
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r("app.string.delete_button_text"),
        action: () => {
          if (deleteObj && this.database) {
            // 从数据库中删除
            this.database.remove(deleteObj);

            // 从 items 数组中移除（通过 UUID 匹配）
            const itemsIndex = this.items.findIndex(i => i.uuid.id === deleteUuid);
            if (itemsIndex >= 0) {
              this.items.splice(itemsIndex, 1);
            }

            // 从 filteredItems 数组中移除（通过 UUID 匹配）
            const filteredIndex = this.filteredItems.findIndex(i => i.uuid.id === deleteUuid);
            if (filteredIndex >= 0) {
              this.filteredItems.splice(filteredIndex, 1);
            }

            this.saveDatabase();
            this.hideMoreMenu();
          } else {
            CommonUtils.showToast($r("app.string.please_refresh_data_first"));
          }
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
              this.editGroup(this.selectedItem as KdbxGroup);
            }
          })
        }

        // 选择按钮
        Column({ space: 8 }) {
          Button() {
            Column() {
              Image($r('app.media.ic_check'))
                .width(28)
                .height(28)
                .fillColor($r('app.color.text_primary'))
              Text('选择')
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
            if (this.selectedItem) {
              this.enterSelectionMode(this.selectedItem);
            }
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
            if (this.selectedItem) {
              this.deleteItem(this.selectedItem);
            }
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
   * 下拉刷新（与远端比对，不一致才下载）
   * 先置 force_refresh 忽略"仅使用本地缓存"，再走版本快速路径：
   * 远端 version+size 与本地缓存元数据一致 → 直接复用本地副本（零下载）；
   * 不一致才全量下载。语义仍是"拉最新"，只是内容未变时不再重复传输
   */
  private refreshDatabase() {
    this.isRefreshing = true;
    // 设置强制从远端刷新标志，忽略仅使用本地缓存的设置
    CacheConstants.setForceRefresh(true);

    let loadParam = LoadDatabase.byDbFileParam(FileService.getDbFileParam());
    KdbxLoadService.loadDatabase(loadParam, {
      onSuccessMessage: (successMessage: SuccessMessage) => {
        KdbxUtils.successMessageToKdbx(successMessage, loadParam).then((database: Kdbx) => {
          FileService.resetDbFileParam(database, successMessage.modifiedTime, successMessage.version ?? null,
            successMessage.contentHash ?? null);
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
        this.refreshText = ResourceManager.getMessage(message.message);
      },
      onProgressMessage: (message: ProgressMessage) => {
        // 下载进度：阶段文案 + 字节明细（尺寸未知时仅百分比）
        const stage: string = ResourceManager.getMessage('downloading');
        if (message.totalBytes > 0) {
          this.refreshText =
            `${stage} ${StringUtils.formatFileSize(message.transferredBytes)} / ${StringUtils.formatFileSize(message.totalBytes)}`;
        } else {
          this.refreshText = `${stage} ${message.percent}%`;
        }
      },
      onErrorMessage: (message: LoadMessage) => {
        this.refreshText = ResourceManager.getMessage(message.message);
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
      KdbxSaveService.saveDatabaseFromUi(ToastSaveDatabaseCallback.wrap({
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
   * 打开模板选择器
   */
  private openTemplateSelector() {
    this.templateSelectorController.open();
  }

  /**
   * 处理模板选择
   */
  private handleTemplateSelected(template: ITemplate) {
    if (!this.currentGroup) {
      return;
    }
    // 跳转到模板创建页面
    const templateId = isPresetTemplate(template) ? (template as IPresetTemplate).id : (template as IUserTemplate).uuid.id;
    const isPreset = isPresetTemplate(template);

    const templateParam: TemplateEntryCreateParam = {
      groupId: this.currentGroup.uuid.id,
      templateId: templateId,
      isPreset: isPreset
    };
    this.navPathStack.pushPathByName(PageConstants.PAGE_TEMPLATE_ENTRY_CREATE, templateParam);
  }

  /**
   * 添加收藏数据
   */
  private addFavorite() {
    let startIndex = 0;
    // 如果是默认分组，添加收藏的数据到最上方
    if (this.database && !this.showBack) {
      const favoriteItems = KdbxUtils.getFavoriteItems(this.database);
      // 过滤掉当前分组中已有的收藏项，避免重复
      const currentItemsUuid = new Set(this.items.map(item => item.uuid.id));
      const uniqueFavoriteItems = favoriteItems.filter(item => !currentItemsUuid.has(item.uuid.id));
      // 将收藏项添加到列表最前面
      this.items = [...uniqueFavoriteItems, ...this.items];
      startIndex = uniqueFavoriteItems.length;
    }
    this.buildIndexerData(startIndex);
  }

  private handleAddGroup(iconId?: number | string, fgColor?: string, bgColor?: string) {
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

    // 设置分组颜色
    group.fgColor = fgColor;
    group.bgColor = bgColor;

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
      // 移动条目
      this.moveParam.entryIds.forEach((entryId: string) => {
        const entry = KdbxUtils.getEntry(this.database!, this.moveParam!.sourceGroupId, entryId);
        if (entry) {
          this.database!.move(entry, this.currentGroup!);
        }
      });
      // 移动分组
      this.moveParam.groupIds.forEach((groupId: string) => {
        const group = this.database!.getGroup(groupId);
        if (group) {
          // 检查是否移动到自己或子分组
          if (this.currentGroup!.uuid.id !== group.uuid.id && !KdbxUtils.isChildGroup(group, this.currentGroup!)) {
            this.database!.move(group, this.currentGroup!);
          }
        }
      });
      // 保存数据库
      this.saveDatabase();
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to move item: %{public}s', error.message);
      CommonUtils.showToast({
        message: $r('app.string.operation_failed'),
        duration: 2000
      });
    } finally {
      // 取消移动模式并返回源分组
      this.exitMoveMode();
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
      // 全局搜索模式：搜索整个数据库（排除回收站中的内容）
      this.filteredItems = [];

      if (this.database) {
        let result = KdbxUtils.searchInGroup(this.database.getDefaultGroup(), this.searchText, this.database, false);
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
   * 构建索引数据，快速定位条目开始索引
   */
  private buildIndexerData(startIndex?:number): void {
    this.indexerValues = [];
    this.indexerMap.clear();

    if (this.items.length === 0 || this.sortBy !== SortMode.NAME || this.isSearching) {
      return;
    }
    // 构建索引数据
    const indexer = KdbxUtils.buildIndexerData(UIUtils.getTarget(this.items), startIndex);
    this.indexerValues = indexer.indexerValues;
    this.indexerMap = indexer.indexerMap;
  }

  /**
   * 锁定数据库
   */
  private lockDatabase() {
    LockScreenService.showLockWindow(true);
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
        this.headerHeight = 108;
      } else {
        this.headerHeight = 48;
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
    // 在 Navigation 系统中,可以直接 pop
    this.navPathStack.pop();
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
                  .height(36)
                  .layoutWeight(1)
                  .flexShrink(1)
                  .id('input_search')
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
                  .height(36)
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
                      }, (index: number) => `${index}_${Date.now()}`)
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
            .margin({ top: 4 })
            .width('100%')
          } else {
            Row() {
              Row() {
                if (this.showBack) {
                  Image($r("app.media.ic_angle_left"))
                    .width(28)
                    .height(28)
                    .margin({ left: 16 })
                    .fillColor($r('app.color.text_primary'))
                    .onClick(() => {
                      // 左侧返回按钮：返回到父分组
                      this.navigateToParentGroup();
                    })
                }
                // 选择模式下显示已选数量
                Text(this.isSelectionMode ? `${this.titleName}(${this.selectedItems.size})` : this.titleName)
                  .fontSize(22)
                  .fontWeight(FontWeight.Medium)
                  .margin({ left: 16 })
                  .fontColor($r('app.color.text_primary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              }
              .margin({ right: 25 })
              .layoutWeight(1)
              .flexShrink(1)

              // 选择模式下显示全选/取消全选按钮，否则显示常规按钮
              if (this.isSelectionMode) {
                Button(this.isAllSelected() ? $r('app.string.deselect_all_button') : $r('app.string.select_all_button'))
                  .height(32)
                  .fontSize(14)
                  .backgroundColor($r('app.color.card_bg'))
                  .fontColor($r('app.color.text_primary'))
                  .margin({ right: 16 })
                  .onClick(() => {
                    if (this.isAllSelected()) {
                      this.deselectAll();
                    } else {
                      this.selectAll();
                    }
                  })
              } else {
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
                    .id('btn_lock_database')
                    .onClick(() => {
                      this.lockDatabase();
                    })
                  Image($r('app.media.ic_settings'))
                    .width(24)
                    .height(24)
                    .margin({ right: 16 })
                    .onClick(() => {
                       NavigationManager.getInstance().navigateBackToRoot('Settings');
                     })
                }
                .flexShrink(0)
                .width(112)
              }
            }
            .alignItems(VerticalAlign.Center)
            .width('100%')
            .layoutWeight(1)
          }
        }
        .width('100%')
        .height(this.headerHeight)

        // 顶部面包屑导航条（进入布局流，内容区自动下移，不遮挡条目）
        if (this.isBreadcrumbVisible && this.breadcrumbPosition === BreadcrumbPosition.TOP
          && !this.moveParam && !this.isSelectionMode) {
          Scroll() {
            Row() {
              ForEach(this.navigationPath, (pathItem: NavigationPathItem, index: number) => {
                Row() {
                  Text(pathItem.name)
                    .fontSize(14)
                    .fontColor(index === this.navigationPath.length - 1 ? $r('app.color.text_primary') : $r('app.color.button_bg_blue'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                    .onClick(() => {
                      if (index < this.navigationPath.length - 1) {
                        this.navigateToBreadcrumb(pathItem.id);
                      }
                    })

                  if (index < this.navigationPath.length - 1) {
                    Text(' > ')
                      .fontSize(14)
                      .fontColor($r('app.color.text_secondary'))
                  }
                }
              })
            }
            .justifyContent(FlexAlign.Start)
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .height(36)
          .padding({ left: 16, right: 16 })
          .backgroundColor($r("app.color.bg_secondary"))
          .scrollable(ScrollDirection.Horizontal)
          .scrollBar(BarState.Off)
          .align(Alignment.Start)
        }

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
          // 使用 Stack 包裹以支持 AlphabetIndexer 悬浮
          Stack({ alignContent: Alignment.End }) {
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
                            // .fillColor(item.fgColor ? item.fgColor : undefined)
                          Column() {
                            Text(KdbxUtils.getFieldName(item.name))
                              .fontSize(18)
                              .textAlign(TextAlign.Start)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .flexGrow(1)
                              .maxLines(1)
                              .fontColor(item.fgColor || $r('app.color.text_primary'))
                            Text($r("app.string.group_items_message", this.groupItemCount(item)))
                              .fontSize(12)
                              .textAlign(TextAlign.Start)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .flexGrow(1)
                              .margin({ top: 4 })
                              .maxLines(1)
                              .fontColor(item.fgColor || $r('app.color.text_secondary'))
                          }
                          .flexGrow(1)
                          .alignItems(HorizontalAlign.Start)
                          .layoutWeight(1)

                          Image($r('app.media.ic_arrow_right'))
                            .width(28)
                            .height(28)
                            .margin({ right: 0 })
                            .fillColor(item.fgColor || $r('app.color.text_primary'))
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
                      .borderRadius(8)
                      .backgroundColor(this.selectedItems.has(item.uuid.id) ? $r("app.color.button_bg_blue") :
                        (item.bgColor || $r("app.color.card_bg")))
                      .padding({
                        left: 6,
                        right: 6,
                        top: 6,
                        bottom: 6
                      })
                      .onClick(() => {
                        if (this.isSelectionMode) {
                          this.toggleSelection(item);
                        } else {
                          // 判断是否是收藏项
                          const isFavorite = KdbxUtils.isFavorite(item);
                          // 点击分组时，直接在左侧列表中展开该分组
                          // 收藏的分组需要更新面包屑，收藏的条目不更新
                          this.navigateToGroup(item as KdbxGroup, !isFavorite || (item as KdbxGroup).parentGroup?.uuid.id !== this.currentGroup?.uuid.id);
                        }
                      })
                      .bindContextMenu(this.GroupContextMenu(item), ResponseType.RightClick)
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
                            // .fillColor(item.fgColor ? item.fgColor : undefined)
                          Column() {
                            Text(KdbxUtils.getFieldValueString(item.fields, KdbxUtils.FIELD_TITLE))
                              .fontSize(18)
                              .textAlign(TextAlign.Start)
                              .flexGrow(1)
                              .textOverflow({ overflow: TextOverflow.Ellipsis })
                              .maxLines(1)
                              .fontColor(item.fgColor || $r('app.color.text_primary'))
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
                              .fontColor(item.fgColor || $r('app.color.text_secondary'))
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
                            .fillColor(item.fgColor || $r('app.color.text_primary'))
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
                      .backgroundColor(this.selectedItems.has(item.uuid.id) ? $r("app.color.button_bg_blue") :
                        (item.bgColor || $r("app.color.card_bg")))
                      .padding({
                        left: 6,
                        right: 6,
                        top: 6,
                        bottom: 6
                      })
                      .onClick(() => {
                        if (this.isSelectionMode) {
                          this.toggleSelection(item);
                        } else {
                          // 分栏模式下，判断右侧是否已显示当前条目
                          const isSplitMode = this.windowInfo.isSplitMode;
                          if (isSplitMode && this.selectedEntryId === item.uuid.id) {
                            // 右侧已显示当前条目，不重复添加
                            return;
                          }
                          // 更新选中的条目ID并导航
                          this.selectedEntryId = item.uuid.id;
                          const entryParam: EntryParam = { entryId: item.uuid.id, groupId: item.parentGroup?.uuid.id };
                          this.navPathStack.pushPathByName(PageConstants.PAGE_ENTRY_VIEW, entryParam);
                        }
                      })
                      .bindContextMenu(this.EntryContextMenu(item), ResponseType.RightClick)
                    }
                    .swipeAction({
                      end: {
                        builder: () => this.EntrySwipeActionButtons(index, item)
                      }
                    })
                  }

                }, (item: KdbxGroup | KdbxEntry, index: number) => `${index}-${Date.now()}`)
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
              top: 4,
              bottom: 0
            })
            .scrollBar(BarState.Auto)
            .clipContent(ContentClipMode.SAFE_AREA)
          }
          .backgroundColor($r("app.color.bg_primary"))
          .refreshOffset(90)
          .pullToRefresh(this.isPullToRefresh)
          .onRefreshing(() => {
            this.refreshDatabase();
          })
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])

            // 索引条 - 悬浮在列表上方（仅名称排序且非搜索状态时显示）
            if (this.indexerValues.length > 0) {
              AlphabetIndexer({ arrayValue: this.indexerValues, selected: this.indexerSelected })
                .selectedColor($r('app.color.button_bg_blue'))
                .color($r('app.color.text_secondary'))
                .selectedBackgroundColor($r('app.color.bg_secondary'))
                .itemSize(20)
                .usingPopup(true)
                .popupColor($r('app.color.text_primary'))
                .popupBackground($r('app.color.card_bg'))
                .alignStyle(IndexerAlign.END, 12)
                .onSelect((index: number) => {
                  this.indexerSelected = index;
                  const listIndex = this.indexerMap.get(this.indexerValues[index]);
                  if (listIndex !== undefined) {
                    this.listScroller.scrollToIndex(listIndex);
                  }
                })
                .margin({ right: 8 })
                .height('70%')
            }
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .onAreaChange((oldArea: Area, newArea: Area) => {
        // 监听左侧导航栏区域变化
        // 在分栏模式下，当用户拖拽调整导航栏宽度时，这个回调会被触发
        const newWidth = Number(newArea.width);
        const newHeight = Number(newArea.height);
        let needUpdateBounds = false;

        if (newWidth > 0 && newWidth !== this.currentNavBarWidth) {
          // 更新当前导航栏宽度
          this.currentNavBarWidth = newWidth;

          // newWidth 已是实际可用宽度（分栏=导航栏宽，单列=屏宽），直接计算边界
          this.maxX = this.currentNavBarWidth - this.containerWidth;

          // 确保按钮在新边界内
          if (this.containerX > this.maxX) {
            this.containerX = Math.max(0, this.maxX - 22);
          }
        }

        // 监听高度变化，更新Y边界
        if (newHeight > 0 && newHeight !== this.screenHeight) {
          this.screenHeight = newHeight;
          this.maxY = this.screenHeight - this.containerHeight - 16; // 距离底部保留16vp的安全距离

          // 确保按钮在新边界内
          if (this.containerY > this.maxY) {
            this.containerY = Math.max(0, this.maxY - 32);
          } else if (this.containerY < 0) {
            this.containerY = 32;
          }
        }
      })

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
        .id('btn_add_group')
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
        .id('btn_add_entry')
        .onClick(() => {
          this.showAddButtons = false;
          // 使用 Navigation 导航，在分栏模式下会在右侧内容区显示
          const entryParam: EntryParam = {
            groupId: this.currentGroup?.uuid.id
          };
          this.navPathStack.pushPathByName(PageConstants.PAGE_ENTRY_EDIT, entryParam);
        })

        // 从模板创建按钮
        Button() {
          Row() {
            Image($r('app.media.ic_copy'))
              .width(20)
              .height(20)
              .fillColor($r("app.color.button_text_blue"))
            Text($r('app.string.template_from_template'))
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
          this.openTemplateSelector();
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
          // 清空 TotpView 的导航栈，确保右侧分栏为空
          const totpNavPathStack = NavigationManager.getInstance().getNavPathStackByRoot('TotpView');
          if (totpNavPathStack) {
            totpNavPathStack.clear();
          }
          // 切换到 TOTP 根页面
          NavigationManager.getInstance().navigateBackToRoot('TotpView');
        })

        // 主添加按钮
        Button() {
          Image(this.showAddButtons ? $r('app.media.ic_clear') : $r('app.media.ic_add'))
            .width(28)
            .height(28)
            .fillColor(Color.White)
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor(this.showAddButtons ? $r("app.color.error") : $r("app.color.button_bg_blue"))
        .enabled(!this.isLoading)
        .opacity(this.isLoading ? 0.5 : 1)
        .visibility(this.showAddButtons ? Visibility.Hidden : Visibility.Visible)
        .id('btn_add_fab')
        .onClick(() => {
          this.showAddButtons = true;
        })

        // 展开菜单时的关闭按钮
        Button() {
          Image($r('app.media.ic_clear'))
            .width(28)
            .height(28)
            .fillColor(Color.White)
        }
        .width(56)
        .height(56)
        .borderRadius(28)
        .backgroundColor($r("app.color.error"))
        .enabled(!this.isLoading)
        .opacity(this.isLoading ? 0.5 : 1)
        .visibility(this.showAddButtons ? Visibility.Visible : Visibility.None)
        .onClick(() => {
          this.showAddButtons = false;
        })
      }
      .width(this.containerWidth)
      .height(this.showAddButtons ? 200 : this.containerHeight)
      .visibility((this.moveParam || this.isSelectionMode) ? Visibility.None : Visibility.Visible)
      .zIndex(999)
      .gesture(
        // 拖拽手势（展开状态下禁用）
        PanGesture({ fingers: 1, direction: PanDirection.All })
          .onActionStart(() => {
            if (!this.showAddButtons) {
              this.isDragging = true;
              this.oldContainerX = this.containerX;
              this.oldContainerY = this.containerY;
            }
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

      // 底部面包屑导航条（绝对定位浮层，贴容器底部上方 36vp，不影响内容区起点）
      if (this.isBreadcrumbVisible && this.breadcrumbPosition === BreadcrumbPosition.BOTTOM) {
        Scroll() {
          Row() {
            ForEach(this.navigationPath, (pathItem: NavigationPathItem, index: number) => {
              Row() {
                // 路径项
                Text(pathItem.name)
                  .fontSize(14)
                  .fontColor(index === this.navigationPath.length - 1 ? $r('app.color.text_primary') : $r('app.color.button_bg_blue'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .onClick(() => {
                    // 点击路径项导航到对应分组
                    if (index < this.navigationPath.length - 1) {
                      this.navigateToBreadcrumb(pathItem.id);
                    }
                  })

                // 分隔符（最后一项不显示）
                if (index < this.navigationPath.length - 1) {
                  Text(' > ')
                    .fontSize(14)
                    .fontColor($r('app.color.text_secondary'))
                }
              }
            })
          }
          .justifyContent(FlexAlign.Start)
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .height(36)
        .padding({ left: 16, right: 16 })
        .backgroundColor($r("app.color.bg_secondary"))
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Off) // 隐藏滚动条，保持美观
        .align(Alignment.Start) // 内容居左对齐
        .position({ x: 0, y: '100%' })
        .translate({ y: -36 })
        .visibility((this.moveParam || this.isSelectionMode) ? Visibility.None : Visibility.Visible)
      }

      // 移动模式下的底部浮动按钮
      if (this.moveParam) {
        Column() {
          Row() {
            Button($r('app.string.move_here'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(40)
              .margin({ right: 8 })
              .borderRadius(20)
              .backgroundColor($r("app.color.button_bg_blue"))
              .fontColor($r("app.color.button_text_blue"))
              .id('btn_move_here')
              .onClick(() => {
                this.moveItemToCurrentGroup();
              })

            Button($r('app.string.cancel_button_text'), { type: ButtonType.Normal })
              .layoutWeight(1)
              .height(40)
              .borderRadius(20)
              .backgroundColor(Color.Gray)
              .fontColor(Color.White)
              .id('btn_cancel_move')
              .onClick(() => {
                // 取消移动模式并返回源分组
                this.exitMoveMode();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .height(60)
        .padding({
          top: 8,
          bottom: 8,
          left: 16,
          right: 16
        })
        .position({ x: 0, y: '100%' })
        .translate({ y: -60 })
        .justifyContent(FlexAlign.Center)
      }

      // 批量选择模式下的底部操作栏
      if (this.isSelectionMode) {
        Column() {
          Row() {
            // 移动按钮
            Button($r('app.string.move_button_text'))
              .layoutWeight(1)
              .height(40)
              .margin({ right: 8 })
              .borderRadius(20)
              .backgroundColor($r("app.color.button_bg_blue"))
              .fontColor($r("app.color.button_text_blue"))
              .enabled(this.selectedItems.size > 0)
              .opacity(this.selectedItems.size > 0 ? 1 : 0.5)
              .id('btn_batch_move')
              .onClick(() => {
                this.startBatchMove();
              })

            // 删除按钮
            Button($r('app.string.delete_button_text'))
              .layoutWeight(1)
              .height(40)
              .margin({ right: 8 })
              .borderRadius(20)
              .backgroundColor($r("app.color.error"))
              .fontColor(Color.White)
              .enabled(this.selectedItems.size > 0)
              .opacity(this.selectedItems.size > 0 ? 1 : 0.5)
              .id('btn_batch_delete')
              .onClick(() => {
                this.confirmBatchDelete();
              })

            // 取消按钮
            Button($r('app.string.cancel_button_text'))
              .layoutWeight(1)
              .height(40)
              .borderRadius(20)
              .backgroundColor(Color.Gray)
              .fontColor(Color.White)
              .id('btn_cancel_selection')
              .onClick(() => {
                this.exitSelectionMode();
              })
          }
          .width('100%')
          .justifyContent(FlexAlign.SpaceBetween)
        }
        .width('100%')
        .height(60)
        .padding({
          top: 8,
          bottom: 8,
          left: 16,
          right: 16
        })
        .position({ x: 0, y: '100%' })
        .translate({ y: -60 })
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
