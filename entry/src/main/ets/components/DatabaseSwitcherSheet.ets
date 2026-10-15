import { emitter } from '@kit.BasicServicesKit';

import { AutoOpenCoordinator } from '../services/autoopen/AutoOpenCoordinator';
import { AutoOpenItem } from '../services/autoopen/AutoOpenItem';
import { AutoOpenService } from '../services/autoopen/AutoOpenService';
import { AutoOpenPathResolver } from '../services/autoopen/AutoOpenPathResolver';
import { DeviceIdentity } from '../services/autoopen/DeviceIdentity';
import { IfDeviceParser } from '../services/autoopen/IfDeviceParser';
import { DatabaseRegistry, OpenDatabaseRecord } from '../services/database/DatabaseRegistry';
import { FileService } from '../services/FileService';
import { EventBus } from '../services/EventBus';
import { NavigationManager } from '../common/utils';
import { PageConstants } from '../common/constants/PageConstants';
import { StorageType } from '../storage';

/**
 * 数据库切换面板（M3，bindSheet 半模态内容）：
 * - 区块 1「已打开」：注册表全部记录，当前库高亮标记，点击切换当前库；
 * - 区块 2「子数据库」：当前库 AutoOpen 条目中可见 + 本设备启用 + 未打开的子库，点击手动打开；
 * - 区块 3「打开其他数据库…」：以添加模式（保留已打开库）进入最近文件选择。
 * 面板展示期间监听子库打开事件实时刷新列表。
 */
@Component
export struct DatabaseSwitcherSheet {
  // 父组件驱动的刷新节拍（bindSheet 每次展开自增）：@Watch 触发数据重建
  @Prop @Watch('onRefreshTick') refreshTick: number = 0;
  // 关闭请求回调（父组件置 bindSheet 显示状态为 false）
  onRequestClose: () => void = () => {
  };
  @State openRecords: OpenDatabaseRecord[] = [];
  @State currentKey: string | null = null;
  @State childItems: AutoOpenItem[] = [];

  private registry: DatabaseRegistry = FileService.getRegistry();
  private navManager: NavigationManager = NavigationManager.getInstance();
  private onChildOpened: Callback<emitter.EventData> = (): void => {
    this.refreshData();
  };
  private onChildOpenFailed: Callback<emitter.EventData> = (event: emitter.EventData): void => {
    AutoOpenCoordinator.showOpenFailedToast(event);
    this.refreshData();
  };
  private onAutoOpenDone: Callback<emitter.EventData> = (): void => {
    this.refreshData();
  };
  private onCurrentChanged: Callback<emitter.EventData> = (): void => {
    this.refreshData();
  };

  aboutToAppear(): void {
    this.refreshData();
    EventBus.on(AutoOpenCoordinator.EVENT_DATABASE_OPENED, this.onChildOpened);
    EventBus.on(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED, this.onChildOpenFailed);
    EventBus.on(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, this.onAutoOpenDone);
    EventBus.on(DatabaseRegistry.EVENT_CURRENT_DATABASE_CHANGED, this.onCurrentChanged);
  }

  aboutToDisappear(): void {
    EventBus.off(AutoOpenCoordinator.EVENT_DATABASE_OPENED, this.onChildOpened);
    EventBus.off(AutoOpenCoordinator.EVENT_DATABASE_OPEN_FAILED, this.onChildOpenFailed);
    EventBus.off(AutoOpenCoordinator.EVENT_AUTO_OPEN_DONE, this.onAutoOpenDone);
    EventBus.off(DatabaseRegistry.EVENT_CURRENT_DATABASE_CHANGED, this.onCurrentChanged);
  }

  onRefreshTick(): void {
    this.refreshData();
  }

  /**
   * 重建面板数据：已打开记录 + 当前库的待打开子库条目
   */
  private refreshData(): void {
    this.openRecords = this.registry.all();
    this.currentKey = this.registry.getCurrentKey();
    this.childItems = this.collectChildItems();
  }

  /**
   * 收集区块 2 子库条目：当前库 AutoOpen 条目中
   * 可见（Visible）+ 本设备启用（IfDevice）+ 未打开（不在注册表）的条目
   */
  private collectChildItems(): AutoOpenItem[] {
    const currentParam = this.registry.getCurrent();
    const parentIocKey = this.registry.getCurrentKey();
    if (currentParam === undefined || !currentParam.database || parentIocKey === null) {
      return [];
    }
    const deviceId: string = DeviceIdentity.getDeviceId();
    const items: AutoOpenItem[] = [];
    const scanned: AutoOpenItem[] = AutoOpenService.scan(currentParam.database, parentIocKey);
    for (const item of scanned) {
      if (!item.visible || !item.enabled) {
        continue;
      }
      if (!IfDeviceParser.isEnabled(item.ifDeviceRaw, deviceId).enabled) {
        continue;
      }
      const childPath: string = AutoOpenPathResolver.resolveUrl(item.url, currentParam.filePath);
      if (childPath.length === 0) {
        continue;
      }
      if (this.registry.has(DatabaseRegistry.buildIocKey(StorageType.LOCAL, childPath))) {
        continue;
      }
      items.push(item);
    }
    return items;
  }

  /**
   * 区块 1 点击：切换当前库（注册表广播 CURRENT_DATABASE_CHANGED，数据库视图自动重载）
   */
  private switchTo(record: OpenDatabaseRecord): void {
    if (record.iocKey !== this.currentKey) {
      this.registry.setCurrent(record.iocKey);
    }
    this.onRequestClose();
  }

