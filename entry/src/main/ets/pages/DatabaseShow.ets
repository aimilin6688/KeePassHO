import { AddGroupDialog } from '../components/AddGroupDialog';
import ThemeManager from '../common/utils/ThemeManager';
import { Kdbx, KdbxEntry, KdbxGroup } from 'kdbxweb';
import { PromptAction, Router } from '@kit.ArkUI';
import { FileService } from '../services/FileService';
import { KdbxFileManager } from '../services/kdbx/KdbxFileManager';
import KdbxUtils from '../common/utils/KdbxUtils';
import { DatabaseShowParam } from '../services/TypeDefined';

@Entry
@Component
struct DatabaseShow {
  @State newGroupName: string | undefined = "";
  @State editingGroupIndex: number = -1;
  @State isLoading: boolean = true;
  @State titleName: string = '';
  @State groups: Array<KdbxGroup> = [];
  @State entries: Array<KdbxEntry> = [];
  @State showBack: boolean = false;
  private database: Kdbx | null = null;
  private router: Router = this.getUIContext().getRouter();
  private promptAction: PromptAction = this.getUIContext().getPromptAction();
  private currentGroup: KdbxGroup | undefined = undefined;
  dialogController: CustomDialogController = new CustomDialogController({
    builder: AddGroupDialog({
      newGroupName: this.newGroupName,
      editingGroupIndex: this.editingGroupIndex,
      onConfirm: (): void => this.handleAddGroup(),
      onCancel: (): void => {
        this.newGroupName = "";
        this.editingGroupIndex = -1;
      }
    }),
    alignment: DialogAlignment.Default,
    autoCancel: true
  })

  aboutToAppear() {
    // 获取从Password页面传递的参数
    const params = FileService.getInstance().getDbFileParam();
    this.titleName = params.fileName ?? '未知数据库';
    this.database = params.database ?? null;
    this.initData(this.router.getParams() as DatabaseShowParam);
    // 监听主题变化
    ThemeManager.getInstance().addThemeChangeListener(() => {
      this.onThemeChanged();
    });
  }

  private initData(dbShowParam: DatabaseShowParam | undefined) {
    if (!this.database) {
      this.promptAction.showToast({
        message: '无效的数据库',
        duration: 2000
      });
      this.router.back();
      return;
    }

    this.isLoading = true;
    try {
      if (dbShowParam && dbShowParam.groupId) {
        this.currentGroup = this.database.getGroup(dbShowParam.groupId);
        this.titleName = this.currentGroup?.name || '';
        this.showBack = true;
      } else {
        // 获取根分组下的所有子分组
        this.currentGroup = this.database.getDefaultGroup();
        this.showBack = false;
      }

      // 判断分组是否有效
      if (this.currentGroup === undefined) {
        this.promptAction.showToast({
          message: '无效的分组',
          duration: 2000
        });
        this.router.back();
        return;
      }
      this.groups = this.currentGroup.groups;
      this.entries = this.currentGroup.entries;
      console.info(`加载了 ${this.groups.length} 个分组, ${this.entries.length} 个条目`);
    } catch (error) {
      console.error(`处理数据库失败: ${error}`);
      this.promptAction.showToast({ message: `处理数据库失败: ${error}`, duration: 2000 });
      // 返回到密码输入页面
      setTimeout(() => {
        this.router.back();
      }, 2000);
    } finally {
      this.isLoading = false;
    }
  }

