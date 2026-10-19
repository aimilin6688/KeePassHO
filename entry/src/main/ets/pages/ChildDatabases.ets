import { hilog } from '@kit.PerformanceAnalysisKit';
import { deviceInfo, emitter } from '@kit.BasicServicesKit';

import { Kdbx, KdbxEntry } from 'kdbxweb';

import { AutoOpenCoordinator } from '../services/autoopen/AutoOpenCoordinator';
import { AutoOpenEntryService } from '../services/autoopen/AutoOpenEntryService';
import { AutoOpenItem } from '../services/autoopen/AutoOpenItem';
import { AutoOpenService } from '../services/autoopen/AutoOpenService';
import { SchemeMapper } from '../services/autoopen/SchemeMapper';
import { DeviceIdentity } from '../services/autoopen/DeviceIdentity';
import { DeviceEnableState, IfDeviceParser } from '../services/autoopen/IfDeviceParser';
import { DatabaseRegistry } from '../services/kdbx/DatabaseRegistry';
import { DbFileParam, EntryParam } from '../services/TypeDefined';
import { DataService } from '../services/DataService';
import { FileService } from '../services/FileService';
import { EventBus } from '../services/EventBus';
import KdbxSaveService from '../services/kdbx/KdbxSaveService';
import { ToastSaveDatabaseCallback } from '../workers/callback/ToastSaveDatabaseCallback';
import { LoadingDialog } from '../components/loading/LoadingDialogUtils';
import { CommonUtils, KdbxUtils, NavigationManager, ResourceManager } from '../common/utils';
import { PageConstants } from '../common/constants/PageConstants';
import { FileStorage, StorageType } from '../storage';

const DOMAIN = 0x0000;
const TAG = 'ChildDatabases';

/**
 * 子库行视图模型：AutoOpen 条目 + 本设备/已打开等派生展示状态
 */
class ChildRowItem {
  public readonly item: AutoOpenItem;
  /** 子库已在注册表（本会话已打开） */
  public opened: boolean = false;
  /** 本设备启用（IfDevice 判定） */
  public deviceEnabled: boolean = true;
  /** 本设备是否显式配置（未配置显示「未指定」） */
  public deviceExplicit: boolean = false;
  /** 子库存储类型（M6：行图标按此显示；解析失败回落 LOCAL） */
  public storageType: StorageType = StorageType.LOCAL;

  constructor(item: AutoOpenItem) {
    this.item = item;
  }
}

/**
 * 子数据库管理页（M4，对齐 kp2a ConfigureChildDatabasesActivity）：
 * - 列表：当前库 AutoOpen 条目，按 Title 升序、LastModificationTime 倒序；
 * - 行操作：本设备启用/停用（改写 IfDevice）、立即打开（未打开时）、编辑、复制为本设备副本、
 *   删除子数据库（移除父库 AutoOpen 条目，不删除子库文件本身）；
 * - 添加子库：菜单选择——「选择文件…」进入存储选择页（支持本地/远端全存储）、
 *   「最近打开」进入最近文件列表，均经解锁回环（addChildParent 中继）登记为父库子库；
 * - 修改均走现有保存管线存当前库（父库）。
 */
@Component
struct ChildDatabasesPage {
  @State rows: ChildRowItem[] = [];
  private registry: DatabaseRegistry = FileService.getRegistry();
  private navManager: NavigationManager = NavigationManager.getInstance();

  private onChildOpened = (): void => {
    this.refreshData();
  };
  private onChildOpenFailed = (event: emitter.EventData): void => {
    AutoOpenCoordinator.showOpenFailedToast(event);
    this.refreshData();
  };
  private onChildOpenDone = (): void => {
    this.refreshData();
  };
  private onCurrentChanged = (): void => {
    this.refreshData();
  };
  private onDatabaseUpdate = (): void => {
    this.refreshData();
  };

  aboutToAppear(): void {
    this.refreshData();
    EventBus.on(AutoOpenCoordinator.EVENT_DATABASE_OPENED, this.onChildOpened);
    EventBus.on(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED, this.onChildOpenFailed);
    EventBus.on(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, this.onChildOpenDone);
    EventBus.on(DatabaseRegistry.EVENT_CURRENT_DATABASE_CHANGED, this.onCurrentChanged);
    EventBus.on(EventBus.DATABASE_UPDATE, this.onDatabaseUpdate);
  }

  aboutToDisappear(): void {
    EventBus.off(AutoOpenCoordinator.EVENT_DATABASE_OPENED, this.onChildOpened);
    EventBus.off(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED, this.onChildOpenFailed);
    EventBus.off(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, this.onChildOpenDone);
    EventBus.off(DatabaseRegistry.EVENT_CURRENT_DATABASE_CHANGED, this.onCurrentChanged);
    EventBus.off(EventBus.DATABASE_UPDATE, this.onDatabaseUpdate);
  }

