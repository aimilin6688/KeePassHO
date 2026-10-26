import { Kdbx, KdbxEntry } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DateUtils, KdbxUtils, NavigationManager, ResourceManager } from '../common/utils';
import { PageConstants } from '../common/constants/PageConstants';
import { FileService } from '../services/FileService';
import { EntryParam } from '../services/TypeDefined';
import { ExpiryRemindResult, ExpiryRemindService } from '../services/ExpiryRemindService';
import { SettingsService } from '../services/SettingsService';

const DOMAIN = 0xFF00;
const TAG = 'ExpiryReport';

/**
 * 到期报表行视图模型
 */
class ExpiryReportRow {
  entry: KdbxEntry;
  title: string = '';
  username: string = '';
  /** 剩余天数：正数=N 天内到期，0=今天到期，负数=已过期 N 天 */
  remainingDays: number = 0;
  /** 剩余天数本地化文案（加载时预生成，避免 build 内格式化） */
  remainingText: string = '';

  constructor(entry: KdbxEntry, title: string, username: string, remainingDays: number, remainingText: string) {
    this.entry = entry;
    this.title = title;
    this.username = username;
    this.remainingDays = remainingDays;
    this.remainingText = remainingText;
  }
}

@Builder
export function ExpiryReportBuilder(name: string, param: Object): void {
  NavDestination() {
    ExpiryReport()
  }
  .backgroundColor($r('app.color.bg_primary'))
  .hideTitleBar(true)
}

/**
 * 到期报表页（M1 条目到期提醒）：解锁横幅「查看」进入，
 * 分「已过期 / 即将到期」两段展示，按剩余天数排序，支持搜索过滤，
 * 点击条目跳转条目详情。条目卡片样式与边距对齐 TotpView。
 */
@Component
struct ExpiryReport {
  private static readonly DAY_MS: number = 24 * 60 * 60 * 1000;
  private navPathStack: NavPathStack = NavigationManager.getInstance().getNavPathStack()!;
  @State isLoading: boolean = true;
  @State isSearching: boolean = false;
  @State searchText: string = '';
  /** 0=已过期 1=即将到期 */
  @State activeTab: number = 0;
  @State expiredRows: Array<ExpiryReportRow> = [];
  @State expiringRows: Array<ExpiryReportRow> = [];
  @State visibleRows: Array<ExpiryReportRow> = [];
  @State expiredTabText: string = '';
  @State expiringTabText: string = '';
  private remindDays: number = SettingsService.KEY_SECURITY_EXPIRE_REMIND_DAYS_DEFAULT;

  aboutToAppear(): void {
    this.loadReport();
  }

  onPageShow(): void {
    // 从条目编辑页返回时刷新数据
    this.loadReport();
  }

  /**
   * 加载到期报表数据
   */
  private loadReport(): void {
    this.isLoading = true;
    try {
      const dbFileParam = FileService.getInstance().getDbFileParam();
      const database: Kdbx | null = dbFileParam.database ?? null;
      if (!database) {
        hilog.warn(DOMAIN, TAG, 'Database unavailable, pop back');
        this.navPathStack.pop();
        return;
      }
      this.remindDays = SettingsService.getExpireRemindDays();
      const result: ExpiryRemindResult = ExpiryRemindService.collectExpiringEntries(database, this.remindDays);
      const now: number = Date.now();
      this.expiredRows = result.expiredEntries.map((entry: KdbxEntry): ExpiryReportRow => {
        return ExpiryReport.buildRow(entry, now, true);
      });
      this.expiringRows = result.expiringEntries.map((entry: KdbxEntry): ExpiryReportRow => {
        return ExpiryReport.buildRow(entry, now, false);
      });
      this.expiredRows.sort((a: ExpiryReportRow, b: ExpiryReportRow): number => a.remainingDays - b.remainingDays);
      this.expiringRows.sort((a: ExpiryReportRow, b: ExpiryReportRow): number => a.remainingDays - b.remainingDays);
      this.expiredTabText = ResourceManager.getString($r('app.string.expiry_report_tab_expired'), this.expiredRows.length);
      this.expiringTabText = ResourceManager.getString($r('app.string.expiry_report_tab_expiring'), this.expiringRows.length);
      this.applyFilter();
      hilog.info(DOMAIN, TAG, 'Expiry report loaded: expired=%{public}d, expiring=%{public}d',
        this.expiredRows.length, this.expiringRows.length);
    } catch (error) {
      hilog.error(DOMAIN, TAG, 'Failed to load expiry report: %{public}s', `${error}`);
    } finally {
      this.isLoading = false;
    }
  }