  @Builder
  SwipeActionButtons(index: number, item: KdbxGroup | KdbxEntry) {
    Row() {
      Button("编辑", { type: ButtonType.Normal })
        .width(80)
        .height(60)
        .backgroundColor($r('app.color.accent'))
        .fontColor(Color.White)
        .fontSize(14)
        .onClick(() => {
          if (item instanceof KdbxEntry) {
            // 跳转到 Item 编辑页面
          }
          if (item instanceof KdbxGroup) {
            this.editingGroupIndex = index
            this.newGroupName = this.groups[index].name;
            this.dialogController.open()
          }
        })

      Button("删除", { type: ButtonType.Normal })
        .width(80)
        .height(60)
        .backgroundColor($r('app.color.danger'))
        .fontColor(Color.White)
        .fontSize(14)
        .onClick(() => {
          AlertDialog.show({
            title: '确认删除',
            message: '确定要删除这个分组吗？',
            primaryButton: {
              value: '取消',
              action: () => {
              }
            },
            secondaryButton: {
              value: '删除',
              action: () => {
                if (this.database === null) {
                  return;
                }
                let deleteObj: KdbxGroup | KdbxEntry = null;
                if (item instanceof KdbxGroup) {
                  deleteObj = this.groups[index];
                  this.groups.splice(index, 1);
                }
                if (item instanceof KdbxEntry) {
                  deleteObj = this.entries[index];
                  this.entries.splice(index, 1);
                }
                this.database.remove(deleteObj);
                this.saveDatabase();
              }
            }
          })
        })
    }
  }

  /**
   * 保存数据库
   */
  private saveDatabase() {
    if (this.database) {
      const dbFileParam = FileService.getInstance().getDbFileParam();
      this.database.save().then(async savedDb => {
        const fileManager = new KdbxFileManager(dbFileParam.storageType);
        fileManager.saveKdbxFile(dbFileParam.filePath, savedDb).then(() => {
          this.promptAction.showToast({ message: `保存成功` });
        }).catch((error: Error) => {
          console.error(`保存数据库失败: ${error}`);
          this.promptAction.showToast({ message: `保存数据库失败: ${error.message}` });
        });
      }).catch((error: Error) => {
        console.error(`保存数据库失败: ${error}`);
        this.promptAction.showToast({ message: `保存数据库失败: ${error.message}` });
      });
    }
  }

  private handleAddGroup() {
    if (this.newGroupName === undefined || !this.newGroupName.trim()) {
      return;
    }
    if (!this.database) {
      this.promptAction.showToast({
        message: '无效的数据库信息'
      });
      return;
    }

    if (this.editingGroupIndex >= 0 && this.editingGroupIndex < this.groups.length) {
      // 编辑现有分组
      const group = this.groups[this.editingGroupIndex];
      group.name = this.newGroupName.trim();
      group.times.update();
    } else {
      // 添加新分组
      this.database.createGroup(this.currentGroup, this.newGroupName.trim());
    }
    // 保存数据库
    this.saveDatabase();
    this.updateUI();
    // 重置状态
    this.newGroupName = "";
    this.editingGroupIndex = -1;
  }

  aboutToDisappear() {
    // 移除主题变化监听
    ThemeManager.getInstance().removeThemeChangeListenerAll();
  }

  onThemeChanged() {
    // 强制组件刷新以应用新主题
    this.updateUI();
  }

