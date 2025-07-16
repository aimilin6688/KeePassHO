import { PromptAction, Router } from '@kit.ArkUI';
import { Kdbx, KdbxEntry } from 'kdbxweb';
import KdbxUtils from '../common/utils/KdbxUtils';
import { FileService } from '../services/FileService';
import { EntryParam } from '../services/TypeDefined';
import { EntryViewFieldItem, FieldView } from '../components/EntryViewFieldItem';


interface EntryHistoryView {
  index: number;
  date: string;
  historyId: string;
}

@Entry
@Component
struct EntryView {
  @State isLoading: boolean = true;
  @State entry: KdbxEntry | null = null;
  @State fields: Array<FieldView> = [];
  @State historyEntries: Array<EntryHistoryView> = [];
  @State showHistory: boolean = false;
  @State selectedHistoryIndex: number = -1;
  private database: Kdbx | null = null;
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private entryId: string = '';
  private groupId: string = '';

  aboutToAppear() {
    // 获取从DatabaseShow页面传递的参数
    const params = this.router.getParams() as EntryParam;
    this.entryId = params?.entryId || '';
    this.groupId = params?.groupId || '';
  }

  onPageShow(): void {
    // 加载数据库和条目
    this.loadEntry();
  }

  /**
   * 加载条目
   */
  private loadEntry() {
    console.log("加载条目：%s, %s", this.entryId, this.groupId);
    this.isLoading = true;
    try {
      // 获取数据库
      const dbFileParam = FileService.getInstance().getDbFileParam();
      this.database = dbFileParam.database ?? null;

      if (!this.database || !this.entryId) {
        this.promptAction.showToast({
          message: '无效的数据库或条目ID',
          duration: 2000
        });
        this.router.back();
        return;
      }

      // 获取条目
      this.entry = KdbxUtils.getEntry(this.database, this.groupId, this.entryId);

      if (!this.entry) {
        this.promptAction.showToast({
          message: '找不到指定的条目',
          duration: 2000
        });
        this.router.back();
        return;
      }

      // 加载字段
      this.loadFields();

      // 加载历史记录
      this.loadHistory();

    } catch (error) {
      console.error(`加载条目失败: ${error}`);
      this.promptAction.showToast({
        message: `加载条目失败: ${error}`,
        duration: 2000
      });
      this.router.back();
    } finally {
      this.isLoading = false;
    }
  }

  /**
   * 加载条目字段
   */
  private loadFields() {
    if (!this.entry) {
      return;
    }

    this.fields = [];

    // 遍历条目的所有字段
    for (const field of this.entry.fields) {
      const key: string = field[0];
      if (key === KdbxUtils.FIELD_TITLE) {
        continue;
      }
      const value = field[1];
      const isProtected = typeof value !== 'string';
      const strValue = KdbxUtils.getFieldValueString(this.entry.fields, key);

      if (strValue !== '') {
        this.fields.push(new FieldView(key, strValue, isProtected, true));
      }
    }

    // 添加标签字段
    if(this.entry.tags && this.entry.tags.length > 0){
      this.fields.push(new FieldView(KdbxUtils.FIELD_TAGS, this.entry.tags.join(', '), false, true));
    }

    // 字段排序
    this.fields.sort((a, b) => {
      // 将常用字段排在前面
      const commonFields = [KdbxUtils.FIELD_TITLE, KdbxUtils.FIELD_USERNAME, KdbxUtils.FIELD_PASSWORD, KdbxUtils.FIELD_URL, KdbxUtils.FIELD_NOTES, KdbxUtils.FIELD_TAGS];
      const aIndex = commonFields.indexOf(a.key);
      const bIndex = commonFields.indexOf(b.key);

      if (aIndex >= 0 && bIndex >= 0) {
        return aIndex - bIndex;
      } else if (aIndex >= 0) {
        return -1;
      } else if (bIndex >= 0) {
        return 1;
      } else {
        return a.key.localeCompare(b.key);
      }
    });

    // 添加分组信息
    this.fields = [new FieldView(KdbxUtils.GROUP_NAME, this.getGroupName(), false, false), ...this.fields];
    // 增加创建时间和更新时间
    this.fields.push(new FieldView(KdbxUtils.FIELD_CREATION_TIME, this.entry.times.creationTime?.toLocaleString() || '', false, false));
    this.fields.push(new FieldView(KdbxUtils.FIELD_LASTMOD_TIME, this.entry.times.lastModTime?.toLocaleString() || '', false, false));
  }

  /**
   * 加载历史记录
   */
  private loadHistory() {
    if (!this.entry) {
      return;
    }

    this.historyEntries = [];

    // 遍历条目的历史记录
    for (let i = 0; i < this.entry.history.length; i++) {
      const historyEntry = this.entry.history[i];
      const date = historyEntry.times.lastModTime?.toLocaleString() || '未知时间';

      this.historyEntries.push({
        index: i,
        date,
        historyId: historyEntry.uuid.id
      });
    }

    // 按修改时间倒序排序（最新的在前面）
    this.historyEntries.reverse();
  }

  /**
   * 编辑条目
   */
  private editEntry() {
    this.router.pushUrl({
      url: 'pages/EntryEdit',
      params: {
        entryId: this.entryId,
        groupId: this.groupId
      }
    });
  }

  /**
   * 查看历史记录详情
   */
  private viewHistoryDetail(index: number) {
    this.selectedHistoryIndex = index;
  }

  /**
   * 返回当前条目视图
   */
  private backToCurrentEntry() {
    this.selectedHistoryIndex = -1;
  }

