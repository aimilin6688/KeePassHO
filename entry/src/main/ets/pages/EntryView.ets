import { PromptAction, Router } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils, Kdbx, KdbxBinaries, KdbxBinary, KdbxBinaryWithHash, KdbxEntry, ProtectedValue } from 'kdbxweb';
import KdbxUtils from '../common/utils/KdbxUtils';
import { FileService } from '../services/FileService';
import { EntryParam } from '../services/TypeDefined';
import { EntryViewFieldItem, FieldView } from '../components/EntryViewFieldItem';
import DateUtils from '../common/utils/DateUtils';
import { ToastSaveDatabaseCallback } from '../workers/callback/ToastSaveDatabaseCallback';


const DOMAIN = 0xFF00;
const TAG = 'EntryView';

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
    this.selectedHistoryIndex = params.historyIndex === undefined ? -1 : params.historyIndex;
  }

  onPageShow(): void {
    // 加载数据库和条目
    this.loadEntry();
  }

  /**
   * 加载条目
   */
  private loadEntry() {
    hilog.info(DOMAIN, TAG, 'Loading entry: entryId=%{public}s, groupId=%{public}s, historyIndex:%{public}d', this.entryId, this.groupId,
      this.selectedHistoryIndex);
    this.isLoading = true;
    try {
      // 获取数据库
      const dbFileParam = FileService.getInstance().getDbFileParam();
      this.database = dbFileParam.database ?? null;

      if (!this.database || !this.entryId) {
        this.promptAction.showToast({
          message: $r('app.string.invalid_db_or_entry'),
          duration: 2000
        });
        this.router.back();
        return;
      }

      // 获取条目
      this.entry = KdbxUtils.getEntry(this.database, this.groupId, this.entryId, this.selectedHistoryIndex);

      if (!this.entry) {
        this.promptAction.showToast({
          message: $r('app.string.entry_not_found'),
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
      hilog.error(DOMAIN, TAG, '%{public}s', `Failed to load entry: ${error}`);
      this.promptAction.showToast({
        message: $r('app.string.load_entry_failed') + `: ${error}`,
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
      const strValue = KdbxUtils.getValueString(value);
      if (strValue !== '') {
        this.fields.push(new FieldView(key, strValue, KdbxUtils.isProtectedValue(value), true));
      }
    }

    // 添加标签字段
    if (this.entry.tags && this.entry.tags.length > 0) {
      this.fields.push(new FieldView(KdbxUtils.FIELD_TAGS, this.entry.tags.join(', '), false, true));
    }

    // 添加覆盖URL
    if (this.entry.overrideUrl && this.entry.overrideUrl.length > 0) {
      this.fields.push(new FieldView(KdbxUtils.FIELD_OVERRIDE_URL, this.entry.overrideUrl, false, true));
    }

    // 字段排序
    this.fields.sort((a, b) => {
      // 将常用字段排在前面
      const commonFields = [KdbxUtils.FIELD_TITLE, KdbxUtils.FIELD_USERNAME, KdbxUtils.FIELD_PASSWORD, KdbxUtils.FIELD_URL, KdbxUtils.FIELD_NOTES, KdbxUtils.FIELD_TAGS,KdbxUtils.FIELD_OVERRIDE_URL];
      const aIndex = commonFields.indexOf(a.key);
      const bIndex = commonFields.indexOf(b.key);

      if (aIndex >= 0 && bIndex >= 0) {
        return aIndex - bIndex;
      } else if (aIndex >= 0) {
        return -1;
      } else if (bIndex >= 0) {
        return 1;
      } else {
        return this.fields.indexOf(a) - this.fields.indexOf(b);
      }
    });

    // 添加分组信息
    this.fields = [new FieldView(KdbxUtils.GROUP_NAME, this.getGroupName(), false, false), ...this.fields];

    // 展示附件
    this.addBinaries();

    // 过期时间
    if (this.entry.times.expires) {
      this.fields.push(new FieldView(KdbxUtils.FIELD_EXPIRY_TIME, DateUtils.format(this.entry.times.expiryTime), false, false));
    }

    // 增加创建时间和更新时间
    this.fields.push(new FieldView(KdbxUtils.FIELD_CREATION_TIME, DateUtils.format(this.entry.times.creationTime), false, false));
    this.fields.push(new FieldView(KdbxUtils.FIELD_LASTMOD_TIME, DateUtils.format(this.entry.times.lastModTime), false, false));
  }

  // 添加附件属性
  private addBinaries() {
    if (!this.entry || this.entry?.binaries.size <= 0) {
      return;
    }
    for (const entry of this.entry.binaries) {
      this.addBinary(entry[0], entry[1]);
    }
  }

  // 添加单个附件属性
  private addBinary(key: string, binary: KdbxBinary | KdbxBinaryWithHash) {
    if (binary instanceof ProtectedValue) {
      this.fields.push(new FieldView(key, "", false, false, ByteUtils.stringToBuffer(binary.getText())));
    }
    // 二进制文件
    else if (binary instanceof ArrayBuffer) {
      this.fields.push(new FieldView(key, "", false, false, binary));
    }
    // hash 值
    else if (KdbxBinaries.isKdbxBinaryWithHash(binary)) {
      let binaryHash: KdbxBinaryWithHash = binary as KdbxBinaryWithHash;
      this.addBinary(key, binaryHash.value);
    }
  }

  /**
   * 加载历史记录
   */
  private loadHistory() {
    if (!this.entry || this.selectedHistoryIndex >= 0) {
      return;
    }

    this.historyEntries = [];

    // 遍历条目的历史记录
    for (let i = 0; i < this.entry.history.length; i++) {
      const historyEntry = this.entry.history[i];
      const date = DateUtils.format(historyEntry.times.lastModTime);

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
    this.router.pushUrl({
      url: 'pages/EntryView',
      params: {
        entryId: this.entryId,
        groupId: this.groupId,
        historyIndex: index
      }
    });
  }

  /**
   * 获取分组名称
   */
  private getGroupName(): string {
    return KdbxUtils.getGroupPath(this.entry?.parentGroup, "/", false);
  }

  /**
   * 删除历史记录
   */
  private deleteHistory() {
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
          let entry = KdbxUtils.getEntry(this.database, this.groupId, this.entryId);
          if (entry) {
            entry.removeHistory(this.selectedHistoryIndex);
            KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
              onSuccess: () => {
                this.router.back();
              }
            }));
          }
        }
      }
    });
  }

  /**
   * 回滚到历史记录
   */
  private rollbackToHistory() {
    this.getUIContext().showAlertDialog({
      title: $r("app.string.dialog_confirm_title"),
      message: $r("app.string.dialog_rollback_confirm_message"),
      primaryButton: {
        value: $r('app.string.cancel_button_text'),
        action: () => {
        }
      },
      secondaryButton: {
        value: $r("app.string.rollback_button_text"),
        action: () => {
          let entry = KdbxUtils.getEntry(this.database, this.groupId, this.entryId);
          if (entry) {
            entry.copyFrom(this.entry);
            KdbxUtils.saveDatabase(ToastSaveDatabaseCallback.wrap({
              onSuccess: () => {
                this.router.back();
              }
            }));
          }
        }
      }
    });
  }

  /**
   * 构建历史记录项
   */
  @Builder
  HistoryItem(item: EntryHistoryView) {
    Row() {
      // 左侧图标
      Image($r("app.media.ic_clock"))
        .width(40)
        .height(40)
        .margin({ right: 12 })
        .fillColor($r('app.color.text_primary'))

      // 中间内容区域
      Column() {
        // 版本号
        Text($r('app.string.history_version', item.index + 1))
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
    .backgroundColor($r("app.color.card_bg"))
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
          Image($r("app.media.ic_angle_left"))
            .width(24)
            .height(24)
            .margin({ left: 16 })
            .fillColor($r('app.color.text_primary'))
            .onClick(() => {
              this.router.back();
            })

          Row() {
            if (this.selectedHistoryIndex >= 0) {
              Text($r('app.string.history_version', this.selectedHistoryIndex + 1))
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .margin({ left: 16 })
                .fontColor($r('app.color.text_primary'))
            } else {
              Text(KdbxUtils.getFieldValueString(this.entry?.fields, KdbxUtils.FIELD_TITLE) || '')
                .fontSize(20)
                .fontWeight(FontWeight.Medium)
                .margin({ left: 16 })
                .fontColor($r('app.color.text_primary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .width('80%')
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
          .alignItems(VerticalAlign.Center)
          .width('auto')
          .layoutWeight(1)

        }
        .width('100%')
        .height(56)

        if (this.isLoading) {
          // 加载中状态
          Column() {
            LoadingProgress()
              .width(50)
              .height(50)
              .color($r('app.color.primary'))

            Text($r('app.string.loading_message'))
              .fontSize(16)
              .margin({ top: 16 })
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r("app.color.bg_primary"))
        } else if (this.selectedHistoryIndex >= 0) {
          List() {
            ForEach(this.fields, (field: FieldView) => {
              ListItem() {
                EntryViewFieldItem({ field: field, entry: this.entry })
              }
            })

            ListItem() {
              Row()
                .height(100)
                .width('100%')
                .backgroundColor(Color.Transparent)
            }
          }
          .height('100%')
          .width('100%')
          .padding({
            left: 16,
            right: 16,
            bottom: 0
          })
          .layoutWeight(1)

          // 操作按钮
          Row() {
            // 回滚按钮
            Button() {
              Row() {
                Image($r('app.media.ic_rollback'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.button_text'))
                  .margin({ right: 8 })

                Text($r('app.string.rollback_button_text'))
                  .fontSize(16)
                  .fontColor($r('app.color.button_text'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
            .width('45%')
            .height(40)
            .borderRadius(16)
            .backgroundColor($r("app.color.error"))
            .onClick(() => {
              this.rollbackToHistory();
            })

            Blank()
            // 删除按钮
            Button() {
              Row() {
                Image($r('app.media.ic_delete'))
                  .width(20)
                  .height(20)
                  .fillColor($r('app.color.button_text'))
                  .margin({ right: 8 })

                Text($r('app.string.delete_button_text'))
                  .fontSize(16)
                  .fontColor($r('app.color.button_text'))
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
            }
            .width('45%')
            .height(40)
            .borderRadius(16)
            .backgroundColor(Color.Gray)
            .onClick(() => {
              this.deleteHistory();
            })
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
          .translate({ y: -45 }) // 调整位置，确保正确显示
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
              .padding({
                left: 16,
                right: 16,
                top: 12,
                bottom: 40
              })
              .layoutWeight(1)
              .backgroundColor($r("app.color.bg_primary"))
            }
            .tabBar($r('app.string.field_name'))

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
                .padding({
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 40
                })
                .layoutWeight(1)
                .backgroundColor($r("app.color.bg_primary"))
              } else {
                Column() {
                  Image($r("app.media.ic_clock"))
                    .width(80)
                    .height(80)
                    .fillColor($r('app.color.text_secondary'))
                    .opacity(0.5)

                  Text($r('app.string.no_history'))
                    .fontSize(16)
                    .fontColor($r('app.color.text_secondary'))
                    .margin({ top: 16 })
                }
                .width('100%')
                .height('100%')
                .justifyContent(FlexAlign.Center)
                .backgroundColor($r("app.color.bg_primary"))
              }
            }
            .tabBar($r('app.string.history_record'))
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
    .backgroundColor($r("app.color.bg_primary"))
    .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
  }
}