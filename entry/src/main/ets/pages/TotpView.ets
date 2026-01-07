import { KdbxEntry } from 'kdbxweb';
import { SortMode } from '../common/constants/SortConstants';
import { KdbxUtils, DateUtils, ClipboardUtils, WindowUtils, CommonUtils } from '../common/utils';
import { FileService } from '../services/FileService';
import { SettingsService } from '../services/SettingsService';
import { Router } from '@kit.ArkUI';
import { TotpPreviewComponent } from '../components/TotpPreviewComponent';
import { common } from '@kit.AbilityKit';

@Entry
@Component
struct TotpView {
  @State resultEntries: Array<KdbxEntry> = [];
  @State searchText: string = ''; // 搜索文本
  @State isSearching: boolean = false; // 是否处于搜索状态
  private router: Router = this.getUIContext().getRouter();
  private totpEntries: Array<KdbxEntry> = []; // 过滤后的条目列表

  aboutToAppear(): void {
    this.loadTotpEntries();
  }

  onPageShow(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
  }

  private loadTotpEntries(): void {
    this.totpEntries = [];
    const kdbx = FileService.getDatabase();
    if (!kdbx) {
      return;
    }
    let result = KdbxUtils.searchInGroup(kdbx.getDefaultGroup(), 'otpauth://totp/');
    const sortBy = SettingsService.getInstance().getSync(SettingsService.KEY_SORT_BY, SortMode.DEFAULT);
    KdbxUtils.sortBy([], result.filteredEntries, sortBy);
    this.totpEntries.push(...result.filteredEntries);
    this.resultEntries.push(...result.filteredEntries);
  }

  /**
   * 显示搜索框
   */
  private showSearch() {
    this.isSearching = true;
    this.searchText = '';
  }

  /**
   * 执行搜索
   * @param value
   */
  private doSearch(value: string) {
    this.searchText = value;
    this.resultEntries.splice(0, this.resultEntries.length);
    // 清空重新添加
    if (!this.searchText || this.searchText.trim() === '') {
      this.resultEntries.push(...this.totpEntries);
      return;
    }
    this.resultEntries.push(...KdbxUtils.searchInEntries(this.totpEntries, this.searchText));
  }

  build() {
    Stack() {
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
                    this.doSearch(value);
                  })
                  .onSubmit((value: string) => {
                    this.doSearch(value);
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
                    this.doSearch('');
                  })
              }
              .width('100%')
            }
            .margin({ top: 12 })
            .width('100%')
          } else {
            Image($r("app.media.ic_angle_left"))
              .width(24)
              .height(24)
              .margin({ left: 16 })
              .fillColor($r('app.color.text_primary'))
              .onClick(() => {
                this.router.back();
              })
            Text($r("app.string.totp_title"))
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
          }
        }
        .width('100%')
        .height(56)

        // 数据库内容
        List({ space: 8 }) {
          if (!this.resultEntries || this.resultEntries.length == 0) {
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
            // 条目数据展示
            ForEach(this.resultEntries, (itemEntry: KdbxEntry, index: number) => {
              ListItem() {
                Row() {
                  Image(DateUtils.isExpired(itemEntry.times.expires, itemEntry.times.expiryTime) ? $r('app.media.C45_Expired') :
                    KdbxUtils.getIcon(itemEntry.icon, itemEntry.customIcon, $r('app.media.ic_file')))
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
                    // TOTP 字段展示
                    ForEach(KdbxUtils.getTotpUrl(itemEntry), (totpUrl: string, index: number) => {
                      TotpPreviewComponent({
                        totpUrl: totpUrl, doClick: (value) => {
                          ClipboardUtils.copyAutoClear(value);
                          return false;
                        }
                      }).margin({ top: 6 })
                    });
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
                .width('100%')
                .borderRadius(8)
                .backgroundColor($r("app.color.card_bg"))
                .padding({
                  left: 6,
                  right: 6,
                  top: 8,
                  bottom: 8
                })
                .onClick(() => {
                  CommonUtils.pushUrl({ url: 'pages/EntryView', params: { entryId: itemEntry.uuid.id, groupId: itemEntry.parentGroup?.uuid.id } });
                })
              }
            }, (item: KdbxEntry, index: number) => `${index}-${item.uuid.id}`)

            ListItem() {
              Row()
                .height(100)
                .width('100%')
                .backgroundColor(Color.Transparent)
            }
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
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}