  /**
   * 获取分组名称
   */
  private getGroupName(): string {
    if (this.entry && this.entry.parentGroup) {
      return this.entry.parentGroup?.name ?? '';
    }
    return '未分组';
  }

  /**
   * 构建历史记录项
   */
  @Builder
  HistoryItem(item: EntryHistoryView) {
    Row() {
      // 左侧图标
      Image($r('app.media.ic_history'))
        .width(40)
        .height(40)
        .margin({ right: 12 })
        .fillColor($r('app.color.text_primary'))

      // 中间内容区域
      Column() {
        // 版本号
        Text(`历史版本 #${this.historyEntries.length - item.index}`)
          .fontSize(16)
          .fontColor($r('app.color.text_primary'))
          .width('100%')
          .textAlign(TextAlign.Start)
          .margin({ bottom: 4 })

        // 修改日期
        Text(item.date)
          .fontSize(14)
          .fontColor($r('app.color.text_secondary'))
          .width('100%')
          .textAlign(TextAlign.Start)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)

      // 右侧箭头
      Image($r('app.media.ic_arrow_right'))
        .width(24)
        .height(24)
        .fillColor($r('app.color.text_secondary'))
    }
    .width('100%')
    .backgroundColor($r('app.color.card_background'))
    .borderRadius(8)
    .padding(12)
    .margin({ bottom: 8 })
    .onClick(() => {
      this.viewHistoryDetail(item.index);
    })
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Image($r('app.media.ic_back'))
            .width(24)
            .height(24)
            .margin({ left: 16 })
            .fillColor($r('app.color.text_primary'))
            .onClick(() => {
              this.router.back();
            })

          if (this.selectedHistoryIndex >= 0) {
            Text(`历史版本 #${this.historyEntries.length - this.selectedHistoryIndex}`)
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .margin({ left: 16 })
              .fontColor($r('app.color.text_primary'))
          } else {
            Text(KdbxUtils.getFieldValueString(this.entry?.fields, KdbxUtils.FIELD_TITLE) || '查看条目')
              .fontSize(20)
              .fontWeight(FontWeight.Medium)
              .margin({ left: 16 })
              .fontColor($r('app.color.text_primary'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }

          Blank()

          if (this.selectedHistoryIndex < 0) {
            Button() {
              Image($r('app.media.ic_edit'))
                .width(24)
                .height(24)
                .fillColor($r('app.color.text_primary'))
            }
            .backgroundColor(Color.Transparent)
            .width(48)
            .height(48)
            .borderRadius(20)
            .margin({ right: 16 })
            .onClick(() => {
              this.editEntry();
            })
          }
        }
        .width('100%')
        .height(56)
        .backgroundColor($r('app.color.card_background'))

        if (this.isLoading) {
          // 加载中状态
          Column() {
            LoadingProgress()
              .width(50)
              .height(50)
              .color($r('app.color.primary'))

            Text('正在加载条目...')
              .fontSize(16)
              .margin({ top: 16 })
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.background_primary'))
        } else if (this.selectedHistoryIndex >= 0 && this.selectedHistoryIndex < this.historyEntries.length) {
          // 显示历史记录详情
          Column() {
            // 历史记录详情
            List() {
              ListItem() {
                Row() {
                  Text('修改时间:')
                    .fontSize(16)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.text_primary'))

                  Text(this.historyEntries[this.selectedHistoryIndex].date)
                    .fontSize(16)
                    .fontColor($r('app.color.text_primary'))
                    .margin({ left: 8 })
                }
                .width('100%')
                .height('100%')
                .padding(16)
                .backgroundColor($r('app.color.card_background'))
                .borderRadius(8)
                .margin({ bottom: 16 })
              }

              ListItem() {
                Button('返回当前版本')
                  .width('100%')
                  .height(50)
                  .backgroundColor($r('app.color.primary'))
                  .fontColor(Color.White)
                  .onClick(() => {
                    this.backToCurrentEntry();
                  })
              }
              .margin({ top: 16, bottom: 16 })
            }
            .width('100%')
            .padding({ left: 16, right: 16, top: 16 })
            .layoutWeight(1)
            .backgroundColor($r('app.color.background_primary'))
          }
          .width('100%')
          .height('100%')
        } else {
          // 显示当前条目
          Tabs() {
            TabContent() {
              List() {
                ForEach(this.fields, (field: FieldView) => {
                  ListItem() {
                    EntryViewFieldItem({ field: field, entry: this.entry })
                  }
                })
              }
              .height('100%')
              .width('100%')
              .padding({ left: 16, right: 16, top: 12, bottom:40 })
              .layoutWeight(1)
              .backgroundColor($r('app.color.background_primary'))
            }
            .tabBar('字段')

            TabContent() {
              if (this.historyEntries.length > 0) {
                List() {
                  ForEach(this.historyEntries, (item: EntryHistoryView) => {
                    ListItem() {
                      this.HistoryItem(item)
                    }
                  })
                }
                .height('100%')
                .width('100%')
                .padding({ left: 16, right: 16, top: 12, bottom:40 })
                .layoutWeight(1)
                .backgroundColor($r('app.color.background_primary'))
              } else {
                Column() {
                  Image($r('app.media.ic_history'))
                    .width(80)
                    .height(80)
                    .fillColor($r('app.color.text_secondary'))
                    .opacity(0.5)

                  Text('没有历史记录')
                    .fontSize(16)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 16 })
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .backgroundColor($r('app.color.background_primary'))
              }
            }
            .tabBar('历史记录')
          }
          .width('100%')
          .height('100%')
          .barMode(BarMode.Fixed)
          .barWidth('100%')
          .barHeight(40) // 减少tab标签页的高度
        }
      }
      .width('100%')
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }
}