import KdbxSaveService from '../services/kdbx/KdbxSaveService';
import { PromptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ByteUtils, Kdbx, KdbxBinaries, KdbxBinary, KdbxBinaryDiskRef, KdbxBinaryWithHash, KdbxEntry, ProtectedValue } from 'kdbxweb';
import { KdbxUtils, DateUtils, WindowUtils, CommonUtils, NavigationManager, StringUtils, ResourceManager } from '../common/utils';
import { PageConstants } from '../common/constants/PageConstants';
import { FileService } from '../services/FileService';
import { EntryParam } from '../services/TypeDefined';
import { EntryViewFieldItem, FieldView } from '../components/EntryViewFieldItem';
import { ToastSaveDatabaseCallback } from '../workers/callback/ToastSaveDatabaseCallback';
import { common } from '@kit.AbilityKit';
import { OtpExtractionResult } from '../services/otp';
import { EventBus } from '../services/EventBus';
import { SessionManager } from '../services/SessionManager';
import { SettingsService } from '../services/SettingsService';
import { BusinessError, emitter } from '@kit.BasicServicesKit';

const DOMAIN = 0xFF00;
const TAG = 'EntryView';
const DAY_MS: number = 24 * 60 * 60 * 1000;

interface EntryHistoryView {
  index: number;
  date: string;
  historyId: string;
}

// EntryView页面的Builder函数
@Builder
export function EntryViewBuilder(name: string, param: Object): void {
  NavDestination() {
    EntryView({ entryParam: param as EntryParam })
  }
  .backgroundColor($r('app.color.bg_primary'))
  .hideTitleBar(true)  // 隐藏 NavDestination 的默认标题栏，使用组件内部的自定义标题栏
}

@Component
export struct EntryView {
  // 底部悬浮按钮栏总高度（自身高度 60 + 底部留白 16）
  private readonly BOTTOM_BAR_HEIGHT: number = 70;
  private navPathStack: NavPathStack = NavigationManager.getInstance().getNavPathStack()!;
  private entryParam: EntryParam | undefined = undefined;
  @State isLoading: boolean = true;
  @State entry: KdbxEntry | null = null;
  @State fields: Array<FieldView> = [];
  @State historyEntries: Array<EntryHistoryView> = [];
  @State showHistory: boolean = false;
  @State selectedHistoryIndex: number = -1;
  private database: Kdbx | null = null;
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private entryId: string = '';
  private groupId: string = '';
  private onDatabaseUpdate: Callback<emitter.EventData> = (): void => {
    if (this.selectedHistoryIndex >= 0) {
      return;
    }
    this.loadEntry();
  };

  aboutToAppear() {
    // 获取从DatabaseShow页面传递的参数
    if (this.entryParam) {
      this.entryId = this.entryParam.entryId || '';
      this.groupId = this.entryParam.groupId || '';
      this.selectedHistoryIndex = this.entryParam.historyIndex === undefined ? -1 : this.entryParam.historyIndex;
    }
    // 加载数据库和条目
    this.loadEntry();
    // 监听数据库更新事件
    EventBus.on(EventBus.DATABASE_UPDATE, this.onDatabaseUpdate);
  }

  aboutToDisappear() {
    // 取消监听数据库更新事件
    EventBus.off(EventBus.DATABASE_UPDATE, this.onDatabaseUpdate);
  }

  onPageShow(): void {
    WindowUtils.onPageShow(this.getUIContext().getHostContext() as common.UIAbilityContext);
    // 刷新条目数据（从编辑页面返回时）
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
        CommonUtils.showToast({
          message: $r('app.string.invalid_db_or_entry'),
          duration: 2000
        });
        this.navPathStack.pop();
        return;
      }

      // 获取条目
      this.entry = KdbxUtils.getEntry(this.database, this.groupId, this.entryId, this.selectedHistoryIndex);

      if (!this.entry) {
        CommonUtils.showToast({
          message: $r('app.string.entry_not_found'),
          duration: 2000
        });
        this.navPathStack.pop();
        return;
      }

      // 解锁会话通知仅绑定含账号或密码的条目；无账号且无密码（含分组类条目）不更新通知；
      // 字段可用性标记决定通知按钮动态显示（仅账号→复制账号，仅密码→复制密码，都有→双按钮）
      const entryFields = this.entry?.fields;
      const hasUsername = !!KdbxUtils.getFieldValueString(entryFields, KdbxUtils.FIELD_USERNAME);
      const hasPassword = !!KdbxUtils.getFieldValueString(entryFields, KdbxUtils.FIELD_PASSWORD);
      if (hasUsername || hasPassword) {
        SessionManager.getInstance().setActiveEntry(this.groupId, this.entryId,
          KdbxUtils.getFieldValueString(entryFields, KdbxUtils.FIELD_TITLE) || '', hasUsername, hasPassword);
      }

      // 加载字段
      this.loadFields();

