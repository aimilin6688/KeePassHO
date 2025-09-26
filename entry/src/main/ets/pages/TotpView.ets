import { KdbxEntry } from 'kdbxweb';
import { SortMode } from '../common/constants/SortConstants';
import KdbxUtils from '../common/utils/KdbxUtils';
import { FileService } from '../services/FileService';
import { SettingsService } from '../services/SettingsService';
import { Router } from '@kit.ArkUI';
import DateUtils from '../common/utils/DateUtils';
import { TotpPreviewComponent } from '../components/TotpPreviewComponent';

@Entry
@Component
struct TotpView {
  @State totpEntries: Array<KdbxEntry> = []; // 过滤后的条目列表
  private router: Router = this.getUIContext().getRouter();

  aboutToAppear(): void {
    this.loadTotpEntries();
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
  }

  build() {
    Stack() {
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
          Text($r("app.string.totp_title"))
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .margin({ left: 16 })
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('55%')
        }
        .width('100%')
        .height(56)

        // 数据库内容
        List({ space: 8 }) {
          if(!this.totpEntries || this.totpEntries.length == 0){
            ListItem(){
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
          }else{
            // 条目数据展示
            ForEach(this.totpEntries, (itemEntry: KdbxEntry, index: number) => {
              ListItem() {
                Row() {
                  Image(DateUtils.isExpired(itemEntry.times.expires, itemEntry.times.expiryTime) ? $r('app.media.C45_Expired') :
                  KdbxUtils.getIcon(itemEntry.icon, itemEntry.customIcon, $r('app.media.ic_file')))
                    .width(36)
                    .height(36)
                    .margin({left: 6, right: 16, top: 10, bottom: 10})
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
                      TotpPreviewComponent({ totpUrl: totpUrl })
                    });
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
                .backgroundColor($r("app.color.card_bg"))
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