  private static buildRow(entry: KdbxEntry, now: number, expired: boolean): ExpiryReportRow {
    const title: string = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_TITLE);
    const username: string = KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_USERNAME);
    const expiryTime: Date | undefined = entry.times.expiryTime;
    let remainingDays: number = 0;
    if (expiryTime) {
      remainingDays = Math.ceil((expiryTime.getTime() - now) / ExpiryReport.DAY_MS);
    }
    let remainingText: string = '';
    if (expired) {
      remainingText = ResourceManager.getString($r('app.string.expiry_report_expired_days'), Math.max(1, -remainingDays));
    } else if (remainingDays <= 0) {
      remainingText = ResourceManager.getString($r('app.string.expiry_report_expires_today'));
    } else {
      remainingText = ResourceManager.getString($r('app.string.expiry_report_expiring_days'), remainingDays);
    }
    return new ExpiryReportRow(entry, title, username, remainingDays, remainingText);
  }

  /**
   * 按当前页签与搜索词过滤行
   */
  private applyFilter(): void {
    const keyword: string = this.searchText.trim().toLowerCase();
    const source: Array<ExpiryReportRow> = this.activeTab === 0 ? this.expiredRows : this.expiringRows;
    if (keyword.length === 0) {
      this.visibleRows = [...source];
      return;
    }
    this.visibleRows = source.filter((row: ExpiryReportRow): boolean => {
      return row.title.toLowerCase().includes(keyword) || row.username.toLowerCase().includes(keyword);
    });
  }

  /**
   * 打开条目详情
   */
  private openEntry(row: ExpiryReportRow): void {
    const entryParam: EntryParam = { entryId: row.entry.uuid.id, groupId: row.entry.parentGroup?.uuid.id };
    this.navPathStack.pushPathByName(PageConstants.PAGE_ENTRY_VIEW, entryParam);
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏：返回 + 标题 + 搜索（对齐 TotpView）
        Row() {
          if (this.isSearching) {
            Row() {
              Search({ placeholder: $r('app.string.expiry_report_search_hint'), value: this.searchText })
                .margin({ left: 16 })
                .height(36)
                .layoutWeight(1)
                .flexShrink(1)
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
                  this.applyFilter();
                })
              Button($r('app.string.cancel_button_text'))
                .width(70)
                .height(36)
                .fontSize(16)
                .flexShrink(0)
                .fontColor($r('app.color.text_primary'))
                .backgroundColor($r('app.color.card_bg'))
                .margin({ right: 16 })
                .padding({ left: 5, right: 5 })
                .onClick(() => {
                  this.isSearching = false;
                  this.searchText = '';
                  this.applyFilter();
                })
            }
            .width('100%')
          } else {
            Image($r('app.media.ic_angle_left'))
              .width(28)
              .height(28)
              .margin({ left: 16 })
              .fillColor($r('app.color.text_primary'))
              .onClick(() => {
                this.navPathStack.pop();
              })
            Text($r('app.string.expiry_report_title'))
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .margin({ left: 16 })
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .width('55%')
            Blank()
            Image($r('app.media.ic_search'))
              .width(24)
              .height(24)
              .margin({ right: 16 })
              .onClick(() => {
                this.isSearching = true;
              })
          }
        }
        .width('100%')
        .height(40)

        // 分段切换：已过期 / 即将到期（边距对齐列表内容区）
        Row({ space: 8 }) {
          Text(this.expiredTabText)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.activeTab === 0 ? Color.White : $r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(36)
            .borderRadius(8)
            .backgroundColor(this.activeTab === 0 ? $r('app.color.button_bg_blue') : $r('app.color.bg_secondary'))
            .onClick(() => {
              this.activeTab = 0;
              this.applyFilter();
            })
          Text(this.expiringTabText)
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.activeTab === 1 ? Color.White : $r('app.color.text_primary'))
            .textAlign(TextAlign.Center)
            .layoutWeight(1)
            .height(36)
            .borderRadius(8)
            .backgroundColor(this.activeTab === 1 ? $r('app.color.button_bg_blue') : $r('app.color.bg_secondary'))
            .onClick(() => {
              this.activeTab = 1;
              this.applyFilter();
            })
        }
        .width('100%')
        .padding({ left: 12, right: 12, top: 4 })

        // 加载中 / 空态 / 列表
        if (this.isLoading) {
          Column() {
            LoadingProgress()
              .width(50)
              .height(50)
              .color($r('app.color.primary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.visibleRows.length === 0) {
          Column() {
            Image($r('app.media.ic_empty'))
              .width(100)
              .height(100)
              .margin({ bottom: 16 })
              .fillColor(Color.Gray)
            Text($r('app.string.expiry_report_empty'))
              .fontSize(16)
              .fontColor(Color.Gray)
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          List({ space: 8 }) {
            ForEach(this.visibleRows, (row: ExpiryReportRow) => {
              ListItem() {
                Stack({ alignContent: Alignment.TopEnd }) {
                  Row() {
                    Image(DateUtils.isExpired(row.entry.times.expires, row.entry.times.expiryTime) ? $r('app.media.C45_Expired') :
                      KdbxUtils.getIcon(row.entry.icon, row.entry.customIcon, $r('app.media.ic_file')))
                      .width(36)
                      .height(36)
                      .margin({
                        left: 6,
                        right: 16,
                        top: 10,
                        bottom: 10
                      })
                      .borderRadius(4)
                    Column() {
                      Text(row.title)
                        .fontSize(18)
                        .textAlign(TextAlign.Start)
                        .flexGrow(1)
                        .textOverflow({ overflow: TextOverflow.Ellipsis })
                        .maxLines(1)
                        .fontColor(row.entry.fgColor || $r('app.color.text_primary'))
                        .decoration({
                          type: (DateUtils.isExpired(row.entry.times.expires, row.entry.times.expiryTime) ?
                            TextDecorationType.LineThrough : TextDecorationType.None)
                        })
                      if (row.username.length > 0) {
                        Text(row.username)
                          .fontSize(12)
                          .fontColor($r('app.color.text_secondary'))
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })
                          .margin({ top: 2 })
                          .width('100%')
                      }
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)

                    Text(row.remainingText)
                      .fontSize(12)
                      .fontColor(this.activeTab === 0 ? $r('app.color.error') : $r('app.color.warn'))
                      .margin({ right: 4 })

                    Image($r('app.media.ic_arrow_right'))
                      .width(28)
                      .height(28)
                      .fillColor(row.entry.fgColor || $r('app.color.text_primary'))
                  }
                  .padding({ left: 2 })
                  .width('100%')
                }
                .borderRadius(8)
                .backgroundColor(row.entry.bgColor || $r('app.color.card_bg'))
                .padding({
                  left: 6,
                  right: 6,
                  top: 6,
                  bottom: 6
                })
                .onClick(() => {
                  this.openEntry(row);
                })
              }
            }, (row: ExpiryReportRow) => row.entry.uuid.id)
          }
          .width('100%')
          .layoutWeight(1)
          .backgroundColor($r('app.color.bg_primary'))
          .padding({
            left: 12,
            right: 12,
            top: 4,
            bottom: 0
          })
          .scrollBar(BarState.Auto)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}