      // 加载历史记录
      this.loadHistory();

    } catch (error) {
      hilog.error(DOMAIN, TAG, '%{public}s', `Failed to load entry: ${error}`);
      CommonUtils.showToast({
        message: $r('app.string.load_entry_failed') + `: ${error}`,
        duration: 2000
      });
      this.navPathStack.pop();
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

    // 使用兼容层获取 TOTP URL 及已处理的字段名
    const totpResult: OtpExtractionResult = KdbxUtils.getTotpUrlWithProcessedFields(this.entry);
    const totpUrls: string[] = totpResult.urls;
    const processedFields: Set<string> = totpResult.processedFields;

    // 添加 TOTP 字段（通过兼容层解析，支持多种数据库格式）
    for (const totpUrl of totpUrls) {
      this.fields.push(new FieldView(KdbxUtils.FIELD_TOTP, totpUrl, false, true));
    }

    // 遍历条目的所有字段
    for (const field of this.entry.fields) {
      const key: string = field[0];
      // 跳过标题字段
      if (key === KdbxUtils.FIELD_TITLE) {
        continue;
      }
      // 跳过已被 TOTP 兼容层处理的字段
      if (processedFields.has(key)) {
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
      const commonFields =
        [KdbxUtils.FIELD_TITLE, KdbxUtils.FIELD_USERNAME, KdbxUtils.FIELD_PASSWORD, KdbxUtils.FIELD_TOTP, KdbxUtils.FIELD_URL, KdbxUtils.FIELD_NOTES, KdbxUtils.FIELD_TAGS,
          KdbxUtils.FIELD_OVERRIDE_URL];
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
    if (SettingsService.getSync(SettingsService.KEY_SECURITY_ITEM_SHOW_GROUP, SettingsService.KEY_SECURITY_ITEM_SHOW_GROUP_DEFAULT)) {
      this.fields = [new FieldView(KdbxUtils.GROUP_NAME, this.getGroupName(), false, false), ...this.fields];
    }

    // 展示附件
    this.addBinaries();

    // 过期时间（M2：附带剩余天数提示，已过期红 / 临期橙 / 远期次级色）
    if (this.entry.times.expires) {
      const expiryTime: Date | undefined = this.entry.times.expiryTime;
      const expiryField: FieldView = new FieldView(KdbxUtils.FIELD_EXPIRY_TIME,
        expiryTime ? DateUtils.format(expiryTime) : '', false, false);
      if (expiryTime) {
        const now: number = Date.now();
        const remainingDays: number = Math.ceil((expiryTime.getTime() - now) / DAY_MS);
        if (remainingDays < 0) {
          expiryField.warningText = ResourceManager.getString($r('app.string.expiry_report_expired_days'),
            Math.max(1, -remainingDays));
          expiryField.warningColor = $r('app.color.error');
        } else if (remainingDays === 0) {
          expiryField.warningText = ResourceManager.getString($r('app.string.expiry_report_expires_today'));
          expiryField.warningColor = $r('app.color.warn');
        } else {
          expiryField.warningText = ResourceManager.getString($r('app.string.expiry_report_expiring_days'),
            remainingDays);
          expiryField.warningColor = remainingDays <= SettingsService.getExpireRemindDays() ?
            $r('app.color.warn') : $r('app.color.text_secondary');
        }
      }
      this.fields.push(expiryField);
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
    // 磁盘引用（S4 附件磁盘化）：先用元信息占位，内容异步回读
    else if (binary instanceof KdbxBinaryDiskRef) {
      const fieldView = new FieldView(key, "", false, false, undefined, binary.byteLength);
      this.fields.push(fieldView);
      this.fillDiskRefBinary(fieldView, binary);
    }
    // hash 值
    else if (KdbxBinaries.isKdbxBinaryWithHash(binary)) {
      let binaryHash: KdbxBinaryWithHash = binary as KdbxBinaryWithHash;
      this.addBinary(key, binaryHash.value);
    }
  }

  /**
   * 异步回读磁盘引用附件内容并填充字段（FieldView 为 @Observed，赋值即刷新）
   */
  private fillDiskRefBinary(fieldView: FieldView, ref: KdbxBinaryDiskRef) {
    const database = FileService.getDatabase();
    if (!database) {
      return;
    }
    database.binaries.readDiskRef(ref).then((bytes: ArrayBuffer) => {
      fieldView.binaryFile = bytes;
      fieldView.fileSizeStr = StringUtils.formatFileSize(bytes.byteLength);
    }).catch((error: BusinessError) => {
      hilog.error(DOMAIN, TAG, 'read disk-ref attachment failed: %{public}s', `${error?.message ?? error}`);
      CommonUtils.showToast({ message: $r("app.string.invalid_binary_file"), duration: 2000 });
    });
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
    const params: EntryParam = {
      entryId: this.entryId,
      groupId: this.groupId
    };
    this.navPathStack.pushPathByName(PageConstants.PAGE_ENTRY_EDIT, params);
  }

  /**
   * 查看历史记录详情
   */
  private viewHistoryDetail(index: number) {
    const params: EntryParam = {
      entryId: this.entryId,
      groupId: this.groupId,
      historyIndex: index
    };
    this.navPathStack.pushPathByName(PageConstants.PAGE_ENTRY_VIEW, params);
  }

  /**
   * 获取分组名称
   */
  private getGroupName(): string {
    return KdbxUtils.getGroupPath(this.entry?.parentGroup, "/", false);
  }

  /**
   * 获取条目头部图标（过期条目沿用列表页约定显示过期图标）
   */
  private getEntryHeaderIcon(): ResourceStr {
    const entry = this.entry;
    if (entry && DateUtils.isExpired(entry.times.expires === true, entry.times.expiryTime)) {
      return $r('app.media.C45_Expired');
    }
    return KdbxUtils.getIcon(entry?.icon, entry?.customIcon, $r('app.media.ic_file'));
  }

  /**
   * 获取条目头部标题
   */
  private getEntryHeaderTitle(): string {
    const entry = this.entry;
    if (!entry) {
      return '';
    }
    return KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_TITLE);
  }

  /**
   * 获取条目头部用户名
   */
  private getEntryHeaderUsername(): string {
    const entry = this.entry;
    if (!entry) {
      return '';
    }
    return KdbxUtils.getFieldValueString(entry.fields, KdbxUtils.FIELD_USERNAME);
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
            KdbxUtils.cleanupOrphanedBinaries(this.database);
            this.selectedHistoryIndex = -1;
            KdbxSaveService.saveDatabaseFromUi(ToastSaveDatabaseCallback.wrap({
              onSuccess: () => {
                this.navPathStack.pop();
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
            KdbxSaveService.saveDatabaseFromUi(ToastSaveDatabaseCallback.wrap({
              onSuccess: () => {
                this.navPathStack.pop();
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

  /**
   * 构建条目头部（图标 + 标题 + 用户名，当前条目与历史版本共用）
   */
  @Builder
  EntryHeader() {
    Row() {
      // 条目图标（含品牌图标等自定义图标，过期沿用列表页约定）
      Image(this.getEntryHeaderIcon())
        .width(56)
        .height(56)
        .borderRadius(12)
        .objectFit(ImageFit.Contain)

      // 标题与用户名
      Column() {
        Text(this.getEntryHeaderTitle())
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.text_primary'))
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.getEntryHeaderUsername() !== '') {
          Text(this.getEntryHeaderUsername())
            .fontSize(14)
            .fontColor($r('app.color.text_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .backgroundColor($r("app.color.card_bg"))
    .borderRadius(8)
    .padding(12)
    .margin({ bottom: 8 })
  }

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          Image($r("app.media.ic_angle_left"))
            .width(28)
            .height(28)
            .margin({ left: 16 })
            .fillColor($r('app.color.text_primary'))
            .onClick(() => {
              this.navPathStack.pop();
            })

          Row() {
            if (this.selectedHistoryIndex >= 0) {
              Text($r('app.string.history_version', this.selectedHistoryIndex + 1))
                .fontSize(22)
                .fontWeight(FontWeight.Medium)
                .margin({ left: 16 })
                .fontColor($r('app.color.text_primary'))
            } else {
              Text(KdbxUtils.getFieldValueString(this.entry?.fields, KdbxUtils.FIELD_TITLE) || '')
                .fontSize(22)
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
                  .width(28)
                  .height(28)
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
        .height(48)

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
            ListItem() {
              this.EntryHeader()
            }

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
            bottom: 0
          })
          .layoutWeight(1)
          // 底部按钮为悬浮层，留出等高的内容偏移，保证最后一项能滚动到按钮上方
          .contentEndOffset(this.BOTTOM_BAR_HEIGHT)
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])

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
            .borderRadius(20)
            .backgroundColor($r("app.color.error"))
            .id('btn_rollback')
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
            .borderRadius(20)
            .backgroundColor(Color.Gray)
            .id('btn_delete_history')
            .onClick(() => {
              this.deleteHistory();
            })
          }
          .width('100%')
          .height(60)
          .backgroundColor(Color.Transparent)
          .padding({
            top: 8,
            bottom: 8,
            left: 16,
            right: 16
          })
          // 脱离文档流悬浮，上移量 = 自身高度 60 + 底部留白 16
          .position({ x: 0, y: '100%' })
          .translate({ y: -this.BOTTOM_BAR_HEIGHT })
        } else {
          // 显示当前条目
          Tabs() {
            TabContent() {
              List() {
                ListItem() {
                  this.EntryHeader()
                }

                ForEach(this.fields, (field: FieldView) => {
                  ListItem() {
                    EntryViewFieldItem({ field: field, entry: this.entry })
                  }
                })
                ListItem(){}
                .height(40)
              }
              .height('100%')
              .width('100%')
              .padding({
                left: 16,
                right: 16
              })
              .layoutWeight(1)
              .backgroundColor($r("app.color.bg_primary"))
              .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
                  ListItem(){}
                  .height(40)
                }
                .height('100%')
                .width('100%')
                .padding({
                  left: 16,
                  right: 16,
                })
                .layoutWeight(1)
                .backgroundColor($r("app.color.bg_primary"))
                .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
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
            .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
          }
          .width('100%')
          .height('100%')
          .barMode(BarMode.Fixed)
          .barWidth('100%')
          .barHeight(48) // Tab 标签页高度，确保文字完整显示
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