  /**
   * 重建列表数据：扫描当前库 AutoOpen 条目 + 本设备/已打开派生状态 + 排序
   */
  private refreshData(): void {
    const currentParam: DbFileParam | undefined = this.registry.getCurrent();
    const parentIocKey: string | null = this.registry.getCurrentKey();
    const rows: ChildRowItem[] = [];
    if (currentParam !== undefined && currentParam.database !== undefined && parentIocKey !== null) {
      const deviceId: string = DeviceIdentity.getDeviceId();
      const items: AutoOpenItem[] = AutoOpenService.scan(currentParam.database, parentIocKey);
      for (const item of items) {
        const row: ChildRowItem = new ChildRowItem(item);
        // M6：本地/远端统一解析（scheme 决定存储类型），「已打开」判定与协调器同口径
        const target = SchemeMapper.resolveTarget(item.url, currentParam.filePath);
        if (target !== undefined) {
          row.storageType = target.storageType;
          row.opened = this.registry.has(
            DatabaseRegistry.buildIocKey(target.storageType, target.filePath));
        }
        const state: DeviceEnableState = IfDeviceParser.isEnabled(item.ifDeviceRaw, deviceId);
        row.deviceEnabled = state.enabled;
        row.deviceExplicit = state.isExplicit;
        rows.push(row);
      }
    }
    rows.sort((a: ChildRowItem, b: ChildRowItem): number => {
      const titleA: string = a.item.title.toLowerCase();
      const titleB: string = b.item.title.toLowerCase();
      if (titleA !== titleB) {
        return titleA < titleB ? -1 : 1;
      }
      return b.item.lastModificationTime - a.item.lastModificationTime;
    });
    this.rows = rows;
  }

  /**
   * 行操作：本设备启用/停用（改写 IfDevice 字段后保存父库）
   */
  private toggleDeviceEnabled(row: ChildRowItem): void {
    const entry: KdbxEntry | null | undefined = this.findEntry(row);
    if (entry === null || entry === undefined) {
      this.refreshData();
      return;
    }
    entry.pushHistory();
    AutoOpenEntryService.setEntryDeviceEnabled(entry, DeviceIdentity.getDeviceId(), !row.deviceEnabled);
    entry.times.update();
    this.saveParentDatabase();
  }

  /**
   * 行操作：立即打开子库（已在注册表时 openManually 直接切换当前库）。
   * 加载为异步入队，失败终态经 OPEN_FAILED 事件由 onChildOpenFailed 提示
   */
  private openChildNow(row: ChildRowItem): void {
    AutoOpenCoordinator.getInstance().openManually(row.item).then((result: string) => {
      if (result === 'failed') {
        CommonUtils.showToast(
          $r('app.string.child_dbs_open_failed', this.displayName(row.item)), 2000);
      }
      this.refreshData();
    });
  }

  /**
   * 子库条目展示名：Title 为空时回退 URL（与行展示一致）
   */
  private displayName(item: AutoOpenItem): string {
    return item.title.length > 0 ? item.title : item.url;
  }

  /**
   * 行操作：编辑子库条目（复用普通条目编辑页）
   */
  private editChildEntry(row: ChildRowItem): void {
    const entryParam: EntryParam = {
      entryId: row.item.entryUuid,
      groupId: row.item.parentGroupId
    };
    this.navManager.navigateTo(PageConstants.PAGE_ENTRY_EDIT, entryParam);
  }

  /**
   * 行操作：复制为本设备副本（原条目本设备置停用，新条目仅本设备启用）
   */
  private copyForDevice(row: ChildRowItem): void {
    const database: Kdbx | undefined = this.getDatabase();
    const entry: KdbxEntry | null | undefined = this.findEntry(row);
    if (database === undefined || entry === null || entry === undefined) {
      this.refreshData();
      return;
    }
    const clone: KdbxEntry | undefined = AutoOpenEntryService.copyEntryForDevice(
      database, entry, DeviceIdentity.getDeviceId(), deviceInfo.productModel);
    if (clone === undefined) {
      CommonUtils.showToast({
        message: $r('app.string.child_dbs_add_failed'),
        duration: 2000
      });
      return;
    }
    clone.times.update();
    this.saveParentDatabase();
  }

