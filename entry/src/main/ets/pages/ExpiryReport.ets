import { Kdbx, KdbxEntry } from 'kdbxweb';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { KdbxUtils, NavigationManager, ResourceManager } from '../common/utils';
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
  .title($r('app.string.expiry_report_title'))
  .backgroundColor($r('app.color.bg_primary'))
}

/**
 * 到期报表页（M1 条目到期提醒）：解锁横幅「查看」进入，
 * 分「已过期 / 即将到期」两段展示，按剩余天数排序，支持搜索过滤，
 * 点击条目跳转条目详情。
 */
@Component
struct ExpiryReport {
  private static readonly DAY_MS: number = 24 * 60 * 60 * 1000;
  private navPathStack: NavPathStack = NavigationManager.getInstance().getNavPathStack()!;
  @State isLoading: boolean = true;
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
    Column() {
      // 搜索框
      TextInput({ placeholder: $r('app.string.expiry_report_search_hint'), text: this.searchText })
        .onChange((value: string) => {
          this.searchText = value;
          this.applyFilter();
        })
        .height(40)
        .fontSize(14)
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(8)
        .margin({ left: 12, right: 12, top: 8 })

      // 分段切换：已过期 / 即将到期
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
      .margin({ left: 12, right: 12, top: 8 })

      // 空态 / 列表
      if (this.visibleRows.length === 0) {
        Column() {
          Text(this.isLoading ? '' : $r('app.string.expiry_report_empty'))
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
        }
        .width('100%')
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List({ space: 0 }) {
          ForEach(this.visibleRows, (row: ExpiryReportRow) => {
            ListItem() {
              Row({ space: 12 }) {
                Column({ space: 2 }) {
                  Text(row.title)
                    .fontSize(15)
                    .fontColor($r('app.color.text_primary'))
                    .maxLines(1)
                    .textOverflow({ overflow: TextOverflow.Ellipsis })
                  if (row.username.length > 0) {
                    Text(row.username)
                      .fontSize(12)
                      .fontColor($r('app.color.text_secondary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                }
                .alignItems(HorizontalAlign.Start)
                .layoutWeight(1)

                Text(row.remainingText)
                  .fontSize(12)
                  .fontColor(this.activeTab === 0 ? $r('app.color.error') : $r('app.color.warn'))
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 10, bottom: 10 })
              .onClick(() => {
                this.openEntry(row);
              })
            }
          }, (row: ExpiryReportRow) => row.entry.uuid.id)
        }
        .width('100%')
        .layoutWeight(1)
        .backgroundColor($r('app.color.card_bg'))
        .borderRadius(12)
        .divider({ strokeWidth: 0.5, color: $r('app.color.divider') })
        .margin({ left: 12, right: 12, top: 8 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.bg_primary'))
  }
}