  /**
   * 强制组件刷新
   */
  private updateUI(){
    // 强制刷新UI - 先清空数组，再重新加载
    this.groups = [];
    this.entries = [];
    // 延迟一帧后重新加载数据，确保UI更新
    setTimeout(() => {
      this.groups = [...this.currentGroup?.groups || []];
      this.entries = [...this.currentGroup?.entries || []];
    }, 10);
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

  build() {
    Stack() {
      Column() {
        // 顶部导航栏
        Row() {
          if (this.showBack) {
            Image($r('app.media.ic_back'))
              .width(24)
              .height(24)
              .margin({ left: 16 })
              .fillColor($r('app.color.text_primary'))
              .onClick(() => {
                this.router.back();
              })
          }
          Text(this.titleName)
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .margin({ left: 16 })
            .fontColor($r('app.color.text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Blank()
          Image($r('app.media.ic_settings'))
            .width(24)
            .height(24)
            .margin({ right: 16 })
            .onClick(() => {
              this.router.pushUrl({ url: 'pages/Settings' })
            })
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

            Text('正在加载数据库...')
              .fontSize(16)
              .margin({ top: 16 })
              .fontColor($r('app.color.text_primary'))
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
          .backgroundColor($r('app.color.background_primary'))
        } else {
          // 数据库内容
          List({ space: 8 }) {
            ForEach(this.groups, (itemGroup: KdbxGroup, index: number) => {
              ListItem() {
                Row() {
                  Image($r('app.media.ic_folder_open'))
                    .width(28)
                    .height(28)
                    .margin(10)
                  Column() {
                    Text(itemGroup.name)
                      .fontSize(18)
                      .textAlign(TextAlign.Start)
                      .flexGrow(1)
                    Text(`组群 ${this.groupItemCount(itemGroup)} 个条目`)
                      .fontSize(12)
                      .textAlign(TextAlign.Start)
                      .flexGrow(1)
                      .margin({ top: 4 })
                  }
                  .flexGrow(1)
                  .alignItems(HorizontalAlign.Start)

                  Image($r('app.media.ic_arrow_right'))
                    .width(20)
                    .height(20)
                    .margin({ right: 10 })
                    .fillColor($r('app.color.text_primary'))
                }
                .width('100%')
                .height(60)
                .borderRadius(8)
                .backgroundColor($r('app.color.card_background'))
                .padding({ left: 10, right: 10 })
                .onClick(() => {
                  this.router.pushUrl({ url: 'pages/DatabaseShow', params: { groupId: itemGroup.uuid.id } });
                })
              }
              .swipeAction({
                end: {
                  builder: this.SwipeActionButtons(index, itemGroup)
                }
              })
            }, (item: KdbxGroup, index: number) => `${index}-${item.uuid.id}`)

            ForEach(this.entries, (itemEntry: KdbxEntry, index: number) => {
              ListItem() {
                Row() {
                  Image($r('app.media.ic_file'))
                    .width(28)
                    .height(28)
                    .margin(10)
                  Column() {
                    Text(KdbxUtils.getFieldValueString(itemEntry.fields, "Title"))
                      .fontSize(18)
                      .textAlign(TextAlign.Start)
                      .flexGrow(1)
                    Text(KdbxUtils.getFieldValueString(itemEntry.fields, "UserName"))
                      .fontSize(12)
                      .textAlign(TextAlign.Start)
                      .flexGrow(1)
                  }
                  .flexGrow(1)
                  .alignItems(HorizontalAlign.Start)

                  Image($r('app.media.ic_arrow_right'))
                    .width(20)
                    .height(20)
                    .margin({ right: 10 })
                    .fillColor($r('app.color.text_primary'))
                }
                .width('100%')
                .height(60)
                .borderRadius(8)
                .backgroundColor($r('app.color.card_background'))
                .padding({ left: 10, right: 10 })
              }
              .swipeAction({
                end: {
                  builder: this.SwipeActionButtons(index, itemEntry)
                }
              })
            }, (item: KdbxEntry, index: number) => `${index}-${item.uuid.id}`)
          }
          .width('100%')
          .height('100%')
          .backgroundColor($r('app.color.background_primary'))
          .padding({ left: 12, right: 12, top: 12 })
          .scrollBar(BarState.Auto)
        }
      }
      .width('100%')
      .margin({ bottom: 80 })

      Button() {
        Image($r('app.media.ic_add'))
          .width(24)
          .height(24)
          .fillColor(Color.White)
      }
      .width(60)
      .height(60)
      .borderRadius(30)
      .backgroundColor($r('app.color.accent'))
      .position({ right: 12, bottom: 12 })
      .enabled(!this.isLoading)
      .opacity(this.isLoading ? 0.5 : 1)
      .onClick(() => {
        this.editingGroupIndex = -1
        this.newGroupName = ""
        this.dialogController.open()
      })
    }
    .width('100%')
    .height('100%')
  }
}