  /**
   * 行操作：删除子数据库（确认后移除父库中的 AutoOpen 条目，不删除子库文件本身；
   * Kdbx.remove 自带回收站语义：未启用回收站或条目已在回收站时为永久删除，
   * 永久删除时清理孤儿附件，对齐 DatabaseView.deleteItem）
   */
  private deleteChildEntry(row: ChildRowItem): void {
    const database: Kdbx | undefined = this.getDatabase();
    const entry: KdbxEntry | null | undefined = this.findEntry(row);
    if (database === undefined || entry === null || entry === undefined) {
      this.refreshData();
      return;
    }
    const isPermanentDelete = database.isInRecycleBin(entry);
    this.getUIContext().showAlertDialog({
      title: $r('app.string.child_dbs_delete'),
      message: $r('app.string.child_dbs_delete_confirm_message', this.displayName(row.item)),
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r('app.string.delete_button_text'),
        action: () => {
          database.remove(entry);
          if (isPermanentDelete) {
            KdbxUtils.cleanupOrphanedBinaries(database);
          }
          this.saveParentDatabase();
        }
      }
    });
  }

  /**
   * 添加子库：选择文件（存储选择页 → 解锁回环：addChildParent 中继回本页发起库）
   */
  private addChildFromSelectLocation(): void {
    const currentKey: string | null = this.registry.getCurrentKey();
    if (currentKey === null) {
      return;
    }
    DataService.selectKdbx('add', currentKey);
    this.navManager.navigateTo(PageConstants.PAGE_SELECT_LOCATION);
  }

  /**
   * 添加子库：最近打开（最近文件列表 → 解锁回环：addChildParent 中继回本页发起库）
   */
  private addChildFromRecentFiles(): void {
    const currentKey: string | null = this.registry.getCurrentKey();
    if (currentKey === null) {
      return;
    }
    const navParam: Record<string, string> = {
      'openMode': 'add',
      'addChildParent': currentKey
    };
    this.navManager.navigateTo(PageConstants.PAGE_RECENT_FILES, navParam);
  }

  /**
   * 定位行条目（条目可能已被外部编辑/删除，找不到返回 undefined 并刷新）
   */
  private findEntry(row: ChildRowItem): KdbxEntry | null | undefined {
    const database: Kdbx | undefined = this.getDatabase();
    if (database === undefined) {
      return undefined;
    }
    return KdbxUtils.getEntry(database, row.item.parentGroupId, row.item.entryUuid);
  }

  /**
   * 取当前库模型（无当前库时返回 undefined）
   */
  private getDatabase(): Kdbx | undefined {
    const currentParam: DbFileParam | undefined = this.registry.getCurrent();
    return currentParam !== undefined ? currentParam.database : undefined;
  }

  /**
   * 行存储图标（M6）：按子库存储类型取 FileStorageFactory 页面配置图标，
   * 未注册类型回落本地 kdbx 文件图标
   */
  private getStorageIcon(row: ChildRowItem): ResourceStr {
    const pageConfig = FileStorage.getPageConfig(row.storageType);
    return pageConfig !== undefined ? pageConfig.icon : $r('app.media.file_kdbx');
  }

  /**
   * 保存当前库（父库）：成功后广播 DATABASE_UPDATE 并刷新列表
   */
  private saveParentDatabase(): void {
    if (this.getDatabase() === undefined) {
      return;
    }
    LoadingDialog.showLoading(ResourceManager.getString($r('app.string.load_save_database')));
    KdbxSaveService.saveDatabaseFromUi(ToastSaveDatabaseCallback.wrap({
      onSuccess: () => {
        EventBus.emit<void>(EventBus.DATABASE_UPDATE);
        this.refreshData();
      },
      onError: (error: string) => {
        hilog.error(DOMAIN, TAG, 'save parent database failed: %{public}s', error);
      }
    }));
  }

  @Builder
  AddSourceMenu() {
    Menu() {
      MenuItem({
        startIcon: $r('app.media.ic_add_file'),
        content: $r('app.string.child_dbs_select_file')
      })
        .onClick(() => {
          this.addChildFromSelectLocation();
        })
      MenuItem({
        startIcon: $r('app.media.ic_clock'),
        content: $r('app.string.recent_files')
      })
        .onClick(() => {
          this.addChildFromRecentFiles();
        })
    }
  }

  @Builder
  AddMenuBuilder() {
    Row() {
      Text($r('app.string.child_dbs_add'))
        .fontSize(14)
        .fontColor($r('app.color.text_primary'))
    }
    .height('100%')
    .padding({ right: 16 })
    .justifyContent(FlexAlign.Center)
    .bindMenu(this.AddSourceMenu())
  }

  @Builder
  ChildRowMenu(row: ChildRowItem) {
    Menu() {
      if (row.deviceEnabled) {
        MenuItem({
          startIcon: $r('app.media.ic_check'),
          content: $r('app.string.child_dbs_disable_on_device')
        })
          .onClick(() => {
            this.toggleDeviceEnabled(row);
          })
      } else {
        MenuItem({
          startIcon: $r('app.media.ic_check'),
          content: $r('app.string.child_dbs_enable_on_device')
        })
          .onClick(() => {
            this.toggleDeviceEnabled(row);
          })
      }
      if (!row.opened) {
        MenuItem({
          startIcon: $r('app.media.file_kdbx'),
          content: $r('app.string.child_dbs_open_now')
        })
          .onClick(() => {
            this.openChildNow(row);
          })
      }
      MenuItem({
        startIcon: $r('app.media.ic_edit'),
        content: $r('app.string.edit_button_text')
      })
        .onClick(() => {
          this.editChildEntry(row);
        })
      MenuItem({
        startIcon: $r('app.media.ic_copy'),
        content: $r('app.string.child_dbs_copy_for_device')
      })
        .onClick(() => {
          this.copyForDevice(row);
        })
      MenuItem({
        startIcon: $r('app.media.ic_delete'),
        content: $r('app.string.child_dbs_delete')
      })
        .onClick(() => {
          this.deleteChildEntry(row);
        })
    }
  }

  @Builder
  DeviceStateText(row: ChildRowItem) {
    if (row.deviceExplicit && row.deviceEnabled) {
      Text($r('app.string.child_dbs_device_enabled_label'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    } else if (row.deviceExplicit && !row.deviceEnabled) {
      Text($r('app.string.child_dbs_device_disabled_label'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    } else {
      Text($r('app.string.child_dbs_device_unspecified_label'))
        .fontSize(12)
        .fontColor($r('app.color.text_secondary'))
    }
  }

  @Builder
  ChildRow(row: ChildRowItem) {
    Row() {
      Image(this.getStorageIcon(row))
        .width(28)
        .height(28)
        .fillColor($r('app.color.text_primary'))
        .margin({ left: 12, right: 12 })
      Column() {
        Row() {
          Text(row.item.title.length > 0 ? row.item.title : row.item.url)
            .fontSize(16)
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (!row.item.enabled) {
            Text($r('app.string.child_dbs_entry_disabled'))
              .fontSize(10)
              .fontColor($r('app.color.text_secondary'))
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(8)
              .backgroundColor($r('app.color.card_bg'))
              .margin({ left: 6 })
          }
          if (row.opened) {
            Text($r('app.string.child_dbs_opened'))
              .fontSize(10)
              .fontColor($r('app.color.button_bg_blue'))
              .padding({ left: 6, right: 6, top: 1, bottom: 1 })
              .borderRadius(8)
              .backgroundColor($r('app.color.card_bg'))
              .margin({ left: 6 })
          }
        }
        .width('100%')
        Text(row.item.url)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
        Column() {
          this.DeviceStateText(row)
        }
        .alignItems(HorizontalAlign.Start)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Image($r('app.media.ic_arrow_right'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.text_secondary'))
        .margin({ right: 12 })
    }
    .width('100%')
    .constraintSize({ minHeight: 64 })
    .borderRadius(8)
    .backgroundColor($r('app.color.card_bg'))
    .margin({ bottom: 8 })
    .onClick(() => {
    })
    .bindMenu(this.ChildRowMenu(row), {
      // 菜单右对齐锚点弹出（默认左侧），位置放不下时系统自动翻转
      placement: Placement.BottomRight
    })
  }

  @Builder
  EmptyState() {
    Column() {
      Image($r('app.media.ic_empty'))
        .width(100)
        .height(100)
        .margin({ bottom: 16 })
        .fillColor(Color.Gray)
      Text($r('app.string.child_dbs_empty'))
        .fontSize(16)
        .fontColor(Color.Gray)
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
  }

  build() {
    NavDestination() {
      Column() {
        // 功能说明（对齐 kp2a config_child_db 布局：列表上方固定说明文案）
        Text($r('app.string.child_db_explanation'))
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .padding({ left: 16, right: 16, top: 10, bottom: 6 })
          .width('100%')
        if (this.rows.length === 0) {
          this.EmptyState()
        } else {
          Scroll() {
            Column() {
              ForEach(this.rows, (row: ChildRowItem) => {
                this.ChildRow(row)
              }, (row: ChildRowItem) =>
                row.item.entryUuid + '|' + row.deviceEnabled + '|' + row.deviceExplicit + '|' + row.opened)
            }
            .width('100%')
            .padding({ left: 8, right: 8, top: 8, bottom: 24 })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .align(Alignment.TopStart)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title($r('app.string.child_dbs_title'))
    .menus(this.AddMenuBuilder)
    .backgroundColor($r('app.color.bg_primary'))
  }
}

/**
 * 子数据库管理页 Builder 函数
 */
@Builder
export function ChildDatabasesBuilder(name: string, param: Object): void {
  ChildDatabasesPage()
}