  /**
   * 区块 2 点击：手动打开子库（成功后成为当前库；失败仅提示，面板保留供重试）。
   * 加载为异步入队，异步失败终态经 OPEN_FAILED 事件由 onChildOpenFailed 提示
   */
  private openChild(item: AutoOpenItem): void {
    AutoOpenCoordinator.getInstance().openManually(item).then((result: string) => {
      if (result === 'failed') {
        this.getUIContext().getPromptAction().showToast({
          message: $r('app.string.child_dbs_open_failed',
            item.title.length > 0 ? item.title : item.url),
          duration: 2000
        });
        return;
      }
      this.onRequestClose();
    });
  }

  /**
   * 区块 3 点击：以添加模式进入最近文件选择（打开新库不清已打开的库）
   */
  private openOtherDatabase(): void {
    this.onRequestClose();
    const navParam: Record<string, string> = { 'openMode': 'add' };
    this.navManager.navigateTo(PageConstants.PAGE_RECENT_FILES, navParam);
  }

  /**
   * 管理子数据库行点击：收起面板并进入子数据库管理页
   */
  private manageChildDatabases(): void {
    this.onRequestClose();
    this.navManager.navigateTo(PageConstants.PAGE_CHILD_DATABASES);
  }

  @Builder
  SectionHeader(title: ResourceStr) {
    Text(title)
      .fontSize(13)
      .fontColor($r('app.color.text_secondary'))
      .margin({ top: 16, left: 16, bottom: 4 })
      .width('100%')
  }

  @Builder
  OpenRecordRow(record: OpenDatabaseRecord) {
    Row() {
      Image($r('app.media.file_kdbx'))
        .width(28)
        .height(28)
        .margin({ left: 12, right: 12 })
      Column() {
        Text(record.dbFileParam.fileName)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(record.dbFileParam.filePath)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      if (record.iocKey === this.currentKey) {
        Text($r('app.string.database_switcher_current'))
          .fontSize(12)
          .fontColor($r('app.color.button_bg_blue'))
          .padding({ left: 8, right: 8, top: 2, bottom: 2 })
          .borderRadius(10)
          .backgroundColor($r('app.color.card_bg'))
          .margin({ right: 12 })
      }
    }
    .width('100%')
    .height(56)
    .borderRadius(8)
    .backgroundColor(record.iocKey === this.currentKey ? $r('app.color.bg_secondary') : Color.Transparent)
    .onClick(() => {
      this.switchTo(record);
    })
  }

  @Builder
  ChildItemRow(item: AutoOpenItem) {
    Row() {
      Image($r('app.media.file_kdbx'))
        .width(28)
        .height(28)
        .margin({ left: 12, right: 12 })
      Column() {
        Text(item.title.length > 0 ? item.title : item.url)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(item.url)
          .fontSize(12)
          .fontColor($r('app.color.text_secondary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .margin({ top: 2 })
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
    .height(56)
    .borderRadius(8)
    .onClick(() => {
      this.openChild(item);
    })
  }

  @Builder
  OpenOtherRow() {
    Row() {
      Image($r('app.media.ic_add_file'))
        .width(28)
        .height(28)
        .margin({ left: 12, right: 12 })
      Text($r('app.string.database_switcher_open_other'))
        .fontSize(16)
        .fontColor($r('app.color.button_bg_blue'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
    }
    .width('100%')
    .height(52)
    .borderRadius(8)
    .margin({ top: 8 })
    .onClick(() => {
      this.openOtherDatabase();
    })
  }

  /**
   * 管理子数据库行（区块 3 之后）：进入子数据库管理页
   */
  @Builder
  ManageChildDatabasesRow() {
    Row() {
      Image($r('app.media.file_kdbx'))
        .width(28)
        .height(28)
        .margin({ left: 12, right: 12 })
      Text($r('app.string.child_dbs_manage'))
        .fontSize(16)
        .fontColor($r('app.color.text_primary'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Image($r('app.media.ic_arrow_right'))
        .width(20)
        .height(20)
        .fillColor($r('app.color.text_secondary'))
        .margin({ right: 12 })
    }
    .width('100%')
    .height(52)
    .borderRadius(8)
    .margin({ top: 8 })
    .onClick(() => {
      this.manageChildDatabases();
    })
  }

  build() {
    Column() {
      Text($r('app.string.database_switcher_title'))
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.text_primary'))
        .margin({ top: 16, bottom: 4 })
      Scroll() {
        Column() {
          if (this.openRecords.length > 0) {
            this.SectionHeader($r('app.string.database_switcher_opened_section'))
            ForEach(this.openRecords, (record: OpenDatabaseRecord) => {
              this.OpenRecordRow(record)
            }, (record: OpenDatabaseRecord) => record.iocKey)
          }
          if (this.childItems.length > 0) {
            this.SectionHeader($r('app.string.database_switcher_children_section'))
            ForEach(this.childItems, (item: AutoOpenItem) => {
              this.ChildItemRow(item)
            }, (item: AutoOpenItem) => item.entryUuid)
          }
          this.OpenOtherRow()
          this.ManageChildDatabasesRow()
        }
        .width('100%')
        .padding({ left: 8, right: 8, bottom: 24 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .align(Alignment.TopStart)
    }
    .width('100%')
    .height('100%')
    .padding({ left: 8, right: 8 })
  }
}
